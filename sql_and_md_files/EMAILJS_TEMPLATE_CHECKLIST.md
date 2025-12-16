# EmailJS Template Configuration Checklist

## ✅ What You've Configured (From Image)

- **To Email**: `{{to_email}}` ✅ CORRECT
- **From Name**: `agricart` ✅ GOOD

## Complete Template Configuration Checklist

### Required Fields:

1. ✅ **To Email**: `{{to_email}}` - MUST use this variable
2. ✅ **From Name**: `agricart` (or your preferred sender name)
3. ⚠️ **From Email**: Should be configured in your EmailJS Service settings
4. ⚠️ **Subject**: Should be set (e.g., "Account Status Update - AgriCart")
5. ⚠️ **Template Content**: Should contain the HTML from `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`

### Additional Settings to Check:

- **Reply To** (optional): Can be `agricartcalcoa@gmail.com` or leave empty
- **Template Variables**: Make sure all these are recognized by EmailJS:
  - `{{to_email}}`
  - `{{customer_name}}`
  - `{{staff_name}}`
  - `{{staff_role}}`
  - `{{show_approved}}`
  - `{{show_rejected}}`
  - `{{approval_date}}`
  - `{{rejection_reason}}`
  - `{{rejection_date}}`

### Important Notes:

1. **Service Configuration**: Make sure your EmailJS Service (`service_pd9ccy8`) is:
   - Connected to an email account (Gmail, SMTP, etc.)
   - Tested and working
   - Has permissions to send emails

2. **Template ID**: Verify the Template ID is exactly: `template_0azg7ul`

3. **Service ID**: Verify the Service ID is exactly: `service_pd9ccy8`

---

## If Still Getting Errors

If you still see "The recipients address is empty" after saving:

1. **Double-check**: The "To Email" field must be exactly `{{to_email}}` (no spaces, case-sensitive)
2. **Save again**: Click Save in EmailJS dashboard
3. **Check Service**: Make sure your EmailJS Service is properly configured
4. **Browser cache**: Try hard refresh (Ctrl+Shift+R) on staff dashboard
5. **Check console**: Look for the `📤 EmailJS template params:` log to verify what's being sent

---

## Testing Steps

1. Save template in EmailJS dashboard
2. Open staff dashboard
3. Approve a test customer
4. Check browser console for:
   - `📤 EmailJS template params:` (shows what's being sent)
   - `✅ Approval email sent successfully`
5. Check customer's email inbox (and spam folder)

