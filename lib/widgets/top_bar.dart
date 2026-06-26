import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/home_screen.dart';
import '../services/haptic_service.dart';

class TopBar extends StatefulWidget {
  const TopBar({super.key, required this.isRunning, required this.onToggle});

  final bool isRunning;
  final VoidCallback onToggle;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  late Timer _clockTimer;
  String _time = '';

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isRunning) _blink.repeat(reverse: true);
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateTime(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  void didUpdateWidget(TopBar old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!widget.isRunning && _blink.isAnimating) {
      _blink.stop();
      _blink.animateTo(1.0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: ConsoleColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ConsoleColors.border)),
      ),
      child: Row(
        children: [
          // Logo mark
          _LogoMark(),
          const SizedBox(width: 10),

          // App name
          Text(
            'LIGHTMEUP',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
              color: ConsoleColors.text.withOpacity(0.85),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'AMBIENT SYNC',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              letterSpacing: 1.5,
              color: ConsoleColors.text2,
            ),
          ),

          const Spacer(),

          // Status pill — tappable
          GestureDetector(
            onTap: () {
              if (widget.isRunning) {
                HapticService.serviceOff();
              } else {
                HapticService.serviceOn();
              }
              widget.onToggle();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.isRunning
                    ? ConsoleColors.cyan.withOpacity(0.08)
                    : Colors.transparent,
                border: Border.all(
                  color: widget.isRunning
                      ? ConsoleColors.cyan.withOpacity(0.5)
                      : ConsoleColors.border2,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _blink,
                    builder: (_, __) => Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isRunning
                            ? ConsoleColors.cyan.withOpacity(
                                0.3 + _blink.value * 0.7,
                              )
                            : ConsoleColors.text3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isRunning ? 'ACTIVE' : 'OFFLINE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: widget.isRunning
                          ? ConsoleColors.cyan
                          : ConsoleColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Clock
          Text(
            _time,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              letterSpacing: 1,
              color: ConsoleColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: ConsoleColors.cyan, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Center(
        child: Text(
          'L',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ConsoleColors.cyan,
          ),
        ),
      ),
    );
  }
}
