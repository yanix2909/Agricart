# AgriCart - Supabase Email Configuration Templates

## How to Configure Email Templates in Supabase

1. Go to your **Supabase Dashboard**
2. Navigate to **Authentication** → **Email Templates**
3. Select the template you want to customize
4. Copy and paste the appropriate template below
5. Click **Save**

---

## 1. Confirmation Email Template (Sign Up)

**Template Name:** `Confirm signup`

**Subject Line:**
```
Welcome to AgriCart - Confirm Your Email Address
```

**Email Body (HTML):**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Confirm Your Email - AgriCart</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f5f5f5; padding: 40px 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); overflow: hidden;">
                    <!-- Header with Green Background -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #315E26 0%, #4A7C3A 100%); padding: 50px 30px; text-align: center;">
                            <!-- Logos Side by Side -->
                            <table cellpadding="0" cellspacing="0" style="margin: 0 auto 20px auto;">
                                <tr>
                                    <td style="padding: 0 10px; text-align: center; vertical-align: middle;">
                                        <img src="https://afkwexvvuxwbpioqnelp.supabase.co/storage/v1/object/public/email_assets/agricart_logo.png" alt="AgriCart Logo" style="width: 80px; height: 80px; border-radius: 50%; background-color: #FFFEF9; padding: 5px; box-shadow: 0 4px 12px rgba(0,0,0,0.2); object-fit: contain;" />
                                    </td>
                                    <td style="padding: 0 10px; text-align: center; vertical-align: middle;">
                                        <img src="https://afkwexvvuxwbpioqnelp.supabase.co/storage/v1/object/public/email_assets/calcoa_logo.png" alt="CALCOA Logo" style="width: 80px; height: 80px; border-radius: 50%; background-color: #FFFEF9; padding: 5px; box-shadow: 0 4px 12px rgba(0,0,0,0.2); object-fit: contain;" />
                                    </td>
                                </tr>
                            </table>
                            <h1 style="color: #FFFEF9; margin: 0; font-size: 32px; font-weight: 700; letter-spacing: 0.5px;">
                                AgriCart
                            </h1>
                            <p style="color: #FFF8E1; margin: 12px 0 0 0; font-size: 15px; font-weight: 500; opacity: 0.95;">
                                Cabintan Livelihood Community Agriculture – Cooperative (CALCOA)
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Main Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <h2 style="color: #1b370c; margin: 0 0 16px 0; font-size: 24px; font-weight: 600;">
                                Welcome to AgriCart! 🎉
                            </h2>
                            
                            <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 24px 0;">
                                Thank you for registering with AgriCart, your trusted platform for fresh agricultural products directly from local farmers.
                            </p>
                            
                            <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 24px 0;">
                                To complete your registration and start shopping, please confirm your email address by clicking the button below:
                            </p>
                            
                            <!-- Confirmation Button -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="margin: 32px 0;">
                                <tr>
                                    <td align="center">
                                        <a href="{{ .ConfirmationURL }}" 
                                           style="display: inline-block; background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); color: #ffffff; text-decoration: none; padding: 16px 48px; border-radius: 10px; font-size: 16px; font-weight: 700; box-shadow: 0 4px 12px rgba(47,122,62,0.3);">
                                            Confirm Email Address
                                        </a>
                                    </td>
                                </tr>
                            </table>
                            
                            <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 24px 0 0 0; padding: 16px; background-color: #f8f9fa; border-left: 4px solid #2f7a3e; border-radius: 4px;">
                                <strong>⏱️ Note:</strong> This confirmation link will expire in 24 hours for security purposes.
                            </p>
                            
                            <!-- Alternative Link -->
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 24px 0 0 0;">
                                If the button doesn't work, copy and paste this link into your browser:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; word-break: break-all; margin: 8px 0 0 0;">
                                {{ .ConfirmationURL }}
                            </p>
                        </td>
                    </tr>
                    
                    <!-- What's Next Section -->
                    <tr>
                        <td style="padding: 0 30px 40px 30px;">
                            <div style="background-color: #eaf3ec; padding: 24px; border-radius: 8px; margin-top: 16px;">
                                <h3 style="color: #1b370c; margin: 0 0 16px 0; font-size: 18px; font-weight: 600;">
                                    What's Next?
                                </h3>
                                <ul style="color: #333333; font-size: 14px; line-height: 1.8; margin: 0; padding-left: 20px;">
                                    <li>Your account will be reviewed by our AgriCart staff</li>
                                    <li>You'll receive a notification once approved (usually within 24-48 hours)</li>
                                    <li>After approval, you can start browsing and ordering fresh products</li>
                                    <li>Support local farmers and enjoy quality produce!</li>
                                </ul>
                            </div>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8f9fa; padding: 24px 30px; border-top: 1px solid #e0e0e0;">
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 0 0 12px 0;">
                                <strong>Need help?</strong> Contact our support team:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 4px 0;">
                                📧 Email: <a href="mailto:agricartcalcoa@gmail.com" style="color: #2f7a3e; text-decoration: none;">agricartcalcoa@gmail.com</a>
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 16px 0;">
                                📱 Phone: <a href="tel:+639502588355" style="color: #2f7a3e; text-decoration: none;">09502588355</a>
                            </p>
                            
                            <p style="color: #999999; font-size: 12px; line-height: 1.5; margin: 16px 0 0 0;">
                                If you didn't create an account with AgriCart, please ignore this email or contact support if you have concerns.
                            </p>
                            
                            <p style="color: #999999; font-size: 12px; margin: 16px 0 0 0; text-align: center;">
                                © 2025 AgriCart. All rights reserved.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
