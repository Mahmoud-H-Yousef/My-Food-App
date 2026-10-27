/// Plain data classes. All nutrition values on [Food] are per 100 g.
library;

class Nutrition {
  final double kcal, p, c, f;
  const Nutrition(this.kcal, this.p, this.c, this.f);
  static const zero = Nutrition(0, 0, 0, 0);

  Nutrition operator +(Nutrition o) => Nutrition(kcal + o.kcal, p + o.p, c + o.c, f + o.f);
  Nutrition scale(double factor) => Nutrition(kcal * factor, p * factor, c * factor, f * factor);
}

class Portion {
  final int? id;
  final String labelEn;
  final String labelAr;
  final double grams;
  const Portion({this.id, required this.labelEn, this.labelAr = '', required this.grams});

  String label(String lang) => lang == 'ar' && labelAr.isNotEmpty ? labelAr : labelEn;

  static const gram = Portion(id: -1, labelEn: 'g', labelAr: 'جم', grams: 1);
}

/// Where a food came from.
abstract class FoodSource {
  static const usda = 'usda';
  static const world = 'world';
  static const custom = 'custom';
  static const barcode = 'off';
  static const recipe = 'recipe';
}

class Food {
  final int? id;
  final String src;
  final String extId;
  final String nameEn;
  final String nameAr;
  final String category;
  final double kcal, p, c, f, fiber, sugar, sodium;
  final String barcode;
  final String brand;
  final bool fav;
  final int uses;
  final int? recipeId;
  List<Portion> portions;

  Food({
    this.id,
    required this.src,
    this.extId = '',
    required this.nameEn,
    this.nameAr = '',
    this.category = '',
    required this.kcal,
    this.p = 0,
    this.c = 0,
    this.f = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.sodium = 0,
    this.barcode = '',
    this.brand = '',
    this.fav = false,
    this.uses = 0,
    this.recipeId,
    this.portions = const [],
  });

  String name(String lang) {
    if (lang == 'ar' && nameAr.isNotEmpty) return nameAr;
    if (nameEn.isNotEmpty) return nameEn;
    return nameAr;
  }

  Nutrition forGrams(double grams) => Nutrition(kcal, p, c, f).scale(grams / 100);

  factory Food.fromRow(Map<String, Object?> r) => Food(
        id: r['id'] as int?,
        src: r['src'] as String,
        extId: (r['ext_id'] as String?) ?? '',
        nameEn: (r['name_en'] as String?) ?? '',
        nameAr: (r['name_ar'] as String?) ?? '',
        category: (r['cat'] as String?) ?? '',
        kcal: (r['kcal'] as num).toDouble(),
        p: (r['p'] as num).toDouble(),
        c: (r['c'] as num).toDouble(),
        f: (r['f'] as num).toDouble(),
        fiber: ((r['fib'] as num?) ?? 0).toDouble(),
        sugar: ((r['sug'] as num?) ?? 0).toDouble(),
        sodium: ((r['na'] as num?) ?? 0).toDouble(),
        barcode: (r['barcode'] as String?) ?? '',
        brand: (r['brand'] as String?) ?? '',
        fav: (r['fav'] as int? ?? 0) == 1,
        uses: (r['uses'] as int?) ?? 0,
        recipeId: r['recipe_id'] as int?,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'src': src,
        'ext_id': extId,
        'name_en': nameEn,
        'name_ar': nameAr,
        'search': searchKey([nameEn, nameAr, brand]),
        'cat': category,
        'kcal': kcal,
        'p': p,
        'c': c,
        'f': f,
        'fib': fiber,
        'sug': sugar,
        'na': sodium,
        'barcode': barcode,
        'brand': brand,
        'fav': fav ? 1 : 0,
        'uses': uses,
        'recipe_id': recipeId,
      };

  /// Every portion the user can pick, grams last.
  List<Portion> get allPortions => [...portions, Portion.gram];
}

/// Lowercases and folds Arabic letter variants so "أرز", "ارز" and "رز" style typing all match.
String normalize(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp('[ً-ْـ]'), ''); // tashkeel, tatweel
  t = t.replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي').replaceAll('ؤ', 'و').replaceAll('ئ', 'ي');
  return t;
}

String searchKey(Iterable<String> parts) => normalize(parts.where((s) => s.isNotEmpty).join(' '));

class LogEntry {
  final int? id;
  final String day;
  final int meal;
  final int? foodId;
  final String name;
  final double grams;
  final double qty;
  final String unit;
  final double kcal, p, c, f;

  const LogEntry({
    this.id,
    required this.day,
    required this.meal,
    this.foodId,
    required this.name,
    required this.grams,
    this.qty = 1,
    this.unit = 'g',
    required this.kcal,
    this.p = 0,
    this.c = 0,
    this.f = 0,
  });

  Nutrition get nutrition => Nutrition(kcal, p, c, f);

