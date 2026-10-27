import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../logic/profile.dart';
import '../services/health_sync.dart';

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseDay(String s) => DateTime.parse(s);

/// App-wide state: settings, profile and the diary day being viewed.
class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  Profile? profile;

  AppState(this.prefs, this.profile);

  // ---------- settings ----------

  /// '' = follow the phone.
  String get langSetting => prefs.getString('lang') ?? '';
  set langSetting(String v) {
    prefs.setString('lang', v);
    notifyListeners();
  }

  ThemeMode get themeMode => ThemeMode.values.byName(prefs.getString('theme') ?? 'system');
  set themeMode(ThemeMode m) {
    prefs.setString('theme', m.name);
    notifyListeners();
  }

  bool get imperial => prefs.getBool('imperial') ?? false;
  set imperial(bool v) {
    prefs.setBool('imperial', v);
    notifyListeners();
  }

  bool get ramadan => prefs.getBool('ramadan') ?? false;
  set ramadan(bool v) {
    prefs.setBool('ramadan', v);
    notifyListeners();
  }

  bool get addExercise => prefs.getBool('addExercise') ?? true;
  set addExercise(bool v) {
    prefs.setBool('addExercise', v);
    notifyListeners();
  }

  int get glassMl => prefs.getInt('glassMl') ?? 250;
  set glassMl(int v) {
    prefs.setInt('glassMl', v);
    notifyListeners();
  }

  String getString(String key, [String def = '']) => prefs.getString(key) ?? def;
  Future<void> setString(String key, String v) async {
    await prefs.setString(key, v);
    notifyListeners();
  }

  bool getBool(String key, [bool def = false]) => prefs.getBool(key) ?? def;
  Future<void> setBool(String key, bool v) async {
    await prefs.setBool(key, v);
    notifyListeners();
  }

  Future<void> saveProfile(Profile p) async {
    profile = p;
    await p.save(prefs);
    notifyListeners();
  }

  Targets get targets => (profile ?? Profile()).targets;

  // ---------- diary ----------

  DateTime day = DateUtils.dateOnly(DateTime.now());
  String get dayStr => dayKey(day);
  bool get isToday => DateUtils.isSameDay(day, DateTime.now());

  List<LogEntry> entries = [];
  int waterMl = 0;

  /// Active calories burned today from Health Connect (0 when not connected).
  int burnedKcal = 0;
  int steps = 0;

  Nutrition get eaten => entries.fold(Nutrition.zero, (a, e) => a + e.nutrition);
  int get budget => targets.kcal + (addExercise ? burnedKcal : 0);

  List<LogEntry> mealEntries(int meal) => entries.where((e) => e.meal == meal).toList();

  Future<void> setDay(DateTime d) async {
    day = DateUtils.dateOnly(d);
    await reload();
  }

  Future<void> reload() async {
    entries = await Repo.entries(dayStr);
    waterMl = await Repo.water(dayStr);
    notifyListeners();
    HealthSync.instance.refreshActivity(this);
  }

  /// After the diary changes: reload and queue the Health Connect write.
  Future<void> changed() async {
    await reload();
    HealthSync.instance.scheduleWrite(this);
  }

  Future<void> addEntry(LogEntry e) async {
    await Repo.addEntry(e);
    await changed();
  }

  Future<void> updateEntry(LogEntry e) async {
    await Repo.updateEntry(e);
    await changed();
  }

  Future<void> deleteEntry(LogEntry e) async {
    await Repo.deleteEntry(e.id!);
    await changed();
  }

  Future<void> addWater(int ml) async {
    await Repo.setWater(dayStr, waterMl + ml);
    await changed();
  }

  void setActivity({int? burned, int? steps}) {
    if (burned != null) burnedKcal = burned;
    if (steps != null) this.steps = steps;
    notifyListeners();
  }

  /// Meal slot shown when adding food now: picks by time of day.
  int get suggestedMeal {
    final h = DateTime.now().hour;
    if (ramadan) {
      if (h >= 1 && h < 6) return 0;
      if (h >= 17 && h < 21) return 1;
      return 3;
    }
    if (h < 11) return 0;
    if (h < 16) return 1;
    if (h < 21) return 2;
    return 3;
  }

  /// Notify listeners after outside changes (foods, recipes, plan).
  void touch() => notifyListeners();
}
