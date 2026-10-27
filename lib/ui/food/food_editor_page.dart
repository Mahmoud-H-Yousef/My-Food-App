import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../common.dart';
import '../theme.dart';

/// Create or edit your own food. Values can be typed per 100 g or per serving
/// (as printed on most labels); they're stored per 100 g.
class FoodEditorPage extends StatefulWidget {
  final Food? food;
  final String initialName;
  final String barcode;
  const FoodEditorPage({super.key, this.food, this.initialName = '', this.barcode = ''});

  @override
  State<FoodEditorPage> createState() => _FoodEditorPageState();
}

class _FoodEditorPageState extends State<FoodEditorPage> {
  late final _name = TextEditingController(text: widget.food?.name('en') ?? widget.initialName);
  late final _brand = TextEditingController(text: widget.food?.brand ?? '');
  late final _barcode = TextEditingController(text: widget.food?.barcode ?? widget.barcode);
  final _kcal = TextEditingController(), _p = TextEditingController(), _c = TextEditingController(), _f = TextEditingController();
  final _fiber = TextEditingController(), _sugar = TextEditingController();
  final _servingG = TextEditingController(text: '100');
  bool _perServing = false;
  late final List<Portion> _portions = [...?widget.food?.portions];

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    if (f != null) {
      _kcal.text = fmtNum(f.kcal);
      _p.text = fmtNum(f.p);
      _c.text = fmtNum(f.c);
      _f.text = fmtNum(f.f);
      _fiber.text = fmtNum(f.fiber);
      _sugar.text = fmtNum(f.sugar);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final kcal = parseNum(_kcal.text);
    if (name.isEmpty || kcal == null) {
      toast(context, context.tr('needNameKcal'));
      return;
    }
    final serving = parseNum(_servingG.text) ?? 100;
    final factor = _perServing && serving > 0 ? 100 / serving : 1.0;
    double v(TextEditingController c) => (parseNum(c.text) ?? 0) * factor;
    final portions = [..._portions];
    if (_perServing && serving > 0 && !portions.any((p) => p.grams == serving)) {
      portions.insert(0, Portion(labelEn: '1 serving', labelAr: 'حصة واحدة', grams: serving));
    }
    final old = widget.food;
    final food = Food(
      id: old?.id,
      src: old?.src ?? FoodSource.custom,
      extId: old?.extId ?? '',
      nameEn: name,
      nameAr: name,
      brand: _brand.text.trim(),
      barcode: _barcode.text.trim(),
      kcal: kcal * factor,
      p: v(_p),
      c: v(_c),
      f: v(_f),
      fiber: v(_fiber),
      sugar: v(_sugar),
      fav: old?.fav ?? false,
      uses: old?.uses ?? 0,
      portions: portions,
    );
    final id = await Repo.saveFood(food);
    final saved = await Repo.food(id);
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _addPortion() async {
    final label = TextEditingController();
    final grams = TextEditingController();
    final p = await showDialog<Portion>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('addUnit')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: label, autofocus: true, decoration: InputDecoration(labelText: context.tr('unitName'), hintText: context.tr('unitHint'))),
          const SizedBox(height: 8),
          TextField(controller: grams, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('grams'), suffixText: 'g')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              final g = parseNum(grams.text);
              if (label.text.trim().isEmpty || g == null || g <= 0) return;
              Navigator.pop(ctx, Portion(labelEn: label.text.trim(), labelAr: label.text.trim(), grams: g));
            },
            child: Text(context.tr('add')),
          ),
        ],
      ),
    );
    if (p != null) setState(() => _portions.add(p));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.food != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? context.tr('editFood') : context.tr('createFood')),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.tr('delete'),
              onPressed: () async {
                if (!await confirm(context, context.tr('deleteFoodQ'))) return;
                await Repo.hideFood(widget.food!.id!);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('name'))),
        const SizedBox(height: 12),
        TextField(controller: _brand, decoration: InputDecoration(labelText: context.tr('brandOptional'))),
        const SizedBox(height: 12),
        TextField(controller: _barcode, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('barcodeOptional'))),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(context.tr('per100g'))),
            ButtonSegment(value: true, label: Text(context.tr('perServing'))),
          ],
          selected: {_perServing},
          onSelectionChanged: (s) => setState(() => _perServing = s.first),
        ),
        if (_perServing) ...[
          const SizedBox(height: 12),
          TextField(controller: _servingG, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('servingSize'), suffixText: 'g')),
        ],
        const SizedBox(height: 12),
        TextField(controller: _kcal, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('kcal'))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _numField(_p, context.tr('protein'), proteinColor)),
          const SizedBox(width: 8),
          Expanded(child: _numField(_c, context.tr('carbs'), carbsColor)),
          const SizedBox(width: 8),
          Expanded(child: _numField(_f, context.tr('fat'), fatColor)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _numField(_fiber, context.tr('fiber'), null)),
          const SizedBox(width: 8),
          Expanded(child: _numField(_sugar, context.tr('sugar'), null)),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Text(context.tr('units'), style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(onPressed: _addPortion, icon: const Icon(Icons.add), label: Text(context.tr('addUnit'))),
        ]),
        for (final p in _portions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.label(lang(context))),
            subtitle: Text('${fmtNum(p.grams)} ${context.tr('g')}'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _portions.remove(p))),
          ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: Text(context.tr('save'))),
      ]),
    );
  }

  Widget _numField(TextEditingController c, String label, Color? color) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: 'g', labelStyle: color == null ? null : TextStyle(color: color)),
      );
}
