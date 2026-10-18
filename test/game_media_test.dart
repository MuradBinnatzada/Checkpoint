import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game_media.dart';

void main() {
  test('reads the media answer, dropping images without a usable id', () {
    final media = GameMedia.fromJson({
      'artworks': [
        {'image_id': 'ar5l8', 'width': 1920, 'height': 1080},
        {'image_id': '../x'},
        'junk',
      ],
      'screenshots': [
        {'image_id': 'sc6lx9', 'width': 0},
      ],
    })!;

    expect(media.artworks.single.imageId, 'ar5l8');
    expect(media.artworks.single.width, 1920);
    expect(media.screenshots.single.imageId, 'sc6lx9');
    expect(media.screenshots.single.width, isNull);
    expect(media.isEmpty, isFalse);
  });

  test(
    'an error answer is not media; an answer with no art is empty media',
    () {
      expect(
        GameMedia.fromJson({'error': 'No such game', 'code': 'NOT_FOUND'}),
        isNull,
      );
      expect(GameMedia.fromJson('nope'), isNull);
      expect(
        GameMedia.fromJson({'artworks': [], 'screenshots': []})!.isEmpty,
        isTrue,
      );
    },
  );

  test(
    'builds IGDB URLs the database accepts, and recognises them in any size',
    () {
      const image = GameMediaImage(imageId: 'ar5l8');
      final allowed = RegExp(
        r'^https://images\.igdb\.com/igdb/image/upload/t_[a-z0-9_]{1,24}/[A-Za-z0-9]{1,32}\.(jpg|png|webp)$',
      ); // user_games_custom_backdrop_igdb

      expect(
        image.backdropUrl,
        'https://images.igdb.com/igdb/image/upload/t_1080p/ar5l8.jpg',
      );
      expect(allowed.hasMatch(image.backdropUrl), isTrue);
      expect(allowed.hasMatch(image.thumbnailUrl), isTrue);
      expect(image.isShownBy(image.backdropUrl), isTrue);
      expect(image.isShownBy(image.thumbnailUrl), isTrue);
      expect(
        image.isShownBy(
          'https://images.igdb.com/igdb/image/upload/t_1080p/xar5l8.jpg',
        ),
        isFalse,
      );
      expect(image.isShownBy(null), isFalse);
    },
  );
}
