self.FTS_CONFIG = {
  supabaseUrl: "https://hivmiqktbaatghuaxfvg.supabase.co",
  publishableKey: "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P",
  liveBucket: "fts-selfie-live",
  legacyBucket: "fts-selfie-uploads",
  baseUrl: "https://ftslufototeamshow.github.io/fts-selfie-event/",
  defaultEventToken: "e_cE5HKlFIJGTFA-78tjIPtrPL",
  cacheVersion: "fts-selfie-v49b-final-guest-stats-social-ads"
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

if (typeof window !== "undefined") {
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
