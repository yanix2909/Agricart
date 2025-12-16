# Android Notification Not Appearing - Troubleshooting Guide

## Issue
FCM messages are being accepted by Google (Edge Function logs show success), but notifications are **not appearing on the Android device** when the app is closed or force-stopped.

## Root Cause Analysis

### ✅ What's Working
- Edge Function is sending FCM messages successfully
- Google FCM servers are accepting the messages
- FCM token exists in database
- Notification channel is created in app

### ❌ What's Not Working
- Notifications are not appearing on the device

## Common Causes & Solutions

### 1. Battery Optimization (Most Common)
Android may be blocking notifications from force-stopped apps due to battery optimization.

**Solution:**
1. Settings → Apps → AgriCart → Battery
2. Set to **"Unrestricted"** or **"Not optimized"**
3. Test again

### 2. Notification Channel Settings
The notification channel might be disabled or set to low importance.

**Solution:**
1. Settings → Apps → AgriCart → Notifications
2. Find **"AgriCart Customer Notifications"** channel
3. Ensure it's **enabled**
4. Set importance to **"High"** or **"Urgent"**
5. Enable all options (Sound, Vibration, Pop on screen, etc.)

### 3. Do Not Disturb (DND)
DND might be blocking notifications.

**Solution:**
1. Settings → Notifications → Do Not Disturb
2. Add AgriCart to exception list
3. Or disable DND temporarily to test

### 4. App Not Opened After Installation
FCM requires the app to be opened at least once after installation/update.

**Solution:**
1. Open the app at least once
2. Ensure notification permission is granted
3. Test notification again

### 5. Google Play Services Issues
Google Play Services might be outdated or having issues.

**Solution:**
1. Settings → Apps → Google Play Services
2. Update to latest version
3. Clear cache if needed

### 6. Android Version-Specific Issues
Some Android versions have stricter notification policies.

**Solution:**
- Android 11+: Ensure notification permission is granted
- Android 12+: Check notification permission status
- Android 13+: Ensure POST_NOTIFICATIONS permission is granted

## Testing Steps

### Step 1: Verify Notification Channel
1. Open app
2. Check logs for: `✅ Notification channel created: agricart_customer_channel`
3. Go to: Settings → Apps → AgriCart → Notifications
4. Verify channel exists and is enabled

### Step 2: Check Battery Optimization
1. Settings → Apps → AgriCart → Battery
2. Set to "Unrestricted"
3. Reboot device (optional but recommended)

### Step 3: Test with App in Background
1. Open app
2. Minimize app (don't force stop)
3. Send notification from web dashboard
4. **Expected**: Notification appears ✅

### Step 4: Test with App Force-Stopped
1. Open app at least once
2. Force stop the app completely
3. Send notification from web dashboard
4. **Expected**: Notification appears ✅ (if battery optimization is disabled)

### Step 5: Check Edge Function Logs
1. Check Supabase Edge Function logs
2. Look for: `✅ FCM notification sent successfully`
3. Look for: `📱 FCM Message ID: projects/...`
4. If these appear, FCM message was sent successfully

## Device-Specific Checks

### Samsung Devices
- Check "App power management" settings
- Disable "Put unused apps to sleep"
- Add app to "Never sleeping apps" list

### Xiaomi/Redmi Devices
- Check "Battery saver" settings
- Disable "Restrict background activity"
- Add app to "Autostart" list

### OnePlus Devices
- Check "Battery optimization" settings
- Disable "Smart power saving"
- Add app to "Don't optimize" list

### Huawei Devices
- Check "Battery optimization" settings
- Disable "App launch" restrictions
- Add app to "Protected apps" list

## FCM Message Verification

The FCM message structure is correct and includes:
- ✅ `notification` field (title + body) - Triggers automatic display
- ✅ `android.priority: "high"` - High priority delivery
- ✅ `android.notification.channelId` - Matches app's channel
- ✅ `android.notification.visibility: "public"` - Shows on lock screen
- ✅ `android.directBootOk: true` - Works after reboot

## Debug Commands

### Check Notification Channel (via ADB)
```bash
adb shell dumpsys notification | grep -A 10 "agricart_customer_channel"
```

### Check App Notification Settings (via ADB)
```bash
adb shell cmd notification list_channels com.agricart.customer
```

### Check FCM Token (via ADB)
```bash
adb logcat | grep -i "fcm\|firebase\|notification"
```

## Expected Behavior

### When App is Open
- Notification appears in-app (via Realtime Database listener)
- No system notification (to prevent duplicates)

### When App is Closed (Background)
- System notification appears ✅
- Sound and vibration play ✅
- Notification shows in system tray ✅

### When App is Force-Stopped
- System notification appears ✅ (if battery optimization is disabled)
- Sound and vibration play ✅
- Notification shows in system tray ✅

## If Still Not Working

1. **Uninstall and reinstall the app**
   - This resets all notification settings
   - Ensures clean channel creation

2. **Check device logs**
   - Use `adb logcat` to see Android system logs
   - Look for FCM-related errors

3. **Test with another device**
   - Rule out device-specific issues
   - Test on different Android versions

4. **Verify FCM token is valid**
   - Check if token in database matches device token
   - Regenerate token if needed

5. **Check Google Play Services**
   - Update to latest version
   - Clear cache and data

## Summary

The FCM message structure is correct. If notifications aren't appearing, it's likely due to:
1. **Battery optimization** blocking notifications (most common)
2. **Notification channel** disabled or set to low importance
3. **Do Not Disturb** blocking notifications
4. **Device-specific** power management settings

**Most common fix**: Disable battery optimization for the app.

