import 'package:material_ui/material_ui.dart';

ThemeData buildTheme(Brightness b) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F46E5),
    brightness: b,
  ),
);
