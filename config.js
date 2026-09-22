self.FTS_CONFIG = {
  supabaseUrl: "https://hivmiqktbaatghuaxfvg.supabase.co",
  publishableKey: "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P",
  liveBucket: "fts-selfie-live",
  legacyBucket: "fts-selfie-uploads",
  baseUrl: "https://ftslufototeamshow.github.io/fts-selfie-event/",
  defaultEventToken: "KUERBIS26",
  cacheVersion: "fts-selfie-v50-loader-rescue"
};

function ftsApplyPrintBillingV47Polish(page) {
  if (page === "admin.html") {
    const apply = () => {
      const enabled = document.getElementById("printEnabled");
      const mode = document.getElementById("printBillingMode");
      const customer = document.getElementById("nexoaCustomerId");
      const event = document.getElementById("nexoaEventId");
      const hint = document.getElementById("nexoaBillingHint");
      if (!enabled || !mode || !customer || !event) return false;
      const refresh = () => {
        const needsNexoa = enabled.checked && ["organizer_flat", "fts_free"].includes(mode.value);
        if (hint && needsNexoa && !/Nexoa-Status:/.test(hint.textContent || "")) {
          hint.textContent = mode.value === "fts_free"
            ? "Pflicht: Nexoa-Kunde und Nexoa-Event auswählen. Die Gratisleistung wird nach Eventende als Sponsoring/Gratisleistung für die Buchhaltung vorbereitet."
            : "Pflicht: Nexoa-Kunde und Nexoa-Event auswählen. Der vereinbarte Fixpreis wird nach Eventende für die Nexoa-Rechnung bereitgestellt.";
        }
      };
      mode.addEventListener("change", refresh);enabled.addEventListener("change", refresh);refresh();
      if (typeof persistPrintSetting === "function" && !persistPrintSetting.__ftsV47Final) {
        const original = persistPrintSetting;
        const wrapped = async function(eventToken) {
          const currentMode = mode.value;
          if (enabled.checked && ["organizer_flat", "fts_free"].includes(currentMode) && (!customer.value || !event.value)) throw new Error("Bitte Nexoa-Kunde und Nexoa-Event auswählen, damit die Fotoprint-Abrechnung korrekt zugeordnet wird.");
          return await original(eventToken);
        };
        wrapped.__ftsV47Final = true;persistPrintSetting = wrapped;
      }
      return true;
    };
    if (!apply()) {let tries = 0;const timer = setInterval(() => {tries += 1;if (apply() || tries > 40) clearInterval(timer)}, 100)}
  }
  if (page === "print.html") {
    const top = document.querySelector(".brand p");if (top) top.textContent = "Fotoprint-Aufträge sicher prüfen, drucken und dokumentieren.";
    const live = document.querySelector("#liveView .sectionHead p");if (live) live.textContent = "Druckbereit nach bestätigter Gastzahlung oder wenn Veranstalter/FTS die Prints übernimmt.";
  }
}

function ftsLoadScriptOnce(src, marker, onload) {
  if (document.querySelector(`script[${marker}]`)) { if (onload) onload(); return; }
  const s = document.createElement("script");s.src = src;s.async = true;s.setAttribute(marker, "1");if (onload) s.onload = onload;document.head.appendChild(s);
}

function ftsGuestEventTokenV50() {
  try { return new URLSearchParams(location.search).get("e") || self.FTS_CONFIG.defaultEventToken; }
  catch { return self.FTS_CONFIG.defaultEventToken; }
}

function ftsLoaderSessionV50() {
  try {
    const k="fts_loader_session_v50";let v=sessionStorage.getItem(k);
    if(!v){v=(crypto.randomUUID?crypto.randomUUID():"loader_"+Date.now().toString(36));sessionStorage.setItem(k,v)}
    return v;
  } catch { return "loader"; }
}

function ftsReportLoaderV50(message, details={}, severity="warning") {
  if (typeof window === "undefined" || !navigator.onLine) return;
  try {
    fetch(`${self.FTS_CONFIG.supabaseUrl}/functions/v1/fts-client-issue`, {
      method:"POST",keepalive:true,
      headers:{"apikey":self.FTS_CONFIG.publishableKey,"Content-Type":"application/json"},
      body:JSON.stringify({
        event_token:ftsGuestEventTokenV50(),issue_type:"guest_loader",severity,
        message:String(message||"Gastseite Ladeproblem").slice(0,500),details,
        issue_key:"guest-loader-v50",resolved:false,session_id:ftsLoaderSessionV50()
      })
    }).catch(()=>{});
  } catch {}
}

