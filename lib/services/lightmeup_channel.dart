import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/led_colors.dart';
import '../models/led_effect.dart';

/// Thin wrapper around the MethodChannel + EventChannel that talks to
/// [LightmeupService] on the native (Kotlin) side.
///
/// Channel names must match exactly what is declared in MainActivity.kt.
class LightmeupChannel {
  static const _methodChannel = MethodChannel(
    'com.example.lightmeup/lightmeup',
  );

  static const _eventChannel = EventChannel('com.example.lightmeup/colors');

  // ── Colour stream ──────────────────────────────────────────────────────

  Stream<LedColors> get colorStream => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => LedColors.fromMap(event as Map<dynamic, dynamic>));

  // ── Service control ────────────────────────────────────────────────────

  Future<bool> startService(AppSettings settings) async {
    try {
      debugPrint(
        '[LightmeupChannel] calling startService with: '
        'brightness=${settings.brightness}, frameSkip=${settings.frameSkip}, '
        'smoothing=${settings.smoothing}, zoneWidth=${settings.zoneWidth}, '
        'effect=${settings.ledEffect.name}',
      );

      final result = await _methodChannel.invokeMethod<bool>('startService', {
        'brightness': settings.brightness,
        'frameSkip': settings.frameSkip,
        'smoothing': settings.smoothing,
        'zoneWidth': settings.zoneWidth,
        // Send effect config at start so the service knows what mode to run.
        ...settings.effectConfig.toChannelMap(settings.ledEffect),
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

  Future<void> stopService() async {
    try {
      await _methodChannel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      debugPrint('stopService error: ${e.message}');
    }
  }

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

  /// Push a live effect change to the running service without restarting.
  Future<void> updateEffect(LedEffectMode mode, LedEffectConfig config) async {
    try {
      debugPrint('[LightmeupChannel] updateEffect: ${mode.name}');
      await _methodChannel.invokeMethod(
        'updateEffect',
        config.toChannelMap(mode),
      );
    } on PlatformException catch (e) {
      debugPrint('updateEffect error: ${e.message}');
    }
  }
}
