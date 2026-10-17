import 'package:flutter/material.dart';

import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';

/// Another member in a list: photo, name, @handle and a Follow button. Tapping
/// the row opens their profile. The member who is signed in gets no button.
class MemberTile extends StatelessWidget {
  const MemberTile({super.key, required this.user, this.subtitle});

  final SocialUser user;

  /// A third line under the @handle.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final auth = context.watch<AuthStore>();
    final isSelf = auth.user?.id == user.id;
    final following = profile.isFollowing(user.id);

    void toggle() {
      if (!auth.isLoggedIn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Log in to follow people')),
          );
        return;
      }
      profile.toggleFollow(user.id);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openProfile(context, userId: user.id, preview: user),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ProfileAvatar(name: user.name, size: 52, imageUrl: user.avatarUrl),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    user.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Palette.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelf)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'You',
                  style: TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              )
            else ...[
              const SizedBox(width: 8),
              following
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: toggle,
                      child: const Text('Following'),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: toggle,
                      child: const Text('Follow'),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