async function ftsClearGuestRuntimeCacheV50() {
  try {
    if ("serviceWorker" in navigator) {
      const regs=await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.filter(r=>String(r.scope||"").includes("/fts-selfie-event/")).map(r=>r.unregister().catch(()=>false)));
    }
  } catch {}
  try {
    if ("caches" in window) {
      const keys=await caches.keys();
      await Promise.all(keys.filter(k=>String(k).startsWith("fts-selfie-")).map(k=>caches.delete(k).catch(()=>false)));
    }
  } catch {}
}

function ftsInstallGuestLoaderRescueV50() {
  const page=(location.pathname.split("/").pop()||"index.html").toLowerCase();
  if (!["index.html",""] .includes(page)) return;

  window.addEventListener("error",e=>{
    ftsReportLoaderV50("JavaScript-Fehler auf der Gastseite",{message:String(e?.message||""),file:String(e?.filename||""),line:Number(e?.lineno||0)},"error");
  });
  window.addEventListener("unhandledrejection",e=>{
    ftsReportLoaderV50("Unbehandelter Fehler auf der Gastseite",{reason:String(e?.reason?.message||e?.reason||"").slice(0,500)},"error");
  });

  setTimeout(async()=>{
    const card=document.getElementById("card");
    const stillLoading=!!card && /Event wird geladen/i.test(card.textContent||"");
    if(!stillLoading)return;
    const u=new URL(location.href);
    const rescued=u.searchParams.get("fts_rescue")==="1";
    ftsReportLoaderV50(rescued?"Gastseite hängt auch nach Cache-Neustart":"Gastseite hing im alten Laufzeit-Cache",{href:location.pathname+location.search,rescued},rescued?"error":"warning");
    if(rescued)return;
    await ftsClearGuestRuntimeCacheV50();
    if(!u.searchParams.get("e"))u.searchParams.set("e",self.FTS_CONFIG.defaultEventToken);
    u.searchParams.set("fts_rescue","1");
    u.searchParams.set("v",String(Date.now()));
    location.replace(u.toString());
  },6500);

  window.addEventListener("load",()=>{
    setTimeout(()=>{
      const card=document.getElementById("card");
      if(card && !/Event wird geladen/i.test(card.textContent||"")){
        try{
          const u=new URL(location.href);
          if(u.searchParams.has("fts_rescue")||u.searchParams.has("v")){
            u.searchParams.delete("fts_rescue");u.searchParams.delete("v");history.replaceState(null,"",u.toString());
          }
        }catch{}
      }
    },1500);
  });
}

if (typeof window !== "undefined") {
  ftsInstallGuestLoaderRescueV50();
  window.addEventListener("load", () => {
    const page = (location.pathname.split("/").pop() || "index.html").toLowerCase();
    if (!["index.html", "admin.html", "print.html", "dashboard.html", ""].includes(page)) return;
    if (["index.html", "admin.html", "print.html", ""].includes(page)) {
      ftsLoadScriptOnce("./print-billing-v47.js?v=47", "data-fts-print-billing-v47", () => {
        if (page === "print.html") ftsLoadScriptOnce("./print-billing-v47-fix.js?v=47", "data-fts-print-billing-v47-fix");
        ftsApplyPrintBillingV47Polish(page);
      });
    }
    if (["index.html", "admin.html", ""].includes(page)) {
      const loadFinal = () => ftsLoadScriptOnce("./guest-final-v49b.js?v=49b", "data-fts-guest-final-v49b");
      if (document.querySelector('script[data-fts-gallery-links-v48]')) loadFinal();
      else ftsLoadScriptOnce("./gallery-links-v48.js?v=48", "data-fts-gallery-links-v48", loadFinal);
    }
    if (page === "dashboard.html") ftsLoadScriptOnce("./dashboard-stats-v49.js?v=49", "data-fts-dashboard-stats-v49");
  });
}
