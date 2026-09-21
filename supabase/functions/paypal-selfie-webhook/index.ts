import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const ENVIRONMENT="sandbox";
const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"content-type, paypal-transmission-id, paypal-transmission-time, paypal-cert-url, paypal-auth-algo, paypal-transmission-sig",
  "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
};
const allowed=new Set([
  "PAYMENT.CAPTURE.COMPLETED",
  "PAYMENT.CAPTURE.PENDING",
  "PAYMENT.CAPTURE.DENIED",
  "PAYMENT.CAPTURE.REFUNDED",
  "PAYMENT.CAPTURE.REVERSED"
]);
let tokenCache:{token:string;expiresAt:number}|null=null;

function json(body:unknown,status=200){
  return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
}
function clean(v:unknown,max=500){return String(v??"").trim().slice(0,max)}
function paypalBase(){return ENVIRONMENT==="sandbox"?"https://api-m.sandbox.paypal.com":"https://api-m.paypal.com"}
function envName(base:string){return `PAYPAL_SELFIE_${ENVIRONMENT.toUpperCase()}_${base}`}
function clientId(){return Deno.env.get(envName("CLIENT_ID"))||""}
function secret(){return Deno.env.get(envName("CLIENT_SECRET"))||""}
function webhookId(){return Deno.env.get(envName("WEBHOOK_ID"))||""}
function valueToCents(v:unknown){
  const n=Number(String(v??"").replace(",","."));
  return Number.isFinite(n)?Math.round(n*100):NaN;
}

async function accessToken(){
  if(tokenCache&&Date.now()<tokenCache.expiresAt-60_000)return tokenCache.token;
  if(!clientId()||!secret())throw new Error("PayPal Sandbox Client ID/Secret fehlen");
  const r=await fetch(paypalBase()+"/v1/oauth2/token",{
    method:"POST",
    headers:{"Authorization":"Basic "+btoa(clientId()+":"+secret()),"Content-Type":"application/x-www-form-urlencoded"},
    body:"grant_type=client_credentials"
  });
  const data=await r.json().catch(()=>({}));
  if(!r.ok||!data?.access_token)throw new Error("PayPal OAuth fehlgeschlagen");
  tokenCache={token:String(data.access_token),expiresAt:Date.now()+Math.max(60,Number(data.expires_in||300))*1000};
  return tokenCache.token;
}

async function verifyWithPayPal(rawEvent:string,event:any,headers:Headers){
  if(!webhookId())throw new Error("PayPal Sandbox Webhook-ID fehlt");
  const transmissionId=clean(headers.get("paypal-transmission-id"),200);
  const transmissionTime=clean(headers.get("paypal-transmission-time"),100);
  const certUrl=clean(headers.get("paypal-cert-url"),1000);
  const authAlgo=clean(headers.get("paypal-auth-algo"),100);
  const transmissionSig=clean(headers.get("paypal-transmission-sig"),2000);
  if(!transmissionId||!transmissionTime||!certUrl||!authAlgo||!transmissionSig)return false;

  // PayPal requires webhook_event to be posted back without changing its JSON.
  // Build the verification request around the exact raw event body received from PayPal.
  const verifyBody="{"+
    "\"transmission_id\":"+JSON.stringify(transmissionId)+","+
    "\"transmission_time\":"+JSON.stringify(transmissionTime)+","+
    "\"cert_url\":"+JSON.stringify(certUrl)+","+
    "\"auth_algo\":"+JSON.stringify(authAlgo)+","+
    "\"transmission_sig\":"+JSON.stringify(transmissionSig)+","+
    "\"webhook_id\":"+JSON.stringify(webhookId())+","+
    "\"webhook_event\":"+rawEvent+
  "}";
  const token=await accessToken();
  const r=await fetch(paypalBase()+"/v1/notifications/verify-webhook-signature",{
    method:"POST",
    headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
    body:verifyBody
  });
  const data=await r.json().catch(()=>({}));
  if(!r.ok)throw new Error("PayPal Webhook-Verifikation fehlgeschlagen");
  return String(data?.verification_status||"").toUpperCase()==="SUCCESS";
}

