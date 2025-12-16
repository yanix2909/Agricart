# Fix: EmailJS Gmail Authentication Error

## Error
```
412 (Precondition Failed)
Gmail_API: Request had insufficient authentication scopes.
```

## Cause
The Gmail service connected to EmailJS needs to be re-authenticated or granted proper permissions.

## Solution

### Step 1: Re-authenticate Gmail Service

1. Go to **https://dashboard.emailjs.com/**
2. Sign in to your EmailJS account
3. Navigate to **Email Services**
4. Find your service: **`service_pd9ccy8`**
5. Click on it to edit/open it

### Step 2: Reconnect Gmail Account

1. Look for **"Reconnect"** or **"Authorize"** button
2. Click it to re-authenticate
3. Grant these permissions:
   - ✅ Send email on your behalf
   - ✅ Read email (if needed)
   - ✅ Manage email settings

### Step 3: Grant Required Scopes

When re-authenticating, make sure Gmail grants these scopes:
- `https://www.googleapis.com/auth/gmail.send` (Required for sending emails)
- `https://www.googleapis.com/auth/gmail.compose` (May be needed)

### Step 4: Test the Service

1. In EmailJS dashboard, go to your service
2. Look for a **"Test"** or **"Send Test Email"** button
3. Send a test email to yourself
4. If successful, the service is properly configured

---

## Alternative: Use Different Email Service

If Gmail continues to have issues, you can:

### Option A: Use SMTP Service (Recommended)

1. In EmailJS dashboard, create a **new SMTP service**
2. Use your email provider's SMTP settings:
   - Gmail SMTP: `smtp.gmail.com`
   - Port: `587` (TLS) or `465` (SSL)
   - Use your Gmail email and an **App Password** (not your regular password)
3. Update the service ID in code if you change it

### Option B: Use EmailJS Direct Service

1. Some EmailJS plans offer direct email sending
2. Check if your plan supports it
3. Configure accordingly

---

## How to Get Gmail App Password (For SMTP)

If using SMTP instead of Gmail API:

1. Go to **Google Account Settings**
2. Navigate to **Security**
3. Enable **2-Step Verification** (if not already enabled)
4. Go to **App Passwords**
5. Generate a new app password for "Mail"
6. Use this password (not your regular Gmail password) in SMTP settings

---

## Quick Fix Steps Summary

1. ✅ Go to EmailJS Dashboard → Email Services
2. ✅ Open service `service_pd9ccy8`
3. ✅ Click "Reconnect" or "Authorize" button
4. ✅ Grant all requested permissions
5. ✅ Test the service
6. ✅ Try approving a customer again

---

## Verify After Fix

After re-authenticating, test by:
1. Approving a test customer in staff dashboard
2. Check browser console for: `✅ Approval email sent successfully`
3. Check customer's email inbox

---

**Note**: If re-authentication doesn't work, you may need to revoke EmailJS's access to your Gmail account in Google Account settings and start fresh, or switch to SMTP service.

