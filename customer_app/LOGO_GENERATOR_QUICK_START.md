# Quick Start: Generate Your AgriCart Logo 🚀

## ⚡ Fast Way to See and Export the Logo

### Step 1: Run the Logo Preview App
```bash
cd customer_app
flutter run -t lib/logo_demo_main.dart
```

### Step 2: View the Logo
You'll see:
- **Large preview** of the custom green vegetable cart logo
- **Multiple sizes** (small, medium, large)
- **Cream background** with modern green cart
- **Fresh vegetables** (broccoli, tomato, carrot, leafy greens)

### Step 3: Export as PNG
Tap any export button:
- **512x512** ← Best for app icons
- **1024x1024** ← Highest quality
- **192x192** ← Android XXXHDPI

Logo saves to your device gallery automatically!

### Step 4: Use the Logo
1. Transfer PNG from device to computer
2. Replace `customer_app/assets/images/agricart_logo.png`
3. Run: `flutter pub run flutter_launcher_icons`
4. Done! ✅

## 🎨 What the Logo Looks Like

```
     ╭─────────────────╮
     │   Cream Circle  │
     │                 │
     │    🥦 🍅 🥬     │  ← Fresh vegetables
     │   ┌─────────┐   │
     │   │  CART   │   │  ← Green shopping cart
     │   └─────────┘   │
     │     ●     ●     │  ← Wheels
     ╰─────────────────╯
```

**Colors:**
- Background: Cream (#F5F2E8)
- Cart: Modern Green (#2E7D32)
- Veggies: Various greens, red tomato, orange carrot

## 📱 Alternative: Run in Main App

If `flutter run -t` doesn't work, temporarily edit `main.dart`:

```dart
// In lib/main.dart, line 72, replace:
runApp(const MyApp());

// With:
runApp(const LogoDemoApp());  // Add: import 'logo_demo_main.dart';
```

Then run: `flutter run`

**Don't forget to change it back after exporting!**

## ❓ Need Help?

See full documentation: `CUSTOM_LOGO_GENERATOR_README.md`

## ✨ Features

✅ Programmatically drawn (no image files needed)  
✅ Scalable to any size (vector-based)  
✅ Easy to customize colors  
✅ Export to PNG for app icons  
✅ Modern, professional design  
✅ Perfect for agricultural/marketplace apps  

---

**Time to generate:** < 1 minute  
**Result:** Professional custom logo for your app icon!

