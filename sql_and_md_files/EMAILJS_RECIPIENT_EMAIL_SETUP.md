# EmailJS Recipient Email Configuration Fix

## Problem
Error: "The recipients address is empty" (422 status)

This happens because EmailJS template needs to be configured to use the recipient email variable.

## Solution: Configure EmailJS Template

### Step 1: Open Your EmailJS Template

1. Go to **https://dashboard.emailjs.com/**
2. Sign in
3. Navigate to **Email Templates**
4. Find or open template with ID: **`template_0azg7ul`**

### Step 2: Configure "To Email" Field

In your EmailJS template settings, you need to set the **"To Email"** field:

1. Look for the **"To Email"** or **"Recipient Email"** field in the template settings
2. Set it to use one of these template variables:
   - `{{to_email}}` (recommended)
   - OR `{{user_email}}`
   - OR `{{email}}`

### Step 3: Template Settings Location

The "To Email" field is usually found in:
- **Template Settings** → **Email Settings** → **To Email**
- Or in the template editor sidebar
- Or in the template configuration panel

### Step 4: Example Configuration

In EmailJS dashboard, your template settings should look like:

```
Template Name: Customer Approval/Rejection
Template ID: template_0azg7ul
Service: service_pd9ccy8

Email Settings:
  From Name: AgriCart
  From Email: [your configured email]
  To Email: {{to_email}}    ← THIS IS CRITICAL!
  Reply To: [optional]
  Subject: Account Status Update - AgriCart
```

### Step 5: Save and Test

1. **Save** the template settings
2. **Test** by approving a customer again
3. Check browser console - should see: `✅ Approval email sent successfully`

---

## Alternative: If "To Email" Field is Not Available

If your EmailJS service doesn't allow dynamic "To Email" in template settings, you may need to:

1. **Check Service Type**: Some EmailJS services require the recipient to be configured differently
2. **Use Service Default**: Configure a default recipient in the service settings (not recommended for customer emails)
3. **Contact EmailJS Support**: If the template doesn't support dynamic recipient emails

---

## Code Already Updated

The code now sends the recipient email in multiple formats:
- `to_email: customerEmail`
- `user_email: customerEmail`
- `email: customerEmail`

So whichever variable name you use in the EmailJS template will work.

---

## Quick Checklist

- [ ] EmailJS template `template_0azg7ul` is open
- [ ] "To Email" field is set to `{{to_email}}` (or `{{user_email}}` or `{{email}}`)
- [ ] Template is saved
- [ ] Test by approving a customer
- [ ] Check browser console for success message

---

**Most Common Issue**: The "To Email" field in EmailJS template dashboard is not configured to use `{{to_email}}` variable.

