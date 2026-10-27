import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../logic/profile.dart';
import '../theme.dart';

const _kgPerLb = 0.45359237;
const _cmPerIn = 2.54;

/// Sex, age, height, weight and activity. Edits [profile] in place.
class ProfileBodyForm extends StatelessWidget {
  final Profile profile;
  final bool imperial;
  final VoidCallback onChanged;
  const ProfileBodyForm({super.key, required this.profile, required this.imperial, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final heightShown = imperial ? p.heightCm / _cmPerIn : p.heightCm;
    final weightShown = imperial ? p.weightKg / _kgPerLb : p.weightKg;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<Sex>(
        segments: [
          ButtonSegment(value: Sex.male, label: Text(context.tr('male')), icon: const Icon(Icons.male)),
          ButtonSegment(value: Sex.female, label: Text(context.tr('female')), icon: const Icon(Icons.female)),
        ],
        selected: {p.sex},
        onSelectionChanged: (s) {
          p.sex = s.first;
          onChanged();
        },
      ),
      const SizedBox(height: 16),
      _NumberField(
        label: context.tr('age'),
        value: p.age.toDouble(),
        suffix: context.tr('years'),
        onChanged: (v) {
          p.age = v.round().clamp(10, 100);
          onChanged();
        },
      ),
      const SizedBox(height: 12),
      _NumberField(
        key: ValueKey('h$imperial'),
        label: context.tr('height'),
        value: heightShown,
        suffix: imperial ? 'in' : 'cm',
        onChanged: (v) {
          p.heightCm = (imperial ? v * _cmPerIn : v).clamp(100, 250);
          onChanged();
        },
      ),
      const SizedBox(height: 12),
      _NumberField(
        key: ValueKey('w$imperial'),
        label: context.tr('weight'),
        value: weightShown,
        suffix: imperial ? 'lb' : 'kg',
        decimals: true,
        onChanged: (v) {
          p.weightKg = (imperial ? v * _kgPerLb : v).clamp(25, 350);
          onChanged();
        },
      ),
      const SizedBox(height: 16),
      Text(context.tr('activity'), style: Theme.of(context).textTheme.titleSmall),
      for (var i = 0; i < activityLevels.length; i++)
        RadioListTile<int>(
          contentPadding: EdgeInsets.zero,
          value: i,
          groupValue: p.activity,
          title: Text(context.tr('act$i')),
          subtitle: Text(context.tr('act${i}Sub')),
          onChanged: (v) {
            p.activity = v!;
            onChanged();
          },
        ),
    ]);
  }
}

/// Goal and weekly rate.
class ProfileGoalForm extends StatelessWidget {
  final Profile profile;
  final VoidCallback onChanged;
  const ProfileGoalForm({super.key, required this.profile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final icons = {
      Goal.lose: Icons.trending_down,
      Goal.maintain: Icons.balance,
      Goal.gain: Icons.trending_up,
      Goal.muscle: Icons.fitness_center,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in Goal.values)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.goal == g ? brandGreen : Theme.of(context).dividerColor, width: p.goal == g ? 2 : 1),
          ),
          child: ListTile(
            leading: Icon(icons[g]),
            title: Text(context.tr('goal_${g.name}')),
            subtitle: Text(context.tr('goal_${g.name}Sub')),
            onTap: () {
              p.goal = g;
              onChanged();
            },
          ),
        ),
      if (p.goal == Goal.lose || p.goal == Goal.gain) ...[
        const SizedBox(height: 8),
        Text(context.tr('ratePerWeek'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: [for (final r in [0.25, 0.5, 0.75, 1.0]) ButtonSegment(value: r, label: Text('$r kg'))],
          selected: {p.ratePerWeek},
          onSelectionChanged: (s) {
            p.ratePerWeek = s.first;
            onChanged();
          },
        ),
      ],
    ]);
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final double value;
  final String suffix;
  final bool decimals;
  final ValueChanged<double> onChanged;
  const _NumberField({super.key, required this.label, required this.value, required this.suffix, this.decimals = false, required this.onChanged});

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.decimals ? fmtNum(widget.value) : widget.value.round().toString());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals),
      decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
      onChanged: (s) {
        final v = double.tryParse(s.replaceAll(',', '.'));
        if (v != null && v > 0) widget.onChanged(v);
      },
    );
  }
}
