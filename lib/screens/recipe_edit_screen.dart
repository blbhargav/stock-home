import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../providers/auth_provider.dart';
import '../providers/recipe_provider.dart';
import '../services/storage_service.dart';

/// Create or edit a household (user) recipe. Built-in recipes are read-only and
/// never reach this screen for editing.
///
/// Ingredients and steps are reorderable cards. Each step can be linked to
/// ingredients (so it only appears when those are selected) and can carry an
/// optional timer in minutes.
class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.existing});

  final Recipe? existing;

  bool get isEditing => existing != null;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _servingsCtrl;

  final List<_IngredientDraft> _ingredients = [];
  final List<_StepDraft> _steps = [];
  int _nextIngredientId = 0;
  bool _saving = false;

  final _imagePicker = ImagePicker();
  final _storage = StorageService();
  File? _pickedImage; // newly chosen image not yet uploaded
  String? _imageUrl; // existing/remote image url
  bool _removeImage = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _servingsCtrl = TextEditingController(text: r?.servings?.toString() ?? '');
    _imageUrl = r?.imageUrl;

    if (r != null) {
      for (final ing in r.ingredients) {
        _ingredients.add(_IngredientDraft.fromModel(ing));
      }
      for (final step in r.steps) {
        _steps.add(_StepDraft.fromModel(step));
      }
    } else {
      _addIngredient();
      _addStep();
    }
    _nextIngredientId = _ingredients.length + 1;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _servingsCtrl.dispose();
    for (final i in _ingredients) {
      i.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  void _addIngredient() {
    HapticFeedback.selectionClick();
    setState(() {
      _ingredients.add(_IngredientDraft(id: 'ing_${_nextIngredientId++}'));
    });
  }

  void _removeIngredient(int index) {
    HapticFeedback.selectionClick();
    final removed = _ingredients[index];
    setState(() {
      _ingredients.removeAt(index);
      // Drop any step references to the removed ingredient id.
      for (final s in _steps) {
        s.requires.remove(removed.id);
      }
    });
    // Dispose after the frame so any dismissing field doesn't touch it.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _addStep() {
    HapticFeedback.selectionClick();
    setState(() => _steps.add(_StepDraft()));
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() {
        _pickedImage = File(picked.path);
        _removeImage = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not pick image.')));
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
      _imageUrl = null;
      _removeImage = true;
    });
  }

  void _removeStep(int index) {
    HapticFeedback.selectionClick();
    final removed = _steps[index];
    setState(() => _steps.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final valid = _ingredients
        .where((i) => i.nameCtrl.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one ingredient.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final provider = context.read<RecipeProvider>();
    final auth = context.read<AuthProvider>();
    final who = auth.resolvedDisplayName;
    final householdId = auth.householdId;

    final ingredients = valid.map((d) => d.toModel()).toList();
    final validIds = ingredients.map((i) => i.id).toSet();
    final steps = _steps
        .where((s) => s.textCtrl.text.trim().isNotEmpty)
        .map((s) => s.toModel(validIds))
        .toList();

    // Resolve the hero image: upload a newly picked one, keep/clear existing.
    String? imageUrl = _removeImage ? null : _imageUrl;
    try {
      if (_pickedImage != null && householdId != null) {
        final imageId = 'recipe_${DateTime.now().microsecondsSinceEpoch}';
        imageUrl = await _storage.uploadImage(
          householdId: householdId,
          imageId: imageId,
          file: _pickedImage!,
          folder: 'recipes',
        );
        // Delete the previous image if we're replacing one.
        final old = widget.existing?.imageUrl;
        if (old != null && old.isNotEmpty && old != imageUrl) {
          await _storage.deleteByUrl(old);
        }
      } else if (_removeImage) {
        final old = widget.existing?.imageUrl;
        if (old != null && old.isNotEmpty) {
          await _storage.deleteByUrl(old);
        }
      }
    } catch (_) {
      // Non-fatal: save the recipe without blocking on image issues.
    }

    final recipe = Recipe(
      id: widget.existing?.id ?? 'temp',
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      servings: int.tryParse(_servingsCtrl.text.trim()),
      ingredients: ingredients,
      steps: steps,
      isBuiltIn: false,
      createdBy: widget.existing?.createdBy ?? who,
      imageUrl: imageUrl,
    );

    try {
      if (widget.isEditing) {
        await provider.updateRecipe(recipe);
      } else {
        await provider.addRecipe(recipe);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save recipe: $e')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: Text('Remove "${widget.existing!.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<RecipeProvider>().deleteRecipe(widget.existing!.id);
      if (mounted) {
        Navigator.of(context)
          ..pop() // edit screen
          ..pop(); // cook screen, if we came from it
      }
    }
  }

  Future<void> _confirmDiscard() async {
    final hasContent =
        _nameCtrl.text.isNotEmpty ||
        _descCtrl.text.isNotEmpty ||
        _ingredients.any((i) => i.nameCtrl.text.isNotEmpty) ||
        _steps.any((s) => s.textCtrl.text.isNotEmpty);

    if (widget.isEditing || !hasContent) {
      if (mounted) Navigator.maybePop(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard recipe?'),
        content: const Text('All unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        leading: IconButton(
          tooltip: 'Discard and go back',
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : _confirmDiscard,
        ),
        title: Text(
          widget.isEditing ? 'Edit recipe' : 'New recipe',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _saving
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: scheme.primary,
                      ),
                    ),
                  )
                : FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    child: Text(widget.isEditing ? 'Update' : 'Save'),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            const _SectionLabel(
              icon: Icons.restaurant_menu_rounded,
              label: 'Basic info',
            ),
            const SizedBox(height: 12),
            _ImagePickerCard(
              pickedImage: _pickedImage,
              imageUrl: _removeImage ? null : _imageUrl,
              onPick: _showImageSourceSheet,
              onRemove: _removeCurrentImage,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Recipe name',
                hintText: 'e.g. Masala Omelette',
                prefixIcon: Icon(Icons.edit_note_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.subject_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _servingsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Servings (optional)',
                prefixIcon: Icon(Icons.people_alt_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'Enter a valid number';
                return null;
              },
            ),

            const SizedBox(height: 28),
            _SectionLabel(
              icon: Icons.egg_alt_outlined,
              label: 'Ingredients',
              count: _ingredients.length,
            ),
            const SizedBox(height: 12),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ingredients.length,
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _ingredients.removeAt(oldIndex);
                  _ingredients.insert(newIndex, item);
                });
              },
              proxyDecorator: (child, index, animation) => Material(
                elevation: 8,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: child,
              ),
              itemBuilder: (context, index) {
                final ing = _ingredients[index];
                return _IngredientCard(
                  key: ValueKey(ing.id),
                  index: index,
                  draft: ing,
                  onRemove: _ingredients.length > 1
                      ? () => _removeIngredient(index)
                      : null,
                  onToggleOptional: (v) => setState(() => ing.optional = v),
                );
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _AddButton(label: 'Add ingredient', onTap: _addIngredient),
            ),

            const SizedBox(height: 24),
            _SectionLabel(
              icon: Icons.format_list_numbered_rounded,
              label: 'Steps',
              count: _steps.length,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                'Link a step to ingredients so it only shows when those are '
                'selected — great for optional ingredients.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _steps.length,
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _steps.removeAt(oldIndex);
                  _steps.insert(newIndex, item);
                });
              },
              proxyDecorator: (child, index, animation) => Material(
                elevation: 8,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: child,
              ),
              itemBuilder: (context, index) {
                final step = _steps[index];
                return _StepCard(
                  key: ValueKey(step),
                  index: index,
                  draft: step,
                  ingredients: _ingredients,
                  onRemove: _steps.length > 1 ? () => _removeStep(index) : null,
                  onChanged: () => setState(() {}),
                );
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _AddButton(label: 'Add step', onTap: _addStep),
            ),

            const SizedBox(height: 28),
            FilledButton.tonal(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                widget.isEditing ? 'Update recipe' : 'Save recipe',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label, this.count});

  final IconData icon;
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Draft holders (mutable, own their controllers)
// ---------------------------------------------------------------------------

