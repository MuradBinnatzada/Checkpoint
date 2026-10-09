import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';

void main() {
  test('library state labels stay stable', () {
    expect(GameStatus.playing.label, 'Playing');
    expect(SortField.dateAdded.label, 'Date Added');
  });
}
