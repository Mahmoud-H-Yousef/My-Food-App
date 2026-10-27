import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db.dart';
import 'l10n/strings.dart';
import 'logic/profile.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await AppDb.open();
  final profile = await Profile.load(prefs);
  runApp(ChangeNotifierProvider(
    create: (_) => AppState(prefs, profile),
    child: const MyFoodApp(),
  ));
}

class MyFoodApp extends StatelessWidget {
  const MyFoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: 'My Food',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: app.themeMode,
      locale: app.langSetting.isEmpty ? null : Locale(app.langSetting),
      supportedLocales: [for (final l in Strings.languages.keys) Locale(l)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const StartGate(),
    );
  }
}

/// Fills the food database on first launch, then shows onboarding or the app.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (!await AppDb.isSeeded()) await AppDb.seed();
      if (!mounted) return;
      await context.read<AppState>().reload();
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      final app = context.watch<AppState>();
      return app.profile == null ? const OnboardingPage() : const HomeShell();
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/icon/icon.png', width: 96, height: 96),
            const SizedBox(height: 24),
            if (_error == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.tr('preparingDb'), textAlign: TextAlign.center),
            ] else
              Text(_error!, style: TextStyle(color: cs.error)),
          ]),
        ),
      ),
    );
  }
}
