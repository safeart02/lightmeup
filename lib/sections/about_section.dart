// lib/sections/about_section.dart — complete replacement
//
// Changes vs original:
//   • Adds an "Overlay Panel" toggle row so the user can start/stop
//     OverlayService from inside the settings screen.
//   • Uses state.isOverlayRunning and state.toggleOverlay() — both
//     already provided by the updated AppState.
//   Everything else is unchanged.

import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../widgets/bottom_bar.dart';
import '../../services/app_state.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final captureGranted = state.isRunning;
    final overlayRunning = state.isOverlayRunning;

    return SectionScaffold(
      title: 'About',
      description: 'Service info, permissions and overlay',
      children: [
        // ── Overlay toggle ─────────────────────────────────────────────────
        SettingGroup(
          label: 'OVERLAY',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Overlay Panel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: ConsoleColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          overlayRunning
                              ? 'Quick panel active over other apps'
                              : 'Show quick panel above any app',
                          style: const TextStyle(
                            fontSize: 10,
                            color: ConsoleColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => state.toggleOverlay(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: overlayRunning
                            ? ConsoleColors.cyan.withOpacity(0.10)
                            : Colors.transparent,
                        border: Border.all(
                          color: overlayRunning
                              ? ConsoleColors.cyan.withOpacity(0.5)
                              : ConsoleColors.border2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            overlayRunning
                                ? Icons.picture_in_picture_rounded
                                : Icons.picture_in_picture_alt_rounded,
                            size: 13,
                            color: overlayRunning
                                ? ConsoleColors.cyan
                                : ConsoleColors.text2,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            overlayRunning ? 'STOP' : 'START',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: overlayRunning
                                  ? ConsoleColors.cyan
                                  : ConsoleColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── Info ───────────────────────────────────────────────────────────
        SettingGroup(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        color: ConsoleColors.text2,
                        height: 1.7,
                      ),
                      children: [
                        const TextSpan(text: 'Tap '),
                        const TextSpan(
                          text: 'Start Service',
                          style: TextStyle(
                            color: ConsoleColors.cyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(
                          text:
                              ' in the sidebar to grant screen capture '
                              'permission. The service runs in the background '
                              'when you leave the app, continuing to sync your '
                              'LED strip to on-screen content.',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      _InfoChip(
                        label: 'VERSION',
                        value: '2.0.1',
                        valueColor: ConsoleColors.cyan,
                      ),
                      const SizedBox(width: 10),
                      _InfoChip(label: 'TARGET', value: 'Android 10+'),
                      const SizedBox(width: 10),
                      _InfoChip(
                        label: 'CAPTURE',
                        value: captureGranted ? 'Granted' : 'Not granted',
                        valueColor: captureGranted
                            ? ConsoleColors.cyan
                            : ConsoleColors.text,
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Overlay permission status chip
                  Row(
                    children: [
                      _InfoChip(
                        label: 'OVERLAY',
                        value: overlayRunning ? 'Running' : 'Off',
                        valueColor: overlayRunning
                            ? ConsoleColors.cyan
                            : ConsoleColors.text,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Info chip ──────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    this.valueColor = ConsoleColors.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ConsoleColors.panel2,
        border: Border.all(color: ConsoleColors.border2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 7,
              letterSpacing: 2.0,
              color: ConsoleColors.text3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
