# EmailJS Separate Templates Setup

## Template Configuration

You now have **separate templates** for approval and rejection emails:

### Approval Email
- **Template ID**: `template_0azg7ul`
- **Service ID**: `service_pd9ccy8`
- **Use Case**: When staff/admin approves a customer account

### Rejection Email
- **Template ID**: `template_9wamzsp`
- **Service ID**: `service_pd9ccy8`
- **Use Case**: When staff/admin rejects a customer account

---

## Template Variables Required

### Approval Template (`template_0azg7ul`)

Required variables:
- `{{to_email}}` - Recipient email address
- `{{customer_name}}` - Customer's full name
- `{{staff_name}}` - Staff/Admin name
- `{{staff_role}}` - Staff/Admin role
- `{{approval_date}}` - Date when approved

### Rejection Template (`template_9wamzsp`)

Required variables:
- `{{to_email}}` - Recipient email address
- `{{customer_name}}` - Customer's full name
- `{{staff_name}}` - Staff/Admin name
- `{{staff_role}}` - Staff/Admin role
- `{{rejection_reason}}` - Reason for rejection
- `{{rejection_date}}` - Date when rejected

---

## Code Implementation

The code has been updated to:
- ✅ Use `template_0azg7ul` for approval emails
- ✅ Use `template_9wamzsp` for rejection emails
- ✅ Send appropriate variables for each template type
- ✅ Removed conditional display variables (not needed with separate templates)

---

## EmailJS Dashboard Setup

### For Approval Template (`template_0azg7ul`):

1. Open the template in EmailJS dashboard
2. Set **"To Email"** field to: `{{to_email}}`
3. Ensure template only contains approval content (no rejection section)
4. Save the template

### For Rejection Template (`template_9wamzsp`):

1. Create or open the rejection template in EmailJS dashboard
2. Set **"To Email"** field to: `{{to_email}}`
3. Add the rejection email HTML content
4. Ensure template only contains rejection content (no approval section)
5. Save the template

---

## Template Content

### Approval Template (`template_0azg7ul`)
- Should contain ONLY the approval section from `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`
- Remove the rejection section
- Remove conditional CSS (not needed)

### Rejection Template (`template_9wamzsp`)
- Should contain ONLY the rejection section from `CUSTOMER_APPROVAL_REJECTION_TEMPLATE.html`
- Remove the approval section
- Remove conditional CSS (not needed)

---

## Benefits of Separate Templates

✅ **Cleaner emails** - No conditional logic needed
✅ **Easier to manage** - Each template is independent
✅ **Better design control** - Can customize each template separately
✅ **No display issues** - No risk of showing wrong content

---

## Testing

1. **Test Approval**:
   - Approve a test customer
   - Check email - should only show approval content
   - Browser console: `✅ Approval email sent successfully`

2. **Test Rejection**:
   - Reject a test customer
   - Check email - should only show rejection content
   - Browser console: `✅ Rejection email sent successfully`

---

## Next Steps

1. ✅ Code is updated - uses separate template IDs
2. ⚠️ Set up `template_9wamzsp` in EmailJS dashboard:
   - Create the rejection template
   - Set "To Email" to `{{to_email}}`
   - Add rejection HTML content
   - Save

3. ⚠️ Update `template_0azg7ul` if needed:
   - Remove rejection section
   - Keep only approval content
   - Save

---

**Last Updated**: 2025-01-27

