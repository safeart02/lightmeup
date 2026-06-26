import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';
import '../models/led_colors.dart';
import '../models/led_effect.dart';
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

  // ── Live LED colours ───────────────────────────────────────────────────

  LedColors _currentColors = LedColors.black;
  LedColors get currentColors => _currentColors;

  StreamSubscription<LedColors>? _colorSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> init() async {
    _settings = await _settingsService.load();
    if (!_isRunning) {
      _isRunning = await _channel.isRunning();
    }
    _isLoading = false;

    _colorSub = _channel.colorStream.listen((colors) {
      _currentColors = colors;
      notifyListeners();
    }, onError: (e) => debugPrint('[AppState] colorStream error: $e'));

    notifyListeners();
  }

  @override
  void dispose() {
    _colorSub?.cancel();
    super.dispose();
  }

  // ── Service control ────────────────────────────────────────────────────

  Future<void> toggleService() async {
    debugPrint('[AppState] toggleService called, _isRunning=$_isRunning');
    if (_isRunning) {
      await _channel.stopService();
      _isRunning = false;
      _settings = _settings.copyWith(serviceEnabled: false);
      _currentColors = LedColors.black;
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

  // ── Settings mutations ─────────────────────────────────────────────────

  Future<void> updateBrightness(double value) =>
      _update(_settings.copyWith(brightness: value), push: true);

  Future<void> updateFrameSkip(int value) =>
      _update(_settings.copyWith(frameSkip: value), push: true);

  Future<void> updateSmoothing(double value) =>
      _update(_settings.copyWith(smoothing: value), push: true);

  Future<void> updateZoneWidth(double value) =>
      _update(_settings.copyWith(zoneWidth: value), push: true);

  // ── Key binding mutations ──────────────────────────────────────────────

  Future<void> setQuickPanelLeftKey(LogicalKeyboardKey? key) =>
      _update(_settings.copyWith(quickPanelLeftKey: key));

  Future<void> setQuickPanelRightKey(LogicalKeyboardKey? key) =>
      _update(_settings.copyWith(quickPanelRightKey: key));

  // ── Effect mutations ───────────────────────────────────────────────────

  /// Change the active LED effect mode. Pushes to the service immediately
  /// if it's running.
  Future<void> setLedEffect(LedEffectMode mode) async {
    final next = _settings.copyWith(ledEffect: mode);
    _settings = next;
    await _settingsService.save(_settings);
    if (_isRunning) {
      await _channel.updateEffect(_settings.ledEffect, _settings.effectConfig);
    }
    notifyListeners();
  }

  /// Update effect config (color, speed, etc.). Pushes live if running.
  Future<void> updateEffectConfig(LedEffectConfig config) async {
    final next = _settings.copyWith(effectConfig: config);
    _settings = next;
    await _settingsService.save(_settings);
    if (_isRunning) {
      await _channel.updateEffect(_settings.ledEffect, _settings.effectConfig);
    }
    notifyListeners();
  }

  // ── Internal ───────────────────────────────────────────────────────────

  Future<void> _update(AppSettings next, {bool push = false}) async {
    _settings = next;
    await _settingsService.save(_settings);
    if (push && _isRunning) {
      await _channel.updateSettings(_settings);
    }
    notifyListeners();
  }
}
