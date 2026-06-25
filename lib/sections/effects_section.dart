import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../models/led_effect.dart';
import '../screens/home_screen.dart';
import '../widgets/bottom_bar.dart';

// ── Gamepad key constants ─────────────────────────────────────────────────────
// LogicalKeyboardKey overrides == and hashCode, so it cannot be used in a
// const Set. All sets are final (non-const).
//
// On Android, gamepad D-pad events fire arrowUp/Down/Left/Right as their
// logical key — no separate dpad constants exist.
//
// Shoulder buttons use gameButtonLeft1 / gameButtonRight1.
final _kConfirm = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.gameButtonA,
};
final _kCancel = {LogicalKeyboardKey.escape, LogicalKeyboardKey.gameButtonB};
final _kUp = {LogicalKeyboardKey.arrowUp};
final _kDown = {LogicalKeyboardKey.arrowDown};
final _kLeft = {LogicalKeyboardKey.arrowLeft};
final _kRight = {LogicalKeyboardKey.arrowRight};
final _kL1 = {LogicalKeyboardKey.pageUp, LogicalKeyboardKey.gameButtonLeft1};
final _kR1 = {LogicalKeyboardKey.pageDown, LogicalKeyboardKey.gameButtonRight1};

bool _is(LogicalKeyboardKey key, Set<LogicalKeyboardKey> set) =>
    set.contains(key);

// ── Focus item types ──────────────────────────────────────────────────────────

enum _ItemType {
  mode,
  colorPicker,
  slider,
  toggle,
  preset,
  addColor,
  removeColor,
}

class _FocusItem {
  const _FocusItem(this.type, this.id);
  final _ItemType type;
  final String id;
}

// ── SettingGroup ──────────────────────────────────────────────────────────────

class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
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
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

// ── EffectsSection ────────────────────────────────────────────────────────────

class EffectsSection extends StatefulWidget {
  const EffectsSection({super.key, required this.state});
  final AppState state;

  @override
  State<EffectsSection> createState() => _EffectsSectionState();
}

class _EffectsSectionState extends State<EffectsSection> {
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  int _focusIndex = 0;
  bool _itemActive = false;

