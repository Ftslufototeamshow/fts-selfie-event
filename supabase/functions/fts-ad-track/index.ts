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

function clean(value: unknown, max = 500) {
  return String(value ?? "").trim().slice(0, max);
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
    const adKey = clean(body?.ad_key, 500);
    const action = clean(body?.action, 10).toLowerCase();
    const sessionId = clean(body?.session_id, 100);

    if (!eventToken || !adKey || !["view", "click"].includes(action)) {
      return json({ ok: false, error: "Ungültige Werbe-Statistikdaten" }, 400);
    }

    const { data: eventRows, error: eventError } = await supabase.rpc("fts_get_event", {
      p_event_token: eventToken,
    });
    if (eventError) throw eventError;

    const canonical = Array.isArray(eventRows) && eventRows[0]?.event_token
      ? String(eventRows[0].event_token)
      : "";
    if (!canonical) return json({ ok: false, error: "Event nicht gefunden" }, 404);

    const { data: adRows, error: adError } = await supabase.rpc("fts_get_event_ads_v2", {
      p_event_token: eventToken,
    });
    if (adError) throw adError;

    const row = Array.isArray(adRows) ? adRows[0] : null;
    const items = Array.isArray(row?.ad_items) ? row.ad_items : [];
    const ad = items.find((x: any) => String(x?.path || "") === adKey && x?.active !== false);
    const luxDate = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Europe/Luxembourg",
      year: "numeric", month: "2-digit", day: "2-digit",
    }).format(new Date());
    const inDateWindow = !!ad &&
      (!ad.start_date || luxDate >= String(ad.start_date)) &&
      (!ad.end_date || luxDate <= String(ad.end_date));
    const hasLink = !!ad && /^https?:\/\//i.test(String(ad.link || ""));

    if (!row?.ads_enabled || !ad || !inDateWindow || (action === "click" && !hasLink)) {
      return json({ ok: false, error: "Werbung nicht aktiv" }, 404);
    }

    const { error: insertError } = await supabase.from("fts_event_ad_events_v13").insert({
      event_token: canonical,
      ad_key: adKey,
      ad_name: clean(ad?.name || "Werbung", 100) || "Werbung",
      action,
      session_id: sessionId,
    });

    if (insertError) {
      if (insertError.code === "23505" && action === "view") {
        return json({ ok: true, duplicate: true });
      }
      throw insertError;
    }

    return json({ ok: true, duplicate: false });
  } catch (err) {
    console.error(err);
    return json({ ok: false, error: String((err as any)?.message || err) }, 500);
  }
});
