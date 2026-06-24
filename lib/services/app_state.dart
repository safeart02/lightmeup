import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';
import '../models/led_colors.dart';
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

  /// Exposed so overlay_main.dart can call setOverlayFocusable() directly
  /// without needing a full AppState method for every window-manager call.
  LightmeupChannel get channel => _channel;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // ── Overlay state ────────────────────────────────────────────────

  bool _isOverlayRunning = false;

  /// Whether the system-overlay window (OverlayService) is active.
  bool get isOverlayRunning => _isOverlayRunning;

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
    _isOverlayRunning = await _channel.isOverlayRunning();

    _isLoading = false;

    // Subscribe to the colour stream unconditionally — the native side only
    // emits when the service is running, so we don't need to start/stop the
    // subscription with the service.
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

  // ── LightmeupService control ──────────────────────────────

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

  // ── OverlayService control ───────────────────────────────────────

  /// Start the system-overlay window so the quick panel appears above other
  /// apps. Returns true if the overlay is now running (permission may be
  /// requested from the user if not already granted).
  Future<bool> startOverlay() async {
    if (_isOverlayRunning) return true;
    final ok = await _channel.startOverlay();
    _isOverlayRunning = ok;
    notifyListeners();
    return ok;
  }

  /// Stop the overlay window.
  Future<void> stopOverlay() async {
    await _channel.stopOverlay();
    _isOverlayRunning = false;
    notifyListeners();
  }

  /// Start or stop the overlay window depending on its current state.
  Future<void> toggleOverlay() async {
    if (_isOverlayRunning) {
      await stopOverlay();
    } else {
      await startOverlay();
    }
  }

  // ── Settings mutations ────────────────────────────────────

  Future<void> updateBrightness(double value) =>
      _update(_settings.copyWith(brightness: value), push: true);

  Future<void> updateFrameSkip(int value) =>
      _update(_settings.copyWith(frameSkip: value), push: true);

  Future<void> updateSmoothing(double value) =>
      _update(_settings.copyWith(smoothing: value), push: true);

  Future<void> updateZoneWidth(double value) =>
      _update(_settings.copyWith(zoneWidth: value), push: true);

  // ── Key binding mutations (Updated for combinations) ─────────────────

  Future<void> setQuickPanelLeftKeys(List<LogicalKeyboardKey>? keys) =>
      _update(_settings.copyWith(quickPanelLeftKeys: keys));

  Future<void> setQuickPanelRightKeys(List<LogicalKeyboardKey>? keys) =>
      _update(_settings.copyWith(quickPanelRightKeys: keys));

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