  List<_FocusItem> _items = [];

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final count = _items.length;
      if (count == 0) return;
      final id = _items[_focusIndex.clamp(0, count - 1)].id;
      final key = _itemKeys[id];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    });
  }

  List<_FocusItem> _buildItems(LedEffectMode mode, LedEffectConfig config) {
    final items = <_FocusItem>[];
    for (final m in LedEffectMode.values) {
      items.add(_FocusItem(_ItemType.mode, 'mode_${m.name}'));
    }
    switch (mode) {
      case LedEffectMode.solidColor:
        items.add(const _FocusItem(_ItemType.colorPicker, 'color_primary'));
      case LedEffectMode.splitColor:
        items.add(const _FocusItem(_ItemType.colorPicker, 'color_primary'));
        items.add(const _FocusItem(_ItemType.colorPicker, 'color_secondary'));
      case LedEffectMode.breathing:
        items.add(const _FocusItem(_ItemType.colorPicker, 'color_primary'));
        items.add(const _FocusItem(_ItemType.slider, 'slider_speed'));
        items.add(const _FocusItem(_ItemType.toggle, 'toggle_mirror'));
      case LedEffectMode.strobe:
        items.add(const _FocusItem(_ItemType.colorPicker, 'color_primary'));
        items.add(const _FocusItem(_ItemType.slider, 'slider_speed'));
        items.add(const _FocusItem(_ItemType.slider, 'slider_duty'));
      case LedEffectMode.colorCycle:
        for (final presetName in _ColorCycleConfigState._presets.keys) {
          items.add(_FocusItem(_ItemType.preset, 'preset_$presetName'));
        }
        for (int i = 0; i < config.cycleColors.length; i++) {
          items.add(_FocusItem(_ItemType.colorPicker, 'color_cycle_$i'));
          if (config.cycleColors.length > 2) {
            items.add(_FocusItem(_ItemType.removeColor, 'remove_$i'));
          }
        }
        if (config.cycleColors.length < 8) {
          items.add(const _FocusItem(_ItemType.addColor, 'add_color'));
        }
        items.add(const _FocusItem(_ItemType.slider, 'slider_speed'));
      default:
        break;
    }
    return items;
  }

  void _onKey(
    KeyEvent event,
    LedEffectMode mode,
    LedEffectConfig config,
    ValueChanged<LedEffectConfig> onChanged,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;

    if (_itemActive) {
      // ── Active mode ───────────────────────────────────────────────────────
      final item = _items.isNotEmpty
          ? _items[_focusIndex.clamp(0, _items.length - 1)]
          : null;
      if (item == null) return;

      if (_is(key, _kCancel)) {
        setState(() => _itemActive = false);
        return;
      }

      if (item.type == _ItemType.slider) {
        final isSpeed = item.id == 'slider_speed';
        final isDuty = item.id == 'slider_duty';
        final divisions = isDuty ? 8 : 19;
        final step = 1.0 / divisions;
        final bigStep = step * 5;

        final current = isSpeed
            ? config.speed
            : isDuty
            ? config.dutyCycle
            : config.speed;
        final minVal = isDuty ? 0.1 : 0.05;
        final maxVal = isDuty ? 0.9 : 1.0;

        double delta = 0;
        if (_is(key, _kRight)) delta = step;
        if (_is(key, _kLeft)) delta = -step;
        if (_is(key, _kR1)) delta = bigStep;
        if (_is(key, _kL1)) delta = -bigStep;

        if (delta != 0) {
          final next = (current + delta).clamp(minVal, maxVal);
          final snapped = (next * divisions).round() / divisions;
          final nc = isSpeed
              ? config.copyWith(speed: snapped)
              : config.copyWith(dutyCycle: snapped);
          onChanged(nc);
        }
        if (_is(key, _kConfirm)) setState(() => _itemActive = false);
        return;
      }

      if (_is(key, _kConfirm)) setState(() => _itemActive = false);
      return;
    }

    // ── Navigation mode ───────────────────────────────────────────────────────
    final count = _items.length;
    if (count == 0) return;

    const gridCols = 2;
    final modeCount = LedEffectMode.values.length;
    final inGrid = _focusIndex < modeCount;

    if (inGrid) {
      final col = _focusIndex % gridCols;
      final row = _focusIndex ~/ gridCols;
      final gridRows = (modeCount + gridCols - 1) ~/ gridCols;

      if (_is(key, _kRight)) {
        final next = _focusIndex + 1;
        // Stay in same row only
        if (next < modeCount && next ~/ gridCols == row) {
          setState(() => _focusIndex = next);
          _scrollToFocused();
        }
      } else if (_is(key, _kLeft)) {
        final next = _focusIndex - 1;
        if (next >= 0 && next ~/ gridCols == row) {
          setState(() => _focusIndex = next);
          _scrollToFocused();
        }
      } else if (_is(key, _kDown)) {
        final nextRow = row + 1;
        if (nextRow < gridRows) {
          final next = (nextRow * gridCols + col).clamp(0, modeCount - 1);
          setState(() => _focusIndex = next);
          _scrollToFocused();
        } else if (modeCount < count) {
          // Exit grid downward into controls
          setState(() => _focusIndex = modeCount);
          _scrollToFocused();
        }
      } else if (_is(key, _kUp)) {
        final nextRow = row - 1;
        if (nextRow >= 0) {
          final next = nextRow * gridCols + col;
          setState(() => _focusIndex = next);
          _scrollToFocused();
        }
        // Top row: do nothing (no wrap)
      } else if (_is(key, _kConfirm)) {
        final item = _items[_focusIndex];
        final modeName = item.id.replaceFirst('mode_', '');
        final selectedMode = LedEffectMode.values.firstWhere(
          (m) => m.name == modeName,
        );
        context.read<AppState>().setLedEffect(selectedMode);
      } else if (_is(key, _kCancel)) {
        _focusNode.previousFocus();
      }
    } else {
      // Linear controls below grid
      if (_is(key, _kDown)) {
        if (_focusIndex < count - 1) {
          setState(() => _focusIndex++);
          _scrollToFocused();
        }
      } else if (_is(key, _kUp)) {
        if (_focusIndex > modeCount) {
          setState(() => _focusIndex--);
          _scrollToFocused();
        } else {
          // Return to bottom-left cell of last grid row
          final gridRows = (modeCount + gridCols - 1) ~/ gridCols;
          final lastRowStart = (gridRows - 1) * gridCols;
          setState(() => _focusIndex = lastRowStart.clamp(0, modeCount - 1));
          _scrollToFocused();
        }
      } else if (_is(key, _kRight) || _is(key, _kLeft)) {
        // No horizontal movement in linear controls
      } else if (_is(key, _kConfirm)) {
        final item = _items[_focusIndex];
        if (item.type == _ItemType.slider) {
          setState(() => _itemActive = true);
        } else if (item.type == _ItemType.toggle) {
          onChanged(config.copyWith(mirrorSides: !config.mirrorSides));
        } else if (item.type == _ItemType.colorPicker) {
          setState(() => _itemActive = true);
        } else if (item.type == _ItemType.addColor) {
          final next = List<Color>.from(config.cycleColors)
            ..add(const Color(0xFF00D4FF));
          onChanged(config.copyWith(cycleColors: next));
        } else if (item.type == _ItemType.removeColor) {
          final idx = int.parse(item.id.replaceFirst('remove_', ''));
          final next = List<Color>.from(config.cycleColors)..removeAt(idx);
          onChanged(config.copyWith(cycleColors: next));
        } else if (item.type == _ItemType.preset) {
          final name = item.id.replaceFirst('preset_', '');
          final colors = _ColorCycleConfigState._presets[name];
          if (colors != null) onChanged(config.copyWith(cycleColors: colors));
        }
      } else if (_is(key, _kCancel)) {
        _focusNode.previousFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.state.settings.ledEffect;
    final config = widget.state.settings.effectConfig;
    final onChanged = (LedEffectConfig c) =>
        context.read<AppState>().updateEffectConfig(c);

    _items = _buildItems(mode, config);

    for (final item in _items) {
      _itemKeys.putIfAbsent(item.id, () => GlobalKey());
    }

    final focusIndex = _focusIndex.clamp(
      0,
      _items.isEmpty ? 0 : _items.length - 1,
    );
    final focusedId = _items.isNotEmpty ? _items[focusIndex].id : null;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (e) => _onKey(e, mode, config, onChanged),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: SectionScaffold(
          title: 'Effects',
          description: 'LED modes and animations',
          children: [
            // ── Mode picker grid ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MODE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 7,
                      letterSpacing: 2.0,
                      color: ConsoleColors.text3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ModeGrid(
                    selected: mode,
                    focusedId: focusedId,
                    itemKeys: _itemKeys,
                    onSelect: (m) => context.read<AppState>().setLedEffect(m),
                  ),
                ],
              ),
            ),

            // ── Per-mode controls ─────────────────────────────────────────
            if (mode != LedEffectMode.ambientSync &&
                mode != LedEffectMode.rainbow)
              _ModeConfig(
                mode: mode,
                config: config,
                focusedId: focusedId,
                itemActive: _itemActive,
                itemKeys: _itemKeys,
                onChanged: onChanged,
              ),

            // ── Preview bar ───────────────────────────────────────────────
            _PreviewBar(
              mode: mode,
              config: config,
              currentColors: widget.state.currentColors,
              isRunning: widget.state.isRunning,
            ),

            // ── Gamepad hints ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  _HintBadge('D-PAD', 'Navigate'),
                  const SizedBox(width: 8),
                  _HintBadge('A', _itemActive ? 'Confirm' : 'Select'),
                  const SizedBox(width: 8),
                  _HintBadge('B', _itemActive ? 'Cancel' : 'Back'),
                  if (_itemActive &&
                      _items.isNotEmpty &&
                      _items[focusIndex].type == _ItemType.slider) ...[
                    const SizedBox(width: 8),
                    _HintBadge('L1/R1', 'Jump'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hint badge ────────────────────────────────────────────────────────────────

class _HintBadge extends StatelessWidget {
  const _HintBadge(this.button, this.label);
  final String button;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: ConsoleColors.border2),
            borderRadius: BorderRadius.circular(3),
            color: ConsoleColors.panel2,
          ),
          child: Text(
            button,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: ConsoleColors.text2,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 8,
            color: ConsoleColors.text3,
          ),
        ),
      ],
    );
  }
}

