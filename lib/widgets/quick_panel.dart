import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../screens/home_screen.dart';
import '../models/led_colors.dart';
import 'bottom_bar.dart';

/// Which side the panel slides in from.
enum PanelSide { left, right }

/// The overlay quick-access panel — mirrors Steam Deck QAM UX.
///
/// Wrap your root [Scaffold] in a [Stack] and place this on top.
/// The panel captures all d-pad/gamepad input while open; the main
/// screen behind it is frozen.
///
/// Call [QuickPanelController.open] / [.close] to drive visibility,
/// or let [HomeScreen] handle it via key events and swipe zones.
class QuickPanel extends StatefulWidget {
  const QuickPanel({super.key, required this.controller, required this.side});

  final QuickPanelController controller;
  final PanelSide side;

  @override
  State<QuickPanel> createState() => _QuickPanelState();
}

class _QuickPanelState extends State<QuickPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _scrim;

  // ── Focus model (mirrors HomeScreen: Level 0 nav → Level 1 row → Level 2 slider) ──
  // In the panel there is only one "section" (no nav), so we have:
  //   Level 0  row cursor  — ↑↓ moves between rows
  //   Level 1  slider active — ◄► adjusts
  _PanelLevel _level = _PanelLevel.row;
  int _cursorRow = 0;

  // ── Slider controllers ─────────────────────────────────────────────────
  final _brightnessCtrl = SliderController();
  final _smoothingCtrl = SliderController();
  final _zoneWidthCtrl = SliderController();
  final _frameSkipCtrl = SliderController();

  static const _rowCount = 4; // brightness, smoothing, zoneWidth, frameSkip

  List<SliderController> get _controllers => [
    _brightnessCtrl,
    _smoothingCtrl,
    _zoneWidthCtrl,
    _frameSkipCtrl,
  ];

  @override
  void initState() {
    super.initState();

    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    final begin = widget.side == PanelSide.right
        ? const Offset(1.0, 0.0)
        : const Offset(-1.0, 0.0);

    _slide = Tween<Offset>(
      begin: begin,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

    _scrim = Tween<double>(
      begin: 0.0,
      end: 0.55,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

    widget.controller._attach(this);
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    _anim.dispose();
    super.dispose();
  }

  bool get _isOpen => _anim.value > 0;

  void _open() {
    _level = _PanelLevel.row;
    _cursorRow = 0;
    _anim.forward();
  }

  void _close() => _anim.reverse();

  // ── Key handling ───────────────────────────────────────────────────────

  KeyEventResult handleKey(KeyEvent event, AppState state) {
    if (!_isOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Close on B / Escape / Back
    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      _close();
      return KeyEventResult.handled;
    }

    // Y — toggle service (always available)
    if (key == LogicalKeyboardKey.keyY ||
        key == LogicalKeyboardKey.gameButtonY) {
      context.read<AppState>().toggleService();
      return KeyEventResult.handled;
    }

    switch (_level) {
      case _PanelLevel.row:
        if (key == LogicalKeyboardKey.arrowUp) {
          setState(() => _cursorRow = (_cursorRow - 1).clamp(0, _rowCount - 1));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          setState(() => _cursorRow = (_cursorRow + 1).clamp(0, _rowCount - 1));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          setState(() => _level = _PanelLevel.slider);
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled; // swallow all keys while panel is open

      case _PanelLevel.slider:
        if (key == LogicalKeyboardKey.arrowLeft) {
          _controllers[_cursorRow].nudge(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _controllers[_cursorRow].nudge(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape) {
          setState(() => _level = _PanelLevel.row);
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        if (_anim.value == 0) return const SizedBox.shrink();

        final state = context.watch<AppState>();
        final screenW = MediaQuery.of(context).size.width;
        final panelW = screenW * 0.40;

        return Stack(
          children: [
            // ── Scrim ────────────────────────────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                child: Container(color: Colors.black.withOpacity(_scrim.value)),
              ),
            ),

            // ── Panel ────────────────────────────────────────────────────
            Positioned(
              top: 0,
              bottom: 0,
              left: widget.side == PanelSide.left ? 0 : null,
              right: widget.side == PanelSide.right ? 0 : null,
              width: panelW,
              child: SlideTransition(
                position: _slide,
                child: _PanelBody(
                  side: widget.side,
                  state: state,
                  cursorRow: _level == _PanelLevel.row ? _cursorRow : -1,
                  activeRow: _level == _PanelLevel.slider ? _cursorRow : -1,
                  brightnessCtrl: _brightnessCtrl,
                  smoothingCtrl: _smoothingCtrl,
                  zoneWidthCtrl: _zoneWidthCtrl,
                  frameSkipCtrl: _frameSkipCtrl,
                  onClose: _close,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Panel level ───────────────────────────────────────────────────────────────

enum _PanelLevel { row, slider }

// ── Controller ────────────────────────────────────────────────────────────────

/// Lets [HomeScreen] open/close either panel without holding a direct
/// reference to its State.
class QuickPanelController {
  _QuickPanelState? _state;

  void _attach(_QuickPanelState s) => _state = s;
  void _detach(_QuickPanelState s) {
    if (_state == s) _state = null;
  }

  bool get isOpen => _state?._isOpen ?? false;

  void open() => _state?._open();
  void close() => _state?._close();
  void toggle() => isOpen ? close() : open();

  /// Route a key event into the panel. Returns [KeyEventResult.handled] if
  /// the panel consumed it (i.e. was open), [KeyEventResult.ignored] if not.
  KeyEventResult handleKey(KeyEvent event, AppState state) =>
      _state?.handleKey(event, state) ?? KeyEventResult.ignored;
}

// ── Panel body ────────────────────────────────────────────────────────────────

class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.side,
    required this.state,
    required this.cursorRow,
    required this.activeRow,
    required this.brightnessCtrl,
    required this.smoothingCtrl,
    required this.zoneWidthCtrl,
    required this.frameSkipCtrl,
    required this.onClose,
  });

  final PanelSide side;
  final AppState state;
  final int cursorRow;
  final int activeRow;
  final SliderController brightnessCtrl;
  final SliderController smoothingCtrl;
  final SliderController zoneWidthCtrl;
  final SliderController frameSkipCtrl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ConsoleColors.panel,
        border: Border(
          left: side == PanelSide.right
              ? const BorderSide(color: ConsoleColors.border2, width: 1)
              : BorderSide.none,
          right: side == PanelSide.left
              ? const BorderSide(color: ConsoleColors.border2, width: 1)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(isRunning: state.isRunning, onClose: onClose),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Live colour preview ────────────────────────────────
                  _ColorPreview(colors: state.currentColors),

                  // ── Service toggle ─────────────────────────────────────
                  _ServiceToggle(
                    isRunning: state.isRunning,
                    onToggle: () => context.read<AppState>().toggleService(),
                  ),

                  const _Divider(label: 'OUTPUT'),

                  // ── Brightness ─────────────────────────────────────────
                  _PanelSliderRow(
                    name: 'Brightness',
                    value: state.settings.brightness,
                    min: 0.05,
                    max: 1.0,
                    divisions: 19,
                    label: '${(state.settings.brightness * 100).round()}%',
                    controller: brightnessCtrl,
                    highlighted: cursorRow == 0,
                    active: activeRow == 0,
                    onChanged: (v) =>
                        context.read<AppState>().updateBrightness(v),
                  ),

                  // ── Smoothing ──────────────────────────────────────────
                  _PanelSliderRow(
                    name: 'Smoothing',
                    value: state.settings.smoothing,
                    min: 0.0,
                    max: 0.95,
                    divisions: 19,
                    label: state.settings.smoothing == 0.0
                        ? 'Off'
                        : '${(state.settings.smoothing * 100).round()}%',
                    controller: smoothingCtrl,
                    highlighted: cursorRow == 1,
                    active: activeRow == 1,
                    onChanged: (v) =>
                        context.read<AppState>().updateSmoothing(v),
                  ),

                  const _Divider(label: 'CAPTURE'),

                  // ── Zone Width ─────────────────────────────────────────
                  _PanelSliderRow(
                    name: 'Zone Width',
                    value: state.settings.zoneWidth,
                    min: 0.05,
                    max: 0.40,
                    divisions: 7,
                    label: '${(state.settings.zoneWidth * 100).round()}%',
                    controller: zoneWidthCtrl,
                    highlighted: cursorRow == 2,
                    active: activeRow == 2,
                    onChanged: (v) =>
                        context.read<AppState>().updateZoneWidth(v),
                  ),

                  const _Divider(label: 'PERFORMANCE'),

                  // ── Frame Skip ─────────────────────────────────────────
                  _PanelSliderRow(
                    name: 'Frame Skip',
                    value: state.settings.frameSkip.toDouble(),
                    min: 0,
                    max: 5,
                    divisions: 5,
                    label: state.settings.frameSkip == 0
                        ? 'Every'
                        : '1 in ${state.settings.frameSkip + 1}',
                    controller: frameSkipCtrl,
                    highlighted: cursorRow == 3,
                    active: activeRow == 3,
                    onChanged: (v) =>
                        context.read<AppState>().updateFrameSkip(v.round()),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Bottom hint ────────────────────────────────────────────────
          _PanelHint(activeRow: activeRow),
        ],
      ),
    );
  }
}

// ── Panel header ──────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.isRunning, required this.onClose});
  final bool isRunning;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ConsoleColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'QUICK ACCESS',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w700,
              color: ConsoleColors.text2,
            ),
          ),
          const Spacer(),
          // Live status dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning ? ConsoleColors.cyan : ConsoleColors.text3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isRunning ? 'ACTIVE' : 'OFFLINE',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: isRunning ? ConsoleColors.cyan : ConsoleColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live colour preview ───────────────────────────────────────────────────────

class _ColorPreview extends StatelessWidget {
  const _ColorPreview({required this.colors});
  final LedColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LED COLOURS',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 7,
              letterSpacing: 2.0,
              color: ConsoleColors.text3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ColorRect(
                  label: 'L',
                  color: colors.left,
                  accentColor: ConsoleColors.cyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ColorRect(
                  label: 'R',
                  color: colors.right,
                  accentColor: ConsoleColors.violet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorRect extends StatelessWidget {
  const _ColorRect({
    required this.label,
    required this.color,
    required this.accentColor,
  });

  final String label;
  final Color color;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    // Determine if the colour is dark enough to need a lighter label.
    final luma = color.red * 0.299 + color.green * 0.587 + color.blue * 0.114;
    final labelColor = luma < 80 ? accentColor : Colors.black.withOpacity(0.6);

    final isBlack =
        color == Colors.black ||
        (color.red == 0 && color.green == 0 && color.blue == 0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      height: 52,
      decoration: BoxDecoration(
        color: isBlack ? ConsoleColors.panel2 : color,
        border: Border.all(
          color: isBlack ? ConsoleColors.border2 : color.withOpacity(0.4),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Hex readout
          if (!isBlack)
            Positioned(
              bottom: 5,
              right: 8,
              child: Text(
                '#${color.red.toRadixString(16).padLeft(2, '0')}'
                        '${color.green.toRadixString(16).padLeft(2, '0')}'
                        '${color.blue.toRadixString(16).padLeft(2, '0')}'
                    .toUpperCase(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 7,
                  letterSpacing: 0.5,
                  color: labelColor.withOpacity(0.7),
                ),
              ),
            ),
          // Zone label
          Positioned(
            top: 6,
            left: 8,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isBlack ? ConsoleColors.text3 : labelColor,
              ),
            ),
          ),
          // Offline indicator
          if (isBlack)
            const Center(
              child: Text(
                '— —',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: ConsoleColors.text3,
                  letterSpacing: 4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Service toggle ────────────────────────────────────────────────────────────

class _ServiceToggle extends StatelessWidget {
  const _ServiceToggle({required this.isRunning, required this.onToggle});
  final bool isRunning;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 38,
          decoration: BoxDecoration(
            color: isRunning
                ? ConsoleColors.cyan.withOpacity(0.08)
                : Colors.transparent,
            border: Border.all(
              color: isRunning
                  ? ConsoleColors.cyan.withOpacity(0.4)
                  : ConsoleColors.border2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.power_settings_new_rounded,
                size: 13,
                color: isRunning ? ConsoleColors.cyan : ConsoleColors.text2,
              ),
              const SizedBox(width: 8),
              Text(
                isRunning ? 'STOP SERVICE' : 'START SERVICE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: isRunning ? ConsoleColors.cyan : ConsoleColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section divider ───────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 7,
          letterSpacing: 2.0,
          color: ConsoleColors.text3,
        ),
      ),
    );
  }
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _PanelSliderRow extends StatefulWidget {
  const _PanelSliderRow({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.controller,
    required this.highlighted,
    required this.active,
    required this.onChanged,
  });

  final String name;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final SliderController controller;
  final bool highlighted;
  final bool active;
  final ValueChanged<double> onChanged;

  @override
  State<_PanelSliderRow> createState() => _PanelSliderRowState();
}

class _PanelSliderRowState extends State<_PanelSliderRow> {
  late double _local;

  @override
  void initState() {
    super.initState();
    _local = widget.value.clamp(widget.min, widget.max);
    widget.controller.attach(_nudge);
  }

  @override
  void didUpdateWidget(_PanelSliderRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _local = widget.value.clamp(widget.min, widget.max);
    }
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  void _nudge(int dir) {
    final step = (widget.max - widget.min) / widget.divisions;
    final next = (_local + dir * step).clamp(widget.min, widget.max);
    if (next == _local) return;
    setState(() => _local = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final Color border;
    final Color bg;
    if (widget.active) {
      border = ConsoleColors.cyan.withOpacity(0.4);
      bg = ConsoleColors.cyanDim;
    } else if (widget.highlighted) {
      border = ConsoleColors.cyan.withOpacity(0.15);
      bg = ConsoleColors.cyanGlow;
    } else {
      border = Colors.transparent;
      bg = Colors.transparent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: widget.active
                        ? ConsoleColors.cyan
                        : ConsoleColors.text,
                  ),
                ),
              ),
              // Value badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ConsoleColors.cyan.withOpacity(0.08),
                  border: Border.all(
                    color: ConsoleColors.cyan.withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: ConsoleColors.cyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: ConsoleColors.cyan,
              inactiveTrackColor: ConsoleColors.border2,
              thumbColor: ConsoleColors.bg,
              overlayColor: ConsoleColors.cyan.withOpacity(0.1),
              thumbShape: _PanelDiamondThumb(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: SizedBox(
              height: 24,
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
        ],
      ),
    );
  }
}

// ── Panel bottom hint ─────────────────────────────────────────────────────────

class _PanelHint extends StatelessWidget {
  const _PanelHint({required this.activeRow});
  final int activeRow;

  @override
  Widget build(BuildContext context) {
    final isSlider = activeRow >= 0;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ConsoleColors.border)),
      ),
      child: Row(
        children: [
          _MiniHint(
            button: isSlider ? '◄►' : '↑↓',
            label: isSlider ? 'Adjust' : 'Select',
          ),
          const SizedBox(width: 16),
          _MiniHint(button: 'A', label: isSlider ? 'Confirm' : 'Adjust'),
          const SizedBox(width: 16),
          _MiniHint(button: 'B', label: 'Close'),
        ],
      ),
    );
  }
}

class _MiniHint extends StatelessWidget {
  const _MiniHint({required this.button, required this.label});
  final String button;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 16,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: ConsoleColors.border2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
            child: Text(
              button,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 7,
                color: ConsoleColors.text2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: ConsoleColors.text2),
        ),
      ],
    );
  }
}

// ── Diamond thumb (panel-local copy, smaller) ─────────────────────────────────

class _PanelDiamondThumb extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(10, 10);

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
    const half = 5.0;
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
        ..strokeWidth = 1.5,
    );
  }
}
