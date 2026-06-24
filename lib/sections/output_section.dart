import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../widgets/bottom_bar.dart';

class OutputSection extends StatelessWidget {
  const OutputSection({
    super.key,
    required this.state,
    required this.cursorRow,
    required this.activeRow,
    required this.brightnessCtrl,
    required this.smoothingCtrl,
  });

  final AppState state;
  final int cursorRow; // which row the d-pad cursor is on (-1 = none)
  final int activeRow; // which row ◄► is adjusting (-1 = none)
  final SliderController brightnessCtrl;
  final SliderController smoothingCtrl;

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Output',
      description: 'LED strip brightness and colour behaviour',
      children: [
        SettingGroup(
          label: 'BRIGHTNESS',
          children: [
            SettingRow(
              name: 'LED Brightness',
              description: 'Master luminance of the LED strip',
              highlighted: cursorRow == 0,
              active: activeRow == 0,
              control: ConsoleSlider(
                value: state.settings.brightness,
                min: 0.05,
                max: 1.0,
                divisions: 19,
                label: '${(state.settings.brightness * 100).round()}%',
                controller: brightnessCtrl,
                onChanged: (v) => context.read<AppState>().updateBrightness(v),
              ),
            ),
          ],
        ),
        SettingGroup(
          label: 'COLOUR',
          children: [
            SettingRow(
              name: 'Colour Smoothing',
              description: 'Transition speed between colours — higher = slower',
              highlighted: cursorRow == 1,
              active: activeRow == 1,
              control: ConsoleSlider(
                value: state.settings.smoothing,
                min: 0.0,
                max: 0.95,
                divisions: 19,
                label: state.settings.smoothing == 0.0
                    ? 'Off'
                    : '${(state.settings.smoothing * 100).round()}%',
                controller: smoothingCtrl,
                onChanged: (v) => context.read<AppState>().updateSmoothing(v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
