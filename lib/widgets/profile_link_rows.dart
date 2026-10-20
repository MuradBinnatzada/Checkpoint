import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

/// One row of [ProfileLinkRows].
class ProfileLink {
  const ProfileLink({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown on the right, before the arrow.
  final int? count;
}

/// A short menu at the foot of a profile: an icon, a label, how many, and an
/// arrow, one row each, in one rounded card.
class ProfileLinkRows extends StatelessWidget {
  const ProfileLinkRows({super.key, required this.links});

  final List<ProfileLink> links;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 52,
                color: context.palette.hairline,
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  links[i].onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(links[i].icon, size: 20, color: context.palette.accent),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          links[i].label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (links[i].count != null) ...[
                        Text(
                          fmtCount(links[i].count!),
                          style: TextStyle(
                            color: context.palette.muted,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: context.palette.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
