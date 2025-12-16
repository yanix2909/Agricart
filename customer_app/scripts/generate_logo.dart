import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Standalone script to generate AgriCart logo PNG with TRANSPARENT background
/// Run: dart run scripts/generate_logo.dart

void main() async {
  print('🎨 Generating AgriCart Logo (Transparent Background)...\n');
  
  const size = 1024;
  const scale = size / 120.0;
  
  // Create image with 4 channels (RGBA) for transparency
  final image = img.Image(width: size, height: size, numChannels: 4);
  
  // Fill ENTIRE image with fully transparent pixels
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 0, 0, 0, 0); // Fully transparent
    }
  }
  
  final centerX = size ~/ 2;
  final centerY = size ~/ 2;
  
  // Helper function to scale coordinates
  int scaleX(double x) => (x * scale).round();
  int scaleY(double y) => (y * scale).round();
  int scaleR(double r) => (r * scale).round();
  
  // Helper to check if point is inside circle
  bool isInsideCircle(int x, int y, int cx, int cy, int radius) {
    final dx = x - cx;
    final dy = y - cy;
    return (dx * dx + dy * dy) <= (radius * radius);
  }
  
  // 1. Draw main circular badge (dark green) - ONLY inside the circle
  final badgeRadius = scaleR(56);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      if (isInsideCircle(x, y, centerX, centerY, badgeRadius)) {
        image.setPixelRgba(x, y, 26, 77, 46, 255); // #1a4d2e
      }
    }
  }
  
  // Helper to draw filled circle with specific color
  void drawCircle(int cx, int cy, int radius, int r, int g, int b, {int alpha = 255}) {
    for (int y = cy - radius; y <= cy + radius; y++) {
      for (int x = cx - radius; x <= cx + radius; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          if (isInsideCircle(x, y, cx, cy, radius)) {
            image.setPixelRgba(x, y, r, g, b, alpha);
          }
        }
      }
    }
  }
  
  // Helper to draw filled ellipse
  void drawEllipse(int cx, int cy, int rx, int ry, int r, int g, int b, {int alpha = 255}) {
    for (int y = cy - ry; y <= cy + ry; y++) {
      for (int x = cx - rx; x <= cx + rx; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          final dx = (x - cx).toDouble();
          final dy = (y - cy).toDouble();
          if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0) {
            image.setPixelRgba(x, y, r, g, b, alpha);
          }
        }
      }
    }
  }
  
  // Helper to draw filled polygon
  void drawPolygon(List<List<int>> points, int r, int g, int b, {int alpha = 255}) {
    // Find bounding box
    int minX = points[0][0], maxX = points[0][0];
    int minY = points[0][1], maxY = points[0][1];
    for (var point in points) {
      if (point[0] < minX) minX = point[0];
      if (point[0] > maxX) maxX = point[0];
      if (point[1] < minY) minY = point[1];
      if (point[1] > maxY) maxY = point[1];
    }
    
    // Fill polygon using point-in-polygon test
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          // Ray casting algorithm
          bool inside = false;
          for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
            if (((points[i][1] > y) != (points[j][1] > y)) &&
                (x < (points[j][0] - points[i][0]) * (y - points[i][1]) / 
                     (points[j][1] - points[i][1]) + points[i][0])) {
              inside = !inside;
            }
          }
          if (inside) {
            image.setPixelRgba(x, y, r, g, b, alpha);
          }
        }
      }
    }
  }
  
  // Helper to draw line
  void drawLine(int x1, int y1, int x2, int y2, int r, int g, int b, {int alpha = 255}) {
    final dx = (x2 - x1).abs();
    final dy = (y2 - y1).abs();
    final sx = x1 < x2 ? 1 : -1;
    final sy = y1 < y2 ? 1 : -1;
    var err = dx - dy;
    var x = x1;
    var y = y1;
    
    while (true) {
      if (x >= 0 && x < size && y >= 0 && y < size) {
        image.setPixelRgba(x, y, r, g, b, alpha);
      }
      
      if (x == x2 && y == y2) break;
      
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x += sx;
      }
      if (e2 < dx) {
        err += dx;
        y += sy;
      }
    }
  }
  
  // 2. Draw shopping cart base (white trapezoid)
  drawPolygon([
    [scaleX(35), scaleY(45)],
    [scaleX(81), scaleY(45)],
    [scaleX(78), scaleY(65)],
    [scaleX(78), scaleY(68)],
    [scaleX(41), scaleY(68)],
    [scaleX(38), scaleY(65)],
  ], 255, 255, 255, alpha: 242); // opacity 0.95
  
  // 3. Cart handle/rim (thick white line)
  for (int offset = 0; offset < 3; offset++) {
    drawLine(
      scaleX(35), scaleY(45 + offset * 0.3), 
      scaleX(81), scaleY(45 + offset * 0.3),
      255, 255, 255
    );
  }
  
  // 4. Cart wheels
  drawCircle(scaleX(45), scaleY(75), scaleR(4), 255, 255, 255);
  drawCircle(scaleX(71), scaleY(75), scaleR(4), 255, 255, 255);
  
  // 5. Vegetables - Leaf 1 (left)
  drawEllipse(scaleX(48), scaleY(52), scaleR(6), scaleR(9), 26, 77, 46, alpha: 230); // opacity 0.9
  drawLine(scaleX(48), scaleY(48), scaleX(48), scaleY(56), 255, 255, 255, alpha: 178); // opacity 0.7
  
  // 6. Vegetables - Leaf 2 (center)
  drawEllipse(scaleX(58), scaleY(50), scaleR(7), scaleR(10), 26, 77, 46, alpha: 217); // opacity 0.85
  drawLine(scaleX(58), scaleY(45), scaleX(58), scaleY(55), 255, 255, 255, alpha: 178);
  
  // 7. Vegetables - Leaf 3 (right)
  drawEllipse(scaleX(68), scaleY(53), scaleR(6), scaleR(8), 26, 77, 46, alpha: 230);
  drawLine(scaleX(68), scaleY(49), scaleX(68), scaleY(57), 255, 255, 255, alpha: 178);
  
  // 8. Top leaves - Left leaf
  drawPolygon([
    [scaleX(52), scaleY(38)],
    [scaleX(48), scaleY(32)],
    [scaleX(52), scaleY(28)],
    [scaleX(54), scaleY(30)],
    [scaleX(54), scaleY(34)],
    [scaleX(53), scaleY(38)],
  ], 255, 255, 255, alpha: 242); // opacity 0.95
  
  // 9. Top leaves - Right leaf
  drawPolygon([
    [scaleX(64), scaleY(36)],
    [scaleX(60), scaleY(30)],
    [scaleX(64), scaleY(26)],
    [scaleX(66), scaleY(28)],
    [scaleX(66), scaleY(32)],
    [scaleX(65), scaleY(36)],
  ], 255, 255, 255, alpha: 230); // opacity 0.9
  
  // 10. Accent circle (subtle white ring) - draw inside the badge only
  final accentRadius = scaleR(53);
  for (double angle = 0; angle < 2 * math.pi; angle += 0.01) {
    final x = centerX + (accentRadius * math.cos(angle)).round();
    final y = centerY + (accentRadius * math.sin(angle)).round();
    if (x >= 0 && x < size && y >= 0 && y < size) {
      image.setPixelRgba(x, y, 255, 255, 255, 38); // opacity 0.15
    }
  }
  
  // Save as PNG with alpha channel
  final pngBytes = img.encodePng(image);
  final file = File('assets/images/agricart_logo.png');
  await file.writeAsBytes(pngBytes);
  
  print('✅ Logo generated successfully!');
  print('📁 Saved to: assets/images/agricart_logo.png');
  print('📏 Size: ${size}x$size pixels');
  print('🎨 Design: Transparent background - only circular logo visible');
  print('');
  print('Next steps:');
  print('1. Run: flutter pub run flutter_launcher_icons');
  print('2. Run: flutter clean');
  print('3. Run: flutter build apk\n');
}
