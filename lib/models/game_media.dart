import 'package:flutter/foundation.dart';

/// Image sizes IGDB serves (`t_<size>` in an image URL).
abstract final class IgdbImageSize {
  /// 569 x 320: a thumbnail, for the picker.
  static const screenshotMed = 'screenshot_med';

  /// 1920 x 1080: a full-width backdrop.
  static const hd1080 = '1080p';
}

/// The URL of IGDB image [imageId] in [size] (see [IgdbImageSize]). The database
/// only accepts a chosen backdrop in this form (`user_games_custom_backdrop_igdb`).
String igdbImageUrl(String imageId, String size) =>
    'https://images.igdb.com/igdb/image/upload/t_$size/$imageId.jpg';

final _imageIdPattern = RegExp(r'^[A-Za-z0-9]{1,32}$');

/// One picture of a game on IGDB: an artwork or a screenshot.
@immutable
class GameMediaImage {
  const GameMediaImage({required this.imageId, this.width, this.height});

  final String imageId;
  final int? width;
  final int? height;

  /// The image as a full-width backdrop.
  String get backdropUrl => igdbImageUrl(imageId, IgdbImageSize.hd1080);

  /// A small copy, for the picker.
  String get thumbnailUrl => igdbImageUrl(imageId, IgdbImageSize.screenshotMed);

  /// Whether [url] (a [backdropUrl]) is this image, whatever its size.
  bool isShownBy(String? url) => url != null && url.endsWith('/$imageId.jpg');

  /// One entry of the `media` answer of `igdb-handler`, or null when it has no
  /// usable image id.
  static GameMediaImage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['image_id'];
    if (id is! String || !_imageIdPattern.hasMatch(id)) return null;
    int? dimension(Object? v) => v is num && v > 0 ? v.toInt() : null;
    return GameMediaImage(
      imageId: id,
      width: dimension(json['width']),
      height: dimension(json['height']),
    );
  }
}

/// The art a member can pick a game's backdrop from: its artworks and
/// screenshots on IGDB (`media` mode of `igdb-handler`).
@immutable
class GameMedia {
  const GameMedia({this.artworks = const [], this.screenshots = const []});

  final List<GameMediaImage> artworks;
  final List<GameMediaImage> screenshots;

  bool get isEmpty => artworks.isEmpty && screenshots.isEmpty;

  /// The `media` answer, or null when it is not one (an `{ "error": ... }`, say).
  static GameMedia? fromJson(Object? json) {
    if (json is! Map) return null;
    if (!json.containsKey('artworks') && !json.containsKey('screenshots')) {
      return null;
    }
    List<GameMediaImage> list(Object? raw) => [
      if (raw is List)
        for (final entry in raw) ?GameMediaImage.fromJson(entry),
    ];
    return GameMedia(
      artworks: list(json['artworks']),
      screenshots: list(json['screenshots']),
    );
  }
}
