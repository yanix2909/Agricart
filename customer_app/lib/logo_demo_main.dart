import 'package:flutter/material.dart';
import 'screens/logo_preview_screen.dart';

/// Standalone demo app to preview and export the custom painted logo
/// 
/// To run this demo:
/// 1. Temporarily replace main.dart content with this file's runApp call
/// 2. Or run: flutter run -t lib/logo_demo_main.dart
/// 
/// Or add a button in profile/settings to navigate to LogoPreviewScreen

void main() {
  runApp(const LogoDemoApp());
}

class LogoDemoApp extends StatelessWidget {
  const LogoDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriCart Logo Generator',
      theme: ThemeData(
        primaryColor: const Color(0xFF2E7D32),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          primary: const Color(0xFF2E7D32),
        ),
        useMaterial3: true,
      ),
      home: const LogoPreviewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

