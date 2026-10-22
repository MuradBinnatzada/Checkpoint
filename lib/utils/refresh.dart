import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';

/// What pulling down on a screen of the member's own data waits for: the library
/// with its sessions (and the Home carousels), and the profile with its follows.
/// Signed out there is only the library's carousels to read again. Neither
/// store throws: a server that can't be reached leaves the copy on screen and
/// says so in the Library tab's banner.
Future<void> refreshMyData(BuildContext context) {
  final library = context.read<LibraryStore>();
  final profile = context.read<ProfileStore>();
  final signedIn = context.read<AuthStore>().isLoggedIn;
  return Future.wait([library.refresh(), if (signedIn) profile.refresh()]);
}
