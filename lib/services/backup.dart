import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';

/// A backup is one JSON file: the settings plus the whole database (gzipped, base64).
class Backup {
  static const _skipPrefs = {'gdriveEmail', 'lastBackup'};

  static Future<Uint8List> create(SharedPreferences prefs) async {
    final path = await AppDb.path();
    await AppDb.close(); // make sure everything is flushed to the file
    final bytes = await File(path).readAsBytes();
    await AppDb.open();
    final settings = <String, Object?>{
      for (final k in prefs.getKeys())
        if (!_skipPrefs.contains(k)) k: prefs.get(k),
    };
    final json = jsonEncode({
      'app': 'myfood',
      'format': 1,
      'created': DateTime.now().toIso8601String(),
      'prefs': settings,
      'db': base64Encode(gzip.encode(bytes)),
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Replaces all data with the backup. The caller reloads the app state after.
  static Future<void> restore(SharedPreferences prefs, Uint8List data) async {
    final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    if (j['app'] != 'myfood') throw const FormatException('This is not a My Food backup file.');
    final db = gzip.decode(base64Decode(j['db'] as String));
    final path = await AppDb.path();
    await AppDb.close();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(path).writeAsBytes(db, flush: true);
    await AppDb.open();
    final p = (j['prefs'] as Map).cast<String, Object?>();
    for (final e in p.entries) {
      final v = e.value;
      if (v is bool) await prefs.setBool(e.key, v);
      if (v is int) await prefs.setInt(e.key, v);
      if (v is double) await prefs.setDouble(e.key, v);
      if (v is String) await prefs.setString(e.key, v);
      if (v is List) await prefs.setStringList(e.key, v.cast<String>());
    }
  }

  static String fileName() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'MyFood-backup-${d.year}${two(d.month)}${two(d.day)}.json';
  }
}

/// Backups in the hidden app folder of the user's Google Drive (drive.appdata scope:
/// the app can't see any of your other Drive files).
class DriveBackup {
  /// Android OAuth client from Google Cloud (package com.mahmoud.myfood + the release SHA-1).
  /// Can also be pasted in the app's settings.
  static const builtInClientId = '';

  static const _redirect = 'com.mahmoud.myfood:/oauth2redirect';
  static const _scopes = ['openid', 'email', 'https://www.googleapis.com/auth/drive.appdata'];
  static const _service = AuthorizationServiceConfiguration(
    authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
  );
  static const _fileName = 'myfood-backup.json';
  static const _appAuth = FlutterAppAuth();
  static const _store = FlutterSecureStorage();

  final SharedPreferences prefs;
  DriveBackup(this.prefs);

  String get clientId {
    final custom = prefs.getString('gdriveClientId') ?? '';
    return custom.trim().isNotEmpty ? custom.trim() : builtInClientId;
  }

  bool get configured => clientId.isNotEmpty;
  String? get email => prefs.getString('gdriveEmail');
  bool get signedIn => email != null;

  String? _access;
  DateTime? _expiry;

  Future<void> signIn() async {
    final r = await _appAuth.authorizeAndExchangeCode(AuthorizationTokenRequest(
      clientId,
      _redirect,
      serviceConfiguration: _service,
      scopes: _scopes,
      promptValues: ['select_account', 'consent'],
    ));
    if (r.refreshToken == null) throw StateError('Google did not return a sign-in token. Try again.');
    await _store.write(key: 'gdrive_refresh', value: r.refreshToken);
    _access = r.accessToken;
    _expiry = r.accessTokenExpirationDateTime;
    final p = await http.get(Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'), headers: {'Authorization': 'Bearer $_access'});
    final mail = p.statusCode == 200 ? (jsonDecode(p.body)['email'] as String? ?? 'Google') : 'Google';
    await prefs.setString('gdriveEmail', mail);
  }

  Future<void> signOut() async {
    await _store.delete(key: 'gdrive_refresh');
    await prefs.remove('gdriveEmail');
    _access = null;
  }

  Future<String> _token() async {
    if (_access != null && _expiry != null && DateTime.now().isBefore(_expiry!.subtract(const Duration(minutes: 2)))) return _access!;
    final refresh = await _store.read(key: 'gdrive_refresh');
    if (refresh == null) throw StateError('Sign in to Google again.');
    final r = await _appAuth.token(TokenRequest(clientId, _redirect, refreshToken: refresh, serviceConfiguration: _service, scopes: _scopes));
    _access = r.accessToken;
    _expiry = r.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 50));
    if (r.refreshToken != null) await _store.write(key: 'gdrive_refresh', value: r.refreshToken);
    return _access!;
  }

  Future<Map<String, dynamic>?> _find() async {
    final t = await _token();
    final q = Uri.encodeQueryComponent("name = '$_fileName'");
    final r = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,modifiedTime,size)'),
      headers: {'Authorization': 'Bearer $t'},
    );
    if (r.statusCode != 200) throw Exception('Google Drive: ${r.statusCode} ${r.body}');
    final files = (jsonDecode(r.body)['files'] as List).cast<Map<String, dynamic>>();
    return files.isEmpty ? null : files.first;
  }

  /// When the last backup in Drive was made, or null if there is none.
  Future<DateTime?> lastBackupTime() async {
    final f = await _find();
    return f == null ? null : DateTime.tryParse(f['modifiedTime'] as String);
  }

  Future<void> upload(Uint8List data) async {
    final t = await _token();
    final existing = await _find();
    const boundary = 'myfood-boundary';
    final meta = existing == null ? {'name': _fileName, 'parents': ['appDataFolder']} : <String, Object>{};
    final body = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode(meta)}\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Type: application/json\r\n\r\n'),
      ...data,
      ...utf8.encode('\r\n--$boundary--'),
    ];
    final uri = existing == null
        ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart')
        : Uri.parse('https://www.googleapis.com/upload/drive/v3/files/${existing['id']}?uploadType=multipart');
    final req = http.Request(existing == null ? 'POST' : 'PATCH', uri)
      ..headers['Authorization'] = 'Bearer $t'
      ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
      ..bodyBytes = body;
    final r = await http.Response.fromStream(await req.send());
    if (r.statusCode != 200) throw Exception('Google Drive upload failed: ${r.statusCode}');
    await prefs.setString('lastBackup', DateTime.now().toIso8601String());
  }

  Future<Uint8List?> download() async {
    final f = await _find();
    if (f == null) return null;
    final t = await _token();
    final r = await http.get(Uri.parse('https://www.googleapis.com/drive/v3/files/${f['id']}?alt=media'), headers: {'Authorization': 'Bearer $t'});
    if (r.statusCode != 200) throw Exception('Google Drive download failed: ${r.statusCode}');
    return r.bodyBytes;
  }

  /// Daily automatic backup, run at app start.
  Future<void> autoBackupIfDue() async {
    if (!signedIn || !configured || !(prefs.getBool('autoBackup') ?? true)) return;
    final last = DateTime.tryParse(prefs.getString('lastBackup') ?? '');
    if (last != null && DateTime.now().difference(last).inHours < 24) return;
    await upload(await Backup.create(prefs));
  }
}
