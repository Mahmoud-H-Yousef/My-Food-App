import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repo.dart';
import '../l10n/strings.dart';
import '../logic/profile.dart';
import '../state/app_state.dart';
import 'widgets/profile_form.dart';

/// First-run setup: language, body details and goal.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _profile = Profile();
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          LinearProgressIndicator(value: (_step + 1) / 3),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(24), children: [
              if (_step == 0) ...[
                Center(child: Image.asset('assets/icon/icon.png', width: 88, height: 88)),
                const SizedBox(height: 16),
                Text(context.tr('welcome'), style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(context.tr('welcomeSub'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 32),
                Text(context.tr('language'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final e in {'': context.tr('systemLang'), ...Strings.languages}.entries)
                  RadioListTile<String>(
                    value: e.key,
                    groupValue: app.langSetting,
                    title: Text(e.value),
                    onChanged: (v) => app.langSetting = v!,
                  ),
              ],
              if (_step == 1) ...[
                Text(context.tr('aboutYou'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(context.tr('aboutYouSub'), style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                ProfileBodyForm(profile: _profile, imperial: app.imperial, onChanged: () => setState(() {})),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('imperialUnits')),
                  value: app.imperial,
                  onChanged: (v) => app.imperial = v,
                ),
              ],
              if (_step == 2) ...[
                Text(context.tr('yourGoal'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                ProfileGoalForm(profile: _profile, onChanged: () => setState(() {})),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text(context.tr('dailyTarget'), style: TextStyle(color: cs.onPrimaryContainer)),
                      Text('${_profile.targets.kcal} ${context.tr('kcal')}',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
                      Text(
                          '${context.tr('protein')} ${_profile.targets.protein}g · ${context.tr('carbs')} ${_profile.targets.carbs}g · ${context.tr('fat')} ${_profile.targets.fat}g',
                          style: TextStyle(color: cs.onPrimaryContainer)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(children: [
              if (_step > 0) TextButton(onPressed: () => setState(() => _step--), child: Text(context.tr('back'))),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  if (_step < 2) {
                    setState(() => _step++);
                    return;
                  }
                  await Repo.setWeight(dayKey(DateTime.now()), _profile.weightKg);
                  await app.saveProfile(_profile);
                },
                child: Text(_step < 2 ? context.tr('next') : context.tr('start')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
