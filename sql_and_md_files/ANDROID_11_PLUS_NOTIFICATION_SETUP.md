# Android 11+ Notification Setup - Complete Guide

## Overview
This document explains how the FCM notification system is optimized for **Android 11 (API 30) and above**, ensuring compatibility across all screen sizes and Android versions.

## Key Android 11+ Requirements

### 1. Notification Channels (Mandatory)
- **Channel ID**: `agricart_customer_channel`
- **Importance**: `High` (required for background notifications)
- **Created in**: `customer_app/lib/services/notification_service.dart`
- **Must match**: FCM message `android.notification.channelId`

### 2. FCM Message Structure
The FCM message is optimized with:

#### Android-Specific Settings:
```typescript
android: {
  priority: "high", // Required for high-priority messages (Android 11+)
  notification: {
    channelId: "agricart_customer_channel", // Must match app's channel
    sound: "default",
    visibility: "public", // Show on lock screen (all screen sizes)
    defaultSound: true, // Play sound
    defaultVibrateTimings: true, // Vibrate
    notificationCount: 1, // Badge count
    clickAction: "FLUTTER_NOTIFICATION_CLICK",
    tag: "agricart_notification", // Grouping (Android 11+)
    sticky: false,
  },
  ttl: "86400s", // 24 hours
  directBootOk: true, // Work after reboot (Android 11+)
}
```

#### Critical Fields:
- **`notification` field**: Required for FCM to auto-display when app is closed
- **`android.priority: "high"`**: Ensures notification is delivered immediately
- **`android.notification.channelId`**: Must match the channel created in the app
- **`android.notification.visibility: "public"`**: Shows on lock screen (all screen sizes)

### 3. App Configuration

#### Notification Channel (Flutter):
```dart
const androidChannel = AndroidNotificationChannel(
  'agricart_customer_channel',
  'AgriCart Customer Notifications',
  description: 'Notifications for order updates and important messages',
  importance: Importance.high, // Required for Android 11+
  playSound: true,
  enableVibration: true,
  showBadge: true,
  enableLights: true, // LED light support
  ledColor: const Color.fromARGB(255, 76, 175, 80), // Green
);
```

#### AndroidManifest.xml:
- ✅ `POST_NOTIFICATIONS` permission (Android 13+)
- ✅ Firebase Messaging Service configured
- ✅ Default notification channel ID set
- ✅ Notification icon and color configured

#### build.gradle:
- ✅ `minSdkVersion 30` (Android 11)
- ✅ `targetSdkVersion 36` (Latest)
- ✅ `compileSdk 36`

## Compatibility Matrix

| Android Version | API Level | Status | Notes |
|----------------|-----------|--------|-------|
| Android 11 | 30 | ✅ Supported | Notification channels mandatory |
| Android 12 | 31 | ✅ Supported | Enhanced notification display |
| Android 12L | 32 | ✅ Supported | Large screen optimizations |
| Android 13 | 33 | ✅ Supported | POST_NOTIFICATIONS permission |
| Android 14 | 34 | ✅ Supported | Latest features |
| Android 15+ | 35+ | ✅ Supported | Future-proof |

## Screen Size Compatibility

The notification system works on all screen sizes:
- ✅ **Small phones** (320dp - 480dp)
- ✅ **Normal phones** (480dp - 640dp)
- ✅ **Large phones** (640dp - 960dp)
- ✅ **Tablets** (960dp+)
- ✅ **Foldables** (All configurations)

**Key Settings:**
- `visibility: "public"` ensures notifications show on all screen sizes
- `defaultSound: true` and `defaultVibrateTimings: true` work on all devices
- Channel importance `high` ensures proper display across all sizes

## Testing Checklist

### Before Testing:
1. ✅ App has notification permissions granted
2. ✅ Battery optimization is disabled for the app
3. ✅ Notification channel is created (check app logs)
4. ✅ FCM token is saved to database

### Test Scenarios:

#### Scenario 1: App Closed (Force-Stopped)
1. Force stop the app completely
2. Send a notification from web dashboard
3. **Expected**: Notification appears in system tray with sound/vibration
4. **Check**: Notification shows on lock screen (if device is locked)

#### Scenario 2: App in Background
1. Minimize the app (don't force stop)
2. Send a notification
3. **Expected**: Notification appears in system tray
4. **Check**: Tapping notification opens the app

#### Scenario 3: App Open
1. Keep app open and visible
2. Send a notification
3. **Expected**: Notification appears in-app (not as system notification)
4. **Check**: No duplicate notifications

#### Scenario 4: Device Reboot
1. Reboot the device
2. Don't open the app
3. Send a notification
4. **Expected**: Notification appears (thanks to `directBootOk: true`)

## Troubleshooting

### Notifications Not Appearing When App is Closed

1. **Check Notification Permissions:**
   - Settings → Apps → AgriCart → Notifications
   - Ensure "AgriCart Customer Notifications" channel is enabled
   - Set importance to "High"

2. **Check Battery Optimization:**
   - Settings → Apps → AgriCart → Battery
   - Set to "Unrestricted" or "Not optimized"

3. **Check Do Not Disturb:**
   - Ensure DND is not blocking notifications
   - Check if app is in exception list

4. **Verify Channel Configuration:**
   - Check app logs for: `✅ Notification channel created: agricart_customer_channel`
   - Verify channel importance is `High`

5. **Check FCM Token:**
   - Verify token is saved in `customer_fcm_tokens` table
   - Check Edge Function logs for token retrieval

### Notifications Not Working on Specific Android Version

- **Android 11 (API 30)**: Ensure channel is created before app closes
- **Android 12 (API 31)**: Check notification permission status
- **Android 13+ (API 33+)**: Ensure `POST_NOTIFICATIONS` permission is granted

## Best Practices

1. **Always create notification channel on app startup** (before user can close app)
2. **Use high importance channel** for critical notifications
3. **Set `visibility: "public"`** for lock screen display
4. **Use `directBootOk: true`** for post-reboot notifications
5. **Set appropriate TTL** (24 hours) for offline delivery

## Summary

The notification system is fully optimized for:
- ✅ Android 11+ (API 30+)
- ✅ All screen sizes (phones, tablets, foldables)
- ✅ All device states (app closed, background, foreground)
- ✅ Post-reboot scenarios
- ✅ Offline delivery (24-hour TTL)

The FCM message structure follows FCM v1 API best practices and Android 11+ requirements to ensure reliable notification delivery across all devices.

