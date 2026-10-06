import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/grocery_categories.dart';
import '../models/grocery_item.dart';
import '../models/grocery_suggestions.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../services/product_lookup_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
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
  late final TextEditingController _notesCtrl;

  /// Captured from the Autocomplete's fieldViewBuilder so programmatic updates
  /// (e.g. barcode scan) reflect in the visible name field.
  TextEditingController? _nameFieldCtrl;

  late String _category;
  late String _unit;
  late GroceryStatus _status;

  DateTime? _purchaseDate;
  DateTime? _expiryDate;
  bool _isStaple = false;

  // Label (card) image state.
  String? _imageUrl; // existing/remote URL
  File? _pickedImage; // newly picked local file (not yet uploaded)
  bool _removeImage = false; // user removed the existing image
  double? _uploadProgress; // non-null while uploading

  // User reference photos (max GroceryItem.maxPhotos).
  List<String> _existingPhotos = []; // remote URLs retained
  final List<File> _newPhotos = []; // newly picked local files to upload

  bool _saving = false;
  bool _scanning = false;
  bool _listeningNotes = false;
  String _notesBeforeDictation = '';

  final _qtyFocus = FocusNode();

  final _lookupService = ProductLookupService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

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
    _notesCtrl = TextEditingController(text: item?.notes ?? '');
    _category = item?.category ?? GroceryCategories.all.last; // "Other"
    _unit = item?.unit ?? GroceryCategories.units.first; // "pcs"
    _status = item?.status ?? GroceryStatus.inStock;
    _purchaseDate = item?.purchaseDate;
    _expiryDate = item?.expiryDate;
    _isStaple = item?.isStaple ?? false;
    _imageUrl = item?.imageUrl;
    _existingPhotos = List<String>.from(item?.photos ?? const []);
    _loadFrequentNames();
  }

  // Cache of the household's previously-purchased item names (most frequent
  // first), used to enrich the name autocomplete.
  List<String> _frequentNames = const [];

  Future<void> _loadFrequentNames() async {
    try {
      // Pull a broad set once; filtering happens in optionsBuilder.
      final names = await context
          .read<GroceryProvider>()
          .frequentItemNames('', limit: 1000);
      if (mounted) setState(() => _frequentNames = names);
    } catch (_) {
      // Non-critical.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
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

  Future<void> _toggleNotesDictation() async {
    if (_listeningNotes) {
      await SpeechService.instance.stop();
      setState(() => _listeningNotes = false);
      return;
    }
    // Append to existing notes.
    _notesBeforeDictation = _notesCtrl.text.isEmpty
        ? ''
        : '${_notesCtrl.text.trimRight()} ';
    setState(() => _listeningNotes = true);
    await SpeechService.instance.listen(
      onResult: (text) {
        if (mounted) {
          setState(() {
            _notesCtrl.text = '$_notesBeforeDictation$text';
            _notesCtrl.selection = TextSelection.collapsed(
                offset: _notesCtrl.text.length);
          });
        }
      },
    );
    // Auto-stop detection: speech_to_text calls onStatus('done') when the
    // user stops speaking; the engine then calls stop internally. We just
    // need to update our UI state. Use a delayed check.
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _listeningNotes) {
        setState(() => _listeningNotes = false);
      }
    });
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
        // Also update the visible Autocomplete field, if built.
        _nameFieldCtrl?.text = product.name;
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() {
        _pickedImage = File(picked.path);
        _removeImage = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick image.')),
        );
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeCurrentImage() {
    setState(() {
      _pickedImage = null;
      _removeImage = true;
      _imageUrl = null;
    });
  }

  int get _photoCount => _existingPhotos.length + _newPhotos.length;

  Future<void> _addUserPhoto() async {
    if (_photoCount >= GroceryItem.maxPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() => _newPhotos.add(File(picked.path)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick image.')),
        );
      }
    }
  }

  void _removeExistingPhoto(String url) {
    setState(() => _existingPhotos.remove(url));
    // Actual Storage deletion happens on save.
  }

  void _removeNewPhoto(File file) {
    setState(() => _newPhotos.remove(file));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final groceries = context.read<GroceryProvider>();
    final displayName = auth.resolvedDisplayName;
    final householdId = auth.householdId;
    final quantity = double.parse(_qtyCtrl.text.trim().replaceAll(',', '.'));
    final notes = _notesCtrl.text.trim();

    try {
      // Resolve the final image URL: upload new picks, keep or clear existing.
      String? finalImageUrl = _imageUrl;
      if (_pickedImage != null && householdId != null) {
        setState(() => _uploadProgress = 0);
        final imageId = DateTime.now().millisecondsSinceEpoch.toString();
        finalImageUrl = await _storageService.uploadImage(
          householdId: householdId,
          imageId: imageId,
          file: _pickedImage!,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );
        // Delete the previous image if we're replacing one.
        final old = widget.existing?.imageUrl;
        if (old != null && old.isNotEmpty && old != finalImageUrl) {
          await _storageService.deleteByUrl(old);
        }
      } else if (_removeImage) {
        final old = widget.existing?.imageUrl;
        if (old != null && old.isNotEmpty) {
          await _storageService.deleteByUrl(old);
        }
        finalImageUrl = null;
      }
      if (mounted) setState(() => _uploadProgress = null);

      // Resolve user reference photos: delete removed existing ones, upload new.
      final removedPhotos = (widget.existing?.photos ?? const [])
          .where((url) => !_existingPhotos.contains(url))
          .toList();
      for (final url in removedPhotos) {
        await _storageService.deleteByUrl(url);
      }
      final uploadedPhotos = <String>[];
      for (final file in _newPhotos) {
        if (householdId == null) break;
        setState(() => _uploadProgress = 0);
        final photoId =
            'photo_${DateTime.now().microsecondsSinceEpoch}';
        final url = await _storageService.uploadImage(
          householdId: householdId,
          imageId: photoId,
          file: file,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );
        uploadedPhotos.add(url);
      }
      final finalPhotos = [..._existingPhotos, ...uploadedPhotos];
      if (mounted) setState(() => _uploadProgress = null);

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
          notes: notes.isEmpty ? null : notes,
          clearNotes: notes.isEmpty,
          imageUrl: finalImageUrl,
          clearImage: finalImageUrl == null,
          photos: finalPhotos,
          updatedBy: displayName,
          updatedByName: displayName,
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
          notes: notes.isEmpty ? null : notes,
          imageUrl: finalImageUrl,
          photos: finalPhotos,
          updatedBy: displayName,
          updatedByName: displayName,
        );
        await groceries.addGrocery(item);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = null;
        });
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
            _ImagePickerCard(
              pickedImage: _pickedImage,
              imageUrl: _imageUrl,
              uploadProgress: _uploadProgress,
              enabled: !_saving,
              onPick: _showImageSourceSheet,
              onRemove: _removeCurrentImage,
            ),
            const SizedBox(height: 14),
            // ── Name with autocomplete suggestions ─────────────────────────
            Autocomplete<({String name, String category})>(
              initialValue: TextEditingValue(text: _nameCtrl.text),
              optionsBuilder: (value) {
                final query = value.text.trim();
                if (query.isEmpty) {
                  return const Iterable<({String name, String category})>.empty();
                }
                final q = query.toLowerCase();
                final matches = GrocerySuggestions.search(query);
                final hasExact = matches.any(
                  (s) => s.name.toLowerCase() == q,
                );
                // Household's recently/frequently bought names matching query,
                // excluding any already covered by the static list.
                final staticNames =
                    matches.map((s) => s.name.toLowerCase()).toSet();
                final recent = _frequentNames
                    .where((n) =>
                        n.toLowerCase().contains(q) &&
                        !staticNames.contains(n.toLowerCase()) &&
                        n.toLowerCase() != q)
                    .take(3)
                    .map((n) => (name: n, category: '__recent__'))
                    .toList();
                return [
                  if (!hasExact) (name: query, category: ''),
                  ...recent,
                  ...matches,
                ];
              },
              displayStringForOption: (s) => s.name,
              onSelected: (suggestion) {
                _nameCtrl.text = suggestion.name;
                // Only pre-fill category for real static suggestions.
                if (suggestion.category.isNotEmpty &&
                    suggestion.category != '__recent__' &&
                    GroceryCategories.all.contains(suggestion.category)) {
                  setState(() => _category = suggestion.category);
                }
                FocusScope.of(context).requestFocus(_qtyFocus);
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                // Capture the Autocomplete's controller so scan/suggestion
                // updates can write to the visible field. Register the sync
                // listener only once per controller instance.
                if (!identical(_nameFieldCtrl, controller)) {
                  _nameFieldCtrl = controller;
                  controller.addListener(() {
                    if (_nameCtrl.text != controller.text) {
                      _nameCtrl.text = controller.text;
                    }
                  });
                }
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) {
                    onFieldSubmitted();
                    FocusScope.of(context).requestFocus(_qtyFocus);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Aloo, Paneer, Chai…',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  validator: _validateName,
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final scheme = Theme.of(context).colorScheme;
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(14),
                    color: scheme.surfaceContainerHigh,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, _) => Divider(
                            height: 1, color: scheme.outlineVariant),
                        itemBuilder: (context, index) {
                          final s = options.elementAt(index);
                          final isCustom = s.category.isEmpty;
                          final isRecent = s.category == '__recent__';
                          return InkWell(
                            onTap: () => onSelected(s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  if (isCustom) ...[
                                    Icon(Icons.add,
                                        size: 18, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(text: 'Add '),
                                            TextSpan(
                                              text: '"${s.name}"',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        ),
                                        style:
                                            TextStyle(color: scheme.primary),
                                      ),
                                    ),
                                  ] else if (isRecent) ...[
                                    Icon(Icons.history,
                                        size: 18,
                                        color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: scheme.secondaryContainer
                                            .withValues(alpha: 0.6),
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        'Recent',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer
                                            .withValues(alpha: 0.5),
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        s.category,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
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
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesCtrl,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Notes',
                hintText: _listeningNotes
                    ? 'Listening…'
                    : 'e.g. Top shelf of fridge, prefer Amul brand',
                prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: _listeningNotes
                      ? 'Stop dictation'
                      : 'Dictate notes',
                  icon: Icon(
                    _listeningNotes ? Icons.stop_circle : Icons.mic_outlined,
                    color: _listeningNotes
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _saving ? null : _toggleNotesDictation,
                ),
              ),
            ),
            _NoteSuggestions(
              currentNote: _notesCtrl.text,
              onSelect: (note) => setState(() {
                _notesCtrl.text = note;
                _notesCtrl.selection =
                    TextSelection.collapsed(offset: note.length);
              }),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionLabel(label: 'Photos'),
                Text(
                  '$_photoCount / ${GroceryItem.maxPhotos}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Add up to ${GroceryItem.maxPhotos} photos — e.g. what it looks '
              'like or where it\'s stored.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            _UserPhotosRow(
              existingPhotos: _existingPhotos,
              newPhotos: _newPhotos,
              maxPhotos: GroceryItem.maxPhotos,
              enabled: !_saving,
              onAdd: _addUserPhoto,
              onRemoveExisting: _removeExistingPhoto,
              onRemoveNew: _removeNewPhoto,
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

class _ImagePickerCard extends StatelessWidget {
  const _ImagePickerCard({
    required this.pickedImage,
    required this.imageUrl,
    required this.uploadProgress,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final File? pickedImage;
  final String? imageUrl;
  final double? uploadProgress;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  bool get _hasImage => pickedImage != null || (imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_hasImage) {
      // Add-photo placeholder.
      return InkWell(
        onTap: enabled ? onPick : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined,
                  size: 32, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                'Add a photo',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Image preview with overlay actions.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: pickedImage != null
                ? Image.file(pickedImage!, fit: BoxFit.cover)
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: scheme.surfaceContainerHighest,
                        child: const Center(
                            child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stack) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
          ),
          // Upload progress overlay.
          if (uploadProgress != null)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: CircularProgressIndicator(
                    value: uploadProgress,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // Action buttons.
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                _OverlayButton(
                  icon: Icons.edit,
                  tooltip: 'Change photo',
                  onPressed: enabled ? onPick : null,
                ),
                const SizedBox(width: 8),
                _OverlayButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove photo',
                  onPressed: enabled ? onRemove : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        color: Colors.white,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _UserPhotosRow extends StatelessWidget {
  const _UserPhotosRow({
    required this.existingPhotos,
    required this.newPhotos,
    required this.maxPhotos,
    required this.enabled,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  final List<String> existingPhotos;
  final List<File> newPhotos;
  final int maxPhotos;
  final bool enabled;
  final VoidCallback onAdd;
  final void Function(String url) onRemoveExisting;
  final void Function(File file) onRemoveNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = existingPhotos.length + newPhotos.length;
    final canAdd = count < maxPhotos;

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final url in existingPhotos)
            _PhotoThumb(
              image: Image.network(url, fit: BoxFit.cover),
              fullImage: Image.network(url, fit: BoxFit.contain),
              enabled: enabled,
              onRemove: () => onRemoveExisting(url),
            ),
          for (final file in newPhotos)
            _PhotoThumb(
              image: Image.file(file, fit: BoxFit.cover),
              fullImage: Image.file(file, fit: BoxFit.contain),
              enabled: enabled,
              onRemove: () => onRemoveNew(file),
            ),
          if (canAdd)
            InkWell(
              onTap: enabled ? onAdd : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: scheme.primary),
                    const SizedBox(height: 4),
                    Text('Add',
                        style: TextStyle(
                            color: scheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.image,
    required this.fullImage,
    required this.enabled,
    required this.onRemove,
  });

  final Widget image;
  final Widget fullImage;
  final bool enabled;
  final VoidCallback onRemove;

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenPhoto(image: fullImage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _openFullscreen(context),
              child: SizedBox(width: 100, height: 100, child: image),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onRemove : null,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom photo viewer.
class _FullscreenPhoto extends StatelessWidget {
  const _FullscreenPhoto({required this.image});

  final Widget image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: image,
        ),
      ),
    );
  }
}

class _NoteSuggestions extends StatelessWidget {
  const _NoteSuggestions({
    required this.currentNote,
    required this.onSelect,
  });

  final String currentNote;
  final void Function(String note) onSelect;

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<GroceryProvider>().recentNotes;
    final current = currentNote.trim().toLowerCase();

    // Filter: exclude exact match (already typed) and optionally filter by
    // prefix if the user has started typing.
    final suggestions = notes
        .where((n) =>
            n.trim().toLowerCase() != current &&
            (current.isEmpty ||
                n.toLowerCase().contains(current)))
        .take(5)
        .toList(growable: false);

    if (suggestions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final note in suggestions)
            ActionChip(
              avatar: Icon(Icons.sticky_note_2_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              label: Text(
                note.length > 30 ? '${note.substring(0, 30)}…' : note,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              onPressed: () => onSelect(note),
            ),
        ],
      ),
    );
  }
}

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
