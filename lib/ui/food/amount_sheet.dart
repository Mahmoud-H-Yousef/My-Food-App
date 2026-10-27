import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../common.dart';
import '../theme.dart';

/// What the user chose in the amount sheet.
class Picked {
  final Food food;
  final double grams;
  final double qty;
  final String unit;
  final int meal;
  const Picked(this.food, this.grams, this.qty, this.unit, this.meal);

  Nutrition get nutrition => food.forGrams(grams);

  LogEntry toEntry(String day, String lang) {
    final n = nutrition;
    return LogEntry(
      day: day,
      meal: meal,
      foodId: food.id,
      name: food.name(lang),
      grams: grams,
      qty: qty,
      unit: unit,
      kcal: n.kcal,
      p: n.p,
      c: n.c,
      f: n.f,
    );
  }
}

/// Bottom sheet for choosing how much of a food: unit, quantity, meal.
/// [showMeal] hides the meal chips when adding a recipe ingredient.
Future<Picked?> showAmountSheet(
  BuildContext context,
  Food food, {
  int meal = 0,
  bool showMeal = true,
  double? initialGrams,
  double? initialQty,
  String? initialUnit,
  String? actionLabel,
}) {
  return showModalBottomSheet<Picked>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AmountSheet(
      food: food,
      meal: meal,
      showMeal: showMeal,
      initialGrams: initialGrams,
      initialQty: initialQty,
      initialUnit: initialUnit,
      actionLabel: actionLabel,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  final Food food;
  final int meal;
  final bool showMeal;
  final double? initialGrams, initialQty;
  final String? initialUnit;
  final String? actionLabel;
  const _AmountSheet({required this.food, required this.meal, required this.showMeal, this.initialGrams, this.initialQty, this.initialUnit, this.actionLabel});

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late List<Portion> _portions;
  late Portion _portion;
  late double _qty;
  late int _meal = widget.meal;
  late bool _fav = widget.food.fav;
  final _qtyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _portions = [...widget.food.allPortions];
    if (widget.initialUnit != null) {
      _portion = _portions.firstWhere((p) => p.labelEn == widget.initialUnit || p.labelAr == widget.initialUnit, orElse: () => Portion.gram);
      _qty = _portion.grams == 1 ? (widget.initialGrams ?? 100) : (widget.initialQty ?? 1);
    } else {
      _portion = _portions.first;
      _qty = _portion.grams == 1 ? 100 : 1;
    }
    _qtyCtl.text = fmtNum(_qty);
  }

  // Recipes also offer "Whole pot", so a shared pot can be split by people.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPot();
  }

  bool _potLoaded = false;
  Future<void> _loadPot() async {
    if (_potLoaded || widget.food.recipeId == null) return;
    _potLoaded = true;
    final r = await Repo.recipe(widget.food.recipeId!);
    if (r == null || !mounted || r.finalGrams <= 0) return;
    setState(() => _portions.insert(_portions.length - 1, Portion(id: -2, labelEn: 'Whole pot', labelAr: 'القدر كله', grams: r.finalGrams)));
  }

  @override
  void dispose() {
    _qtyCtl.dispose();
    super.dispose();
  }

  double get _grams => _qty * _portion.grams;

  void _setQty(double v) {
    setState(() => _qty = v < 0 ? 0 : v);
    _qtyCtl.text = fmtNum(_qty);
  }

  Future<void> _splitPot() async {
    final pot = _portions.where((p) => p.id == -2).firstOrNull;
    if (pot == null) return;
    final s = await promptText(context, context.tr('splitPotQ'), initial: '4', keyboard: TextInputType.number);
    final n = parseNum(s ?? '');
    if (n == null || n <= 0) return;
    setState(() {
      _portion = pot;
      _qty = 1 / n;
    });
    _qtyCtl.text = (1 / n).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final l = lang(context);
    final f = widget.food;
    final n = f.forGrams(_grams);
    final t = Theme.of(context).textTheme;
    final step = _portion.grams == 1 ? 10.0 : (_qty < 1 ? 0.25 : 0.5);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.name(l), style: t.titleLarge),
                if (f.brand.isNotEmpty) Text(f.brand, style: t.bodySmall),
                Text('${fmtNum(f.kcal)} ${context.tr('kcal')} / 100 g', style: t.bodySmall),
              ]),
            ),
            if (f.id != null)
              IconButton(
                icon: Icon(_fav ? Icons.star : Icons.star_border, color: _fav ? Colors.amber : null),
                tooltip: context.tr('favorite'),
                onPressed: () async {
                  setState(() => _fav = !_fav);
                  await Repo.setFav(f.id!, _fav);
                },
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            IconButton.filledTonal(onPressed: () => _setQty(_qty - step), icon: const Icon(Icons.remove)),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _qtyCtl,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (s) => setState(() => _qty = parseNum(s) ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: () => _setQty(_qty + step), icon: const Icon(Icons.add)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<Portion>(
                key: ValueKey('${_portions.length}-${_portions.indexOf(_portion)}'),
                initialValue: _portion,
                isExpanded: true,
                items: [
                  for (final p in _portions)
                    DropdownMenuItem(
                      value: p,
                      child: Text(p.grams == 1 ? p.label(l) : '${p.label(l)} (${fmtNum(p.grams)} g)', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (p) {
                  if (p == null) return;
                  final wasGrams = _portion.grams == 1;
                  setState(() => _portion = p);
                  if (p.grams == 1 && !wasGrams) _setQty(100);
                  if (p.grams != 1 && wasGrams) _setQty(1);
                },
              ),
            ),
          ]),
          if (_portions.any((p) => p.id == -2))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(onPressed: _splitPot, icon: const Icon(Icons.groups_outlined), label: Text(context.tr('splitPot'))),
            ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat(context, fmtNum(n.kcal), context.tr('kcal'), Theme.of(context).colorScheme.primary),
                _stat(context, '${fmtNum(n.p)}g', context.tr('protein'), proteinColor),
                _stat(context, '${fmtNum(n.c)}g', context.tr('carbs'), carbsColor),
                _stat(context, '${fmtNum(n.f)}g', context.tr('fat'), fatColor),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('= ${fmtNum(_grams)} g', style: t.bodySmall, textAlign: TextAlign.end),
          ),
          if (widget.showMeal) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (var m = 0; m < 4; m++)
                ChoiceChip(
                  label: Text(mealName(context, m)),
                  avatar: Icon(mealIcon(context, m), size: 18),
                  selected: _meal == m,
                  onSelected: (_) => setState(() => _meal = m),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _grams <= 0
                ? null
                : () => Navigator.pop(context, Picked(f, _grams, _portion.grams == 1 ? _grams : _qty, _portion.grams == 1 ? 'g' : _portion.label(l), _meal)),
            icon: const Icon(Icons.check),
            label: Text(widget.actionLabel ?? context.tr('add')),
          ),
        ]),
      ),
    );
  }

  Widget _stat(BuildContext context, String v, String label, Color color) => Column(children: [
        Text(v, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
