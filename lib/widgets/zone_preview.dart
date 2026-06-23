import 'package:flutter/material.dart';

/// Shows a miniature "screen" with coloured left/right capture zones.
/// Updates live as the user drags the Zone Width slider.
class ZonePreview extends StatelessWidget {
  const ZonePreview({super.key, required this.zoneWidth});

  final double zoneWidth; // 0.0–1.0 fraction of screen width

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (_, constraints) {
        final totalW = constraints.maxWidth;
        const h = 90.0;
        final zoneW = totalW * zoneWidth;

        return Container(
          width: totalW,
          height: h,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // Left zone
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: zoneW,
                child: Container(
                  color: cs.primary.withOpacity(0.25),
                  child: Center(
                    child: Icon(Icons.circle,
                        size: 10, color: cs.primary.withOpacity(0.7)),
                  ),
                ),
              ),

              // Right zone
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: zoneW,
                child: Container(
                  color: cs.secondary.withOpacity(0.25),
                  child: Center(
                    child: Icon(Icons.circle,
                        size: 10, color: cs.secondary.withOpacity(0.7)),
                  ),
                ),
              ),

              // Label: Left stick
              Positioned(
                left: 4,
                bottom: 4,
                child: Text('L stick',
                    style: TextStyle(
                        fontSize: 9,
                        color: cs.primary,
                        fontWeight: FontWeight.bold)),
              ),

              // Label: Right stick
              Positioned(
                right: 4,
                bottom: 4,
                child: Text('R stick',
                    style: TextStyle(
                        fontSize: 9,
                        color: cs.secondary,
                        fontWeight: FontWeight.bold)),
              ),

              // Centre label
              Center(
                child: Text(
                  'Game screen',
                  style: TextStyle(
                      fontSize: 11, color: cs.outlineVariant),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
