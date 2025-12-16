import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Custom painted AgriCart logo with modern green vegetable cart design
/// on cream background. Perfect for app icons and branding.
class AgriCartLogoPainter extends CustomPainter {
  final Color backgroundColor;
  final Color primaryGreen;
  final Color darkGreen;
  final Color accentGreen;

  AgriCartLogoPainter({
    this.backgroundColor = const Color(0xFFF5F2E8), // Cream
    this.primaryGreen = const Color(0xFF2E7D32), // Modern green
    this.darkGreen = const Color(0xFF1B5E20), // Dark green
    this.accentGreen = const Color(0xFF4CAF50), // Light green
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width / 2;

    // Draw cream circular background
    paint.color = backgroundColor;
    canvas.drawCircle(Offset(centerX, centerY), radius, paint);

    // Scale factor for responsive sizing
    final scale = size.width / 200;

    // === SHOPPING CART BASE ===
    
    // Cart body (trapezoid shape - modern minimalist design)
    final cartPath = Path();
    final cartTop = centerY - 25 * scale;
    final cartBottom = centerY + 25 * scale;
    final cartLeft = centerX - 35 * scale;
    final cartRight = centerX + 35 * scale;

    cartPath.moveTo(cartLeft + 8 * scale, cartTop); // Top left
    cartPath.lineTo(cartRight - 8 * scale, cartTop); // Top right
    cartPath.lineTo(cartRight, cartBottom); // Bottom right
    cartPath.lineTo(cartLeft, cartBottom); // Bottom left
    cartPath.close();

    // Fill cart body with light green
    paint.color = const Color(0xFFE8F5E9); // Very light green
    canvas.drawPath(cartPath, paint);

    // Cart outline
    strokePaint.color = primaryGreen;
    strokePaint.strokeWidth = 3 * scale;
    strokePaint.strokeCap = StrokeCap.round;
    strokePaint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(cartPath, strokePaint);

    // Cart handle (modern curved design)
    final handlePath = Path();
    handlePath.moveTo(cartLeft + 8 * scale, cartTop);
    handlePath.quadraticBezierTo(
      centerX - 45 * scale,
      cartTop - 25 * scale,
      centerX - 45 * scale,
      cartTop - 35 * scale,
    );
    handlePath.lineTo(centerX - 40 * scale, cartTop - 35 * scale);
    
    strokePaint.color = primaryGreen;
    strokePaint.strokeWidth = 3 * scale;
    canvas.drawPath(handlePath, strokePaint);

    // === VEGETABLES IN CART ===

    // Leafy vegetable (lettuce/cabbage) - Back left
    paint.color = accentGreen;
    final leafy1Path = Path();
    final leafy1X = centerX - 20 * scale;
    final leafy1Y = cartTop + 10 * scale;
    
    // Draw layered leaves
    for (int i = 0; i < 5; i++) {
      final angle = (i * 72) * math.pi / 180;
      final leafX = leafy1X + math.cos(angle) * 8 * scale;
      final leafY = leafy1Y + math.sin(angle) * 8 * scale;
      canvas.drawCircle(
        Offset(leafX, leafY),
        6 * scale,
        paint..color = Color.lerp(accentGreen, primaryGreen, i * 0.15)!,
      );
    }
    // Center of leafy vegetable
    paint.color = const Color(0xFF66BB6A);
    canvas.drawCircle(Offset(leafy1X, leafy1Y), 7 * scale, paint);

    // Tomato - Front right (red/orange accent)
    paint.color = const Color(0xFFE53935); // Red tomato
    canvas.drawCircle(
      Offset(centerX + 15 * scale, cartTop + 20 * scale),
      9 * scale,
      paint,
    );
    // Tomato highlight
    paint.color = const Color(0xFFEF5350).withOpacity(0.6);
    canvas.drawCircle(
      Offset(centerX + 12 * scale, cartTop + 17 * scale),
      4 * scale,
      paint,
    );
    // Tomato stem
    paint.color = primaryGreen;
    canvas.drawCircle(
      Offset(centerX + 15 * scale, cartTop + 12 * scale),
      2.5 * scale,
      paint,
    );

    // Carrot - Left side
    paint.color = const Color(0xFFFF9800); // Orange
    final carrotPath = Path();
    final carrotX = centerX - 15 * scale;
    final carrotY = cartTop + 25 * scale;
    
    // Carrot body (elongated triangle)
    carrotPath.moveTo(carrotX, carrotY - 12 * scale);
    carrotPath.lineTo(carrotX - 3 * scale, carrotY + 8 * scale);
    carrotPath.lineTo(carrotX + 3 * scale, carrotY + 8 * scale);
    carrotPath.close();
    canvas.drawPath(carrotPath, paint);
    
    // Carrot leaves
    paint.color = primaryGreen;
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(carrotX + (i - 1) * 3 * scale, carrotY - 14 * scale),
        2 * scale,
        paint,
      );
    }

