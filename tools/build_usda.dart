// Converts the USDA FoodData Central "SR Legacy" CSV export into the compact
// assets/data/usda.tsv the app imports on first launch.
//
//   dart run tools/build_usda.dart <path-to-FoodData_Central_sr_legacy_food_csv folder>
//
// Output columns (per 100 g): id, name, category, kcal, protein, carbs, fat,
// fiber, sugar, sodium_mg, portions ("label|grams;label|grams").
import 'dart:io';

const _skipCategories = {'3', '24', '27'}; // baby foods, native foods, QC materials

const _nutrients = {
  '1008': 'kcal',
  '1003': 'p',
  '1005': 'c',
  '1004': 'f',
  '1079': 'fib',
  '2000': 'sug',
  '1093': 'na',
};

List<String> parseCsvLine(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        sb.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out;
}

Iterable<List<String>> rows(String path) sync* {
  final lines = File(path).readAsLinesSync();
  for (final l in lines.skip(1)) {
    if (l.trim().isEmpty) continue;
    yield parseCsvLine(l);
  }
}

String fmt(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tools/build_usda.dart <csv folder>');
    exit(1);
  }
  final dir = args.first;
  final cats = {for (final r in rows('$dir/food_category.csv')) r[0]: r[2]};
  final units = {for (final r in rows('$dir/measure_unit.csv')) r[0]: r[1]};

  final foods = <String, Map<String, dynamic>>{};
  for (final r in rows('$dir/food.csv')) {
    if (_skipCategories.contains(r[3])) continue;
    foods[r[0]] = {'name': r[2], 'cat': cats[r[3]] ?? '', 'n': <String, double>{}, 'portions': <String>[]};
  }
  for (final r in rows('$dir/food_nutrient.csv')) {
    final f = foods[r[1]];
    final key = _nutrients[r[2]];
    if (f == null || key == null) continue;
    (f['n'] as Map<String, double>)[key] = double.tryParse(r[3]) ?? 0;
  }
  for (final r in rows('$dir/food_portion.csv')) {
    final f = foods[r[1]];
    if (f == null) continue;
    final grams = double.tryParse(r[7]) ?? 0;
    if (grams <= 0) continue;
    final amount = double.tryParse(r[3]) ?? 1;
    final unit = r[4] == '9999' ? '' : (units[r[4]] ?? '');
    final label = [fmt(amount), unit, r[6]].where((s) => s.trim().isNotEmpty).join(' ').replaceAll(RegExp(r'[|;\t]'), ',');
    (f['portions'] as List<String>).add('$label|${fmt(grams)}');
  }

  final out = StringBuffer();
  var count = 0;
  for (final e in foods.entries) {
    final n = e.value['n'] as Map<String, double>;
    final p = n['p'] ?? 0, c = n['c'] ?? 0, f = n['f'] ?? 0;
    final kcal = n['kcal'] ?? (p * 4 + c * 4 + f * 9);
    out.writeln([
      e.key,
      (e.value['name'] as String).replaceAll('\t', ' '),
      e.value['cat'],
      fmt(kcal), fmt(p), fmt(c), fmt(f),
      fmt(n['fib'] ?? 0), fmt(n['sug'] ?? 0), fmt(n['na'] ?? 0),
      (e.value['portions'] as List<String>).take(6).join(';'),
    ].join('\t'));
    count++;
  }
  Directory('assets/data').createSync(recursive: true);
  File('assets/data/usda.tsv').writeAsStringSync(out.toString());
  stdout.writeln('wrote $count foods');
}
