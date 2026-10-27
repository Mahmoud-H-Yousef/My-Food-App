import 'package:flutter/widgets.dart';

import 'strings_ar.dart';
import 'strings_en.dart';

/// Simple key → text tables. Missing keys fall back to English.
/// To add a language: create strings_xx.dart and register it in [languages] and [_tables].
class Strings {
  static const languages = {'en': 'English', 'ar': 'العربية'};

  static const _tables = {'en': en, 'ar': ar};

  static String get(String lang, String key, [Map<String, String>? args]) {
    var s = _tables[lang]?[key] ?? en[key] ?? key;
    args?.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }
}

extension TrX on BuildContext {
  String tr(String key, [Map<String, String>? args]) => Strings.get(Localizations.localeOf(this).languageCode, key, args);
}
