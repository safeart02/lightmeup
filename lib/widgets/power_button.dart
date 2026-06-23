import 'package:flutter/material.dart';

class PowerButton extends StatefulWidget {
  const PowerButton({
    super.key,
    required this.isRunning,
    required this.onTap,
  });

  final bool isRunning;
  final VoidCallback onTap;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.isRunning) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PowerButton old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isRunning && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.isRunning ? cs.primary : cs.outline;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isRunning
                  ? cs.primary.withOpacity(0.15)
                  : cs.surfaceContainerHigh,
              border: Border.all(color: color, width: 2.5),
              boxShadow: widget.isRunning
                  ? [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.45),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ]
                  : [],
            ),
            child: Icon(
              Icons.power_settings_new_rounded,
              size: 48,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
