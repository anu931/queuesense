import 'package:material_ui/material_ui.dart';

import 'core/store.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const QueueSenseApp());
}

class QueueSenseApp extends StatelessWidget {
  const QueueSenseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QueueSense',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: const HomeScreen(),
  );
}
