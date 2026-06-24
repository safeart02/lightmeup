import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../screens/home_screen.dart';
import '../widgets/bottom_bar.dart';

class CaptureSection extends StatefulWidget {
  const CaptureSection({
    super.key,
    required this.state,
    required this.cursorRow,
    required this.activeRow,
    required this.zoneWidthCtrl,
  });

  final AppState state;
  final int cursorRow;
  final int activeRow;
  final SliderController zoneWidthCtrl;

  @override
  State<CaptureSection> createState() => _CaptureSectionState();
}

class _CaptureSectionState extends State<CaptureSection> {
  late double _zoneWidth;

  @override
  void initState() {
    super.initState();
    _zoneWidth = widget.state.settings.zoneWidth;
  }

  @override
  void didUpdateWidget(CaptureSection old) {
    super.didUpdateWidget(old);
    if (old.state.settings.zoneWidth != widget.state.settings.zoneWidth) {
      _zoneWidth = widget.state.settings.zoneWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Capture',
      description: 'Screen sampling zones for left and right sticks',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ZONE PREVIEW',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 7,
                  letterSpacing: 2.0,
                  color: ConsoleColors.text3,
                ),
              ),
              const SizedBox(height: 8),
              _ZonePreview(zoneWidth: _zoneWidth),
            ],
          ),
        ),
        SettingGroup(
          label: 'ZONE',
          children: [
            SettingRow(
              name: 'Zone Width',
              description: 'Portion of screen edge sampled per stick',
              highlighted: widget.cursorRow == 0,
              active: widget.activeRow == 0,
              control: ConsoleSlider(
                value: _zoneWidth,
                min: 0.05,
                max: 0.40,
                divisions: 7,
                label: '${(_zoneWidth * 100).round()}%',
                controller: widget.zoneWidthCtrl,
                onChanged: (v) {
                  setState(() => _zoneWidth = v);
                  context.read<AppState>().updateZoneWidth(v);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Zone preview ──────────────────────────────────────────────────────────────

class _ZonePreview extends StatelessWidget {
  const _ZonePreview({required this.zoneWidth});
  final double zoneWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        const h = 72.0;
        final zoneW = w * zoneWidth;

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFF050710),
                  border: Border.all(color: ConsoleColors.border2),
                  borderRadius: BorderRadius.circular(3),
                ),
                clipBehavior: Clip.hardEdge,
                child: CustomPaint(
                  size: Size(w, h),
                  painter: _ZonePainter(zoneW: zoneW, totalW: w, height: h),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _BracketPainter(
                    color: ConsoleColors.text3.withOpacity(0.8),
                    size: 10,
                  ),
                ),
              ),
              Positioned(
                left: 5,
                bottom: 5,
                child: Text(
                  'L  ${(zoneWidth * 100).round()}%',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: ConsoleColors.cyan,
                  ),
                ),
              ),
              Center(
                child: Text(
                  'game screen',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    letterSpacing: 2,
                    color: ConsoleColors.text3,
                  ),
                ),
              ),
              Positioned(
                right: 5,
                bottom: 5,
                child: Text(
                  'R  ${(zoneWidth * 100).round()}%',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: ConsoleColors.violet,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZonePainter extends CustomPainter {
  _ZonePainter({
    required this.zoneW,
    required this.totalW,
    required this.height,
  });
  final double zoneW, totalW, height;

  @override
  void paint(Canvas canvas, Size size) {
    final scanPaint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1;
    for (double y = 0; y < height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(totalW, y), scanPaint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, zoneW, height),
      Paint()..color = ConsoleColors.cyan.withOpacity(0.14),
    );
    canvas.drawLine(
      Offset(zoneW, 0),
      Offset(zoneW, height),
      Paint()
        ..color = ConsoleColors.cyan.withOpacity(0.5)
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      Rect.fromLTWH(totalW - zoneW, 0, zoneW, height),
      Paint()..color = ConsoleColors.violet.withOpacity(0.14),
    );
    canvas.drawLine(
      Offset(totalW - zoneW, 0),
      Offset(totalW - zoneW, height),
      Paint()
        ..color = ConsoleColors.violet.withOpacity(0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ZonePainter old) => old.zoneW != zoneW;
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size sz) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    _bracket(canvas, paint, Offset(0, size), Offset.zero, Offset(size, 0));
    _bracket(
      canvas,
      paint,
      Offset(sz.width - size, 0),
      Offset(sz.width, 0),
      Offset(sz.width, size),
    );
    _bracket(
      canvas,
      paint,
      Offset(0, sz.height - size),
      Offset(0, sz.height),
      Offset(size, sz.height),
    );
    _bracket(
      canvas,
      paint,
      Offset(sz.width - size, sz.height),
      Offset(sz.width, sz.height),
      Offset(sz.width, sz.height - size),
    );
  }

  void _bracket(Canvas c, Paint p, Offset a, Offset b, Offset d) {
    c.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(d.dx, d.dy),
      p,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}
