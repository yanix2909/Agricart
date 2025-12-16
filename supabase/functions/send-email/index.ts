// Supabase Edge Function: send-email
// Sends an HTML email using Resend.
//
// Expected JSON body:
// {
//   "to": "user@example.com",
//   "subject": "Subject text",
//   "html": "<html>...</html>"
// }
//
// ENV REQUIRED IN SUPABASE:
// - RESEND_API_KEY

// @ts-ignore - Deno runtime types
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

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
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  try {
    let body: any;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { to, subject, html } = body ?? {};
    if (!to || !subject || !html) {
      return new Response(
        JSON.stringify({
          error: "Fields 'to', 'subject', and 'html' are required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
    if (!resendApiKey) {
      return new Response(
        JSON.stringify({
          error:
            "Email provider API key (RESEND_API_KEY) is not configured in environment",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Call Resend API
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        // Use Resend's default verified sender for simplicity.
        // You can change this to your own verified domain later.
        from: "onboarding@resend.dev",
        to: [to],
        subject,
        html,
      }),
    });

    const result = await resp.json().catch(() => ({}));

    if (!resp.ok) {
      console.error("Resend error:", resp.status, result);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to send email",
          providerStatus: resp.status,
          providerResponse: result,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: "Email sent successfully",
        providerResponse: result,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err: any) {
    console.error("send-email error:", err);
    return new Response(
      JSON.stringify({
        error: err?.message || "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});