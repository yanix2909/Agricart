# Notification Behavior Clarification

## Summary
**Notifications are sent to the mobile phone ONLY if the customer is logged in**, regardless of whether the app is:
- ✅ Just closed (in background)
- ✅ Force-stopped (completely terminated)

**Notifications are NOT sent if the customer has logged out**, even if the app is still installed.

## How It Works

### 1. When Customer Logs In
- FCM token is saved to `customer_fcm_tokens` table in Supabase
- Token is associated with the customer's ID
- This allows the Edge Function to send notifications to that device

### 2. When Customer Logs Out
- FCM token is **removed** from `customer_fcm_tokens` table
- This happens in `auth_provider.dart` → `signOut()` method
- Edge Function will not find a token and will skip sending the notification

### 3. When Notification is Triggered
The Edge Function (`send-fcm-notification`) checks:
1. ✅ Does FCM token exist for this customer?
   - **YES** → Send notification to device (works even if app is closed/force-stopped)
   - **NO** → Skip notification (customer is logged out)

## Code Flow

### Login Flow
```dart
// auth_provider.dart - signIn()
await NotificationService.saveFCMToken(_userId!);
// → Saves token to customer_fcm_tokens table
```

### Logout Flow
```dart
// auth_provider.dart - signOut()
await NotificationService.removeFCMToken(customerId);
// → Removes token from customer_fcm_tokens table
await SupabaseService.client.auth.signOut();
```

### Notification Sending Flow
```typescript
// Edge Function - send-fcm-notification/index.ts
const fcmTokenData = await supabase
  .from("customer_fcm_tokens")
  .select("fcm_token")
  .eq("customer_id", customerId)
  .single();

if (!fcmTokenData || !fcmTokenData.fcm_token) {
  // Customer is logged out - skip notification
  return { success: false, message: "No FCM token found" };
}

// Customer is logged in - send notification
await sendFCMNotification(...);
```

## Behavior Matrix

| Customer State | App State | Notification Sent? | Reason |
|---------------|-----------|-------------------|--------|
| ✅ Logged In | App Open | ✅ Yes | FCM token exists |
| ✅ Logged In | App Closed | ✅ Yes | FCM token exists, FCM handles delivery |
| ✅ Logged In | App Force-Stopped | ✅ Yes | FCM token exists, Google Play Services handles delivery |
| ❌ Logged Out | App Open | ❌ No | FCM token removed on logout |
| ❌ Logged Out | App Closed | ❌ No | FCM token removed on logout |
| ❌ Logged Out | App Force-Stopped | ❌ No | FCM token removed on logout |

## Important Notes

1. **FCM Token = Login State**
   - Token exists → Customer is logged in → Notifications sent
   - Token removed → Customer is logged out → Notifications NOT sent

2. **App State Doesn't Matter**
   - Whether app is open, closed, or force-stopped doesn't affect notification delivery
   - As long as FCM token exists (customer logged in), notifications will be sent

3. **Edge Function Behavior**
   - If no FCM token found, Edge Function logs: "No FCM token found, customer may be logged out"
   - This is **expected behavior**, not an error
   - Notification is marked as `fcm_sent = true` to prevent retries

4. **Multiple Devices**
   - Each device has its own FCM token
   - If customer logs in on multiple devices, all devices receive notifications
   - If customer logs out, all tokens for that customer are removed

## Testing

### Test 1: Logged In, App Closed
1. Customer logs in → FCM token saved
2. Close app (don't force stop)
3. Send notification from web dashboard
4. **Expected**: ✅ Notification appears on phone

### Test 2: Logged In, App Force-Stopped
1. Customer logs in → FCM token saved
2. Force stop the app completely
3. Send notification from web dashboard
4. **Expected**: ✅ Notification appears on phone (if Android settings allow)

### Test 3: Logged Out, App Still Installed
1. Customer logs out → FCM token removed
2. App is still installed (but logged out)
3. Send notification from web dashboard
4. **Expected**: ❌ No notification sent (Edge Function logs "No FCM token found")

## Edge Function Logs

### When Customer is Logged In:
```
✅ FCM notification sent successfully for notification [id]
📱 FCM Response: { "name": "projects/.../messages/..." }
📱 FCM Message ID: projects/.../messages/...
✅ FCM message accepted by Google - should be delivered to device
```

### When Customer is Logged Out:
```
⚠️ No FCM token found for customer [id], skipping push notification
ℹ️ This is expected if the customer has logged out (FCM token is removed on logout)
ℹ️ Notifications are only sent to logged-in customers, regardless of app state (closed/force-stopped)
```

## Summary

✅ **Notifications work when app is closed/force-stopped** - As long as customer is logged in  
✅ **Notifications don't work when customer is logged out** - FCM token is removed  
✅ **System correctly handles both scenarios** - Edge Function checks token existence before sending

The key is: **FCM token existence = Customer logged in = Notifications sent**