```

---

## 2. Password Reset Email Template

**Template Name:** `Reset password`

**Subject Line:**
```
Reset Your AgriCart Password
```

**Email Body (HTML):**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reset Your Password - AgriCart</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f5f5f5; padding: 40px 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); overflow: hidden;">
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); padding: 40px 30px; text-align: center;">
                            <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: 700;">
                                🌾 AgriCart
                            </h1>
                            <p style="color: #ffffff; margin: 8px 0 0 0; font-size: 14px; opacity: 0.95;">
                                Fresh from Farm to Your Table
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Main Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <h2 style="color: #1b370c; margin: 0 0 16px 0; font-size: 24px; font-weight: 600;">
                                Reset Your Password 🔐
                            </h2>
                            
                            <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 24px 0;">
                                We received a request to reset your AgriCart account password. Click the button below to create a new password:
                            </p>
                            
                            <!-- Reset Button -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="margin: 32px 0;">
                                <tr>
                                    <td align="center">
                                        <a href="{{ .ConfirmationURL }}" 
                                           style="display: inline-block; background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); color: #ffffff; text-decoration: none; padding: 16px 48px; border-radius: 10px; font-size: 16px; font-weight: 700; box-shadow: 0 4px 12px rgba(47,122,62,0.3);">
                                            Reset Password
                                        </a>
                                    </td>
                                </tr>
                            </table>
                            
                            <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 24px 0 0 0; padding: 16px; background-color: #fff3cd; border-left: 4px solid #ff9800; border-radius: 4px;">
                                <strong>⚠️ Important:</strong> This password reset link will expire in 1 hour. If you didn't request a password reset, you can safely ignore this email.
                            </p>
                            
                            <!-- Alternative Link -->
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 24px 0 0 0;">
                                If the button doesn't work, copy and paste this link into your browser:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; word-break: break-all; margin: 8px 0 0 0;">
                                {{ .ConfirmationURL }}
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Security Tips -->
                    <tr>
                        <td style="padding: 0 30px 40px 30px;">
                            <div style="background-color: #eaf3ec; padding: 24px; border-radius: 8px; margin-top: 16px;">
                                <h3 style="color: #1b370c; margin: 0 0 16px 0; font-size: 18px; font-weight: 600;">
                                    Password Security Tips 🛡️
                                </h3>
                                <ul style="color: #333333; font-size: 14px; line-height: 1.8; margin: 0; padding-left: 20px;">
                                    <li>Use a strong, unique password</li>
                                    <li>Combine uppercase, lowercase, numbers, and symbols</li>
                                    <li>Avoid using personal information</li>
                                    <li>Don't share your password with anyone</li>
                                </ul>
                            </div>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8f9fa; padding: 24px 30px; border-top: 1px solid #e0e0e0;">
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 0 0 12px 0;">
                                <strong>Need help?</strong> Contact our support team:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 4px 0;">
                                📧 Email: <a href="mailto:agricartcalcoa@gmail.com" style="color: #2f7a3e; text-decoration: none;">agricartcalcoa@gmail.com</a>
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 16px 0;">
                                📱 Phone: <a href="tel:+639502588355" style="color: #2f7a3e; text-decoration: none;">09502588355</a>
                            </p>
                            
                            <p style="color: #999999; font-size: 12px; margin: 16px 0 0 0; text-align: center;">
                                © 2025 AgriCart. All rights reserved.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
```

