import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/settings_service.dart';
import 'widgets/quick_panel.dart';
import 'models/app_settings.dart';
import 'models/led_colors.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        // Force correct dimensions from the actual view
        final view = View.of(context);
        final data = MediaQueryData.fromView(view);
        return MediaQuery(data: data, child: child!);
      },
      home: const _OverlayRoot(),
    );
  }
}

class _OverlayRoot extends StatefulWidget {
  const _OverlayRoot();

  @override
  State<_OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<_OverlayRoot>
    with WidgetsBindingObserver {
  final _leftPanelCtrl = QuickPanelController();
  final _rightPanelCtrl = QuickPanelController();

  static const _triggerChannel = MethodChannel(
    'com.example.lightmeup/overlay_trigger',
  );

  AppSettings _settings = const AppSettings();

  // Which panel (if any) is currently open or animating.
  // We keep the QuickPanel widget in the tree until the close animation
  // completes (onOpenChanged fires false), then we flip to none and
  // tell native to remove the window.
  _ActivePanel _activePanel = _ActivePanel.none;

  // Prevents double-opens during the 260 ms slide-in animation.
  DateTime _lastOpen = DateTime.fromMillisecondsSinceEpoch(0);
  static const _openDebounce = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _triggerChannel.setMethodCallHandler(_handleTrigger);
    SettingsService().load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _triggerChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  bool get _eitherPanelOpen => _activePanel != _ActivePanel.none;

  // ── Native ↔ Flutter window lifecycle ────────────────────────────────────
  //
  // OPEN sequence (driven by Flutter):
  //   1. Tap / key combo → _openLeft() / _openRight()
  //   2. setState(_activePanel = left/right) → QuickPanel added to tree
  //   3. addPostFrameCallback → 'setFocusable' → native adds panel window to WM
  //   4. setFocusable completes → _leftPanelCtrl.open() → animation starts
  //      (window is in WM before animation, so vsync is available)
  //
  // CLOSE sequence (driven by Flutter):
  //   1. User taps scrim / B button / key combo → QuickPanel._close()
  //   2. _anim.reverse() starts (260 ms)
  //   3. onOpenChanged(false) fires when animation ENDS (status listener below)
  //   4. _onAnimationDone() → 'clearFocusable' → native removes panel window
  //   5. setState(_activePanel = none) → QuickPanel removed from tree
  //
  // The critical constraint: never call 'clearFocusable' before the animation
  // finishes. Removing the window from WM while the slide-out is playing would
  // yank the widget tree mid-animation and cause a visual snap/freeze.

  // Called by QuickPanel.onOpenChanged(false) — which fires when _anim reaches
  // 0.0 (animation fully reversed). Safe to remove the window now.
  void _onAnimationDone() {
    // Tell native to remove the panel window from WindowManager.
    _triggerChannel.invokeMethod('clearFocusable');
    // Remove the QuickPanel widget from the tree.
    if (mounted) setState(() => _activePanel = _ActivePanel.none);
  }

  // ── Trigger handler ───────────────────────────────────────────────────────

  Future<dynamic> _handleTrigger(MethodCall call) async {
    debugPrint('[overlay] trigger: ${call.method}');
    debugPrint(
      '[overlay] state: activePanel=$_activePanel lastOpen=${DateTime.now().difference(_lastOpen).inMilliseconds}ms ago',
    );

    switch (call.method) {
      case 'openLeftPanel':
        _openLeft();
      case 'openRightPanel':
        _openRight();
      case 'toggleLeftPanel':
        _activePanel == _ActivePanel.left ? _closeLeft() : _openLeft();
      case 'toggleRightPanel':
        _activePanel == _ActivePanel.right ? _closeRight() : _openRight();
      case 'tapLeftButton':
        _activePanel == _ActivePanel.left ? _closeLeft() : _openLeft();
      case 'tapRightButton':
        _activePanel == _ActivePanel.right ? _closeRight() : _openRight();
    }
  }

  void _openRight() {
    setState(() => _activePanel = _ActivePanel.right);
    _triggerChannel.invokeMethod('setFocusable').then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rightPanelCtrl.open();
        });
      }
    });
  }

  void _openLeft() {
    setState(() => _activePanel = _ActivePanel.left);
    _triggerChannel.invokeMethod('setFocusable').then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _leftPanelCtrl.open();
        });
      }
    });
  }

  void _closeLeft() {
    _leftPanelCtrl.close();
    // Do NOT call _onAnimationDone() here — wait for onOpenChanged(false)
    // which fires after the 260 ms reverse animation completes.
  }

  void _closeRight() {
    _rightPanelCtrl.close();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _handleKey(event),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Only the active panel is in the tree. QuickPanel returns
            // SizedBox.shrink() when _anim.value == 0, but we also keep it
            // mounted during the close animation so the reverse plays fully.
            // It is removed from the tree only after onOpenChanged(false).
            if (_activePanel == _ActivePanel.left)
              QuickPanel(
                key: const ValueKey('left'),
                controller: _leftPanelCtrl,
                side: PanelSide.left,
                settings: _settings,
                isRunning: false,
                currentColors: LedColors.black,
                callbacks: QuickPanelCallbacks(
                  onToggleService: () {},
                  onBrightnessChanged: (_) {},
                  onSmoothingChanged: (_) {},
                  onZoneWidthChanged: (_) {},
                  onFrameSkipChanged: (_) {},
                ),
                // false → animation finished reversing → safe to remove window
                onOpenChanged: (open) {
                  if (!open) _onAnimationDone();
                },
              ),

            if (_activePanel == _ActivePanel.right)
              QuickPanel(
                key: const ValueKey('right'),
                controller: _rightPanelCtrl,
                side: PanelSide.right,
                settings: _settings,
                isRunning: false,
                currentColors: LedColors.black,
                callbacks: QuickPanelCallbacks(
                  onToggleService: () {},
                  onBrightnessChanged: (_) {},
                  onSmoothingChanged: (_) {},
                  onZoneWidthChanged: (_) {},
                  onFrameSkipChanged: (_) {},
                ),
                onOpenChanged: (open) {
                  if (!open) _onAnimationDone();
                },
              ),

            // Floating button visual — pure paint, no touch handling.
            // Only shown when no panel is open (native hides the button window
            // when a panel opens anyway, so this is just for the visual layer).
            if (!_eitherPanelOpen)
              _FloatingButtonVisual(
                onPositionChanged: (xDp, yDp) {
                  _triggerChannel.invokeMethod('updateButtonPosition', {
                    'x': xDp.round(),
                    'y': yDp.round(),
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Hardware key handler ──────────────────────────────────────────────────

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    bool isComboActive(List<LogicalKeyboardKey>? keys) {
      if (keys == null || keys.isEmpty) return false;
      return keys.every((k) => pressed.contains(k));
    }

    if (_activePanel == _ActivePanel.left) {
      if (isComboActive(_settings.quickPanelLeftKeys)) {
        _closeLeft();
        return KeyEventResult.handled;
      }
      return _leftPanelCtrl.handleKey(event, _settings);
    }

    if (_activePanel == _ActivePanel.right) {
      if (isComboActive(_settings.quickPanelRightKeys)) {
        _closeRight();
        return KeyEventResult.handled;
      }
      return _rightPanelCtrl.handleKey(event, _settings);
    }

    return KeyEventResult.ignored;
  }
}

// ── Active panel enum ─────────────────────────────────────────────────────────

enum _ActivePanel { none, left, right }

// ─────────────────────────────────────────────────────────────────────────────
// Floating Button Visual — paint only, no touch handling
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingButtonVisual extends StatefulWidget {
  const _FloatingButtonVisual({required this.onPositionChanged});
  final void Function(double xDp, double yDp) onPositionChanged;

  @override
  State<_FloatingButtonVisual> createState() => _FloatingButtonVisualState();
}

class _FloatingButtonVisualState extends State<_FloatingButtonVisual> {
  static const double _buttonW = 52.0;
  static const double _buttonH = 72.0;
  static const double _edgeMargin = 0.0;
  static const double _idleOpacity = 0.55;
  static const Duration _fadeDuration = Duration(seconds: 4);

  Offset? _position;
  bool _isVisible = true;
  Timer? _fadeTimer;
  bool _positionReported = false;

  @override
  void initState() {
    super.initState();
    _resetFadeTimer();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _resetFadeTimer() {
    _fadeTimer?.cancel();
    if (mounted && !_isVisible) setState(() => _isVisible = true);
    _fadeTimer = Timer(_fadeDuration, () {
      if (mounted) setState(() => _isVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        _position ??= Offset(
          screenSize.width - _buttonW - _edgeMargin,
          (screenSize.height - _buttonH) / 2,
        );

        // Report initial position to native once so the button window aligns.
        if (!_positionReported) {
          _positionReported = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onPositionChanged(_position!.dx, _position!.dy);
          });
        }

        final pos = _position!;
        final atLeftEdge = pos.dx < screenSize.width / 2;

        return Stack(
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: _isVisible ? 1.0 : _idleOpacity,
                child: _ButtonBody(
                  width: _buttonW,
                  height: _buttonH,
                  atLeftEdge: atLeftEdge,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Button body ───────────────────────────────────────────────────────────────

class _ButtonBody extends StatelessWidget {
  const _ButtonBody({
    required this.width,
    required this.height,
    required this.atLeftEdge,
  });
  final double width;
  final double height;
  final bool atLeftEdge;

  @override
  Widget build(BuildContext context) {
    final radius = atLeftEdge
        ? const BorderRadius.horizontal(right: Radius.circular(36))
        : const BorderRadius.horizontal(left: Radius.circular(36));

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withOpacity(0.92),
            border: Border.all(
              color: const Color(0xFF7C4DFF).withOpacity(0.70),
              width: 1.5,
            ),
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C4DFF).withOpacity(0.35),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 24,
                  color: const Color(0xFF7C4DFF).withOpacity(0.95),
                ),
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: const Color(0xFF7C4DFF).withOpacity(0.25),
              ),
              Expanded(
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: const Color(0xFF7C4DFF).withOpacity(0.95),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
