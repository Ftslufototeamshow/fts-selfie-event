import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const LIVE_BUCKET = "fts-selfie-live";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
    },
  });
}

function clean(v: unknown, max = 300) {
  return String(v ?? "").trim().slice(0, max);
}

function validIso(v: string) {
  if (!v) return "";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "" : d.toISOString();
}

function publicObjectUrl(supabaseUrl: string, bucket: string, path: string) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  return `${supabaseUrl}/storage/v1/object/public/${encodeURIComponent(bucket)}/${encoded}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return json({ ok: false, error: "GET only" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRole) throw new Error("Server configuration missing");

    const admin = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const url = new URL(req.url);
    const token = clean(url.searchParams.get("t"), 160);
    const since = validIso(clean(url.searchParams.get("since"), 80));
    const previousRevision = clean(url.searchParams.get("revision"), 240);
    const requestedLimit = Number(url.searchParams.get("limit") || "500");
    const limit = Number.isFinite(requestedLimit)
      ? Math.max(1, Math.min(1000, Math.trunc(requestedLimit)))
      : 500;

    if (!token) return json({ ok: false, error: "Missing LUMOREX token" }, 400);

    const { data: link, error: linkError } = await admin
      .from("fts_lumorex_event_links_v1")
      .select("event_id,enabled")
      .eq("feed_token", token)
      .maybeSingle();

    if (linkError) throw linkError;
    if (!link?.event_id || link.enabled !== true) {
      return json({ ok: false, error: "LUMOREX link not found" }, 404);
    }

    const { data: event, error: eventError } = await admin
      .from("fts_selfie_events")
      .select("id,token,short_code,title,legacy_bucket")
      .eq("id", link.event_id)
      .maybeSingle();

    if (eventError) throw eventError;
    if (!event?.id) return json({ ok: false, error: "Event not found" }, 404);

    const baseFilters = (q: any) => q
      .eq("event_id", event.id)
      .eq("is_test", false)
      .is("trashed_at", null);

    const countQuery = baseFilters(
      admin.from("fts_selfie_photos").select("id", { count: "exact", head: true })
    );

    const latestQuery = baseFilters(
      admin.from("fts_selfie_photos")
        .select("id,created_at")
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(1)
    );

    let photoQuery = baseFilters(
      admin.from("fts_selfie_photos")
        .select("id,event_id,original_path,designed_path,created_at,event_day")
        .order("created_at", { ascending: true })
        .order("id", { ascending: true })
    );

    if (since) photoQuery = photoQuery.gt("created_at", since);
    photoQuery = photoQuery.limit(limit);

    const [countResult, latestResult, photosResult] = await Promise.all([
      countQuery,
      latestQuery,
      photoQuery,
    ]);

    if (countResult.error) throw countResult.error;
    if (latestResult.error) throw latestResult.error;
    if (photosResult.error) throw photosResult.error;

    const totalCount = Number(countResult.count || 0);
    const latest = Array.isArray(latestResult.data) ? latestResult.data[0] : null;
    const revision = latest
      ? `${totalCount}:${latest.created_at}:${latest.id}`
      : "0:empty";

    const rows = Array.isArray(photosResult.data) ? photosResult.data : [];
    const photos = [];

    for (const p of rows) {
      const designed = clean(p.designed_path, 1200);
      const original = clean(p.original_path, 1200);
      const chosenPath = designed || original;
      const source = designed ? "designed" : "original";
      let imageUrl = "";

      if (/^https?:\/\//i.test(chosenPath)) {
        imageUrl = chosenPath;
      } else if (chosenPath) {
        const looksModern = chosenPath.startsWith(String(event.token) + "/");
        const bucket = !looksModern && event.legacy_bucket
          ? String(event.legacy_bucket)
          : LIVE_BUCKET;

        if (bucket === LIVE_BUCKET) {
          imageUrl = publicObjectUrl(supabaseUrl, bucket, chosenPath);
        } else {
          const { data: signed, error: signedError } = await admin.storage
            .from(bucket)
            .createSignedUrl(chosenPath, 3600);
          if (!signedError && signed?.signedUrl) imageUrl = signed.signedUrl;
        }
      }

      if (!imageUrl) continue;

      photos.push({
        photo_id: p.id,
        event_id: p.event_id,
        event_token: event.token,
        image_url: imageUrl,
        image_source: source,
        created_at: p.created_at,
        event_day: p.event_day,
      });
    }

    const nextSince = photos.length
      ? String(photos[photos.length - 1].created_at)
      : (since || (latest?.created_at ? String(latest.created_at) : null));

    const hasNew = previousRevision
      ? previousRevision !== revision
      : since
        ? photos.length > 0
        : totalCount > 0;

    return json({
      ok: true,
      schema: "fts-lumorex-feed/v1",
      read_only: true,
      event: {
        event_id: event.id,
        event_token: event.token,
        short_code: event.short_code || null,
        title: event.title,
      },
      poll: {
        generated_at: new Date().toISOString(),
        requested_since: since || null,
        requested_revision: previousRevision || null,
        revision,
        has_new: hasNew,
        photo_count_total: totalCount,
        returned_count: photos.length,
        latest_photo_at: latest?.created_at || null,
        next_since: nextSince,
        limit,
        truncated: photos.length >= limit && (since ? true : totalCount > limit),
      },
      photos,
    });
  } catch (err) {
    console.error(err);
    return json({ ok: false, error: String((err as any)?.message || err) }, 500);
  }
});
