import 'dart:convert';
import 'package:flutter/material.dart';

/// All available LED effect modes.
enum LedEffectMode {
  ambientSync,
  solidColor,
  splitColor,
  breathing,
  strobe,
  rainbow,
  colorCycle,
}

extension LedEffectModeLabel on LedEffectMode {
  String get label => switch (this) {
    LedEffectMode.ambientSync => 'Ambient Sync',
    LedEffectMode.solidColor => 'Solid Color',
    LedEffectMode.splitColor => 'Split Color',
    LedEffectMode.breathing => 'Breathing',
    LedEffectMode.strobe => 'Strobe',
    LedEffectMode.rainbow => 'Rainbow',
    LedEffectMode.colorCycle => 'Color Cycle',
  };

  String get description => switch (this) {
    LedEffectMode.ambientSync => 'Match LEDs to on-screen colors',
    LedEffectMode.solidColor => 'Both sticks show one static color',
    LedEffectMode.splitColor => 'Set left and right sticks independently',
    LedEffectMode.breathing => 'Pulse brightness in and out',
    LedEffectMode.strobe => 'Rapid flash at adjustable speed',
    LedEffectMode.rainbow => 'Cycle through the full color spectrum',
    LedEffectMode.colorCycle => 'Cycle through your chosen colors',
  };

  String get icon => switch (this) {
    LedEffectMode.ambientSync => '◈',
    LedEffectMode.solidColor => '■',
    LedEffectMode.splitColor => '◧',
    LedEffectMode.breathing => '◉',
    LedEffectMode.strobe => '◆',
    LedEffectMode.rainbow => '◈',
    LedEffectMode.colorCycle => '◐',
  };
}

/// Configuration parameters for all effect modes.
/// Unused fields are ignored by each mode.
class LedEffectConfig {
  /// Solid / breathing / strobe / colorCycle primary color (left stick).
  final Color primaryColor;

  /// Right stick color for splitColor mode.
  final Color secondaryColor;

  /// Speed for animated effects. 0.0 = slowest, 1.0 = fastest.
  final double speed;

  /// For strobe: duty cycle (fraction of time the LED is on). 0.1–0.9.
  final double dutyCycle;

  /// Colors to cycle through in colorCycle mode. Min 2, max 8.
  final List<Color> cycleColors;

  /// Whether left and right move in sync or offset for breathing / rainbow.
  final bool mirrorSides;

  const LedEffectConfig({
    this.primaryColor = const Color(0xFF00D4FF),
    this.secondaryColor = const Color(0xFF9B6BFF),
    this.speed = 0.5,
    this.dutyCycle = 0.5,
    this.cycleColors = const [
      Color(0xFF00D4FF),
      Color(0xFF9B6BFF),
      Color(0xFF00FF88),
      Color(0xFFFF4466),
    ],
    this.mirrorSides = true,
  });

  LedEffectConfig copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    double? speed,
    double? dutyCycle,
    List<Color>? cycleColors,
    bool? mirrorSides,
  }) {
    return LedEffectConfig(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      speed: speed ?? this.speed,
      dutyCycle: dutyCycle ?? this.dutyCycle,
      cycleColors: cycleColors ?? this.cycleColors,
      mirrorSides: mirrorSides ?? this.mirrorSides,
    );
  }

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
    'primaryColor': primaryColor.value,
    'secondaryColor': secondaryColor.value,
    'speed': speed,
    'dutyCycle': dutyCycle,
    'cycleColors': cycleColors.map((c) => c.value).toList(),
    'mirrorSides': mirrorSides,
  };

  String toJson() => jsonEncode(toMap());

  factory LedEffectConfig.fromMap(Map<String, dynamic> m) {
    List<Color> cycles = const [
      Color(0xFF00D4FF),
      Color(0xFF9B6BFF),
      Color(0xFF00FF88),
      Color(0xFFFF4466),
    ];
    if (m['cycleColors'] is List) {
      final raw = (m['cycleColors'] as List).cast<int>();
      if (raw.isNotEmpty) cycles = raw.map((v) => Color(v)).toList();
    }
    return LedEffectConfig(
      primaryColor: Color(m['primaryColor'] as int? ?? 0xFF00D4FF),
      secondaryColor: Color(m['secondaryColor'] as int? ?? 0xFF9B6BFF),
      speed: (m['speed'] as num?)?.toDouble() ?? 0.5,
      dutyCycle: (m['dutyCycle'] as num?)?.toDouble() ?? 0.5,
      cycleColors: cycles,
      mirrorSides: m['mirrorSides'] as bool? ?? true,
    );
  }

  factory LedEffectConfig.fromJson(String raw) {
    try {
      return LedEffectConfig.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const LedEffectConfig();
    }
  }

  // ── Channel map (sent to Kotlin via MethodChannel) ─────────────────────

  /// Returns a flat Map<String, dynamic> ready to pass over the MethodChannel.
  Map<String, dynamic> toChannelMap(LedEffectMode mode) => {
    'mode': mode.name,
    'primaryColor': primaryColor.value,
    'secondaryColor': secondaryColor.value,
    'speed': speed,
    'dutyCycle': dutyCycle,
    'cycleColors': cycleColors.map((c) => c.value).toList(),
    'mirrorSides': mirrorSides,
  };
}
