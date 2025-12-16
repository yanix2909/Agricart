# Quick Fix: Notifications Not Appearing on Android

## Immediate Steps to Fix

### Step 1: Disable Battery Optimization (CRITICAL)
1. Open **Settings** on your Android device
2. Go to **Apps** → **AgriCart**
3. Tap **Battery**
4. Select **"Unrestricted"** or **"Not optimized"**
5. **Reboot your device** (important!)

### Step 2: Check Notification Channel Settings
1. Open **Settings** → **Apps** → **AgriCart**
2. Tap **Notifications**
3. Find **"AgriCart Customer Notifications"** channel
4. Ensure it's **enabled**
5. Set importance to **"High"** or **"Urgent"**
6. Enable all options:
   - ✅ Sound
   - ✅ Vibration
   - ✅ Pop on screen
   - ✅ Show on lock screen

### Step 3: Check Do Not Disturb
1. Open **Settings** → **Notifications**
2. Tap **Do Not Disturb**
3. Either:
   - **Disable DND temporarily** to test, OR
   - Add **AgriCart** to exception list

### Step 4: Verify App Was Opened
1. **Open the app** at least once
2. Ensure notification permission is granted
3. Check app logs for: `✅ Notification channel created`

### Step 5: Test Again
1. **Force stop** the app completely
2. Send a notification from web dashboard
3. Notification should appear ✅

## Device-Specific Instructions

### Samsung
- Settings → Apps → AgriCart → Battery → **Unrestricted**
- Settings → Apps → AgriCart → **App power management** → **Never sleeping apps** → Add AgriCart

### Xiaomi/Redmi
- Settings → Apps → AgriCart → **Battery saver** → **No restrictions**
- Settings → Apps → **Autostart** → Enable for AgriCart

### OnePlus
- Settings → Apps → AgriCart → **Battery optimization** → **Don't optimize**
- Settings → **Battery** → **Smart power saving** → Disable

### Huawei
- Settings → Apps → AgriCart → **Battery** → **App launch** → **Manage manually** → Enable all
- Settings → **Battery** → **App launch** → **Protected apps** → Add AgriCart

## Verification

After applying fixes, check Edge Function logs:
- ✅ `FCM notification sent successfully`
- ✅ `FCM message accepted by Google`
- ✅ `FCM Message ID: projects/...`

If these appear but notification doesn't show, it's a device setting issue.

## Still Not Working?

1. **Uninstall and reinstall** the app
2. **Grant all permissions** when prompted
3. **Open app** and verify channel is created
4. **Disable battery optimization** again
5. **Test notification**

## Summary

The FCM message is being sent correctly. The issue is Android blocking notifications due to:
- Battery optimization (most common)
- Notification channel settings
- Do Not Disturb
- Device-specific power management

**Most common fix**: Disable battery optimization + Reboot device

