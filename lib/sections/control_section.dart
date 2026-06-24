import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../services/app_state.dart';
import '../screens/home_screen.dart';
import '../widgets/bottom_bar.dart';

class ControlsSection extends StatefulWidget {
  const ControlsSection({super.key, required this.state});
  final AppState state;

  // The helper method remains safely here
  void _openAccessibilitySettings() {
    const intent = AndroidIntent(
      action: 'android.settings.ACCESSIBILITY_SETTINGS',
    );
    intent.launch();
  }

  @override
  State<ControlsSection> createState() => _ControlsSectionState();
}

class _ControlsSectionState extends State<ControlsSection> {
  /// Which slot is currently listening for a key press.
  _ListeningSlot? _listening;

  @override
  Widget build(BuildContext context) {
    final leftKeys = widget.state.settings.quickPanelLeftKeys;
    final rightKeys = widget.state.settings.quickPanelRightKeys;

    return SectionScaffold(
      title: 'Controls',
      description: 'Assign hardware buttons to open the quick panel',
      children: [
        SettingGroup(
          label: 'QUICK PANEL',
          children: [
            _KeyBindRow(
              label: 'Left Panel',
              description: 'Open the left quick-access panel',
              assignedKeys: leftKeys,
              isListening: _listening == _ListeningSlot.left,
              onStartListen: () =>
                  setState(() => _listening = _ListeningSlot.left),
              onClear: () {
                context.read<AppState>().setQuickPanelLeftKeys(null);
                setState(() => _listening = null);
              },
            ),
            _KeyBindRow(
              label: 'Right Panel',
              description: 'Open the right quick-access panel',
              assignedKeys: rightKeys,
              isListening: _listening == _ListeningSlot.right,
              onStartListen: () =>
                  setState(() => _listening = _ListeningSlot.right),
              onClear: () {
                context.read<AppState>().setQuickPanelRightKeys(null);
                setState(() => _listening = null);
              },
            ),
          ],
        ),

        // ── ADDED: BACKGROUND SHORTCUT SERVICE SETUP CARD ──────────────────
        const SizedBox(height: 12),
        SettingGroup(
          label: 'BACKGROUND SHORTCUTS',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Global Key Listening',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: ConsoleColors.text,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Required to listen for button triggers outside of this application.',
                          style: TextStyle(
                            fontSize: 10,
                            color: ConsoleColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: widget._openAccessibilitySettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ConsoleColors.panel2,
                      side: const BorderSide(color: ConsoleColors.border2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Configure',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ConsoleColors.cyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── Listening overlay ──────────────────────────────────────────────
        if (_listening != null)
          _KeyCaptureOverlay(
            slot: _listening!,
            onKeysCaptured: (keys) {
              if (_listening == _ListeningSlot.left) {
                context.read<AppState>().setQuickPanelLeftKeys(keys);
              } else {
                context.read<AppState>().setQuickPanelRightKeys(keys);
              }
              setState(() => _listening = null);
            },
            onCancel: () => setState(() => _listening = null),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: const Text(
            'You can also open either panel by swiping from the screen edge.',
            style: TextStyle(
              fontSize: 11,
              color: ConsoleColors.text2,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Key bind row ──────────────────────────────────────────────────────────────

class _KeyBindRow extends StatelessWidget {
  const _KeyBindRow({
    required this.label,
    required this.description,
    required this.assignedKeys,
    required this.isListening,
    required this.onStartListen,
    required this.onClear,
  });

  final String label;
  final String description;
  final List<LogicalKeyboardKey>? assignedKeys;
  final bool isListening;
  final VoidCallback onStartListen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasKeys = assignedKeys != null && assignedKeys!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
          const SizedBox(width: 12),
          Row(
            children: [
              GestureDetector(
                onTap: onStartListen,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isListening
                        ? ConsoleColors.cyan.withOpacity(0.12)
                        : ConsoleColors.panel2,
                    border: Border.all(
                      color: isListening
                          ? ConsoleColors.cyan.withOpacity(0.6)
                          : ConsoleColors.border2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isListening
                        ? 'Press any button…'
                        : _keysLabel(assignedKeys),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isListening
                          ? ConsoleColors.cyan
                          : (hasKeys
                                ? ConsoleColors.text
                                : ConsoleColors.text3),
                    ),
                  ),
                ),
              ),
              if (hasKeys && !isListening) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      border: Border.all(color: ConsoleColors.border2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: ConsoleColors.text2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _keysLabel(List<LogicalKeyboardKey>? keys) {
    if (keys == null || keys.isEmpty) return 'Not assigned';

    return keys
        .map((key) {
          final label = key.keyLabel;
          if (label.isNotEmpty && label.length <= 12) return label;
          return '0x${key.keyId.toRadixString(16).toUpperCase()}';
        })
        .join(' + ');
  }
}

// ── Key capture overlay ───────────────────────────────────────────────────────

class _KeyCaptureOverlay extends StatefulWidget {
  const _KeyCaptureOverlay({
    required this.slot,
    required this.onKeysCaptured,
    required this.onCancel,
  });

  final _ListeningSlot slot;
  final ValueChanged<List<LogicalKeyboardKey>> onKeysCaptured;
  final VoidCallback onCancel;

  @override
  State<_KeyCaptureOverlay> createState() => _KeyCaptureOverlayState();
}

class _KeyCaptureOverlayState extends State<_KeyCaptureOverlay> {
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: FocusScopeNode(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (_, event) {
          final key = event.logicalKey;

          if (key == LogicalKeyboardKey.escape &&
              event is KeyDownEvent &&
              _pressedKeys.isEmpty) {
            widget.onCancel();
            return KeyEventResult.handled;
          }

          if (event is KeyDownEvent) {
            setState(() {
              _pressedKeys.add(key);
            });
            return KeyEventResult.handled;
          }

          if (event is KeyUpEvent) {
            if (_pressedKeys.isNotEmpty) {
              widget.onKeysCaptured(_pressedKeys.toList());
              _pressedKeys.clear();
            }
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onCancel,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ConsoleColors.cyanDim,
              border: Border.all(color: ConsoleColors.cyan.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.keyboard_rounded,
                  size: 16,
                  color: ConsoleColors.cyan,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pressedKeys.isEmpty
                            ? 'Press your key combination...'
                            : 'Holding: ${_pressedKeys.map((k) => k.keyLabel).join(" + ")}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: ConsoleColors.cyan,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Press one or more keys together and release. Press Escape alone to cancel.',
                        style: TextStyle(
                          fontSize: 10,
                          color: ConsoleColors.cyan.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ListeningSlot { left, right }
