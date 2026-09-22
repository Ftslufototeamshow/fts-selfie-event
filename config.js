self.FTS_CONFIG = {
  supabaseUrl: "https://hivmiqktbaatghuaxfvg.supabase.co",
  publishableKey: "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P",
  liveBucket: "fts-selfie-live",
  legacyBucket: "fts-selfie-uploads",
  baseUrl: "https://ftslufototeamshow.github.io/fts-selfie-event/",
  defaultEventToken: "e_cE5HKlFIJGTFA-78tjIPtrPL",
  cacheVersion: "fts-selfie-v47-print-billing"
};

if (typeof window !== "undefined") {
  window.addEventListener("load", () => {
    const page = (location.pathname.split("/").pop() || "index.html").toLowerCase();
    if (!["index.html", "admin.html", "print.html", ""].includes(page)) return;
    if (document.querySelector('script[data-fts-print-billing-v47]')) return;
    const script = document.createElement("script");
    script.src = "./print-billing-v47.js?v=47";
    script.async = true;
    script.dataset.ftsPrintBillingV47 = "1";
    document.head.appendChild(script);
  });
}
