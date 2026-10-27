import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Opens the app database and fills the built-in food list on first launch.
class AppDb {
  static const fileName = 'myfood.db';
  static Database? _db;

  static Database get db => _db!;

  static Future<String> path() async => p.join(await getDatabasesPath(), fileName);

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<Database> open() async {
    _db = await openDatabase(
      await path(),
      version: 1,
      onCreate: (db, _) async {
        final b = db.batch();
        b.execute('''CREATE TABLE foods(
          id INTEGER PRIMARY KEY AUTOINCREMENT, src TEXT NOT NULL, ext_id TEXT, name_en TEXT, name_ar TEXT,
          search TEXT, cat TEXT, kcal REAL, p REAL, c REAL, f REAL, fib REAL, sug REAL, na REAL,
          barcode TEXT, brand TEXT, fav INTEGER DEFAULT 0, uses INTEGER DEFAULT 0, last_used INTEGER DEFAULT 0,
          recipe_id INTEGER, hidden INTEGER DEFAULT 0)''');
        b.execute('CREATE INDEX foods_barcode ON foods(barcode)');
        b.execute('CREATE INDEX foods_src ON foods(src, ext_id)');
        b.execute('CREATE TABLE portions(id INTEGER PRIMARY KEY AUTOINCREMENT, food_id INTEGER, label_en TEXT, label_ar TEXT, grams REAL)');
        b.execute('CREATE INDEX portions_food ON portions(food_id)');
        b.execute('''CREATE TABLE entries(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT, meal INTEGER, food_id INTEGER,
          name TEXT, grams REAL, qty REAL, unit TEXT, kcal REAL, p REAL, c REAL, f REAL, created INTEGER)''');
        b.execute('CREATE INDEX entries_day ON entries(day)');
        b.execute('CREATE TABLE recipes(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, cooked_g REAL, servings REAL, notes TEXT, food_id INTEGER, created INTEGER)');
        b.execute('''CREATE TABLE ingredients(id INTEGER PRIMARY KEY AUTOINCREMENT, recipe_id INTEGER, food_id INTEGER, name TEXT,
          grams REAL, qty REAL, unit TEXT, kcal REAL, p REAL, c REAL, f REAL)''');
        b.execute('CREATE TABLE water(day TEXT PRIMARY KEY, ml INTEGER)');
        b.execute('CREATE TABLE weights(day TEXT PRIMARY KEY, kg REAL)');
        b.execute('''CREATE TABLE plan(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT, meal INTEGER, food_id INTEGER,
          name TEXT, grams REAL, qty REAL, unit TEXT, kcal REAL)''');
        b.execute('CREATE TABLE shopping(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, amount TEXT, checked INTEGER DEFAULT 0, manual INTEGER DEFAULT 1)');
        b.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)');
        await b.commit(noResult: true);
      },
    );
    return _db!;
  }

  static Future<bool> isSeeded() async {
    final r = await db.query('meta', where: 'k = ?', whereArgs: ['seed']);
    return r.isNotEmpty;
  }

  /// Imports assets/data/world.txt and assets/data/usda.tsv. Takes a few seconds once.
  static Future<void> seed() async {
    final world = await rootBundle.loadString('assets/data/world.txt');
    final usda = await rootBundle.loadString('assets/data/usda.tsv');
    await db.transaction((txn) async {
      await txn.delete('portions', where: 'food_id IN (SELECT id FROM foods WHERE src IN (?, ?))', whereArgs: [FoodSource.world, FoodSource.usda]);
      await txn.delete('foods', where: 'src IN (?, ?)', whereArgs: [FoodSource.world, FoodSource.usda]);
      var nextId = 1 + (Sqflite.firstIntValue(await txn.rawQuery('SELECT MAX(id) FROM foods')) ?? 0);
      final b = txn.batch();

      for (final line in world.split('\n')) {
        final l = line.trim();
        if (l.isEmpty || l.startsWith('#')) continue;
        final c = l.split('^');
        if (c.length < 11) continue;
        final id = nextId++;
        b.insert('foods', {
          'id': id,
          'src': FoodSource.world,
          'ext_id': c[0],
          'name_en': c[1],
          'name_ar': c[2],
          'search': searchKey([c[1], c[2], c[3]]),
          'cat': c[4],
          'kcal': double.parse(c[5]),
          'p': double.parse(c[6]),
          'c': double.parse(c[7]),
          'f': double.parse(c[8]),
          'fib': double.parse(c[9]),
          'sug': 0,
          'na': 0,
        });
        for (final portion in c[10].split(';')) {
          final pp = portion.split('|');
          if (pp.length < 3) continue;
          b.insert('portions', {'food_id': id, 'label_en': pp[0], 'label_ar': pp[1], 'grams': double.parse(pp[2])});
        }
      }

      for (final line in usda.split('\n')) {
        if (line.trim().isEmpty) continue;
        final c = line.split('\t');
        if (c.length < 11) continue;
        final id = nextId++;
        b.insert('foods', {
          'id': id,
          'src': FoodSource.usda,
          'ext_id': c[0],
          'name_en': c[1],
          'name_ar': '',
          'search': searchKey([c[1]]),
          'cat': c[2],
          'kcal': double.parse(c[3]),
          'p': double.parse(c[4]),
          'c': double.parse(c[5]),
          'f': double.parse(c[6]),
          'fib': double.parse(c[7]),
          'sug': double.parse(c[8]),
          'na': double.parse(c[9]),
        });
        if (c[10].trim().isEmpty) continue;
        for (final portion in c[10].trim().split(';')) {
          final pp = portion.split('|');
          if (pp.length < 2) continue;
          b.insert('portions', {'food_id': id, 'label_en': pp[0], 'label_ar': '', 'grams': double.parse(pp[1])});
        }
      }
      b.insert('meta', {'k': 'seed', 'v': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await b.commit(noResult: true);
    });
  }
}
