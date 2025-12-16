// Supabase Edge Function: Delete Auth User
// This function deletes a user from Supabase Auth using Admin API
// Required for proper email reuse when customer accounts are removed

// @ts-ignore - Deno runtime types
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
// @ts-ignore - ESM module types
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// Declare Deno global for TypeScript
declare const Deno: {
  env: {
    get(key: string): string | undefined
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      status: 200,
      headers: corsHeaders,
    })
  }

  try {
    // Get request body
    let requestBody
    try {
      requestBody = await req.json()
    } catch (e) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const { uid } = requestBody

    if (!uid) {
      return new Response(
        JSON.stringify({ error: "User ID (uid) is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // Initialize Supabase Admin Client (with service role key)
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Supabase configuration missing" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    })

    try {
      // Use Supabase Admin API to delete the auth user
      // This properly deletes from auth.users and allows email reuse
      const { data, error } = await supabaseAdmin.auth.admin.deleteUser(uid)

      if (error) {
        console.error("Error deleting auth user:", error)
        // If user doesn't exist, that's okay - return success
        if (
          error.message?.includes("not found") ||
          error.message?.includes("does not exist")
        ) {
          return new Response(
            JSON.stringify({
              success: true,
              message: "Auth user not found (may have been already deleted)",
              deleted: false,
            }),
            {
              status: 200,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          )
        }
        throw error
      }

      console.log("✅ Auth user deleted successfully:", uid)

      return new Response(
        JSON.stringify({
          success: true,
          message: "Auth user deleted successfully. Email can now be reused.",
          deleted: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      )
    } catch (deleteError: any) {
      console.error("Error in auth user deletion:", deleteError)
      return new Response(
        JSON.stringify({
          success: false,
          error: deleteError.message || "Failed to delete auth user",
          message: "Failed to delete auth user from Supabase Auth",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      )
    }
  } catch (error: any) {
    console.error("Error in delete-auth-user:", error)
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  }
})


