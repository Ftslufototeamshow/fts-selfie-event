self.FTS_CONFIG = {
  supabaseUrl: "https://hivmiqktbaatghuaxfvg.supabase.co",
  publishableKey: "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P",
  liveBucket: "fts-selfie-live",
  legacyBucket: "fts-selfie-uploads",
  baseUrl: "https://ftslufototeamshow.github.io/fts-selfie-event/",
  defaultEventToken: "KUERBIS26",
  cacheVersion: "fts-selfie-v51-stable-boot"
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
      mode.addEventListener("change", refresh);
      enabled.addEventListener("change", refresh);
      refresh();
      if (typeof persistPrintSetting === "function" && !persistPrintSetting.__ftsV47Final) {
        const original = persistPrintSetting;
        const wrapped = async function(eventToken) {
          const currentMode = mode.value;
          if (enabled.checked && ["organizer_flat", "fts_free"].includes(currentMode) && (!customer.value || !event.value)) {
            throw new Error("Bitte Nexoa-Kunde und Nexoa-Event auswählen, damit die Fotoprint-Abrechnung korrekt zugeordnet wird.");
          }
          return await original(eventToken);
        };
        wrapped.__ftsV47Final = true;
        persistPrintSetting = wrapped;
      }
      return true;
    };
    if (!apply()) {
      let tries = 0;
      const timer = setInterval(() => {
        tries += 1;
        if (apply() || tries > 40) clearInterval(timer);
      }, 100);
    }
  }
  if (page === "print.html") {
    const top = document.querySelector(".brand p");
    if (top) top.textContent = "Fotoprint-Aufträge sicher prüfen, drucken und dokumentieren.";
    const live = document.querySelector("#liveView .sectionHead p");
    if (live) live.textContent = "Druckbereit nach bestätigter Gastzahlung oder wenn Veranstalter/FTS die Prints übernimmt.";
  }
}

function ftsLoadScriptOnce(src, marker, onload) {
  if (document.querySelector(`script[${marker}]`)) {
    if (onload) onload();
    return;
  }
  const s = document.createElement("script");
  s.src = src;
  s.async = true;
  s.setAttribute(marker, "1");
  if (onload) s.onload = onload;
  document.head.appendChild(s);
}

function ftsPageV51() {
  try { return (location.pathname.split("/").pop() || "index.html").toLowerCase(); }
  catch { return "index.html"; }
}

function ftsGuestTokenV51() {
  try { return new URLSearchParams(location.search).get("e") || self.FTS_CONFIG.defaultEventToken; }
  catch { return self.FTS_CONFIG.defaultEventToken; }
}

function ftsReportGuestBootV51(message, details = {}, severity = "warning") {
  if (typeof window === "undefined" || !navigator.onLine) return;
  try {
    const nativeFetch = window.__ftsNativeFetchV51 || window.fetch.bind(window);
    nativeFetch(`${self.FTS_CONFIG.supabaseUrl}/functions/v1/fts-client-issue`, {
      method: "POST",
      keepalive: true,
      headers: {"apikey": self.FTS_CONFIG.publishableKey, "Content-Type": "application/json"},
      body: JSON.stringify({
        event_token: ftsGuestTokenV51(),
        issue_type: "guest_loader",
        severity,
        message: String(message || "Gastseite Ladeproblem").slice(0, 500),
        details,
        issue_key: "guest-loader-v51",
        resolved: false,
        session_id: "guest-v51"
      })
    }).catch(() => {});
  } catch {}
}

function ftsInstallInitialRpcTimeoutV51() {
  if (typeof window === "undefined" || ftsPageV51() !== "index.html") return;
  if (window.__ftsFetchTimeoutV51) return;
  window.__ftsFetchTimeoutV51 = true;
  const nativeFetch = window.fetch.bind(window);
  window.__ftsNativeFetchV51 = nativeFetch;
  window.fetch = function(input, init = {}) {
    let url = "";
    try { url = typeof input === "string" ? input : String(input?.url || ""); } catch {}
    const isInitialEventRpc = /\/rest\/v1\/rpc\/fts_get_event(?:$|_|\?)/.test(url);
    if (!isInitialEventRpc || init.signal) return nativeFetch(input, init);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 7000);
    return nativeFetch(input, {...init, signal: controller.signal}).finally(() => clearTimeout(timer));
  };
}

function ftsResetOldGuestWorkerV51() {
  if (typeof window === "undefined" || ftsPageV51() !== "index.html") return;
  if (!("serviceWorker" in navigator) || !navigator.serviceWorker.controller) return;
  try {
    const key = "fts_guest_sw_reset_v51";
    if (sessionStorage.getItem(key) === "1") return;
    sessionStorage.setItem(key, "1");
    Promise.resolve().then(async () => {
      try {
        const regs = await navigator.serviceWorker.getRegistrations();
        await Promise.all(regs.filter(r => String(r.scope || "").includes("/fts-selfie-event/")).map(r => r.unregister().catch(() => false)));
      } catch {}
      try {
        if ("caches" in window) {
          const keys = await caches.keys();
          await Promise.all(keys.filter(k => String(k).startsWith("fts-selfie-")).map(k => caches.delete(k).catch(() => false)));
        }
      } catch {}
      const u = new URL(location.href);
      u.searchParams.set("fts_boot", "51");
      u.searchParams.set("v", String(Date.now()));
      location.replace(u.toString());
    });
  } catch {}
}

