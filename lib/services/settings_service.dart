import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_settings.dart';

/// Persists [AppSettings] to encrypted on-device storage.
class SettingsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Keys we store — kept flat so we can update individual fields cheaply.
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
    return AppSettings.fromMap(Map.fromEntries(entries));
  }

  Future<void> save(AppSettings settings) async {
    final map = settings.toMap();
    await Future.wait(
      map.entries.map((e) => _storage.write(key: e.key, value: e.value)),
    );
  }

  /// Convenience: update a single field without reading everything first.
  Future<void> saveField(String key, String value) =>
      _storage.write(key: key, value: value);
}
