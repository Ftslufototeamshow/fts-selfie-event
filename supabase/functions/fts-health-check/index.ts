import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST, OPTIONS",
};
const BASE_URL="https://ftslufototeamshow.github.io/fts-selfie-event/";
const BUCKET="fts-selfie-live";

function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}})}
function clean(v:unknown,max=500){return String(v??"").trim().slice(0,max)}
function arr(v:any){if(Array.isArray(v))return v;try{return JSON.parse(v||"[]")}catch{return[]}}
function safeUrl(v:any){try{const u=new URL(String(v||""));return ["http:","https:"].includes(u.protocol)?u.href:""}catch{return""}}
async function fetchStatus(url:string,timeout=7000){
  const ctrl=new AbortController();const t=setTimeout(()=>ctrl.abort(),timeout);
  try{
    let r=await fetch(url,{method:"HEAD",redirect:"follow",signal:ctrl.signal});
    if(r.status===405||r.status===501) r=await fetch(url,{method:"GET",redirect:"follow",signal:ctrl.signal,headers:{Range:"bytes=0-0"}});
    return {ok:r.status<500,status:r.status};
  }catch(e){return {ok:false,status:0,error:String((e as any)?.message||e)}}finally{clearTimeout(t)}
}

Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({ok:false,error:"Method not allowed"},405);

  try{
    const supaUrl=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!supaUrl||!serviceKey)throw new Error("Server-Konfiguration fehlt");
    const admin=createClient(supaUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const body=await req.json().catch(()=>({}));
    const credential=clean(body.credential,240),inputToken=clean(body.event_token,120);
    if(!credential||!inputToken)return json({ok:false,error:"Zugang oder Event fehlt"},400);

    const {data:dashboard,error:dashError}=await admin.rpc("fts_admin_dashboard_events",{p_admin_code:credential});
    if(dashError)throw dashError;
    const dashRows=Array.isArray(dashboard)?dashboard:[];
    const dash=dashRows.find((x:any)=>String(x.event_token)===inputToken || String(x.short_code||"").toUpperCase()===inputToken.toUpperCase());
    if(!dash)return json({ok:false,error:"Event nicht gefunden oder Gerätezugang ungültig"},403);
    const eventToken=String(dash.event_token);

    const [{data:event,error:eventError},{data:lifecycle,error:lifeError}]=await Promise.all([
      admin.from("fts_selfie_events").select("token,short_code,title,event_date,event_days,active,archived_at,expires_at,ads_enabled,ad_items,customer_id").eq("token",eventToken).maybeSingle(),
      admin.from("fts_event_lifecycle_v11").select("schedule,gallery_url,gallery_available_at,link_expires_at,test_days_before").eq("event_token",eventToken).maybeSingle()
    ]);
    if(eventError)throw eventError;
    if(lifeError)throw lifeError;
    if(!event)return json({ok:false,error:"Event-Datensatz fehlt"},404);

    const checks:any[]=[];
    const add=(id:string,label:string,status:"pass"|"warn"|"fail",detail:string)=>checks.push({id,label,status,detail});
    add("database","Datenbank & Gerätezugang","pass","Supabase und der gespeicherte FTS-Gerätezugang antworten korrekt.");

    if(event.active!==true||event.archived_at)add("event_active","Event-Status","fail","Das Event ist archiviert oder deaktiviert.");
    else add("event_active","Event-Status","pass","Das Event ist aktiv.");

    const schedule=arr(lifecycle?.schedule).filter((x:any)=>x?.date);
    if(!schedule.length){
      add("schedule","Eventzeiten","warn","Für dieses Event ist noch kein neuer Tages-Zeitplan gespeichert; es läuft mit der älteren Datumslogik.");
    }else{
      let bad=false;
      for(const x of schedule){
        const start=String(x.start||"00:00"),end=String(x.end||"23:59");
        if(!/^\d{2}:\d{2}$/.test(start)||!/^\d{2}:\d{2}$/.test(end)||end<=start)bad=true;
      }
      add("schedule","Eventzeiten",bad?"fail":"pass",bad?"Mindestens ein Event-Tag hat ungültige Start-/Endzeiten.":schedule.map((x:any)=>`${x.date}: ${x.start||"00:00"}–${x.end||"23:59"}`).join(" · "));
    }

    if(schedule.length){
      const last=schedule.slice().sort((a:any,b:any)=>String(a.date+a.end).localeCompare(String(b.date+b.end))).at(-1);
      const lastEnd=last?`${last.date}T${last.end||"23:59"}`:"";
      const galleryAt=String(lifecycle?.gallery_available_at||"");
      const expiresAt=String(lifecycle?.link_expires_at||"");
      if(galleryAt&&lastEnd&&galleryAt<lastEnd)add("lifecycle","Galerie & Ablauf","fail","Die Galerie-Freigabe liegt vor dem letzten Event-Ende.");
      else if(expiresAt&&galleryAt&&expiresAt<=galleryAt)add("lifecycle","Galerie & Ablauf","fail","Der endgültige Link-Ablauf liegt vor oder genau auf der Galerie-Freigabe.");
      else if(expiresAt&&lastEnd&&expiresAt<=lastEnd)add("lifecycle","Galerie & Ablauf","fail","Der endgültige Link-Ablauf liegt vor dem letzten Event-Ende.");
      else add("lifecycle","Galerie & Ablauf","pass",`Galerie: ${galleryAt||"nicht terminiert"} · Link-Ende: ${expiresAt||"über Retention geregelt"}`);
    }

    const storagePath=`__health/${eventToken}/${crypto.randomUUID()}.txt`;
    const blob=new Blob(["fts-health"],{type:"text/plain"});
    const {error:uploadError}=await admin.storage.from(BUCKET).upload(storagePath,blob,{upsert:false,contentType:"text/plain"});
    if(uploadError){
      add("storage","Speicher & Foto-Upload","fail","Testdatei konnte nicht in den FTS-Speicher geschrieben werden: "+uploadError.message);
    }else{
      const {error:removeError}=await admin.storage.from(BUCKET).remove([storagePath]);
      add("storage","Speicher & Foto-Upload",removeError?"warn":"pass",removeError?"Upload funktioniert, temporäre Testdatei konnte aber nicht sofort gelöscht werden.":"Temporärer Upload und Löschen funktionieren.");
    }

    const alias=String(event.short_code||eventToken);
    const [guestStatus,posterStatus,customerStatus,swStatus]=await Promise.all([
      fetchStatus(BASE_URL+"?e="+encodeURIComponent(alias)),
      fetchStatus(BASE_URL+"poster.html?e="+encodeURIComponent(alias)),
      dash.customer_token?fetchStatus(BASE_URL+"customer.html?c="+encodeURIComponent(String(dash.customer_token))):Promise.resolve({ok:false,status:0}),
      fetchStatus(BASE_URL+"sw.js")
    ]);
    add("guest_page","QR-/Gastseite",guestStatus.ok?"pass":"fail",guestStatus.ok?`Gastseite erreichbar (HTTP ${guestStatus.status}).`:"Gastseite ist nicht erreichbar.");
    add("poster","QR-Poster",posterStatus.ok?"pass":"warn",posterStatus.ok?`QR-Poster erreichbar (HTTP ${posterStatus.status}).`:"QR-Poster konnte nicht erreicht werden.");
    add("customer_portal","Kundenportal",customerStatus.ok?"pass":"fail",customerStatus.ok?`Kundenportal erreichbar (HTTP ${customerStatus.status}).`:"Kundenportal oder Kunden-Token fehlt/nicht erreichbar.");
    add("service_worker","Offline-Funktion",swStatus.ok?"pass":"warn",swStatus.ok?"Service Worker für Offline-Uploads ist erreichbar.":"Service Worker konnte nicht erreicht werden.");

    const ads=arr(event.ad_items);
    if(event.ads_enabled){
      if(!ads.length)add("ads","Werbung","warn","Werbung ist eingeschaltet, aber es ist kein Banner gespeichert.");
      else add("ads","Werbung","pass",`${ads.length} Werbebanner gespeichert.`);
      const today=new Intl.DateTimeFormat("en-CA",{timeZone:"Europe/Luxembourg",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
      for(let i=0;i<ads.length;i++){
        const a=ads[i]||{},active=a.active!==false&&(!a.start_date||today>=a.start_date)&&(!a.end_date||today<=a.end_date);
        if(!active)continue;
        const link=safeUrl(a.link),name=clean(a.name,100)||`Werbung ${i+1}`;
        if(!a.link){add(`ad_link_${i}`,`Werbelink · ${name}`,"warn","Banner ist aktiv, hat aber keinen Link.");continue}
        if(!link){add(`ad_link_${i}`,`Werbelink · ${name}`,"fail","Der gespeicherte Link ist ungültig.");continue}
        const st=await fetchStatus(link,5500);
        add(`ad_link_${i}`,`Werbelink · ${name}`,st.ok?"pass":"warn",st.ok?`Link erreichbar (HTTP ${st.status}).`:"Link konnte vom System nicht bestätigt werden; manche Plattformen blockieren automatische Prüfungen.");
      }
    }else add("ads","Werbung","pass","Werbung ist für dieses Event ausgeschaltet.");

    if(lifecycle?.gallery_available_at&&!safeUrl(lifecycle?.gallery_url)){
      add("gallery_url","Galerie-Link","warn","Eine Galerie-Freigabe ist terminiert, aber noch kein gültiger Galerie-Link hinterlegt.");
    }else if(safeUrl(lifecycle?.gallery_url)){
      const gs=await fetchStatus(safeUrl(lifecycle.gallery_url),5500);
      add("gallery_url","Galerie-Link",gs.ok?"pass":"warn",gs.ok?"Galerie-Link erreichbar.":"Galerie-Link konnte nicht bestätigt werden.");
    }

    await admin.from("fts_event_issues_v14").update({resolved_at:new Date().toISOString()})
      .eq("event_token",eventToken).eq("issue_type","system_check").is("resolved_at",null);

    const problems=checks.filter(x=>x.status!=="pass");
    if(problems.length){
      const rows=problems.map(x=>({
        event_token:eventToken,issue_type:"system_check",
        severity:x.status==="fail"?"error":"warning",
        message:`${x.label}: ${x.detail}`,
        details:{check_id:x.id,label:x.label},
        session_id:"health-check",
        fingerprint:`system_check|${x.id}`
      }));
      const {error:issueError}=await admin.from("fts_event_issues_v14").insert(rows);
      if(issueError)console.warn("health issue log",issueError);
    }

    const fail=checks.filter(x=>x.status==="fail").length,warn=checks.filter(x=>x.status==="warn").length;
    return json({ok:true,event_token:eventToken,title:event.title,checks,summary:{pass:checks.length-fail-warn,warn,fail}});
  }catch(e){
    console.error(e);
    return json({ok:false,error:String((e as any)?.message||e)},500);
  }
});
