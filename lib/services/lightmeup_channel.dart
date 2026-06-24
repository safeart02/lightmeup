// lib/services/lightmeup_channel.dart — complete replacement
//
// Changes vs original:
//   • startOverlay()             — start the system-overlay window
//   • stopOverlay()              — stop it
//   • setOverlayFocusable(bool)  — toggle input interception
//   • isOverlayRunning()         — query service state
//   • isOverlayPermissionGranted() — check SYSTEM_ALERT_WINDOW
//   All original methods are unchanged.

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/led_colors.dart';

/// Thin wrapper around the MethodChannel + EventChannel that talks to
/// [LightmeupService] (and [OverlayService]) on the native (Kotlin) side.
///
/// Channel names must match exactly what is declared in MainActivity.kt.
class LightmeupChannel {
  static const _methodChannel = MethodChannel(
    'com.example.lightmeup/lightmeup',
  );

  static const _eventChannel = EventChannel('com.example.lightmeup/colors');

  // ── Colour stream ──────────────────────────────────────────────────────

  /// Broadcasts the current left/right LED colours as computed by the native
  /// service. Events are already throttled to ~15 fps on the Kotlin side.
  ///
  /// Emits [LedColors.black] as a sentinel when the service stops.
  /// The stream stays alive across start/stop cycles — callers should not
  /// cancel and re-subscribe; just let it run and react to values.
  Stream<LedColors> get colorStream => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => LedColors.fromMap(event as Map<dynamic, dynamic>));

  // ── LightmeupService control (unchanged) ──────────────────────────────

  /// Ask the user for MediaProjection permission and start the capture loop.
  Future<bool> startService(AppSettings settings) async {
    try {
      debugPrint(
        '[LightmeupChannel] calling startService with: '
        'brightness=${settings.brightness}, frameSkip=${settings.frameSkip}, '
        'smoothing=${settings.smoothing}, zoneWidth=${settings.zoneWidth}',
      );

      final result = await _methodChannel.invokeMethod<bool>('startService', {
        'brightness': settings.brightness,
        'frameSkip': settings.frameSkip,
        'smoothing': settings.smoothing,
        'zoneWidth': settings.zoneWidth,
      });

      debugPrint('[LightmeupChannel] startService returned: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        '[LightmeupChannel] startService PlatformException: '
        'code=${e.code}, message=${e.message}, details=${e.details}',
      );
      return false;
    } catch (e) {
      debugPrint('[LightmeupChannel] startService unexpected error: $e');
      return false;
    }
  }

  Future<bool> isRunning() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isRunning') ?? false;
      debugPrint('[LightmeupChannel] isRunning: $result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[LightmeupChannel] isRunning error: ${e.message}');
      return false;
    }
  }

  /// Stop the capture loop and restore LEDs to a neutral state.
  Future<void> stopService() async {
    try {
      await _methodChannel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      debugPrint('stopService error: ${e.message}');
    }
  }

  /// Push updated settings to the already-running service (no restart needed).
  Future<void> updateSettings(AppSettings settings) async {
    try {
      await _methodChannel.invokeMethod('updateSettings', {
        'brightness': settings.brightness,
        'frameSkip': settings.frameSkip,
        'smoothing': settings.smoothing,
        'zoneWidth': settings.zoneWidth,
      });
    } on PlatformException catch (e) {
      debugPrint('updateSettings error: ${e.message}');
    }
  }

  // ── OverlayService control (new) ───────────────────────────────────────

  /// Start the system-overlay window (requires SYSTEM_ALERT_WINDOW).
  ///
  /// If the permission hasn't been granted yet, Android will open the
  /// "Display over other apps" settings page for the user.
  ///
  /// Returns:
  ///   true  — OverlayService started successfully.
  ///   false — permission was denied by the user.
  Future<bool> startOverlay() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('startOverlay') ?? false;
      debugPrint('[LightmeupChannel] startOverlay: $result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[LightmeupChannel] startOverlay error: ${e.message}');
      return false;
    }
  }

  /// Stop the overlay window.
  Future<void> stopOverlay() async {
    try {
      await _methodChannel.invokeMethod('stopOverlay');
    } on PlatformException catch (e) {
      debugPrint('[LightmeupChannel] stopOverlay error: ${e.message}');
    }
  }

  /// Tell the overlay window whether it should intercept all input
  /// ([focusable] = true, panel open) or pass everything through
  /// ([focusable] = false, panel closed).
  ///
  /// Call this from the overlay Flutter side (overlay_main.dart) whenever
  /// a panel opens or closes.
  Future<void> setOverlayFocusable(bool focusable) async {
    try {
      await _methodChannel.invokeMethod('setOverlayFocusable', {
        'focusable': focusable,
      });
    } on PlatformException catch (e) {
      debugPrint('[LightmeupChannel] setOverlayFocusable error: ${e.message}');
    }
  }

  /// Whether the OverlayService is currently running.
  Future<bool> isOverlayRunning() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isOverlayRunning') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[LightmeupChannel] isOverlayRunning error: ${e.message}');
      return false;
    }
  }

  /// Whether Android's SYSTEM_ALERT_WINDOW permission is already granted.
  /// Use this to decide whether to show an explanation before calling
  /// [startOverlay].
  Future<bool> isOverlayPermissionGranted() async {
    try {
      return await _methodChannel.invokeMethod<bool>(
            'isOverlayPermissionGranted',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint(
        '[LightmeupChannel] isOverlayPermissionGranted error: ${e.message}',
      );
      return false;
    }
  }
}
