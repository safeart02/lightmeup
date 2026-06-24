import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../screens/home_screen.dart';
import '../widgets/bottom_bar.dart';

class ControlsSection extends StatefulWidget {
  const ControlsSection({super.key, required this.state});
  final AppState state;

  @override
  State<ControlsSection> createState() => _ControlsSectionState();
}

class _ControlsSectionState extends State<ControlsSection> {
  /// Which slot is currently listening for a key press.
  _ListeningSlot? _listening;

  @override
  Widget build(BuildContext context) {
    final leftKey = widget.state.settings.quickPanelLeftKey;
    final rightKey = widget.state.settings.quickPanelRightKey;

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
              assignedKey: leftKey,
              isListening: _listening == _ListeningSlot.left,
              onStartListen: () =>
                  setState(() => _listening = _ListeningSlot.left),
              onClear: () {
                context.read<AppState>().setQuickPanelLeftKey(null);
                setState(() => _listening = null);
              },
            ),
            _KeyBindRow(
              label: 'Right Panel',
              description: 'Open the right quick-access panel',
              assignedKey: rightKey,
              isListening: _listening == _ListeningSlot.right,
              onStartListen: () =>
                  setState(() => _listening = _ListeningSlot.right),
              onClear: () {
                context.read<AppState>().setQuickPanelRightKey(null);
                setState(() => _listening = null);
              },
            ),
          ],
        ),

        // ── Listening overlay ──────────────────────────────────────────────
        if (_listening != null)
          _KeyCaptureOverlay(
            slot: _listening!,
            onKeyCapture: (key) {
              if (_listening == _ListeningSlot.left) {
                context.read<AppState>().setQuickPanelLeftKey(key);
              } else {
                context.read<AppState>().setQuickPanelRightKey(key);
              }
              setState(() => _listening = null);
            },
            onCancel: () => setState(() => _listening = null),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Text(
            'You can also open either panel by swiping from the screen edge.',
            style: const TextStyle(
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
    required this.assignedKey,
    required this.isListening,
    required this.onStartListen,
    required this.onClear,
  });

  final String label;
  final String description;
  final LogicalKeyboardKey? assignedKey;
  final bool isListening;
  final VoidCallback onStartListen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
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
              // Key badge / assign button
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
                        : (assignedKey != null
                              ? _keyLabel(assignedKey!)
                              : 'Not assigned'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isListening
                          ? ConsoleColors.cyan
                          : (assignedKey != null
                                ? ConsoleColors.text
                                : ConsoleColors.text3),
                    ),
                  ),
                ),
              ),

              // Clear button — only shown when assigned
              if (assignedKey != null && !isListening) ...[
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

  String _keyLabel(LogicalKeyboardKey key) {
    // Prefer the key label if it's short and readable,
    // otherwise fall back to the key ID.
    final label = key.keyLabel;
    if (label.isNotEmpty && label.length <= 12) return label;
    return '0x${key.keyId.toRadixString(16).toUpperCase()}';
  }
}

// ── Key capture overlay ───────────────────────────────────────────────────────

/// Full-section focus trap that listens for any key press and reports it.
class _KeyCaptureOverlay extends StatelessWidget {
  const _KeyCaptureOverlay({
    required this.slot,
    required this.onKeyCapture,
    required this.onCancel,
  });

  final _ListeningSlot slot;
  final ValueChanged<LogicalKeyboardKey> onKeyCapture;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        // Escape cancels without assigning
        if (key == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        onKeyCapture(key);
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: onCancel,
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
                Icons.radio_button_checked_rounded,
                size: 14,
                color: ConsoleColors.cyan,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Press the button you want to assign to the '
                  '${slot == _ListeningSlot.left ? 'left' : 'right'} panel. '
                  'Tap here or press Escape to cancel.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ConsoleColors.cyan,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ListeningSlot { left, right }
