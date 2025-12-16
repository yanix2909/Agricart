import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Generate AgriCart Rider logo matching EXACT SVG design
/// Run: dart run scripts/generate_logo.dart

void main() async {
  print('🚚 Generating AgriCart Rider Logo (EXACT SVG Design)...\n');
  
  const size = 1024;
  const designScale = 0.75; // Scale down to 75% to add padding for Android adaptive icons
  const scale = (size / 120.0) * designScale;
  
  // Create image with transparent background
  final image = img.Image(width: size, height: size, numChannels: 4);
  
  // Fill with transparent pixels
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  
  final centerX = size ~/ 2;
  final centerY = size ~/ 2;
  
  // Colors from SVG
  const darkGreen = [26, 77, 46]; // #1a4d2e
  const creamLight = [255, 248, 231]; // #FFF8E7
  const creamVeryLight = [255, 251, 240]; // #FFFBF0
  
  // Calculate offset to center the scaled design
  final svgCenter = 60.0 * scale;
  final canvasCenter = size / 2;
  final offset = canvasCenter - svgCenter;
  
  // Helper functions - scale and center the design
  int scaleX(double x) => ((x * scale) + offset).round();
  int scaleY(double y) => ((y * scale) + offset).round();
  int scaleR(double r) => (r * scale).round();
  
  bool isInsideCircle(int x, int y, int cx, int cy, int radius) {
    final dx = x - cx;
    final dy = y - cy;
    return (dx * dx + dy * dy) <= (radius * radius);
  }
  
  void drawCircle(int cx, int cy, int radius, List<int> rgb, {int alpha = 255}) {
    for (int y = cy - radius; y <= cy + radius; y++) {
      for (int x = cx - radius; x <= cx + radius; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          if (isInsideCircle(x, y, cx, cy, radius)) {
            image.setPixelRgba(x, y, rgb[0], rgb[1], rgb[2], alpha);
          }
        }
      }
    }
  }
  
  void drawEllipse(int cx, int cy, int rx, int ry, List<int> rgb, {int alpha = 255}) {
    for (int y = cy - ry; y <= cy + ry; y++) {
      for (int x = cx - rx; x <= cx + rx; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          final dx = (x - cx).toDouble();
          final dy = (y - cy).toDouble();
          if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0) {
            image.setPixelRgba(x, y, rgb[0], rgb[1], rgb[2], alpha);
          }
        }
      }
    }
  }
  
  void drawRect(int x, int y, int w, int h, List<int> rgb, {int alpha = 255}) {
    for (int py = y; py < y + h; py++) {
      for (int px = x; px < x + w; px++) {
        if (px >= 0 && px < size && py >= 0 && py < size) {
          image.setPixelRgba(px, py, rgb[0], rgb[1], rgb[2], alpha);
        }
      }
    }
  }
  
  void drawPolygon(List<List<int>> points, List<int> rgb, {int alpha = 255}) {
    int minX = points[0][0], maxX = points[0][0];
    int minY = points[0][1], maxY = points[0][1];
    for (var point in points) {
      if (point[0] < minX) minX = point[0];
      if (point[0] > maxX) maxX = point[0];
      if (point[1] < minY) minY = point[1];
      if (point[1] > maxY) maxY = point[1];
    }
    
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        if (x >= 0 && x < size && y >= 0 && y < size) {
          bool inside = false;
          for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
            if (((points[i][1] > y) != (points[j][1] > y)) &&
                (x < (points[j][0] - points[i][0]) * (y - points[i][1]) / 
                     (points[j][1] - points[i][1]) + points[i][0])) {
              inside = !inside;
            }
          }
          if (inside) {
            image.setPixelRgba(x, y, rgb[0], rgb[1], rgb[2], alpha);
          }
        }
      }
    }
  }
  
  void drawLine(int x1, int y1, int x2, int y2, List<int> rgb, {int alpha = 255, int thickness = 1}) {
    final dx = (x2 - x1).abs();
    final dy = (y2 - y1).abs();
    final sx = x1 < x2 ? 1 : -1;
    final sy = y1 < y2 ? 1 : -1;
    var err = dx - dy;
    var x = x1;
    var y = y1;
    
    while (true) {
      for (int ty = -thickness ~/ 2; ty <= thickness ~/ 2; ty++) {
        for (int tx = -thickness ~/ 2; tx <= thickness ~/ 2; tx++) {
          final px = x + tx;
          final py = y + ty;
          if (px >= 0 && px < size && py >= 0 && py < size) {
            image.setPixelRgba(px, py, rgb[0], rgb[1], rgb[2], alpha);
          }
        }
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
  
  // Helper to draw bezier curve path (approximate with many line segments)
  void drawBezierPath(List<dynamic> pathData, List<int> rgb, {int alpha = 255}) {
    List<List<double>> points = [];
    
    // Parse path and generate points along the curve
    for (int i = 0; i < pathData.length; i++) {
      if (pathData[i] == 'M') {
        points.add([pathData[i+1], pathData[i+2]]);
      } else if (pathData[i] == 'Q') {
        // Quadratic bezier: Q controlX controlY endX endY
        final startX = points.last[0];
        final startY = points.last[1];
        final controlX = pathData[i+1];
        final controlY = pathData[i+2];
        final endX = pathData[i+3];
        final endY = pathData[i+4];
        
        // Generate 50 points along the curve
        for (double t = 0; t <= 1; t += 0.02) {
          final x = (1-t)*(1-t)*startX + 2*(1-t)*t*controlX + t*t*endX;
          final y = (1-t)*(1-t)*startY + 2*(1-t)*t*controlY + t*t*endY;
          points.add([x, y]);
        }
      }
    }
    
    // Fill the polygon
    final scaledPoints = points.map((p) => [scaleX(p[0]), scaleY(p[1])]).toList();
    drawPolygon(scaledPoints, rgb, alpha: alpha);
  }
  
  // 1. Dark green background circle - exact from SVG: cx="60" cy="60" r="58"
  drawCircle(scaleX(60), scaleY(60), scaleR(58), darkGreen);
  
  // 2. Truck cabin - exact from SVG path
  drawPolygon([
    [scaleX(25), scaleY(50)],
    [scaleX(25), scaleY(65)],
    [scaleX(30), scaleY(65)],
    [scaleX(30), scaleY(70)],
    [scaleX(45), scaleY(70)],
    [scaleX(45), scaleY(50)],
  ], creamLight);
  
  // 3. Truck window - rect x="28" y="53" width="14" height="10"
  drawRect(scaleX(28), scaleY(53), scaleX(14).round(), scaleY(10).round(), darkGreen, alpha: 76);
  
  // 4. Truck cargo area
  drawPolygon([
    [scaleX(45), scaleY(45)],
    [scaleX(45), scaleY(70)],
    [scaleX(80), scaleY(70)],
    [scaleX(80), scaleY(50)],
  ], creamLight);
  
  // 5. Cargo door lines
  drawLine(scaleX(60), scaleY(48), scaleX(60), scaleY(70), darkGreen, alpha: 76, thickness: scaleR(2));
  drawLine(scaleX(70), scaleY(50), scaleX(70), scaleY(70), darkGreen, alpha: 76, thickness: scaleR(2));
  
  // 6. Truck wheels - exact from SVG
  drawCircle(scaleX(35), scaleY(75), scaleR(6), creamVeryLight);
  drawCircle(scaleX(35), scaleY(75), scaleR(3), darkGreen, alpha: 127);
  drawCircle(scaleX(70), scaleY(75), scaleR(6), creamVeryLight);
  drawCircle(scaleX(70), scaleY(75), scaleR(3), darkGreen, alpha: 127);
  
  // 7. Large leaf left - using bezier curve: M 50 40 Q 42 30 45 18 Q 52 22 56 30 Q 58 36 55 42 Z
  drawBezierPath([
    'M', 50.0, 40.0,
    'Q', 42.0, 30.0, 45.0, 18.0,
    'Q', 52.0, 22.0, 56.0, 30.0,
    'Q', 58.0, 36.0, 55.0, 42.0,
  ], creamLight);
  drawLine(scaleX(48), scaleY(22), scaleX(54), scaleY(38), darkGreen, thickness: scaleR(2));
  
  // 8. Large leaf right - using bezier: M 68 42 Q 76 32 73 20 Q 66 24 62 32 Q 60 38 63 44 Z
  drawBezierPath([
    'M', 68.0, 42.0,
    'Q', 76.0, 32.0, 73.0, 20.0,
    'Q', 66.0, 24.0, 62.0, 32.0,
    'Q', 60.0, 38.0, 63.0, 44.0,
  ], creamLight);
  drawLine(scaleX(70), scaleY(24), scaleX(64), scaleY(40), darkGreen, thickness: scaleR(2));
  
  // 9. Center leaf - ellipse cx="59" cy="22" rx="5" ry="10"
  drawEllipse(scaleX(59), scaleY(22), scaleR(5), scaleR(10), creamVeryLight, alpha: 242);
  drawLine(scaleX(59), scaleY(15), scaleX(59), scaleY(28), darkGreen, thickness: scaleR(1.5).round());
  
  // 10. Speed lines - exact from SVG
  drawLine(scaleX(15), scaleY(55), scaleX(20), scaleY(55), creamLight, alpha: 127, thickness: scaleR(2.5).round());
  drawLine(scaleX(10), scaleY(62), scaleX(17), scaleY(62), creamLight, alpha: 102, thickness: scaleR(2.5).round());
  drawLine(scaleX(13), scaleY(69), scaleX(20), scaleY(69), creamLight, alpha: 76, thickness: scaleR(2.5).round());
  
  // 11. Small decorative leaves - ellipse cx="52" cy="12" and cx="66" cy="14"
  drawEllipse(scaleX(52), scaleY(12), scaleR(2.5), scaleR(4), creamVeryLight, alpha: 204);
  drawEllipse(scaleX(66), scaleY(14), scaleR(2.5), scaleR(4), creamVeryLight, alpha: 204);
  
  // Save PNG with alpha channel
  final pngBytes = img.encodePng(image);
  final file = File('assets/images/delivery_logo.png');
  await file.writeAsBytes(pngBytes);
  
  print('✅ Delivery logo generated successfully!');
  print('📁 Saved to: assets/images/delivery_logo.png');
  print('📏 Size: ${size}x$size pixels');
  print('🚚 Design: EXACT match to SVG specification');
  print('🥬 Leaves: Smooth bezier curves');
  print('');
  print('Next steps:');
  print('1. Run: flutter pub run flutter_launcher_icons');
  print('2. Run: flutter clean');
  print('3. Run: flutter build apk\n');
}
