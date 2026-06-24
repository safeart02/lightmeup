import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import 'settings_service.dart';
import 'lightmeup_channel.dart';

/// Central state object consumed by all UI screens via [Provider].
class AppState extends ChangeNotifier {
  AppState({
    required SettingsService settingsService,
    required LightmeupChannel channel,
  }) : _settingsService = settingsService,
       _channel = channel;

  final SettingsService _settingsService;
  final LightmeupChannel _channel;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    _settings = await _settingsService.load();
    // Only check native side on first load, not on rebuilds
    if (!_isRunning) {
      _isRunning = await _channel.isRunning();
    }
    _isLoading = false;
    notifyListeners();
  }

  // ── Service control ────────────────────────────────────────────────────────

  Future<void> toggleService() async {
    debugPrint('[AppState] toggleService called, _isRunning=$_isRunning');
    if (_isRunning) {
      await _channel.stopService();
      _isRunning = false;
      _settings = _settings.copyWith(serviceEnabled: false);
    } else {
      final started = await _channel.startService(_settings);
      debugPrint('[AppState] startService returned: $started');
      _isRunning = started;
      _settings = _settings.copyWith(serviceEnabled: started);
    }
    await _settingsService.save(_settings);
    debugPrint('[AppState] after toggle, _isRunning=$_isRunning');
    notifyListeners();
  }

  // ── Settings mutations ─────────────────────────────────────────────────────

  Future<void> updateBrightness(double value) => _update(
    _settings.copyWith(brightness: value),
    push: true, // brightness change takes effect immediately
  );

  Future<void> updateFrameSkip(int value) =>
      _update(_settings.copyWith(frameSkip: value), push: true);

  Future<void> updateSmoothing(double value) =>
      _update(_settings.copyWith(smoothing: value), push: true);

  Future<void> updateZoneWidth(double value) =>
      _update(_settings.copyWith(zoneWidth: value), push: true);

  /// Internal: persist + optionally push to the live native service.
  Future<void> _update(AppSettings next, {bool push = false}) async {
    _settings = next;
    await _settingsService.save(_settings);
    if (push && _isRunning) {
      await _channel.updateSettings(_settings);
    }
    notifyListeners();
  }
}
