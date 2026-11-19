import 'package:material_ui/material_ui.dart';

import 'src/home_page.dart';
import 'src/monitor.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  runApp(VanaLogMeterApp(settings: settings, monitor: LogMonitor()));
}

class VanaLogMeterApp extends StatelessWidget {
  const VanaLogMeterApp({super.key, required this.settings, required this.monitor});

  final Settings settings;
  final LogMonitor monitor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vana-log-meter',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomePage(settings: settings, monitor: monitor),
    );
  }
}
