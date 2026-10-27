import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'pages/plan_page.dart';
import 'pages/progress_page.dart';
import 'pages/recipes_page.dart';
import 'pages/settings_page.dart';
import 'pages/today_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayPage(),
      const RecipesPage(),
      const PlanPage(),
      const ProgressPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.today_outlined), selectedIcon: const Icon(Icons.today), label: context.tr('tabToday')),
          NavigationDestination(icon: const Icon(Icons.soup_kitchen_outlined), selectedIcon: const Icon(Icons.soup_kitchen), label: context.tr('tabMyPot')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month), label: context.tr('tabPlan')),
          NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights), label: context.tr('tabProgress')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.tr('tabMe')),
        ],
      ),
    );
  }
}
