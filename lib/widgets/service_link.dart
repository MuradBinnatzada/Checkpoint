import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/connected_service.dart';

/// Where tapping a connected account leads: a page to open, or text to copy for
/// Discord, which has no public profile address.
class ServiceLink {
  const ServiceLink({required this.tooltip, this.url, this.copyText});

  final String tooltip;
  final Uri? url;
  final String? copyText;
}

/// The link for [service] once its [name] is known, or null when there is
/// nothing to open: no name, a name that is not one the service allows (it came
/// from another member's app), or Nintendo.
ServiceLink? serviceLink(ConnectedService service, String? name) {
  final id = name?.trim();
  if (id == null || id.isEmpty) return null;
  switch (service) {
    case ConnectedService.steam:
      return ServiceLink(
        tooltip: L10n.current.openServiceProfile('Steam'),
        url: Uri.https('steamcommunity.com', '/profiles/$id'),
      );
    case ConnectedService.xbox:
      return ServiceLink(
        tooltip: L10n.current.openServiceProfile('Xbox'),
        url: Uri.https('xboxgamertag.com', '/search/$id'),
      );
    case ConnectedService.psn:
      return ServiceLink(
        tooltip: L10n.current.openServiceProfile('PSN'),
        url: Uri.https('psnprofiles.com', '/$id'),
      );
    case ConnectedService.discord:
      return ServiceLink(tooltip: L10n.current.copyServiceUsername('Discord'), copyText: id);
    case ConnectedService.instagram:
      if (cleanAccountName(service, id) != id) return null;
      return ServiceLink(
        tooltip: L10n.current.openServiceProfile('Instagram'),
        url: Uri.https('www.instagram.com', '/$id'),
      );
    case ConnectedService.twitch:
      if (cleanAccountName(service, id) != id) return null;
      return ServiceLink(
        tooltip: L10n.current.openTwitchChannel,
        url: Uri.https('www.twitch.tv', '/$id'),
      );
    case ConnectedService.nintendo:
      return null;
  }
}

/// Follows [link]: opens its page outside the app, or copies its text and says so.
Future<void> openServiceLink(
  BuildContext context,
  ConnectedService service,
  ServiceLink link,
) async {
  final copy = link.copyText;
  if (copy != null) {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.serviceUsernameCopied(service.label);
    await Clipboard.setData(ClipboardData(text: copy));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(copied),
        ),
      );
    return;
  }
  final url = link.url;
  if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
}
