import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// All database reads and writes go through here.
class Repo {
  static Database get _db => AppDb.db;

  // ---------- foods ----------

  static Future<Food?> food(int id) async {
    final r = await _db.query('foods', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return null;
    return (await _withPortions([Food.fromRow(r.first)])).first;
  }

  static Future<List<Food>> _withPortions(List<Food> foods) async {
    if (foods.isEmpty) return foods;
    final ids = foods.map((f) => f.id).join(',');
    final rows = await _db.rawQuery('SELECT * FROM portions WHERE food_id IN ($ids) ORDER BY id');
    final byFood = <int, List<Portion>>{};
    for (final r in rows) {
      byFood.putIfAbsent(r['food_id'] as int, () => []).add(Portion(
            id: r['id'] as int,
            labelEn: r['label_en'] as String,
            labelAr: (r['label_ar'] as String?) ?? '',
            grams: (r['grams'] as num).toDouble(),
          ));
    }
    for (final f in foods) {
      f.portions = byFood[f.id] ?? [];
    }
    return foods;
  }

  /// Search by every word typed, in any language. Own foods, recipes and the
  /// curated world list rank above the big USDA table.
  static Future<List<Food>> search(String query, {int limit = 80}) async {
    final words = normalize(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final where = words.map((_) => 'search LIKE ?').join(' AND ');
    final rows = await _db.query('foods',
        where: 'hidden = 0 AND $where', whereArgs: [for (final w in words) '%$w%'], limit: 600);
    final first = words.first;
    double score(Map<String, Object?> r) {
      final s = r['search'] as String;
      var sc = 0.0;
      switch (r['src']) {
        case FoodSource.recipe:
        case FoodSource.custom:
          sc += 60;
        case FoodSource.world:
          sc += 40;
        case FoodSource.barcode:
          sc += 30;
      }
      if (s.startsWith(first)) sc += 25;
      if (RegExp('(^| |,)${RegExp.escape(first)}').hasMatch(s)) sc += 10;
      sc += ((r['uses'] as int?) ?? 0) * 8;
      sc -= s.length / 12;
      return sc;
    }

    final sorted = [...rows]..sort((a, b) => score(b).compareTo(score(a)));
    return _withPortions(sorted.take(limit).map(Food.fromRow).toList());
  }

  static Future<List<Food>> recent({int limit = 40}) async {
    final rows = await _db.query('foods', where: 'hidden = 0 AND last_used > 0', orderBy: 'last_used DESC', limit: limit);
    return _withPortions(rows.map(Food.fromRow).toList());
  }

  static Future<List<Food>> favorites() async {
    final rows = await _db.query('foods', where: 'hidden = 0 AND fav = 1', orderBy: 'name_en');
    return _withPortions(rows.map(Food.fromRow).toList());
  }

  static Future<List<Food>> mine() async {
    final rows = await _db.query('foods',
        where: 'hidden = 0 AND src IN (?, ?, ?)', whereArgs: [FoodSource.custom, FoodSource.recipe, FoodSource.barcode], orderBy: 'id DESC');
    return _withPortions(rows.map(Food.fromRow).toList());
  }

  static Future<Food?> byBarcode(String code) async {
    final r = await _db.query('foods', where: 'barcode = ? AND hidden = 0', whereArgs: [code], limit: 1);
    if (r.isEmpty) return null;
    return (await _withPortions([Food.fromRow(r.first)])).first;
  }

  static Future<int> saveFood(Food f) async {
    return _db.transaction((txn) async {
      int id;
      if (f.id == null) {
        id = await txn.insert('foods', f.toRow());
      } else {
        id = f.id!;
        await txn.update('foods', f.toRow(), where: 'id = ?', whereArgs: [id]);
        await txn.delete('portions', where: 'food_id = ?', whereArgs: [id]);
      }
      for (final p in f.portions) {
        await txn.insert('portions', {'food_id': id, 'label_en': p.labelEn, 'label_ar': p.labelAr, 'grams': p.grams});
      }
      return id;
    });
  }

  static Future<void> setFav(int id, bool fav) => _db.update('foods', {'fav': fav ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  static Future<void> hideFood(int id) => _db.update('foods', {'hidden': 1, 'fav': 0}, where: 'id = ?', whereArgs: [id]);

  static Future<void> markUsed(int id) => _db.rawUpdate(
      'UPDATE foods SET uses = uses + 1, last_used = ? WHERE id = ?', [DateTime.now().millisecondsSinceEpoch, id]);

  // ---------- diary ----------

  static Future<List<LogEntry>> entries(String day) async {
    final rows = await _db.query('entries', where: 'day = ?', whereArgs: [day], orderBy: 'meal, id');
    return rows.map(LogEntry.fromRow).toList();
  }

  static Future<int> addEntry(LogEntry e) async {
    final id = await _db.insert('entries', e.toRow());
    if (e.foodId != null) await markUsed(e.foodId!);
    return id;
  }

  static Future<void> updateEntry(LogEntry e) => _db.update('entries', e.toRow(), where: 'id = ?', whereArgs: [e.id]);

  static Future<void> deleteEntry(int id) => _db.delete('entries', where: 'id = ?', whereArgs: [id]);

  static Future<void> copyDay(String from, String to, {int? meal}) async {
    final src = await entries(from);
    final b = _db.batch();
    for (final e in src) {
      if (meal != null && e.meal != meal) continue;
      b.insert('entries', e.copyWith(day: to).toRow());
    }
    await b.commit(noResult: true);
  }

  /// kcal/p/c/f totals per day for a date range (inclusive, yyyy-MM-dd strings).
  static Future<Map<String, Nutrition>> totals(String from, String to) async {
    final rows = await _db.rawQuery(
        'SELECT day, SUM(kcal) k, SUM(p) p, SUM(c) c, SUM(f) f FROM entries WHERE day BETWEEN ? AND ? GROUP BY day', [from, to]);
    return {
      for (final r in rows)
        r['day'] as String: Nutrition(
            ((r['k'] as num?) ?? 0).toDouble(), ((r['p'] as num?) ?? 0).toDouble(), ((r['c'] as num?) ?? 0).toDouble(), ((r['f'] as num?) ?? 0).toDouble()),
    };
  }

  static Future<int> loggedDays() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(DISTINCT day) FROM entries')) ?? 0;

  // ---------- water & weight ----------

  static Future<int> water(String day) async {
    final r = await _db.query('water', where: 'day = ?', whereArgs: [day]);
    return r.isEmpty ? 0 : r.first['ml'] as int;
  }

  static Future<void> setWater(String day, int ml) =>
      _db.insert('water', {'day': day, 'ml': ml < 0 ? 0 : ml}, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<List<WeightEntry>> weights() async {
    final rows = await _db.query('weights', orderBy: 'day');
    return rows.map((r) => WeightEntry(r['day'] as String, (r['kg'] as num).toDouble())).toList();
  }

  static Future<void> setWeight(String day, double kg) =>
      _db.insert('weights', {'day': day, 'kg': kg}, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<void> deleteWeight(String day) => _db.delete('weights', where: 'day = ?', whereArgs: [day]);

  // ---------- recipes (My Pot) ----------

  static Future<List<Recipe>> recipes() async {
    final rows = await _db.query('recipes', orderBy: 'created DESC');
    final out = <Recipe>[];
    for (final r in rows) {
      out.add(await _recipeFromRow(r));
    }
    return out;
  }

  static Future<Recipe?> recipe(int id) async {
    final rows = await _db.query('recipes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _recipeFromRow(rows.first);
  }

  static Future<Recipe> _recipeFromRow(Map<String, Object?> r) async {
    final id = r['id'] as int;
    final ing = await _db.query('ingredients', where: 'recipe_id = ?', whereArgs: [id], orderBy: 'id');
    final foodId = r['food_id'] as int?;
    var units = <Portion>[];
    if (foodId != null) {
      final f = await food(foodId);
      units = f?.portions ?? [];
    }
    return Recipe(
      id: id,
      name: r['name'] as String,
      cookedGrams: (r['cooked_g'] as num?)?.toDouble(),
      servings: ((r['servings'] as num?) ?? 1).toDouble(),
      notes: (r['notes'] as String?) ?? '',
      foodId: foodId,
      ingredients: ing.map(Ingredient.fromRow).toList(),
      units: units,
    );
  }

  /// Saves the recipe and its matching food row (per 100 g of the finished pot),
  /// so the recipe can be logged and searched like any other food.
  static Future<int> saveRecipe(Recipe r) async {
    final per = r.per100;
    final foodId = await saveFood(Food(
      id: r.foodId,
      src: FoodSource.recipe,
      nameEn: r.name,
      nameAr: r.name,
      kcal: per.kcal,
      p: per.p,
      c: per.c,
      f: per.f,
      recipeId: r.id,
      portions: r.units,
      fav: r.foodId == null ? false : ((await food(r.foodId!))?.fav ?? false),
      uses: r.foodId == null ? 0 : ((await food(r.foodId!))?.uses ?? 0),
    ));
    return _db.transaction((txn) async {
      final row = {
        'name': r.name,
        'cooked_g': r.cookedGrams,
        'servings': r.servings,
        'notes': r.notes,
        'food_id': foodId,
      };
      int id;
      if (r.id == null) {
        id = await txn.insert('recipes', {...row, 'created': DateTime.now().millisecondsSinceEpoch});
      } else {
        id = r.id!;
        await txn.update('recipes', row, where: 'id = ?', whereArgs: [id]);
        await txn.delete('ingredients', where: 'recipe_id = ?', whereArgs: [id]);
      }
      for (final i in r.ingredients) {
        await txn.insert('ingredients', i.toRow(id));
      }
      await txn.update('foods', {'recipe_id': id}, where: 'id = ?', whereArgs: [foodId]);
      return id;
    });
  }

  static Future<void> deleteRecipe(Recipe r) async {
    await _db.delete('ingredients', where: 'recipe_id = ?', whereArgs: [r.id]);
    await _db.delete('recipes', where: 'id = ?', whereArgs: [r.id]);
    if (r.foodId != null) await hideFood(r.foodId!);
  }

  // ---------- meal plan ----------

  static Future<List<PlanItem>> plan(String from, String to) async {
    final rows = await _db.query('plan', where: 'day BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'day, meal, id');
    return rows.map(PlanItem.fromRow).toList();
  }

  static Future<void> addPlan(PlanItem p) => _db.insert('plan', p.toRow());

  static Future<void> deletePlan(int id) => _db.delete('plan', where: 'id = ?', whereArgs: [id]);

  static Future<void> clearPlan(String from, String to) => _db.delete('plan', where: 'day BETWEEN ? AND ?', whereArgs: [from, to]);

  // ---------- shopping ----------

  static Future<List<ShoppingItem>> shopping() async {
    final rows = await _db.query('shopping', orderBy: 'checked, id');
    return rows.map(ShoppingItem.fromRow).toList();
  }

  static Future<void> addShopping(String name, String amount, {bool manual = true}) =>
      _db.insert('shopping', {'name': name, 'amount': amount, 'checked': 0, 'manual': manual ? 1 : 0});

  static Future<void> setShoppingChecked(int id, bool checked) =>
      _db.update('shopping', {'checked': checked ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteShopping(int id) => _db.delete('shopping', where: 'id = ?', whereArgs: [id]);

  static Future<void> clearShopping({bool onlyChecked = false, bool onlyGenerated = false}) {
    if (onlyChecked) return _db.delete('shopping', where: 'checked = 1');
    if (onlyGenerated) return _db.delete('shopping', where: 'manual = 0');
    return _db.delete('shopping');
  }
}
