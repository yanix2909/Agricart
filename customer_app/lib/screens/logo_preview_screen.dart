import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:gal/gal.dart';
import '../widgets/agricart_logo_painter.dart';
import '../../utils/responsive.dart';

/// Screen to preview and export the custom painted AgriCart logo
/// Use this to generate PNG files for app icons
class LogoPreviewScreen extends StatefulWidget {
  const LogoPreviewScreen({super.key});

  @override
  State<LogoPreviewScreen> createState() => _LogoPreviewScreenState();
}

class _LogoPreviewScreenState extends State<LogoPreviewScreen> {
  final GlobalKey _logoKey = GlobalKey();
  bool _isExporting = false;

  Future<void> _exportLogoPNG({int size = 512}) async {
    setState(() => _isExporting = true);

    try {
      // Create a custom paint with the desired size
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final painter = AgriCartLogoPainter();
      painter.paint(canvas, Size(size.toDouble(), size.toDouble()));
      
      final picture = recorder.endRecording();
      final img = await picture.toImage(size, size);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      // Save to gallery
      await Gal.putImageBytes(bytes, name: 'agricart_logo_${size}x$size.png');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logo exported as ${size}x$size PNG to gallery!'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AgriCart Logo Preview'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: Responsive.getHeight(context, mobile: 20)),
            Text(
              'Custom Painted Logo',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 24),
                fontWeight: FontWeight.bold,
                color: Color(0xFF2E7D32),
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 10)),
            Text(
              'Modern green vegetable cart design',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 16),
                color: Colors.grey,
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 40)),
            
            // Large preview
            Center(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: RepaintBoundary(
                  key: _logoKey,
                  child: AgriCartLogoWidget(size: Responsive.getIconSize(context, mobile: 300)),
                ),
              ),
            ),
            
            SizedBox(height: Responsive.getHeight(context, mobile: 40)),
            
            // Size previews
            Text(
              'Different Sizes',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 18),
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 20)),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSizePreview(48, 'Small'),
                _buildSizePreview(96, 'Medium'),
                _buildSizePreview(144, 'Large'),
              ],
            ),
            
            SizedBox(height: Responsive.getHeight(context, mobile: 40)),
            const Divider(),
            SizedBox(height: Responsive.getHeight(context, mobile: 20)),
            
            // Export buttons
            Text(
              'Export as PNG',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 18),
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            
            if (_isExporting)
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
              )
            else
              Column(
                children: [
                  _buildExportButton('512x512 (Recommended)', 512),
                  SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                  _buildExportButton('1024x1024 (High Quality)', 1024),
                  SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                  _buildExportButton('192x192 (Android XXXHDPI)', 192),
                ],
              ),
            
            SizedBox(height: Responsive.getHeight(context, mobile: 30)),
            
            // Instructions
            Container(
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F2E8),
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                border: Border.all(
                  color: const Color(0xFF2E7D32).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: const Color(0xFF2E7D32),
                        size: Responsive.getIconSize(context, mobile: 24),
                      ),
                      SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                      Text(
                        'How to Use',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 18),
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  _buildInstruction(
                    '1',
                    'Export logo as 512x512 or 1024x1024 PNG',
                  ),
                  _buildInstruction(
                    '2',
                    'Save the image to your computer from gallery',
                  ),
                  _buildInstruction(
                    '3',
                    'Replace assets/images/agricart_logo.png with the exported image',
                  ),
                  _buildInstruction(
                    '4',
                    'Run: flutter pub run flutter_launcher_icons',
                  ),
                  _buildInstruction(
                    '5',
                    'Rebuild the app to see the new icon',
                  ),
                ],
              ),
            ),
            
            SizedBox(height: Responsive.getHeight(context, mobile: 20)),
          ],
        ),
      ),
    );
  }

  Widget _buildSizePreview(double size, String label) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AgriCartLogoWidget(size: size),
        ),
        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
        Text(
          label,
          style: TextStyle(
            fontSize: Responsive.getFontSize(context, mobile: 12),
            color: Colors.grey,
          ),
        ),
        Text(
          '${size.toInt()}px',
          style: TextStyle(
            fontSize: Responsive.getFontSize(context, mobile: 10),
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildExportButton(String label, int size) {
    return SizedBox(
      width: double.infinity,
      height: Responsive.getHeight(context, mobile: 56),
      child: ElevatedButton.icon(
        onPressed: () => _exportLogoPNG(size: size),
        icon: const Icon(Icons.download),
        label: Text(
          label,
          style: TextStyle(
            fontSize: Responsive.getFontSize(context, mobile: 16),
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Responsive.getWidth(context, mobile: 28),
            height: Responsive.getHeight(context, mobile: 28),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: Responsive.getFontSize(context, mobile: 14),
                ),
              ),
            ),
          ),
          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 4)),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 14),
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

