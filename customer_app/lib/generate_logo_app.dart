import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'widgets/agricart_logo_painter.dart';

/// Run this to generate the logo: flutter run -t lib/generate_logo_app.dart
void main() {
  runApp(const LogoGeneratorApp());
}

class LogoGeneratorApp extends StatelessWidget {
  const LogoGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const LogoGenerator(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LogoGenerator extends StatefulWidget {
  const LogoGenerator({super.key});

  @override
  State<LogoGenerator> createState() => _LogoGeneratorState();
}

class _LogoGeneratorState extends State<LogoGenerator> {
  String _status = 'Initializing...';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // Generate logo after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateLogo();
    });
  }

  Future<void> _generateLogo() async {
    setState(() {
      _status = '🎨 Generating logo...';
      _isGenerating = true;
    });

    try {
      // Generate at 1024x1024 for high quality
      const size = 1024;
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final painter = AgriCartLogoPainter();
      painter.paint(canvas, const Size(size, size));
      
      final picture = recorder.endRecording();
      final img = await picture.toImage(size, size);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      
      // Get the project root directory
      final currentDir = Directory.current.path;
      final assetPath = '$currentDir/assets/images/agricart_logo.png';
      
      // Save the file
      final file = File(assetPath);
      await file.writeAsBytes(bytes);
      
      setState(() {
        _status = '✅ Logo generated successfully!\n\n'
            '📁 Saved to:\n'
            'assets/images/agricart_logo.png\n\n'
            '📏 Size: ${size}x$size pixels\n\n'
            '🎯 Next steps:\n'
            '1. Run: flutter pub run flutter_launcher_icons\n'
            '2. Run: flutter clean\n'
            '3. Run: flutter build apk\n\n'
            'You can close this app now.';
        _isGenerating = false;
      });
      
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e\n\n'
            'Make sure you run this from the customer_app directory';
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2E8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.brush,
                size: 80,
                color: Color(0xFF2E7D32),
              ),
              const SizedBox(height: 24),
              const Text(
                'AgriCart Logo Generator',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              if (_isGenerating)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
                )
              else
                const AgriCartLogoWidget(size: 200),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _status,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (!_isGenerating && _status.contains('successfully'))
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: ElevatedButton.icon(
                    onPressed: () => _generateLogo(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate Logo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

