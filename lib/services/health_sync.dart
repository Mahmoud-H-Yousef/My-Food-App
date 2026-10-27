import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../state/app_state.dart';

/// Health Connect link (the replacement for the Google Fit API; Google Fit,
/// Samsung Health and Fitbit all share data through it).
///
/// Reads steps and active calories; writes what you eat (one record per meal
/// per day, updated in place), water and weight.
class HealthSync {
  HealthSync._();
  static final instance = HealthSync._();

  final _health = Health();
  bool _configured = false;
  Timer? _debounce;

  static const _readTypes = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];
  static const _writeTypes = [HealthDataType.NUTRITION, HealthDataType.WATER, HealthDataType.WEIGHT];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// installed, needsUpdate or missing
  Future<String> status() async {
    await _configure();
    final s = await _health.getHealthConnectSdkStatus();
    return switch (s) {
      HealthConnectSdkStatus.sdkAvailable => 'installed',
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => 'needsUpdate',
      _ => 'missing',
    };
  }

  Future<void> install() async {
    await _configure();
    await _health.installHealthConnect();
  }

  Future<bool> connect() async {
    await _configure();
    return _health.requestAuthorization(
      [..._readTypes, ..._writeTypes],
      permissions: [
        for (final _ in _readTypes) HealthDataAccess.READ,
        HealthDataAccess.WRITE,
        HealthDataAccess.WRITE,
        HealthDataAccess.READ_WRITE,
      ],
    );
  }

  /// Steps and active kcal for the day shown in the app.
  Future<void> refreshActivity(AppState app) async {
    if (!app.getBool('healthOn')) return;
    try {
      await _configure();
      final start = app.day;
      final end = DateTime.now().isBefore(start.add(const Duration(days: 1))) ? DateTime.now() : start.add(const Duration(days: 1));
      if (!end.isAfter(start)) {
        app.setActivity(burned: 0, steps: 0);
        return;
      }
      final steps = await _health.getTotalStepsInInterval(start, end) ?? 0;
      final pts = await _health.getHealthDataFromTypes(types: [HealthDataType.ACTIVE_ENERGY_BURNED], startTime: start, endTime: end);
      var kcal = 0.0;
      for (final p in _health.removeDuplicates(pts)) {
        final v = p.value;
        if (v is NumericHealthValue) kcal += v.numericValue.toDouble();
      }
      app.setActivity(burned: kcal.round(), steps: steps);
    } catch (e) {
      debugPrint('health read failed: $e');
    }
  }

  /// Called after the diary changes; waits a moment so quick edits are written once.
  void scheduleWrite(AppState app) {
    if (!app.getBool('healthOn')) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => writeDay(app, app.dayStr));
  }

  Future<void> writeDay(AppState app, String day) async {
    try {
      await _configure();
      final entries = await Repo.entries(day);
      final date = parseDay(day);
      final version = DateTime.now().millisecondsSinceEpoch.toDouble();
      const mealTypes = [MealType.BREAKFAST, MealType.LUNCH, MealType.DINNER, MealType.SNACK];
      const hours = [8, 13, 19, 16];
      for (var m = 0; m < 4; m++) {
        final n = entries.where((e) => e.meal == m).fold(Nutrition.zero, (a, e) => a + e.nutrition);
        final start = date.add(Duration(hours: hours[m]));
        await _health.writeMeal(
          mealType: mealTypes[m],
          startTime: start,
          endTime: start.add(const Duration(minutes: 30)),
          clientRecordId: 'myfood-$day-meal$m',
          clientRecordVersion: version,
          caloriesConsumed: n.kcal,
          protein: n.p,
          carbohydrates: n.c,
          fatTotal: n.f,
          name: 'My Food',
        );
      }
      final water = await Repo.water(day);
      if (water > 0) {
        await _health.writeHealthData(
          value: water / 1000,
          type: HealthDataType.WATER,
          startTime: date.add(const Duration(hours: 12)),
          endTime: date.add(const Duration(hours: 12, minutes: 1)),
          clientRecordId: 'myfood-$day-water',
          clientRecordVersion: version,
        );
      }
    } catch (e) {
      debugPrint('health write failed: $e');
    }
  }

  Future<void> writeWeight(AppState app, String day, double kg) async {
    if (!app.getBool('healthOn')) return;
    try {
      await _configure();
      final t = parseDay(day).add(const Duration(hours: 8));
      await _health.writeHealthData(
        value: kg,
        type: HealthDataType.WEIGHT,
        startTime: t,
        clientRecordId: 'myfood-$day-weight',
        clientRecordVersion: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
    } catch (e) {
      debugPrint('health weight failed: $e');
    }
  }
}
