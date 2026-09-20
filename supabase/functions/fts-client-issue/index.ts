import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedTypes = new Set(["offline_queue","upload_failed","background_upload_failed","client_error"]);

function json(body: unknown, status=200) {
  return new Response(JSON.stringify(body), {status, headers:{...cors,"Content-Type":"application/json"}});
}
function clean(v: unknown, max=300) { return String(v ?? "").trim().slice(0,max); }

Deno.serve(async req => {
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(req.method!=="POST") return json({ok:false,error:"Method not allowed"},405);

  try{
    const url=Deno.env.get("SUPABASE_URL"), key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!url||!key) throw new Error("Server-Konfiguration fehlt");
    const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});

    const body=await req.json().catch(()=>({}));
    const eventInput=clean(body.event_token,120);
    const issueType=clean(body.issue_type,60);
    const sessionId=clean(body.session_id,100);
    const issueKey=clean(body.issue_key,160);
    const resolved=body.resolved===true;

    if(!eventInput||!allowedTypes.has(issueType)) return json({ok:false,error:"Ungültige Fehlerdaten"},400);

    const {data:eventRows,error:eventError}=await admin.rpc("fts_get_event",{p_event_token:eventInput});
    if(eventError) throw eventError;
    const eventToken=Array.isArray(eventRows)&&eventRows[0]?.event_token?String(eventRows[0].event_token):"";
    if(!eventToken) return json({ok:false,error:"Event nicht gefunden"},404);

    const fingerprint=[issueType,sessionId||"anonymous",issueKey||"default"].join("|").slice(0,500);

    if(resolved){
      const {error}=await admin.from("fts_event_issues_v14")
        .update({resolved_at:new Date().toISOString()})
        .eq("event_token",eventToken)
        .eq("fingerprint",fingerprint)
        .is("resolved_at",null);
      if(error) throw error;
      return json({ok:true,resolved:true});
    }

    const severity=["info","warning","error"].includes(String(body.severity))?String(body.severity):"warning";
    const message=clean(body.message,500)||"FTS Client-Problem";
    let details:Record<string,unknown>={};
    if(body.details&&typeof body.details==="object"&&!Array.isArray(body.details)){
      const raw=JSON.stringify(body.details);
      if(raw.length<=4000) details=body.details;
    }

    const {data:existing,error:findError}=await admin.from("fts_event_issues_v14")
      .select("id,occurrences")
      .eq("event_token",eventToken)
      .eq("fingerprint",fingerprint)
      .is("resolved_at",null)
      .maybeSingle();
    if(findError) throw findError;

    if(existing?.id){
      const {error}=await admin.from("fts_event_issues_v14").update({
        severity,message,details,session_id:sessionId,
        occurrences:Number(existing.occurrences||1)+1,
        last_seen_at:new Date().toISOString()
      }).eq("id",existing.id);
      if(error) throw error;
    }else{
      const {error}=await admin.from("fts_event_issues_v14").insert({
        event_token:eventToken,issue_type:issueType,severity,message,details,
        session_id:sessionId,fingerprint
      });
      if(error) throw error;
    }

    return json({ok:true});
  }catch(e){
    console.error(e);
    return json({ok:false,error:String((e as any)?.message||e)},500);
  }
});