---

## 3. Magic Link Email Template

**Template Name:** `Magic Link`

**Subject Line:**
```
Sign in to AgriCart
```

**Email Body (HTML):**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sign In to AgriCart</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f5f5f5; padding: 40px 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); overflow: hidden;">
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); padding: 40px 30px; text-align: center;">
                            <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: 700;">
                                🌾 AgriCart
                            </h1>
                            <p style="color: #ffffff; margin: 8px 0 0 0; font-size: 14px; opacity: 0.95;">
                                Fresh from Farm to Your Table
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Main Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <h2 style="color: #1b370c; margin: 0 0 16px 0; font-size: 24px; font-weight: 600;">
                                Sign In to Your Account ✨
                            </h2>
                            
                            <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 24px 0;">
                                Click the button below to sign in to your AgriCart account:
                            </p>
                            
                            <!-- Sign In Button -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="margin: 32px 0;">
                                <tr>
                                    <td align="center">
                                        <a href="{{ .ConfirmationURL }}" 
                                           style="display: inline-block; background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); color: #ffffff; text-decoration: none; padding: 16px 48px; border-radius: 10px; font-size: 16px; font-weight: 700; box-shadow: 0 4px 12px rgba(47,122,62,0.3);">
                                            Sign In to AgriCart
                                        </a>
                                    </td>
                                </tr>
                            </table>
                            
                            <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 24px 0 0 0; padding: 16px; background-color: #fff3cd; border-left: 4px solid #ff9800; border-radius: 4px;">
                                <strong>⚠️ Security:</strong> This sign-in link will expire in 1 hour. If you didn't request this, please ignore this email.
                            </p>
                            
                            <!-- Alternative Link -->
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 24px 0 0 0;">
                                If the button doesn't work, copy and paste this link into your browser:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; word-break: break-all; margin: 8px 0 0 0;">
                                {{ .ConfirmationURL }}
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8f9fa; padding: 24px 30px; border-top: 1px solid #e0e0e0;">
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 0 0 12px 0;">
                                <strong>Need help?</strong> Contact our support team:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 4px 0;">
                                📧 Email: <a href="mailto:agricartcalcoa@gmail.com" style="color: #2f7a3e; text-decoration: none;">agricartcalcoa@gmail.com</a>
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 16px 0;">
                                📱 Phone: <a href="tel:+639502588355" style="color: #2f7a3e; text-decoration: none;">09502588355</a>
                            </p>
                            
                            <p style="color: #999999; font-size: 12px; margin: 16px 0 0 0; text-align: center;">
                                © 2025 AgriCart. All rights reserved.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
