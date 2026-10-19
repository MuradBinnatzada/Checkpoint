import 'package:flutter/material.dart';

import 'package:checkpoint/screens/settings/account_section.dart';
import 'package:checkpoint/screens/settings/data_section.dart';
import 'package:checkpoint/screens/settings/privacy_section.dart';
import 'package:checkpoint/screens/settings/security_section.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';

/// The parts of Settings, in the order they are listed.
enum SettingsSection {
  account('Account', Icons.person_rounded),
  security('Security', Icons.shield_rounded),
  privacy('Privacy', Icons.lock_rounded),
  data('Your data', Icons.import_export_rounded);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Settings, split into sections. On a wide window the sections are a sidebar on
/// the left; on a phone they are a row of chips across the head of the screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialSection = SettingsSection.account,
  });

  final SettingsSection initialSection;

  /// Windows at least this wide get the sidebar.
  static const double sidebarBreakpoint = 720;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section = widget.initialSection;

  /// The account is being deleted: the screen can't be left or switched, because
  /// leaving would hide whether it worked.
  bool _deleting = false;

  void _select(SettingsSection section) {
    if (_deleting || section == _section) return;
    setState(() => _section = section);
  }

  Widget _content() {
    final body = switch (_section) {
      SettingsSection.account => AccountSection(
        onDeletingChanged: (deleting) => setState(() => _deleting = deleting),
      ),
      SettingsSection.security => const SecuritySection(),
      SettingsSection.privacy => const PrivacySection(),
      SettingsSection.data => const DataSection(),
    };
    // A section starts at its top, whatever the one before was scrolled to.
    return KeyedSubtree(key: ValueKey(_section), child: body);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_deleting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _content(),
                ),
              );
              if (constraints.maxWidth >= SettingsScreen.sidebarBreakpoint) {
                return Row(
                  children: [
                    SizedBox(
                      width: 232,
                      child: _Sidebar(
                        selected: _section,
                        enabled: !_deleting,
                        onSelect: _select,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Expanded(child: content),
                  ],
                );
              }
              return Column(
                children: [
                  _SectionChips(
                    selected: _section,
                    enabled: !_deleting,
                    onSelect: _select,
                  ),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The sections down the left side of a wide window.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final SettingsSection selected;
  final bool enabled;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      children: [
        for (final section in SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              enabled: enabled,
              selected: section == selected,
              selectedColor: Palette.accent,
              selectedTileColor: Palette.accent.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(section.icon),
              title: Text(
                section.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => onSelect(section),
            ),
          ),
      ],
    );
  }
}

/// The sections as a row of chips across the top of a narrow screen.
class _SectionChips extends StatelessWidget {
  const _SectionChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final SettingsSection selected;
  final bool enabled;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          for (final section in SettingsSection.values) ...[
            if (section != SettingsSection.values.first)
              const SizedBox(width: 8),
            IgnorePointer(
              ignoring: !enabled,
              child: AppChoiceChip(
                label: section.label,
                selected: section == selected,
                onSelected: () => onSelect(section),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
