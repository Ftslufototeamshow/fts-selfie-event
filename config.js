self.FTS_CONFIG = {
  supabaseUrl: "https://hivmiqktbaatghuaxfvg.supabase.co",
  publishableKey: "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P",
  liveBucket: "fts-selfie-live",
  legacyBucket: "fts-selfie-uploads",
  baseUrl: "https://ftslufototeamshow.github.io/fts-selfie-event/",
  defaultEventToken: "KUERBIS26",
  cacheVersion: "fts-selfie-v54-print-freeze-fix"
};

function ftsLoadScriptOnce(src, marker, onload) {
  if (document.querySelector(`script[${marker}]`)) { if (onload) onload(); return; }
  const s = document.createElement("script");
  s.src = src;s.async = true;s.setAttribute(marker, "1");
  if (onload) s.onload = onload;
  document.head.appendChild(s);
}

function ftsApplyPrintBillingV47Polish(page) {
  if (page === "admin.html") {
    const apply = () => {
      const enabled=document.getElementById("printEnabled"),mode=document.getElementById("printBillingMode"),customer=document.getElementById("nexoaCustomerId"),event=document.getElementById("nexoaEventId"),hint=document.getElementById("nexoaBillingHint");
      if(!enabled||!mode||!customer||!event)return false;
      const refresh=()=>{const needs=enabled.checked&&["organizer_flat","fts_free"].includes(mode.value);if(hint&&needs&&!/Nexoa-Status:/.test(hint.textContent||""))hint.textContent=mode.value==="fts_free"?"Pflicht: Nexoa-Kunde und Nexoa-Event auswählen. Die Gratisleistung wird nach Eventende als Sponsoring/Gratisleistung für die Buchhaltung vorbereitet.":"Pflicht: Nexoa-Kunde und Nexoa-Event auswählen. Der vereinbarte Fixpreis wird nach Eventende für die Nexoa-Rechnung bereitgestellt."};
      mode.addEventListener("change",refresh);enabled.addEventListener("change",refresh);refresh();
      if(typeof persistPrintSetting==="function"&&!persistPrintSetting.__ftsV47Final){const original=persistPrintSetting;const wrapped=async function(eventToken){if(enabled.checked&&["organizer_flat","fts_free"].includes(mode.value)&&(!customer.value||!event.value))throw new Error("Bitte Nexoa-Kunde und Nexoa-Event auswählen, damit die Fotoprint-Abrechnung korrekt zugeordnet wird.");return original(eventToken)};wrapped.__ftsV47Final=true;persistPrintSetting=wrapped}
      return true;
    };
    if(!apply()){let tries=0;const timer=setInterval(()=>{tries++;if(apply()||tries>40)clearInterval(timer)},100)}
  }
  if(page==="print.html"){
    const top=document.querySelector(".brand p");if(top)top.textContent="Fotoprint-Aufträge sicher prüfen, drucken und dokumentieren.";
    const live=document.querySelector("#liveView .sectionHead p");if(live)live.textContent="Druckbereit nach bestätigter Gastzahlung oder wenn Veranstalter/FTS die Prints übernimmt.";
  }
}

function ftsPageV53(){try{return(location.pathname.split("/").pop()||"index.html").toLowerCase()}catch{return"index.html"}}
function ftsGuestTokenV53(){try{return new URLSearchParams(location.search).get("e")||self.FTS_CONFIG.defaultEventToken}catch{return self.FTS_CONFIG.defaultEventToken}}

function ftsInstallFetchGuardV53(){
  if(typeof window==="undefined"||ftsPageV53()!=="index.html"||window.__ftsFetchGuardV53)return;
  window.__ftsFetchGuardV53=true;
  const nativeFetch=window.fetch.bind(window);window.__ftsNativeFetchV53=nativeFetch;
  window.fetch=function(input,init={}){
    let url="";try{url=typeof input==="string"?input:String(input?.url||"")}catch{}
    if(/\/functions\/v1\/fts-scan(?:\?|$)/.test(url)&&typeof init?.body==="string"){
      try{const body=JSON.parse(init.body);if(body&&body.session_id&&!body.visitor_id)return Promise.resolve(new Response('{"ok":true,"legacy_suppressed":true}',{status:200,headers:{"Content-Type":"application/json"}}))}catch{}
    }
    let exact=false;try{exact=new URL(url,location.href).pathname.endsWith('/rest/v1/rpc/fts_get_event')}catch{}
    if(!exact||init.signal)return nativeFetch(input,init);
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),7000);
    return nativeFetch(input,{...init,signal:controller.signal}).finally(()=>clearTimeout(timer));
  };
}

