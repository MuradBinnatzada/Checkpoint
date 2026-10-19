import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/services/steam_link_service.dart';
import 'package:checkpoint/services/sync_failure.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/profile_store.dart';

import 'support/fakes.dart';

/// Connecting Steam: the member signs in through Steam and the server saves the
/// Steam ID Steam confirms. The app never writes one itself.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late FakeSteamLink steam;
  late ProfileStore profile;

  ProfileStore newProfile({String? steamLinkResult}) => ProfileStore(
    repository: repo,
    auth: auth,
    cache: LocalCache(),
    steamLink: steam,
    steamLinkResult: steamLinkResult,
    steamLinkPoll: const Duration(milliseconds: 1),
    steamLinkWait: const Duration(milliseconds: 20),
  );

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    steam = FakeSteamLink(repo);
    profile = newProfile();
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    profile.dispose();
    auth.dispose();
  });

  group('connectSteam', () {
    test('connects the account Steam confirmed, without writing it from the app', () async {
      await profile.initialize();
      expect(profile.steamConnected, isFalse);

      final message = await profile.connectSteam();

      expect(message, 'Steam connected.');
      expect(profile.steamConnected, isTrue);
      expect(profile.steamId, '76561198000000000');
      expect(steam.opened.single.host, 'steamcommunity.com');
      expect(repo.writes.where((w) => w.startsWith('steam:')), isEmpty);
      expect(profile.linkingSteam, isFalse);
    });

    test('says what the server reported when the sign-in did not work', () async {
      await profile.initialize();
      steam
        ..signsIn = false
        ..outcome = const SteamLinkReturned('STEAM_LINK_CANCELLED');

      expect(
        await profile.connectSteam(),
        SyncFailureCode.steamLinkCancelled.message,
      );
      expect(profile.steamConnected, isFalse);

      steam.outcome = const SteamLinkReturned('SOMETHING_NEW');
      expect(
        await profile.connectSteam(),
        'Could not connect Steam. Please try again.',
      );
    });

    test('a return that says ok while the profile has no Steam ID is not believed', () async {
      await profile.initialize();
      steam.signsIn = false; // e.g. another program on this computer called the listener

      final message = await profile.connectSteam();

      expect(message, startsWith("Steam isn't connected yet."));
      expect(profile.steamConnected, isFalse);
    });

    test('on a phone, waits for the Steam ID to reach the profile, then closes the tab', () async {
      await profile.initialize();
      steam
        ..signsIn = false
        ..outcome = const SteamLinkOpened();

      final linking = profile.connectSteam();
      await pumpEventQueue();
      expect(profile.linkingSteam, isTrue);
      expect(profile.steamConnected, isFalse);

      // The member signs in on Steam's page; the server saves the ID.
      repo.steamId = '76561198000000001';
      expect(await linking, 'Steam connected.');
      expect(profile.steamId, '76561198000000001');
      expect(steam.browserCloses, 1);
      expect(profile.linkingSteam, isFalse);
    });

    test('on a phone, stops waiting after a while and says so', () async {
      await profile.initialize();
      steam
        ..signsIn = false
        ..outcome = const SteamLinkOpened();

      final message = await profile.connectSteam();

      expect(message, startsWith("Steam isn't connected yet."));
      expect(profile.linkingSteam, isFalse);
      expect(steam.browserCloses, 0);
    });

    test('Cancel stops waiting and says nothing', () async {
      await profile.initialize();
      steam.gate = Completer<void>();

      final linking = profile.connectSteam();
      await pumpEventQueue();
      expect(profile.linkingSteam, isTrue);

      profile.cancelSteamLink();
      expect(profile.linkingSteam, isFalse);
      expect(steam.cancels, 1);

      steam.gate!.complete();
      expect(await linking, isNull);
    });

    test('a refused start says why, with the wait the server asked for', () async {
      await profile.initialize();
      repo.steamLinkError = FunctionException(
        status: 429,
        details: {'error': 'Too many', 'code': 'RATE_LIMITED', 'retry_after': 1200},
      );

      expect(
        await profile.connectSteam(),
        'Too many requests from your account. Try again in 20 minutes.',
      );
      expect(steam.opened, isEmpty);
      expect(profile.linkingSteam, isFalse);
    });

    test('an unexpected failure gets a plain message', () async {
      await profile.initialize();
      repo.steamLinkError = const FormatException('steam-link answered nonsense');

      expect(
        await profile.connectSteam(),
        'Could not connect Steam. Please try again.',
      );
    });

    test("a platform that can't open the sign-in says so", () async {
      await profile.initialize();
      steam.openError = const SteamLinkException(SteamLinkFlow.unsupportedMessage);

      expect(await profile.connectSteam(), SteamLinkFlow.unsupportedMessage);
      expect(profile.steamConnected, isFalse);
    });

    test('the web app leaving for Steam says nothing yet', () async {
      await profile.initialize();
      steam
        ..signsIn = false
        ..outcome = const SteamLinkLeftApp();

      expect(await profile.connectSteam(), isNull);
    });

    test('needs someone signed in', () async {
      await profile.initialize();
      await authService.signOut();
      await pumpEventQueue();

      expect(
        await profile.connectSteam(),
        'Sign in to connect your Steam account.',
      );
      expect(steam.opened, isEmpty);
    });

    test('disconnecting is still the app\'s to do', () async {
      repo.steamId = '76561198000000000';
      await profile.initialize();

      expect(await profile.disconnectSteam(), isNull);
      expect(profile.steamConnected, isFalse);
      expect(repo.writes, contains('steam:'));
    });
  });

  group('the web app back from Steam', () {
    test('tells how it went once the member is known, and only once', () async {
      profile.dispose();
      repo.steamId = '76561198000000000';
      profile = newProfile(steamLinkResult: 'ok');

      await profile.initialize();
      expect(profile.notice, 'Steam connected.');
      profile.clearNotice();

      await profile.refresh();
      expect(profile.notice, isNull);
    });

    test('reports a failed sign-in', () async {
      profile.dispose();
      profile = newProfile(steamLinkResult: 'STEAM_LINK_EXPIRED');

      await profile.initialize();
      expect(profile.notice, SyncFailureCode.steamLinkExpired.message);
    });
  });

  group('addresses', () {
    test('Steam brings the web app back to itself, without its query or fragment', () {
      expect(
        webReturnUrl(Uri.parse('https://checkpoint.example/app/?x=1#/game/12')),
        Uri.parse('https://checkpoint.example/app/'),
      );
      expect(
        webReturnUrl(Uri.parse('http://localhost:3000/#/')),
        Uri.parse('http://localhost:3000/'),
      );
    });

    test('the result is taken off the address, the rest kept', () {
      expect(
        withoutSteamLinkResult(
          Uri.parse('https://checkpoint.example/?steam_link=ok#/u/abc'),
        ).toString(),
        'https://checkpoint.example/#/u/abc',
      );
      expect(
        withoutSteamLinkResult(
          Uri.parse('http://localhost:3000/app/?a=1&steam_link=STEAM_LINK_INVALID'),
        ).toString(),
        'http://localhost:3000/app/?a=1',
      );
    });

    test('the new codes are known to the app', () {
      for (final wire in ['STEAM_LINK_CANCELLED', 'STEAM_LINK_EXPIRED', 'STEAM_LINK_INVALID']) {
        final code = SyncFailureCode.fromWire(wire);
        expect(code, isNotNull, reason: wire);
        expect(code!.delayed, isFalse, reason: wire);
      }
    });
  });
}
