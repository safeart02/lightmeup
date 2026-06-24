import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/settings_service.dart';
import 'services/lightmeup_channel.dart';
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
  final _channel = LightmeupChannel();
  final _leftPanelCtrl = QuickPanelController();
  final _rightPanelCtrl = QuickPanelController();

  static const _swipeZoneWidth = 44.0;
  static const _swipeVelocityThreshold = 150.0;

  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SettingsService().load().then((s) => setState(() => _settings = s));
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimEdges());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _claimEdges();

  void _claimEdges() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    const maxExclusionDp = 200.0;
    final midY = size.height / 2;
    final halfH = maxExclusionDp / 2;

    final top = ((midY - halfH) * dpr).round();
    final bottom = ((midY + halfH) * dpr).round();
    final right = (_swipeZoneWidth * dpr).round();
    final screenRight = (size.width * dpr).round();

    SystemChannels.platform.invokeMethod<void>(
      'SystemGestures.setSystemGestureExclusionRects',
      <Map<String, int>>[
        {'top': top, 'bottom': bottom, 'left': 0, 'right': right},
        {
          'top': top,
          'bottom': bottom,
          'left': screenRight - right,
          'right': screenRight,
        },
      ],
    );
  }

  bool get _eitherPanelOpen => _leftPanelCtrl.isOpen || _rightPanelCtrl.isOpen;

  void _syncFocus() {
    _channel.setOverlayFocusable(_eitherPanelOpen);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _handleKey(event),
        child: Stack(
          children: [
            // Left Swipe Zone
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _swipeZoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {},
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v > _swipeVelocityThreshold && !_eitherPanelOpen) {
                    _leftPanelCtrl.open();
                    _syncFocus();
                  }
                },
              ),
            ),

            // Right Swipe Zone
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _swipeZoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {},
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -_swipeVelocityThreshold && !_eitherPanelOpen) {
                    _rightPanelCtrl.open();
                    _syncFocus();
                  }
                },
              ),
            ),

            // Quick Panels
            QuickPanel(
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
              onOpenChanged: (_) => _syncFocus(),
            ),
            QuickPanel(
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
              onOpenChanged: (_) => _syncFocus(),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    bool isComboActive(List<LogicalKeyboardKey>? comboKeys) {
      if (comboKeys == null || comboKeys.isEmpty) return false;
      return comboKeys.every((k) => pressed.contains(k));
    }

    if (_leftPanelCtrl.isOpen) {
      if (isComboActive(_settings.quickPanelLeftKeys)) {
        _leftPanelCtrl.close();
        _syncFocus();
        return KeyEventResult.handled;
      }
      return _leftPanelCtrl.handleKey(event, _settings);
    }

    if (_rightPanelCtrl.isOpen) {
      if (isComboActive(_settings.quickPanelRightKeys)) {
        _rightPanelCtrl.close();
        _syncFocus();
        return KeyEventResult.handled;
      }
      return _rightPanelCtrl.handleKey(event, _settings);
    }

    if (isComboActive(_settings.quickPanelLeftKeys)) {
      _leftPanelCtrl.open();
      _syncFocus();
      return KeyEventResult.handled;
    }
    if (isComboActive(_settings.quickPanelRightKeys)) {
      _rightPanelCtrl.open();
      _syncFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}