function ftsResetGuestWorkerV53(){
  if(typeof window==="undefined"||ftsPageV53()!=="index.html"||!("serviceWorker" in navigator)||!navigator.serviceWorker.controller)return;
  try{
    const key="fts_guest_sw_reset_v54";if(sessionStorage.getItem(key)==="1")return;sessionStorage.setItem(key,"1");
    Promise.resolve().then(async()=>{
      try{const regs=await navigator.serviceWorker.getRegistrations();await Promise.all(regs.filter(r=>String(r.scope||"").includes("/fts-selfie-event/")).map(r=>r.unregister().catch(()=>false)))}catch{}
      try{if("caches" in window){const keys=await caches.keys();await Promise.all(keys.filter(k=>String(k).startsWith("fts-selfie-")).map(k=>caches.delete(k).catch(()=>false)))}}catch{}
      const u=new URL(location.href);u.searchParams.set("fts_boot","54");u.searchParams.set("v",String(Date.now()));location.replace(u.toString());
    });
  }catch{}
}

function ftsInstallGuestWatchdogV53(){
  if(typeof window==="undefined"||ftsPageV53()!=="index.html")return;
  setTimeout(()=>{const card=document.getElementById("card");if(!card||!/Event wird geladen/i.test(card.textContent||""))return;try{if(typeof boot==="function"&&!window.__ftsBootRetryV53){window.__ftsBootRetryV53=true;void boot()}}catch{}},4500);
  setTimeout(()=>{const card=document.getElementById("card");if(!card||!/Event wird geladen/i.test(card.textContent||""))return;card.innerHTML='<div class="loading"><h2>Event konnte nicht vollständig geladen werden.</h2><p>Bitte Internetverbindung kurz prüfen und erneut laden.</p><button type="button" class="main" id="ftsRetryGuestV53">Erneut laden</button></div>';document.getElementById("ftsRetryGuestV53")?.addEventListener("click",()=>{const u=new URL(location.href);u.searchParams.set("v",String(Date.now()));location.replace(u.toString())})},10500);
}

function ftsGuestBaseReadyV53(){try{const card=document.getElementById("card");return typeof ev!=="undefined"&&!!ev&&!!card&&!/Event wird geladen/i.test(card.textContent||"")}catch{return false}}
function ftsLoadGuestRuntimeV53(){
  let tries=0;const timer=setInterval(()=>{
    tries++;if(!ftsGuestBaseReadyV53()){if(tries>200)clearInterval(timer);return}clearInterval(timer);
    try{const u=new URL(location.href);for(const k of ["fts_boot","fts_retry","v"])u.searchParams.delete(k);history.replaceState(null,"",u.toString())}catch{}
    ftsLoadScriptOnce("./print-billing-guest-v54.js?v=54","data-fts-print-billing-guest-v54",()=>{
      ftsLoadScriptOnce("./guest-runtime-v52.js?v=54","data-fts-guest-runtime-v52");
    });
  },100);
}

if(typeof window!=="undefined"){
  const page=ftsPageV53();
  if(page==="index.html"){
    ftsInstallFetchGuardV53();ftsInstallGuestWatchdogV53();ftsResetGuestWorkerV53();
    window.addEventListener("load",ftsLoadGuestRuntimeV53,{once:true});
  }else{
    window.addEventListener("load",()=>{
      if(page==="admin.html"||page==="print.html"){
        ftsLoadScriptOnce("./print-billing-v47.js?v=54","data-fts-print-billing-v47",()=>{if(page==="print.html")ftsLoadScriptOnce("./print-billing-v47-fix.js?v=54","data-fts-print-billing-v47-fix");ftsApplyPrintBillingV47Polish(page)});
      }
      if(page==="admin.html"){
        ftsLoadScriptOnce("./gallery-links-v48.js?v=54","data-fts-gallery-links-v48",()=>ftsLoadScriptOnce("./admin-social-v52.js?v=54","data-fts-admin-social-v52"));
      }
      if(page==="dashboard.html"){
        ftsLoadScriptOnce("./dashboard-stats-v49.js?v=54","data-fts-dashboard-stats-v49",()=>ftsLoadScriptOnce("./dashboard-stats-v52.js?v=54","data-fts-dashboard-stats-v52"));
      }
    });
  }
}
