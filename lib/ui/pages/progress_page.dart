import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../../services/health_sync.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';

const _kgPerLb = 0.45359237;

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  List<WeightEntry> _weights = [];
  Map<String, Nutrition> _totals = {};
  int _range = 7;
  int _days = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final w = await Repo.weights();
    final t = await Repo.totals(dayKey(today.subtract(Duration(days: _range - 1))), dayKey(today));
    final d = await Repo.loggedDays();
    if (mounted) {
      setState(() {
        _weights = w;
        _totals = t;
        _days = d;
      });
    }
  }

  Future<void> _addWeight() async {
    final app = context.read<AppState>();
    final last = _weights.isNotEmpty ? _weights.last.kg : (app.profile?.weightKg ?? 70);
    final shown = app.imperial ? last / _kgPerLb : last;
    final s = await promptText(context, context.tr('logWeight'),
        initial: shown.toStringAsFixed(1), keyboard: const TextInputType.numberWithOptions(decimal: true));
    final v = parseNum(s ?? '');
    if (v == null || v <= 0) return;
    final kg = app.imperial ? v * _kgPerLb : v;
    await Repo.setWeight(dayKey(DateTime.now()), kg);
    HealthSync.instance.writeWeight(app, dayKey(DateTime.now()), kg);
    final p = app.profile;
    if (p != null) {
      p.weightKg = kg;
      await app.saveProfile(p);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>(); // refresh when diary changes
    final app = context.read<AppState>();
    final tt = Theme.of(context).textTheme;
    final unit = app.imperial ? 'lb' : 'kg';
    double show(double kg) => app.imperial ? kg / _kgPerLb : kg;
    final logged = _totals.values.where((n) => n.kcal > 0).toList();
    final avg = logged.isEmpty ? 0 : logged.fold(0.0, (a, n) => a + n.kcal) / logged.length;
    final p = app.profile;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('tabProgress'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'weight',
        onPressed: _addWeight,
        icon: const Icon(Icons.monitor_weight_outlined),
        label: Text(context.tr('logWeight')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(context.tr('weight'), style: tt.titleMedium),
                  const Spacer(),
                  if (_weights.isNotEmpty) Text('${show(_weights.last.kg).toStringAsFixed(1)} $unit', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                if (_weights.length >= 2)
                  Text(_changeText(context, show(_weights.last.kg) - show(_weights.first.kg), unit), style: tt.bodySmall),
                const SizedBox(height: 16),
                SizedBox(height: 180, child: _weights.length < 2 ? Center(child: Text(context.tr('weightChartEmpty'), textAlign: TextAlign.center)) : _weightChart(show)),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(context.tr('calories'), style: tt.titleMedium)),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 7, label: Text(context.tr('days7'))),
                      ButtonSegment(value: 30, label: Text(context.tr('days30'))),
                    ],
                    selected: {_range},
                    onSelectionChanged: (s) {
                      setState(() => _range = s.first);
                      _load();
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                SizedBox(height: 180, child: _calorieChart(app.targets.kcal)),
                const SizedBox(height: 8),
                Text(context.tr('avgKcal', {'n': '${avg.round()}'}), style: tt.bodyMedium),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat(context, '$_days', context.tr('daysLogged')),
                if (p != null) _stat(context, p.bmi.toStringAsFixed(1), 'BMI'),
                if (p != null) _stat(context, '${p.tdee.round()}', context.tr('maintenance')),
              ]),
            ),
          ),
          if (_weights.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final w in _weights.reversed.take(30))
                  ListTile(
                    dense: true,
                    title: Text(DateFormat.yMMMEd(lang(context)).format(parseDay(w.day))),
                    trailing: Text('${show(w.kg).toStringAsFixed(1)} $unit'),
                    onLongPress: () async {
                      if (!await confirm(context, context.tr('deleteQ'))) return;
                      await Repo.deleteWeight(w.day);
                      _load();
                    },
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  String _changeText(BuildContext context, double diff, String unit) {
    final sign = diff > 0 ? '+' : '';
    return context.tr('sinceStart', {'n': '$sign${diff.toStringAsFixed(1)} $unit'});
  }

  Widget _stat(BuildContext context, String v, String label) => Column(children: [
        Text(v, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);

  Widget _weightChart(double Function(double) show) {
    final first = parseDay(_weights.first.day);
    final spots = [for (final w in _weights) FlSpot(parseDay(w.day).difference(first).inDays.toDouble(), show(w.kg))];
    final ys = spots.map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = ys.reduce((a, b) => a > b ? a : b) + 1;
    final cs = Theme.of(context).colorScheme;
    return LineChart(LineChartData(
      minY: minY.floorToDouble(),
      maxY: maxY.ceilToDouble(),
      gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: 0.5)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: (spots.last.x / 4).clamp(1, 1000).toDouble(),
            getTitlesWidget: (v, _) => Text(DateFormat.Md(lang(context)).format(first.add(Duration(days: v.round()))), style: const TextStyle(fontSize: 10)),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v.round().toString(), style: const TextStyle(fontSize: 10))),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: brandGreen,
          barWidth: 3,
          dotData: FlDotData(show: spots.length < 20),
          belowBarData: BarAreaData(show: true, color: brandGreen.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }

  Widget _calorieChart(int goal) {
    final today = DateUtils.dateOnly(DateTime.now());
    final cs = Theme.of(context).colorScheme;
    final groups = <BarChartGroupData>[];
    var maxY = goal * 1.2;
    for (var i = 0; i < _range; i++) {
      final d = today.subtract(Duration(days: _range - 1 - i));
      final k = _totals[dayKey(d)]?.kcal ?? 0;
      if (k > maxY) maxY = k * 1.1;
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: k,
          width: _range == 7 ? 18 : 6,
          borderRadius: BorderRadius.circular(4),
          color: k > goal ? cs.error : brandGreen,
        ),
      ]));
    }
    return BarChart(BarChartData(
      maxY: maxY,
      barGroups: groups,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: 0.5)),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: goal.toDouble(), color: cs.primary, strokeWidth: 1.5, dashArray: [6, 4]),
      ]),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text(v.round().toString(), style: const TextStyle(fontSize: 10))),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, _) {
              final d = today.subtract(Duration(days: _range - 1 - v.toInt()));
              if (_range == 30 && v.toInt() % 5 != 4) return const SizedBox.shrink();
              return Text(_range == 7 ? DateFormat.E(lang(context)).format(d) : DateFormat.d().format(d), style: const TextStyle(fontSize: 10));
            },
          ),
        ),
      ),
    ));
  }
}
