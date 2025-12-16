// Serverless function to send FCM notifications using HTTP v1 API
// Deploy this to Vercel, Netlify, or any serverless platform (FREE)

const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');

// Initialize Firebase Admin (only once)
let messaging = null;

function initFirebase() {
  if (messaging) return messaging;
  
  try {
    // Initialize with service account from environment variable
    // The service account JSON should be stored as an environment variable
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || '{}');
    
    if (!serviceAccount.project_id) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT environment variable not set');
    }
    
    initializeApp({
      credential: cert(serviceAccount)
    });
    
    messaging = getMessaging();
    return messaging;
  } catch (error) {
    console.error('Error initializing Firebase Admin:', error);
    throw error;
  }
}

// Main handler function (for Vercel/Netlify)
module.exports = async (req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  
  try {
    const { fcmToken, title, body, data } = req.body;
    
    if (!fcmToken) {
      return res.status(400).json({ error: 'FCM token is required' });
    }
    
    if (!title || !body) {
      return res.status(400).json({ error: 'Title and body are required' });
    }
    
    // Initialize Firebase
    const messagingInstance = initFirebase();
    
    // Build FCM message
    const message = {
      token: fcmToken,
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'agricart_customer_channel',
          sound: 'default'
        }
      },
      apns: {
        headers: {
          'apns-priority': '10'
        },
        payload: {
          aps: {
            sound: 'default',
            badge: 1
          }
        }
      }
    };
    
    // Send FCM notification
    const response = await messagingInstance.send(message);
    
    console.log('✅ FCM notification sent successfully:', response);
    
    return res.status(200).json({ 
      success: true, 
      messageId: response 
    });
    
  } catch (error) {
    console.error('❌ Error sending FCM notification:', error);
    
    // Handle specific FCM errors
    if (error.code === 'messaging/invalid-registration-token') {
      return res.status(400).json({ 
        error: 'Invalid FCM token',
        code: error.code 
      });
    }
    
    if (error.code === 'messaging/registration-token-not-registered') {
      return res.status(400).json({ 
        error: 'FCM token not registered',
        code: error.code 
      });
    }
    
    return res.status(500).json({ 
      error: 'Failed to send notification',
      message: error.message 
    });
  }
};

