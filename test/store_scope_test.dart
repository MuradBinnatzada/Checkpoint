import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/search_store.dart';
import 'package:checkpoint/state/store_scope.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('a store notifying rebuilds only the widgets that watch it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stores = AppStores(
      repository: FakeRepository(),
      authService: FakeAuthService(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });

    var searchBuilds = 0;
    var libraryBuilds = 0;
    var viewBuilds = 0;
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: Column(
          textDirection: TextDirection.ltr,
          children: [
            Builder(builder: (context) {
              context.watch<SearchStore>();
              searchBuilds++;
              return const SizedBox();
            }),
            Builder(builder: (context) {
              context.watch<LibraryStore>();
              libraryBuilds++;
              return const SizedBox();
            }),
            Builder(builder: (context) {
              context.watch<LibraryViewStore>();
              viewBuilds++;
              return const SizedBox();
            }),
          ],
        ),
      ),
    );
    expect((searchBuilds, libraryBuilds, viewBuilds), (1, 1, 1));

    stores.libraryView.setSort(SortField.rating);
    await tester.pump();
    expect((searchBuilds, libraryBuilds, viewBuilds), (1, 1, 2));

    await tester.runAsync(() => stores.search.addRecentSearch('zelda'));
    await tester.pump();
    expect((searchBuilds, libraryBuilds, viewBuilds), (2, 1, 2));
  });

  testWidgets('read gives the store without subscribing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stores = AppStores(
      repository: FakeRepository(),
      authService: FakeAuthService(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });

    var builds = 0;
    late LibraryViewStore read;
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: Builder(builder: (context) {
          read = context.read<LibraryViewStore>();
          builds++;
          return const SizedBox();
        }),
      ),
    );

    stores.libraryView.setSort(SortField.rating);
    await tester.pump();

    expect(read, same(stores.libraryView));
    expect(builds, 1);
  });
}