// ── Mode grid ─────────────────────────────────────────────────────────────────

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({
    required this.selected,
    required this.onSelect,
    required this.itemKeys,
    this.focusedId,
  });
  final LedEffectMode selected;
  final ValueChanged<LedEffectMode> onSelect;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;

  @override
  Widget build(BuildContext context) {
    final modes = LedEffectMode.values;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 3.0,
      ),
      itemCount: modes.length,
      itemBuilder: (_, i) {
        final id = 'mode_${modes[i].name}';
        return _ModeTile(
          key: itemKeys[id],
          mode: modes[i],
          isSelected: modes[i] == selected,
          isFocused: focusedId == id,
          onTap: () => onSelect(modes[i]),
        );
      },
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.mode,
    required this.isSelected,
    required this.onTap,
    this.isFocused = false,
  });

  final LedEffectMode mode;
  final bool isSelected;
  final bool isFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? ConsoleColors.cyanDim : ConsoleColors.panel2,
          border: Border.all(
            color: isFocused
                ? Colors.white.withOpacity(0.8)
                : isSelected
                ? ConsoleColors.cyan.withOpacity(0.6)
                : ConsoleColors.border2,
            width: isFocused
                ? 1.5
                : isSelected
                ? 1.5
                : 1,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.08),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Text(
              mode.icon,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? ConsoleColors.cyan : ConsoleColors.text3,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mode.label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? ConsoleColors.cyan : ConsoleColors.text2,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: ConsoleColors.cyan,
                ),
              ),
            if (isFocused && !isSelected)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Per-mode config dispatcher ────────────────────────────────────────────────

class _ModeConfig extends StatelessWidget {
  const _ModeConfig({
    required this.mode,
    required this.config,
    required this.onChanged,
    required this.itemKeys,
    this.focusedId,
    this.itemActive = false,
  });

  final LedEffectMode mode;
  final LedEffectConfig config;
  final ValueChanged<LedEffectConfig> onChanged;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;
  final bool itemActive;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      LedEffectMode.solidColor => _SolidColorConfig(
        config: config,
        onChanged: onChanged,
        focusedId: focusedId,
        itemActive: itemActive,
        itemKeys: itemKeys,
      ),
      LedEffectMode.splitColor => _SplitColorConfig(
        config: config,
        onChanged: onChanged,
        focusedId: focusedId,
        itemActive: itemActive,
        itemKeys: itemKeys,
      ),
      LedEffectMode.breathing => _BreathingConfig(
        config: config,
        onChanged: onChanged,
        focusedId: focusedId,
        itemActive: itemActive,
        itemKeys: itemKeys,
      ),
      LedEffectMode.strobe => _StrobeConfig(
        config: config,
        onChanged: onChanged,
        focusedId: focusedId,
        itemActive: itemActive,
        itemKeys: itemKeys,
      ),
      LedEffectMode.colorCycle => _ColorCycleConfig(
        config: config,
        onChanged: onChanged,
        focusedId: focusedId,
        itemActive: itemActive,
        itemKeys: itemKeys,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

// ── Solid color config ────────────────────────────────────────────────────────

class _SolidColorConfig extends StatelessWidget {
  const _SolidColorConfig({
    required this.config,
    required this.onChanged,
    required this.itemKeys,
    this.focusedId,
    this.itemActive = false,
  });
  final LedEffectConfig config;
  final ValueChanged<LedEffectConfig> onChanged;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;
  final bool itemActive;

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      label: 'COLOR',
      children: [
        _ColorPickerRow(
          key: itemKeys['color_primary'],
          id: 'color_primary',
          label: 'LED Color',
          description: 'Applied to both joystick LEDs',
          color: config.primaryColor,
          isFocused: focusedId == 'color_primary',
          isActive: itemActive && focusedId == 'color_primary',
          onChanged: (c) => onChanged(config.copyWith(primaryColor: c)),
        ),
      ],
    );
  }
}

// ── Split color config ────────────────────────────────────────────────────────

class _SplitColorConfig extends StatelessWidget {
  const _SplitColorConfig({
    required this.config,
    required this.onChanged,
    required this.itemKeys,
    this.focusedId,
    this.itemActive = false,
  });
  final LedEffectConfig config;
  final ValueChanged<LedEffectConfig> onChanged;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;
  final bool itemActive;

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      label: 'COLORS',
      children: [
        _ColorPickerRow(
          key: itemKeys['color_primary'],
          id: 'color_primary',
          label: 'Left Stick',
          description: 'Color for the left joystick LED',
          color: config.primaryColor,
          accentColor: ConsoleColors.cyan,
          isFocused: focusedId == 'color_primary',
          isActive: itemActive && focusedId == 'color_primary',
          onChanged: (c) => onChanged(config.copyWith(primaryColor: c)),
        ),
        _ColorPickerRow(
          key: itemKeys['color_secondary'],
          id: 'color_secondary',
          label: 'Right Stick',
          description: 'Color for the right joystick LED',
          color: config.secondaryColor,
          accentColor: ConsoleColors.violet,
          isFocused: focusedId == 'color_secondary',
          isActive: itemActive && focusedId == 'color_secondary',
          onChanged: (c) => onChanged(config.copyWith(secondaryColor: c)),
        ),
      ],
    );
  }
}

// ── Breathing config ──────────────────────────────────────────────────────────