function ftsInstallGuestWatchdogV51() {
  if (typeof window === "undefined" || ftsPageV51() !== "index.html") return;

  window.addEventListener("error", e => {
    ftsReportGuestBootV51("JavaScript-Fehler auf der Gastseite", {
      message: String(e?.message || ""),
      file: String(e?.filename || ""),
      line: Number(e?.lineno || 0)
    }, "error");
  });
  window.addEventListener("unhandledrejection", e => {
    ftsReportGuestBootV51("Unbehandelter Fehler auf der Gastseite", {
      reason: String(e?.reason?.message || e?.reason || "").slice(0, 500)
    }, "error");
  });

  setTimeout(() => {
    const card = document.getElementById("card");
    if (!card || !/Event wird geladen/i.test(card.textContent || "")) return;
    ftsReportGuestBootV51("Gastseite: erster Eventabruf dauert zu lange", {token: ftsGuestTokenV51()});
    try {
      if (typeof boot === "function" && !window.__ftsBootRetryV51) {
        window.__ftsBootRetryV51 = true;
        void boot();
      }
    } catch (e) {
      ftsReportGuestBootV51("Gastseite: Wiederholungsversuch konnte nicht gestartet werden", {error: String(e?.message || e)}, "error");
    }
  }, 4500);

  setTimeout(() => {
    const card = document.getElementById("card");
    if (!card || !/Event wird geladen/i.test(card.textContent || "")) return;
    const u = new URL(location.href);
    if (u.searchParams.get("fts_retry") !== "1") {
      ftsReportGuestBootV51("Gastseite: automatischer Neustart nach Ladefehler", {token: ftsGuestTokenV51()}, "error");
      u.searchParams.set("fts_retry", "1");
      u.searchParams.set("v", String(Date.now()));
      location.replace(u.toString());
      return;
    }
    card.innerHTML = `<div class="loading"><h2>Event konnte nicht vollständig geladen werden.</h2><p>Bitte Internetverbindung kurz prüfen und erneut laden.</p><button type="button" class="main" id="ftsRetryGuestV51">Erneut laden</button></div>`;
    document.getElementById("ftsRetryGuestV51")?.addEventListener("click", () => {
      const next = new URL(location.href);
      next.searchParams.delete("fts_retry");
      next.searchParams.set("v", String(Date.now()));
      location.replace(next.toString());
    });
  }, 10500);
}

function ftsGuestBaseReadyV51() {
  try {
    const card = document.getElementById("card");
    return typeof ev !== "undefined" && !!ev && !!card && !/Event wird geladen/i.test(card.textContent || "");
  } catch { return false; }
}

function ftsLoadGuestExtensionsV51() {
  let tries = 0;
  const timer = setInterval(() => {
    tries += 1;
    if (!ftsGuestBaseReadyV51()) {
      if (tries > 200) clearInterval(timer);
      return;
    }
    clearInterval(timer);
    try {
      const u = new URL(location.href);
      if (u.searchParams.has("fts_boot") || u.searchParams.has("fts_retry") || u.searchParams.has("v")) {
        u.searchParams.delete("fts_boot");
        u.searchParams.delete("fts_retry");
        u.searchParams.delete("v");
        history.replaceState(null, "", u.toString());
      }
    } catch {}
    ftsLoadScriptOnce("./print-billing-v47.js?v=51", "data-fts-print-billing-v47", () => ftsApplyPrintBillingV47Polish("index.html"));
    ftsLoadScriptOnce("./gallery-links-v48.js?v=51", "data-fts-gallery-links-v48", () => {
      ftsLoadScriptOnce("./guest-final-v49b.js?v=51", "data-fts-guest-final-v49b");
    });
  }, 100);
}

if (typeof window !== "undefined") {
  const page = ftsPageV51();
  if (page === "index.html") {
    ftsInstallInitialRpcTimeoutV51();
    ftsInstallGuestWatchdogV51();
    ftsResetOldGuestWorkerV51();
    window.addEventListener("load", ftsLoadGuestExtensionsV51, {once: true});
  } else {
    window.addEventListener("load", () => {
      if (page === "admin.html" || page === "print.html") {
        ftsLoadScriptOnce("./print-billing-v47.js?v=51", "data-fts-print-billing-v47", () => {
          if (page === "print.html") ftsLoadScriptOnce("./print-billing-v47-fix.js?v=51", "data-fts-print-billing-v47-fix");
          ftsApplyPrintBillingV47Polish(page);
        });
      }
      if (page === "admin.html") {
        ftsLoadScriptOnce("./gallery-links-v48.js?v=51", "data-fts-gallery-links-v48", () => {
          ftsLoadScriptOnce("./guest-final-v49b.js?v=51", "data-fts-guest-final-v49b");
        });
      }
      if (page === "dashboard.html") {
        ftsLoadScriptOnce("./dashboard-stats-v49.js?v=51", "data-fts-dashboard-stats-v49");
      }
    });
  }
}
