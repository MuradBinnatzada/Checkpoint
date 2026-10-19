import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/models/share_link.dart';

/// Copies the link to [target] and says so. [before] runs first, when given
/// (it puts a game in the catalog, so the link finds it); a failure there
/// doesn't stop the copy.
Future<void> copyShareLink(
  BuildContext context,
  LinkTarget target, {
  Future<void> Function()? before,
}) async {
  final url = shareUrl(target);
  if (url == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await before?.call();
  } catch (e) {
    debugPrint('Preparing the shared link failed: $e');
  }
  await Clipboard.setData(ClipboardData(text: url));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Link copied')));
}

/// Whether this build can make links (it knows the web app's address).
bool get canShareLinks => webAppUrl() != null;

/// "Copy link" in an app bar. Nothing when this build can't make links.
class ShareLinkButton extends StatelessWidget {
  const ShareLinkButton({super.key, required this.target, this.before});
  final LinkTarget target;
  final Future<void> Function()? before;

  @override
  Widget build(BuildContext context) {
    if (!canShareLinks) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Copy link',
      onPressed: () => copyShareLink(context, target, before: before),
      icon: const Icon(Icons.share_rounded),
    );
  }
}
