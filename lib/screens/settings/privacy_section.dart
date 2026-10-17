import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';

/// What other members can see of the account, and what never leaves it. This
/// mirrors the "Who can see what" part of the privacy policy (docs/privacy.html);
/// keep the two in step.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: const [
        Panel(
          title: 'Visible to other signed-in members',
          child: Column(
            children: [
              _Item(
                icon: Icons.badge_rounded,
                title: 'Profile',
                text: 'Display name, username, photo, bio and the month you joined.',
              ),
              _Item(
                icon: Icons.collections_bookmark_rounded,
                title: 'Library',
                text:
                    'Each game with its status, your rating, hours played, platform and '
                    'favorite flag, and the totals made from them.',
              ),
              _Item(
                icon: Icons.history_rounded,
                title: 'Recent activity',
                text: 'Your latest play sessions: the game, hours, platform and when.',
              ),
              _Item(
                icon: Icons.people_alt_rounded,
                title: 'Followers and following',
                text: 'Who follows you and who you follow.',
              ),
              _Item(
                icon: Icons.link_rounded,
                title: 'Connected accounts',
                text:
                    'Your Steam ID and your PSN, Xbox, Discord, Instagram and Twitch '
                    'names, which is what their links open.',
              ),
              _Item(
                icon: Icons.emoji_events_rounded,
                title: 'Achievements',
                text: 'Only when another member asks to see them.',
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        Panel(
          title: 'Private to you',
          child: Column(
            children: [
              _Item(
                icon: Icons.mail_outline_rounded,
                title: 'Email address',
                text: 'Never shown to other members.',
              ),
              _Item(
                icon: Icons.sell_outlined,
                title: 'Purchase prices',
                text: 'What you paid for a game stays on your account.',
              ),
              _Item(
                icon: Icons.sticky_note_2_outlined,
                title: 'Session notes',
                text: 'The notes you write on play sessions.',
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            'None of this is visible to people who are not signed in. You can change '
            'what your profile shows under Edit Profile and in Connected accounts.',
            style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Palette.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: Palette.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
