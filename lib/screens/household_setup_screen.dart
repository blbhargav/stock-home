import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Lets a signed-in user create a new household or join an existing one
/// using a shared household code. Wired to [AuthProvider].
class HouseholdSetupScreen extends StatefulWidget {
  const HouseholdSetupScreen({super.key, this.addingAnother = false});

  /// When true, this screen is pushed as a route to add a second household
  /// (shows a back button and pops on success). When false, it's the gate
  /// screen for first-time setup.
  final bool addingAnother;

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _createFormKey = GlobalKey<FormState>();
  final _joinFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _creating = false;
  bool _joining = false;
  String? _joinError;

  bool get _busy => _creating || _joining;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ---- Validation ---------------------------------------------------------

  String? _validateHouseholdName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Give your household a name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  String? _validateCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the household code';
    return null;
  }

  // ---- Actions ------------------------------------------------------------

  Future<void> _createHousehold() async {
    FocusScope.of(context).unfocus();
    if (!(_createFormKey.currentState?.validate() ?? false)) return;

    setState(() => _creating = true);
    try {
      await context.read<AuthProvider>().createHousehold(_nameCtrl.text);
      if (widget.addingAnother && mounted) {
        _showSnack('Household created! Switched to "${_nameCtrl.text}".');
        Navigator.of(context).pop();
      }
      // Otherwise AppGate routes to HomeScreen once householdId is set.
    } catch (e) {
      if (mounted) {
        _showSnack('Could not create household. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinHousehold() async {
    FocusScope.of(context).unfocus();
    setState(() => _joinError = null);
    if (!(_joinFormKey.currentState?.validate() ?? false)) return;

    setState(() => _joining = true);
    try {
      await context.read<AuthProvider>().joinHousehold(_codeCtrl.text);
      if (widget.addingAnother && mounted) {
        _showSnack('Joined household!');
        Navigator.of(context).pop();
      }
      // Otherwise AppGate routes to HomeScreen once householdId is set.
    } catch (e) {
      if (mounted) {
        setState(() => _joinError = e is StateError
            ? e.message
            : 'No household found for that code. Double-check it with '
                'whoever invited you.');
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (mounted) await context.read<AuthProvider>().signOut();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = context.watch<AuthProvider>();
    final name = auth.resolvedDisplayName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your household'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _busy ? null : _confirmSignOut,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildIntro(theme, scheme, name),
                  const SizedBox(height: 24),
                  _buildCreateCard(theme, scheme),
                  const SizedBox(height: 16),
                  _OrDivider(color: scheme.outlineVariant),
                  const SizedBox(height: 16),
                  _buildJoinCard(theme, scheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(ThemeData theme, ColorScheme scheme, String? name) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.home_rounded,
              size: 32,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            (name == null || name.isEmpty) ? 'Welcome!' : 'Welcome, $name!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'StockHome works best when everyone at home shares one pantry. '
            'Start a new household, or join an existing one with the code '
            'a housemate shared with you.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateCard(ThemeData theme, ColorScheme scheme) {
    return _SetupCard(
      icon: Icons.add_home_rounded,
      title: 'Create a household',
      subtitle: "You'll get a code to invite the people you live with.",
      child: Form(
        key: _createFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _createHousehold(),
              decoration: const InputDecoration(
                labelText: 'Household name',
                hintText: 'e.g. The Rivera Family',
                prefixIcon: Icon(Icons.house_outlined),
              ),
              validator: _validateHouseholdName,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _createHousehold,
              child: _creating
                  ? _ButtonSpinner(color: scheme.onPrimary)
                  : const Text('Create household'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinCard(ThemeData theme, ColorScheme scheme) {
    return _SetupCard(
      icon: Icons.group_add_rounded,
      title: 'Join a household',
      subtitle: 'Enter the code a housemate shared with you.',
      child: Form(
        key: _joinFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _codeCtrl,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onFieldSubmitted: (_) => _joinHousehold(),
              onChanged: (_) {
                if (_joinError != null) setState(() => _joinError = null);
              },
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(
                labelText: 'Household code',
                hintText: 'Paste the code from a housemate',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              validator: _validateCode,
            ),
            if (_joinError != null) ...[
              const SizedBox(height: 12),
              _InlineError(message: _joinError!),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : _joinHousehold,
              child: _joining
                  ? _ButtonSpinner(color: scheme.primary)
                  : const Text('Join household'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: style),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
