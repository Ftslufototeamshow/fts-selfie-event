self.FTS_CONFIG = {
  supabaseUrl: "https://hivmiqktbaatghuaxfvg.supabase.co",
  publishableKey: "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P",
  liveBucket: "fts-selfie-live",
  legacyBucket: "fts-selfie-uploads",
  baseUrl: "https://ftslufototeamshow.github.io/fts-selfie-event/",
  defaultEventToken: "e_cE5HKlFIJGTFA-78tjIPtrPL",
  cacheVersion: "fts-selfie-v47-print-billing"
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

if (typeof window !== "undefined") {
  window.addEventListener("load", () => {
    const page = (location.pathname.split("/").pop() || "index.html").toLowerCase();
    if (!["index.html", "admin.html", "print.html", ""].includes(page)) return;
    if (document.querySelector('script[data-fts-print-billing-v47]')) return;
    const script = document.createElement("script");
    script.src = "./print-billing-v47.js?v=47";
    script.async = true;
    script.dataset.ftsPrintBillingV47 = "1";
    script.onload = () => {
      if (page === "print.html" && !document.querySelector('script[data-fts-print-billing-v47-fix]')) {
        const fix = document.createElement("script");
        fix.src = "./print-billing-v47-fix.js?v=47";
        fix.async = true;
        fix.dataset.ftsPrintBillingV47Fix = "1";
        document.head.appendChild(fix);
      }
      ftsApplyPrintBillingV47Polish(page);
    };
    document.head.appendChild(script);
  });
}
