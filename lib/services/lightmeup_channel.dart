import 'package:flutter/services.dart';
import '../models/app_settings.dart';
import 'package:flutter/material.dart';

/// Thin wrapper around the MethodChannel that talks to [LightmeupService] on
/// the native (Kotlin) side.
///
/// Channel name must match exactly what is declared in MainActivity.kt.
class LightmeupChannel {
  static const _channel = MethodChannel('com.example.lightmeup/lightmeup');

  /// Ask the user for MediaProjection permission and start the capture loop.
  /// The native side will show the system permission dialog before starting.
  Future<bool> startService(AppSettings settings) async {
    try {
      debugPrint(
        '[LightmeupChannel] calling startService with: '
        'brightness=${settings.brightness}, frameSkip=${settings.frameSkip}, '
        'smoothing=${settings.smoothing}, zoneWidth=${settings.zoneWidth}',
      );

      final result = await _channel.invokeMethod<bool>('startService', {
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
      final result = await _channel.invokeMethod<bool>('isRunning') ?? false;
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
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      print('stopService error: ${e.message}');
    }
  }

  /// Push updated settings to the already-running service (no restart needed).
  Future<void> updateSettings(AppSettings settings) async {
    try {
      await _channel.invokeMethod('updateSettings', {
        'brightness': settings.brightness,
        'frameSkip': settings.frameSkip,
        'smoothing': settings.smoothing,
        'zoneWidth': settings.zoneWidth,
      });
    } on PlatformException catch (e) {
      print('updateSettings error: ${e.message}');
    }
  }
}
