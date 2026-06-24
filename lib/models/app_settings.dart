import 'package:flutter/services.dart';

/// All user-configurable settings. Serialised to/from flutter_secure_storage.
class AppSettings {
  /// Master on/off for the ambient service
  final bool serviceEnabled;

  /// Brightness sent to led_light_brightness_percent (0.0–1.0)
  final double brightness;

  /// How many screen frames to skip between LED updates.
  /// 0 = every frame, 1 = every other frame, etc.
  final int frameSkip;

  /// Colour smoothing: 0.0 = instant snap, 1.0 = never changes.
  final double smoothing;

  /// Left zone width as a fraction of screen width (e.g. 0.15 = leftmost 15%)
  final double zoneWidth;

  /// Hardware key that opens the LEFT quick panel.
  /// Null = no key assigned (swipe-only).
  final LogicalKeyboardKey? quickPanelLeftKey;

  /// Hardware key that opens the RIGHT quick panel.
  /// Null = no key assigned (swipe-only).
  final LogicalKeyboardKey? quickPanelRightKey;

  const AppSettings({
    this.serviceEnabled = false,
    this.brightness = 0.6,
    this.frameSkip = 1,
    this.smoothing = 0.35,
    this.zoneWidth = 0.15,
    this.quickPanelLeftKey,
    this.quickPanelRightKey,
  });

  AppSettings copyWith({
    bool? serviceEnabled,
    double? brightness,
    int? frameSkip,
    double? smoothing,
    double? zoneWidth,
    // Use a sentinel to distinguish "set to null" from "leave unchanged".
    Object? quickPanelLeftKey = _keep,
    Object? quickPanelRightKey = _keep,
  }) {
    return AppSettings(
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      brightness: brightness ?? this.brightness,
      frameSkip: frameSkip ?? this.frameSkip,
      smoothing: smoothing ?? this.smoothing,
      zoneWidth: zoneWidth ?? this.zoneWidth,
      quickPanelLeftKey: quickPanelLeftKey == _keep
          ? this.quickPanelLeftKey
          : quickPanelLeftKey as LogicalKeyboardKey?,
      quickPanelRightKey: quickPanelRightKey == _keep
          ? this.quickPanelRightKey
          : quickPanelRightKey as LogicalKeyboardKey?,
    );
  }

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, String> toMap() => {
    'serviceEnabled': serviceEnabled.toString(),
    'brightness': brightness.toString(),
    'frameSkip': frameSkip.toString(),
    'smoothing': smoothing.toString(),
    'zoneWidth': zoneWidth.toString(),
    // Store as keyId int string, empty string = not assigned.
    'quickPanelLeftKey': quickPanelLeftKey?.keyId.toString() ?? '',
    'quickPanelRightKey': quickPanelRightKey?.keyId.toString() ?? '',
  };

  factory AppSettings.fromMap(Map<String, String?> m) => AppSettings(
    serviceEnabled: m['serviceEnabled'] == 'true',
    brightness: double.tryParse(m['brightness'] ?? '') ?? 0.6,
    frameSkip: int.tryParse(m['frameSkip'] ?? '') ?? 1,
    smoothing: double.tryParse(m['smoothing'] ?? '') ?? 0.35,
    zoneWidth: double.tryParse(m['zoneWidth'] ?? '') ?? 0.15,
    quickPanelLeftKey: _parseKey(m['quickPanelLeftKey']),
    quickPanelRightKey: _parseKey(m['quickPanelRightKey']),
  );

  static LogicalKeyboardKey? _parseKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final id = int.tryParse(raw);
    if (id == null) return null;
    return LogicalKeyboardKey(id);
  }
}

// Sentinel object used by copyWith to detect "leave unchanged" vs "set null".
const _keep = Object();
