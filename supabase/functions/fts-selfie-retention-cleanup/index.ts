import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

async function removeInBatches(storage: any, bucket: string, paths: string[]) {
  const unique = [...new Set(paths.map((x) => String(x || "").trim()).filter(Boolean))];
  let removed = 0;
  for (let i = 0; i < unique.length; i += 100) {
    const batch = unique.slice(i, i + 100);
    const { error } = await storage.from(bucket).remove(batch);
    if (error) throw error;
    removed += batch.length;
  }
  return removed;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRole) throw new Error("Supabase server environment fehlt");

    const supabase = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: expired, error: expiredError } = await supabase.rpc("fts_retention_expired_events_v1");
    if (expiredError) throw expiredError;

    const bucket = "fts-selfie-live";
    const results: any[] = [];

    for (const event of expired || []) {
      let deletedPhotos = 0;
      let deletedFiles = 0;

      while (true) {
        const { data: photos, error: photosError } = await supabase
          .from("fts_selfie_photos")
          .select("id,original_path,designed_path,publication_designed_path")
          .eq("event_id", event.event_id)
          .limit(500);

        if (photosError) throw photosError;
        const rows = photos || [];
        if (!rows.length) break;

        const paths = rows.flatMap((p: any) => [
          p.original_path,
          p.designed_path,
          p.publication_designed_path,
        ]).filter(Boolean);

        deletedFiles += await removeInBatches(supabase.storage, bucket, paths);

        const ids = rows.map((p: any) => p.id);
        const { error: deleteError } = await supabase
          .from("fts_selfie_photos")
          .delete()
          .in("id", ids);
        if (deleteError) throw deleteError;

        deletedPhotos += rows.length;
      }

      const { error: auditError } = await supabase
        .from("fts_selfie_retention_cleanup_v1")
        .insert({
          event_id: event.event_id,
          event_token: event.event_token,
          link_expires_at: event.link_expires_at,
          deleted_photos: deletedPhotos,
          deleted_files: deletedFiles,
        });
      if (auditError) console.warn("Retention-Audit konnte nicht gespeichert werden:", auditError.message);

      results.push({
        event_token: event.event_token,
        deleted_photos: deletedPhotos,
        deleted_files: deletedFiles,
      });
    }

    return json({
      ok: true,
      events_cleaned: results.length,
      deleted_photos: results.reduce((n, x) => n + x.deleted_photos, 0),
      deleted_files: results.reduce((n, x) => n + x.deleted_files, 0),
      results,
    });
  } catch (err) {
    console.error(err);
    return json({ ok: false, error: String((err as any)?.message || err) }, 500);
  }
});
