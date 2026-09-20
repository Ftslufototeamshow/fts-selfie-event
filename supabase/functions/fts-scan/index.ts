import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clean(value: unknown, max = 80) {
  return String(value ?? "").trim().slice(0, max);
}

function cleanDevice(value: unknown) {
  const v = clean(value, 20).toLowerCase();
  return ["mobile", "tablet", "desktop"].includes(v) ? v : "unknown";
}

function cleanCountry(value: string | null) {
  const v = String(value || "").toUpperCase();
  return /^[A-Z]{2}$/.test(v) ? v : "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRole) throw new Error("Supabase server environment fehlt");

    const supabase = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json().catch(() => ({}));
    const eventToken = clean(body?.event_token, 120);
    const sessionId = clean(body?.session_id, 100);
    const deviceType = cleanDevice(body?.device_type);
    const browserLanguage = clean(body?.browser_language, 30);
    const browserTimezone = clean(body?.browser_timezone, 60);
    const countryCode = cleanCountry(req.headers.get("cf-ipcountry"));

    if (!eventToken) return json({ ok: false, error: "Event fehlt" }, 400);

    const { data: eventRows, error: eventError } = await supabase.rpc("fts_get_event", {
      p_event_token: eventToken,
    });
    if (eventError) throw eventError;

    const canonical = Array.isArray(eventRows) && eventRows[0]?.event_token
      ? String(eventRows[0].event_token)
      : "";
    if (!canonical) return json({ ok: false, error: "Event nicht gefunden" }, 404);

    const { error: insertError } = await supabase.from("fts_event_scans_v11").insert({
      event_token: canonical,
      device_type: deviceType,
      browser_language: browserLanguage,
      browser_timezone: browserTimezone,
      country_code: countryCode,
      session_id: sessionId,
    });

    if (insertError) {
      if (insertError.code === "23505") {
        return json({ ok: true, duplicate: true, country: countryCode || null });
      }
      throw insertError;
    }

    return json({ ok: true, duplicate: false, country: countryCode || null });
  } catch (err) {
    console.error(err);
    return json({ ok: false, error: String((err as any)?.message || err) }, 500);
  }
});
