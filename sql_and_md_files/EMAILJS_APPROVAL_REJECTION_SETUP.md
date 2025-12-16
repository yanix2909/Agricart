# EmailJS Customer Approval/Rejection Template Setup

## Template File
- **File**: `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`
- **EmailJS Service ID**: `service_pd9ccy8`
- **EmailJS Template ID**: `template_0azg7ul`

## How It Works

This is a **single HTML template** that can display either approval or rejection content based on template variables passed from your JavaScript code.

## Template Variables

The template uses the following variables that you need to set when calling EmailJS:

### Required Variables (Always Set):

1. **`{{customer_name}}`** - Customer's full name
2. **`{{staff_name}}`** - Staff/Admin name who reviewed
3. **`{{staff_role}}`** - Staff/Admin role

### Conditional Display Variables:

4. **`{{show_approved}}`** - Show/hide approved section
   - Set to `true` to show approved content
   - Set to `false` to hide approved content

5. **`{{show_rejected}}`** - Show/hide rejected section
   - Set to `true` to show rejected content
   - Set to `false` to hide rejected content

### Conditional Content Variables:

**For Approved Emails:**
- `{{show_approved}}` = `true`
- `{{show_rejected}}` = `false`
- `{{approval_date}}` - Date when account was approved

**For Rejected Emails:**
- `{{show_approved}}` = `false`
- `{{show_rejected}}` = `true`
- `{{rejection_reason}}` - Reason for rejection
- `{{rejection_date}}` - Date when account was rejected

---

## JavaScript Implementation Examples

### Example 1: Send Approval Email

```javascript
// When customer is approved
function sendApprovalEmail(customerName, customerEmail, staffName, staffRole, approvalDate) {
    emailjs.send('service_pd9ccy8', 'template_0azg7ul', {
        customer_name: customerName,
        staff_name: staffName,
        staff_role: staffRole,
        approval_date: approvalDate,
        show_approved: 'true',    // Show approved section
        show_rejected: 'false',   // Hide rejected section
        rejection_reason: '',     // Not needed for approval
        rejection_date: ''        // Not needed for approval
    }, {
        to_email: customerEmail
    })
    .then(function(response) {
        console.log('✅ Approval email sent!', response.status, response.text);
    })
    .catch(function(error) {
        console.error('❌ Failed to send approval email:', error);
    });
}

// Usage:
sendApprovalEmail(
    'John Doe',
    'john.doe@example.com',
    'Maria Santos',
    'Admin',
    'January 15, 2025'
);
```

### Example 2: Send Rejection Email

```javascript
// When customer is rejected
function sendRejectionEmail(customerName, customerEmail, staffName, staffRole, rejectionReason, rejectionDate) {
    emailjs.send('service_pd9ccy8', 'template_0azg7ul', {
        customer_name: customerName,
        staff_name: staffName,
        staff_role: staffRole,
        rejection_reason: rejectionReason,
        rejection_date: rejectionDate,
        show_approved: 'false',   // Hide approved section
        show_rejected: 'true',    // Show rejected section
        approval_date: ''         // Not needed for rejection
    }, {
        to_email: customerEmail
    })
    .then(function(response) {
        console.log('✅ Rejection email sent!', response.status, response.text);
    })
    .catch(function(error) {
        console.error('❌ Failed to send rejection email:', error);
    });
}

// Usage:
sendRejectionEmail(
    'John Doe',
    'john.doe@example.com',
    'Maria Santos',
    'Admin',
    'ID verification documents were not clear or incomplete.',
    'January 15, 2025'
);
```

---

## Integration with Staff Dashboard

### In `staff.js` or `admin.js`:

```javascript
// After approving a customer
async function approveCustomer(customerUid, verificationData) {
    try {
        // ... your existing approval logic ...
        
        // Send approval email
        if (verificationData.email && verificationData.email.trim() !== '') {
            const approvalDate = new Date().toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
            
            await sendApprovalEmail(
                verificationData.fullName,
                verificationData.email,
                currentStaff.name,
                currentStaff.role,
                approvalDate
            );
        }
        
        console.log('Customer approved successfully');
    } catch (error) {
        console.error('Error approving customer:', error);
    }
}

// After rejecting a customer
async function rejectCustomer(customerUid, verificationData, rejectionReason) {
    try {
        // ... your existing rejection logic ...
        
        // Send rejection email
        if (verificationData.email && verificationData.email.trim() !== '') {
            const rejectionDate = new Date().toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
            
            await sendRejectionEmail(
                verificationData.fullName,
                verificationData.email,
                currentStaff.name,
                currentStaff.role,
                rejectionReason,
                rejectionDate
            );
        }
        
        console.log('Customer rejected successfully');
    } catch (error) {
        console.error('Error rejecting customer:', error);
    }
}
```

---

## Setting Up in EmailJS Dashboard

1. Go to **EmailJS Dashboard** → **Email Templates**
2. Find template **`template_0azg7ul`** (or create new one)
3. Copy the entire content from **`CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`**
4. Paste it into the HTML template editor
5. In the **Settings** tab, configure:
   - **Subject Line**: `AgriCart Account Status Update`
   - Make sure all template variables are recognized:
     - `customer_name`
     - `staff_name`
     - `staff_role`
     - `approved_display`
     - `rejected_display`
     - `approval_date`
     - `rejection_reason`
     - `rejection_date`

---

## Notes

- ✅ The template uses the **same design format** as `EMAIL_CONFIRMATION_TEMPLATE.html`
- ✅ **One template** handles both approval and rejection
- ✅ Content changes based on `approved_display` and `rejected_display` variables
- ✅ Different messages for approval vs rejection
- ✅ Same logo, colors, and footer design

---

## Template Variables Summary Table

| Variable | Required | For Approval | For Rejection | Example Value |
|----------|----------|--------------|---------------|---------------|
| `customer_name` | ✅ Yes | ✅ Yes | ✅ Yes | "John Doe" |
| `staff_name` | ✅ Yes | ✅ Yes | ✅ Yes | "Maria Santos" |
| `staff_role` | ✅ Yes | ✅ Yes | ✅ Yes | "Admin" |
| `show_approved` | ✅ Yes | `true` | `false` | `true` or `false` |
| `show_rejected` | ✅ Yes | `false` | `true` | `true` or `false` |
| `approval_date` | Conditional | ✅ Yes | ❌ No | "January 15, 2025" |
| `rejection_reason` | Conditional | ❌ No | ✅ Yes | "ID documents unclear" |
| `rejection_date` | Conditional | ❌ No | ✅ Yes | "January 15, 2025" |

---

## Testing

Test both scenarios:

1. **Test Approval Email:**
   ```javascript
   sendApprovalEmail('Test User', 'test@example.com', 'Test Staff', 'Admin', 'Today');
   ```

2. **Test Rejection Email:**
   ```javascript
   sendRejectionEmail('Test User', 'test@example.com', 'Test Staff', 'Admin', 'Test rejection reason', 'Today');
   ```

Make sure the correct section appears and the other is hidden!

