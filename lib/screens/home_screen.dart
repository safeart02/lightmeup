import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/power_button.dart';
import '../widgets/setting_slider.dart';
import '../widgets/zone_preview.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.light_mode, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            const Text('LightMeUp',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Power toggle ──────────────────────────────────────────────
            Center(
              child: PowerButton(
                isRunning: state.isRunning,
                onTap: () => context.read<AppState>().toggleService(),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                state.isRunning ? "LEDs Active" : "Service stopped",
                style: TextStyle(
                  color: state.isRunning ? cs.primary : cs.outline,
                  fontSize: 13,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Zone preview diagram ──────────────────────────────────────
            _SectionHeader('Zone Preview'),
            const SizedBox(height: 8),
            ZonePreview(zoneWidth: state.settings.zoneWidth),

            const SizedBox(height: 28),

            // ── Brightness ────────────────────────────────────────────────
            _SectionHeader('LED Brightness'),
            SettingSlider(
              value: state.settings.brightness,
              min: 0.05,
              max: 1.0,
              divisions: 19,
              label: '${(state.settings.brightness * 100).round()}%',
              onChanged: (v) => context.read<AppState>().updateBrightness(v),
            ),

            const SizedBox(height: 20),

            // ── Zone width ────────────────────────────────────────────────
            _SectionHeader('Capture Zone Width'),
            _SubLabel('Width of screen edge sampled per stick'),
            SettingSlider(
              value: state.settings.zoneWidth,
              min: 0.05,
              max: 0.40,
              divisions: 7,
              label: '${(state.settings.zoneWidth * 100).round()}%',
              onChanged: (v) => context.read<AppState>().updateZoneWidth(v),
            ),

            const SizedBox(height: 20),

            // ── Colour smoothing ──────────────────────────────────────────
            _SectionHeader('Colour Smoothing'),
            _SubLabel('Higher = smoother transitions, slower response'),
            SettingSlider(
              value: state.settings.smoothing,
              min: 0.0,
              max: 0.95,
              divisions: 19,
              label: state.settings.smoothing == 0.0
                  ? 'Off'
                  : '${(state.settings.smoothing * 100).round()}%',
              onChanged: (v) => context.read<AppState>().updateSmoothing(v),
            ),

            const SizedBox(height: 20),

            // ── Frame skip ────────────────────────────────────────────────
            _SectionHeader('Frame Skip'),
            _SubLabel('Process every Nth frame — higher saves battery'),
            SettingSlider(
              value: state.settings.frameSkip.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              label: state.settings.frameSkip == 0
                  ? 'Every frame'
                  : '1 in ${state.settings.frameSkip + 1}',
              onChanged: (v) =>
                  context.read<AppState>().updateFrameSkip(v.round()),
            ),

            const SizedBox(height: 40),

            // ── Info card ─────────────────────────────────────────────────
            _InfoCard(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Small internal widgets ──────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tap the power button to grant screen capture permission. '
              'The service continues running when you leave the app.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
