import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.selected,
    required this.isRunning,
    required this.navFocused,
    required this.onSelect,
    required this.onToggle,
  });

  final NavSection selected;
  final bool isRunning;

  /// True when Level 0 is active — the nav panel itself has gamepad focus.
  final bool navFocused;
  final ValueChanged<NavSection> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: ConsoleColors.panel,
        border: Border(right: BorderSide(color: ConsoleColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 7,
                letterSpacing: 2.0,
                color: ConsoleColors.text3,
              ),
            ),
          ),

          _NavItem(
            icon: Icons.brightness_medium_rounded,
            label: 'Output',
            section: NavSection.output,
            selected: selected,
            navFocused: navFocused,
            onTap: onSelect,
          ),
          _NavItem(
            icon: Icons.crop_free_rounded,
            label: 'Capture',
            section: NavSection.capture,
            selected: selected,
            navFocused: navFocused,
            onTap: onSelect,
          ),
          _NavItem(
            icon: Icons.speed_rounded,
            label: 'Performance',
            section: NavSection.performance,
            selected: selected,
            navFocused: navFocused,
            onTap: onSelect,
          ),
          _NavItem(
            icon: Icons.info_outline_rounded,
            label: 'About',
            section: NavSection.about,
            selected: selected,
            navFocused: navFocused,
            onTap: onSelect,
          ),

          const Spacer(),

          Padding(
            padding: const EdgeInsets.all(14),
            child: _PowerButton(isRunning: isRunning, onToggle: onToggle),
          ),
        ],
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.section,
    required this.selected,
    required this.navFocused,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final NavSection section;
  final NavSection selected;
  final bool navFocused;
  final ValueChanged<NavSection> onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = section == selected;
    // "Cursor" = this item is selected AND the nav panel has gamepad focus.
    // Visually brighter than the dimmer "content open" selected state.
    final isCursor = isSelected && navFocused;

    final Color leftBorder;
    final Color bg;
    final Color iconColor;
    final Color labelColor;
    final FontWeight labelWeight;

    if (isCursor) {
      // Full-brightness cyan: nav panel is focused here
      leftBorder = ConsoleColors.cyan;
      bg = ConsoleColors.cyanDim;
      iconColor = ConsoleColors.cyan;
      labelColor = ConsoleColors.cyan;
      labelWeight = FontWeight.w700;
    } else if (isSelected) {
      // Dimmer: content is open but nav panel is not focused
      leftBorder = ConsoleColors.cyan.withOpacity(0.35);
      bg = ConsoleColors.cyanGlow;
      iconColor = ConsoleColors.cyan.withOpacity(0.6);
      labelColor = ConsoleColors.cyan.withOpacity(0.6);
      labelWeight = FontWeight.w600;
    } else {
      leftBorder = Colors.transparent;
      bg = Colors.transparent;
      iconColor = ConsoleColors.text2;
      labelColor = ConsoleColors.text2;
      labelWeight = FontWeight.w500;
    }

    return GestureDetector(
      onTap: () => onTap(section),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          border: Border(left: BorderSide(color: leftBorder, width: 2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: labelWeight,
                  color: labelColor,
                ),
              ),
            ),
            // Chevron only when nav is focused — hints "press A to enter"
            if (isCursor)
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: ConsoleColors.cyan.withOpacity(0.6),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Power button ──────────────────────────────────────────────────────────────

class _PowerButton extends StatefulWidget {
  const _PowerButton({required this.isRunning, required this.onToggle});
  final bool isRunning;
  final VoidCallback onToggle;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _iconAnim;
  bool _prevRunning = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 1.0,
    );
    _iconAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _prevRunning = widget.isRunning;
  }

  @override
  void didUpdateWidget(_PowerButton old) {
    super.didUpdateWidget(old);
    if (widget.isRunning != _prevRunning) {
      _ctrl.forward(from: 0.0);
      _prevRunning = widget.isRunning;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOn = widget.isRunning;

    return GestureDetector(
      onTap: widget.onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 42,
        decoration: BoxDecoration(
          color: isOn
              ? ConsoleColors.cyan.withOpacity(0.08)
              : Colors.transparent,
          border: Border.all(
            color: isOn
                ? ConsoleColors.cyan.withOpacity(0.4)
                : ConsoleColors.border2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotationTransition(
              turns: Tween<double>(begin: -0.25, end: 0.0).animate(_iconAnim),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1.0).animate(_iconAnim),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 15,
                  color: isOn ? ConsoleColors.cyan : ConsoleColors.text2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isOn ? 'STOP SERVICE' : 'START SERVICE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: isOn ? ConsoleColors.cyan : ConsoleColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
