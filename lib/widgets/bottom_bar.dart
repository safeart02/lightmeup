import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

// ── Bottom hint bar ───────────────────────────────────────────────────────────

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.isRunning,
    required this.level,
    this.panelOpen = false,
  });

  final bool isRunning;
  final FocusLevel level;

  /// True when either quick panel is open — switches hints to panel context.
  final bool panelOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: ConsoleColors.panel,
        border: Border(top: BorderSide(color: ConsoleColors.border)),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: panelOpen
                // ── Panel-open hints ───────────────────────────────────────
                ? _HintRow(
                    key: const ValueKey('panel'),
                    hints: const [
                      _HintData('↑↓', 'Select'),
                      _HintData('A', 'Adjust'),
                      _HintData('B', 'Close panel'),
                    ],
                  )
                // ── Normal hints ───────────────────────────────────────────
                : switch (level) {
                    FocusLevel.nav => _HintRow(
                      key: const ValueKey('nav'),
                      hints: const [
                        _HintData('↑↓', 'Choose section'),
                        _HintData('A / ►', 'Enter'),
                        _HintData('Y', 'Toggle service'),
                      ],
                    ),
                    FocusLevel.section => _HintRow(
                      key: const ValueKey('section'),
                      hints: const [
                        _HintData('↑↓', 'Choose setting'),
                        _HintData('A', 'Adjust'),
                        _HintData('B / ◄', 'Back'),
                      ],
                    ),
                    FocusLevel.slider => _HintRow(
                      key: const ValueKey('slider'),
                      hints: const [
                        _HintData('◄►', 'Change value'),
                        _HintData('A / B', 'Confirm'),
                        _HintData('Y', 'Toggle service'),
                      ],
                    ),
                  },
          ),
          const Spacer(),
          Container(width: 1, height: 14, color: ConsoleColors.border2),
          const SizedBox(width: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              isRunning ? 'SERVICE ACTIVE' : 'SERVICE OFFLINE',
              key: ValueKey(isRunning),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8,
                letterSpacing: 1.2,
                color: isRunning ? ConsoleColors.cyan : ConsoleColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintData {
  const _HintData(this.button, this.label);
  final String button;
  final String label;
}

class _HintRow extends StatelessWidget {
  const _HintRow({super.key, required this.hints});
  final List<_HintData> hints;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < hints.length; i++) ...[
          if (i > 0) const SizedBox(width: 20),
          _Hint(button: hints[i].button, label: hints[i].label),
        ],
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.button, required this.label});
  final String button;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            border: Border.all(color: ConsoleColors.border2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
            child: Text(
              button,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 8,
                color: ConsoleColors.text2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: ConsoleColors.text2),
        ),
      ],
    );
  }
}

// ── Section scaffold ──────────────────────────────────────────────────────────

class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: ConsoleColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: ConsoleColors.text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 11,
                  color: ConsoleColors.text2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Setting group ─────────────────────────────────────────────────────────────

class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, this.label, required this.children});
  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ConsoleColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                label!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 7,
                  letterSpacing: 2.0,
                  color: ConsoleColors.text3,
                ),
              ),
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}

// ── Slider controller ─────────────────────────────────────────────────────────

/// Callback-based controller so it can be used across files.
/// attach() / detach() are public because Dart's _ prefix is file-private.
class SliderController {
  void Function(int)? _nudgeCallback;

  void attach(void Function(int) callback) => _nudgeCallback = callback;
  void detach() => _nudgeCallback = null;

  void nudge(int direction) => _nudgeCallback?.call(direction);
}

// ── Setting row ───────────────────────────────────────────────────────────────

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.name,
    required this.description,
    required this.control,
    required this.highlighted,
    required this.active,
  });

  final String name;
  final String description;
  final Widget control;
  final bool highlighted;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    final Color bgColor;
    if (active) {
      borderColor = ConsoleColors.cyan.withOpacity(0.4);
      bgColor = ConsoleColors.cyanDim;
    } else if (highlighted) {
      borderColor = ConsoleColors.cyan.withOpacity(0.15);
      bgColor = ConsoleColors.cyanGlow;
    } else {
      borderColor = Colors.transparent;
      bgColor = Colors.transparent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: active ? ConsoleColors.cyan : ConsoleColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 10,
                    color: ConsoleColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

// ── Console slider ────────────────────────────────────────────────────────────

class ConsoleSlider extends StatefulWidget {
  const ConsoleSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.divisions,
    this.controller,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final SliderController? controller;

  @override
  State<ConsoleSlider> createState() => _ConsoleSliderState();
}

class _ConsoleSliderState extends State<ConsoleSlider> {
  late double _local;

  @override
  void initState() {
    super.initState();
    _local = widget.value.clamp(widget.min, widget.max);
    widget.controller?.attach(_nudge);
  }

  @override
  void didUpdateWidget(ConsoleSlider old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.detach();
      widget.controller?.attach(_nudge);
    }
    if (old.value != widget.value) {
      _local = widget.value.clamp(widget.min, widget.max);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    super.dispose();
  }

  void _nudge(int direction) {
    final divisions = widget.divisions ?? 20;
    final step = (widget.max - widget.min) / divisions;
    final next = (_local + direction * step).clamp(widget.min, widget.max);
    if (next == _local) return;
    setState(() => _local = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: ConsoleColors.cyan,
              inactiveTrackColor: ConsoleColors.border2,
              thumbColor: ConsoleColors.bg,
              overlayColor: ConsoleColors.cyan.withOpacity(0.1),
              thumbShape: _DiamondThumbShape(),
              tickMarkShape: _SquareTickShape(),
              activeTickMarkColor: ConsoleColors.cyan.withOpacity(0.4),
              inactiveTickMarkColor: ConsoleColors.text3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _local,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (v) {
                setState(() => _local = v);
                widget.onChanged(v);
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: ConsoleColors.cyan.withOpacity(0.08),
            border: Border.all(color: ConsoleColors.cyan.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ConsoleColors.cyan,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Custom slider components ──────────────────────────────────────────────────

class _DiamondThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(14, 14);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    const half = 7.0;

    final path = Path()
      ..moveTo(center.dx, center.dy - half)
      ..lineTo(center.dx + half, center.dy)
      ..lineTo(center.dx, center.dy + half)
      ..lineTo(center.dx - half, center.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = ConsoleColors.bg);
    canvas.drawPath(
      path,
      Paint()
        ..color = ConsoleColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}

class _SquareTickShape extends SliderTickMarkShape {
  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => const Size(2, 6);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) {
    final isActive = center.dx <= thumbCenter.dx;
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 2, height: 5),
      Paint()
        ..color = isActive
            ? sliderTheme.activeTickMarkColor!
            : sliderTheme.inactiveTickMarkColor!,
    );
  }
}
