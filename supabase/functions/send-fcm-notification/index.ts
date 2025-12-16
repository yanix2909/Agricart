// Supabase Edge Function: send-fcm-notification
// Sends FCM push notifications using Firebase Admin SDK
//
// This function is called by database triggers when a new notification is inserted.
// It sends the FCM notification and marks fcm_sent = true to prevent duplicates.
//
// ENV REQUIRED IN SUPABASE:
// - FIREBASE_SERVICE_ACCOUNT (JSON string of Firebase service account key)

// @ts-ignore - Deno runtime types
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno npm: specifier
import { createClient } from "npm:@supabase/supabase-js@2";

// Declare Deno global for TypeScript
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Initialize Firebase Admin SDK
async function initFirebaseAdmin() {
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  
  if (!serviceAccountJson) {
    const errorMessage = `
❌ FIREBASE_SERVICE_ACCOUNT environment variable is not configured!

To fix this:
1. Go to Firebase Console → Project Settings → Service Accounts
2. Generate a new private key (JSON file)
3. Go to Supabase Dashboard → Edge Functions → Secrets
4. Add secret: FIREBASE_SERVICE_ACCOUNT
5. Paste the entire JSON content as the value
6. Redeploy the Edge Function if needed

See SETUP_FIREBASE_SERVICE_ACCOUNT.md for detailed instructions.
    `.trim();
    throw new Error(errorMessage);
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(serviceAccountJson);
  } catch (e) {
    throw new Error("Invalid FIREBASE_SERVICE_ACCOUNT JSON format");
  }

  if (!serviceAccount.project_id) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT missing project_id");
  }

  // Import Firebase Admin SDK for Deno
  // Note: We'll use the Firebase REST API v1 instead of Admin SDK
  // because Deno doesn't have native support for firebase-admin
  return serviceAccount;
}

// Send FCM notification using Firebase REST API v1
async function sendFCMNotification(
  serviceAccount: any,
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
) {
  // Get access token using service account
  const tokenUrl = `https://oauth2.googleapis.com/token`;
  
  const jwt = await createJWT(serviceAccount);
  
  const tokenResponse = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    const errorText = await tokenResponse.text();
    throw new Error(`Failed to get access token: ${errorText}`);
  }

  const tokenData = await tokenResponse.json();
  const accessToken = tokenData.access_token;

  // Send FCM message using REST API v1
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
  
  // Build FCM message according to FCM v1 API specification
  // Optimized for Android 11+ (API 30+) and all screen sizes
  // CRITICAL: For force-stopped apps, we need to ensure FCM displays the notification automatically
  // IMPORTANT: priority must be at android level, NOT inside android.notification
  // For Android 11+ to display notifications when app is force-stopped, we need:
  // 1. The 'notification' field (title + body) - FCM will auto-display (CRITICAL for force-stopped apps)
  // 2. The 'android.notification.channelId' matching the app's channel
  // 3. High priority at android level
  // 4. Proper visibility and display settings for all screen sizes
  // 5. collapseKey to prevent Android from collapsing notifications
  // 6. fcmOptions to ensure delivery even when app is force-stopped
  const message = {
    message: {
      token: fcmToken,
      // The 'notification' field is CRITICAL - this tells FCM to automatically display
      // the notification on the device when the app is closed/force-stopped (Android 11+ requirement)
      // Without this field, Android will suppress notifications from force-stopped apps
      notification: {
        title: title,
        body: body,
        // Image URL (optional - for rich notifications on Android 11+)
        // image: "https://example.com/notification-image.jpg",
      },
      // Data payload for app to process when notification is tapped
      data: {
        ...data,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      // fcmOptions ensures delivery even when app is force-stopped
      fcmOptions: {
        // analytics_label helps track notification delivery
        analyticsLabel: `agricart_${data.type || "notification"}_${Date.now()}`,
      },
      android: {
        // NOTE: For force-stopped apps, "normal" priority sometimes works better than "high"
        // Some Android versions block "high" priority notifications for force-stopped apps
        // Try "normal" if "high" doesn't work for force-stopped apps
        priority: "high", // Priority at android level (required for high-priority messages on Android 11+)
        // Alternative: Use "normal" if high priority is blocked for force-stopped apps
        // priority: "normal", // Uncomment this and comment above if high priority doesn't work
        
        // collapseKey prevents Android from collapsing multiple notifications into one
        // Use orderId or notification type to group related notifications
        // NOTE: collapseKey must be at android level, not message level
        collapseKey: data.orderId || data.type || "agricart_notification",
        // CRITICAL: This ensures the notification is delivered even when app is force-stopped
        // Google Play Services will handle delivery, not the app itself
        notification: {
          // android.notification does NOT support priority field
          channelId: "agricart_customer_channel", // Must match channel created in app (Android 11+ requirement)
          sound: "default",
          visibility: "public", // Show on lock screen (Android 11+ requirement for all screen sizes)
          // Ensure notification is displayed prominently when app is closed/force-stopped (Android 11+)
          defaultSound: true, // Play default notification sound
          defaultVibrateTimings: true, // Use default vibration pattern
          notificationCount: 1, // Badge count
          // Ensure notification is clickable and shows in system tray
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          // Android 11+ specific settings for better display across all screen sizes
          tag: "agricart_notification", // Tag for notification grouping (Android 11+)
          sticky: false, // Not a sticky notification
        },
        ttl: "86400s", // 24 hours - ensures notification is delivered even if device is offline
        // Direct boot support for Android 11+ (ensures notifications work after reboot)
        directBootOk: true,
        // Ensure notification is delivered even when app is force-stopped
        // Google Play Services will handle delivery
      },
      apns: {
        headers: {
          "apns-priority": "10", // High priority for iOS
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            "content-available": 1,
            // Note: The top-level 'notification' field above is used for iOS display
            // FCM automatically converts it to APNs format
          },
        },
      },
    },
  };

  // Log the message structure for debugging (remove sensitive data)
  console.log("FCM message structure:", JSON.stringify({
    ...message,
    message: {
      ...message.message,
      token: message.message.token.substring(0, 20) + "...",
    }
  }, null, 2));

  const fcmResponse = await fetch(fcmUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });

  if (!fcmResponse.ok) {
    const errorText = await fcmResponse.text();
    throw new Error(`FCM API error: ${errorText}`);
  }

  return await fcmResponse.json();
}

