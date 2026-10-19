import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/app/new_password_screen.dart';
import 'package:checkpoint/services/connection_failure.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_link_rows.dart';

/// How the account signs in, a way to change the password of an email account,
/// and a way to end the sessions left on other devices.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key});

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  static final _googleSecurity = Uri.https('myaccount.google.com', '/security');

  bool _signingOut = false;

  static String _methodLabel(String? provider) => switch (provider) {
    'google' => 'Google',
    'email' => 'Email and password',
    null => 'Unknown',
    final other => other[0].toUpperCase() + other.substring(1),
  };

  Future<void> _signOutOthers() async {
    final auth = context.read<AuthStore>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingOut = true);
    String message;
    try {
      await auth.signOutOtherDevices();
      message = 'Signed out of your other devices';
    } catch (e) {
      debugPrint('Signing out other devices failed: $e');
      message = e is SessionPending || isConnectionFailure(e)
          ? 'Could not reach the server. Check your connection and try again.'
          : auth.messageFor(e);
    }
    if (mounted) setState(() => _signingOut = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final provider = auth.provider;
    final email = auth.email;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Panel(
          title: 'Sign-in',
          child: Column(
            children: [
              _InfoRow(label: 'Method', value: _methodLabel(provider)),
              if (email != null) _InfoRow(label: 'Email', value: email),
            ],
          ),
        ),
        if (provider == 'email') ...[
          const SizedBox(height: 14),
          ProfileLinkRows(
            links: [
              ProfileLink(
                icon: Icons.password_rounded,
                label: 'Change password',
                onTap: () => changePassword(context),
              ),
            ],
          ),
        ],
        if (provider == 'google') ...[
          const SizedBox(height: 14),
          ProfileLinkRows(
            links: [
              ProfileLink(
                icon: Icons.manage_accounts_rounded,
                label: 'Manage your Google Account',
                onTap: () => launchUrl(
                  _googleSecurity,
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'You sign in with Google, so your password and two-step verification '
              'are managed in your Google Account.',
              style: TextStyle(
                color: Palette.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Panel(
          title: 'Sessions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Signed in on a device you no longer use? This ends the sessions on '
                'every other device. This one stays signed in.',
                style: TextStyle(color: Palette.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _signingOut ? null : _signOutOthers,
                icon: _signingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.devices_other_rounded, size: 18),
                label: const Text('Sign out other devices'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
