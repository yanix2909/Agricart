import 'package:flutter/material.dart';

/// Responsive utility class for handling different device types and screen sizes
class Responsive {
  /// Breakpoints for different device types
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Get device type based on screen width
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return DeviceType.mobile;
    } else if (width < tabletBreakpoint) {
      return DeviceType.tablet;
    } else {
      return DeviceType.desktop;
    }
  }

  /// Check if device is mobile (phone)
  static bool isMobile(BuildContext context) {
    return getDeviceType(context) == DeviceType.mobile;
  }

  /// Check if device is tablet (including iPad)
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  /// Check if device is desktop
  static bool isDesktop(BuildContext context) {
    return getDeviceType(context) == DeviceType.desktop;
  }

  /// Check if device is tablet or larger
  static bool isTabletOrLarger(BuildContext context) {
    return isTablet(context) || isDesktop(context);
  }

  /// Get responsive padding based on device type
  static EdgeInsets getPadding(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return const EdgeInsets.all(16);
      case DeviceType.tablet:
        return const EdgeInsets.all(24);
      case DeviceType.desktop:
        return const EdgeInsets.all(32);
    }
  }

  /// Get responsive horizontal padding
  static EdgeInsets getHorizontalPadding(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return const EdgeInsets.symmetric(horizontal: 16);
      case DeviceType.tablet:
        return const EdgeInsets.symmetric(horizontal: 24);
      case DeviceType.desktop:
        return const EdgeInsets.symmetric(horizontal: 32);
    }
  }

  /// Get responsive vertical padding
  static EdgeInsets getVerticalPadding(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return const EdgeInsets.symmetric(vertical: 16);
      case DeviceType.tablet:
        return const EdgeInsets.symmetric(vertical: 24);
      case DeviceType.desktop:
        return const EdgeInsets.symmetric(vertical: 32);
    }
  }

  /// Get responsive spacing between elements
  static double getSpacing(BuildContext context, {double mobile = 16, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.5;
      case DeviceType.desktop:
        return desktop ?? mobile * 2;
    }
  }

  /// Get responsive font size
  static double getFontSize(BuildContext context, {required double mobile, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.2;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.4;
    }
  }

  /// Get responsive grid cross axis count for products
  static int getProductGridColumns(BuildContext context) {
    final deviceType = getDeviceType(context);
    final width = MediaQuery.of(context).size.width;
    
    switch (deviceType) {
      case DeviceType.mobile:
        return 2; // 2 columns on phones
      case DeviceType.tablet:
        // 3 columns on tablets, 4 on larger tablets
        return width > 800 ? 4 : 3;
      case DeviceType.desktop:
        // 5-6 columns on desktop
        return width > 1400 ? 6 : 5;
    }
  }

  /// Get responsive grid cross axis count for general use
  static int getGridColumns(BuildContext context, {int mobile = 1, int? tablet, int? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? (mobile + 1);
      case DeviceType.desktop:
        return desktop ?? (tablet ?? mobile + 2);
    }
  }

  /// Get responsive child aspect ratio for product grids
  static double getProductAspectRatio(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return 0.68; // Slightly taller to accommodate content
      case DeviceType.tablet:
        return 0.72;
      case DeviceType.desktop:
        return 0.75; // Wider cards on desktop
    }
  }

  /// Get responsive card width
  static double? getCardWidth(BuildContext context, {double? mobile, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.desktop:
        return desktop;
    }
  }

  /// Get responsive icon size
  static double getIconSize(BuildContext context, {double mobile = 24, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.2;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.4;
    }
  }

  /// Get responsive button height
  static double getButtonHeight(BuildContext context, {double mobile = 48, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.1;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.2;
    }
  }

  /// Get responsive border radius
  static double getBorderRadius(BuildContext context, {double mobile = 12, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.2;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.4;
    }
  }

  /// Get responsive max width for content (prevents content from being too wide on large screens)
  static double? getMaxContentWidth(BuildContext context, {double? mobile, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? 800;
      case DeviceType.desktop:
        return desktop ?? 1200;
    }
  }

  /// Get responsive hero section height
  static double getHeroHeight(BuildContext context, {double mobile = 220, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.3;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.5;
    }
  }

  /// Get responsive horizontal product card width (for horizontal scrolling lists)
  static double getHorizontalCardWidth(BuildContext context, {double mobile = 160, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.3;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.5;
    }
  }

  /// Get responsive horizontal product card height
  static double getHorizontalCardHeight(BuildContext context, {double mobile = 200, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.2;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.4;
    }
  }

  /// Get responsive app bar height
  static double getAppBarHeight(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return kToolbarHeight;
      case DeviceType.tablet:
        return kToolbarHeight * 1.1;
      case DeviceType.desktop:
        return kToolbarHeight * 1.2;
    }
  }

  /// Get responsive bottom navigation bar height
  static double getBottomNavHeight(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return kBottomNavigationBarHeight;
      case DeviceType.tablet:
        return kBottomNavigationBarHeight * 1.1;
      case DeviceType.desktop:
        return kBottomNavigationBarHeight * 1.2;
    }
  }

  /// Get responsive text scale factor (prevents text from being too large on tablets)
  static double getTextScaleFactor(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return 1.0;
      case DeviceType.tablet:
        return 1.0; // Keep same scale on tablets
      case DeviceType.desktop:
        return 1.0; // Keep same scale on desktop
    }
  }

  /// Get responsive image size
  static double getImageSize(BuildContext context, {required double mobile, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.3;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.6;
    }
  }

  /// Get responsive dialog width
  static double? getDialogWidth(BuildContext context) {
    final deviceType = getDeviceType(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    switch (deviceType) {
      case DeviceType.mobile:
        return screenWidth * 0.9; // 90% of screen width
      case DeviceType.tablet:
        return screenWidth * 0.6; // 60% of screen width
      case DeviceType.desktop:
        return 500; // Fixed width on desktop
    }
  }

  /// Get responsive list item height
  static double getListItemHeight(BuildContext context, {double mobile = 80, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.2;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.4;
    }
  }

  /// Get responsive width value
  static double getWidth(BuildContext context, {required double mobile, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.3;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.6;
    }
  }

  /// Get responsive height value
  static double getHeight(BuildContext context, {required double mobile, double? tablet, double? desktop}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile * 1.2;
      case DeviceType.desktop:
        return desktop ?? mobile * 1.4;
    }
  }

  /// Get screen width
  static double getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Get screen height
  static double getScreenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// Get responsive value as percentage of screen width
  static double getWidthPercentage(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.width * (percentage / 100);
  }

  /// Get responsive value as percentage of screen height
  static double getHeightPercentage(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.height * (percentage / 100);
  }

  /// Get constrained width (useful for centering content on large screens)
  static double getConstrainedWidth(BuildContext context, {double maxWidth = 600}) {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth > maxWidth ? maxWidth : screenWidth;
  }
}

/// Device type enumeration
enum DeviceType {
  mobile,
  tablet,
  desktop,
}