// Create JWT for service account authentication
async function createJWT(serviceAccount: any): Promise<string> {
  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600, // 1 hour
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  // Encode header and payload
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));

  // Sign the token
  const signature = await signJWT(
    `${encodedHeader}.${encodedPayload}`,
    serviceAccount.private_key
  );

  return `${encodedHeader}.${encodedPayload}.${signature}`;
}

// Base64 URL encode
function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

// Sign JWT using RSA private key
async function signJWT(
  data: string,
  privateKeyPem: string
): Promise<string> {
  // Clean the PEM key
  const keyData = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");

  // Convert base64 to ArrayBuffer
  const binaryString = atob(keyData);
  const keyBuffer = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    keyBuffer[i] = binaryString.charCodeAt(i);
  }

  // Import the private key
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBuffer.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );

  // Sign the data
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(data)
  );

  // Convert to base64url
  const signatureArray = new Uint8Array(signature);
  let base64 = "";
  for (let i = 0; i < signatureArray.length; i++) {
    base64 += String.fromCharCode(signatureArray[i]);
  }
  
  return base64UrlEncode(base64);
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  try {
    // Get Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Supabase environment variables not configured");
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let body: any;
    try {
      body = await req.json();
      console.log("Received request body:", JSON.stringify(body, null, 2));
    } catch (e) {
      console.error("Error parsing request body:", e);
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body", details: String(e) }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Handle both webhook calls (with 'record') and direct calls (with customer_id, fcm_token, etc.)
    let notificationId: string | undefined;
    let customerId: string;
    let title: string;
    let notificationMessage: string;
    let type: string | undefined;
    let orderId: string | undefined;
    let fcm_sent: boolean | undefined;
    let fcmToken: string | undefined;
    let directCall = false;

    if (body.record) {
      // Webhook call from database trigger
      console.log("Processing webhook call (with record)");
      const { record } = body;
      notificationId = record.id;
      customerId = record.customer_id;
      title = record.title;
      notificationMessage = record.message;
      type = record.type;
      orderId = record.order_id;
      fcm_sent = record.fcm_sent;
    } else if (body.customer_id) {
      // Direct call from web dashboard
      console.log("Processing direct call (with customer_id)");
      directCall = true;
      customerId = body.customer_id;
      title = body.title;
      notificationMessage = body.body || body.message;
      type = body.data?.type || body.type;
      orderId = body.data?.orderId || body.data?.order_id || body.order_id;
      fcmToken = body.fcm_token; // Token provided directly
      
      // Validate required fields for direct calls
      if (!title || !notificationMessage) {
        console.error("Missing required fields for direct call:", { title, notificationMessage });
        return new Response(
          JSON.stringify({ 
            error: "Missing required fields",
            details: "Both 'title' and 'body' (or 'message') are required for direct calls"
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    } else {
      console.error("Invalid request format - no 'record' or 'customer_id' found");
      console.error("Request body keys:", Object.keys(body));
      return new Response(
        JSON.stringify({ 
          error: "Invalid request format. Expected 'record' (webhook) or 'customer_id' (direct call)",
          received: Object.keys(body)
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }
    
    console.log("Extracted data:", {
      customerId,
      title,
      notificationMessage: notificationMessage?.substring(0, 50) + "...",
      type,
      orderId,
      directCall,
      hasFcmToken: !!fcmToken
    });

    // Skip if FCM was already sent (only for webhook calls)
    if (!directCall && fcm_sent === true) {
      console.log(
        `Skipping notification ${notificationId} - FCM already sent`
      );
      return new Response(
        JSON.stringify({
          success: true,
          message: "FCM already sent, skipping",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Get FCM token - use provided token for direct calls, or fetch from database for webhook calls
    if (!fcmToken) {
      const { data: fcmTokenData, error: fcmError } = await supabase
        .from("customer_fcm_tokens")
        .select("fcm_token")
        .eq("customer_id", customerId)
        .order("last_used_at", { ascending: false })
        .limit(1)
        .single();

      if (fcmError || !fcmTokenData || !fcmTokenData.fcm_token) {
        console.log(
          `⚠️ No FCM token found for customer ${customerId}, skipping push notification`
        );
        console.log(
          `ℹ️ This is expected if the customer has logged out (FCM token is removed on logout)`
        );
        console.log(
          `ℹ️ Notifications are only sent to logged-in customers, regardless of app state (closed/force-stopped)`
        );
        
        // Mark as sent anyway to prevent retries (only for webhook calls)
        // This ensures we don't keep trying to send to logged-out users
        if (!directCall && notificationId) {
          await supabase
            .from("customer_notifications")
            .update({ fcm_sent: true })
            .eq("id", notificationId);
        }

        return new Response(
          JSON.stringify({
            success: false,
            message: "No FCM token found, notification not sent. Customer may be logged out.",
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      fcmToken = fcmTokenData.fcm_token;
    }

    // Initialize Firebase Admin
    let serviceAccount;
    try {
      serviceAccount = await initFirebaseAdmin();
    } catch (initError: any) {
      console.error("❌ Failed to initialize Firebase Admin:", initError.message);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Firebase configuration error",
          message: initError.message,
          help: "See SETUP_FIREBASE_SERVICE_ACCOUNT.md for setup instructions",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Prepare FCM data payload
    const fcmData: Record<string, string> = {
      type: type || "notification",
      customerId: customerId,
    };

    // Add optional fields if they exist
    if (notificationId) {
      fcmData.notificationId = notificationId;
    }
    if (orderId) {
      fcmData.orderId = orderId;
    }

    // Ensure fcmToken is defined before sending
    if (!fcmToken) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "FCM token is required but not found",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Send FCM notification
    try {
      const fcmResponse = await sendFCMNotification(
        serviceAccount,
        fcmToken,
        title,
        notificationMessage,
        fcmData
      );

      console.log(
        `✅ FCM notification sent successfully for notification ${notificationId || 'direct call'}`
      );
      console.log(`📱 FCM Response:`, JSON.stringify(fcmResponse, null, 2));
      console.log(`📱 FCM Message ID: ${fcmResponse?.name || 'N/A'}`);
      
      // Log important FCM response details
      if (fcmResponse?.name) {
        console.log(`✅ FCM message accepted by Google - should be delivered to device`);
        console.log(`📱 FCM Message ID: ${fcmResponse.name}`);
        console.log(`ℹ️ Troubleshooting: If notification doesn't appear on device:`);
        console.log(`   1. Check battery optimization: Settings → Apps → AgriCart → Battery → Unrestricted`);
        console.log(`   2. Check notification channel: Settings → Apps → AgriCart → Notifications → High importance`);
        console.log(`   3. Check Do Not Disturb: Settings → Notifications → Do Not Disturb → Add exception`);
        console.log(`   4. Ensure app was opened at least once after installation`);
        console.log(`   5. Check device-specific power management settings`);
      }

      // For direct calls, create notification in Supabase if it doesn't exist
      // This ensures notifications appear in the customer app's notification list
      if (directCall) {
        try {
          // Check for existing notification with same orderId + type to prevent duplicates
          if (orderId && type) {
            const { data: existingNotifications } = await supabase
              .from("customer_notifications")
              .select("id, fcm_sent")
              .eq("customer_id", customerId)
              .eq("order_id", orderId)
              .eq("type", type)
              .order("timestamp", { ascending: false })
              .limit(1);
            
            if (existingNotifications && existingNotifications.length > 0) {
              const existing = existingNotifications[0];
              console.log(`ℹ️ Notification already exists for order ${orderId} type ${type}, skipping insert`);
              // Update fcm_sent flag if needed
              if (!existing.fcm_sent) {
                await supabase
                  .from("customer_notifications")
                  .update({ fcm_sent: true })
                  .eq("id", existing.id);
              }
            } else {
              // Generate notification ID
              const finalNotificationId = notificationId || `${type}_${orderId}_${Date.now()}`;
              
              // Create notification in Supabase
              const notificationData: any = {
                id: finalNotificationId,
                customer_id: customerId,
                title: title,
                message: notificationMessage,
                type: type,
                timestamp: Date.now(),
                is_read: false,
                fcm_sent: true, // Mark as sent since we just sent FCM
                order_id: orderId,
              };
              
              const { error: insertError } = await supabase
                .from("customer_notifications")
                .insert(notificationData);
              
              if (insertError) {
                console.error("Error creating notification in Supabase:", insertError);
                // Don't fail the request - FCM was sent successfully
              } else {
                console.log(`✅ Created notification in Supabase: ${finalNotificationId}`);
              }
            }
          } else {
            // No orderId or type - create notification anyway (for non-order notifications)
            const finalNotificationId = notificationId || `notification_${customerId}_${Date.now()}`;
            
            const notificationData: any = {
              id: finalNotificationId,
              customer_id: customerId,
              title: title,
              message: notificationMessage,
              type: type || "notification",
              timestamp: Date.now(),
              is_read: false,
              fcm_sent: true,
            };
            
            if (orderId) {
              notificationData.order_id = orderId;
            }
            
            const { error: insertError } = await supabase
              .from("customer_notifications")
              .insert(notificationData);
            
            if (insertError) {
              console.error("Error creating notification in Supabase:", insertError);
            } else {
              console.log(`✅ Created notification in Supabase: ${finalNotificationId}`);
            }
          }
        } catch (createError) {
          console.error("Error creating notification in Supabase for direct call:", createError);
          // Don't fail the request - FCM was sent successfully
        }
      } else {
        // Mark notification as sent (for webhook calls)
        if (notificationId) {
          const { error: updateError } = await supabase
            .from("customer_notifications")
            .update({ fcm_sent: true })
            .eq("id", notificationId);

          if (updateError) {
            console.error("Error updating fcm_sent flag:", updateError);
          }
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: "FCM notification sent successfully",
          fcmResponse,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    } catch (fcmError: any) {
      console.error("Error sending FCM notification:", fcmError);

      // Handle invalid token errors - mark as sent to prevent retries (only for webhook calls)
      if (
        fcmError.message?.includes("invalid-registration-token") ||
        fcmError.message?.includes("registration-token-not-registered")
      ) {
        if (!directCall && notificationId) {
          await supabase
            .from("customer_notifications")
            .update({ fcm_sent: true })
            .eq("id", notificationId);
        }

        // Remove invalid token
        await supabase
          .from("customer_fcm_tokens")
          .delete()
          .eq("fcm_token", fcmToken);
      }

      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to send FCM notification",
          message: fcmError.message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }
  } catch (err: any) {
    console.error("send-fcm-notification error:", err);
    return new Response(
      JSON.stringify({
        error: err?.message || "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

