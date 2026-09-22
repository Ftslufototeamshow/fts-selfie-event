import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"content-type, paypal-transmission-id, paypal-transmission-time, paypal-cert-url, paypal-auth-algo, paypal-transmission-sig",
  "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
};
const allowed=new Set(["PAYMENT.CAPTURE.COMPLETED","PAYMENT.CAPTURE.PENDING","PAYMENT.CAPTURE.DENIED","PAYMENT.CAPTURE.REFUNDED","PAYMENT.CAPTURE.REVERSED"]);
const tokenCache=new Map<string,{token:string;expiresAt:number}>();
type PayPalEnv="sandbox"|"live";

function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}})}
function clean(v:unknown,max=500){return String(v??"").trim().slice(0,max)}
function normalizeEnv(v:unknown):PayPalEnv{return String(v||"").toLowerCase()==="live"?"live":"sandbox"}
function paypalBase(env:PayPalEnv){return env==="sandbox"?"https://api-m.sandbox.paypal.com":"https://api-m.paypal.com"}
function envName(env:PayPalEnv,base:string){return `PAYPAL_SELFIE_${env.toUpperCase()}_${base}`}
function clientId(env:PayPalEnv){return Deno.env.get(envName(env,"CLIENT_ID"))||""}
function secret(env:PayPalEnv){return Deno.env.get(envName(env,"CLIENT_SECRET"))||""}
function webhookId(env:PayPalEnv){return Deno.env.get(envName(env,"WEBHOOK_ID"))||""}
function supabaseAdminKey(){const raw=Deno.env.get("SUPABASE_SECRET_KEYS")||"";if(raw){try{const keys=JSON.parse(raw);if(keys?.default)return String(keys.default)}catch{}}return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||""}
function valueToCents(v:unknown){const n=Number(String(v??"").replace(",","."));return Number.isFinite(n)?Math.round(n*100):NaN}

async function accessToken(env:PayPalEnv){const cached=tokenCache.get(env);if(cached&&Date.now()<cached.expiresAt-60_000)return cached.token;if(!clientId(env)||!secret(env))throw new Error(`PayPal ${env==="live"?"Live":"Sandbox"} Client ID/Secret fehlen`);const r=await fetch(paypalBase(env)+"/v1/oauth2/token",{method:"POST",headers:{"Authorization":"Basic "+btoa(clientId(env)+":"+secret(env)),"Content-Type":"application/x-www-form-urlencoded"},body:"grant_type=client_credentials"});const data=await r.json().catch(()=>({}));if(!r.ok||!data?.access_token)throw new Error(`PayPal ${env==="live"?"Live":"Sandbox"} OAuth fehlgeschlagen`);const entry={token:String(data.access_token),expiresAt:Date.now()+Math.max(60,Number(data.expires_in||300))*1000};tokenCache.set(env,entry);return entry.token}