```

---

## 4. Email Change Confirmation Template

**Template Name:** `Change Email Address`

**Subject Line:**
```
Confirm Your New Email Address - AgriCart
```

**Email Body (HTML):**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Confirm Email Change - AgriCart</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f5f5f5; padding: 40px 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); overflow: hidden;">
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); padding: 40px 30px; text-align: center;">
                            <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: 700;">
                                🌾 AgriCart
                            </h1>
                            <p style="color: #ffffff; margin: 8px 0 0 0; font-size: 14px; opacity: 0.95;">
                                Fresh from Farm to Your Table
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Main Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <h2 style="color: #1b370c; margin: 0 0 16px 0; font-size: 24px; font-weight: 600;">
                                Confirm Your Email Change 📧
                            </h2>
                            
                            <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 24px 0;">
                                We received a request to change the email address for your AgriCart account. To complete this change, please confirm your new email address:
                            </p>
                            
                            <!-- Confirm Button -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="margin: 32px 0;">
                                <tr>
                                    <td align="center">
                                        <a href="{{ .ConfirmationURL }}" 
                                           style="display: inline-block; background: linear-gradient(135deg, #2f7a3e 0%, #3c9a4e 100%); color: #ffffff; text-decoration: none; padding: 16px 48px; border-radius: 10px; font-size: 16px; font-weight: 700; box-shadow: 0 4px 12px rgba(47,122,62,0.3);">
                                            Confirm New Email
                                        </a>
                                    </td>
                                </tr>
                            </table>
                            
                            <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 24px 0 0 0; padding: 16px; background-color: #fff3cd; border-left: 4px solid #ff9800; border-radius: 4px;">
                                <strong>⚠️ Security:</strong> If you didn't request this email change, please contact support immediately at calcoacoop@gmail.com
                            </p>
                            
                            <!-- Alternative Link -->
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 24px 0 0 0;">
                                If the button doesn't work, copy and paste this link into your browser:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; word-break: break-all; margin: 8px 0 0 0;">
                                {{ .ConfirmationURL }}
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8f9fa; padding: 24px 30px; border-top: 1px solid #e0e0e0;">
                            <p style="color: #666666; font-size: 13px; line-height: 1.6; margin: 0 0 12px 0;">
                                <strong>Need help?</strong> Contact our support team:
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 4px 0;">
                                📧 Email: <a href="mailto:agricartcalcoa@gmail.com" style="color: #2f7a3e; text-decoration: none;">agricartcalcoa@gmail.com</a>
                            </p>
                            <p style="color: #2f7a3e; font-size: 13px; margin: 0 0 16px 0;">
                                📱 Phone: <a href="tel:+639502588355" style="color: #2f7a3e; text-decoration: none;">09502588355</a>
                            </p>
                            
                            <p style="color: #999999; font-size: 12px; margin: 16px 0 0 0; text-align: center;">
                                © 2025 AgriCart. All rights reserved.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
```

---

## Additional Supabase Settings

### 1. Enable Email Confirmations

In **Supabase Dashboard** → **Authentication** → **Settings**:

- ✅ **Enable email confirmations** - Toggle to ON
- **Confirmation URL**: Set your redirect URL (e.g., `myapp://callback` for mobile)
- **Time to confirm**: 24 hours (default is good)

### 2. SMTP Configuration (Optional - for custom email domain)

If you want to use your own email domain instead of Supabase's default:

1. Go to **Settings** → **Auth** → **SMTP Settings**
2. Configure your SMTP provider (e.g., Gmail, SendGrid, AWS SES)
3. Test the configuration

### 3. Redirect URLs Configuration

In **Authentication** → **URL Configuration**:

- Add your app's deep link scheme: `agricart://`
- Add web redirect URLs if needed
- For Flutter mobile: `agricart://callback`

---

## Testing Email Confirmations

### Test the confirmation flow:

1. Register a new customer account
2. Check the email inbox for confirmation email
3. Click the confirmation link
4. Verify the user can now log in
5. Test resend confirmation button on login screen

### Common Issues:

- **Emails going to spam**: Configure SPF/DKIM records or use custom SMTP
- **Links not working**: Check redirect URL configuration in Supabase
- **Emails not sending**: Verify Supabase project is not on free tier limits

---

## Variables Available in Templates

Supabase provides these variables for email templates:

- `{{ .ConfirmationURL }}` - The confirmation/reset link
- `{{ .Token }}` - The confirmation token (if needed separately)
- `{{ .TokenHash }}` - Hashed token
- `{{ .SiteURL }}` - Your site URL from settings
- `{{ .Email }}` - User's email address

---

## Support Contact Information

Update these in the templates as needed:

- **Support Email**: calcoacoop@gmail.com
- **Support Phone**: +63 123 456 7890
- **Company Name**: AgriCart
- **Tagline**: Fresh from Farm to Your Table

---

**Last Updated**: November 26, 2024

