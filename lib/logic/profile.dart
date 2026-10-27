import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

enum Sex { male, female }

enum Goal { lose, maintain, gain, muscle }

/// Activity multipliers for the Mifflin-St Jeor resting energy.
const activityLevels = [1.2, 1.375, 1.55, 1.725, 1.9];

class Targets {
  final int kcal;
  final int protein, carbs, fat; // grams
  final int waterMl;
  const Targets(this.kcal, this.protein, this.carbs, this.fat, this.waterMl);
}

/// The user's body details and goal. Stored as JSON in shared preferences.
class Profile {
  Sex sex;
  int age;
  double heightCm;
  double weightKg;
  int activity; // index into activityLevels
  Goal goal;
  double ratePerWeek; // kg per week for lose/gain
  int? customKcal;
  int? customProtein, customCarbs, customFat;
  int? customWater;

  Profile({
    this.sex = Sex.male,
    this.age = 25,
    this.heightCm = 170,
    this.weightKg = 70,
    this.activity = 1,
    this.goal = Goal.maintain,
    this.ratePerWeek = 0.5,
    this.customKcal,
    this.customProtein,
    this.customCarbs,
    this.customFat,
    this.customWater,
  });

  double get bmr => 10 * weightKg + 6.25 * heightCm - 5 * age + (sex == Sex.male ? 5 : -161);
  double get tdee => bmr * activityLevels[activity.clamp(0, activityLevels.length - 1)];
  double get bmi => weightKg / pow(heightCm / 100, 2);

  int get suggestedKcal {
    final daily = ratePerWeek * 7700 / 7;
    var k = switch (goal) {
      Goal.lose => tdee - daily,
      Goal.maintain => tdee,
      Goal.gain => tdee + daily,
      Goal.muscle => tdee + 250,
    };
    final floor = sex == Sex.male ? 1500.0 : 1200.0;
    if (k < floor) k = floor;
    return (k / 10).round() * 10;
  }

  Targets get targets {
    final kcal = customKcal ?? suggestedKcal;
    // Protein by body weight (more when cutting or building), fat as a share of energy, carbs fill the rest.
    final proteinPerKg = switch (goal) {
      Goal.lose => 1.8,
      Goal.maintain => 1.4,
      Goal.gain => 1.6,
      Goal.muscle => 2.0,
    };
    final protein = customProtein ?? (weightKg * proteinPerKg).round();
    final fat = customFat ?? (kcal * 0.28 / 9).round();
    final carbs = customCarbs ?? max(0, ((kcal - protein * 4 - fat * 9) / 4).round());
    final water = customWater ?? ((weightKg * 35 / 250).round() * 250);
    return Targets(kcal, protein, carbs, fat, water);
  }

  Map<String, dynamic> toJson() => {
        'sex': sex.name,
        'age': age,
        'h': heightCm,
        'w': weightKg,
        'act': activity,
        'goal': goal.name,
        'rate': ratePerWeek,
        'ck': customKcal,
        'cp': customProtein,
        'cc': customCarbs,
        'cf': customFat,
        'cw': customWater,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        sex: Sex.values.byName(j['sex'] ?? 'male'),
        age: j['age'] ?? 25,
        heightCm: (j['h'] ?? 170).toDouble(),
        weightKg: (j['w'] ?? 70).toDouble(),
        activity: j['act'] ?? 1,
        goal: Goal.values.byName(j['goal'] ?? 'maintain'),
        ratePerWeek: (j['rate'] ?? 0.5).toDouble(),
        customKcal: j['ck'],
        customProtein: j['cp'],
        customCarbs: j['cc'],
        customFat: j['cf'],
        customWater: j['cw'],
      );

  static Future<Profile?> load(SharedPreferences prefs) async {
    final s = prefs.getString('profile');
    if (s == null) return null;
    return Profile.fromJson(jsonDecode(s));
  }

  Future<void> save(SharedPreferences prefs) => prefs.setString('profile', jsonEncode(toJson()));
}
