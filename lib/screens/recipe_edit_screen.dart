import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../providers/auth_provider.dart';
import '../providers/recipe_provider.dart';

/// Create or edit a household (user) recipe. Built-in recipes are read-only and
/// never reach this screen for editing.
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

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _servingsCtrl = TextEditingController(text: r?.servings?.toString() ?? '');

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
    // Ensure the id counter won't collide with loaded ids.
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
    setState(() {
      _ingredients.add(_IngredientDraft(id: 'ing_${_nextIngredientId++}'));
    });
  }

  void _addStep() {
    setState(() => _steps.add(_StepDraft()));
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

    setState(() => _saving = true);
    final provider = context.read<RecipeProvider>();
    final who = context.read<AuthProvider>().resolvedDisplayName;

    final ingredients = valid.map((d) => d.toModel()).toList();
    final validIds = ingredients.map((i) => i.id).toSet();
    final steps = _steps
        .where((s) => s.textCtrl.text.trim().isNotEmpty)
        .map((s) => s.toModel(validIds))
        .toList();

    final recipe = Recipe(
      id: widget.existing?.id ?? 'temp',
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      servings: int.tryParse(_servingsCtrl.text.trim()),
      ingredients: ingredients,
      steps: steps,
      isBuiltIn: false,
      createdBy: widget.existing?.createdBy ?? who,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit recipe' : 'New recipe'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Recipe name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _servingsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Servings (optional)',
              ),
            ),

            const SizedBox(height: 24),
            _Heading('Ingredients'),
            for (var i = 0; i < _ingredients.length; i++)
              _IngredientEditor(
                key: ValueKey(_ingredients[i].id),
                draft: _ingredients[i],
                onRemove: () => setState(() {
                  _ingredients[i].dispose();
                  _ingredients.removeAt(i);
                }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addIngredient,
                icon: const Icon(Icons.add),
                label: const Text('Add ingredient'),
              ),
            ),

            const SizedBox(height: 16),
            _Heading('Steps'),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Link a step to ingredients so it only shows when those are '
                'selected (great for optional ingredients).',
                style: TextStyle(fontSize: 12),
              ),
            ),
            for (var i = 0; i < _steps.length; i++)
              _StepEditor(
                key: ValueKey(_steps[i]),
                number: i + 1,
                draft: _steps[i],
                ingredients: _ingredients,
                onRemove: () => setState(() {
                  _steps[i].dispose();
                  _steps.removeAt(i);
                }),
                onChanged: () => setState(() {}),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addStep,
                icon: const Icon(Icons.add),
                label: const Text('Add step'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

// --- Draft holders (mutable, own their controllers) ---

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
  _StepDraft({String text = '', Set<String>? requires})
    : textCtrl = TextEditingController(text: text),
      requires = requires ?? {};

  factory _StepDraft.fromModel(RecipeStep s) =>
      _StepDraft(text: s.text, requires: s.requiresIngredients.toSet());

  final TextEditingController textCtrl;
  final Set<String> requires;

  RecipeStep toModel(Set<String> validIds) => RecipeStep(
    text: textCtrl.text.trim(),
    requiresIngredients: requires.where(validIds.contains).toList(),
  );

  void dispose() => textCtrl.dispose();
}

class _IngredientEditor extends StatelessWidget {
  const _IngredientEditor({
    super.key,
    required this.draft,
    required this.onRemove,
  });

  final _IngredientDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Ingredient'),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.qtyCtrl,
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: draft.unitCtrl,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: draft.prepCtrl,
              decoration: const InputDecoration(
                labelText: 'Prep (e.g. finely chopped) — optional',
              ),
            ),
            StatefulBuilder(
              builder: (context, setLocal) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Optional ingredient'),
                value: draft.optional,
                onChanged: (v) => setLocal(() => draft.optional = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepEditor extends StatelessWidget {
  const _StepEditor({
    super.key,
    required this.number,
    required this.draft,
    required this.ingredients,
    required this.onRemove,
    required this.onChanged,
  });

  final int number;
  final _StepDraft draft;
  final List<_IngredientDraft> ingredients;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final named = ingredients
        .where((i) => i.nameCtrl.text.trim().isNotEmpty)
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.textCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'Step $number'),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            if (named.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Only show this step if these are selected:',
                style: TextStyle(fontSize: 12),
              ),
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
    );
  }
}
