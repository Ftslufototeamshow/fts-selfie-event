import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
};
const UNIT_PRICE_CENTS=200;
const CURRENCY="EUR";
const MAX_TOTAL_QTY=50;
const PUBLIC_BASE="https://ftslufototeamshow.github.io/fts-selfie-event/index.html";
let merchantCache:{code:string;expiresAt:number}|null=null;

function json(body:unknown,status=200){
  return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
}
function clean(v:unknown,max=300){return String(v??"").trim().slice(0,max)}
function centsToValue(cents:number){return (cents/100).toFixed(2)}
function valueToCents(v:unknown){const n=Number(String(v??"").replace(",","."));return Number.isFinite(n)?Math.round(n*100):NaN}
function supabaseAdminKey(){
  const raw=Deno.env.get("SUPABASE_SECRET_KEYS")||"";
  if(raw){try{const keys=JSON.parse(raw);if(keys?.default)return String(keys.default)}catch{}}
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
}
function sumupKey(){return Deno.env.get("SUMUP_SELFIE_API_KEY")||""}

async function sumupFetch(path:string,init:RequestInit={}){
  const key=sumupKey();
  if(!key)throw new Error("SUMUP_SELFIE_API_KEY fehlt");
  const r=await fetch("https://api.sumup.com"+path,{
    ...init,
    headers:{
      "Authorization":"Bearer "+key,
      "Content-Type":"application/json",
      "Accept":"application/json",
      ...(init.headers||{})
    }
  });
  const txt=await r.text();
  let data:any={};try{data=txt?JSON.parse(txt):{}}catch{data={raw:txt}}
  if(!r.ok){
    const err:any=new Error(data?.detail||data?.message||data?.title||`SumUp HTTP ${r.status}`);
    err.status=r.status;err.sumup=data;throw err;
  }
  return data;
}
async function merchantCode(){
  if(merchantCache&&Date.now()<merchantCache.expiresAt)return merchantCache.code;
  const me=await sumupFetch("/v0.1/me",{method:"GET"});
  const code=clean(me?.merchant_profile?.merchant_code||me?.merchant_code||me?.merchant?.merchant_code,40);
  if(!code)throw new Error("SumUp Händlercode konnte nicht ermittelt werden");
  merchantCache={code,expiresAt:Date.now()+10*60_000};
  return code;
}
async function bodyOf(req:Request){
  if(req.method==="GET")return Object.fromEntries(new URL(req.url).searchParams.entries());
  return await req.json().catch(()=>({}));
}
async function findEvent(admin:any,input:string){
  let q=await admin.from("fts_selfie_events").select("id,token,short_code,title,active,archived_at,expires_at").eq("token",input).maybeSingle();
  if(q.error)throw q.error;if(q.data)return q.data;
  q=await admin.from("fts_selfie_events").select("id,token,short_code,title,active,archived_at,expires_at").eq("short_code",input.toUpperCase()).maybeSingle();
  if(q.error)throw q.error;return q.data;
}
async function eventSetting(admin:any,eventId:string){
  const {data,error}=await admin.from("fts_selfie_print_settings")
    .select("enabled,print_starts_at,print_ends_at,unit_price_cents,currency,paypal_environment,billing_mode,organizer_flat_price_cents,payment_provider,sumup_environment")
    .eq("event_id",eventId).maybeSingle();
  if(error)throw error;return data;
}
function windowActive(setting:any){
  if(!setting?.enabled)return false;
  if(Number(setting.unit_price_cents||UNIT_PRICE_CENTS)!==UNIT_PRICE_CENTS)return false;
  if(String(setting.currency||CURRENCY).toUpperCase()!==CURRENCY)return false;
  const now=Date.now(),start=setting.print_starts_at?Date.parse(setting.print_starts_at):NaN,end=setting.print_ends_at?Date.parse(setting.print_ends_at):NaN;
  if(Number.isFinite(start)&&now<start)return false;
  if(Number.isFinite(end)&&now>end)return false;
  return true;
}
function normalizeItems(rawItems:any[]){
  if(!Array.isArray(rawItems)||!rawItems.length||rawItems.length>20)throw new Error("Bitte mindestens ein Foto auswählen");
  const normalized=new Map<string,number>();
  for(const raw of rawItems){
    const id=clean(raw?.photo_id,80),qty=Number(raw?.quantity);
    if(!/^[0-9a-f-]{36}$/i.test(id)||!Number.isInteger(qty)||qty<1||qty>20)throw new Error("Ungültige Foto-Auswahl oder Anzahl");
    normalized.set(id,(normalized.get(id)||0)+qty);
  }
  const ids=[...normalized.keys()],quantityTotal=[...normalized.values()].reduce((a,b)=>a+b,0);
  if(quantityTotal<1||quantityTotal>MAX_TOTAL_QTY)throw new Error("Maximal 50 Ausdrucke pro Auftrag");
  return {normalized,ids,quantityTotal};
}
async function validatePhotos(admin:any,eventId:string,sessionId:string,ids:string[],environment:string){
  let q=admin.from("fts_selfie_photos")
    .select("id,designed_path,event_id,guest_session_id,is_test,trashed_at,event_day")
    .in("id",ids).eq("event_id",eventId).eq("guest_session_id",sessionId).is("trashed_at",null);
  if(environment==="live")q=q.eq("is_test",false);
  const {data,error}=await q;if(error)throw error;
  if((data||[]).length!==ids.length||(data||[]).some((p:any)=>!p.designed_path))throw new Error("Mindestens ein Foto ist nicht für den Druck verfügbar");
  return data||[];
}
async function stockSnapshot(admin:any,eventId:string){
  const {data,error}=await admin.rpc("fts_selfie_stock_snapshot_v70",{p_event_id:eventId});
  if(error)throw error;return data||{managed:false,safe_available:null};
}
async function reserveStock(admin:any,eventId:string,orderId:string,quantity:number,eventDay:string|null=null){
  const {data,error}=await admin.rpc("fts_selfie_reserve_stock_v70",{p_event_id:eventId,p_order_id:orderId,p_quantity:quantity,p_event_day:eventDay});
  if(error)throw error;return data||{ok:true,managed:false};
}
function firstPhotoDay(photos:any[]){const ds=(photos||[]).map((p:any)=>String(p?.event_day||"")).filter(Boolean).sort();return ds[0]||null}
async function stockOr409(admin:any,eventId:string,orderId:string,quantity:number,eventDay:string|null=null){
  const s=await reserveStock(admin,eventId,orderId,quantity,eventDay);
  if(s?.ok===false){const e:any=new Error("Nicht genügend sicherer Fotoprint-Bestand. Der Druckverkauf wurde gestoppt, bevor eine Zahlung ausgelöst wird.");e.status=409;e.stock=s;throw e}
  return s;
}
async function ownedOrder(admin:any,orderId:string,eventId:string,sessionId:string){
  const {data,error}=await admin.from("fts_selfie_print_orders").select("*").eq("id",orderId).eq("event_id",eventId).eq("guest_session_id",sessionId).maybeSingle();
  if(error)throw error;return data;
}
async function receiptForOrder(admin:any,orderId:string){
  const {data,error}=await admin.from("fts_selfie_receipts")
    .select("receipt_number,event_title_snapshot,organizer_snapshot,event_date_snapshot,quantity_total,unit_price_cents,total_cents,refund_cents,currency,payment_method,payment_environment,is_test,pickup_code,payment_status,paid_at,items_snapshot,payment_provider,provider_reference,paypal_order_id,paypal_capture_id")
    .eq("order_id_snapshot",orderId).maybeSingle();
  if(error)throw error;return data;
}
function safeReceipt(r:any){
  if(!r)return null;
  return {
    receipt_number:r.receipt_number,event_title:r.event_title_snapshot,organizer_name:r.organizer_snapshot,event_date:r.event_date_snapshot,
    quantity_total:r.quantity_total,unit_price_cents:r.unit_price_cents,total_cents:r.total_cents,refund_cents:r.refund_cents||0,
    net_cents:Number(r.total_cents||0)-Number(r.refund_cents||0),currency:r.currency,payment_method:r.payment_method,
    payment_environment:r.payment_environment||null,is_test:r.is_test===true,pickup_code:r.pickup_code||null,
    payment_provider:r.payment_provider||"sumup",provider_reference:r.provider_reference||r.paypal_capture_id||r.paypal_order_id||null,
    payment_status:r.payment_status,paid_at:r.paid_at,items:Array.isArray(r.items_snapshot)?r.items_snapshot:[]
  };
}
function safeOrderStatus(o:any){
  return {
    order_id:o.id,billing_mode:o.billing_mode||"guest_paypal",payment_provider:o.payment_provider||"sumup",
    sumup_environment:o.sumup_environment||"live",sumup_checkout_id:o.sumup_checkout_id||null,sumup_transaction_id:o.sumup_transaction_id||null,
    payment_status:o.payment_status,print_status:o.print_status,pickup_code:o.pickup_code||null,pickup_status:o.pickup_status||"WAITING_PRINT",
    quantity_total:o.quantity_total,total_cents:o.total_cents,total:centsToValue(Number(o.total_cents||0)),currency:o.currency,
    paid_at:o.paid_at||null,printed_at:o.printed_at||null,pickup_ready_at:o.pickup_ready_at||null,picked_up_at:o.picked_up_at||null
  };
}
function successfulTransaction(checkout:any){
  const txs=Array.isArray(checkout?.transactions)?checkout.transactions:[];
  return txs.find((x:any)=>["SUCCESSFUL","PAID_OUT"].includes(String(x?.status||"").toUpperCase()))||txs[0]||null;
}
async function reconcile(admin:any,order:any){
  if(!order?.sumup_checkout_id)throw new Error("SumUp Checkout-ID fehlt");
  const checkout=await sumupFetch("/v0.1/checkouts/"+encodeURIComponent(order.sumup_checkout_id),{method:"GET"});
  const ref=clean(checkout?.checkout_reference,80);
  if(ref!==`FTS-PRINT-${order.id}`)throw new Error("SumUp Checkout-Referenz stimmt nicht");
  const status=String(checkout?.status||"").toUpperCase();
  const amountCents=valueToCents(checkout?.amount);
  const currency=clean(checkout?.currency,10).toUpperCase();
  const tx=successfulTransaction(checkout),txId=clean(tx?.id,120);
  const {data,error}=await admin.rpc("fts_selfie_apply_sumup_checkout_v93",{
    p_print_order_id:order.id,p_sumup_checkout_id:order.sumup_checkout_id,p_transaction_id:txId,
    p_status:status,p_amount_cents:amountCents,p_currency:currency,
    p_details:{provider:"sumup",checkout_status:status,transaction_status:String(tx?.status||""),transaction_code:tx?.transaction_code||null,payment_type:tx?.payment_type||null}
  });
  if(error)throw error;
  const {data:fresh,error:freshError}=await admin.from("fts_selfie_print_orders").select("*").eq("id",order.id).single();
  if(freshError)throw freshError;
  return fresh;
}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(!["GET","POST"].includes(req.method))return json({ok:false,error:"Method not allowed"},405);
  try{
    const supabaseUrl=Deno.env.get("SUPABASE_URL"),adminKey=supabaseAdminKey();
    if(!supabaseUrl||!adminKey)throw new Error("Supabase Server-Konfiguration fehlt");
    const admin=createClient(supabaseUrl,adminKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const body:any=await bodyOf(req);
    const action=clean(body.action,40)||"config";

    if(action==="callback"){
      const orderId=clean(body.order_id,80);
      if(!/^[0-9a-f-]{36}$/i.test(orderId))return json({ok:false,error:"Druckauftrag fehlt"},400);
      const {data:order,error}=await admin.from("fts_selfie_print_orders").select("*").eq("id",orderId).eq("payment_provider","sumup").maybeSingle();
      if(error)throw error;if(!order)return json({ok:false,error:"Druckauftrag nicht gefunden"},404);
      const fresh=await reconcile(admin,order);
      return json({ok:true,...safeOrderStatus(fresh)});
    }

    const eventInput=clean(body.event_token,140),sessionId=clean(body.guest_session_id,140);
    if(!eventInput||!sessionId)return json({ok:false,error:"Event oder Gast-Sitzung fehlt"},400);
    const event=await findEvent(admin,eventInput);
    if(!event?.id||event.active!==true||event.archived_at)return json({ok:false,error:"Event nicht verfügbar"},404);
    const setting=await eventSetting(admin,event.id),active=windowActive(setting);
    const provider=String(setting?.payment_provider||"paypal").toLowerCase();
    const environment=String(setting?.sumup_environment||"live").toLowerCase()==="sandbox"?"sandbox":"live";
    const configured=!!sumupKey();
    const stock=await stockSnapshot(admin,event.id),stockBlocked=stock?.managed===true&&Number(stock?.safe_available||0)<=0;

    if(action==="config"){
      return json({
        ok:true,enabled:active&&!stockBlocked,configured,environment,payment_provider:provider,
        unit_price_cents:UNIT_PRICE_CENTS,unit_price:"2.00",currency:CURRENCY,billing_mode:String(setting?.billing_mode||"guest_paypal"),
        guest_payment_required:String(setting?.billing_mode||"guest_paypal")==="guest_paypal",
        starts_at:setting?.print_starts_at||null,ends_at:setting?.print_ends_at||null,
        stock_managed:stock?.managed===true,stock_safe_available:stock?.safe_available??null,stock_blocked:stockBlocked
      });
    }

    if(!active)return json({ok:false,error:"Fotodruck ist für dieses Event gerade nicht freigeschaltet"},403);
    if(provider!=="sumup")return json({ok:false,error:"SumUp ist für dieses Event nicht als Zahlungsanbieter aktiviert"},409);
    if(String(setting?.billing_mode||"guest_paypal")!=="guest_paypal")return json({ok:false,error:"Für dieses Event ist keine Gastzahlung vorgesehen"},409);
    if(!configured)return json({ok:false,error:"SumUp ist serverseitig noch nicht konfiguriert"},503);
    if(stockBlocked)return json({ok:false,error:"Der sichere Fotoprint-Bestand ist aufgebraucht. Selfies funktionieren weiter, neue Druckzahlungen sind vorübergehend gesperrt.",stock},409);

    if(action==="create-order"){
      const {normalized,ids,quantityTotal}=normalizeItems(Array.isArray(body.items)?body.items:[]);
      const photos=await validatePhotos(admin,event.id,sessionId,ids,environment),totalCents=quantityTotal*UNIT_PRICE_CENTS;
      const {data:order,error:orderError}=await admin.from("fts_selfie_print_orders").insert({
        event_id:event.id,guest_session_id:sessionId,paypal_environment:"live",billing_mode:"guest_paypal",
        payment_provider:"sumup",sumup_environment:environment,payment_status:"CREATED",print_status:"BLOCKED",
        unit_price_cents:UNIT_PRICE_CENTS,quantity_total:quantityTotal,total_cents:totalCents,currency:CURRENCY
      }).select("*").single();
      if(orderError)throw orderError;

      const photoMap=new Map(photos.map((p:any)=>[String(p.id),p]));
      const itemRows=ids.map(id=>({
        order_id:order.id,photo_id:id,designed_path_snapshot:String(photoMap.get(id).designed_path),quantity:normalized.get(id),
        unit_price_cents:UNIT_PRICE_CENTS,line_total_cents:Number(normalized.get(id))*UNIT_PRICE_CENTS
      }));
      const {error:itemError}=await admin.from("fts_selfie_print_order_items").insert(itemRows);
      if(itemError){await admin.from("fts_selfie_print_orders").update({payment_status:"ERROR",last_error:"Print items insert failed"}).eq("id",order.id);throw itemError}

      try{
        await stockOr409(admin,event.id,order.id,quantityTotal,firstPhotoDay(photos));
        const merchant_code=await merchantCode();
        const redirect=new URL(PUBLIC_BASE);
        redirect.searchParams.set("e",event.token);
        redirect.searchParams.set("sumup_return","1");
        redirect.searchParams.set("print_order_id",order.id);
        const callback=`${supabaseUrl}/functions/v1/sumup-selfie-checkout?action=callback&order_id=${encodeURIComponent(order.id)}`;
        const validUntil=new Date(Date.now()+30*60_000).toISOString();
        const checkout=await sumupFetch("/v0.1/checkouts",{
          method:"POST",
          body:JSON.stringify({
            checkout_reference:`FTS-PRINT-${order.id}`,
            amount:Number(centsToValue(totalCents)),
            currency:CURRENCY,
            merchant_code,
            description:`FTS Selfie Fotoprint ${quantityTotal}x 10x15`,
            redirect_url:redirect.toString(),
            return_url:callback,
            valid_until:validUntil,
            hosted_checkout:{enabled:true}
          })
        });
        const checkoutId=clean(checkout?.id,120),hostedUrl=clean(checkout?.hosted_checkout_url,600);
        if(!checkoutId||!hostedUrl)throw new Error("SumUp Hosted Checkout konnte nicht erstellt werden");
        const {error:updateError}=await admin.from("fts_selfie_print_orders")
          .update({sumup_checkout_id:checkoutId,payment_status:"PENDING",updated_at:new Date().toISOString()})
          .eq("id",order.id);
        if(updateError)throw updateError;
        return json({ok:true,print_order_id:order.id,sumup_checkout_id:checkoutId,hosted_checkout_url:hostedUrl,total:centsToValue(totalCents),total_cents:totalCents,currency:CURRENCY,payment_provider:"sumup"});
      }catch(e){
        await admin.from("fts_selfie_print_orders").update({payment_status:"ERROR",last_error:clean((e as any)?.message||e,500),updated_at:new Date().toISOString()}).eq("id",order.id);
        throw e;
      }
    }

    const printOrderId=clean(body.print_order_id,80);
    if(!/^[0-9a-f-]{36}$/i.test(printOrderId))return json({ok:false,error:"Druckauftrag fehlt"},400);
    const order=await ownedOrder(admin,printOrderId,event.id,sessionId);
    if(!order)return json({ok:false,error:"Druckauftrag nicht gefunden"},404);
    if(order.payment_provider!=="sumup")return json({ok:false,error:"Dieser Druckauftrag verwendet nicht SumUp"},409);

    if(action==="status"){
      let fresh=order;
      if(order.sumup_checkout_id && !["COMPLETED","REFUNDED","REVERSED"].includes(order.payment_status)){
        fresh=await reconcile(admin,order);
      }
      const receipt=await receiptForOrder(admin,fresh.id);
      return json({ok:true,...safeOrderStatus(fresh),receipt:safeReceipt(receipt)});
    }
    if(action==="receipt"){
      const fresh=order.sumup_checkout_id?await reconcile(admin,order):order;
      if(!["COMPLETED","REFUNDED","REVERSED"].includes(fresh.payment_status))return json({ok:false,error:"Beleg ist erst nach bestätigter Zahlung verfügbar"},409);
      const receipt=await receiptForOrder(admin,fresh.id);
      if(!receipt)return json({ok:false,error:"Beleg wird noch vorbereitet"},404);
      return json({ok:true,receipt:safeReceipt(receipt)});
    }
    return json({ok:false,error:"Unbekannte Aktion"},400);
  }catch(e){
    console.error("sumup-selfie-checkout",e);
    return json({ok:false,error:clean((e as any)?.message||e,500)},(e as any)?.status||500);
  }
});