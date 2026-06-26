// haptic_service.dart
//
// "3D-feeling" haptic feedback using package:vibration ^3.2.0.
//
// Android VibrationEffect.createWaveform rule (hard requirement):
//   timings.length == amplitudes.length — always.
//   Use amplitude 0 for every wait/off slot; motor-off is just amp = 0.
//
// Pattern layout:  [wait_ms, vibrate_ms, wait_ms, vibrate_ms, …]
// Intensities:     [0,       amp,        0,        amp,        …]
//
// Amplitude guide (1–255)
//   40–60   whisper  — bare tick, nav movement
//   80–110  click    — clear nav enter/back
//   140–170 medium   — confirm, mode select
//   200–230 strong   — service toggle
//   255     peak     — end-stop wall hit

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class HapticService {
  // ── Capability cache ────────────────────────────────────────────────────────

  static bool? _hasAmplitude;
  static bool? _hasCustom;

  /// Optional warm-up call in main() after WidgetsFlutterBinding.
  static Future<void> init() async {
    _hasAmplitude = await Vibration.hasAmplitudeControl() ?? false;
    _hasCustom = await Vibration.hasCustomVibrationsSupport() ?? false;
  }

  static Future<bool> get _amplitude async {
    _hasAmplitude ??= await Vibration.hasAmplitudeControl() ?? false;
    return _hasAmplitude!;
  }

  static Future<bool> get _custom async {
    _hasCustom ??= await Vibration.hasCustomVibrationsSupport() ?? false;
    return _hasCustom!;
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  /// D-pad up/down in the sidebar — whisper tick.
  static Future<void> navMove() async {
    if (await _amplitude) {
      Vibration.vibrate(duration: 18, amplitude: 52);
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Entering a section (A / ►) — quick double-pop, rising.
  static Future<void> navEnter() async {
    if (await _custom) {
      // pattern:     [wait, on,  wait, on ]
      // intensities: [0,    95,  0,    120]
      Vibration.vibrate(pattern: [0, 14, 30, 14], intensities: [0, 95, 0, 120]);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  /// Leaving a section (B / ◄) — double-pop, falling.
  static Future<void> navBack() async {
    if (await _custom) {
      // pattern:     [wait, on,  wait, on ]
      // intensities: [0,    110, 0,    70 ]
      Vibration.vibrate(pattern: [0, 14, 28, 10], intensities: [0, 110, 0, 70]);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  // ── Slider ─────────────────────────────────────────────────────────────────

  /// One detent of slider movement.
  /// [value] is normalised 0.0→1.0 across the slider range.
  /// Amplitude ramps from 40 (bottom) to 140 (top).
  static Future<void> sliderDetent(double value) async {
    if (await _amplitude) {
      final amp = (40 + (value.clamp(0.0, 1.0) * 100)).round();
      Vibration.vibrate(duration: 14, amplitude: amp);
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Slider hit its minimum or maximum — hard impact + soft echo.
  static Future<void> sliderEndStop() async {
    if (await _custom) {
      // pattern:     [wait, on,  wait, on ]
      // intensities: [0,    255, 0,    90 ]
      Vibration.vibrate(pattern: [0, 25, 18, 15], intensities: [0, 255, 0, 90]);
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  // ── Mode / section select ───────────────────────────────────────────────────

  /// Touch-tap on a nav item or mode tile — crisp double-tap.
  static Future<void> modeSelect() async {
    if (await _custom) {
      // pattern:     [wait, on,  wait, on ]
      // intensities: [0,    140, 0,    160]
      Vibration.vibrate(
        pattern: [0, 12, 24, 12],
        intensities: [0, 140, 0, 160],
      );
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  // ── Service toggle ──────────────────────────────────────────────────────────

  /// Service switching ON — three-step rising sweep.
  static Future<void> serviceOn() async {
    if (await _custom) {
      // pattern:     [wait, on,  wait, on,  wait, on ]
      // intensities: [0,    80,  0,    150, 0,    220]
      Vibration.vibrate(
        pattern: [0, 18, 22, 22, 22, 30],
        intensities: [0, 80, 0, 150, 0, 220],
      );
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  /// Service switching OFF — three-step falling decay.
  static Future<void> serviceOff() async {
    if (await _custom) {
      // pattern:     [wait, on,  wait, on,  wait, on ]
      // intensities: [0,    210, 0,    130, 0,    55 ]
      Vibration.vibrate(
        pattern: [0, 28, 18, 20, 18, 14],
        intensities: [0, 210, 0, 130, 0, 55],
      );
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  // ── Confirm ─────────────────────────────────────────────────────────────────

  /// A/B confirm out of a slider, or any decisive action.
  static Future<void> confirm() async {
    if (await _amplitude) {
      Vibration.vibrate(duration: 20, amplitude: 155);
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  // ── Colour picker drag ──────────────────────────────────────────────────────

  /// Fire while dragging hue bar or sat/val box (throttle at call-site to
  /// ~16 ms to avoid stacking).
  /// [intensity] 0.0–1.0 maps drag speed to rumble softness.
  static Future<void> colorPickerDrag({double intensity = 0.5}) async {
    if (await _amplitude) {
      final amp = (30 + (intensity.clamp(0.0, 1.0) * 60)).round();
      Vibration.vibrate(duration: 12, amplitude: amp);
    }
    // No fallback — silent on unsupported hardware is fine for continuous drag.
  }

  // ── Row move inside a section ───────────────────────────────────────────────

  /// D-pad up/down inside a section's setting rows — slightly heavier than navMove.
  static Future<void> rowMove() async {
    if (await _amplitude) {
      Vibration.vibrate(duration: 12, amplitude: 70);
    } else {
      HapticFeedback.selectionClick();
    }
  }
}
