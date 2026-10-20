import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/completion_time.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_list.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/milestone.dart';
import 'package:checkpoint/models/milestone_progress.dart';
import 'package:checkpoint/models/user_profile.dart';

import 'support/fakes.dart';

void main() {
  group('the catalog', () {
    test('has one milestone per id', () {
      final ids = [for (final m in milestones) m.id];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('unlocks every frame exactly once, and each title once', () {
      for (final frame in AvatarFrame.values) {
        expect(
          milestones.where((m) => m.frame == frame),
          hasLength(1),
          reason: frame.id,
        );
      }
      final titles = [for (final m in milestones) ?m.rewardTitle];
      expect(titles.toSet(), hasLength(titles.length));
    });

    test('counts something for every metric', () {
      for (final metric in MilestoneMetric.values) {
        expect(
          milestones.any((m) => m.metric == metric),
          isTrue,
          reason: metric.wire,
        );
      }
    });

    test('matches the rows the migration seeds', () {
      final sql = File('supabase/migrations/20261020120100_milestones.sql')
          .readAsStringSync();
      final row = RegExp(
        r"\('([a-z0-9_]+)', '([a-z_]+)', (\d+), (null|'[a-z]+'), (null|'[^']+')\)",
      );
      final seeded = {
        for (final match in row.allMatches(sql))
          match.group(1)!: (
            metric: match.group(2)!,
            threshold: int.parse(match.group(3)!),
            frame: _unquote(match.group(4)!),
            title: _unquote(match.group(5)!),
          ),
      };

      expect(seeded.keys.toSet(), {for (final m in milestones) m.id});
      for (final m in milestones) {
        expect(seeded[m.id], (
          metric: m.metric.wire,
          threshold: m.threshold,
          frame: m.frame?.id,
          title: m.rewardTitle,
        ), reason: m.id);
      }
    });
  });

  group('levels', () {
    test('start at 0, 50, 150 and 300 points', () {
      expect(MilestoneLevel.of(0).level, 1);
      expect(MilestoneLevel.of(49).level, 1);
      expect(MilestoneLevel.of(50).level, 2);
      expect(MilestoneLevel.of(149).level, 2);
      expect(MilestoneLevel.of(150).level, 3);
      expect(MilestoneLevel.of(300).level, 4);
    });

    test('say how far into the level', () {
      final level = MilestoneLevel.of(100);
      expect(level.levelStart, 50);
      expect(level.nextLevelAt, 150);
      expect(level.progress, 0.5);
    });
  });

  group('earned milestones', () {
    final jan = DateTime.utc(2026, 1, 5);
    final mar = DateTime.utc(2026, 3, 5);

    test('list the newest first and add up their points', () {
      final earned = EarnedMilestones({'library_1': jan, 'library_10': mar});
      expect([for (final m in earned.list) m.id], ['library_10', 'library_1']);
      expect(earned.points, 20);
      expect(earned.level.level, 1);
    });

    test('keep milestones this build does not know without counting them', () {
      final earned = EarnedMilestones({
        'library_1': jan,
        'from_the_future': mar,
      });
      expect(earned.count, 1);
      expect(
        EarnedMilestones.fromJson(earned.toJson()).has('from_the_future'),
        isTrue,
      );
    });

    test('keep the earlier date when the same one comes twice', () {
      final earned = EarnedMilestones({'library_1': mar})
          .plus({'library_1': jan});
      expect(earned.unlockedAt['library_1'], jan);
    });

    test('unlock the frames and titles of what they hold', () {
      final earned = EarnedMilestones({'library_100': jan, 'two_factor': jan});
      expect(earned.frames, [AvatarFrame.gold, AvatarFrame.shield]);
      expect([for (final m in earned.titles) m.rewardTitle], ['Collector']);
    });

    test('come back from the device as they were saved', () {
      final earned = EarnedMilestones({'library_1': jan, 'sessions_1': mar});
      final back = EarnedMilestones.fromJson(earned.toJson());
      expect(back.unlockedAt.keys, earned.unlockedAt.keys);
      expect(back.unlockedAt['sessions_1']!.isAtSameMomentAs(mar), isTrue);
    });
  });

  group('flair', () {
    test('comes back from the device as it was saved', () {
      const flair = ProfileFlair(
        frameId: 'gold',
        titleId: 'library_100',
        showcaseIds: ['library_100', 'two_factor'],
      );
      expect(profileFlairFromJson(profileFlairToJson(flair)), flair);
      expect(profileFlairFromJson(null), ProfileFlair.none);
    });

    test('knows its frame, title and showcase', () {
      const flair = ProfileFlair(
        frameId: 'gold',
        titleId: 'library_100',
        showcaseIds: ['two_factor', 'unknown'],
      );
      expect(flair.frame, AvatarFrame.gold);
      expect(flair.title, 'Collector');
      expect([for (final m in flair.showcase) m.id], ['two_factor']);
    });
  });

  group('progress', () {
    LogEntry session(String id, DateTime at, {bool steam = false}) => LogEntry(
      id: id,
      gameId: 'a',
      timestamp: at,
      hours: 1,
      platform: GamePlatform.pc,
      fromSteam: steam,
    );

    test('counts the library, playtime and completions', () {
      final progress = MilestoneProgress.of(
        library: [
          testGame('a', hours: 120, status: GameStatus.completed),
          testGame('b', hours: 5, status: GameStatus.wishlist),
          testGame('c', hours: 0, status: GameStatus.dropped),
        ],
        sessions: const [],
      );
      expect(progress.valueOf(MilestoneMetric.libraryGames), 3);
      expect(progress.valueOf(MilestoneMetric.hours), 125);
      expect(progress.valueOf(MilestoneMetric.gameHours), 120);
      expect(progress.valueOf(MilestoneMetric.completed), 1);
      expect(progress.valueOf(MilestoneMetric.wishlist), 1);
      expect(progress.valueOf(MilestoneMetric.dropped), 1);
      expect(progress.reached(milestoneById('game_hours_100')!), isTrue);
      expect(
        progress.fractionOf(milestoneById('library_10')!),
        closeTo(0.3, 1e-9),
      );
    });

    test('counts only the sessions the member logged', () {
      final progress = MilestoneProgress.of(
        library: const [],
        sessions: [
          session('1', DateTime(2026, 5, 1, 12)),
          session('2', DateTime(2026, 5, 2, 12), steam: true),
        ],
      );
      expect(progress.valueOf(MilestoneMetric.sessions), 1);
    });

    test('finds the longest run of days and late-night sessions', () {
      final sessions = [
        session('1', DateTime(2026, 5, 1, 23)),
        session('2', DateTime(2026, 5, 2, 9)),
        session('3', DateTime(2026, 5, 2, 21)),
        session('4', DateTime(2026, 5, 3, 2)),
        session('5', DateTime(2026, 5, 7, 12)),
      ];
      final progress = MilestoneProgress.of(
        library: const [],
        sessions: sessions,
      );
      expect(progress.valueOf(MilestoneMetric.streakDays), 3);
      expect(progress.valueOf(MilestoneMetric.nightSessions), 1);
    });

    test('counts genres, decades and old games among those played', () {
      final progress = MilestoneProgress.of(
        library: [
          testGame('a', year: 1991, genres: const ['Platform']),
          testGame('b', year: 2005, genres: const ['RPG', 'Shooter']),
          testGame(
            'c',
            year: 2024,
            genres: const ['Puzzle'],
            status: GameStatus.toPlay,
            hours: 0,
          ),
        ],
        sessions: const [],
      );
      expect(progress.valueOf(MilestoneMetric.genres), 3);
      expect(progress.valueOf(MilestoneMetric.decades), 2);
      expect(progress.valueOf(MilestoneMetric.retroGames), 1);
    });

    test('counts reviews, ratings and completion times', () {
      final progress = MilestoneProgress.of(
        library: [
          testGame('a').copyWith(review: 'Great'),
          testGame('b')
              .copyWith(rating: 0)
              .withCompletionTime(
                const CompletionTime(CompletionCategory.mainStory, 600),
              ),
        ],
        sessions: const [],
      );
      expect(progress.valueOf(MilestoneMetric.reviews), 1);
      expect(progress.valueOf(MilestoneMetric.rated), 1);
      expect(progress.valueOf(MilestoneMetric.completionTimes), 1);
    });

    test('leaves out what the device does not know', () {
      final progress = MilestoneProgress.of(
        library: const [],
        sessions: const [],
      );
      expect(progress.valueOf(MilestoneMetric.lists), isNull);
      expect(progress.valueOf(MilestoneMetric.followers), isNull);
      expect(progress.valueOf(MilestoneMetric.perfectGames), isNull);
      expect(progress.fractionOf(milestoneById('lists_1')!), isNull);
      expect(progress.reached(milestoneById('lists_1')!), isFalse);
    });

    test('counts lists once they are known', () {
      final progress = MilestoneProgress.of(
        library: const [],
        sessions: const [],
        lists: [
          GameList(
            id: 'l1',
            ownerId: 'u1',
            title: 'Cozy',
            isPublic: true,
            games: [testGame('a')],
          ),
          const GameList(id: 'l2', ownerId: 'u1', title: 'Later'),
        ],
      );
      expect(progress.valueOf(MilestoneMetric.lists), 2);
      expect(progress.valueOf(MilestoneMetric.publicLists), 1);
      expect(progress.valueOf(MilestoneMetric.listSize), 1);
    });

    test('counts whole months as a member, and founding members', () {
      final profile = UserProfile(
        name: 'Ada',
        handle: '@ada',
        avatarUrl: 'https://example.com/a.png',
        bio: 'Hi',
        joined: DateTime.utc(2026, 1, 31),
      );
      MilestoneProgress at(DateTime now) => MilestoneProgress.of(
        library: const [],
        sessions: const [],
        profile: profile,
        now: now,
      );

      expect(
        at(DateTime.utc(2026, 2, 27)).valueOf(MilestoneMetric.memberMonths),
        0,
      );
      // A month after the 31st of January is the end of February.
      expect(
        at(DateTime.utc(2026, 2, 28, 1)).valueOf(MilestoneMetric.memberMonths),
        1,
      );
      expect(
        at(DateTime.utc(2027, 1, 31)).valueOf(MilestoneMetric.memberMonths),
        12,
      );
      expect(
        at(DateTime.utc(2027, 1, 31)).valueOf(MilestoneMetric.foundingMember),
        1,
      );
      expect(
        at(DateTime.utc(2027, 1, 31)).valueOf(MilestoneMetric.profileComplete),
        1,
      );
    });
  });
}

String? _unquote(String value) =>
    value == 'null' ? null : value.substring(1, value.length - 1);