class _BreathingConfig extends StatelessWidget {
  const _BreathingConfig({
    required this.config,
    required this.onChanged,
    required this.itemKeys,
    this.focusedId,
    this.itemActive = false,
  });
  final LedEffectConfig config;
  final ValueChanged<LedEffectConfig> onChanged;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;
  final bool itemActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingGroup(
          label: 'COLOR',
          children: [
            _ColorPickerRow(
              key: itemKeys['color_primary'],
              id: 'color_primary',
              label: 'Breath Color',
              description: 'Color the LEDs pulse through',
              color: config.primaryColor,
              isFocused: focusedId == 'color_primary',
              isActive: itemActive && focusedId == 'color_primary',
              onChanged: (c) => onChanged(config.copyWith(primaryColor: c)),
            ),
          ],
        ),
        SettingGroup(
          label: 'TIMING',
          children: [
            _SliderRow(
              key: itemKeys['slider_speed'],
              id: 'slider_speed',
              label: 'Speed',
              description: 'How fast the pulse cycles',
              value: config.speed,
              min: 0.05,
              max: 1.0,
              divisions: 19,
              isFocused: focusedId == 'slider_speed',
              isActive: itemActive && focusedId == 'slider_speed',
              labelBuilder: (v) {
                if (v < 0.25) return 'Slow';
                if (v < 0.6) return 'Med';
                return 'Fast';
              },
              onChanged: (v) => onChanged(config.copyWith(speed: v)),
            ),
            _ToggleRow(
              key: itemKeys['toggle_mirror'],
              id: 'toggle_mirror',
              label: 'Mirror Sides',
              description: 'Both sticks breathe in sync',
              value: config.mirrorSides,
              isFocused: focusedId == 'toggle_mirror',
              onChanged: (v) => onChanged(config.copyWith(mirrorSides: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Strobe config ─────────────────────────────────────────────────────────────

class _StrobeConfig extends StatelessWidget {
  const _StrobeConfig({
    required this.config,
    required this.onChanged,
    required this.itemKeys,
    this.focusedId,
    this.itemActive = false,
  });
  final LedEffectConfig config;
  final ValueChanged<LedEffectConfig> onChanged;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;
  final bool itemActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingGroup(
          label: 'COLOR',
          children: [
            _ColorPickerRow(
              key: itemKeys['color_primary'],
              id: 'color_primary',
              label: 'Strobe Color',
              description: 'Color flashed during on-phase',
              color: config.primaryColor,
              isFocused: focusedId == 'color_primary',
              isActive: itemActive && focusedId == 'color_primary',
              onChanged: (c) => onChanged(config.copyWith(primaryColor: c)),
            ),
          ],
        ),
        SettingGroup(
          label: 'STROBE',
          children: [
            _SliderRow(
              key: itemKeys['slider_speed'],
              id: 'slider_speed',
              label: 'Flash Speed',
              description: 'Flashes per second',
              value: config.speed,
              min: 0.05,
              max: 1.0,
              divisions: 19,
              isFocused: focusedId == 'slider_speed',
              isActive: itemActive && focusedId == 'slider_speed',
              labelBuilder: (v) => '${(v * 20).round()} Hz',
              onChanged: (v) => onChanged(config.copyWith(speed: v)),
            ),
            _SliderRow(
              key: itemKeys['slider_duty'],
              id: 'slider_duty',
              label: 'Duty Cycle',
              description: 'Fraction of time the LED is on',
              value: config.dutyCycle,
              min: 0.1,
              max: 0.9,
              divisions: 8,
              isFocused: focusedId == 'slider_duty',
              isActive: itemActive && focusedId == 'slider_duty',
              labelBuilder: (v) => '${(v * 100).round()}%',
              onChanged: (v) => onChanged(config.copyWith(dutyCycle: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Color cycle config ────────────────────────────────────────────────────────

class _ColorCycleConfig extends StatefulWidget {
  const _ColorCycleConfig({
    required this.config,
    required this.onChanged,
    required this.itemKeys,
    this.focusedId,
    this.itemActive = false,
  });
  final LedEffectConfig config;
  final ValueChanged<LedEffectConfig> onChanged;
  final Map<String, GlobalKey> itemKeys;
  final String? focusedId;
  final bool itemActive;

  @override
  State<_ColorCycleConfig> createState() => _ColorCycleConfigState();
}

class _ColorCycleConfigState extends State<_ColorCycleConfig> {
  // Exposed so _buildItems can iterate preset names for focus items.
  static const _presets = <String, List<Color>>{
    'Ocean': [
      Color(0xFF00D4FF),
      Color(0xFF0066FF),
      Color(0xFF00FFCC),
      Color(0xFF0044AA),
    ],
    'Fire': [
      Color(0xFFFF4400),
      Color(0xFFFF8800),
      Color(0xFFFFCC00),
      Color(0xFFFF2200),
    ],
    'Forest': [
      Color(0xFF00FF44),
      Color(0xFF44AA00),
      Color(0xFF00CC66),
      Color(0xFF228800),
    ],
    'Neon': [
      Color(0xFFFF00FF),
      Color(0xFF00FFFF),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
    ],
    'Sunset': [
      Color(0xFFFF6B35),
      Color(0xFFF7931E),
      Color(0xFFFF3CAC),
      Color(0xFF784BA0),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final colors = widget.config.cycleColors;
    final itemKeys = widget.itemKeys;

    return Column(
      children: [
        // ── Presets ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PRESETS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 7,
                  letterSpacing: 2.0,
                  color: ConsoleColors.text3,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _presets.entries.map((entry) {
                    final id = 'preset_${entry.key}';
                    final isFocused = widget.focusedId == id;
                    return Padding(
                      key: itemKeys[id],
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => widget.onChanged(
                          widget.config.copyWith(cycleColors: entry.value),
                        ),
                        child: _PresetChip(
                          name: entry.key,
                          colors: entry.value,
                          isFocused: isFocused,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // ── Cycle colors ──────────────────────────────────────────────────
        SettingGroup(
          label: 'CYCLE COLORS  (${colors.length})',
          children: [
            for (int i = 0; i < colors.length; i++)
              _ColorPickerRow(
                key: itemKeys['color_cycle_$i'],
                id: 'color_cycle_$i',
                label: 'Color ${i + 1}',
                description: i == 0
                    ? 'First in the cycle'
                    : i == colors.length - 1
                    ? 'Last in the cycle'
                    : 'Step ${i + 1}',
                color: colors[i],
                isFocused: widget.focusedId == 'color_cycle_$i',
                isActive:
                    widget.itemActive && widget.focusedId == 'color_cycle_$i',
                onChanged: (c) {
                  final next = List<Color>.from(colors);
                  next[i] = c;
                  widget.onChanged(widget.config.copyWith(cycleColors: next));
                },
                trailing: colors.length > 2
                    ? _RemoveButton(
                        key: itemKeys['remove_$i'],
                        isFocused: widget.focusedId == 'remove_$i',
                        onTap: () {
                          final next = List<Color>.from(colors)..removeAt(i);
                          widget.onChanged(
                            widget.config.copyWith(cycleColors: next),
                          );
                        },
                      )
                    : null,
              ),

            if (colors.length < 8)
              _AddColorButton(
                key: itemKeys['add_color'],
                isFocused: widget.focusedId == 'add_color',
                onTap: () {
                  final next = List<Color>.from(colors)
                    ..add(const Color(0xFF00D4FF));
                  widget.onChanged(widget.config.copyWith(cycleColors: next));
                },
              ),
          ],
        ),

        // ── Speed ─────────────────────────────────────────────────────────
        SettingGroup(
          label: 'TIMING',
          children: [
            _SliderRow(
              key: itemKeys['slider_speed'],
              id: 'slider_speed',
              label: 'Cycle Speed',
              description: 'How fast it fades through colors',
              value: widget.config.speed,
              min: 0.05,
              max: 1.0,
              divisions: 19,
              isFocused: widget.focusedId == 'slider_speed',
              isActive: widget.itemActive && widget.focusedId == 'slider_speed',
              labelBuilder: (v) {
                if (v < 0.25) return 'Slow';
                if (v < 0.6) return 'Med';
                return 'Fast';
              },
              onChanged: (v) =>
                  widget.onChanged(widget.config.copyWith(speed: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Remove / Add color buttons ────────────────────────────────────────────────

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({super.key, required this.onTap, this.isFocused = false});
  final VoidCallback onTap;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: isFocused
              ? Colors.white.withOpacity(0.08)
              : Colors.transparent,
          border: Border.all(
            color: isFocused
                ? Colors.white.withOpacity(0.5)
                : ConsoleColors.border2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.remove_rounded,
          size: 14,
          color: ConsoleColors.text2,
        ),
      ),
    );
  }
}

class _AddColorButton extends StatelessWidget {
  const _AddColorButton({
    super.key,
    required this.onTap,
    this.isFocused = false,
  });
  final VoidCallback onTap;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 36,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isFocused
              ? Colors.white.withOpacity(0.05)
              : Colors.transparent,
          border: Border.all(
            color: isFocused
                ? Colors.white.withOpacity(0.5)
                : ConsoleColors.border2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 14, color: ConsoleColors.text2),
            SizedBox(width: 6),
            Text(
              'Add color',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: ConsoleColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preview bar ───────────────────────────────────────────────────────────────

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({
    required this.mode,
    required this.config,
    required this.currentColors,
    required this.isRunning,
  });

  final LedEffectMode mode;
  final LedEffectConfig config;
  final dynamic currentColors;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final Color leftPreview;
    final Color rightPreview;

    if (isRunning && mode == LedEffectMode.ambientSync) {
      leftPreview = currentColors.left as Color;
      rightPreview = currentColors.right as Color;
    } else {
      leftPreview = config.primaryColor;
      rightPreview = mode == LedEffectMode.splitColor
          ? config.secondaryColor
          : config.primaryColor;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREVIEW',
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
                child: _ColorSwatch(
                  label: 'L',
                  color: leftPreview,
                  sublabel: 'LEFT',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ColorSwatch(
                  label: 'R',
                  color: rightPreview,
                  sublabel: 'RIGHT',
                ),
              ),
            ],
          ),
          if (!isRunning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Start the service to activate the selected effect.',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: ConsoleColors.text3,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.label,
    required this.color,
    required this.sublabel,
  });
  final String label;
  final Color color;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            sublabel,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared config widgets ─────────────────────────────────────────────────────

class _ColorPickerRow extends StatefulWidget {
  const _ColorPickerRow({
    super.key,
    required this.id,
    required this.label,
    required this.description,
    required this.color,
    required this.onChanged,
    this.accentColor = ConsoleColors.cyan,
    this.trailing,
    this.isFocused = false,
    this.isActive = false,
  });

  final String id;
  final String label;
  final String description;
  final Color color;
  final ValueChanged<Color> onChanged;
  final Color accentColor;
  final Widget? trailing;
  final bool isFocused;
  final bool isActive;

  @override
  State<_ColorPickerRow> createState() => _ColorPickerRowState();
}

class _ColorPickerRowState extends State<_ColorPickerRow> {
  // Guard: true while the bottom sheet is open so we never double-open.
  bool _pickerOpen = false;

  // Quick-pick swatches: rainbow spectrum + white + black.
  static const _quickColors = [
    Color(0xFFFF0000), // red
    Color(0xFFFF6600), // orange
    Color(0xFFFFFF00), // yellow
    Color(0xFF00FF00), // green
    Color(0xFF00FFFF), // cyan
    Color(0xFF0066FF), // blue
    Color(0xFF9B00FF), // violet
    Color(0xFFFF00FF), // magenta
    Color(0xFFFFFFFF), // white
    Color(0xFF000000), // black
  ];

  @override
  void didUpdateWidget(_ColorPickerRow old) {
    super.didUpdateWidget(old);
    // isActive just became true and the picker isn't already open → open it.
    if (widget.isActive && !old.isActive && !_pickerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_pickerOpen) _openPicker();
      });
    }
  }

  void _openPicker() {
    if (_pickerOpen) return;
    _pickerOpen = true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ConsoleColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: ConsoleColors.border),
      ),
      builder: (_) => _ColorPickerSheet(
        label: widget.label,
        initialColor: widget.color,
        quickColors: _quickColors,
        onChanged: widget.onChanged,
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _pickerOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.symmetric(
        vertical: 8,
        horizontal: widget.isFocused ? 8 : 0,
      ),
      decoration: BoxDecoration(
        color: widget.isFocused
            ? Colors.white.withOpacity(0.04)
            : Colors.transparent,
        border: widget.isFocused
            ? Border.all(color: Colors.white.withOpacity(0.15))
            : const Border(),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ConsoleColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.description,
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
            onTap: _openPicker,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: 28,
              decoration: BoxDecoration(
                color: widget.color,
                border: Border.all(
                  color: widget.isFocused
                      ? Colors.white
                      : widget.accentColor.withOpacity(0.5),
                  width: widget.isFocused ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                  if (widget.isFocused)
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 8,
                    ),
                ],
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

// ── Color picker bottom sheet ─────────────────────────────────────────────────

// Which section of the picker the gamepad cursor is in.
enum _PickerSection { quick, hue, satVal, apply }

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({
    required this.label,
    required this.initialColor,
    required this.quickColors,
    required this.onChanged,
  });

  final String label;
  final Color initialColor;
  final List<Color> quickColors;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;

  // Gamepad state
  _PickerSection _section = _PickerSection.hue;
  int _quickIndex = 0; // active swatch index when section == quick

  // Step sizes
  static const double _hueStep = 3.0; // degrees per d-pad tick
  static const double _hueJump = 30.0; // degrees per L1/R1
  static const double _svStep = 0.03; // sat/val per d-pad tick
  static const double _svJump = 0.15; // sat/val per L1/R1

  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    // Start focused so key events arrive immediately without a tap.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _apply(Color c) {
    widget.onChanged(c);
    Navigator.pop(context);
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;

    // B always cancels
    if (_is(key, _kCancel)) {
      Navigator.pop(context);
      return;
    }

    // L1 / R1 cycle sections (when not adjusting hue/sat in those sections)
    // We repurpose L1/R1 for coarse steps inside hue & satVal, so section
    // cycling uses them only in quick/apply.
    if (_section == _PickerSection.quick || _section == _PickerSection.apply) {
      if (_is(key, _kL1)) {
        _cycleSection(-1);
        return;
      }
      if (_is(key, _kR1)) {
        _cycleSection(1);
        return;
      }
    }

    // Up / Down always cycle sections
    if (_is(key, _kUp)) {
      _cycleSection(-1);
      return;
    }
    if (_is(key, _kDown)) {
      _cycleSection(1);
      return;
    }

    switch (_section) {
      // ── QUICK PICK ────────────────────────────────────────────────────
      case _PickerSection.quick:
        if (_is(key, _kLeft)) {
          setState(
            () => _quickIndex = (_quickIndex - 1).clamp(
              0,
              widget.quickColors.length - 1,
            ),
          );
        } else if (_is(key, _kRight)) {
          setState(
            () => _quickIndex = (_quickIndex + 1).clamp(
              0,
              widget.quickColors.length - 1,
            ),
          );
        } else if (_is(key, _kConfirm)) {
          _apply(widget.quickColors[_quickIndex]);
        }

      // ── HUE BAR ───────────────────────────────────────────────────────
      case _PickerSection.hue:
        double delta = 0;
        if (_is(key, _kLeft)) delta = -_hueStep;
        if (_is(key, _kRight)) delta = _hueStep;
        if (_is(key, _kL1)) delta = -_hueJump;
        if (_is(key, _kR1)) delta = _hueJump;
        if (delta != 0) {
          setState(() {
            final h = (_hsv.hue + delta) % 360;
            _hsv = _hsv.withHue(h < 0 ? h + 360 : h);
            widget.onChanged(_hsv.toColor());
          });
        } else if (_is(key, _kConfirm)) {
          _cycleSection(1); // jump to sat/val
        }

      // ── SAT / VAL BOX ─────────────────────────────────────────────────
      case _PickerSection.satVal:
        double ds = 0, dv = 0;
        if (_is(key, _kLeft)) ds = -_svStep;
        if (_is(key, _kRight)) ds = _svStep;
        if (_is(key, _kUp)) {
          dv = _svStep;
          return;
        } // up/down handled above
        if (_is(key, _kDown)) {
          dv = -_svStep;
          return;
        } // but we catch it here first
        if (_is(key, _kL1)) ds = -_svJump;
        if (_is(key, _kR1)) ds = _svJump;
        if (ds != 0 || dv != 0) {
          setState(() {
            final s = (_hsv.saturation + ds).clamp(0.0, 1.0);
            final v = (_hsv.value + dv).clamp(0.0, 1.0);
            _hsv = HSVColor.fromAHSV(1.0, _hsv.hue, s, v);
            widget.onChanged(_hsv.toColor());
          });
        } else if (_is(key, _kConfirm)) {
          _cycleSection(1); // jump to apply
        }

      // ── APPLY ─────────────────────────────────────────────────────────
      case _PickerSection.apply:
        if (_is(key, _kConfirm)) _apply(_hsv.toColor());
    }
  }

  // satVal needs separate up/down handling (changes value, not section).
  // We intercept up/down before the section switch for satVal.
  void _onKeyRaw(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;

    if (_section == _PickerSection.satVal) {
      double dv = 0;
      if (_is(key, _kUp)) dv = _svStep;
      if (_is(key, _kDown)) dv = -_svStep;
      if (dv != 0) {
        setState(() {
          final v = (_hsv.value + dv).clamp(0.0, 1.0);
          _hsv = HSVColor.fromAHSV(1.0, _hsv.hue, _hsv.saturation, v);
          widget.onChanged(_hsv.toColor());
        });
        return;
      }
    }
    _onKey(event);
  }

  void _cycleSection(int dir) {
    final sections = _PickerSection.values;
    final idx = (sections.indexOf(_section) + dir).clamp(
      0,
      sections.length - 1,
    );
    setState(() => _section = sections[idx]);
  }

  // Hint text for the bottom bar, per section.
  List<(String, String)> get _hints {
    switch (_section) {
      case _PickerSection.quick:
        return [
          ('◀ ▶', 'Choose swatch'),
          ('A', 'Apply'),
          ('↑ ↓ / L1 R1', 'Switch section'),
          ('B', 'Cancel'),
        ];
      case _PickerSection.hue:
        return [
          ('◀ ▶', 'Adjust hue'),
          ('L1 R1', 'Jump ±30°'),
          ('↑ ↓', 'Switch section'),
          ('B', 'Cancel'),
        ];
      case _PickerSection.satVal:
        return [
          ('◀ ▶', 'Saturation'),
          ('↑ ↓', 'Brightness'),
          ('L1 R1', 'Coarse sat'),
          ('B', 'Cancel'),
        ];
      case _PickerSection.apply:
        return [
          ('A', 'Confirm color'),
          ('↑ ↓ / L1 R1', 'Switch section'),
          ('B', 'Cancel'),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKeyRaw,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  widget.label.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 7,
                    letterSpacing: 2.0,
                    color: ConsoleColors.text3,
                  ),
                ),
                const Spacer(),
                // Live preview swatch
                AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: 32,
                  height: 20,
                  decoration: BoxDecoration(
                    color: current,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(color: current.withOpacity(0.5), blurRadius: 8),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Quick pick ────────────────────────────────────────────────
            _SectionLabel(
              label: 'QUICK PICK',
              active: _section == _PickerSection.quick,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              // Tap anywhere in the row to focus the section
              onTap: () => setState(() => _section = _PickerSection.quick),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                decoration: BoxDecoration(
                  color: _section == _PickerSection.quick
                      ? Colors.white.withOpacity(0.04)
                      : Colors.transparent,
                  border: Border.all(
                    color: _section == _PickerSection.quick
                        ? Colors.white.withOpacity(0.2)
                        : Colors.transparent,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: widget.quickColors.asMap().entries.map((e) {
                    final i = e.key;
                    final c = e.value;
                    final isGamepadFocused =
                        _section == _PickerSection.quick && _quickIndex == i;
                    return GestureDetector(
                      onTap: () => _apply(c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isGamepadFocused
                                ? ConsoleColors.cyan
                                : c == const Color(0xFF000000)
                                ? Colors.white.withOpacity(0.25)
                                : Colors.transparent,
                            width: isGamepadFocused ? 2.5 : 1,
                          ),
                          boxShadow: isGamepadFocused
                              ? [
                                  BoxShadow(
                                    color: ConsoleColors.cyan.withOpacity(0.6),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Hue bar ───────────────────────────────────────────────────
            _SectionLabel(label: 'HUE', active: _section == _PickerSection.hue),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _section = _PickerSection.hue),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: BoxDecoration(
                  color: _section == _PickerSection.hue
                      ? Colors.white.withOpacity(0.04)
                      : Colors.transparent,
                  border: Border.all(
                    color: _section == _PickerSection.hue
                        ? Colors.white.withOpacity(0.2)
                        : Colors.transparent,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _HueBar(
                  hue: _hsv.hue,
                  onChanged: (h) => setState(() {
                    _hsv = _hsv.withHue(h);
                    widget.onChanged(_hsv.toColor());
                  }),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Sat / Val ─────────────────────────────────────────────────
            _SectionLabel(
              label: 'COLOR',
              active: _section == _PickerSection.satVal,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _section = _PickerSection.satVal),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _section == _PickerSection.satVal
                      ? Colors.white.withOpacity(0.04)
                      : Colors.transparent,
                  border: Border.all(
                    color: _section == _PickerSection.satVal
                        ? Colors.white.withOpacity(0.2)
                        : Colors.transparent,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _SatValBox(
                  hsv: _hsv,
                  onChanged: (sv) => setState(() {
                    _hsv = HSVColor.fromAHSV(
                      1.0,
                      _hsv.hue,
                      sv.saturation,
                      sv.value,
                    );
                    widget.onChanged(_hsv.toColor());
                  }),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Apply button ──────────────────────────────────────────────
            GestureDetector(
              onTap: () => _apply(current),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _section == _PickerSection.apply
                      ? current.withOpacity(0.25)
                      : current.withOpacity(0.12),
                  border: Border.all(
                    color: _section == _PickerSection.apply
                        ? current.withOpacity(0.9)
                        : current.withOpacity(0.4),
                    width: _section == _PickerSection.apply ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _section == _PickerSection.apply
                      ? [
                          BoxShadow(
                            color: current.withOpacity(0.2),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: current,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: current.withOpacity(0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'APPLY',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _section == _PickerSection.apply
                            ? ConsoleColors.text
                            : ConsoleColors.text2,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Gamepad hint bar ──────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: SizedBox(
                key: ValueKey(_section),
                width: double.infinity,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: _hints.map((h) => _PickerHint(h.$1, h.$2)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Picker section label ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 7,
            letterSpacing: 2.0,
            color: active ? ConsoleColors.cyan : ConsoleColors.text3,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 6),
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ConsoleColors.cyan,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Picker hint badge ─────────────────────────────────────────────────────────

class _PickerHint extends StatelessWidget {
  const _PickerHint(this.button, this.label);
  final String button;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: ConsoleColors.border2),
            borderRadius: BorderRadius.circular(3),
            color: ConsoleColors.panel2,
          ),
          child: Text(
            button,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: ConsoleColors.text2,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 7,
            color: ConsoleColors.text3,
          ),
        ),
      ],
    );
  }
}

// ── Hue bar ───────────────────────────────────────────────────────────────────

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) =>
              onChanged((d.localPosition.dx / width * 360).clamp(0, 360)),
          onHorizontalDragUpdate: (d) =>
              onChanged((d.localPosition.dx / width * 360).clamp(0, 360)),
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              painter: _HueBarPainter(hue: hue),
              size: Size(width, 22),
            ),
          ),
        );
      },
    );
  }
}

class _HueBarPainter extends CustomPainter {
  const _HueBarPainter({required this.hue});
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Rainbow gradient
    final gradient = LinearGradient(
      colors: List.generate(
        37,
        (i) => HSVColor.fromAHSV(1, i * 10.0, 1, 1).toColor(),
      ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..shader = gradient.createShader(rect),
    );
    // Thumb
    final tx = hue / 360 * size.width;
    final thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(tx, size.height / 2), 9, thumbPaint);
    canvas.drawCircle(
      Offset(tx, size.height / 2),
      9,
      Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Show current hue inside thumb
    canvas.drawCircle(
      Offset(tx, size.height / 2),
      5,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
  }

  @override
  bool shouldRepaint(_HueBarPainter old) => old.hue != hue;
}

// ── Saturation / Value box ────────────────────────────────────────────────────

class _SatValBox extends StatelessWidget {
  const _SatValBox({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const height = 160.0;
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _emit(d.localPosition, width, height),
          onPanUpdate: (d) => _emit(d.localPosition, width, height),
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _SatValPainter(hsv: hsv),
              size: Size(width, height),
            ),
          ),
        );
      },
    );
  }

  void _emit(Offset pos, double w, double h) {
    final s = (pos.dx / w).clamp(0.0, 1.0);
    final v = (1 - pos.dy / h).clamp(0.0, 1.0);
    onChanged(HSVColor.fromAHSV(1.0, hsv.hue, s, v));
  }
}

class _SatValPainter extends CustomPainter {
  const _SatValPainter({required this.hsv});
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Base hue
    canvas.drawRRect(
      rrect,
      Paint()..color = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
    );
    // White gradient (left → transparent)
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0)],
        ).createShader(rect),
    );
    // Black gradient (bottom → transparent)
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    // Crosshair thumb
    final tx = hsv.saturation * size.width;
    final ty = (1 - hsv.value) * size.height;
    final thumbColor = hsv.toColor();

    canvas.drawCircle(
      Offset(tx, ty),
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(tx, ty), 7, Paint()..color = thumbColor);
  }

  @override
  bool shouldRepaint(_SatValPainter old) => old.hsv != hsv;
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatefulWidget {
  const _SliderRow({
    super.key,
    required this.id,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
    this.isFocused = false,
    this.isActive = false,
  });

  final String id;
  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelBuilder;
  final ValueChanged<double> onChanged;
  final bool isFocused;
  final bool isActive;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late double _local;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _local = widget.value;
  }

  @override
  void didUpdateWidget(_SliderRow old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.value != widget.value) _local = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final isFocused = widget.isFocused;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isActive
            ? ConsoleColors.cyan.withOpacity(0.06)
            : isFocused
            ? Colors.white.withOpacity(0.04)
            : Colors.transparent,
        border: isActive
            ? Border.all(color: ConsoleColors.cyan.withOpacity(0.4))
            : isFocused
            ? Border.all(color: Colors.white.withOpacity(0.15))
            : const Border(),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive ? ConsoleColors.cyan : ConsoleColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.description,
                  style: const TextStyle(
                    fontSize: 10,
                    color: ConsoleColors.text2,
                  ),
                ),
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '◀ D-PAD ▶  •  L1/R1 fast jump',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        color: ConsoleColors.cyan.withOpacity(0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: isActive
                    ? ConsoleColors.cyan
                    : ConsoleColors.cyan.withOpacity(0.7),
                inactiveTrackColor: ConsoleColors.border2,
                thumbColor: Colors.white,
                thumbShape: _BorderedThumbShape(
                  borderColor: isActive
                      ? ConsoleColors.cyan
                      : ConsoleColors.cyan.withOpacity(0.6),
                  isActive: isActive,
                ),
                overlayColor: ConsoleColors.cyan.withOpacity(0.12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: _local,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                onChanged: (v) => setState(() {
                  _dragging = true;
                  _local = v;
                }),
                onChangeEnd: (v) {
                  setState(() => _dragging = false);
                  widget.onChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 52,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? ConsoleColors.cyan.withOpacity(0.15)
                  : ConsoleColors.cyan.withOpacity(0.08),
              border: Border.all(
                color: isActive
                    ? ConsoleColors.cyan.withOpacity(0.6)
                    : ConsoleColors.cyan.withOpacity(0.3),
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              widget.labelBuilder(_local),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isActive
                    ? ConsoleColors.cyan
                    : ConsoleColors.cyan.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BorderedThumbShape extends SliderComponentShape {
  const _BorderedThumbShape({
    required this.borderColor,
    this.thumbRadius = 7.0,
    this.borderWidth = 2.0,
    this.isActive = false,
  });

  final Color borderColor;
  final double thumbRadius;
  final double borderWidth;
  final bool isActive;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

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
    canvas.drawCircle(center, thumbRadius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      thumbRadius - borderWidth / 2,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
    if (isActive) {
      canvas.drawCircle(
        center,
        thumbRadius - borderWidth - 1.5,
        Paint()..color = borderColor.withOpacity(0.5),
      );
    }
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    super.key,
    required this.id,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.isFocused = false,
  });

  final String id;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isFocused ? Colors.white.withOpacity(0.04) : Colors.transparent,
        border: isFocused
            ? Border.all(color: Colors.white.withOpacity(0.15))
            : const Border(),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ConsoleColors.text,
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
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 24,
              decoration: BoxDecoration(
                color: value
                    ? ConsoleColors.cyan.withOpacity(0.12)
                    : ConsoleColors.panel2,
                border: Border.all(
                  color: isFocused
                      ? Colors.white.withOpacity(0.6)
                      : value
                      ? ConsoleColors.cyan.withOpacity(0.5)
                      : ConsoleColors.border2,
                  width: isFocused ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? ConsoleColors.cyan : ConsoleColors.text3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Preset chip ───────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.name,
    required this.colors,
    this.isFocused = false,
  });
  final String name;
  final List<Color> colors;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withOpacity(0.06)
            : ConsoleColors.panel2,
        border: Border.all(
          color: isFocused
              ? Colors.white.withOpacity(0.5)
              : ConsoleColors.border2,
          width: isFocused ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: colors
                .take(4)
                .map(
                  (c) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                )
                .toList(),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: ConsoleColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}
