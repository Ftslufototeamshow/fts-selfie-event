import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { zipSync } from "npm:fflate@0.8.2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
};
const clean=(v:string,max=180)=>String(v||"").slice(0,max);
const slug=(v:string)=>clean(v).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/ß/g,"ss").replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"")||"event";
const basename=(v:string)=>clean(v,600).split("/").pop()?.replace(/[^a-zA-Z0-9._-]+/g,"-")||"foto.jpg";
const validDay=(v:string)=>/^\d{4}-\d{2}-\d{2}$/.test(v)||v==="__test__";
async function input(req:Request){
  if(req.method==="GET"){const u=new URL(req.url);return Object.fromEntries(u.searchParams.entries())}
  const ct=req.headers.get("content-type")||"";
  if(ct.includes("application/json"))return await req.json();
  const fd=await req.formData();return Object.fromEntries([...fd.entries()].map(([k,v])=>[k,String(v)]));
}
function attachment(blob:Blob|Uint8Array,filename:string,type:string){
  const safe=clean(filename,180).replace(/[^a-zA-Z0-9._-]+/g,"-")||"download";
  const size=blob instanceof Uint8Array?blob.byteLength:blob.size;
  return new Response(blob,{status:200,headers:{...cors,"Content-Type":type,"Content-Disposition":`attachment; filename="${safe}"`,"Content-Length":String(size),"Cache-Control":"private, no-store, max-age=0","X-Content-Type-Options":"nosniff"}});
}
Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(!["GET","POST"].includes(req.method))return new Response("Method not allowed",{status:405,headers:cors});
  try{
    const p:any=await input(req),action=String(p.action||"zip"),mode=String(p.mode||"customer"),eventToken=clean(p.event_token,220);
    if(!eventToken)throw new Error("Event fehlt.");
    const url=Deno.env.get("SUPABASE_URL")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const db=createClient(url,service,{auth:{persistSession:false}});
    let title=clean(p.title||"event",160);

    if(action==="file"){
      const photoId=clean(p.photo_id,80),fileKind=String(p.file_kind||"design");if(!photoId)throw new Error("Foto fehlt.");
      let path="";
      if(mode==="customer"){
        const customerToken=clean(p.customer_token,220);if(!customerToken)throw new Error("Kundenlink fehlt.");
        const {data,error}=await db.rpc("fts_get_customer_designs_v38",{p_customer_token:customerToken});if(error)throw error;
        const row=(data||[]).find((r:any)=>String(r.event_token)===eventToken&&String(r.photo_id)===photoId);
        if(!row?.designed_path)throw new Error("Foto nicht verfügbar.");
        path=String(row.designed_path);if(row.event_title)title=String(row.event_title);
      }else if(mode==="admin"){
        const credential=clean(p.credential,300);if(!credential)throw new Error("FTS-Zugang fehlt.");
        const {data,error}=await db.rpc("fts_admin_get_event_photos",{p_admin_code:credential,p_event_token:eventToken,p_view:"active"});if(error)throw error;
        const row=(data||[]).find((r:any)=>String(r.photo_id)===photoId);if(!row)throw new Error("Foto nicht verfügbar.");
        if(fileKind==="original"&&row.original_exists&&row.original_path)path=String(row.original_path);
        else if(fileKind==="design"&&row.design_exists&&row.designed_path)path=String(row.designed_path);
        else throw new Error("Datei nicht verfügbar.");
      }else throw new Error("Unbekannter Download-Modus.");
      const {data,error}=await db.storage.from("fts-selfie-live").download(path);if(error||!data)throw error||new Error("Datei konnte nicht geladen werden.");
      return attachment(data,basename(path),data.type||"application/octet-stream");
    }

    if(action!=="zip")throw new Error("Unbekannte Download-Aktion.");
    const day=clean(p.day,20);if(!validDay(day))throw new Error("Ungültiger Event-Tag.");
    let files:{path:string;zipPath:string}[]=[];
    if(mode==="customer"){
      const customerToken=clean(p.customer_token,220);if(!customerToken)throw new Error("Kundenlink fehlt.");
      const {data,error}=await db.rpc("fts_get_customer_designs_v38",{p_customer_token:customerToken});if(error)throw error;
      const rows=(data||[]).filter((r:any)=>String(r.event_token)===eventToken&&String(r.event_day||r.event_date||"")===day);
      if(rows[0]?.event_title)title=String(rows[0].event_title);
      files=rows.filter((r:any)=>r.designed_path).map((r:any)=>({path:String(r.designed_path),zipPath:`${slug(title)}/${day}/Event-Designs/${basename(String(r.designed_path))}`}));
    }else if(mode==="admin"){
      const credential=clean(p.credential,300),type=["original","design","both"].includes(String(p.type))?String(p.type):"design";if(!credential)throw new Error("FTS-Zugang fehlt.");
      const {data,error}=await db.rpc("fts_admin_get_event_photos",{p_admin_code:credential,p_event_token:eventToken,p_view:"active"});if(error)throw error;
      const rows=(data||[]).filter((r:any)=>day==="__test__"?!!r.is_test:(!r.is_test&&String(r.event_day||r.event_date||"")===day));
      for(const r of rows){
        if((type==="original"||type==="both")&&r.original_exists&&r.original_path)files.push({path:String(r.original_path),zipPath:`${slug(title)}/${day}/Originale/${basename(String(r.original_path))}`});
        if((type==="design"||type==="both")&&r.design_exists&&r.designed_path)files.push({path:String(r.designed_path),zipPath:`${slug(title)}/${day}/Event-Designs/${basename(String(r.designed_path))}`});
      }
    }else throw new Error("Unbekannter Download-Modus.");
    if(!files.length)throw new Error("Für diesen Tag sind keine Dateien zum Herunterladen vorhanden.");
    if(files.length>250)throw new Error("Dieses Album ist zu groß für einen direkten ZIP-Download.");
    const archive:Record<string,Uint8Array>={},failed:string[]=[];
    for(const item of files){
      const {data,error}=await db.storage.from("fts-selfie-live").download(item.path);
      if(error||!data){failed.push(item.path);continue}
      archive[item.zipPath]=new Uint8Array(await data.arrayBuffer());
    }
    if(!Object.keys(archive).length)throw new Error("Die Fotos konnten nicht geladen werden.");
    const zip=zipSync(archive,{level:0});
    const wanted=clean(p.filename||`FTS-${slug(title)}-${day}.zip`,180);
    const filename=(wanted.toLowerCase().endsWith(".zip")?wanted:wanted+".zip").replace(/[^a-zA-Z0-9._-]+/g,"-");
    const response=attachment(zip,filename,"application/zip");
    response.headers.set("X-FTS-Zip-Files",String(Object.keys(archive).length));response.headers.set("X-FTS-Zip-Failed",String(failed.length));
    return response;
  }catch(e){
    return new Response(JSON.stringify({ok:false,error:String((e as any)?.message||e)}),{status:400,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
  }
});