import 'package:flutter/material.dart';

const brandGreen = Color(0xFF16A34A);
const proteinColor = Color(0xFFE11D48);
const carbsColor = Color(0xFFF59E0B);
const fatColor = Color(0xFF3B82F6);
const waterColor = Color(0xFF0EA5E9);

ThemeData buildTheme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: brandGreen, brightness: b);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF6F8F6) : cs.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: b == Brightness.light ? Colors.white : cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      indicatorColor: cs.primaryContainer,
    ),
  );
}

/// Rounds for display: whole numbers above 10, one decimal below.
String fmtNum(num v) {
  if (v.abs() >= 10 || v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(1);
}