function eventStatus(eventType:string,resource:any){
  if(eventType==="PAYMENT.CAPTURE.COMPLETED")return "COMPLETED";
  if(eventType==="PAYMENT.CAPTURE.PENDING")return "PENDING";
  if(eventType==="PAYMENT.CAPTURE.DENIED")return "DENIED";
  if(eventType==="PAYMENT.CAPTURE.REFUNDED")return "REFUNDED";
  if(eventType==="PAYMENT.CAPTURE.REVERSED")return "REVERSED";
  return String(resource?.status||"").toUpperCase();
}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method==="GET"){
    return json({
      ok:true,
      service:"paypal-selfie-webhook",
      environment:ENVIRONMENT,
      configured:!!(clientId()&&secret()&&webhookId()),
      accepts:[...allowed]
    });
  }
  if(req.method!=="POST")return json({ok:false,error:"Method not allowed"},405);

  try{
    const supabaseUrl=Deno.env.get("SUPABASE_URL"),serviceRole=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!supabaseUrl||!serviceRole)throw new Error("Supabase Server-Konfiguration fehlt");
    const admin=createClient(supabaseUrl,serviceRole,{auth:{persistSession:false,autoRefreshToken:false}});

    const raw=await req.text();
    let event:any;
    try{event=JSON.parse(raw)}catch{return json({ok:false,error:"Invalid JSON"},400)}

    const eventType=clean(event?.event_type,120);
    if(!allowed.has(eventType)){
      return json({ok:true,ignored:true,event_type:eventType||null});
    }

    const verified=await verifyWithPayPal(raw,event,req.headers);
    if(!verified)return json({ok:false,error:"PayPal Webhook-Signatur ungültig"},400);

    const resource=event?.resource||{};
    const related=resource?.supplementary_data?.related_ids||{};
    const orderId=clean(related?.order_id,120);
    const relatedCaptureId=clean(related?.capture_id,120);
    const captureId=eventType==="PAYMENT.CAPTURE.REFUNDED"
      ? relatedCaptureId
      : clean(resource?.id,120);
    const providerEventId=clean(event?.id,180);

    let order:any=null;
    if(orderId){
      const q=await admin.from("fts_selfie_print_orders").select("*").eq("paypal_order_id",orderId).maybeSingle();
      if(q.error)throw q.error;order=q.data;
    }
    if(!order&&captureId){
      const q=await admin.from("fts_selfie_print_orders").select("*").eq("paypal_capture_id",captureId).maybeSingle();
      if(q.error)throw q.error;order=q.data;
    }
    if(!order){
      console.warn("PayPal webhook: unbekannter FTS Auftrag",eventType,orderId,captureId);
      return json({ok:true,ignored:true,reason:"unknown_order"});
    }

    const status=eventStatus(eventType,resource);
    let amountCents=valueToCents(resource?.amount?.value);
    let currency=clean(resource?.amount?.currency_code,10).toUpperCase();

    if(["REFUNDED","REVERSED"].includes(status)){
      amountCents=Number(order.total_cents);
      currency=String(order.currency||"EUR");
    }
    if(!Number.isFinite(amountCents)||!currency){
      throw new Error("PayPal Webhook ohne gültigen Betrag/Währung");
    }

    const {data:applied,error:applyError}=await admin.rpc("fts_selfie_apply_payment_capture_v45",{
      p_print_order_id:order.id,
      p_paypal_order_id:order.paypal_order_id,
      p_capture_id:captureId||order.paypal_capture_id||"",
      p_status:status,
      p_amount_cents:amountCents,
      p_currency:currency,
      p_provider_event_id:providerEventId||null,
      p_event_type:eventType,
      p_verified:true,
      p_details:{
        source:"paypal_webhook",
        event_type:eventType,
        resource_status:clean(resource?.status,80),
        final_capture:resource?.final_capture===true
      }
    });
    if(applyError)throw applyError;

    return json({ok:true,verified:true,event_type:eventType,result:applied||null});
  }catch(e){
    console.error("paypal-selfie-webhook",e);
    return json({ok:false,error:clean((e as any)?.message||e,500)},500);
  }
});