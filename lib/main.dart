import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'services/settings_service.dart';
import 'services/lightmeup_channel.dart';
import 'services/app_state.dart';
import 'screens/home_screen.dart';
import 'overlay_main.dart' as overlay;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep overlayMain alive in the AOT snapshot.
  // ignore: unused_local_variable
  final _ = overlay.overlayMain; // ← tear-off, not a call
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LightmeupApp());
}

class LightmeupApp extends StatelessWidget {
  const LightmeupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        settingsService: SettingsService(),
        channel: LightmeupChannel(),
      )..init(),
      child: MaterialApp(
        title: 'LightMeUp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7C4DFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
