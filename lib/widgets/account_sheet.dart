import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
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
  VoidCallback? onInsights,
  VoidCallback? onActivity,
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
      onInsights: onInsights,
      onActivity: onActivity,
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
    this.onInsights,
    this.onActivity,
  });

  final AccountInfo info;
  final VoidCallback? onSwitchHousehold;
  final VoidCallback? onSignOut;
  final VoidCallback? onRemindersChanged;
  final VoidCallback? onManageMembers;
  final VoidCallback? onInsights;
  final VoidCallback? onActivity;

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

  /// Opens the native share sheet with an invite message containing the code.
  Future<void> _inviteMembers(BuildContext context) async {
    final navigator = Navigator.of(context);
    final message =
        'Join our household "${info.householdName}" on StockHome!\n\n'
        'Open the app, tap "Join a household", and enter this code:\n'
        '${info.householdCode}';
    navigator.pop();
    await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: 'Join ${info.householdName} on StockHome',
      ),
    );
  }

  /// Lets the user export inventory or purchase history as CSV via share.
  Future<void> _exportData(BuildContext context) async {
    final provider = context.read<GroceryProvider>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Inventory (CSV)'),
              onTap: () => Navigator.pop(ctx, 'inventory'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Purchase history (CSV)'),
              onTap: () => Navigator.pop(ctx, 'purchases'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    String csv;
    String filename;
    if (choice == 'inventory') {
      csv = provider.inventoryCsv();
      filename = 'stockhome_inventory.csv';
    } else {
      csv = await provider.purchasesCsv();
      filename = 'stockhome_purchases.csv';
    }
    if (csv.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to export yet.')),
        );
      }
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        text: csv,
        subject: filename,
      ),
    );
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
    // Capture the root navigator before closing this sheet, so we can open
    // the switcher and navigate afterwards with a valid context.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final auth = context.read<AuthProvider>();
    final onNew = onSwitchHousehold;
    Navigator.of(context).pop(); // close the account sheet
    _showHouseholdSwitcher(rootContext, auth, onNew);
  }

  Future<void> _showHouseholdSwitcher(
    BuildContext context,
    AuthProvider auth,
    VoidCallback? onNew,
  ) async {
    final memberships = await auth.watchMemberships().first;
    if (!context.mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Your households',
                  style: Theme.of(ctx).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final h in memberships)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: const Icon(Icons.home_rounded),
                ),
                title: Text(h.name),
                subtitle: Text(
                    '${h.memberCount} member${h.memberCount == 1 ? '' : 's'}'),
                trailing: h.id == auth.householdId
                    ? Icon(Icons.check_circle, color: scheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, h.id),
              ),
            const Divider(),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.secondaryContainer,
                child: const Icon(Icons.add),
              ),
              title: const Text('Create or join another household'),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result == 'new') {
      onNew?.call(); // routes to HouseholdSetupScreen
    } else if (result is String && result != auth.householdId) {
      await auth.switchHousehold(result);
      // The household-id stream will re-fire, rebinding everything via AppGate.
    }
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
          const _ThemeSection(),
          const _GroupDivider(),
          const _LanguageSection(),
          const _GroupDivider(),
          _ActionTile(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Invite members',
            onTap: () => _inviteMembers(context),
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
            icon: Icons.insights_outlined,
            label: 'Spending & insights',
            onTap: () {
              Navigator.of(context).pop();
              onInsights?.call();
            },
          ),
          _ActionTile(
            icon: Icons.history,
            label: 'Activity',
            onTap: () {
              Navigator.of(context).pop();
              onActivity?.call();
            },
          ),
          _ActionTile(
            icon: Icons.ios_share,
            label: 'Export data',
            onTap: () => _exportData(context),
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
          const SizedBox(height: 8),
          const Center(child: _VersionLabel()),
          const SizedBox(height: 4),
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

class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localeProvider = context.watch<LocaleProvider>();
    final current = localeProvider.locale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.language ?? 'LANGUAGE',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.translate, color: scheme.primary),
          title: Text(LocaleProvider.labelFor(current)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickLanguage(context),
        ),
      ],
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final provider = context.read<LocaleProvider>();
    final current = provider.locale;
    // Options: System default (null) + each supported locale.
    final options = <Locale?>[null, ...LocaleProvider.supported];
    final chosen = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final loc in options)
              ListTile(
                title: Text(LocaleProvider.labelFor(loc)),
                trailing: (current?.languageCode ?? '') ==
                        (loc?.languageCode ?? '')
                    ? Icon(Icons.check,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, loc ?? 'system'),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    if (chosen == 'system') {
      await provider.setLocale(null);
    } else if (chosen is Locale) {
      await provider.setLocale(chosen);
    }
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final themeProvider = context.watch<ThemeProvider>();
    final mode = themeProvider.themeMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'APPEARANCE',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dark'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              context.read<ThemeProvider>().setThemeMode(s.first),
        ),
      ],
    );
  }
}

class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'StockHome v${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // Ignore — just don't show a version.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_version.isEmpty) return const SizedBox(height: 16);
    return Text(
      _version,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
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
