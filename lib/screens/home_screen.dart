import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/side_nav.dart';
import '../widgets/top_bar.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/quick_panel.dart';
import '../sections/output_section.dart';
import '../sections/capture_section.dart';
import '../sections/performance_section.dart';
import '../sections/about_section.dart';
import '../sections/control_section.dart';
import '../sections/effects_section.dart';

enum NavSection { output, effects, capture, performance, controls, about }

/// Three-level focus model — mirrors standard console menu UX:
///
///   Level 0  [nav]      Left panel focused. ↑↓ pick section, A/► enter it.
///   Level 1  [section]  Inside section. ↑↓ pick row, A enter row, ◄ back to nav.
///   Level 2  [slider]   Slider active. ◄► adjust, A or B exit to level 1.
enum FocusLevel { nav, section, slider }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FocusLevel _level = FocusLevel.nav;
  NavSection _section = NavSection.output;
  int _cursorRow = 0;

  // ── Quick panel controllers ────────────────────────────────────────────
  final _leftPanelCtrl = QuickPanelController();
  final _rightPanelCtrl = QuickPanelController();

  // ── Swipe detection ────────────────────────────────────────────────────
  static const _swipeZoneWidth = 24.0;
  static const _swipeVelocityThreshold = 300.0;

  // ── Slider controllers ─────────────────────────────────────────────────
  final _brightnessCtrl = SliderController();
  final _smoothingCtrl = SliderController();
  final _zoneWidthCtrl = SliderController();
  final _frameSkipCtrl = SliderController();

  static const _rowCounts = {
    NavSection.output: 2,
    NavSection.effects: 0,
    NavSection.capture: 1,
    NavSection.performance: 1,
    NavSection.controls: 0,
    NavSection.about: 0,
  };

  int get _rowCount => _rowCounts[_section]!;

  List<SliderController> get _activeControllers {
    switch (_section) {
      case NavSection.output:
        return [_brightnessCtrl, _smoothingCtrl];
      case NavSection.capture:
        return [_zoneWidthCtrl];
      case NavSection.performance:
        return [_frameSkipCtrl];
      case NavSection.effects:
      case NavSection.controls:
      case NavSection.about:
        return [];
    }
  }

  bool get _eitherPanelOpen => _leftPanelCtrl.isOpen || _rightPanelCtrl.isOpen;

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Scaffold(
        backgroundColor: ConsoleColors.bg,
        body: Center(
          child: CircularProgressIndicator(color: ConsoleColors.cyan),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ConsoleColors.bg,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _handleKey(event, state),
        child: Stack(
          children: [
            // ── Main UI ─────────────────────────────────────────────────
            Column(
              children: [
                TopBar(
                  isRunning: state.isRunning,
                  onToggle: () => context.read<AppState>().toggleService(),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SideNav(
                        selected: _section,
                        isRunning: state.isRunning,
                        navFocused: _level == FocusLevel.nav,
                        onSelect: (s) => setState(() {
                          _section = s;
                          _level = FocusLevel.nav;
                          _cursorRow = 0;
                        }),
                        onToggle: () =>
                            context.read<AppState>().toggleService(),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.02, 0),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: _buildSection(state),
                        ),
                      ),
                    ],
                  ),
                ),
                BottomBar(
                  isRunning: state.isRunning,
                  level: _level,
                  panelOpen: _eitherPanelOpen,
                ),
              ],
            ),

            // ── Left swipe zone (invisible) ──────────────────────────────
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _swipeZoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v > _swipeVelocityThreshold && !_eitherPanelOpen) {
                    _leftPanelCtrl.open();
                    setState(() {});
                  }
                },
              ),
            ),

            // ── Right swipe zone (invisible) ─────────────────────────────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _swipeZoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -_swipeVelocityThreshold && !_eitherPanelOpen) {
                    _rightPanelCtrl.open();
                    setState(() {});
                  }
                },
              ),
            ),

            // ── Left quick panel ─────────────────────────────────────────
            QuickPanel(controller: _leftPanelCtrl, side: PanelSide.left),

            // ── Right quick panel ────────────────────────────────────────
            QuickPanel(controller: _rightPanelCtrl, side: PanelSide.right),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(AppState state) {
    final cursor = _level != FocusLevel.nav ? _cursorRow : -1;
    final active = _level == FocusLevel.slider ? _cursorRow : -1;

    switch (_section) {
      case NavSection.output:
        return OutputSection(
          key: const ValueKey('output'),
          state: state,
          cursorRow: cursor,
          activeRow: active,
          brightnessCtrl: _brightnessCtrl,
          smoothingCtrl: _smoothingCtrl,
        );
      case NavSection.effects:
        return EffectsSection(key: const ValueKey('effects'), state: state);
      case NavSection.capture:
        return CaptureSection(
          key: const ValueKey('capture'),
          state: state,
          cursorRow: cursor,
          activeRow: active,
          zoneWidthCtrl: _zoneWidthCtrl,
        );
      case NavSection.performance:
        return PerformanceSection(
          key: const ValueKey('performance'),
          state: state,
          cursorRow: cursor,
          activeRow: active,
          frameSkipCtrl: _frameSkipCtrl,
        );
      case NavSection.controls:
        return ControlsSection(key: const ValueKey('controls'), state: state);
      case NavSection.about:
        return AboutSection(key: const ValueKey('about'), state: state);
    }
  }

  // ── Key handler ────────────────────────────────────────────────────────

  KeyEventResult _handleKey(KeyEvent event, AppState state) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (_leftPanelCtrl.isOpen) {
      if (key == state.settings.quickPanelLeftKey) {
        _leftPanelCtrl.close();
        setState(() {});
        return KeyEventResult.handled;
      }
      return _leftPanelCtrl.handleKey(event, state);
    }

    if (_rightPanelCtrl.isOpen) {
      if (key == state.settings.quickPanelRightKey) {
        _rightPanelCtrl.close();
        setState(() {});
        return KeyEventResult.handled;
      }
      return _rightPanelCtrl.handleKey(event, state);
    }

    final leftKey = state.settings.quickPanelLeftKey;
    final rightKey = state.settings.quickPanelRightKey;

    if (leftKey != null && key == leftKey) {
      _leftPanelCtrl.open();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (rightKey != null && key == rightKey) {
      _rightPanelCtrl.open();
      setState(() {});
      return KeyEventResult.handled;
    }

    // Y — toggle service at any level
    if (key == LogicalKeyboardKey.keyY ||
        key == LogicalKeyboardKey.gameButtonY) {
      context.read<AppState>().toggleService();
      return KeyEventResult.handled;
    }

    switch (_level) {
      case FocusLevel.nav:
        if (key == LogicalKeyboardKey.arrowUp) {
          _cycleSection(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _cycleSection(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.arrowRight) {
          if (_rowCount > 0) {
            setState(() {
              _level = FocusLevel.section;
              _cursorRow = 0;
            });
          } else {
            setState(() => _level = FocusLevel.section);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      case FocusLevel.section:
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_cursorRow > 0) setState(() => _cursorRow--);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (_cursorRow < _rowCount - 1) setState(() => _cursorRow++);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          if (_rowCount > 0) setState(() => _level = FocusLevel.slider);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack ||
            key == LogicalKeyboardKey.arrowLeft) {
          setState(() {
            _level = FocusLevel.nav;
            _cursorRow = 0;
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      case FocusLevel.slider:
        if (key == LogicalKeyboardKey.arrowLeft) {
          _activeControllers[_cursorRow].nudge(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _activeControllers[_cursorRow].nudge(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack) {
          setState(() => _level = FocusLevel.section);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  void _cycleSection(int delta) {
    final values = NavSection.values;
    final next = (values.indexOf(_section) + delta).clamp(0, values.length - 1);
    setState(() => _section = values[next]);
  }
}

/// Central colour palette — reference these throughout all widgets.
class ConsoleColors {
  static const bg = Color(0xFF080B12);
  static const panel = Color(0xFF0E1320);
  static const panel2 = Color(0xFF131826);
  static const border = Color(0x12FFFFFF);
  static const border2 = Color(0x1EFFFFFF);
  static const cyan = Color(0xFF00D4FF);
  static const cyanDim = Color(0x1F00D4FF);
  static const cyanGlow = Color(0x0F00D4FF);
  static const violet = Color(0xFF9B6BFF);
  static const text = Color(0xFFE2EAF4);
  static const text2 = Color(0xFF7A8FA8);
  static const text3 = Color(0xFF3A4A5C);
}
