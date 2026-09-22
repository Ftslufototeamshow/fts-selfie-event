(()=>{
  const page=(location.pathname.split('/').pop()||'index.html').toLowerCase();
  const readyStatuses=new Set(['COMPLETED','COVERED','FREE']);
  const modeText={
    guest_paypal:{de:'Gast zahlt selbst · 2,00 € pro Print',en:'Guest pays · €2.00 per print',fr:'Le visiteur paie · 2,00 € par tirage'},
    organizer_flat:{de:'Vom Veranstalter übernommen',en:'Covered by the organiser',fr:'Pris en charge par l’organisateur'},
    fts_free:{de:'FTS Gratisaktion',en:'FTS complimentary print',fr:'Impression offerte par FTS'}
  };
  const localLang=()=>typeof lang!=='undefined'&&['de','en','fr'].includes(lang)?lang:'de';
  const tMode=m=>modeText[m]?.[localLang()]||modeText[m]?.de||m;

  if(page==='admin.html') initAdmin();
  if(page==='index.html'||page==='') initGuest();
  if(page==='print.html') initStation();

  function initAdmin(){
    const printCheck=document.getElementById('printEnabled');
    if(!printCheck||typeof rpc!=='function'||typeof authCredential!=='function')return;
    const host=printCheck.closest('.full')||printCheck.parentElement;
    if(!host||document.getElementById('printBillingMode'))return;
    const panel=document.createElement('div');
    panel.id='printBillingV47';
    panel.style.cssText='margin-top:14px;padding-top:14px;border-top:1px solid rgba(255,255,255,.08);display:grid;gap:10px';
    panel.innerHTML=`
      <div><label>Wer bezahlt die Fotoprints?</label>
        <select id="printBillingMode">
          <option value="guest_paypal">Gäste zahlen selbst · 2,00 € pro Ausdruck</option>
          <option value="organizer_flat">Veranstalter übernimmt · Fixpreis</option>
          <option value="fts_free">FTS gratis / Sponsoring</option>
        </select>
      </div>
      <div id="flatPriceRow" style="display:none"><label>Fixpreis für den Veranstalter</label>
        <div style="display:grid;grid-template-columns:1fr auto;gap:8px;align-items:center"><input id="printFlatPrice" type="number" min="0.01" step="0.01" inputmode="decimal" placeholder="z. B. 350,00"><b>EUR</b></div>
        <div class="hint">Dieser Betrag gilt für das gesamte Event – unabhängig davon, wie viele Fotos tatsächlich gedruckt werden.</div>
      </div>
      <div id="nexoaLinkRows" style="display:none;padding:12px;border-radius:12px;background:#0a2426;border:1px solid rgba(255,255,255,.08)">
        <b style="display:block;margin-bottom:8px">Nexoa-Verknüpfung</b>
        <div class="grid">
          <div><label>Nexoa-Kunde</label><select id="nexoaCustomerId"><option value="">Kunde auswählen …</option></select></div>
          <div><label>Nexoa-Event</label><select id="nexoaEventId"><option value="">Zuerst Kunde auswählen …</option></select></div>
        </div>
        <div class="hint" id="nexoaBillingHint" style="margin-top:8px">Damit landet MySelfie/Fotoprint beim richtigen Kunden und Event in Nexoa.</div>
      </div>`;
    host.appendChild(panel);

    const mode=document.getElementById('printBillingMode'),flat=document.getElementById('printFlatPrice'),customer=document.getElementById('nexoaCustomerId'),nexEvent=document.getElementById('nexoaEventId');
    let customersLoaded=false;
    const toggle=()=>{
      const m=mode.value,on=printCheck.checked;
      panel.style.opacity=on?'1':'.55';
      mode.disabled=!on;
      document.getElementById('flatPriceRow').style.display=on&&m==='organizer_flat'?'block':'none';
      document.getElementById('nexoaLinkRows').style.display=on&&m!=='guest_paypal'?'block':'none';
      if(on&&m!=='guest_paypal'&&!customersLoaded)void loadCustomers();
    };
    async function loadCustomers(selected=''){
      try{
        const rows=await rpc('fts_admin_list_nexoa_customers_v47',{p_admin_code:authCredential()})||[];
        customer.innerHTML='<option value="">Kunde auswählen …</option>'+rows.map(x=>`<option value="${String(x.customer_id)}">${escapeAdmin(x.display_name)}${x.customer_number?' · '+escapeAdmin(x.customer_number):''}</option>`).join('');
        customersLoaded=true;if(selected)customer.value=String(selected);
      }catch(e){console.warn('Nexoa Kunden',e);document.getElementById('nexoaBillingHint').textContent='Nexoa-Kunden konnten nicht geladen werden.'}
    }
    async function loadEvents(customerId,selected=''){
      if(!customerId){nexEvent.innerHTML='<option value="">Zuerst Kunde auswählen …</option>';return}
      nexEvent.innerHTML='<option value="">Events werden geladen …</option>';
      try{
        const rows=await rpc('fts_admin_list_nexoa_events_v47',{p_admin_code:authCredential(),p_customer_id:Number(customerId)})||[];
        nexEvent.innerHTML='<option value="">Event auswählen …</option>'+rows.map(x=>`<option value="${x.event_id}">${escapeAdmin(x.event_title)}${x.event_date?' · '+new Date(x.event_date+'T12:00:00').toLocaleDateString('de-DE'):''}</option>`).join('');
        if(selected)nexEvent.value=String(selected);
      }catch(e){console.warn('Nexoa Events',e);nexEvent.innerHTML='<option value="">Events konnten nicht geladen werden</option>'}
    }
    function escapeAdmin(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
    mode.addEventListener('change',toggle);printCheck.addEventListener('change',toggle);customer.addEventListener('change',()=>void loadEvents(customer.value));

    const oldPersist=typeof persistPrintSetting==='function'?persistPrintSetting:null;
    persistPrintSetting=async function(eventToken){
      const start=document.getElementById('printStartsAt')?.value||'',end=document.getElementById('printEndsAt')?.value||'',m=mode.value;
      if(start&&end&&end<=start)throw new Error('Druck-Ende muss nach Druck-Start liegen.');
      const price=Math.round(Number(String(flat.value||'0').replace(',','.'))*100);
      if(printCheck.checked&&m==='organizer_flat'){
        if(!Number.isFinite(price)||price<=0)throw new Error('Bitte den Fixpreis des Veranstalters eintragen.');
        if(!customer.value||!nexEvent.value)throw new Error('Bitte den Nexoa-Kunden und das passende Nexoa-Event auswählen.');
      }
      if(printCheck.checked&&m==='fts_free'&&customer.value&&!nexEvent.value)throw new Error('Bitte zum ausgewählten Nexoa-Kunden auch das Nexoa-Event auswählen.');
      await rpc('fts_admin_set_print_settings_v47',{
        p_admin_code:authCredential(),p_event_token:eventToken,p_enabled:printCheck.checked===true,p_billing_mode:m,
        p_organizer_flat_price_cents:m==='organizer_flat'?price:0,p_nexoa_customer_id:customer.value?Number(customer.value):null,
        p_nexoa_event_id:nexEvent.value||null,p_print_starts_at:typeof printDateIso==='function'?printDateIso(start):null,p_print_ends_at:typeof printDateIso==='function'?printDateIso(end):null
      });
    };

    async function loadExisting(){
      if(typeof DUP_TOKEN!=='undefined'&&DUP_TOKEN){mode.value='guest_paypal';flat.value='';toggle();return}
      const token=typeof EDIT_TOKEN!=='undefined'?EDIT_TOKEN:null;if(!token){toggle();return}
      try{
        const raw=await rpc('fts_admin_get_print_settings_v47',{p_admin_code:authCredential(),p_event_token:token});
        const s=Array.isArray(raw)?raw[0]:raw;if(!s)return;
        printCheck.checked=!!s.enabled;mode.value=s.billing_mode||'guest_paypal';flat.value=s.organizer_flat_price_cents?String((Number(s.organizer_flat_price_cents)/100).toFixed(2)):'';
        if(s.nexoa_customer_id){await loadCustomers(String(s.nexoa_customer_id));await loadEvents(String(s.nexoa_customer_id),s.nexoa_event_id||'')}
        const hint=document.getElementById('nexoaBillingHint');if(hint&&s.nexoa_billing_status)hint.textContent='Nexoa-Status: '+s.nexoa_billing_status;
      }catch(e){console.warn('Print-Abrechnung laden',e)}finally{toggle()}
    }
    void loadExisting();
  }

  function initGuest(){
    if(typeof bindPrintControls!=='function'||typeof paypalPrintApi!=='function')return;
    const checkout=document.getElementById('selfiePrintCheckout');if(!checkout)return;
    let coveredBtn=document.getElementById('coveredPrintBtn');
    if(!coveredBtn){coveredBtn=document.createElement('button');coveredBtn.type='button';coveredBtn.id='coveredPrintBtn';coveredBtn.className='ghostBtn';coveredBtn.style.cssText='display:none;width:100%;margin-top:10px;padding:13px;font-weight:950;background:var(--accent);color:#102020';checkout.appendChild(coveredBtn)}
    const oldBind=bindPrintControls,oldSummary=updatePrintSummary;
    updatePrintSummary=function(){
      const mode=printConfig?.billing_mode||'guest_paypal';if(mode==='guest_paypal')return oldSummary();
      const items=selectedPrintItems(),qty=items.reduce((n,x)=>n+Number(x.quantity||0),0),count=document.getElementById('selfiePrintCount'),sum=document.getElementById('selfiePrintTotal'),host=document.getElementById('paypalPrintHost');
      if(count)count.textContent=qty+' '+ptr('prints');if(sum)sum.textContent=mode==='organizer_flat'?(localLang()==='fr'?'Pris en charge':localLang()==='en'?'Covered':'Übernommen'):(localLang()==='fr'?'Offert':localLang()==='en'?'Complimentary':'Gratis');
      if(host)host.classList.remove('show');coveredBtn.style.display=qty>0?'block':'none';
    };
    bindPrintControls=function(rows){
      const mode=printConfig?.billing_mode||'guest_paypal';if(mode==='guest_paypal'){coveredBtn.style.display='none';return oldBind(rows)}
      const box=document.getElementById('selfiePrintCheckout');if(!box)return;const canShow=!!printConfig?.enabled&&rows.some(r=>r.photo_id);box.classList.toggle('show',canShow);if(!canShow)return;
      document.getElementById('selfiePrintTitle').textContent=ptr('title');
      const badge=document.getElementById('selfiePrintSandbox');if(badge)badge.textContent=tMode(mode);
      const intro=document.getElementById('selfiePrintIntro');if(intro)intro.textContent=mode==='organizer_flat'?(localLang()==='fr'?'Choisissez vos photos. Le coût est pris en charge par l’organisateur. Aucun paiement PayPal n’est nécessaire.':localLang()==='en'?'Choose your photos. The organiser covers the cost, so no PayPal payment is required.':'Wähle deine Fotos und die Anzahl. Der Veranstalter übernimmt die Kosten – du musst hier nichts bezahlen.'):(localLang()==='fr'?'Choisissez vos photos. Cette impression est offerte par FTS.':localLang()==='en'?'Choose your photos. This print is complimentary from FTS.':'Wähle deine Fotos und die Anzahl. Dieser Fotoprint ist eine Gratisaktion von FTS.');
      const hint=document.getElementById('selfiePrintPriceHint');if(hint)hint.textContent=localLang()==='fr'?'Aucun paiement sur le QR code':localLang()==='en'?'No payment at the QR code':'Keine Zahlung am QR-Code';
      document.querySelectorAll('.mySelfiePrintChoice label span').forEach(x=>{x.textContent=(localLang()==='fr'?'Imprimer cette photo':localLang()==='en'?'Print this photo':'Dieses Foto drucken')});
      printSelection.clear();document.querySelectorAll('[data-print-select]').forEach(check=>{const i=Number(check.dataset.printSelect),row=rows[i],qty=document.querySelector('[data-print-qty="'+i+'"]');if(!row?.photo_id)return;printSelection.set(i,{photo_id:row.photo_id,selected:false,quantity:1});check.onchange=()=>{const x=printSelection.get(i);x.selected=check.checked;if(qty)qty.disabled=!check.checked;updatePrintSummary()};if(qty)qty.onchange=()=>{const x=printSelection.get(i);x.quantity=Math.max(1,Math.min(20,Number(qty.value)||1));qty.value=String(x.quantity);updatePrintSummary()}});
      document.getElementById('paypalPrintHost')?.classList.remove('show');printStatus('');showPrintReceipt?.(null);updatePrintSummary();
    };
    coveredBtn.onclick=async()=>{
      const items=selectedPrintItems();if(!items.length){printStatus(ptr('choose'),'warn');return}coveredBtn.disabled=true;const old=coveredBtn.textContent;coveredBtn.textContent='…';
      try{const result=await paypalPrintApi('create-covered-order',{items});currentPrintOrder={print_order_id:result.order_id||result.print_order_id,paypal_order_id:null};printStatus(localLang()==='fr'?'Commande envoyée à l’impression ✓':localLang()==='en'?'Print order sent ✓':'Druckauftrag an die Print Station gesendet ✓','ok');printSelection.clear();document.querySelectorAll('[data-print-select]').forEach(x=>x.checked=false);document.querySelectorAll('[data-print-qty]').forEach(x=>{x.disabled=true;x.value='1'});updatePrintSummary()}catch(e){console.error(e);printStatus(String(e?.message||'Druckauftrag konnte nicht gesendet werden.'),'err')}finally{coveredBtn.disabled=false;coveredBtn.textContent=old}
    };
    const refreshLabel=()=>{const mode=printConfig?.billing_mode||'guest_paypal';coveredBtn.textContent=mode==='organizer_flat'?(localLang()==='fr'?'Envoyer à l’impression':localLang()==='en'?'Send to print':'Zum Drucken senden'):(localLang()==='fr'?'Impression gratuite':localLang()==='en'?'Request complimentary print':'Gratisdruck anfordern')};
    const observer=new MutationObserver(refreshLabel);observer.observe(checkout,{subtree:true,childList:true});refreshLabel();
  }

  function initStation(){
    if(typeof loadCore!=='function'||typeof rpc!=='function')return;
    const canPrint=o=>readyStatuses.has(String(o?.payment_status||''))&&o?.print_status==='READY';
    paymentLabel=function(s){s=String(s||'').toUpperCase();if(s==='COMPLETED')return['PayPal bezahlt','ok'];if(s==='COVERED')return['Veranstalter übernimmt','ok'];if(s==='FREE')return['FTS gratis','ok'];if(['CREATED','APPROVED','PENDING'].includes(s))return['Reserviert · Zahlung läuft','warn'];if(s==='REFUNDED')return['Erstattet','err'];if(s==='REVERSED')return['Rückgängig','err'];if(s==='CANCELLED')return['Abgebrochen','err'];return[s||'Unbekannt','err']};
    statusClass=function(o){if(canPrint(o))return'ready';if(['CREATED','APPROVED','PENDING'].includes(o.payment_status))return'wait';if(['CANCELLED','DENIED','FAILED','ERROR','REFUNDED','REVERSED'].includes(o.payment_status))return'cancelled';return''};
    computeMetrics=function(rows){const today=new Date().toLocaleDateString('en-CA');let ready=0,wait=0,printed=0,rev=0;for(const o of rows){if(o.event_closed)continue;if(canPrint(o))ready++;if(['CREATED','APPROVED','PENDING'].includes(o.payment_status))wait++;if(o.print_status==='PRINTED')printed++;if(o.payment_status==='COMPLETED'&&o.paid_at&&new Date(o.paid_at).toLocaleDateString('en-CA')===today)rev+=Number(o.total_cents||0)}document.getElementById('readyN').textContent=ready;document.getElementById('waitN').textContent=wait;document.getElementById('printedN').textContent=printed;document.getElementById('todayRevenue').textContent=euro(rev)};
    orderHtml=function(o){const p=paymentLabel(o.payment_status),pr=printLabel(o.print_status),items=Array.isArray(o.items)?o.items:[],ready=canPrint(o),amount=o.billing_mode==='organizer_flat'?'Veranstalter':o.billing_mode==='fts_free'?'FTS gratis':euro(o.total_cents),amountSub=o.billing_mode==='organizer_flat'?'Fixpreis auf Event-Ebene':o.billing_mode==='fts_free'?'keine Gastzahlung':Number(o.quantity_total||0)+' Ausdruck'+(Number(o.quantity_total||0)===1?'':'e');return '<article class="order '+statusClass(o)+'" data-order-card="'+esc(o.order_id)+'"><div class="orderTop"><div><div class="orderTitle">'+esc(o.event_title)+'</div><div class="orderMeta">'+esc(o.organizer_name)+' · '+dt(o.created_at)+'<br>Auftrag '+esc(String(o.order_id).slice(0,8).toUpperCase())+(o.receipt_number?' · '+esc(o.receipt_number):'')+'</div></div><div class="amount"><strong>'+esc(amount)+'</strong><small>'+esc(amountSub)+'</small></div></div><div class="badges"><span class="badge '+p[1]+'">'+esc(p[0])+'</span><span class="badge '+pr[1]+'">'+esc(pr[0])+'</span>'+(o.event_closed?'<span class="badge">Event abgeschlossen</span>':'')+'</div><div class="photos">'+(items.length?items.map((x,i)=>photoItemHtml(x,i,o)).join(''):'<div class="photoMissing" style="width:126px">Keine Fotodatei mehr vorhanden</div>')+'</div><div class="orderActions">'+(ready?'<button class="printNow" data-print-order="'+esc(o.order_id)+'">Jetzt drucken</button><button class="doneBtn" data-mark-printed="'+esc(o.order_id)+'">Gedruckt bestätigen</button>':'')+(o.receipt_number?'<button class="receiptBtn" data-order-receipt="'+esc(o.order_id)+'">Beleg anzeigen</button>':'')+'</div></article>'};
    renderOrders=function(){const ev=document.getElementById('eventFilter').value;let live=orders.filter(o=>!o.event_closed&&(!ev||o.event_token===ev));if(onlyReady)live=live.filter(canPrint);document.getElementById('liveOrders').innerHTML=live.length?live.map(orderHtml).join(''):'<div class="empty">Aktuell keine passenden Druckaufträge.</div>';bindOrderActions(document.getElementById('liveOrders'));const aev=document.getElementById('archiveEventFilter').value,archived=orders.filter(o=>o.event_closed&&(!aev||o.event_token===aev));document.getElementById('archiveOrders').innerHTML=archived.length?archived.map(orderHtml).join(''):'<div class="empty">Noch keine archivierten Druckaufträge.</div>';bindOrderActions(document.getElementById('archiveOrders'));computeMetrics(orders)};
    const oldPrint=printOrder;printOrder=async function(orderId,onlyIndex=null){const o=orders.find(x=>String(x.order_id)===String(orderId));if(!o||!canPrint(o))return toast('Dieser Auftrag ist nicht druckbereit.');return oldPrint(orderId,onlyIndex)};
    loadCore=async function(showStatus=true){if(showStatus)document.getElementById('statusText').textContent='Aktualisiere …';try{const [e,o,y]=await Promise.all([rpc('fts_admin_print_station_events_v47',{p_admin_code:credential()}),rpc('fts_admin_print_station_orders_v47',{p_admin_code:credential(),p_event_token:null}),rpc('fts_admin_print_year_summary_v46',{p_admin_code:credential()})]);events=e||[];orders=o||[];years=y||[];eventOptions(document.getElementById('eventFilter'),false);eventOptions(document.getElementById('archiveEventFilter'),true);if(launchEvent)document.getElementById('eventFilter').value=launchEvent;renderOrders();renderYears();document.getElementById('statusText').textContent='Aktuell · '+new Date().toLocaleTimeString('de-DE',{hour:'2-digit',minute:'2-digit'});if(!timer)timer=setInterval(()=>{if(activeTab==='live')loadCore(false)},5000)}catch(e){console.error(e);document.getElementById('statusText').textContent='Verbindung wird erneut versucht';if(isCredentialError(e)){localStorage.removeItem(DEVICE_KEY);setLoggedIn(false)}}};
    const intro=document.querySelector('#liveView .sectionHead p');if(intro)intro.textContent='Druckbereit nach bestätigter Gastzahlung oder wenn Veranstalter/FTS die Prints übernimmt.';
    document.getElementById('onlyReadyBtn').onclick=()=>{onlyReady=!onlyReady;document.getElementById('onlyReadyBtn').textContent=onlyReady?'Alle Aufträge anzeigen':'Nur druckbereit';renderOrders()};
    if(credential())void loadCore(false);
  }
})();