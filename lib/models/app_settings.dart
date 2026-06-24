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

  /// Hardware key combination that opens the LEFT quick panel.
  /// Null / empty = no keys assigned (swipe-only).
  final List<LogicalKeyboardKey>? quickPanelLeftKeys;

  /// Hardware key combination that opens the RIGHT quick panel.
  /// Null / empty = no keys assigned (swipe-only).
  final List<LogicalKeyboardKey>? quickPanelRightKeys;

  const AppSettings({
    this.serviceEnabled = false,
    this.brightness = 0.6,
    this.frameSkip = 1,
    this.smoothing = 0.35,
    this.zoneWidth = 0.15,
    this.quickPanelLeftKeys,
    this.quickPanelRightKeys,
  });

  AppSettings copyWith({
    bool? serviceEnabled,
    double? brightness,
    int? frameSkip,
    double? smoothing,
    double? zoneWidth,
    // Use a sentinel to distinguish "set to null" from "leave unchanged".
    Object? quickPanelLeftKeys = _keep,
    Object? quickPanelRightKeys = _keep,
  }) {
    return AppSettings(
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      brightness: brightness ?? this.brightness,
      frameSkip: frameSkip ?? this.frameSkip,
      smoothing: smoothing ?? this.smoothing,
      zoneWidth: zoneWidth ?? this.zoneWidth,
      quickPanelLeftKeys: quickPanelLeftKeys == _keep
          ? this.quickPanelLeftKeys
          : quickPanelLeftKeys as List<LogicalKeyboardKey>?,
      quickPanelRightKeys: quickPanelRightKeys == _keep
          ? this.quickPanelRightKeys
          : quickPanelRightKeys as List<LogicalKeyboardKey>?,
    );
  }

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, String> toMap() => {
    'serviceEnabled': serviceEnabled.toString(),
    'brightness': brightness.toString(),
    'frameSkip': frameSkip.toString(),
    'smoothing': smoothing.toString(),
    'zoneWidth': zoneWidth.toString(),
    // Join multiple key IDs with commas, empty string if null or empty
    'quickPanelLeftKeys':
        quickPanelLeftKeys?.map((k) => k.keyId).join(',') ?? '',
    'quickPanelRightKeys':
        quickPanelRightKeys?.map((k) => k.keyId).join(',') ?? '',
  };

  factory AppSettings.fromMap(Map<String, String?> m) => AppSettings(
    serviceEnabled: m['serviceEnabled'] == 'true',
    brightness: double.tryParse(m['brightness'] ?? '') ?? 0.6,
    frameSkip: int.tryParse(m['frameSkip'] ?? '') ?? 1,
    smoothing: double.tryParse(m['smoothing'] ?? '') ?? 0.35,
    zoneWidth: double.tryParse(m['zoneWidth'] ?? '') ?? 0.15,
    quickPanelLeftKeys: _parseKeys(
      m['quickPanelLeftKeys'] ?? m['quickPanelLeftKey'],
    ),
    quickPanelRightKeys: _parseKeys(
      m['quickPanelRightKeys'] ?? m['quickPanelRightKey'],
    ),
  );

  /// Parsers comma-separated IDs back into a list of keys. Handles fallback for legacy single key data.
  static List<LogicalKeyboardKey>? _parseKeys(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final List<LogicalKeyboardKey> keys = [];
    final fragments = raw.split(',');

    for (final fragment in fragments) {
      final id = int.tryParse(fragment.trim());
      if (id != null) {
        keys.add(LogicalKeyboardKey(id));
      }
    }

    return keys.isNotEmpty ? keys : null;
  }
}

// Sentinel object used by copyWith to detect "leave unchanged" vs "set null".
const _keep = Object();