    // Broccoli - Center back
    paint.color = primaryGreen;
    final broccoliX = centerX;
    final broccoliY = cartTop + 8 * scale;
    
    // Broccoli florets (cluster of circles)
    canvas.drawCircle(Offset(broccoliX, broccoliY), 7 * scale, paint);
    
    paint.color = accentGreen;
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * math.pi / 180;
      canvas.drawCircle(
        Offset(
          broccoliX + math.cos(angle) * 5 * scale,
          broccoliY + math.sin(angle) * 5 * scale,
        ),
        4 * scale,
        paint,
      );
    }
    
    // Broccoli stem
    paint.color = const Color(0xFF558B2F);
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(broccoliX, broccoliY + 8 * scale),
        width: 4 * scale,
        height: 8 * scale,
      ),
      Radius.circular(2 * scale),
    );
    canvas.drawRRect(stemRect, paint);

    // Small leafy accent - Right back
    paint.color = const Color(0xFF66BB6A);
    canvas.drawCircle(
      Offset(centerX + 18 * scale, cartTop + 8 * scale),
      6 * scale,
      paint,
    );

    // === CART WHEELS ===
    
    // Left wheel
    paint.color = darkGreen;
    canvas.drawCircle(
      Offset(cartLeft + 15 * scale, cartBottom + 8 * scale),
      5 * scale,
      paint,
    );
    // Wheel hub
    paint.color = primaryGreen;
    canvas.drawCircle(
      Offset(cartLeft + 15 * scale, cartBottom + 8 * scale),
      2.5 * scale,
      paint,
    );

    // Right wheel
    paint.color = darkGreen;
    canvas.drawCircle(
      Offset(cartRight - 15 * scale, cartBottom + 8 * scale),
      5 * scale,
      paint,
    );
    // Wheel hub
    paint.color = primaryGreen;
    canvas.drawCircle(
      Offset(cartRight - 15 * scale, cartBottom + 8 * scale),
      2.5 * scale,
      paint,
    );

    // === DECORATIVE ELEMENTS ===
    
    // Small fresh produce accent dots around the design
    paint.color = accentGreen.withOpacity(0.3);
    canvas.drawCircle(Offset(centerX - 55 * scale, centerY - 15 * scale), 3 * scale, paint);
    canvas.drawCircle(Offset(centerX + 55 * scale, centerY - 10 * scale), 3 * scale, paint);
    canvas.drawCircle(Offset(centerX - 50 * scale, centerY + 20 * scale), 3 * scale, paint);
    
    paint.color = const Color(0xFFE53935).withOpacity(0.3);
    canvas.drawCircle(Offset(centerX + 52 * scale, centerY + 15 * scale), 3 * scale, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Widget that displays the AgriCart logo
class AgriCartLogoWidget extends StatelessWidget {
  final double size;
  final Color? backgroundColor;
  final Color? primaryGreen;
  final Color? darkGreen;
  final Color? accentGreen;

  const AgriCartLogoWidget({
    super.key,
    this.size = 200,
    this.backgroundColor,
    this.primaryGreen,
    this.darkGreen,
    this.accentGreen,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: AgriCartLogoPainter(
        backgroundColor: backgroundColor ?? const Color(0xFFF5F2E8),
        primaryGreen: primaryGreen ?? const Color(0xFF2E7D32),
        darkGreen: darkGreen ?? const Color(0xFF1B5E20),
        accentGreen: accentGreen ?? const Color(0xFF4CAF50),
      ),
    );
  }
}