class _IngredientDraft {
  _IngredientDraft({
    required this.id,
    String name = '',
    String quantity = '',
    String unit = '',
    String prep = '',
    this.optional = false,
  }) : nameCtrl = TextEditingController(text: name),
       qtyCtrl = TextEditingController(text: quantity),
       unitCtrl = TextEditingController(text: unit),
       prepCtrl = TextEditingController(text: prep);

  factory _IngredientDraft.fromModel(RecipeIngredient i) => _IngredientDraft(
    id: i.id,
    name: i.name,
    quantity: i.quantity ?? '',
    unit: i.unit ?? '',
    prep: i.prep ?? '',
    optional: i.optional,
  );

  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController unitCtrl;
  final TextEditingController prepCtrl;
  bool optional;

  RecipeIngredient toModel() => RecipeIngredient(
    id: id,
    name: nameCtrl.text.trim(),
    quantity: qtyCtrl.text.trim().isEmpty ? null : qtyCtrl.text.trim(),
    unit: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
    prep: prepCtrl.text.trim().isEmpty ? null : prepCtrl.text.trim(),
    optional: optional,
  );

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    unitCtrl.dispose();
    prepCtrl.dispose();
  }
}

class _StepDraft {
  _StepDraft({
    String text = '',
    Set<String>? requires,
    int? timerSeconds,
    this.optional = false,
  }) : textCtrl = TextEditingController(text: text),
       minutesCtrl = TextEditingController(
         text: (timerSeconds != null && timerSeconds > 0)
             ? (timerSeconds ~/ 60).toString()
             : '',
       ),
       requires = requires ?? {};

