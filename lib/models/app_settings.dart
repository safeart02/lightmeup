import 'package:flutter/material.dart';

/// All user-configurable settings. Serialised to/from flutter_secure_storage.
class AppSettings {
  /// Master on/off for the ambient service
  final bool serviceEnabled;

  /// Brightness sent to led_light_brightness_percent (0.0–1.0)
  final double brightness;

  /// How many screen frames to skip between LED updates.
  /// 0 = every frame, 1 = every other frame, etc.
  /// Higher = less CPU, slower reaction.
  final int frameSkip;

  /// Colour smoothing: 0.0 = instant snap, 1.0 = never changes.
  /// Applied as:  newColor = lerp(currentColor, sampledColor, 1 - smoothing)
  final double smoothing;

  /// Left zone width as a fraction of screen width (e.g. 0.15 = leftmost 15%)
  final double zoneWidth;

  const AppSettings({
    this.serviceEnabled = false,
    this.brightness = 0.6,
    this.frameSkip = 1,
    this.smoothing = 0.35,
    this.zoneWidth = 0.15,
  });

  AppSettings copyWith({
    bool? serviceEnabled,
    double? brightness,
    int? frameSkip,
    double? smoothing,
    double? zoneWidth,
  }) {
    return AppSettings(
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      brightness: brightness ?? this.brightness,
      frameSkip: frameSkip ?? this.frameSkip,
      smoothing: smoothing ?? this.smoothing,
      zoneWidth: zoneWidth ?? this.zoneWidth,
    );
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, String> toMap() => {
        'serviceEnabled': serviceEnabled.toString(),
        'brightness': brightness.toString(),
        'frameSkip': frameSkip.toString(),
        'smoothing': smoothing.toString(),
        'zoneWidth': zoneWidth.toString(),
      };

  factory AppSettings.fromMap(Map<String, String?> m) => AppSettings(
        serviceEnabled: m['serviceEnabled'] == 'true',
        brightness: double.tryParse(m['brightness'] ?? '') ?? 0.6,
        frameSkip: int.tryParse(m['frameSkip'] ?? '') ?? 1,
        smoothing: double.tryParse(m['smoothing'] ?? '') ?? 0.35,
        zoneWidth: double.tryParse(m['zoneWidth'] ?? '') ?? 0.15,
      );
}
