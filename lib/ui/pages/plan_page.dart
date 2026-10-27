import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../food/amount_sheet.dart';
import '../food/food_search_page.dart';
import '../theme.dart';

/// Weekly meal plan and the shopping list made from it.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _shoppingKey = GlobalKey<_ShoppingListState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('tabPlan')),
        actions: [
          IconButton(icon: const Icon(Icons.kitchen_outlined), tooltip: context.tr('whatCanICook'), onPressed: () => showWhatCanICook(context)),
        ],
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(icon: const Icon(Icons.calendar_view_week), text: context.tr('weekPlan')),
          Tab(icon: const Icon(Icons.shopping_cart_outlined), text: context.tr('shoppingList')),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [
        _WeekPlan(onShoppingMade: () {
          _shoppingKey.currentState?.load();
          _tabs.animateTo(1);
        }),
        _ShoppingList(key: _shoppingKey),
      ]),
    );
  }
}

class _WeekPlan extends StatefulWidget {
  final VoidCallback onShoppingMade;
  const _WeekPlan({required this.onShoppingMade});

  @override
  State<_WeekPlan> createState() => _WeekPlanState();
}

class _WeekPlanState extends State<_WeekPlan> {
  late DateTime _weekStart;
  List<PlanItem> _items = [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final first = MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0 = Sunday
      final today = DateUtils.dateOnly(DateTime.now());
      final back = (today.weekday % 7 - first) % 7;
      _weekStart = today.subtract(Duration(days: back));
      _load();
    }
  }

  List<DateTime> get _days => [for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i))];

  Future<void> _load() async {
    final items = await Repo.plan(dayKey(_days.first), dayKey(_days.last));
    if (mounted) setState(() => _items = items);
  }

  void _shift(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
    _load();
  }

  Future<void> _add(DateTime day) async {
    final picked = await Navigator.push<Picked>(
        context, MaterialPageRoute(builder: (_) => FoodSearchPage(pickOnly: true, title: '${context.tr('planFor')} ${dayLabel(context, day)}')));
    if (picked == null) return;
    await Repo.addPlan(PlanItem(
      day: dayKey(day),
      meal: picked.meal,
      foodId: picked.food.id,
      name: picked.food.name(mounted ? lang(context) : 'en'),
      grams: picked.grams,
      qty: picked.qty,
      unit: picked.unit,
      kcal: picked.nutrition.kcal,
    ));
    _load();
  }

  Future<void> _logItems(List<PlanItem> items, String day) async {
    final app = context.read<AppState>();
    for (final it in items) {
      final food = it.foodId == null ? null : await Repo.food(it.foodId!);
      final n = food?.forGrams(it.grams) ?? Nutrition(it.kcal, 0, 0, 0);
      await Repo.addEntry(LogEntry(
        day: day,
        meal: it.meal,
        foodId: it.foodId,
        name: it.name,
        grams: it.grams,
        qty: it.qty,
        unit: it.unit,
        kcal: n.kcal,
        p: n.p,
        c: n.c,
        f: n.f,
      ));
    }
    await app.changed();
    if (mounted) toast(context, context.tr('loggedN', {'n': '${items.length}'}));
  }

  Future<void> _makeShopping() async {
    final totals = <String, double>{};
    final names = <String, String>{};
    void addFood(String name, double grams) {
      final k = normalize(name);
      names[k] = name;
      totals[k] = (totals[k] ?? 0) + grams;
    }

    for (final it in _items) {
      final food = it.foodId == null ? null : await Repo.food(it.foodId!);
      if (food?.recipeId != null) {
        final r = await Repo.recipe(food!.recipeId!);
        if (r != null && r.finalGrams > 0) {
          final share = it.grams / r.finalGrams;
          for (final ing in r.ingredients) {
            addFood(ing.name, ing.grams * share);
          }
          continue;
        }
      }
      addFood(it.name, it.grams);
    }
    if (totals.isEmpty) {
      if (mounted) toast(context, context.tr('planEmpty'));
      return;
    }
    await Repo.clearShopping(onlyGenerated: true);
    for (final k in totals.keys) {
      final g = totals[k]!;
      await Repo.addShopping(names[k]!, g >= 1000 ? '${(g / 1000).toStringAsFixed(1)} kg' : '${(g / 10).ceil() * 10} g', manual: false);
    }
    widget.onShoppingMade();
  }

  @override
  Widget build(BuildContext context) {
    final goal = context.watch<AppState>().targets.kcal;
    final l = lang(context);
    final fmt = DateFormat.MMMd(l);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
          Expanded(
            child: Text('${fmt.format(_days.first)} – ${fmt.format(_days.last)}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _makeShopping, icon: const Icon(Icons.shopping_cart_checkout), label: Text(context.tr('makeShoppingList'))),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: context.tr('clearWeek'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _items.isEmpty
                ? null
                : () async {
                    if (!await confirm(context, context.tr('clearWeekQ'))) return;
                    await Repo.clearPlan(dayKey(_days.first), dayKey(_days.last));
                    _load();
                  },
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: [
          for (final d in _days) _dayCard(context, d, goal),
        ]),
      ),
    ]);
  }

  Widget _dayCard(BuildContext context, DateTime d, int goal) {
    final key = dayKey(d);
    final items = _items.where((i) => i.day == key).toList();
    final total = items.fold(0.0, (a, i) => a + i.kcal);
    final tt = Theme.of(context).textTheme;
    final isToday = DateUtils.isSameDay(d, DateTime.now());
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: isToday ? const BorderSide(color: brandGreen, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          title: Text(DateFormat.EEEE(lang(context)).format(d), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(items.isEmpty
              ? DateFormat.MMMd(lang(context)).format(d)
              : '${total.round()} / $goal ${context.tr('kcal')}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (items.isNotEmpty)
              IconButton(icon: const Icon(Icons.playlist_add_check), tooltip: context.tr('logDay'), onPressed: () => _logItems(items, key)),
            IconButton.filledTonal(icon: const Icon(Icons.add), onPressed: () => _add(d)),
          ]),
        ),
        for (var m = 0; m < 4; m++)
          for (final it in items.where((i) => i.meal == m))
            ListTile(
              dense: true,
              leading: Icon(mealIcon(context, m), size: 18),
              title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(it.unit == 'g' ? '${fmtNum(it.grams)} g' : '${fmtNum(it.qty)} × ${it.unit}', style: tt.bodySmall),
              trailing: Text('${it.kcal.round()}'),
              onTap: () => _itemMenu(it),
            ),
        if (items.isNotEmpty) const SizedBox(height: 6),
      ]),
    );
  }

  Future<void> _itemMenu(PlanItem it) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.check), title: Text(context.tr('logIt')), onTap: () => Navigator.pop(c, 'log')),
          ListTile(leading: const Icon(Icons.delete_outline), title: Text(context.tr('delete')), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (v == 'log') await _logItems([it], it.day);
    if (v == 'delete') {
      await Repo.deletePlan(it.id!);
      _load();
    }
  }
}

