import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
};
const UNIT_PRICE_CENTS=200;
const CURRENCY="EUR";
const ENVIRONMENT="sandbox";
const MAX_TOTAL_QTY=50;
let tokenCache:{token:string;expiresAt:number}|null=null;

function json(body:unknown,status=200){
  return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
}
function clean(v:unknown,max=300){return String(v??"").trim().slice(0,max)}
function centsToValue(cents:number){return (cents/100).toFixed(2)}
function valueToCents(v:unknown){
  const n=Number(String(v??"").replace(",","."));
  return Number.isFinite(n)?Math.round(n*100):NaN;
}
function paypalBase(){return ENVIRONMENT==="sandbox"?"https://api-m.sandbox.paypal.com":"https://api-m.paypal.com"}
function envName(base:string){return `PAYPAL_SELFIE_${ENVIRONMENT.toUpperCase()}_${base}`}
function paypalClientId(){return Deno.env.get(envName("CLIENT_ID"))||""}
function paypalSecret(){return Deno.env.get(envName("CLIENT_SECRET"))||""}

async function paypalAccessToken(){
  if(tokenCache&&Date.now()<tokenCache.expiresAt-60_000)return tokenCache.token;
  const id=paypalClientId(),secret=paypalSecret();
  if(!id||!secret)throw new Error("PayPal Sandbox Secrets fehlen");
  const basic=btoa(`${id}:${secret}`);
  const r=await fetch(paypalBase()+"/v1/oauth2/token",{
    method:"POST",
    headers:{"Authorization":"Basic "+basic,"Content-Type":"application/x-www-form-urlencoded"},
    body:"grant_type=client_credentials"
  });
  const data=await r.json().catch(()=>({}));
  if(!r.ok||!data?.access_token)throw new Error("PayPal OAuth fehlgeschlagen");
  tokenCache={token:String(data.access_token),expiresAt:Date.now()+Math.max(60,Number(data.expires_in||300))*1000};
  return tokenCache.token;
}
async function paypalFetch(path:string,init:RequestInit={}){
  const token=await paypalAccessToken();
  const r=await fetch(paypalBase()+path,{
    ...init,
    headers:{
      "Authorization":"Bearer "+token,
      "Content-Type":"application/json",
      ...(init.headers||{})
    }
  });
  const text=await r.text();
  let data:any={};try{data=text?JSON.parse(text):{}}catch{data={raw:text}}
  if(!r.ok){
    const err=new Error(data?.message||data?.name||`PayPal HTTP ${r.status}`);
    (err as any).paypal=data;(err as any).status=r.status;throw err;
  }
  return data;
}
async function bodyOf(req:Request){
  if(req.method==="GET")return Object.fromEntries(new URL(req.url).searchParams.entries());
  return await req.json().catch(()=>({}));
}
async function findEvent(admin:any,input:string){
  let q=await admin.from("fts_selfie_events")
    .select("id,token,short_code,title,active,archived_at,expires_at")
    .eq("token",input).maybeSingle();
  if(q.error)throw q.error;
  if(q.data)return q.data;
  q=await admin.from("fts_selfie_events")
    .select("id,token,short_code,title,active,archived_at,expires_at")
    .eq("short_code",input.toUpperCase()).maybeSingle();
  if(q.error)throw q.error;
  return q.data;
}
function windowActive(setting:any){
  if(!setting?.enabled)return false;
  const now=Date.now();
  const start=setting.print_starts_at?Date.parse(setting.print_starts_at):NaN;
  const end=setting.print_ends_at?Date.parse(setting.print_ends_at):NaN;
  if(Number.isFinite(start)&&now<start)return false;
  if(Number.isFinite(end)&&now>end)return false;
  return true;
}
async function eventSetting(admin:any,eventId:string){
  const {data,error}=await admin.from("fts_selfie_print_settings")
    .select("enabled,print_starts_at,print_ends_at,unit_price_cents,currency,paypal_environment")
    .eq("event_id",eventId).maybeSingle();
  if(error)throw error;
  return data;
}
async function ownedOrder(admin:any,orderId:string,eventId:string,sessionId:string){
  const {data,error}=await admin.from("fts_selfie_print_orders")
    .select("*").eq("id",orderId).eq("event_id",eventId).eq("guest_session_id",sessionId).maybeSingle();
  if(error)throw error;
  return data;
}
function safeOrderStatus(o:any){
  return {
    order_id:o.id,
    paypal_order_id:o.paypal_order_id||null,
    payment_status:o.payment_status,
    print_status:o.print_status,
    quantity_total:o.quantity_total,
    total_cents:o.total_cents,
    total:centsToValue(Number(o.total_cents||0)),
    currency:o.currency,
    paid_at:o.paid_at||null,
    printed_at:o.printed_at||null
  };
}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(!["GET","POST"].includes(req.method))return json({ok:false,error:"Method not allowed"},405);
  try{
    const supabaseUrl=Deno.env.get("SUPABASE_URL"),serviceRole=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!supabaseUrl||!serviceRole)throw new Error("Supabase Server-Konfiguration fehlt");
    const admin=createClient(supabaseUrl,serviceRole,{auth:{persistSession:false,autoRefreshToken:false}});
    const body:any=await bodyOf(req);
    const action=clean(body.action,40)||"config";
    const eventInput=clean(body.event_token,140);
    const sessionId=clean(body.guest_session_id,140);
    if(!eventInput||!sessionId)return json({ok:false,error:"Event oder Gast-Sitzung fehlt"},400);

    const event=await findEvent(admin,eventInput);
    if(!event?.id||event.active!==true||event.archived_at)return json({ok:false,error:"Event nicht verfügbar"},404);
    const setting=await eventSetting(admin,event.id);
    const active=windowActive(setting);
    const configured=!!(paypalClientId()&&paypalSecret());

    if(action==="config"){
      return json({
        ok:true,
        enabled:active,
        configured,
        environment:ENVIRONMENT,
        client_id:configured?paypalClientId():"",
        unit_price_cents:UNIT_PRICE_CENTS,
        unit_price:"2.00",
        currency:CURRENCY,
        starts_at:setting?.print_starts_at||null,
        ends_at:setting?.print_ends_at||null
      });
    }

    if(!active)return json({ok:false,error:"Fotodruck ist für dieses Event gerade nicht freigeschaltet"},403);
    if(!configured)return json({ok:false,error:"PayPal Sandbox ist serverseitig noch nicht konfiguriert"},503);

    if(action==="create-order"){
      const rawItems=Array.isArray(body.items)?body.items:[];
      if(!rawItems.length||rawItems.length>20)return json({ok:false,error:"Bitte mindestens ein Foto auswählen"},400);
      const normalized=new Map<string,number>();
      for(const raw of rawItems){
        const id=clean(raw?.photo_id,80);
        const qty=Number(raw?.quantity);
        if(!/^[0-9a-f-]{36}$/i.test(id)||!Number.isInteger(qty)||qty<1||qty>20)return json({ok:false,error:"Ungültige Foto-Auswahl oder Anzahl"},400);
        normalized.set(id,(normalized.get(id)||0)+qty);
      }
      const ids=[...normalized.keys()];
      const quantityTotal=[...normalized.values()].reduce((a,b)=>a+b,0);
      if(quantityTotal<1||quantityTotal>MAX_TOTAL_QTY)return json({ok:false,error:"Maximal 50 Ausdrucke pro Zahlung"},400);

      const {data:photos,error:photosError}=await admin.from("fts_selfie_photos")
        .select("id,designed_path,event_id,guest_session_id,is_test,trashed_at")
        .in("id",ids).eq("event_id",event.id).eq("guest_session_id",sessionId)
        .eq("is_test",false).is("trashed_at",null);
      if(photosError)throw photosError;
      if((photos||[]).length!==ids.length||photos.some((p:any)=>!p.designed_path))return json({ok:false,error:"Mindestens ein Foto ist nicht für den Druck verfügbar"},403);

      const totalCents=quantityTotal*UNIT_PRICE_CENTS;
      const {data:order,error:orderError}=await admin.from("fts_selfie_print_orders").insert({
        event_id:event.id,guest_session_id:sessionId,paypal_environment:ENVIRONMENT,
        payment_status:"CREATED",print_status:"BLOCKED",unit_price_cents:UNIT_PRICE_CENTS,
        quantity_total:quantityTotal,total_cents:totalCents,currency:CURRENCY
      }).select("*").single();
      if(orderError)throw orderError;

      const photoMap=new Map((photos||[]).map((p:any)=>[String(p.id),p]));
      const itemRows=ids.map(id=>({
        order_id:order.id,photo_id:id,designed_path_snapshot:String(photoMap.get(id).designed_path),
        quantity:normalized.get(id),unit_price_cents:UNIT_PRICE_CENTS,
        line_total_cents:Number(normalized.get(id))*UNIT_PRICE_CENTS
      }));
      const {error:itemError}=await admin.from("fts_selfie_print_order_items").insert(itemRows);
      if(itemError){
        await admin.from("fts_selfie_print_orders").update({payment_status:"ERROR",last_error:"Print items insert failed"}).eq("id",order.id);
        throw itemError;
      }

      try{
        const paypalOrder=await paypalFetch("/v2/checkout/orders",{
          method:"POST",
          headers:{"PayPal-Request-Id":"fts-selfie-create-"+order.id},
          body:JSON.stringify({
            intent:"CAPTURE",
            purchase_units:[{
              reference_id:order.id,
              custom_id:order.id,
              invoice_id:"FTS-PRINT-"+order.id,
              description:"FTS MySelfie Fotodruck",
              amount:{currency_code:CURRENCY,value:centsToValue(totalCents)},
              items:[{
                name:"MySelfie Fotoprint 10x15",
                quantity:String(quantityTotal),
                unit_amount:{currency_code:CURRENCY,value:"2.00"},
                category:"PHYSICAL_GOODS"
              }]
            }],
            payment_source:{
              paypal:{
                experience_context:{
                  user_action:"PAY_NOW",
                  shipping_preference:"NO_SHIPPING"
                }
              }
            }
          })
        });
        if(!paypalOrder?.id)throw new Error("PayPal Order-ID fehlt");
        const {error:updateError}=await admin.from("fts_selfie_print_orders")
          .update({paypal_order_id:String(paypalOrder.id),updated_at:new Date().toISOString()})
          .eq("id",order.id);
        if(updateError)throw updateError;
        return json({
          ok:true,id:String(paypalOrder.id),orderId:String(paypalOrder.id),
          print_order_id:order.id,quantity_total:quantityTotal,total:centsToValue(totalCents),
          total_cents:totalCents,currency:CURRENCY
        });
      }catch(e){
        await admin.from("fts_selfie_print_orders").update({
          payment_status:"ERROR",last_error:clean((e as any)?.message||e,500),updated_at:new Date().toISOString()
        }).eq("id",order.id);
        throw e;
      }
    }

    const printOrderId=clean(body.print_order_id,80);
    if(!/^[0-9a-f-]{36}$/i.test(printOrderId))return json({ok:false,error:"Druckauftrag fehlt"},400);
    const order=await ownedOrder(admin,printOrderId,event.id,sessionId);
    if(!order)return json({ok:false,error:"Druckauftrag nicht gefunden"},404);

    if(action==="status")return json({ok:true,...safeOrderStatus(order)});

    if(action==="cancel"){
      if(order.payment_status==="COMPLETED")return json({ok:true,...safeOrderStatus(order)});
      const {data:updated,error}=await admin.from("fts_selfie_print_orders").update({
        payment_status:"CANCELLED",print_status:"BLOCKED",cancelled_at:new Date().toISOString(),updated_at:new Date().toISOString()
      }).eq("id",order.id).neq("payment_status","COMPLETED").select("*").maybeSingle();
      if(error)throw error;
      return json({ok:true,...safeOrderStatus(updated||order)});
    }

    if(action==="capture-order"){
      const paypalOrderId=clean(body.paypal_order_id,80);
      if(!paypalOrderId||paypalOrderId!==order.paypal_order_id)return json({ok:false,error:"PayPal Order-ID stimmt nicht"},400);
      if(order.payment_status==="COMPLETED")return json({ok:true,...safeOrderStatus(order),idempotent:true});

      try{
        const data=await paypalFetch("/v2/checkout/orders/"+encodeURIComponent(paypalOrderId)+"/capture",{
          method:"POST",
          headers:{"PayPal-Request-Id":"fts-selfie-capture-"+order.id},
          body:"{}"
        });
        const capture=data?.purchase_units?.[0]?.payments?.captures?.[0];
        const status=String(capture?.status||data?.status||"").toUpperCase();
        const captureId=clean(capture?.id,120);
        const amountCents=valueToCents(capture?.amount?.value);
        const currency=clean(capture?.amount?.currency_code,10).toUpperCase();
        if(!status||!Number.isFinite(amountCents)||!currency)throw new Error("PayPal Capture-Antwort unvollständig");

        const {data:applied,error:applyError}=await admin.rpc("fts_selfie_apply_payment_capture_v45",{
          p_print_order_id:order.id,p_paypal_order_id:paypalOrderId,p_capture_id:captureId,
          p_status:status,p_amount_cents:amountCents,p_currency:currency,
          p_provider_event_id:null,p_event_type:"CAPTURE_API",p_verified:true,
          p_details:{source:"server_capture",paypal_status:status}
        });
        if(applyError)throw applyError;
        return json({ok:true,...(applied||{}),paypal_status:status});
      }catch(e){
        await admin.from("fts_selfie_print_orders").update({
          last_error:clean((e as any)?.message||e,500),updated_at:new Date().toISOString()
        }).eq("id",order.id);
        throw e;
      }
    }

    return json({ok:false,error:"Unbekannte Aktion"},400);
  }catch(e){
    console.error("paypal-selfie-checkout",e);
    return json({ok:false,error:clean((e as any)?.message||e,500)},(e as any)?.status||500);
  }
});