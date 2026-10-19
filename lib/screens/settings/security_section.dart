import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/app/new_password_screen.dart';
import 'package:checkpoint/screens/settings/two_factor_setup_screen.dart';
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
              'You sign in with Google, so your password and Google\'s 2-Step '
              'Verification are managed in your Google Account. Two-factor '
              'authentication below adds a Checkpoint code on top.',
              style: TextStyle(
                color: Palette.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Panel(
          title: 'Two-factor authentication',
          child: _TwoFactorSwitch(),
        ),
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

/// Two-factor authentication on or off. On opens the setup (an authenticator
/// app and its first code); off asks first.
class _TwoFactorSwitch extends StatefulWidget {
  const _TwoFactorSwitch();

  @override
  State<_TwoFactorSwitch> createState() => _TwoFactorSwitchState();
}

class _TwoFactorSwitchState extends State<_TwoFactorSwitch> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    if (on) {
      await setUpTwoFactor(context);
    } else {
      await _turnOff();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOff() async {
    final auth = context.read<AuthStore>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off two-factor authentication?'),
        content: const Text(
          'Signing in will only need your password or your Google or Apple '
          'account again. You can turn it back on any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    String message;
    try {
      await auth.disableTwoFactor();
      message = 'Two-factor authentication is off';
    } catch (e) {
      debugPrint('Turning off two-factor authentication failed: $e');
      message = e is SessionPending || (e is! AuthException && isConnectionFailure(e))
          ? 'Could not reach the server. Check your connection and try again.'
          : auth.messageFor(e);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final on = context.watch<AuthStore>().hasTwoFactor;
    // Its own Material, so the tap splash shows over the panel's background.
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(
          Icons.phonelink_lock_rounded,
          color: Palette.accent,
        ),
        title: const Text(
          'Authenticator app',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          on
              ? 'On. Signing in asks for a code from your authenticator app.'
              : 'Ask for a code from an authenticator app each time you sign '
                    'in, after your password or Google or Apple account.',
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        value: on,
        onChanged: _busy ? null : (value) => unawaited(_toggle(value)),
      ),
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
