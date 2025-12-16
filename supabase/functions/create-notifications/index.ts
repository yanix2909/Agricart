// Supabase Edge Function: create-notifications
// Creates notifications for customers with service role permissions
// This allows the staff dashboard to create notifications without RLS restrictions

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
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  try {
    // Get Supabase client with service role
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Supabase environment variables not configured");
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Parse request body
    let body: any;
    try {
      body = await req.json();
    } catch (e) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { title, message, type, productId, customerIds } = body;

    // Validate required fields
    if (!title || !message || !type) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: title, message, type" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Get customer IDs - either from request or fetch all customers
    let customers: Array<{ uid: string }> = [];
    
    if (customerIds && Array.isArray(customerIds) && customerIds.length > 0) {
      // Use provided customer IDs
      customers = customerIds.map((uid: string) => ({ uid }));
    } else {
      // Fetch all customers
      const { data: customersData, error: customersError } = await supabase
        .from("customers")
        .select("uid");

      if (customersError) {
        throw customersError;
      }

      if (!customersData || customersData.length === 0) {
        return new Response(
          JSON.stringify({ success: true, message: "No customers found", count: 0 }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      customers = customersData;
    }

    // Prepare notifications for all customers
    const timestamp = Date.now();
    const notifications = customers.map((customer) => {
      const notificationId = `product_${type}_${timestamp}_${Math.random().toString(36).substr(2, 9)}`;
      const notification: any = {
        id: notificationId,
        customer_id: customer.uid,
        title: title,
        message: message,
        type: type,
        timestamp: timestamp,
        is_read: false,
        fcm_sent: false, // Will be set to true by Edge Function after sending FCM
      };
      
      // Only add product_id if provided and column exists
      // (We'll add it conditionally to avoid errors if column doesn't exist yet)
      if (productId) {
        notification.product_id = productId;
      }
      
      return notification;
    });

    // Insert all notifications in batches
    const batchSize = 50;
    let totalInserted = 0;
    let errors: any[] = [];

    for (let i = 0; i < notifications.length; i += batchSize) {
      const batch = notifications.slice(i, i + batchSize);
      
      // Remove product_id if column doesn't exist (to avoid schema errors)
      // We'll try with product_id first, and if it fails, retry without it
      let batchToInsert = batch;
      let insertError: any = null;
      
      const { error: firstTryError } = await supabase
        .from("customer_notifications")
        .insert(batchToInsert);
      
      if (firstTryError && (firstTryError as any).message && (firstTryError as any).message.includes("product_id")) {
        // Column doesn't exist, remove product_id from all notifications
        console.log("⚠️ product_id column not found, inserting without it");
        batchToInsert = batch.map((notif: any) => {
          const { product_id, ...rest } = notif;
          return rest;
        });
        
        const { error: retryError } = await supabase
          .from("customer_notifications")
          .insert(batchToInsert);
        
        insertError = retryError;
      } else {
        insertError = firstTryError;
      }

      if (insertError) {
        console.error(`Error inserting notification batch ${i / batchSize + 1}:`, insertError);
        const errorMessage = insertError?.message || insertError?.toString() || String(insertError);
        errors.push({
          batch: i / batchSize + 1,
          error: errorMessage,
        });
      } else {
        totalInserted += batch.length;
        console.log(`✅ Inserted notification batch ${i / batchSize + 1} (${batch.length} notifications)`);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Created ${totalInserted} notifications`,
        count: totalInserted,
        errors: errors.length > 0 ? errors : undefined,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error: any) {
    console.error("Error creating notifications:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
