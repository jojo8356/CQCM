import 'package:flutter/material.dart';
import 'screens/main_menu_screen.dart';
import 'widgets/ui_zoom_scope.dart';

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
      // Zoom de l'interface (Ctrl +, Ctrl -, Ctrl + molette) pour tout
      // l'arbre : menu, catalogue et sessions comprises.
      builder: (context, child) => UiZoomScope(child: child),
      home: const MainMenuScreen(),
    );
  }
}
