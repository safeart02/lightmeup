import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../widgets/bottom_bar.dart';

class PerformanceSection extends StatelessWidget {
  const PerformanceSection({
    super.key,
    required this.state,
    required this.cursorRow,
    required this.activeRow,
    required this.frameSkipCtrl,
  });

  final AppState state;
  final int cursorRow;
  final int activeRow;
  final SliderController frameSkipCtrl;

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Performance',
      description: 'Frame processing and battery trade-offs',
      children: [
        SettingGroup(
          label: 'SAMPLING',
          children: [
            SettingRow(
              name: 'Frame Skip',
              description: 'Process every Nth frame — reduces CPU load',
              highlighted: cursorRow == 0,
              active: activeRow == 0,
              control: ConsoleSlider(
                value: state.settings.frameSkip.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                label: state.settings.frameSkip == 0
                    ? 'Every'
                    : '1 in ${state.settings.frameSkip + 1}',
                controller: frameSkipCtrl,
                onChanged: (v) =>
                    context.read<AppState>().updateFrameSkip(v.round()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
