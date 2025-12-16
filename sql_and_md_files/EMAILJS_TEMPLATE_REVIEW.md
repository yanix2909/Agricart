# EmailJS Template Review & Setup Checklist

## ✅ Template Review - CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html

### Template Structure ✅
- **Conditional Display**: Uses CSS `data-show-approval` and `data-show-rejection` attributes ✅
- **CSS Hiding**: `tr[data-show-approval="false"]` and `tr[data-show-rejection="false"]` will hide sections ✅
- **Template Variables**: All required variables are present ✅
- **Design**: Matches EMAIL_CONFIRMATION_TEMPLATE.html design ✅
- **Logo URLs**: Valid Supabase storage URLs ✅

### Template Variables Used

The template expects these EmailJS variables:

1. **`{{customer_name}}`** - Customer's full name ✅
2. **`{{staff_name}}`** - Staff/Admin name ✅
3. **`{{staff_role}}`** - Staff/Admin role ✅
4. **`{{show_approved}}`** - "true" or "false" string ✅
5. **`{{show_rejected}}`** - "true" or "false" string ✅
6. **`{{approval_date}}`** - Date string (for approved emails) ✅
7. **`{{rejection_reason}}`** - Reason text (for rejected emails) ✅
8. **`{{rejection_date}}`** - Date string (for rejected emails) ✅

### Implementation Status

✅ **Template file is ready** - `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`  
✅ **Code implementation is ready** - Email sending functions in `staff.js`  
⚠️ **EmailJS Public Key** - Needs to be added to `staff-dashboard.html`  
✅ **Template variables match** - Code sends correct variables

---

## 🔧 Setup Steps

### Step 1: Get EmailJS Public Key

1. Go to **https://dashboard.emailjs.com/**
2. Sign in to your EmailJS account
3. Navigate to **Account** → **General**
4. Copy your **Public Key** (looks like: `abc123xyz789...`)

### Step 2: Add Public Key to staff-dashboard.html

Open `webdashboards/staff-dashboard.html` and find this line (around line 7810):

```javascript
emailjs.init('YOUR_EMAILJS_PUBLIC_KEY');
```

Replace `'YOUR_EMAILJS_PUBLIC_KEY'` with your actual key:

```javascript
emailjs.init('your-actual-public-key-here');
```

### Step 3: Configure EmailJS Template

1. Go to **EmailJS Dashboard** → **Email Templates**
2. Find or create template with ID: `template_0azg7ul`
3. **Service ID**: `service_pd9ccy8`
4. **Template Content**: Copy the entire content from `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html` and paste it in the EmailJS template editor
5. **Important**: Make sure the "To Email" field in EmailJS template settings is configured to use a template variable like `{{to_email}}` OR set it to receive from your service configuration

### Step 4: Configure EmailJS Service

1. Go to **EmailJS Dashboard** → **Email Services**
2. Find service with ID: `service_pd9ccy8`
3. Ensure it's properly configured (Gmail, SMTP, etc.)
4. Test the service to make sure emails can be sent

---

## 📋 EmailJS Template Settings

When setting up the template in EmailJS dashboard:

### Template Settings:
- **Template Name**: Customer Approval/Rejection
- **Template ID**: `template_0azg7ul`
- **Service**: `service_pd9ccy8`

### Template Variables (Auto-detected):
- `customer_name`
- `staff_name`
- `staff_role`
- `show_approved`
- `show_rejected`
- `approval_date`
- `rejection_reason`
- `rejection_date`
- `to_email` (if using recipient email variable - see below)

### Recipient Email Configuration:

**Option 1**: Use Template Variable (Recommended)
- In EmailJS template settings, set "To Email" field to: `{{to_email}}`
- Then update `staff.js` to include `to_email` in templateParams (see below)

**Option 2**: Use Service Default
- Configure recipient email in EmailJS service settings
- EmailJS will use the default recipient

---

## 🔍 Important Notes

### ⚠️ Recipient Email Address

Currently, the code does NOT explicitly pass the recipient email (`to_email`) to EmailJS. You need to configure this in one of two ways:

**Option A**: Add `to_email` to template parameters (Recommended)

Update `staff.js` `sendApprovalEmail` and `sendRejectionEmail` functions to include:

```javascript
const templateParams = {
  // ... existing params ...
  to_email: customerEmail  // Add this line
};
```

**Option B**: Configure in EmailJS Dashboard
- Set the "To Email" field in your EmailJS service settings to receive emails sent through this template
- This works if all emails should go to a single address (not recommended for customer emails)

### 📧 Email Delivery

- Emails will only send if:
  - ✅ Customer email is valid (not `@agricart.local`)
  - ✅ EmailJS Public Key is configured
  - ✅ EmailJS service is properly set up
  - ✅ Template ID and Service ID are correct

### 🧪 Testing

1. **Test Approval Email**:
   - Register a test customer with a real email
   - Approve them in staff dashboard
   - Check browser console for: `✅ Approval email sent successfully`
   - Check customer's email inbox (and spam folder)

2. **Test Rejection Email**:
   - Register another test customer
   - Reject them in staff dashboard (with reason)
   - Check browser console for: `✅ Rejection email sent successfully`
   - Check customer's email inbox (and spam folder)

---

## 🔧 Code Verification Checklist

✅ `sendApprovalEmail()` function exists in `staff.js`  
✅ `sendRejectionEmail()` function exists in `staff.js`  
✅ `approveVerification()` calls `sendApprovalEmail()`  
✅ `rejectVerification()` calls `sendRejectionEmail()`  
✅ EmailJS script is loaded in `staff-dashboard.html`  
⚠️ EmailJS Public Key needs to be configured  
⚠️ Recipient email (`to_email`) may need to be added to template params

---

## 📝 Next Steps

1. **Get EmailJS Public Key** from dashboard
2. **Replace placeholder** in `staff-dashboard.html`
3. **Upload template** to EmailJS dashboard (copy from `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`)
4. **Configure recipient email** in EmailJS template settings or add `to_email` to code
5. **Test** by approving/rejecting a test customer
6. **Check EmailJS dashboard logs** if emails don't arrive

---

**Last Updated**: 2025-01-27

