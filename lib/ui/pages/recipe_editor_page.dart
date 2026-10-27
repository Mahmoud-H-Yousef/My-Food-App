import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../food/amount_sheet.dart';
import '../food/food_search_page.dart';
import '../theme.dart';

/// Build a pot: ingredients in, optional cooked weight, units such as ladle or plate.
class RecipeEditorPage extends StatefulWidget {
  final Recipe? recipe;
  const RecipeEditorPage({super.key, this.recipe});

  @override
  State<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends State<RecipeEditorPage> {
  late final _name = TextEditingController(text: widget.recipe?.name ?? '');
  late final _cooked = TextEditingController(text: widget.recipe?.cookedGrams == null ? '' : fmtNum(widget.recipe!.cookedGrams!));
  late final _servings = TextEditingController(text: fmtNum(widget.recipe?.servings ?? 4));
  late final _notes = TextEditingController(text: widget.recipe?.notes ?? '');
  late final List<Ingredient> _ingredients = [...?widget.recipe?.ingredients];
  // Custom units, without the automatic "1 serving" one.
  late final List<Portion> _units = [...?widget.recipe?.units.where((u) => u.labelEn != '1 serving')];

  Recipe get _draft => Recipe(
        id: widget.recipe?.id,
        name: _name.text.trim(),
        cookedGrams: parseNum(_cooked.text),
        servings: (parseNum(_servings.text) ?? 1).clamp(0.1, 1000).toDouble(),
        notes: _notes.text.trim(),
        foodId: widget.recipe?.foodId,
        ingredients: _ingredients,
        units: [
          if ((parseNum(_servings.text) ?? 0) > 0) ...[
            Portion(labelEn: '1 serving', labelAr: 'حصة واحدة', grams: _servingGrams),
          ],
          ..._units,
        ],
      );

  double get _servingGrams {
    final d = Recipe(cookedGrams: parseNum(_cooked.text), ingredients: _ingredients, name: '');
    final s = parseNum(_servings.text) ?? 1;
    return s <= 0 ? d.finalGrams : d.finalGrams / s;
  }

  Future<void> _addIngredient() async {
    final picked = await Navigator.push<Picked>(
        context, MaterialPageRoute(builder: (_) => FoodSearchPage(pickOnly: true, showMeal: false, title: context.tr('addIngredient'))));
    if (picked == null || !mounted) return;
    setState(() => _ingredients.add(Ingredient(
          foodId: picked.food.id,
          name: picked.food.name(lang(context)),
          grams: picked.grams,
          qty: picked.qty,
          unit: picked.unit,
          n: picked.nutrition,
        )));
  }

  Future<void> _editIngredient(int i) async {
    final ing = _ingredients[i];
    final food = ing.foodId == null ? null : await Repo.food(ing.foodId!);
    if (food == null || !mounted) return;
    final picked = await showAmountSheet(context, food,
        showMeal: false, initialGrams: ing.grams, initialQty: ing.qty, initialUnit: ing.unit, actionLabel: context.tr('save'));
    if (picked == null) return;
    setState(() => _ingredients[i] = Ingredient(foodId: food.id, name: ing.name, grams: picked.grams, qty: picked.qty, unit: picked.unit, n: picked.nutrition));
  }

  Future<void> _addUnit() async {
    final label = TextEditingController();
    final grams = TextEditingController();
    final p = await showDialog<Portion>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('addUnit')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, children: [
            for (final s in [context.tr('unitLadle'), context.tr('unitPlate'), context.tr('unitBowl'), context.tr('unitPiece'), context.tr('unitCup')])
              ActionChip(label: Text(s), onPressed: () => label.text = s),
          ]),
          const SizedBox(height: 8),
          TextField(controller: label, decoration: InputDecoration(labelText: context.tr('unitName'))),
          const SizedBox(height: 8),
          TextField(
            controller: grams,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('unitWeight'), suffixText: 'g', helperText: context.tr('unitWeightHelp'), helperMaxLines: 3),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              final g = parseNum(grams.text);
              if (label.text.trim().isEmpty || g == null || g <= 0) return;
              Navigator.pop(ctx, Portion(labelEn: '1 ${label.text.trim()}', labelAr: '1 ${label.text.trim()}', grams: g));
            },
            child: Text(context.tr('add')),
          ),
        ],
      ),
    );
    if (p != null) setState(() => _units.add(p));
  }

  Future<void> _save() async {
    final r = _draft;
    if (r.name.isEmpty) {
      toast(context, context.tr('needName'));
      return;
    }
    if (r.ingredients.isEmpty) {
      toast(context, context.tr('needIngredients'));
      return;
    }
    await Repo.saveRecipe(r);
    if (!mounted) return;
    context.read<AppState>().touch();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = _draft;
    final total = r.total;
    final per = r.per100;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? context.tr('newPot') : context.tr('editPot')),
        actions: [
          if (widget.recipe != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, context.tr('deletePotQ'))) return;
                await Repo.deleteRecipe(widget.recipe!);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('potName'), hintText: context.tr('potNameHint')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text(context.tr('step1Ingredients'), style: tt.titleMedium)),
          FilledButton.tonalIcon(onPressed: _addIngredient, icon: const Icon(Icons.add), label: Text(context.tr('add'))),
        ]),
        const SizedBox(height: 4),
        if (_ingredients.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(context.tr('ingredientsHint'), style: TextStyle(color: cs.onSurfaceVariant))),
        for (var i = 0; i < _ingredients.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_ingredients[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_ingredients[i].unit == 'g'
                ? '${fmtNum(_ingredients[i].grams)} g'
                : '${fmtNum(_ingredients[i].qty)} × ${_ingredients[i].unit} (${fmtNum(_ingredients[i].grams)} g)'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${_ingredients[i].n.kcal.round()} ${context.tr('kcal')}'),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _ingredients.removeAt(i))),
            ]),
            onTap: () => _editIngredient(i),
          ),
        if (_ingredients.isNotEmpty)
          Text(context.tr('potTotal', {'kcal': '${total.kcal.round()}', 'g': fmtNum(r.rawGrams)}), style: tt.bodySmall),
        const SizedBox(height: 24),
        Text(context.tr('step2Cooked'), style: tt.titleMedium),
        const SizedBox(height: 4),
        Text(context.tr('cookedHelp'), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        TextField(
          controller: _cooked,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.tr('cookedWeight'), suffixText: 'g'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        Text(context.tr('step3Units'), style: tt.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _servings,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.tr('servingsCount'), helperText: context.tr('servingsHelp')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        for (final u in _units)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.straighten),
            title: Text(u.label(lang(context))),
            subtitle: Text('${fmtNum(u.grams)} g · ${fmtNum(per.kcal * u.grams / 100)} ${context.tr('kcal')}'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _units.remove(u))),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(onPressed: _addUnit, icon: const Icon(Icons.add), label: Text(context.tr('addUnitLadle'))),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('result'), style: tt.titleMedium?.copyWith(color: cs.onPrimaryContainer)),
              const SizedBox(height: 8),
              _resultRow(context, '100 g', per.kcal, per),
              if ((parseNum(_servings.text) ?? 0) > 0) _resultRow(context, '${context.tr('serving')} (${fmtNum(_servingGrams)} g)', per.kcal * _servingGrams / 100, per.scale(_servingGrams / 100)),
              for (final u in _units) _resultRow(context, u.label(lang(context)), per.kcal * u.grams / 100, per.scale(u.grams / 100)),
              _resultRow(context, context.tr('wholePot'), total.kcal, total),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: _notes, maxLines: 3, decoration: InputDecoration(labelText: context.tr('notesOptional'))),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(context.tr('save'))),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _resultRow(BuildContext context, String label, double kcal, Nutrition n) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: cs.onPrimaryContainer))),
        Text('${kcal.round()} ${context.tr('kcal')}', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text('P${n.p.round()} C${n.c.round()} F${n.f.round()}', style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12)),
      ]),
    );
  }
}
