import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/grocery_categories.dart';
import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../services/product_lookup_service.dart';
import '../theme/app_theme.dart';
import 'barcode_scanner_screen.dart';

/// Form to add a new grocery or edit an existing one. Wired to [GroceryProvider].
class GroceryFormScreen extends StatefulWidget {
  const GroceryFormScreen({super.key, this.existing});

  /// Null → "Add grocery" mode. Non-null → "Edit grocery" mode (pre-filled).
  final GroceryItem? existing;

  bool get _isEditing => existing != null;

  @override
  State<GroceryFormScreen> createState() => _GroceryFormScreenState();
}

class _GroceryFormScreenState extends State<GroceryFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;

  late String _category;
  late String _unit;
  late GroceryStatus _status;

  DateTime? _purchaseDate;
  DateTime? _expiryDate;
  bool _isStaple = false;

  bool _saving = false;
  bool _scanning = false;

  final _nameFocus = FocusNode();
  final _qtyFocus = FocusNode();

  final _lookupService = ProductLookupService();

  final DateTime _firstDate = DateTime(DateTime.now().year - 2, 1, 1);
  final DateTime _lastDate = DateTime(DateTime.now().year + 5, 12, 31);

  static final _dateFormat = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _qtyCtrl = TextEditingController(
      text: item != null ? _fmtQty(item.quantity) : '',
    );
    _category = item?.category ?? GroceryCategories.all.last; // "Other"
    _unit = item?.unit ?? GroceryCategories.units.first; // "pcs"
    _status = item?.status ?? GroceryStatus.inStock;
    _purchaseDate = item?.purchaseDate;
    _expiryDate = item?.expiryDate;
    _isStaple = item?.isStaple ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _nameFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  static String _fmtQty(double qty) =>
      qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toString();

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: _firstDate,
      lastDate: _lastDate,
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _scanBarcode() async {
    final messenger = ScaffoldMessenger.of(context);
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode == null || !mounted) return;

    setState(() => _scanning = true);
    try {
      final product = await _lookupService.lookup(barcode);
      if (!mounted) return;
      if (product == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Product not found. Enter the details manually.'),
          ),
        );
        return;
      }
      setState(() {
        _nameCtrl.text = product.name;
        final cat = product.category;
        if (cat != null && GroceryCategories.all.contains(cat)) {
          _category = cat;
        }
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Found: ${product.name}')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final groceries = context.read<GroceryProvider>();
    final displayName =
        auth.user?.displayName ?? auth.user?.email ?? 'Someone';
    final quantity = double.parse(_qtyCtrl.text.trim().replaceAll(',', '.'));

    try {
      if (widget._isEditing) {
        final updated = widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          category: _category,
          quantity: quantity,
          unit: _unit,
          status: _status,
          purchaseDate: _purchaseDate,
          expiryDate: _expiryDate,
          isStaple: _isStaple,
          updatedBy: displayName,
        );
        await groceries.updateGrocery(updated);
      } else {
        final item = GroceryItem(
          id: '',
          name: _nameCtrl.text.trim(),
          category: _category,
          quantity: quantity,
          unit: _unit,
          status: _status,
          purchaseDate: _purchaseDate,
          expiryDate: _expiryDate,
          isStaple: _isStaple,
          updatedBy: displayName,
        );
        await groceries.addGrocery(item);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')),
        );
      }
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Name is required';
    if (value.trim().length < 2) return 'Name is too short';
    return null;
  }

  String? _validateQuantity(String? value) {
    if (value == null || value.trim().isEmpty) return 'Quantity is required';
    final qty = double.tryParse(value.trim().replaceAll(',', '.'));
    if (qty == null) return 'Enter a valid number';
    if (qty <= 0) return 'Must be greater than 0';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget._isEditing ? 'Edit grocery' : 'Add grocery'),
        scrolledUnderElevation: 2,
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_scanner),
            onPressed: (_saving || _scanning) ? null : _scanBarcode,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            const _SectionLabel(label: 'Details'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_qtyFocus),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Whole milk',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: _validateName,
            ),
            const SizedBox(height: 14),
            _DropdownField<String>(
              value: _category,
              labelText: 'Category',
              prefixIcon: Icons.category_outlined,
              enabled: !_saving,
              items: GroceryCategories.all
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: TextFormField(
                    controller: _qtyCtrl,
                    focusNode: _qtyFocus,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*[.,]?\d*'),
                      ),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      hintText: 'e.g. 1.5',
                      prefixIcon: Icon(Icons.straighten_outlined),
                    ),
                    validator: _validateQuantity,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 9,
                  child: _DropdownField<String>(
                    value: _unit,
                    labelText: 'Unit',
                    prefixIcon: Icons.scale_outlined,
                    enabled: !_saving,
                    items: GroceryCategories.units
                        .map((u) =>
                            DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setState(() => _unit = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DropdownField<GroceryStatus>(
              value: _status,
              labelText: 'Status',
              prefixIcon: Icons.circle_outlined,
              prefixIconColor: AppTheme.statusColor(_status),
              enabled: !_saving,
              items: GroceryStatus.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.statusColor(s),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(s.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile(
                value: _isStaple,
                onChanged: (v) => setState(() => _isStaple = v),
                secondary: const Icon(Icons.autorenew),
                title: const Text('Staple item'),
                subtitle: const Text(
                    'Automatically added to the shopping list when it runs out'),
              ),
            ),
            const SizedBox(height: 28),
            const _SectionLabel(label: 'Dates'),
            const SizedBox(height: 10),
            _DatePickerTile(
              label: 'Purchase date',
              date: _purchaseDate,
              dateFormat: _dateFormat,
              enabled: !_saving,
              onTap: () => _pickDate(
                current: _purchaseDate,
                onPicked: (d) => setState(() => _purchaseDate = d),
              ),
              onClear: () => setState(() => _purchaseDate = null),
            ),
            const SizedBox(height: 10),
            _DatePickerTile(
              label: 'Expiry / best-by date',
              date: _expiryDate,
              dateFormat: _dateFormat,
              enabled: !_saving,
              isExpiry: true,
              onTap: () => _pickDate(
                current: _expiryDate,
                onPicked: (d) => setState(() => _expiryDate = d),
              ),
              onClear: () => setState(() => _expiryDate = null),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: scheme.onPrimary,
                    ),
                  )
                : Text(widget._isEditing ? 'Save changes' : 'Add to pantry'),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: scheme.primary,
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.labelText,
    required this.prefixIcon,
    required this.items,
    required this.onChanged,
    this.prefixIconColor,
    this.enabled = true,
  });

  final T value;
  final String labelText;
  final IconData prefixIcon;
  final Color? prefixIconColor;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(14),
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(prefixIcon, color: prefixIconColor),
      ),
      items: items,
      onChanged: enabled ? onChanged : null,
      dropdownColor: scheme.surfaceContainerHigh,
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.dateFormat,
    required this.onTap,
    required this.onClear,
    this.enabled = true,
    this.isExpiry = false,
  });

  final String label;
  final DateTime? date;
  final DateFormat dateFormat;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final bool enabled;
  final bool isExpiry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final danger = AppTheme.statusColor(GroceryStatus.needsPurchase);

    final bool isSet = date != null;
    final bool isPast = isExpiry && isSet && date!.isBefore(DateTime.now());

    final Color tileColor = isPast
        ? danger.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final Color borderColor =
        isPast ? danger.withValues(alpha: 0.4) : scheme.outlineVariant;
    final Color valueColor = isPast
        ? danger
        : isSet
            ? scheme.onSurface
            : scheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: tileColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: isPast ? danger : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isPast ? danger : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSet
                            ? '${dateFormat.format(date!)}${isPast ? '  ·  Expired' : ''}'
                            : 'Not set',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: valueColor,
                          fontWeight:
                              isSet ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSet)
                  IconButton(
                    tooltip: 'Clear date',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: enabled ? onClear : null,
                    icon: Icon(Icons.close,
                        size: 18, color: scheme.onSurfaceVariant),
                  )
                else
                  Icon(Icons.chevron_right,
                      size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