  factory LogEntry.fromRow(Map<String, Object?> r) => LogEntry(
        id: r['id'] as int?,
        day: r['day'] as String,
        meal: r['meal'] as int,
        foodId: r['food_id'] as int?,
        name: r['name'] as String,
        grams: (r['grams'] as num).toDouble(),
        qty: (r['qty'] as num).toDouble(),
        unit: r['unit'] as String,
        kcal: (r['kcal'] as num).toDouble(),
        p: (r['p'] as num).toDouble(),
        c: (r['c'] as num).toDouble(),
        f: (r['f'] as num).toDouble(),
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'day': day,
        'meal': meal,
        'food_id': foodId,
        'name': name,
        'grams': grams,
        'qty': qty,
        'unit': unit,
        'kcal': kcal,
        'p': p,
        'c': c,
        'f': f,
        'created': DateTime.now().millisecondsSinceEpoch,
      };

  LogEntry copyWith({String? day, int? meal}) => LogEntry(
        day: day ?? this.day,
        meal: meal ?? this.meal,
        foodId: foodId,
        name: name,
        grams: grams,
        qty: qty,
        unit: unit,
        kcal: kcal,
        p: p,
        c: c,
        f: f,
      );
}

class Ingredient {
  final int? id;
  final int? foodId;
  final String name;
  final double grams;
  final double qty;
  final String unit;
  final Nutrition n; // for [grams]

  const Ingredient({this.id, this.foodId, required this.name, required this.grams, this.qty = 1, this.unit = 'g', required this.n});

  factory Ingredient.fromRow(Map<String, Object?> r) => Ingredient(
        id: r['id'] as int?,
        foodId: r['food_id'] as int?,
        name: r['name'] as String,
        grams: (r['grams'] as num).toDouble(),
        qty: ((r['qty'] as num?) ?? 1).toDouble(),
        unit: (r['unit'] as String?) ?? 'g',
        n: Nutrition((r['kcal'] as num).toDouble(), (r['p'] as num).toDouble(), (r['c'] as num).toDouble(), (r['f'] as num).toDouble()),
      );

  Map<String, Object?> toRow(int recipeId) => {
        'recipe_id': recipeId,
        'food_id': foodId,
        'name': name,
        'grams': grams,
        'qty': qty,
        'unit': unit,
        'kcal': n.kcal,
        'p': n.p,
        'c': n.c,
        'f': n.f,
      };
}

class Recipe {
  final int? id;
  final String name;
  final double? cookedGrams;
  final double servings;
  final String notes;
  final int? foodId;
  final List<Ingredient> ingredients;
  final List<Portion> units; // custom units such as "1 ladle = 150 g"

  const Recipe({
    this.id,
    required this.name,
    this.cookedGrams,
    this.servings = 1,
    this.notes = '',
    this.foodId,
    this.ingredients = const [],
    this.units = const [],
  });

  Nutrition get total => ingredients.fold(Nutrition.zero, (a, i) => a + i.n);
  double get rawGrams => ingredients.fold(0.0, (a, i) => a + i.grams);

  /// Weight the per-100 g numbers are based on: the weighed cooked pot, or the raw total.
  double get finalGrams => (cookedGrams != null && cookedGrams! > 0) ? cookedGrams! : rawGrams;

  Nutrition get per100 => finalGrams <= 0 ? Nutrition.zero : total.scale(100 / finalGrams);
}

class WeightEntry {
  final String day;
  final double kg;
  const WeightEntry(this.day, this.kg);
}

class PlanItem {
  final int? id;
  final String day;
  final int meal;
  final int? foodId;
  final String name;
  final double grams;
  final double qty;
  final String unit;
  final double kcal;

  const PlanItem({this.id, required this.day, required this.meal, this.foodId, required this.name, required this.grams, this.qty = 1, this.unit = 'g', required this.kcal});

  factory PlanItem.fromRow(Map<String, Object?> r) => PlanItem(
        id: r['id'] as int?,
        day: r['day'] as String,
        meal: r['meal'] as int,
        foodId: r['food_id'] as int?,
        name: r['name'] as String,
        grams: (r['grams'] as num).toDouble(),
        qty: (r['qty'] as num).toDouble(),
        unit: r['unit'] as String,
        kcal: (r['kcal'] as num).toDouble(),
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'day': day,
        'meal': meal,
        'food_id': foodId,
        'name': name,
        'grams': grams,
        'qty': qty,
        'unit': unit,
        'kcal': kcal,
      };
}

class ShoppingItem {
  final int? id;
  final String name;
  final String amount;
  final bool checked;
  final bool manual;
  const ShoppingItem({this.id, required this.name, this.amount = '', this.checked = false, this.manual = true});

  factory ShoppingItem.fromRow(Map<String, Object?> r) => ShoppingItem(
        id: r['id'] as int?,
        name: r['name'] as String,
        amount: (r['amount'] as String?) ?? '',
        checked: (r['checked'] as int? ?? 0) == 1,
        manual: (r['manual'] as int? ?? 1) == 1,
      );
}
