import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/grocery_item.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Everything the account sheet needs to display.
class AccountInfo {
  const AccountInfo({
    required this.displayName,
    required this.email,
    required this.householdName,
    required this.householdCode,
    required this.memberCount,
  });

  final String displayName;
  final String email;
  final String householdName;
  final String householdCode;
  final int memberCount;
}

/// Shows the account / household bottom sheet.
///
/// The sheet closes itself before invoking [onSwitchHousehold] / [onSignOut],
/// so callbacks can navigate freely.
Future<void> showAccountSheet(
  BuildContext context, {
  required AccountInfo info,
  VoidCallback? onSwitchHousehold,
  VoidCallback? onSignOut,
  VoidCallback? onRemindersChanged,
  VoidCallback? onManageMembers,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => _AccountSheet(
      info: info,
      onSwitchHousehold: onSwitchHousehold,
      onSignOut: onSignOut,
      onRemindersChanged: onRemindersChanged,
      onManageMembers: onManageMembers,
    ),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({
    required this.info,
    this.onSwitchHousehold,
    this.onSignOut,
    this.onRemindersChanged,
    this.onManageMembers,
  });

  final AccountInfo info;
  final VoidCallback? onSwitchHousehold;
  final VoidCallback? onSignOut;
  final VoidCallback? onRemindersChanged;
  final VoidCallback? onManageMembers;

  /// Copies the household code, closes the sheet, then shows a floating
  /// SnackBar (a SnackBar belongs to the underlying Scaffold and would
  /// otherwise be hidden behind the sheet).
  Future<void> _copyCode(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await Clipboard.setData(ClipboardData(text: info.householdCode));
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Household code copied')));
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final danger = AppTheme.statusColor(GroceryStatus.needsPurchase);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      onSignOut?.call();
    }
  }

  void _switchHousehold(BuildContext context) {
    Navigator.of(context).pop();
    onSwitchHousehold?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final danger = AppTheme.statusColor(GroceryStatus.needsPurchase);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(
                  _initials(info.displayName),
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _GroupDivider(),
          Text(
            'HOUSEHOLD',
            style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.home_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.householdName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              info.memberCount == 1
                  ? '1 member'
                  : '${info.memberCount} members',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Household code',
                        style: text.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        info.householdCode,
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy household code',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => _copyCode(context),
                ),
              ],
            ),
          ),
          const _GroupDivider(),
          _RemindersSection(onChanged: onRemindersChanged),
          const _GroupDivider(),
          _ActionTile(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Invite members',
            onTap: () => _copyCode(context),
          ),
          _ActionTile(
            icon: Icons.group_outlined,
            label: 'Manage members',
            onTap: () {
              Navigator.of(context).pop();
              onManageMembers?.call();
            },
          ),
          _ActionTile(
            icon: Icons.swap_horiz_rounded,
            label: 'Switch household',
            onTap: () => _switchHousehold(context),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(height: 1),
          ),
          _ActionTile(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            color: danger,
            onTap: () => _confirmSignOut(context),
          ),
        ],
      ),
    );
  }

  /// First letter of the first and last words, uppercased. Falls back to '?'.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.characters.first).toUpperCase();
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1),
      );
}

class _RemindersSection extends StatefulWidget {
  const _RemindersSection({this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<_RemindersSection> createState() => _RemindersSectionState();
}

class _RemindersSectionState extends State<_RemindersSection> {
  final _settings = SettingsService();

  bool _loading = true;
  bool _enabled = true;
  int _daysBefore = 2;

  static const _dayOptions = [1, 2, 3, 5, 7];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _settings.getExpiryRemindersEnabled();
    final days = await _settings.getExpiryDaysBefore();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _daysBefore = days;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _settings.setExpiryRemindersEnabled(value);
    if (value) {
      await NotificationService.instance.requestPermissions();
    }
    widget.onChanged?.call();
  }

  Future<void> _setDays(int days) async {
    setState(() => _daysBefore = days);
    await _settings.setExpiryDaysBefore(days);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REMINDERS',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.notifications_active_outlined,
              color: scheme.primary),
          title: const Text('Expiry reminders'),
          subtitle: const Text('Get notified before items expire'),
          value: _enabled,
          onChanged: _setEnabled,
        ),
        if (_enabled)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Row(
              children: [
                Text('Remind me',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _daysBefore,
                  underline: const SizedBox.shrink(),
                  items: _dayOptions
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d == 1 ? '1 day before' : '$d days before'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _setDays(v);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
