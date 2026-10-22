import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/milestone_badge.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';

/// Another member in a list: photo (in their frame), name with the milestones
/// they show off, @handle and a Follow button. Tapping the row opens their
/// profile. The member who is signed in gets no button.
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
    final frame = user.flair.frame;
    // A framed photo is drawn smaller, so the row keeps its height.
    final photo = frame == null ? 52.0 : 52 - 2 * FramedAvatar.inset(52);

    void toggle() {
      if (!auth.isLoggedIn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.logInToFollow)),
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
            SizedBox.square(
              dimension: 52,
              child: Center(
                child: FramedAvatar(
                  size: photo,
                  frame: frame,
                  child: ProfileAvatar(name: user.name, size: photo, imageUrl: user.avatarUrl),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final m in user.flair.showcase)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: MilestoneBadge(milestone: m, size: 18),
                        ),
                    ],
                  ),
                  Text(
                    user.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.palette.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelf)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  context.l10n.you,
                  style: TextStyle(color: context.palette.muted, fontSize: 12.5),
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
                      child: Text(context.l10n.followingButton),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: toggle,
                      child: Text(context.l10n.follow),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
