# Force-Stopped App Notification Troubleshooting

## Issue
Notifications work when the app is in background, but **do not appear when the app is force-stopped**.

## Understanding Force-Stopped Apps on Android

When an app is **force-stopped** on Android:
- All app processes are killed
- Background services are stopped
- The app cannot run any code until the user opens it again

**However**, FCM notifications with the `notification` field should still work because:
- Google Play Services handles FCM delivery (not the app)
- The system automatically displays notifications when the `notification` field is present
- The app doesn't need to be running for FCM to display notifications

## Why Notifications Might Not Work When Force-Stopped

### 1. Android Security Feature (Most Common)
Android may suppress notifications from force-stopped apps until the user opens the app again. This is a security/privacy feature.

**Solution**: The user must open the app at least once after installation/update for FCM to work properly.

### 2. Battery Optimization
If the app is battery-optimized, Android might block notifications when the app is force-stopped.

**Solution**: Disable battery optimization for the app:
1. Settings → Apps → AgriCart → Battery
2. Set to "Unrestricted" or "Not optimized"

### 3. Notification Channel Settings
The notification channel must be enabled and set to high importance.

**Solution**: 
1. Settings → Apps → AgriCart → Notifications
2. Ensure "AgriCart Customer Notifications" channel is enabled
3. Set importance to "High" or "Urgent"

### 4. Do Not Disturb (DND)
DND might be blocking notifications.

**Solution**:
1. Settings → Notifications → Do Not Disturb
2. Add AgriCart to exception list or disable DND

### 5. App Not Opened After Installation
FCM requires the app to be opened at least once after installation/update.

**Solution**: User must open the app at least once.

## Current FCM Message Structure

The FCM message is correctly configured with:
- ✅ `notification` field (title + body) - **CRITICAL** for auto-display
- ✅ `android.priority: "high"` - Ensures immediate delivery
- ✅ `android.notification.channelId` - Matches app's channel
- ✅ `android.notification.visibility: "public"` - Shows on lock screen
- ✅ `android.directBootOk: true` - Works after reboot

## Testing Steps

### Test 1: Normal Background (Should Work)
1. Minimize the app (don't force stop)
2. Send a notification
3. **Expected**: Notification appears ✅

### Test 2: Force-Stopped (May Not Work Initially)
1. Force stop the app completely
2. Send a notification
3. **Expected**: 
   - If app was opened recently: Notification appears ✅
   - If app was never opened after install: May not appear ❌

### Test 3: After Opening App Once
1. Open the app (even briefly)
2. Force stop the app
3. Send a notification
4. **Expected**: Notification appears ✅ (if battery optimization is disabled)

## Android Manifest Configuration

The app is configured with:
- ✅ `android:stopWithTask="false"` - Service continues even when app is force-stopped
- ✅ `android:directBootAware="true"` - Works after reboot
- ✅ Firebase Messaging Service properly configured
- ✅ Background service properly configured

## Important Notes

1. **FCM with `notification` field should work even when force-stopped** - Google Play Services handles delivery
2. **Android may suppress notifications** from force-stopped apps as a security feature
3. **User must open app at least once** after installation/update for FCM to work
4. **Battery optimization must be disabled** for reliable notifications
5. **Notification channel must be enabled** and set to high importance

## Edge Function Logs

If you see "shutdown" in Edge Function logs:
- This might refer to the Edge Function completing, not the app
- Check if the FCM API call was successful (status 200)
- Check FCM response for any errors

## Recommended User Instructions

For users experiencing issues with force-stopped notifications:

1. **Open the app at least once** after installation/update
2. **Disable battery optimization**:
   - Settings → Apps → AgriCart → Battery → Unrestricted
3. **Enable notifications**:
   - Settings → Apps → AgriCart → Notifications → Enable
   - Set "AgriCart Customer Notifications" channel to "High" importance
4. **Check Do Not Disturb**:
   - Ensure DND is not blocking notifications
5. **Test notification**:
   - Force stop the app
   - Send a test notification
   - Notification should appear

## Technical Details

### How FCM Works When App is Force-Stopped

1. **FCM message sent** from Edge Function to FCM servers
2. **FCM servers** deliver to Google Play Services (not the app)
3. **Google Play Services** checks if notification should be displayed
4. **System displays notification** if:
   - App was opened at least once
   - Battery optimization is disabled
   - Notification channel is enabled
   - DND is not blocking

### Why Background Handler Might Not Run

When the app is force-stopped:
- The `_firebaseMessagingBackgroundHandler` might not execute
- **This is OK** - FCM will still display the notification automatically
- The notification is displayed by the system, not the app

## Summary

The FCM message structure is correct. Notifications should work when force-stopped, but Android may suppress them due to:
- Security features (app not opened recently)
- Battery optimization
- Notification settings
- Do Not Disturb

**Solution**: Ensure app is opened at least once, disable battery optimization, and enable notifications with high importance.

