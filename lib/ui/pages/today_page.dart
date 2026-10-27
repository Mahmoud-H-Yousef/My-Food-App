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
import '../widgets/charts.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => app.setDay(app.day.subtract(const Duration(days: 1)))),
          TextButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: app.day, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null) app.setDay(d);
            },
            child: Text(dayLabel(context, app.day), style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => app.setDay(app.day.add(const Duration(days: 1)))),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: ListTile(leading: const Icon(Icons.content_copy), title: Text(context.tr('copyYesterday')))),
              PopupMenuItem(value: 'copyFrom', child: ListTile(leading: const Icon(Icons.event_repeat), title: Text(context.tr('copyFromDay')))),
              if (app.entries.isNotEmpty)
                PopupMenuItem(value: 'clear', child: ListTile(leading: const Icon(Icons.delete_sweep_outlined), title: Text(context.tr('clearDay')))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAddFood(context, app.suggestedMeal),
        icon: const Icon(Icons.add),
        label: Text(context.tr('addFood')),
      ),
      body: RefreshIndicator(
        onRefresh: app.reload,
        child: ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), children: [
          const _SummaryCard(),
          for (var m = 0; m < 4; m++) _MealCard(meal: m),
          const _WaterCard(),
        ]),
      ),
    );
  }

  Future<void> _menu(BuildContext context, String v) async {
    final app = context.read<AppState>();
    switch (v) {
      case 'copy':
        await Repo.copyDay(dayKey(app.day.subtract(const Duration(days: 1))), app.dayStr);
        await app.changed();
        if (context.mounted) toast(context, context.tr('copied'));
      case 'copyFrom':
        final d = await showDatePicker(
            context: context, initialDate: app.day.subtract(const Duration(days: 1)), firstDate: DateTime(2020), lastDate: DateTime(2100), helpText: context.tr('copyFromDay'));
        if (d == null) return;
        await Repo.copyDay(dayKey(d), app.dayStr);
        await app.changed();
        if (context.mounted) toast(context, context.tr('copied'));
      case 'clear':
        if (!context.mounted || !await confirm(context, context.tr('clearDayQ'))) return;
        for (final e in [...app.entries]) {
          await Repo.deleteEntry(e.id!);
        }
        await app.changed();
    }
  }
}

Future<void> openAddFood(BuildContext context, int meal) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => FoodSearchPage(meal: meal)));

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.targets;
    final eaten = app.eaten;
    final budget = app.budget;
    final left = budget - eaten.kcal;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _side(context, Icons.restaurant, eaten.kcal.round().toString(), context.tr('eaten')),
            Ring(
              value: budget <= 0 ? 0 : eaten.kcal / budget,
              color: brandGreen,
              size: 150,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(left.abs().round().toString(), style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: left < 0 ? cs.error : null)),
                Text(left < 0 ? context.tr('over') : context.tr('left'), style: tt.bodySmall),
              ]),
            ),
            _side(context, Icons.local_fire_department_outlined, app.burnedKcal.toString(), context.tr('burned')),
          ]),
          const SizedBox(height: 4),
          Text(context.tr('goalLine', {'n': '${t.kcal}'}), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (app.steps > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${app.steps} ${context.tr('steps')}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: MacroBar(label: context.tr('protein'), value: eaten.p, target: t.protein.toDouble(), color: proteinColor)),
            const SizedBox(width: 12),
            Expanded(child: MacroBar(label: context.tr('carbs'), value: eaten.c, target: t.carbs.toDouble(), color: carbsColor)),
            const SizedBox(width: 12),
            Expanded(child: MacroBar(label: context.tr('fat'), value: eaten.f, target: t.fat.toDouble(), color: fatColor)),
          ]),
        ]),
      ),
    );
  }

  Widget _side(BuildContext context, IconData icon, String v, String label) => Column(children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(v, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _MealCard extends StatelessWidget {
  final int meal;
  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.mealEntries(meal);
    final total = items.fold(0.0, (a, e) => a + e.kcal);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          leading: Icon(mealIcon(context, meal), color: brandGreen),
          title: Text(mealName(context, meal), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: items.isEmpty ? null : Text('${total.round()} ${context.tr('kcal')}'),
          trailing: IconButton.filledTonal(icon: const Icon(Icons.add), onPressed: () => openAddFood(context, meal)),
        ),
        for (final e in items)
          Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: AlignmentDirectional.centerEnd,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) async {
              await app.deleteEntry(e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(context.tr('deleted')),
                  action: SnackBarAction(label: context.tr('undo'), onPressed: () => app.addEntry(e)),
                ));
              }
            },
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsetsDirectional.only(start: 72, end: 16),
              title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(entryAmount(context, e)),
              trailing: Text('${e.kcal.round()}', style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => editEntry(context, e),
            ),
          ),
        if (items.isNotEmpty) const SizedBox(height: 6),
      ]),
    );
  }
}

String entryAmount(BuildContext context, LogEntry e) {
  if (e.unit.isEmpty) return context.tr('quickAdd');
  if (e.unit == 'g') return '${fmtNum(e.grams)} g';
  return '${fmtNum(e.qty)} × ${e.unit} (${fmtNum(e.grams)} g)';
}

/// Change amount or meal of a logged item.
Future<void> editEntry(BuildContext context, LogEntry e) async {
  final app = context.read<AppState>();
  final food = e.foodId == null ? null : await Repo.food(e.foodId!);
  if (!context.mounted) return;
  if (food == null) {
    final q = await showQuickAddDialog(context, meal: e.meal, day: e.day);
    if (q == null) return;
    await app.deleteEntry(e);
    await app.addEntry(LogEntry(day: e.day, meal: e.meal, name: q.name, grams: 0, unit: '', kcal: q.kcal, p: q.p, c: q.c, f: q.f));
    return;
  }
  final picked = await showAmountSheet(context, food,
      meal: e.meal, initialGrams: e.grams, initialQty: e.qty, initialUnit: e.unit, actionLabel: context.tr('save'));
  if (picked == null || !context.mounted) return;
  final updated = picked.toEntry(e.day, lang(context));
  await app.updateEntry(LogEntry(
    id: e.id,
    day: updated.day,
    meal: updated.meal,
    foodId: updated.foodId,
    name: e.name,
    grams: updated.grams,
    qty: updated.qty,
    unit: updated.unit,
    kcal: updated.kcal,
    p: updated.p,
    c: updated.c,
    f: updated.f,
  ));
}

class _WaterCard extends StatelessWidget {
  const _WaterCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final goal = app.targets.waterMl;
    final glass = app.glassMl;
    final glasses = (goal / glass).ceil().clamp(1, 16);
    final filled = (app.waterMl / glass).floor();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.water_drop_outlined, color: waterColor),
            const SizedBox(width: 8),
            Text(context.tr('water'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${app.waterMl} / $goal ml'),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < glasses; i++)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => app.addWater(i < filled ? -glass : glass),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(i < filled ? Icons.local_drink : Icons.local_drink_outlined,
                      size: 30, color: i < filled ? waterColor : Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(context.tr('glassSize', {'n': '$glass'}), style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: app.waterMl > 0 ? () => app.addWater(-glass) : null),
            IconButton(icon: const Icon(Icons.add_circle, color: waterColor), onPressed: () => app.addWater(glass)),
          ]),
        ]),
      ),
    );
  }
}
