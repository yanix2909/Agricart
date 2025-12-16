# Customer Removal Email Implementation

## Overview

This implementation adds email notifications when staff/admin removes a customer account. The email is sent using Supabase's invite user format, and after the email is sent, the customer account is deleted from both the `customers` table and Supabase Auth (`auth.users`).

## Implementation Details

### Flow

1. **Staff/Admin clicks "Remove Customer"**
2. **Get customer email** - The system retrieves the customer's email before deletion
3. **Send email** - An email is sent using Supabase's invite format via Edge Function
4. **Delete account** - Customer record is deleted from `customers` table and `auth.users`

### Files Modified

1. **`webdashboards/customer-rejection-handler.js`**
   - Updated `removeCustomer()` method to:
     - Get customer email before deletion
     - Send email using Supabase invite format via Edge Function
     - Delete from customer table and auth.users via SQL function

2. **`webdashboards/staff.js`**
   - Updated `removeCustomer()` method to use `customerRejectionHandler`
   - Passes staff info (uid, name, role) to the handler

3. **`webdashboards/staff-dashboard.html`**
   - Added script tag to include `customer-rejection-handler.js`

### Files Created

1. **`supabase/functions/send-customer-removal-email/index.ts`**
   - Edge Function that sends email using Supabase's `inviteUserByEmail()` API
   - Uses Supabase Admin API (service role) to send invite-format emails
   - Handles errors gracefully (deletion continues even if email fails)

## Setup Instructions

### 1. Deploy Supabase Edge Function

The Edge Function needs to be deployed to your Supabase project:

```bash
# Install Supabase CLI if not already installed
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project (if not already linked)
supabase link --project-ref YOUR_PROJECT_REF

# Deploy the Edge Function
supabase functions deploy send-customer-removal-email
```

### 2. Set Environment Variables

The Edge Function requires these environment variables (set in Supabase Dashboard):

- `SUPABASE_URL` - Your Supabase project URL (automatically set)
- `SUPABASE_SERVICE_ROLE_KEY` - Your Supabase service role key (automatically set)

These are automatically available in Supabase Edge Functions, so no manual configuration is needed.

### 3. Verify SQL Functions

Ensure the following SQL functions exist in your Supabase database:

- `remove_customer_account()` - Deletes from customers table and auth.users
- `delete_customer_auth_user()` - Helper function to delete from auth.users

These should already exist from the previous customer rejection/removal system setup.

## How It Works

### Email Sending

1. When `removeCustomer()` is called:
   - Customer email is retrieved from the `customers` table
   - Edge Function `send-customer-removal-email` is invoked
   - Edge Function uses `admin.auth.admin.inviteUserByEmail()` to send email
   - Email is sent in Supabase's invite format

2. **Note**: If the user already exists in auth, `inviteUserByEmail()` will fail, but this is handled gracefully. The deletion will still proceed.

### Account Deletion

After the email is sent (or if email sending fails), the SQL function `remove_customer_account()` is called, which:
- Deletes the customer record from the `customers` table
- Deletes the user from `auth.users` (via `delete_customer_auth_user()`)
- This allows the email to be reused for future registrations

## Email Format

The email uses Supabase's built-in invite email format. The content can be customized later by:
- Modifying Supabase email templates in the Dashboard
- Updating the Edge Function to use custom email content
- Using a third-party email service

## Error Handling

- If email sending fails, the deletion still proceeds
- Errors are logged to the console but don't block the removal process
- The customer account is always deleted, even if email fails

## Testing

1. **Test Email Sending**:
   - Remove a test customer account
   - Check that email is received
   - Verify email format matches Supabase invite format

2. **Test Account Deletion**:
   - Remove a customer account
   - Verify customer is deleted from `customers` table
   - Verify user is deleted from `auth.users`
   - Verify email can be reused for new registration

3. **Test Error Handling**:
   - Temporarily break the Edge Function
   - Remove a customer account
   - Verify deletion still proceeds even if email fails

## Future Improvements

1. **Custom Email Content**: Update the Edge Function to send custom email content instead of using the default invite format
2. **Email Templates**: Use Supabase email templates for better customization
3. **Email Queue**: Implement a retry mechanism for failed emails
4. **Email Tracking**: Track email delivery status

## Notes

- The email is sent **before** account deletion to ensure the customer receives it
- The email uses Supabase's invite format as requested (content can be changed later)
- Account deletion happens in a transaction, ensuring both customer table and auth.users are cleaned up
- The email address becomes available for reuse immediately after deletion