  factory _StepDraft.fromModel(RecipeStep s) => _StepDraft(
    text: s.text,
    requires: s.requiresIngredients.toSet(),
    timerSeconds: s.timerSeconds,
    optional: s.optional,
  );

  final TextEditingController textCtrl;
  final TextEditingController minutesCtrl;
  final Set<String> requires;
  bool optional;

  RecipeStep toModel(Set<String> validIds) {
    final mins = int.tryParse(minutesCtrl.text.trim());
    return RecipeStep(
      text: textCtrl.text.trim(),
      requiresIngredients: requires.where(validIds.contains).toList(),
      timerSeconds: (mins != null && mins > 0) ? mins * 60 : null,
      optional: optional,
    );
  }

  void dispose() {
    textCtrl.dispose();
    minutesCtrl.dispose();
  }
}

// ---------------------------------------------------------------------------
// Ingredient card
// ---------------------------------------------------------------------------

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    super.key,
    required this.index,
    required this.draft,
    required this.onToggleOptional,
    this.onRemove,
  });

  final int index;
  final _IngredientDraft draft;
  final ValueChanged<bool> onToggleOptional;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(index: index, label: 'Ingredient', onRemove: onRemove),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  TextFormField(
                    controller: draft.nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Ingredient',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: draft.qtyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: draft.unitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: draft.prepCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prep (e.g. finely chopped) — optional',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _OptionalToggle(
                    value: draft.optional,
                    onChanged: onToggleOptional,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Themed optional toggle whose tint changes when enabled.
class _OptionalToggle extends StatefulWidget {
  const _OptionalToggle({
    required this.value,
    required this.onChanged,
    this.label = 'Optional ingredient',
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  State<_OptionalToggle> createState() => _OptionalToggleState();
}

class _OptionalToggleState extends State<_OptionalToggle> {
  late bool _value = widget.value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _value
            ? scheme.secondaryContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
            size: 18,
            color: _value ? scheme.secondary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _value
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Switch(
            value: _value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step card (with ingredient-requirement chips + timer)
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    required this.index,
    required this.draft,
    required this.ingredients,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final _StepDraft draft;
  final List<_IngredientDraft> ingredients;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final named = ingredients
        .where((i) => i.nameCtrl.text.trim().isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(index: index, label: 'Step', onRemove: onRemove),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: draft.textCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Describe this step',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Step text is required'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          controller: draft.minutesCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Timer (min)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Optional. Leave blank to auto-detect from the '
                            'step text.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _OptionalToggle(
                    label: 'Optional step',
                    value: draft.optional,
                    onChanged: (v) => draft.optional = v,
                  ),
                  if (named.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Only show this step if these are selected:',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final ing in named)
                          FilterChip(
                            label: Text(ing.nameCtrl.text.trim()),
                            selected: draft.requires.contains(ing.id),
                            onSelected: (sel) {
                              if (sel) {
                                draft.requires.add(ing.id);
                              } else {
                                draft.requires.remove(ing.id);
                              }
                              onChanged();
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared card header: numbered bubble, label, drag handle, remove button.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.index, required this.label, this.onRemove});

  final int index;
  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label ${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 20,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove',
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: scheme.error.withValues(alpha: 0.8),
              ),
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// A tappable card for choosing a recipe hero image. Shows a preview (local
/// file or remote url) with a remove button, or an "add photo" placeholder.
class _ImagePickerCard extends StatelessWidget {
  const _ImagePickerCard({
    required this.pickedImage,
    required this.imageUrl,
    required this.onPick,
    required this.onRemove,
  });

  final File? pickedImage;
  final String? imageUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage =
        pickedImage != null || (imageUrl != null && imageUrl!.isNotEmpty);

    return GestureDetector(
      onTap: onPick,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 160,
          width: double.infinity,
          color: scheme.surfaceContainerHighest,
          child: hasImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    if (pickedImage != null)
                      Image.file(pickedImage!, fit: BoxFit.cover)
                    else
                      Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Icon(Icons.broken_image)),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: scheme.surface.withValues(alpha: 0.85),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Remove photo',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onRemove,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 32,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a photo (optional)',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
