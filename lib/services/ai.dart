import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repo.dart';

/// One food the AI recognised.
class AiItem {
  String name;
  double grams;
  Nutrition n; // for [grams]
  Food? match; // food from the database used instead of the AI's own numbers
  bool selected = true;

  AiItem(this.name, this.grams, this.n, {this.match});

  Nutrition get nutrition => match == null ? n : match!.forGrams(grams);
}

/// Food recognition from text or a photo.
///
/// On-device: Gemma 4 E2B (free, offline, ~2.6 GB, runs on 64-bit ARM phones
/// with Android 11+). Optional: a free Google Gemini API key for stronger
/// photo recognition (online).
class Ai extends ChangeNotifier {
  Ai._();
  static final instance = Ai._();

  static const modelUrl = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const modelFile = 'gemma-4-E2B-it.litertlm';
  static const modelSize = '2.6 GB';

  bool _initialized = false;
  bool _activated = false;
  int? downloadProgress; // 0..100 while downloading
  String? lastError;

  /// The on-device engine only ships for 64-bit ARM.
  bool get deviceSupported => Platform.isAndroid && Platform.version.contains('android_arm64');

  Future<void> _init() async {
    if (_initialized) return;
    await FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    _initialized = true;
  }

  Future<bool> modelInstalled() async {
    if (!deviceSupported) return false;
    try {
      await _init();
      final ids = await FlutterEdgeAi.listInstalledModels();
      return ids.any((id) => id.contains('gemma-4-E2B'));
    } catch (e) {
      debugPrint('ai: $e');
      return false;
    }
  }

  InferenceInstallationBuilder _builder() =>
      FlutterEdgeAi.installModel(modelType: ModelType.gemma4, fileType: ModelFileType.litertlm).fromNetwork(modelUrl);

  /// Downloads (or re-activates) the on-device model.
  Future<void> download() async {
    await _init();
    downloadProgress = 0;
    lastError = null;
    notifyListeners();
    try {
      await _builder().withProgress((p) {
        downloadProgress = p;
        notifyListeners();
      }).install();
      _activated = true;
    } catch (e) {
      lastError = '$e';
      rethrow;
    } finally {
      downloadProgress = null;
      notifyListeners();
    }
  }

  Future<void> deleteModel() async {
    await _init();
    for (final id in await FlutterEdgeAi.listInstalledModels()) {
      if (id.contains('gemma-4-E2B')) await FlutterEdgeAi.uninstallModel(id);
    }
    _activated = false;
    notifyListeners();
  }

  Future<InferenceModel> _model() async {
    await _init();
    if (!_activated) {
      // Already downloaded: this only registers it as the active model.
      await _builder().install();
      _activated = true;
    }
    return FlutterEdgeAi.getActiveModel(maxTokens: 2048, supportImage: true, maxNumImages: 1);
  }

  Future<String> _askGemma(String prompt, {Uint8List? image}) async {
    final model = await _model();
    final chat = await model.createChat(supportImage: image != null, temperature: 0.2, topK: 40);
    await chat.addQueryChunk(image == null
        ? Message.text(text: prompt, isUser: true)
        : Message.withImage(text: prompt, imageBytes: image, isUser: true));
    final out = StringBuffer();
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) out.write(r.token);
    }
    return out.toString();
  }

  Future<String> _askGemini(String key, String model, String prompt, {Uint8List? image}) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            if (image != null) {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(image)}},
          ],
        },
      ],
      'generationConfig': {'temperature': 0.2, 'responseMimeType': 'application/json'},
    };
    final r = await http
        .post(uri, headers: {'Content-Type': 'application/json', 'x-goog-api-key': key}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception('Gemini ${r.statusCode}: ${r.body.length > 300 ? r.body.substring(0, 300) : r.body}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final parts = (j['candidates'] as List).first['content']['parts'] as List;
    return parts.map((p) => p['text'] ?? '').join();
  }

  String _prompt(String lang, {String? text, bool photo = false, bool recipe = false}) {
    final language = lang == 'ar' ? 'Arabic' : 'English';
    final task = recipe
        ? 'Read this recipe and list every ingredient with its raw weight in grams.'
        : photo
            ? 'Identify every food and drink in this photo and estimate the portion weight in grams.'
            : 'The user describes what they ate. List each food and drink with its weight in grams.';
    return '''
You are a careful nutrition assistant. $task
Use typical home portions when the amount is not given (for example 1 loaf of Egyptian bread = 100 g, 1 egg = 50 g, 1 cup cooked rice = 160 g, 1 tsp sugar = 4 g).
Give the calories and macros for that weight.
Write food names in $language, short and common (e.g. "${lang == 'ar' ? 'فول مدمس' : 'ful medames'}").
Reply with JSON only, no other text:
{"items":[{"name":"...","grams":0,"kcal":0,"protein":0,"carbs":0,"fat":0}]}
${text == null ? '' : '\nText: $text'}''';
  }

  /// Which engine will answer, given the settings.
  String engineFor(SharedPreferences prefs, {required bool photo}) {
    final key = prefs.getString('geminiKey') ?? '';
    final preferGemini = prefs.getBool('geminiForPhotos') ?? true;
    if (key.isNotEmpty && (photo ? preferGemini : !deviceSupported)) return 'gemini';
    if (deviceSupported) return 'gemma';
    return key.isNotEmpty ? 'gemini' : 'none';
  }

  Future<List<AiItem>> recognise(SharedPreferences prefs, String lang, {String? text, Uint8List? image, bool recipe = false}) async {
    final prompt = _prompt(lang, text: text, photo: image != null, recipe: recipe);
    final engine = engineFor(prefs, photo: image != null);
    final String raw;
    switch (engine) {
      case 'gemini':
        raw = await _askGemini(prefs.getString('geminiKey')!, prefs.getString('geminiModel') ?? 'gemini-flash-latest', prompt, image: image);
      case 'gemma':
        if (!await modelInstalled()) throw const AiNotReady();
        raw = await _askGemma(prompt, image: image);
      default:
        throw const AiNotReady();
    }
    final items = _parse(raw);
    await _matchDatabase(items, lang);
    return items;
  }

  List<AiItem> _parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) throw FormatException('The AI answer was not readable:\n$raw');
    final j = jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return [
      for (final it in (j['items'] as List? ?? const []).cast<Map<String, dynamic>>())
        if ((it['name'] ?? '').toString().trim().isNotEmpty)
          AiItem(it['name'].toString().trim(), d(it['grams']), Nutrition(d(it['kcal']), d(it['protein']), d(it['carbs']), d(it['fat']))),
    ];
  }

  /// Prefer the app's own numbers when a close match exists (own foods, recipes, world dishes).
  Future<void> _matchDatabase(List<AiItem> items, String lang) async {
    for (final it in items) {
      final results = await Repo.search(it.name, limit: 3);
      if (results.isEmpty) continue;
      final best = results.first;
      if (best.src == FoodSource.usda) continue; // too many near-misses in the big table
      final a = normalize(it.name), b = normalize(best.name(lang));
      if (b.contains(a) || a.contains(b) || normalize(best.nameEn).contains(a)) it.match = best;
    }
  }
}

class AiNotReady implements Exception {
  const AiNotReady();
}
