import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/repo.dart';

/// Barcode lookups. Checks foods already saved on the phone first, then the free
/// Open Food Facts database (ODbL), and saves what it finds so it works offline next time.
class OpenFoodFacts {
  static const _ua = 'MyFood/1.0 (Android; personal calorie tracker)';

  static Future<Food?> lookup(String code) async {
    final local = await Repo.byBarcode(code);
    if (local != null) return local;

    final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$code'
        '?fields=product_name,product_name_en,product_name_ar,brands,nutriments,serving_quantity,serving_size');
    final r = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw Exception('Open Food Facts: HTTP ${r.statusCode}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['status'] != 1 || j['product'] == null) return null;
    final p = j['product'] as Map<String, dynamic>;
    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};

    double val(String k) {
      final v = n[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    var kcal = val('energy-kcal_100g');
    if (kcal == 0 && val('energy_100g') > 0) kcal = val('energy_100g') / 4.184;
    final nameEn = ((p['product_name_en'] ?? p['product_name'] ?? '') as String).trim();
    final nameAr = ((p['product_name_ar'] ?? '') as String).trim();
    final serving = (p['serving_quantity'] is num) ? (p['serving_quantity'] as num).toDouble() : double.tryParse('${p['serving_quantity']}');
    final servingLabel = (p['serving_size'] as String?)?.trim();

    final food = Food(
      src: FoodSource.barcode,
      extId: code,
      barcode: code,
      nameEn: nameEn.isEmpty ? (nameAr.isEmpty ? code : nameAr) : nameEn,
      nameAr: nameAr,
      brand: ((p['brands'] ?? '') as String).split(',').first.trim(),
      kcal: kcal,
      p: val('proteins_100g'),
      c: val('carbohydrates_100g'),
      f: val('fat_100g'),
      fiber: val('fiber_100g'),
      sugar: val('sugars_100g'),
      sodium: val('sodium_100g') * 1000,
      portions: [
        if (serving != null && serving > 0)
          Portion(labelEn: servingLabel == null || servingLabel.isEmpty ? '1 serving' : '1 serving ($servingLabel)', labelAr: 'حصة واحدة', grams: serving),
      ],
    );
    final id = await Repo.saveFood(food);
    return Repo.food(id);
  }
}
