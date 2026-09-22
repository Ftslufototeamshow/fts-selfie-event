(()=>{
  const page=(location.pathname.split('/').pop()||'index.html').toLowerCase();

  if(page==='admin.html'){
    const apply=()=>{
      const enabled=document.getElementById('printEnabled');
      const mode=document.getElementById('printBillingMode');
      const customer=document.getElementById('nexoaCustomerId');
      const event=document.getElementById('nexoaEventId');
      const hint=document.getElementById('nexoaBillingHint');
      if(!enabled||!mode||!customer||!event)return false;

      const refresh=()=>{
        const needsNexoa=enabled.checked&&['organizer_flat','fts_free'].includes(mode.value);
        if(hint&&needsNexoa&&!/Nexoa-Status:/.test(hint.textContent||'')){
          hint.textContent=mode.value==='fts_free'
            ?'Pflicht: Nexoa-Kunde und Nexoa-Event auswählen. Die Gratisleistung wird nach Eventende als Sponsoring/Gratisleistung für die Buchhaltung vorbereitet.'
            :'Pflicht: Nexoa-Kunde und Nexoa-Event auswählen. Der vereinbarte Fixpreis wird nach Eventende für die Nexoa-Rechnung bereitgestellt.';
        }
      };
      mode.addEventListener('change',refresh);
      enabled.addEventListener('change',refresh);
      refresh();

      const original=typeof persistPrintSetting==='function'?persistPrintSetting:null;
      if(original&&!original.__ftsV47Final){
        const wrapped=async function(eventToken){
          const currentMode=mode.value;
          if(enabled.checked&&['organizer_flat','fts_free'].includes(currentMode)&&(!customer.value||!event.value)){
            throw new Error('Bitte Nexoa-Kunde und Nexoa-Event auswählen, damit die Fotoprint-Abrechnung korrekt zugeordnet wird.');
          }
          return await original(eventToken);
        };
        wrapped.__ftsV47Final=true;
        persistPrintSetting=wrapped;
      }
      return true;
    };
    if(!apply()){
      let tries=0;
      const timer=setInterval(()=>{tries++;if(apply()||tries>40)clearInterval(timer)},100);
    }
  }

  if(page==='print.html'){
    const top=document.querySelector('.brand p');
    if(top)top.textContent='Fotoprint-Aufträge sicher prüfen, drucken und dokumentieren.';
    const live=document.querySelector('#liveView .sectionHead p');
    if(live)live.textContent='Druckbereit nach bestätigter Gastzahlung oder wenn Veranstalter/FTS die Prints übernimmt.';
  }
})();
