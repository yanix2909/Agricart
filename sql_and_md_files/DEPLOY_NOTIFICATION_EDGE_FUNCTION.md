# Deploy Notification Edge Function

## Problem
The staff dashboard cannot directly insert notifications into `customer_notifications` table due to Row Level Security (RLS) policies. The RLS policies only allow:
1. Authenticated customers to insert their own notifications
2. Service role to insert notifications

## Solution
An Edge Function (`create-notifications`) has been created that uses service role permissions to insert notifications. This Edge Function must be deployed to Supabase.

## Deployment Steps

### 1. Deploy the Edge Function

Using Supabase CLI:
```bash
cd supabase/functions/create-notifications
supabase functions deploy create-notifications
```

Or using the Supabase Dashboard:
1. Go to Supabase Dashboard → Edge Functions
2. Click "Create a new function"
3. Name it `create-notifications`
4. Copy the contents of `supabase/functions/create-notifications/index.ts`
5. Deploy the function

### 2. Verify Environment Variables

The Edge Function requires these environment variables (automatically set by Supabase):
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Your Supabase service role key

These are automatically available in Edge Functions, so no manual configuration is needed.

### 3. Test the Edge Function

You can test it using curl or Postman:

```bash
curl -X POST 'https://afkwexvvuxwbpioqnelp.supabase.co/functions/v1/create-notifications' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Test Notification",
    "message": "This is a test notification",
    "type": "product_added",
    "productId": "test_product_123"
  }'
```

### 4. Verify Notifications Are Created

After deploying, when staff/admin:
- Restocks a product (quantity >= current quantity)
- Adds a new product

The Edge Function will be called automatically, and notifications will be created for all customers.

## Troubleshooting

### Edge Function Not Found (404)
- Make sure the function is deployed
- Check the function name matches exactly: `create-notifications`
- Verify the Supabase URL is correct

### Permission Denied (403)
- Check that the anon key is being sent in the Authorization header
- Verify RLS policies allow service role to insert notifications

### No Notifications Created
- Check Edge Function logs in Supabase Dashboard
- Verify customers exist in the database
- Check browser console for error messages

### Notifications Created But Not Sent
- The Edge Function only creates notifications
- FCM push notifications are sent by the `send-fcm-notification` Edge Function
- This is triggered automatically by database triggers when notifications are inserted

## How It Works

1. Staff/admin restocks a product or adds a new product
2. `NotificationHelpers.notifyAllCustomers()` is called
3. It makes an HTTP POST request to the `create-notifications` Edge Function
4. The Edge Function uses service role permissions to insert notifications for all customers
5. Database triggers detect new notifications and call `send-fcm-notification` Edge Function
6. FCM push notifications are sent to all customers with FCM tokens
7. Notifications appear in the customer app's notification history
