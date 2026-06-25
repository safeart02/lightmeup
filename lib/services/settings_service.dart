import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keys = [
    'serviceEnabled',
    'brightness',
    'frameSkip',
    'smoothing',
    'zoneWidth',
  ];

  Future<AppSettings> load() async {
    final entries = await Future.wait(
      _keys.map((k) async => MapEntry(k, await _storage.read(key: k))),
    );
    final map = Map<String, String?>.fromEntries(entries);

    // Load key combos from regular prefs
    final prefs = await SharedPreferences.getInstance();
    map['quickPanelLeftKeys'] = prefs.getString('quickPanelLeftKeys');
    map['quickPanelRightKeys'] = prefs.getString('quickPanelRightKeys');

    return AppSettings.fromMap(map);
  }

  Future<void> save(AppSettings settings) async {
    // Existing secure fields
    final map = settings.toMap();
    await Future.wait(_keys.map((k) => _storage.write(key: k, value: map[k])));

    // Key combos go to regular SharedPreferences so Kotlin can read them
    final prefs = await SharedPreferences.getInstance();
    final leftVal =
        settings.quickPanelLeftKeys?.map((k) => k.keyId).join(',') ?? '';
    final rightVal =
        settings.quickPanelRightKeys?.map((k) => k.keyId).join(',') ?? '';
    await prefs.setString('quickPanelLeftKeys', leftVal);
    await prefs.setString('quickPanelRightKeys', rightVal);
  }

  Future<void> saveField(String key, String value) =>
      _storage.write(key: key, value: value);
}
