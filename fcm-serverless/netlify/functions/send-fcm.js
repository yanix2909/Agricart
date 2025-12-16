// Netlify serverless function to send FCM notifications
const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');

let messaging = null;

function initFirebase() {
  if (messaging) return messaging;
  
  try {
    const envValue = process.env.FIREBASE_SERVICE_ACCOUNT;
    
    if (!envValue || envValue.trim() === '') {
      throw new Error('FIREBASE_SERVICE_ACCOUNT environment variable is not set');
    }
    
    // Try to parse the JSON - handle cases where it might be double-quoted or have extra whitespace
    let serviceAccount;
    try {
      // Remove any surrounding quotes if present
      const cleanedValue = envValue.trim().replace(/^["']|["']$/g, '');
      serviceAccount = JSON.parse(cleanedValue);
    } catch (parseError) {
      console.error('JSON Parse Error:', parseError.message);
      console.error('First 100 chars of env value:', envValue.substring(0, 100));
      throw new Error(`Invalid JSON in FIREBASE_SERVICE_ACCOUNT: ${parseError.message}. Make sure you pasted the entire JSON file content without quotes.`);
    }
    
    if (!serviceAccount || typeof serviceAccount !== 'object') {
      throw new Error('FIREBASE_SERVICE_ACCOUNT must be a valid JSON object');
    }
    
    if (!serviceAccount.project_id) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT is missing project_id. Make sure you pasted the complete service account JSON.');
    }
    
    if (!serviceAccount.private_key) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT is missing private_key. Make sure you pasted the complete service account JSON.');
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

exports.handler = async (event, context) => {
  // Enable CORS
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
  
  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 200,
      headers,
      body: ''
    };
  }
  
  if (event.httpMethod !== 'POST') {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: 'Method not allowed' })
    };
  }
  
  try {
    const { fcmToken, title, body, data } = JSON.parse(event.body || '{}');
    
    if (!fcmToken) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'FCM token is required' })
      };
    }
    
    if (!title || !body) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'Title and body are required' })
      };
    }
    
    const messagingInstance = initFirebase();
    
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
        priority: 'high', // Required for background delivery on Android 11+
        notification: {
          channelId: 'agricart_customer_channel',
          sound: 'default',
          priority: 'high',
          visibility: 'public',
        },
        // Additional settings for Android 11+ when app is completely closed
        ttl: 86400000, // 24 hours - how long the message should be kept if device is offline
      },
      apns: {
        headers: {
          'apns-priority': '10'
        },
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            contentAvailable: 1
          }
        }
      }
    };
    
    const response = await messagingInstance.send(message);
    
    console.log('✅ FCM notification sent successfully:', response);
    
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ 
        success: true, 
        messageId: response 
      })
    };
    
  } catch (error) {
    console.error('❌ Error sending FCM notification:', error);
    
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ 
        error: 'Failed to send notification',
        message: error.message 
      })
    };
  }
};

