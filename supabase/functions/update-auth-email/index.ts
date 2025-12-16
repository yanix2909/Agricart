// Supabase Edge Function: Update Auth User Email
// This function updates a user's email in Supabase Auth using the Admin API.
// It is used when customers change their email so that:
// - The old email is notified about the change
// - The auth.users row is updated to the new email
// - The old email becomes free for reuse

// @ts-ignore - Deno runtime types
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - ESM module types
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  try {
    // Get request body
    let requestBody;
    try {
      requestBody = await req.json();
    } catch (_e) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { uid, newEmail } = requestBody ?? {};

    if (!uid) {
      return new Response(
        JSON.stringify({ error: "User ID (uid) is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!newEmail || typeof newEmail !== "string") {
      return new Response(
        JSON.stringify({ error: "New email is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Initialize Supabase Admin Client (with service role key)
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Supabase configuration missing" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    try {
      // First, get the current user to retrieve the old email
      const { data: currentUser, error: getUserError } =
        await supabaseAdmin.auth.admin.getUserById(uid);

      if (getUserError) {
        console.error("Error getting current user:", getUserError);
        throw getUserError;
      }

      const oldEmail = currentUser?.user?.email;

      if (!oldEmail) {
        throw new Error("Current user email not found");
      }

      const normalizedOld = oldEmail.toLowerCase();
      const normalizedNew = newEmail.toLowerCase();

      if (normalizedOld === normalizedNew) {
        return new Response(
          JSON.stringify({
            success: true,
            message: "Email is already set to this value",
            updated: false,
            newEmail,
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      console.log(
        `📧 Email change request: ${normalizedOld} -> ${normalizedNew}`,
      );

      // IMPORTANT: Supabase Admin API updateUserById will:
      // 1. Send a notification email to the OLD email BEFORE updating
      // 2. Update the email in auth.users to the new email
      // 3. Free the old email for reuse
      //
      // We set email_confirm: true to keep the session usable and avoid
      // forcing the customer to click a new confirmation link again.

      const { data, error } =
        await supabaseAdmin.auth.admin.updateUserById(uid, {
          email: normalizedNew,
          email_confirm: true,
        });

      if (error) {
        console.error("Error updating auth user email:", error);
        throw error;
      }

      console.log("✅ Auth user email updated successfully");
      console.log(`📧 New email is now active: ${normalizedNew}`);
      console.log(
        `📧 Old email (${normalizedOld}) is now freed up and can be reused`,
      );

      return new Response(
        JSON.stringify({
          success: true,
          message:
            "Auth user email updated successfully. Old email can now be reused.",
          updated: true,
          newEmail: normalizedNew,
          data,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    } catch (updateError: any) {
      console.error("Error in auth user email update:", updateError);
      return new Response(
        JSON.stringify({
          success: false,
          error: updateError?.message || "Failed to update auth user email",
          message: "Failed to update email in Supabase Auth",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
  } catch (error: any) {
    console.error("Error in update-auth-email:", error);
    return new Response(
      JSON.stringify({
        error: error?.message || "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});


