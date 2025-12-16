# FCM Serverless Function Setup

This is a **FREE** serverless function that sends FCM push notifications using the HTTP v1 API. It can be deployed to Vercel, Netlify, or any serverless platform.

## Why This is Needed

Since the Legacy FCM API is deprecated and disabled, we need to use the HTTP v1 API, which requires:
- Service account authentication (can't be done from browser)
- Server-side code

This serverless function solves that problem and is **completely FREE**.

## Setup Steps

### 1. Get Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **agricart-53501**
3. Click the **gear icon (⚙️)** → **Project settings**
4. Go to **Service accounts** tab
5. Click **"Generate new private key"**
6. Download the JSON file (keep it secure!)

### 2. Deploy to Vercel (Recommended - FREE)

**Option A: Vercel (Easiest)**

1. Install Vercel CLI:
   ```bash
   npm i -g vercel
   ```

2. Navigate to the `fcm-serverless` folder:
   ```bash
   cd fcm-serverless
   ```

3. Deploy:
   ```bash
   vercel
   ```

4. Set environment variable:
   - Go to [Vercel Dashboard](https://vercel.com/dashboard)
   - Select your project
   - Go to **Settings** → **Environment Variables**
   - Add: `FIREBASE_SERVICE_ACCOUNT` = (paste the entire JSON content from step 1)

5. Redeploy to apply environment variable:
   ```bash
   vercel --prod
   ```

6. Copy the deployment URL (e.g., `https://your-project.vercel.app/send-fcm`)

### 3. Alternative: Deploy to Netlify

**Option B: Netlify (Alternative)**

1. Install Netlify CLI:
   ```bash
   npm i -g netlify-cli
   ```

2. Navigate to the `fcm-serverless` folder:
   ```bash
   cd fcm-serverless
   ```

3. Deploy:
   ```bash
   netlify deploy --prod
   ```

4. Set environment variable:
   - Go to [Netlify Dashboard](https://app.netlify.com/)
   - Select your site
   - Go to **Site settings** → **Environment variables**
   - Add: `FIREBASE_SERVICE_ACCOUNT` = (paste the entire JSON content from step 1)

5. Redeploy to apply environment variable

6. Copy the deployment URL (e.g., `https://your-site.netlify.app/send-fcm`)

### 4. Update Web Dashboard

1. Open `webdashboards/firebase-config.js`
2. Add the serverless function URL:
   ```javascript
   const FCM_SERVERLESS_URL = 'https://your-project.vercel.app/send-fcm';
   ```

3. The web dashboard will automatically use this URL to send notifications.

## Testing

After deployment, test the function:
```bash
curl -X POST https://your-project.vercel.app/send-fcm \
  -H "Content-Type: application/json" \
  -d '{
    "fcmToken": "YOUR_FCM_TOKEN",
    "title": "Test",
    "body": "Test notification",
    "data": {"type": "test"}
  }'
```

## Cost

- **Vercel**: FREE (up to 100GB bandwidth/month)
- **Netlify**: FREE (up to 100GB bandwidth/month)
- **Firebase**: FREE (FCM is free on Spark plan)

## Security

- The service account key is stored as an environment variable (secure)
- The function URL should be kept private (don't expose it publicly)
- Consider adding API key authentication for extra security

