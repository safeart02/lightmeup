import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../widgets/bottom_bar.dart';
import '../../services/app_state.dart';
import '../services/lightmeup_channel.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final captureGranted = state.isRunning;

    return SectionScaffold(
      title: 'About',
      description: 'Service info and permissions',
      children: [
        SettingGroup(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description text
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
                              ' in the sidebar to grant screen capture permission.'
                              ' The service runs in the background when you leave'
                              ' the app, continuing to sync your LED strip to'
                              ' on-screen content.',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Info chips row
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

                  const SizedBox(height: 20),

                  // Quick Settings tile row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'QUICK SETTINGS TILE',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 7,
                              letterSpacing: 2.0,
                              color: ConsoleColors.text3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Start/stop from notification panel',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: ConsoleColors.text2,
                            ),
                          ),
                        ],
                      ),
                      _AddTileButton(),
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

// ── Add Tile button ────────────────────────────────────────────────────────────

class _AddTileButton extends StatefulWidget {
  const _AddTileButton();

  @override
  State<_AddTileButton> createState() => _AddTileButtonState();
}

class _AddTileButtonState extends State<_AddTileButton> {
  bool _requested = false;

  Future<void> _onPressed() async {
    await LightmeupChannel().requestAddTile();
    setState(() => _requested = true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _requested ? null : _onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _requested ? ConsoleColors.panel2 : ConsoleColors.cyanDim,
          border: Border.all(
            color: _requested ? ConsoleColors.border2 : ConsoleColors.cyan,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _requested ? 'REQUESTED' : 'ADD TILE',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: _requested ? ConsoleColors.text3 : ConsoleColors.cyan,
          ),
        ),
      ),
    );
  }
}
