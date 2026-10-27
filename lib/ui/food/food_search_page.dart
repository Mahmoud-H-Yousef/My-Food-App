import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'amount_sheet.dart';
import 'food_editor_page.dart';

/// Search and pick a food. With [pickOnly] the page returns the [Picked]
/// amount instead of logging it (used for recipe ingredients and the plan).
class FoodSearchPage extends StatefulWidget {
  final int meal;
  final bool pickOnly;
  final bool showMeal;
  final String? title;
  const FoodSearchPage({super.key, this.meal = 0, this.pickOnly = false, this.showMeal = true, this.title});

  @override
  State<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends State<FoodSearchPage> with SingleTickerProviderStateMixin {
  final _q = TextEditingController();
  late final _tabs = TabController(length: 3, vsync: this);
  Timer? _debounce;
  List<Food>? _results;
  List<Food> _recent = [], _favs = [], _mine = [];

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    final r = await Repo.recent();
    final f = await Repo.favorites();
    final m = await Repo.mine();
    if (!mounted) return;
    setState(() {
      _recent = r;
      _favs = f;
      _mine = m;
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _tabs.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String s) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (s.trim().isEmpty) {
        setState(() => _results = null);
        return;
      }
      final r = await Repo.search(s);
      if (mounted && _q.text == s) setState(() => _results = r);
    });
  }

  Future<void> _pick(Food food) async {
    final app = context.read<AppState>();
    final picked = await showAmountSheet(context, food,
        meal: widget.meal, showMeal: widget.showMeal, actionLabel: widget.pickOnly ? context.tr('choose') : null);
    if (picked == null || !mounted) return;
    if (widget.pickOnly) {
      Navigator.pop(context, picked);
      return;
    }
    await app.addEntry(picked.toEntry(app.dayStr, lang(context)));
    if (!mounted) return;
    toast(context, context.tr('addedTo', {'meal': mealName(context, picked.meal)}));
    Navigator.pop(context, picked);
  }

  Future<void> _quickAdd() async {
    final app = context.read<AppState>();
    final e = await showQuickAddDialog(context, meal: widget.meal, day: app.dayStr);
    if (e == null || !mounted) return;
    await app.addEntry(e);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _createFood() async {
    final food = await Navigator.push<Food>(context, MaterialPageRoute(builder: (_) => FoodEditorPage(initialName: _q.text)));
    if (food == null || !mounted) return;
    await _loadLists();
    if (mounted) _pick(food);
  }

  @override
  Widget build(BuildContext context) {
    final searching = _results != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (widget.pickOnly ? context.tr('chooseFood') : context.tr('addTo', {'meal': mealName(context, widget.meal)}))),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(searching ? 64 : 112),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SearchBar(
                controller: _q,
                autoFocus: true,
                hintText: context.tr('searchHint'),
                leading: const Icon(Icons.search),
                trailing: [
                  if (_q.text.isNotEmpty)
                    IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _q.clear();
                          _onQuery('');
                        }),
                ],
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (s) {
                  setState(() {});
                  _onQuery(s);
                },
              ),
            ),
            if (!searching)
              TabBar(controller: _tabs, tabs: [
                Tab(text: context.tr('recent')),
                Tab(text: context.tr('favorites')),
                Tab(text: context.tr('myFoods')),
              ]),
          ]),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            if (!widget.pickOnly) ...[
              Expanded(child: OutlinedButton.icon(onPressed: _quickAdd, icon: const Icon(Icons.bolt), label: Text(context.tr('quickAdd')))),
              const SizedBox(width: 8),
            ],
            Expanded(child: OutlinedButton.icon(onPressed: _createFood, icon: const Icon(Icons.add), label: Text(context.tr('createFood')))),
          ]),
        ),
        Expanded(
          child: searching
              ? _list(_results!, empty: context.tr('noResults'))
              : TabBarView(controller: _tabs, children: [
                  _list(_recent, empty: context.tr('noRecent')),
                  _list(_favs, empty: context.tr('noFavorites')),
                  _list(_mine, empty: context.tr('noMyFoods')),
                ]),
        ),
      ]),
    );
  }

  Widget _list(List<Food> foods, {required String empty}) {
    if (foods.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center)));
    }
    final l = lang(context);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: foods.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, i) {
        final f = foods[i];
        final portion = f.portions.isNotEmpty ? f.portions.first : null;
        final sub = portion == null
            ? '${fmtNum(f.kcal)} ${context.tr('kcal')} · 100 g'
            : '${fmtNum(f.kcal * portion.grams / 100)} ${context.tr('kcal')} · ${portion.label(l)}';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _srcColor(f.src).withValues(alpha: 0.15),
            child: Icon(_srcIcon(f.src), color: _srcColor(f.src), size: 20),
          ),
          title: Text(f.name(l), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([if (f.brand.isNotEmpty) f.brand, sub].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: f.fav ? const Icon(Icons.star, color: Colors.amber, size: 18) : null,
          onTap: () => _pick(f),
          onLongPress: f.src == FoodSource.custom || f.src == FoodSource.barcode ? () => _editFood(f) : null,
        );
      },
    );
  }

  Future<void> _editFood(Food f) async {
    await Navigator.push<Food>(context, MaterialPageRoute(builder: (_) => FoodEditorPage(food: f)));
    await _loadLists();
    if (_q.text.isNotEmpty) _onQuery(_q.text);
  }

  IconData _srcIcon(String src) => switch (src) {
        FoodSource.recipe => Icons.soup_kitchen,
        FoodSource.custom => Icons.edit_note,
        FoodSource.barcode => Icons.qr_code,
        FoodSource.world => Icons.restaurant,
        _ => Icons.eco_outlined,
      };

  Color _srcColor(String src) => switch (src) {
        FoodSource.recipe => Colors.deepOrange,
        FoodSource.custom => Colors.purple,
        FoodSource.barcode => Colors.blueGrey,
        FoodSource.world => brandGreen,
        _ => Colors.teal,
      };
}

/// Log calories without picking a food.
Future<LogEntry?> showQuickAddDialog(BuildContext context, {required int meal, required String day}) {
  final name = TextEditingController();
  final kcal = TextEditingController();
  final p = TextEditingController(), c = TextEditingController(), f = TextEditingController();
  return showDialog<LogEntry>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.tr('quickAdd')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: context.tr('nameOptional'))),
          const SizedBox(height: 8),
          TextField(controller: kcal, autofocus: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('kcal'))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${context.tr('protein')} g'))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${context.tr('carbs')} g'))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: f, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${context.tr('fat')} g'))),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: () {
            final k = parseNum(kcal.text);
            if (k == null) return;
            Navigator.pop(
                ctx,
                LogEntry(
                  day: day,
                  meal: meal,
                  name: name.text.trim().isEmpty ? context.tr('quickAdd') : name.text.trim(),
                  grams: 0,
                  qty: 1,
                  unit: '',
                  kcal: k,
                  p: parseNum(p.text) ?? 0,
                  c: parseNum(c.text) ?? 0,
                  f: parseNum(f.text) ?? 0,
                ));
          },
          child: Text(context.tr('add')),
        ),
      ],
    ),
  );
}
