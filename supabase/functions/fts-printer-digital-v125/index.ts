import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
};

const clean=(v:any,max=300)=>String(v??"").trim().slice(0,max);
const hex=(buf:ArrayBuffer)=>Array.from(new Uint8Array(buf)).map(b=>b.toString(16).padStart(2,"0")).join("");
async function sha256(v:string){return hex(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v)))}
function b64Bytes(v:string){
  const raw=atob(v);
  const out=new Uint8Array(raw.length);
  for(let i=0;i<raw.length;i++)out[i]=raw.charCodeAt(i);
  return out;
}
function htmlEscape(v:string){
  return v.replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[c]||c));
}
function adminKey(){
  const raw=Deno.env.get("SUPABASE_SECRET_KEYS")||"";
  if(raw){
    try{const keys=JSON.parse(raw);if(keys?.default)return String(keys.default)}catch{}
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  const supabaseUrl=Deno.env.get("SUPABASE_URL")||"";
  const service=adminKey();
  if(!supabaseUrl||!service)return new Response("Server configuration missing",{status:500});
  const db=createClient(supabaseUrl,service,{auth:{persistSession:false}});

  try{
    if(req.method==="POST"){
      const body:any=await req.json();
      const action=clean(body.action||"create",40);
      const deviceToken=clean(body.device_token,500);
      const sessionToken=clean(body.session_token,500);
      if(!deviceToken||!sessionToken)throw new Error("Printer-Anmeldung fehlt.");

      const {data:session,error:sessionError}=await db.rpc("fts_printer_validate_session_v125",{
        p_device_token:deviceToken,
        p_session_token:sessionToken
      });
      if(sessionError)throw sessionError;
      if(!session?.valid||!session?.user_id)throw new Error("Printer-Sitzung ist nicht gültig.");

      const image64=clean(body.image_base64,14_000_000);
      if(!image64)throw new Error("Bild fehlt.");
      const bytes=b64Bytes(image64);
      if(bytes.byteLength<100||bytes.byteLength>10_000_000)throw new Error("Bildgröße ist ungültig.");

      if(action==="avatar"){
        const path=`printer-avatars/${session.user_id}.jpg`;
        const {error:uploadError}=await db.storage.from("fts-selfie-live").upload(path,bytes,{
          contentType:"image/jpeg",cacheControl:"300",upsert:true
        });
        if(uploadError)throw uploadError;
        const {error:updateError}=await db.from("fts_selfie_printer_users_v72")
          .update({avatar_path:path,updated_at:new Date().toISOString()})
          .eq("id",session.user_id);
        if(updateError)throw updateError;
        return Response.json({ok:true,avatar_path:path},{headers:{...cors,"Cache-Control":"no-store"}});
      }

      if(action!=="create")throw new Error("Unbekannte Aktion.");

      const eventToken=clean(body.event_token,300);
      if(!eventToken)throw new Error("Event fehlt.");
      const {data:eventId,error:eventError}=await db.rpc("fts_selfie_resolve_event_id_v50",{p_event_token:eventToken});
      if(eventError)throw eventError;
      if(!eventId)throw new Error("Event nicht gefunden.");

      const token=crypto.randomUUID().replaceAll("-","")+crypto.randomUUID().replaceAll("-","");
      const tokenHash=await sha256(token);
      const fileName=clean(body.file_name||"FTS-Foto.jpg",160).replace(/[^a-zA-Z0-9._-]+/g,"-")||"FTS-Foto.jpg";
      const storagePath=`${eventId}/${token.slice(0,24)}.jpg`;
      const {error:uploadError}=await db.storage.from("fts-selfie-digital").upload(storagePath,bytes,{
        contentType:"image/jpeg",cacheControl:"60",upsert:false
      });
      if(uploadError)throw uploadError;

      const expires=new Date(Date.now()+7*24*60*60*1000).toISOString();
      const {error:insertError}=await db.from("fts_selfie_printer_digital_downloads_v125").insert({
        token_hash:tokenHash,
        event_id:eventId,
        created_by:session.user_id,
        bucket:"fts-selfie-digital",
        storage_path:storagePath,
        file_name:fileName,
        mime_type:"image/jpeg",
        expires_at:expires
      });
      if(insertError){
        await db.storage.from("fts-selfie-digital").remove([storagePath]).catch(()=>{});
        throw insertError;
      }

      const url=`${supabaseUrl}/functions/v1/fts-printer-digital-v125?token=${encodeURIComponent(token)}`;
      return Response.json({ok:true,url,expires_at:expires},{headers:{...cors,"Cache-Control":"no-store"}});
    }

    if(req.method==="GET"){
      const u=new URL(req.url);
      const token=clean(u.searchParams.get("token"),200);
      if(!token||token.length<40)return new Response("Ungültiger Link.",{status:400,headers:cors});
      const tokenHash=await sha256(token);
      const {data:row,error}=await db.from("fts_selfie_printer_digital_downloads_v125")
        .select("id,bucket,storage_path,file_name,mime_type,expires_at,download_count")
        .eq("token_hash",tokenHash)
        .maybeSingle();
      if(error)throw error;
      if(!row)return new Response("Dieser Fotolink ist nicht gültig.",{status:404,headers:cors});
      if(new Date(row.expires_at).getTime()<=Date.now())return new Response("Dieser Fotolink ist abgelaufen.",{status:410,headers:cors});

      const raw=u.searchParams.get("raw")==="1";
      const download=u.searchParams.get("download")==="1";
      if(raw||download){
        const {data:file,error:fileError}=await db.storage.from(row.bucket).download(row.storage_path);
        if(fileError||!file)throw fileError||new Error("Foto konnte nicht geladen werden.");
        await db.from("fts_selfie_printer_digital_downloads_v125").update({
          download_count:Number(row.download_count||0)+1,
          last_downloaded_at:new Date().toISOString()
        }).eq("id",row.id);
        const headers={
          ...cors,
          "Content-Type":row.mime_type||file.type||"image/jpeg",
          "Cache-Control":"private, no-store, max-age=0",
          "Content-Disposition":`${download?"attachment":"inline"}; filename="${clean(row.file_name,160).replace(/[^a-zA-Z0-9._-]+/g,"-")}"`
        };
        return new Response(file,{status:200,headers});
      }

      const safeName=htmlEscape(row.file_name||"FTS Foto");
      const base=`${supabaseUrl}/functions/v1/fts-printer-digital-v125?token=${encodeURIComponent(token)}`;
      const page=`<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${safeName}</title><style>
      body{margin:0;background:#0b1117;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center}
      main{width:min(94vw,760px);text-align:center;padding:24px}.card{background:#121c25;border:1px solid #2b3a46;border-radius:18px;padding:18px}
      img{max-width:100%;max-height:68vh;border-radius:12px;background:#000}.btn{display:inline-block;margin-top:16px;background:#17c9e8;color:#00151b;padding:14px 22px;border-radius:12px;text-decoration:none;font-weight:800}
      p{color:#b8c6d1;font-size:14px}.brand{color:#d8b25c;font-weight:800;letter-spacing:.08em}</style></head><body><main>
      <div class="brand">FTS SELFIE EVENT</div><h1>Dein digitales Foto</h1><div class="card"><img src="${base}&raw=1" alt="FTS Foto"><br><a class="btn" href="${base}&download=1">Foto herunterladen</a><p>Dieser persönliche Download-Link ist 7 Tage gültig.</p></div>
      </main></body></html>`;
      return new Response(page,{status:200,headers:{...cors,"Content-Type":"text/html; charset=utf-8","Cache-Control":"private, no-store, max-age=0"}});
    }

    return new Response("Method not allowed",{status:405,headers:cors});
  }catch(e){
    console.error(e);
    return new Response(JSON.stringify({ok:false,error:String((e as any)?.message||e)}),{
      status:400,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}
    });
  }
});