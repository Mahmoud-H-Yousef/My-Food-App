import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../logic/profile.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../widgets/profile_form.dart';
import 'settings_sections.dart';

/// "Me" tab: profile, goals, preferences and data.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.profile ?? Profile();
    final t = app.targets;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('tabMe'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _header(context, context.tr('goalsSection')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(context.tr('goal_${p.goal.name}')),
              subtitle: Text('${t.kcal} ${context.tr('kcal')} · P ${t.protein}g · C ${t.carbs}g · F ${t.fat}g'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditPage())),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(context.tr('customTargets')),
              subtitle: Text(p.customKcal == null ? context.tr('automatic') : context.tr('custom')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TargetsPage())),
            ),
          ]),
        ),
        _header(context, context.tr('preferences')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(context.tr('language')),
              subtitle: Text(app.langSetting.isEmpty ? context.tr('systemLang') : Strings.languages[app.langSetting] ?? app.langSetting),
              onTap: () => _pickLanguage(context),
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: Text(context.tr('theme')),
              subtitle: Text(context.tr('theme_${app.themeMode.name}')),
              onTap: () => _pickTheme(context),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.straighten),
              title: Text(context.tr('imperialUnits')),
              value: app.imperial,
              onChanged: (v) => app.imperial = v,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.nights_stay_outlined),
              title: Text(context.tr('ramadanMode')),
              subtitle: Text(context.tr('ramadanModeSub')),
              value: app.ramadan,
              onChanged: (v) => app.ramadan = v,
            ),
            ListTile(
              leading: const Icon(Icons.local_drink_outlined),
              title: Text(context.tr('glassSizeSetting')),
              subtitle: Text('${app.glassMl} ml'),
              onTap: () async {
                final s = await promptText(context, context.tr('glassSizeSetting'), initial: '${app.glassMl}', keyboard: TextInputType.number);
                final v = int.tryParse(s ?? '');
                if (v != null && v > 0) app.glassMl = v;
              },
            ),
          ]),
        ),
        ...extraSettingsSections(context),
        _header(context, context.tr('about')),
        Card(
          child: Column(children: [
            ListTile(
              leading: Image.asset('assets/icon/icon.png', width: 36),
              title: const Text('My Food'),
              subtitle: Text('${context.tr('version')} $appVersion'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.tr('dataSources')),
              subtitle: Text(context.tr('dataSourcesBody')),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 16, 6),
        child: Text(s, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _pickLanguage(BuildContext context) async {
    final app = context.read<AppState>();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: Text(context.tr('language')), children: [
        for (final e in {'': context.tr('systemLang'), ...Strings.languages}.entries)
          RadioListTile<String>(value: e.key, groupValue: app.langSetting, title: Text(e.value), onChanged: (v) => Navigator.pop(c, v)),
      ]),
    );
    if (v != null) app.langSetting = v;
  }

  Future<void> _pickTheme(BuildContext context) async {
    final app = context.read<AppState>();
    final v = await showDialog<ThemeMode>(
      context: context,
      builder: (c) => SimpleDialog(title: Text(context.tr('theme')), children: [
        for (final m in ThemeMode.values)
          RadioListTile<ThemeMode>(value: m, groupValue: app.themeMode, title: Text(context.tr('theme_${m.name}')), onChanged: (v) => Navigator.pop(c, v)),
      ]),
    );
    if (v != null) app.themeMode = v;
  }
}

const appVersion = '4.0';

/// Sections added in later versions.
List<Widget> extraSettingsSections(BuildContext context) => const [HealthSection(), AiSection(), BackupSection()];

/// Edit body details and goal; recalculates targets.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final Profile _p = Profile.fromJson((context.read<AppState>().profile ?? Profile()).toJson());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profileGoal'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ProfileBodyForm(profile: _p, imperial: app.imperial, onChanged: () => setState(() {})),
        const SizedBox(height: 16),
        Text(context.tr('yourGoal'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ProfileGoalForm(profile: _p, onChanged: () => setState(() {})),
        const SizedBox(height: 16),
        Text(context.tr('suggestedKcal', {'n': '${_p.suggestedKcal}'}), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await app.saveProfile(_p);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(context.tr('save')),
        ),
      ]),
    );
  }
}

/// Override calories, macros and water.
class TargetsPage extends StatefulWidget {
  const TargetsPage({super.key});

  @override
  State<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends State<TargetsPage> {
  late final Profile _p = Profile.fromJson((context.read<AppState>().profile ?? Profile()).toJson());
  late final _kcal = TextEditingController(text: _p.customKcal?.toString() ?? '');
  late final _pro = TextEditingController(text: _p.customProtein?.toString() ?? '');
  late final _carb = TextEditingController(text: _p.customCarbs?.toString() ?? '');
  late final _fat = TextEditingController(text: _p.customFat?.toString() ?? '');
  late final _water = TextEditingController(text: _p.customWater?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final auto = Profile.fromJson({..._p.toJson(), 'ck': null, 'cp': null, 'cc': null, 'cf': null, 'cw': null}).targets;
    Widget field(TextEditingController c, String label, int autoValue, String suffix) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, hintText: '${context.tr('automatic')}: $autoValue', suffixText: suffix),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('customTargets'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(context.tr('customTargetsHelp')),
        const SizedBox(height: 16),
        field(_kcal, context.tr('kcal'), auto.kcal, 'kcal'),
        field(_pro, context.tr('protein'), auto.protein, 'g'),
        field(_carb, context.tr('carbs'), auto.carbs, 'g'),
        field(_fat, context.tr('fat'), auto.fat, 'g'),
        field(_water, context.tr('water'), auto.waterMl, 'ml'),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(
            onPressed: () {
              for (final c in [_kcal, _pro, _carb, _fat, _water]) {
                c.clear();
              }
              setState(() {});
            },
            child: Text(context.tr('resetAuto')),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () async {
              _p.customKcal = int.tryParse(_kcal.text);
              _p.customProtein = int.tryParse(_pro.text);
              _p.customCarbs = int.tryParse(_carb.text);
              _p.customFat = int.tryParse(_fat.text);
              _p.customWater = int.tryParse(_water.text);
              await context.read<AppState>().saveProfile(_p);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(context.tr('save')),
          ),
        ]),
      ]),
    );
  }
}