async function verifyWithPayPal(rawEvent:string,headers:Headers,env:PayPalEnv){if(!webhookId(env))throw new Error(`PayPal ${env==="live"?"Live":"Sandbox"} Webhook-ID fehlt`);const transmissionId=clean(headers.get("paypal-transmission-id"),200),transmissionTime=clean(headers.get("paypal-transmission-time"),100),certUrl=clean(headers.get("paypal-cert-url"),1000),authAlgo=clean(headers.get("paypal-auth-algo"),100),transmissionSig=clean(headers.get("paypal-transmission-sig"),2000);if(!transmissionId||!transmissionTime||!certUrl||!authAlgo||!transmissionSig)return false;const verifyBody="{"+"\"transmission_id\":"+JSON.stringify(transmissionId)+","+"\"transmission_time\":"+JSON.stringify(transmissionTime)+","+"\"cert_url\":"+JSON.stringify(certUrl)+","+"\"auth_algo\":"+JSON.stringify(authAlgo)+","+"\"transmission_sig\":"+JSON.stringify(transmissionSig)+","+"\"webhook_id\":"+JSON.stringify(webhookId(env))+","+"\"webhook_event\":"+rawEvent+"}";const token=await accessToken(env);const r=await fetch(paypalBase(env)+"/v1/notifications/verify-webhook-signature",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:verifyBody});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(`PayPal ${env==="live"?"Live":"Sandbox"} Webhook-Verifikation fehlgeschlagen`);return String(data?.verification_status||"").toUpperCase()==="SUCCESS"}
function eventStatus(eventType:string,resource:any){if(eventType==="PAYMENT.CAPTURE.COMPLETED")return "COMPLETED";if(eventType==="PAYMENT.CAPTURE.PENDING")return "PENDING";if(eventType==="PAYMENT.CAPTURE.DENIED")return "DENIED";if(eventType==="PAYMENT.CAPTURE.REFUNDED")return "REFUNDED";if(eventType==="PAYMENT.CAPTURE.REVERSED")return "REVERSED";return String(resource?.status||"").toUpperCase()}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method==="GET")return json({ok:true,service:"paypal-selfie-webhook",environments:{sandbox:{configured:!!(clientId("sandbox")&&secret("sandbox")&&webhookId("sandbox"))},live:{configured:!!(clientId("live")&&secret("live")&&webhookId("live"))}},accepts:[...allowed]});
  if(req.method!=="POST")return json({ok:false,error:"Method not allowed"},405);
  try{
    const supabaseUrl=Deno.env.get("SUPABASE_URL"),adminKey=supabaseAdminKey();if(!supabaseUrl||!adminKey)throw new Error("Supabase Server-Konfiguration fehlt");const admin=createClient(supabaseUrl,adminKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const raw=await req.text();let event:any;try{event=JSON.parse(raw)}catch{return json({ok:false,error:"Invalid JSON"},400)}
    const eventType=clean(event?.event_type,120);if(!allowed.has(eventType))return json({ok:true,ignored:true,event_type:eventType||null});const providerEventId=clean(event?.id,180);if(!providerEventId)return json({ok:false,error:"PayPal Event-ID fehlt"},400);
    const resource=event?.resource||{},related=resource?.supplementary_data?.related_ids||{},orderId=clean(related?.order_id,120),relatedCaptureId=clean(related?.capture_id,120),captureId=eventType==="PAYMENT.CAPTURE.REFUNDED"?relatedCaptureId:clean(resource?.id,120);
    let order:any=null;if(orderId){const q=await admin.from("fts_selfie_print_orders").select("*").eq("paypal_order_id",orderId).maybeSingle();if(q.error)throw q.error;order=q.data}if(!order&&captureId){const q=await admin.from("fts_selfie_print_orders").select("*").eq("paypal_capture_id",captureId).maybeSingle();if(q.error)throw q.error;order=q.data}
    if(!order){console.warn("PayPal webhook: unbekannter FTS Auftrag",eventType,orderId,captureId);return json({ok:true,ignored:true,reason:"unknown_order"})}
    const env=normalizeEnv(order.paypal_environment),verified=await verifyWithPayPal(raw,req.headers,env);if(!verified)return json({ok:false,error:"PayPal Webhook-Signatur ungültig"},400);
    const status=eventStatus(eventType,resource);let amountCents=valueToCents(resource?.amount?.value),currency=clean(resource?.amount?.currency_code,10).toUpperCase();if(status==="REVERSED"&&(!Number.isFinite(amountCents)||!currency)){amountCents=Number(order.total_cents);currency=String(order.currency||"EUR")}if(!Number.isFinite(amountCents)||amountCents<=0||!currency)throw new Error("PayPal Webhook ohne gültigen Betrag/Währung");
    const {data:applied,error:applyError}=await admin.rpc("fts_selfie_apply_payment_capture_v45",{p_print_order_id:order.id,p_paypal_order_id:order.paypal_order_id,p_capture_id:captureId||order.paypal_capture_id||"",p_status:status,p_amount_cents:amountCents,p_currency:currency,p_provider_event_id:providerEventId,p_event_type:eventType,p_verified:true,p_details:{source:"paypal_webhook",paypal_environment:env,event_type:eventType,resource_status:clean(resource?.status,80),final_capture:resource?.final_capture===true,refund_id:eventType==="PAYMENT.CAPTURE.REFUNDED"?clean(resource?.id,120):null}});if(applyError)throw applyError;
    return json({ok:true,verified:true,paypal_environment:env,event_type:eventType,result:applied||null});
  }catch(e){console.error("paypal-selfie-webhook",e);return json({ok:false,error:clean((e as any)?.message||e,500)},500)}
});