class _ShoppingList extends StatefulWidget {
  const _ShoppingList({super.key});

  @override
  State<_ShoppingList> createState() => _ShoppingListState();
}

class _ShoppingListState extends State<_ShoppingList> {
  List<ShoppingItem> _items = [];
  final _add = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final items = await Repo.shopping();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _addItem() async {
    final t = _add.text.trim();
    if (t.isEmpty) return;
    await Repo.addShopping(t, '');
    _add.clear();
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _add,
              decoration: InputDecoration(hintText: context.tr('addItemHint'), prefixIcon: const Icon(Icons.add_shopping_cart)),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _addItem),
        ]),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(context.tr('copyList')),
          onPressed: _items.isEmpty
              ? null
              : () {
                  final text = _items.where((i) => !i.checked).map((i) => '- ${i.name}${i.amount.isEmpty ? '' : ' (${i.amount})'}').join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  toast(context, context.tr('copied'));
                },
        ),
        TextButton.icon(
          icon: const Icon(Icons.remove_done, size: 18),
          label: Text(context.tr('clearChecked')),
          onPressed: _items.any((i) => i.checked)
              ? () async {
                  await Repo.clearShopping(onlyChecked: true);
                  load();
                }
              : null,
        ),
        const SizedBox(width: 8),
      ]),
      Expanded(
        child: _items.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(context.tr('shoppingEmpty'), textAlign: TextAlign.center)))
            : ListView(children: [
                for (final i in _items)
                  Dismissible(
                    key: ValueKey(i.id),
                    onDismissed: (_) async {
                      await Repo.deleteShopping(i.id!);
                      load();
                    },
                    child: CheckboxListTile(
                      value: i.checked,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(i.name, style: TextStyle(decoration: i.checked ? TextDecoration.lineThrough : null)),
                      subtitle: i.amount.isEmpty ? null : Text(i.amount),
                      onChanged: (v) async {
                        await Repo.setShoppingChecked(i.id!, v ?? false);
                        load();
                      },
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

/// Pick what's in your kitchen; your saved recipes are ranked by how much of them you can make.
Future<void> showWhatCanICook(BuildContext context) async {
  final recipes = await Repo.recipes();
  if (!context.mounted) return;
  if (recipes.isEmpty) {
    toast(context, context.tr('noRecipesYet'));
    return;
  }
  final all = <String, String>{};
  for (final r in recipes) {
    for (final i in r.ingredients) {
      all.putIfAbsent(normalize(i.name), () => i.name);
    }
  }
  final have = <String>{};
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      double score(Recipe r) {
        if (r.ingredients.isEmpty) return 0;
        final n = r.ingredients.where((i) => have.contains(normalize(i.name))).length;
        return n / r.ingredients.length;
      }

      final ranked = [...recipes]..sort((a, b) => score(b).compareTo(score(a)));
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
          Text(context.tr('whatCanICook'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(context.tr('whatCanICookHelp')),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in all.entries)
              FilterChip(
                label: Text(e.value),
                selected: have.contains(e.key),
                onSelected: (v) => setState(() => v ? have.add(e.key) : have.remove(e.key)),
              ),
          ]),
          const Divider(height: 32),
          for (final r in ranked)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${(score(r) * 100).round()}%', style: const TextStyle(fontSize: 12))),
              title: Text(r.name),
              subtitle: Text(r.ingredients.where((i) => !have.contains(normalize(i.name))).map((i) => i.name).join(', ').let(
                    (missing) => missing.isEmpty ? context.tr('youHaveAll') : '${context.tr('missing')}: $missing',
                  )),
            ),
        ]),
      );
    }),
  );
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
