# EmailJS Gmail Authentication Fix - Step by Step

## Error You're Seeing
```
412 Gmail_API: Request had insufficient authentication scopes.
```

## Exact Steps to Fix

### Step 1: Open Email Services
1. In EmailJS Dashboard (https://dashboard.emailjs.com/)
2. Look at the **left sidebar menu**
3. Click on **"Email Services"** (or "Services")

### Step 2: Find Your Service
1. You should see a list of your email services
2. Look for service ID: **`service_pd9ccy8`**
3. OR look for a service that says "Gmail" or shows your Gmail email address
4. **Click on the service name** (or the service card/row) to open it

### Step 3: Re-authenticate Gmail
1. Inside the service details page, look for:
   - A button that says **"Reconnect"**
   - OR a button that says **"Authorize"**
   - OR a button that says **"Connect Gmail"**
   - OR a button that says **"Update Connection"**
   - OR a link that says **"Re-authenticate"**

2. **Click that button/link**

### Step 4: Grant Permissions
1. A popup window or new tab will open (Google sign-in)
2. Select the Gmail account you want to use
3. You'll see a page asking for permissions
4. **IMPORTANT**: Make sure to check/grant these permissions:
   - ✅ **"Send email on your behalf"**
   - ✅ **"See and download your email"** (if asked)
   - ✅ Any other email-related permissions

5. Click **"Allow"** or **"Continue"** button

### Step 5: Return to EmailJS
1. After granting permissions, you'll be redirected back to EmailJS
2. The service status should now show as **"Connected"** or **"Active"**
3. The error should disappear

---

## If You Don't See a Reconnect Button

### Option A: Delete and Recreate Service
1. In Email Services page
2. Find your Gmail service
3. Click the **3 dots menu** (⋮) or **gear icon** ⚙️ next to the service
4. Click **"Delete"** or **"Remove"**
5. Confirm deletion
6. Click **"+ Add New Service"** button
7. Select **"Gmail"** from the list
8. Click **"Connect Account"** or **"Authorize"**
9. Follow the Google authorization steps
10. Name your service (or keep default)
11. **IMPORTANT**: Copy the new **Service ID** (you might need to update it in code)

### Option B: Check Service Settings
1. Click on your service
2. Look for **"Settings"** tab
3. Look for **"Authorization"** section
4. Look for **"Reconnect"** or **"Update"** link there

---

## Visual Guide - What to Look For

When you open Email Services, you should see something like:

```
Email Services
─────────────────
📧 service_pd9ccy8 (Gmail)
   [Status: Connected/Error]
   [Reconnect Button]  ← CLICK THIS

📧 Other Service...
```

OR

```
Service Details: service_pd9ccy8
─────────────────────────────
Service Type: Gmail
Email: your-email@gmail.com
Status: Error ❌

[Reconnect Gmail Account]  ← CLICK THIS BUTTON
```

---

## After Re-authenticating

1. ✅ Service status should change to "Connected"
2. ✅ Error message should disappear
3. ✅ Test by approving a customer in staff dashboard
4. ✅ Check browser console for success message

---

## Still Having Issues?

If you still can't find the reconnect button:

1. **Take a screenshot** of your Email Services page
2. Look for any **red error messages** or **warning icons**
3. Check if there's a **"Settings"** or **"Configuration"** tab
4. Try clicking directly on the **service name/card** to see more options

---

## Alternative: Contact EmailJS Support

If nothing works:

1. Go to EmailJS Dashboard
2. Look for **"Support"** or **"Help"** link (usually at bottom)
3. Contact them about: "Gmail service insufficient authentication scopes error"
4. They can help you re-authenticate or fix the service

