import 'package:flutter/material.dart';

/// Holds the current left and right LED zone colours as reported by the
/// native service via the EventChannel stream.
///
/// Both colours are post-saturation-boost and post-brightness — exactly what
/// is sent to the physical LED strip.
class LedColors {
  const LedColors({required this.left, required this.right});

  final Color left;
  final Color right;

  /// Decodes the map pushed by the Kotlin EventChannel sink.
  /// Expects: { 'left': 0xFFrrggbb, 'right': 0xFFrrggbb }
  factory LedColors.fromMap(Map<dynamic, dynamic> map) {
    return LedColors(
      left: Color((map['left'] as int?) ?? 0xFF000000),
      right: Color((map['right'] as int?) ?? 0xFF000000),
    );
  }

  static const black = LedColors(left: Colors.black, right: Colors.black);
}
