# EmailJS Integration Guide for Customer Approval/Rejection Emails

## Overview
This guide shows you how to integrate EmailJS to send approval/rejection emails to customers when staff/admin approves or rejects their account registration.

## Step 1: Add EmailJS Script to HTML

Add the EmailJS script tag to `webdashboards/staff-dashboard.html` before the closing `</body>` tag (around line 23307):

```html
<!-- EmailJS Script -->
<script type="text/javascript" src="https://cdn.jsdelivr.net/npm/@emailjs/browser@4/dist/email.min.js"></script>
<script type="text/javascript">
    // Initialize EmailJS
    (function() {
        emailjs.init("YOUR_EMAILJS_PUBLIC_KEY"); // Replace with your EmailJS Public Key
    })();
</script>
```

**Note:** You'll need to get your EmailJS Public Key from your EmailJS dashboard.

---

## Step 2: Add Email Sending Functions to staff.js

Add these functions to your `staff.js` file. Add them after the `rejectVerification` function (around line 30800):

```javascript
  /**
   * Send approval email to customer using EmailJS
   */
  async sendApprovalEmail(customerEmail, customerName, staffName, staffRole, approvalDate) {
    try {
      if (!customerEmail || customerEmail.trim() === '' || customerEmail.includes('@agricart.local')) {
        console.log('⚠️ Skipping approval email - invalid or default email:', customerEmail);
        return;
      }

      console.log('📧 Sending approval email to:', customerEmail);

      const templateParams = {
        customer_name: customerName,
        staff_name: staffName,
        staff_role: staffRole,
        approval_date: approvalDate,
        show_approved: 'true',
        show_rejected: 'false',
        rejection_reason: '',
        rejection_date: ''
      };

      await emailjs.send('service_pd9ccy8', 'template_0azg7ul', templateParams);
      
      console.log('✅ Approval email sent successfully to:', customerEmail);
    } catch (error) {
      console.error('❌ Failed to send approval email:', error);
      // Don't throw - email failure shouldn't block approval
    }
  }

  /**
   * Send rejection email to customer using EmailJS
   */
  async sendRejectionEmail(customerEmail, customerName, staffName, staffRole, rejectionReason, rejectionDate) {
    try {
      if (!customerEmail || customerEmail.trim() === '' || customerEmail.includes('@agricart.local')) {
        console.log('⚠️ Skipping rejection email - invalid or default email:', customerEmail);
        return;
      }

      console.log('📧 Sending rejection email to:', customerEmail);

      const templateParams = {
        customer_name: customerName,
        staff_name: staffName,
        staff_role: staffRole,
        rejection_reason: rejectionReason || 'Your account verification was not approved.',
        rejection_date: rejectionDate,
        show_approved: 'false',
        show_rejected: 'true',
        approval_date: ''
      };

      await emailjs.send('service_pd9ccy8', 'template_0azg7ul', templateParams);
      
      console.log('✅ Rejection email sent successfully to:', customerEmail);
    } catch (error) {
      console.error('❌ Failed to send rejection email:', error);
      // Don't throw - email failure shouldn't block rejection
    }
  }
```

---

## Step 3: Modify approveVerification Function

Find the `approveVerification` function (around line 30510) and **ADD** the email sending call right after the notification is sent:

```javascript
        // Send notification to customer
        await this.sendCustomerNotification(id, {
          title: "Account Verified!",
          message:
            "You have been verified. Please log in your account. Enjoy shopping!",
          type: "verification",
        });

        // ADD THIS: Send approval email via EmailJS
        if (customerEmail && !customerEmail.includes('@agricart.local')) {
          const approvalDate = new Date(approvalTimestamp).toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric'
          });
          
          await this.sendApprovalEmail(
            customerEmail,
            verification.fullName || verification.name || 'Customer',
            staffName,
            staffRole,
            approvalDate
          );
        }
```

---

## Step 4: Modify rejectVerification Function

Find the `rejectVerification` function (around line 30698) and **ADD** the email sending call right after the notification is sent:

```javascript
        // Send notification to customer
        await this.sendCustomerNotification(id, {
          title: "Verification Failed",
          message: `Verification failed. Reason: ${reason}`,
          type: "verification",
        });

        // ADD THIS: Send rejection email via EmailJS
        const customerEmail = verification.email;
        if (customerEmail && !customerEmail.includes('@agricart.local')) {
          const rejectionDate = new Date(rejectionTimestamp).toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric'
          });
          
          await this.sendRejectionEmail(
            customerEmail,
            verification.fullName || verification.name || 'Customer',
            staffName,
            staffRole,
            reason,
            rejectionDate
          );
        }
```

---

## Step 5: Get Your EmailJS Public Key

1. Go to https://dashboard.emailjs.com/
2. Sign in to your EmailJS account
3. Go to **Account** → **General**
4. Copy your **Public Key**
5. Replace `YOUR_EMAILJS_PUBLIC_KEY` in the HTML script tag with your actual key

---

## Step 6: Test the Integration

1. **Register a test customer** account in the customer app
2. **Confirm their email** (existing confirmation flow)
3. **In staff dashboard**, approve the customer → Check email inbox
4. **Register another test customer**, then **reject** → Check email inbox

---

## Important Notes

- ✅ **In-app notifications still work** - EmailJS emails are sent IN ADDITION to in-app notifications
- ✅ **Default emails are skipped** - Emails with `@agricart.local` won't receive emails (they're generated defaults)
- ✅ **Email failures won't block approval/rejection** - If email fails, the approval/rejection still proceeds
- ✅ **Only valid email addresses** receive emails

---

## Troubleshooting

If emails don't send:

1. Check browser console for errors
2. Verify EmailJS Public Key is correct
3. Verify Service ID (`service_pd9ccy8`) and Template ID (`template_0azg7ul`) are correct
4. Check EmailJS dashboard for delivery logs
5. Make sure customer email is valid (not `@agricart.local`)

---

## Files Modified

- `webdashboards/staff-dashboard.html` - Add EmailJS script
- `webdashboards/staff.js` - Add email functions and integrate into approve/reject

