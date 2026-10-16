import 'package:flutter/material.dart';
import 'screens/main_menu_screen.dart';

void main() {
  runApp(const CQCMApp());
}

class CQCMApp extends StatelessWidget {
  const CQCMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CQCM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const MainMenuScreen(),
    );
  }
}
