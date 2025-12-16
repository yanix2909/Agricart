# Custom AgriCart Logo Generator 🎨

This is a **programmatically generated logo** using Flutter's `CustomPaint` widget - no external image files needed!

## 🎯 What's Included

### Logo Design Features
- **Modern green vegetable cart** with fresh produce
- **Cream background** (#F5F2E8) for a warm, inviting feel
- **Vegetables included:**
  - 🥦 Broccoli (center)
  - 🥬 Leafy greens (lettuce/cabbage)
  - 🍅 Red tomato with highlights
  - 🥕 Orange carrot with green leaves
  - 🫑 Green bell pepper
- **Shopping cart** with modern minimalist design
- **Wheels** for the cart
- **Decorative accents** for visual interest

### Files Created
1. **`lib/widgets/agricart_logo_painter.dart`** - The CustomPainter widget that draws the logo
2. **`lib/screens/logo_preview_screen.dart`** - Preview screen with export functionality
3. **`lib/logo_demo_main.dart`** - Standalone demo app launcher

## 🚀 How to Use the Logo

### Option 1: Run the Logo Preview App (Recommended)

#### Method A: Using the demo launcher
```bash
cd customer_app
flutter run -t lib/logo_demo_main.dart
```

#### Method B: Temporarily modify main.dart
1. Open `lib/main.dart`
2. Temporarily replace line 72 `runApp(const MyApp());` with:
   ```dart
   runApp(const LogoDemoApp());
   ```
3. Add this import at the top:
   ```dart
   import 'logo_demo_main.dart';
   ```
4. Run the app: `flutter run`
5. **Remember to revert main.dart after exporting!**

### Option 2: Export Logo Programmatically

Once in the logo preview screen:
1. **View the logo** in different sizes
2. **Tap export buttons** to save as PNG:
   - 512x512 (Recommended for app icons)
   - 1024x1024 (High quality)
   - 192x192 (Android XXXHDPI)
3. Logo will be saved to your device gallery
4. Transfer the image to your computer
5. Replace `assets/images/agricart_logo.png` with the new image
6. Run: `flutter pub run flutter_launcher_icons`
7. Rebuild the app

### Option 3: Use as a Widget in Your App

You can use the logo anywhere in your app:

```dart
import 'package:agricart_customer/widgets/agricart_logo_painter.dart';

// Default colors (cream background, green cart)
AgriCartLogoWidget(size: 200)

// Custom colors
AgriCartLogoWidget(
  size: 150,
  backgroundColor: Colors.white,
  primaryGreen: Color(0xFF1B5E20),
  darkGreen: Color(0xFF0D3F14),
  accentGreen: Color(0xFF4CAF50),
)
```

## 🎨 Color Palette Used

- **Background:** `#F5F2E8` (Cream)
- **Primary Green:** `#2E7D32` (Modern green - cart outline)
- **Dark Green:** `#1B5E20` (Wheels)
- **Accent Green:** `#4CAF50` (Vegetables)
- **Additional Colors:**
  - Tomato red: `#E53935`
  - Carrot orange: `#FF9800`
  - Leafy green: `#66BB6A`

## 📱 Customization

### Modify the Logo Design

Edit `lib/widgets/agricart_logo_painter.dart` to customize:

1. **Change colors:**
   ```dart
   AgriCartLogoPainter(
     backgroundColor: Color(0xFFFFFFFF), // White background
     primaryGreen: Color(0xFF006400),     // Darker green
     // ... etc
   )
   ```

2. **Adjust vegetables:** Modify the paint coordinates in the `paint()` method

3. **Change cart style:** Modify the `cartPath` drawing code

4. **Add/remove elements:** Add new drawing code in the `paint()` method

### Export Custom Sizes

In `logo_preview_screen.dart`, modify the export button calls:

```dart
_buildExportButton('2048x2048 (Extra Large)', 2048),
```

## 🔄 Update App Icon with New Logo

After exporting your logo:

1. **Save the exported PNG** from device gallery to computer
2. **Replace the logo file:**
   ```bash
   # Copy your exported PNG to:
   customer_app/assets/images/agricart_logo.png
   ```
3. **Regenerate app icons:**
   ```bash
   cd customer_app
   flutter pub run flutter_launcher_icons
   ```
4. **Clean and rebuild:**
   ```bash
   flutter clean
   flutter build apk --debug
   # or
   flutter run
   ```

## ✨ Features of Custom Paint Approach

### Advantages:
- ✅ **No external dependencies** on image files
- ✅ **Infinitely scalable** (vector-based)
- ✅ **Easy to modify** colors and design
- ✅ **Lightweight** (no large image files)
- ✅ **Consistent across all sizes**
- ✅ **Can be animated** if needed
- ✅ **Export any size** without quality loss

### Use Cases:
- App icons
- Splash screens
- Loading animations
- Branding elements
- In-app decorative elements

## 🎯 Design Philosophy

The logo represents:
- 🛒 **Shopping cart** = E-commerce/marketplace
- 🥬 **Fresh vegetables** = Agricultural products
- 🌱 **Green colors** = Organic, fresh, natural
- 🎨 **Modern design** = Contemporary mobile app
- ☁️ **Cream background** = Warm, inviting, friendly

## 📝 Notes

- The logo is responsive and scales perfectly to any size
- All shapes are drawn programmatically using Canvas API
- Colors can be customized per instance
- Export requires gallery permission on device
- The logo looks best at sizes 192px and above
- For app icons, 512x512 or 1024x1024 is recommended

## 🐛 Troubleshooting

**Gallery permission denied:**
- Go to device Settings > Apps > AgriCart Customer > Permissions
- Enable "Photos and Media" or "Storage" permission

**Export not working:**
- Make sure `gal` package is installed (already in pubspec.yaml)
- Check device storage space
- Try exporting a smaller size first

**Logo looks blurry:**
- Export at higher resolution (1024x1024)
- Ensure you're not scaling up from small sizes
- Use vector-based approach by keeping as CustomPaint widget

## 💡 Tips

1. **Preview first** - Always preview the logo before exporting
2. **Export high quality** - Use 1024x1024 for best results
3. **Keep original** - Save the old agricart_logo.png as backup
4. **Test on device** - View the actual app icon on a real device
5. **Iterate quickly** - Modify colors/design and re-export easily

---

**Created by:** CustomPaint Flutter Widget  
**Type:** Vector-based programmatic logo  
**Format:** Dart/Flutter code → Export to PNG  
**License:** Part of AgriCart Customer App  

