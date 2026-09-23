/* FTS Print Station pickup workflow v57 */
(()=>{
  'use strict';
  if((location.pathname.split('/').pop()||'').toLowerCase()!=='print.html')return;
  const baseReceiptPaperHtml=receiptPaperHtml;
  function addCss(){
    if(document.getElementById('ftsPickupStationCss57'))return;
    const s=document.createElement('style');s.id='ftsPickupStationCss57';s.textContent=`
.order{overflow:hidden}.orderToggle,.orderToggleLegacy{width:100%;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:12px;text-align:left;padding:14px;background:transparent!important;color:inherit!important;border:0!important;border-radius:0!important;cursor:pointer}.orderToggleLegacy{padding:14px 14px 10px}.orderToggle .amount,.orderToggleLegacy .amount{align-self:center}.orderToggle .arrow,.orderToggleLegacy .arrow{display:inline-grid;place-items:center;width:27px;height:27px;margin-left:7px;border-radius:999px;background:#172829;color:var(--gold);font-size:1rem;vertical-align:middle;transition:transform .18s ease}.order.collapsed .orderBody{display:none}.order:not(.collapsed) .orderToggle .arrow,.order:not(.collapsed) .orderToggleLegacy .arrow{transform:rotate(180deg)}.orderBody{border-top:1px solid #202a2b}.pickupStrip{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 14px;background:#0b1718}.pickupStrip span{font-size:.68rem;color:var(--muted);font-weight:800}.pickupStrip strong{font-size:1.3rem;letter-spacing:.12em;color:var(--gold)}.testStrip{padding:8px 14px;background:#5a3b17;color:#ffe1a0;font-weight:950;font-size:.72rem;letter-spacing:.04em}.photos{padding-top:12px}.photoItem{position:relative}.photoItem .viewPhoto{display:block;padding:0;width:100%;background:transparent;border:0}.photoItem .singlePrint{width:100%;margin-top:6px;padding:7px 6px;border-radius:8px;background:#182829;color:#e8efed;border:1px solid #ffffff12;font-size:.66rem}.pickupBtn{background:#265a44!important;color:#d7ffe8!important}.archiveBtn{background:#293335!important;color:#e5ecea!important}.pickupWait{background:#46351b!important;color:#ffe19b!important}.receiptTestBanner{padding:10px 12px;margin:0 0 18px;border:2px solid #a76c16;background:#fff2cf;color:#714300;font-weight:950;text-align:center;letter-spacing:.05em}.receiptPickup{margin:14px 0;padding:12px;border:1px solid #d6c9ac;background:#fffaf0;border-radius:10px}.receiptPickup b{display:block;font-size:1.7rem;letter-spacing:.14em;margin-top:3px}.photoViewer57{position:fixed;inset:0;z-index:9999;background:#000d;display:none;place-items:center;padding:14px}.photoViewer57.show{display:grid}.photoViewer57 .box{position:relative;max-width:min(960px,100%);max-height:96vh}.photoViewer57 img{display:block;max-width:100%;max-height:92vh;object-fit:contain;border-radius:12px;background:#050909}.photoViewer57 button{position:absolute;right:8px;top:8px;border:0;border-radius:999px;width:38px;height:38px;background:#111d;color:#fff;font-size:1.1rem}.orderActions{grid-template-columns:repeat(2,minmax(0,1fr))}@media(max-width:720px){.orderActions{grid-template-columns:1fr}.orderToggle{padding:12px}.pickupStrip{padding:9px 12px}}
`;document.head.appendChild(s);
  }
  function viewer(){
    let v=document.getElementById('photoViewer57');if(v)return v;
    v=document.createElement('div');v.id='photoViewer57';v.className='photoViewer57';v.innerHTML='<div class="box"><button type="button">×</button><img alt="Druckfoto groß"></div>';
    document.body.appendChild(v);v.onclick=e=>{if(e.target===v||e.target.tagName==='BUTTON')v.classList.remove('show')};return v;
  }
  function showPhoto(url){const v=viewer();v.querySelector('img').src=url;v.classList.add('show')}
  function canPrint(o){return ['COMPLETED','COVERED','FREE'].includes(String(o?.payment_status||''))&&o?.print_status==='READY'}
  function pickupLabel(o){
    if(o.pickup_status==='READY_FOR_PICKUP')return['Wartet auf Abholung','warn'];
    if(o.pickup_status==='PICKED_UP')return['Abgeholt','ok'];
    if(o.pickup_status==='ARCHIVED')return['Archiviert',''];
    return[o.print_status==='PRINTED'?'Gedruckt':'In Vorbereitung',''];
  }
  function photoHtml(item,i,o){
    const path=item.designed_path||'',url=path?photoUrl(path):'';
    return '<div class="photoItem">'+(path?'<button type="button" class="viewPhoto" data-view-photo="'+esc(url)+'"><img src="'+esc(url)+'" alt="Druckfoto" onerror="this.outerHTML=\'<div class=&quot;photoMissing&quot;>Foto nicht mehr im Speicher</div>\'"></button>':'<div class="photoMissing">Foto nicht mehr im Speicher</div>')+'<b>'+Number(item.quantity||0)+' × 10×15</b>'+(canPrint(o)&&path?'<button type="button" class="singlePrint" data-print-item="'+esc(o.order_id)+'" data-item-index="'+i+'">Dieses Foto drucken</button>':'')+'</div>';
  }
  function card(o,index){
    const pay=String(o.payment_status||'').toUpperCase(),p=pay==='COVERED'?['Veranstalter übernimmt','ok']:pay==='FREE'?['FTS gratis','ok']:paymentLabel(pay),pr=printLabel(o.print_status),pk=pickupLabel(o),items=Array.isArray(o.items)?o.items:[],ready=canPrint(o);
    const amount=o.billing_mode==='organizer_flat'?'Veranstalter':o.billing_mode==='fts_free'?'FTS gratis':euro(o.total_cents);
    const amountSub=o.is_test?'TEST · kein echter Umsatz':Number(o.quantity_total||0)+' Ausdruck'+(Number(o.quantity_total||0)===1?'':'e');
    let actions='';
    if(ready)actions+='<button class="printNow" data-print-order="'+esc(o.order_id)+'">Jetzt drucken</button><button class="doneBtn" data-mark-printed="'+esc(o.order_id)+'">Gedruckt bestätigen</button>';
    if(o.print_status==='PRINTED'&&o.pickup_status==='READY_FOR_PICKUP')actions+='<button class="pickupBtn" data-picked-up="'+esc(o.order_id)+'">Abgeholt bestätigen</button><button class="pickupWait" type="button" disabled>Wartet auf Abholung</button>';
    if(o.pickup_status==='PICKED_UP')actions+='<button class="archiveBtn" data-archive-order="'+esc(o.order_id)+'">Auftrag archivieren</button>';
    if(o.receipt_number)actions+='<button class="receiptBtn" data-order-receipt="'+esc(o.order_id)+'">Beleg anzeigen</button>';
    return '<article class="order '+statusClass(o)+(index===0?'':' collapsed')+'" data-order-card="'+esc(o.order_id)+'">'+
      (o.is_test?'<div class="testStrip">TEST · PAYPAL SANDBOX · KEIN ECHTER GELDFLUSS</div>':'')+
      '<button type="button" class="orderToggle" data-toggle-order="'+esc(o.order_id)+'"><span><span class="orderTitle">'+esc(o.event_title)+'</span><span class="orderMeta">'+esc(o.organizer_name)+' · '+dt(o.created_at)+'<br>Auftrag '+esc(String(o.order_id).slice(0,8).toUpperCase())+(o.receipt_number?' · '+esc(o.receipt_number):'')+'</span></span><span class="amount"><strong>'+esc(amount)+'</strong><small>'+esc(amountSub)+'</small><i class="arrow">⌃</i></span></button>'+
      '<div class="orderBody"><div class="badges"><span class="badge '+p[1]+'">'+esc(p[0])+'</span><span class="badge '+pr[1]+'">'+esc(pr[0])+'</span><span class="badge '+pk[1]+'">'+esc(pk[0])+'</span>'+(o.event_closed?'<span class="badge">Event abgeschlossen</span>':'')+'</div>'+
      '<div class="pickupStrip"><span>ABHOLCODE</span><strong>'+esc(o.pickup_code||'------')+'</strong></div>'+
      '<div class="photos">'+(items.length?items.map((x,i)=>photoHtml(x,i,o)).join(''):'<div class="photoMissing" style="width:126px">Keine Fotodatei mehr vorhanden</div>')+'</div>'+
      '<div class="orderActions">'+actions+'</div></div></article>';
  }
  async function markPicked(id,btn){
    if(!confirm('Abholcode geprüft und Foto wirklich an den Kunden übergeben?'))return;
    btn.disabled=true;try{const ok=await rpc('fts_admin_mark_picked_up_v57',{p_admin_code:credential(),p_order_id:id});if(!ok)throw new Error('Auftrag ist nicht abholbereit.');toast('Als abgeholt markiert.');await loadCore(false)}catch(e){alert(e.message)}finally{btn.disabled=false}
  }
  async function archivePickup(id,btn){
    if(!confirm('Diesen bereits abgeholten Auftrag ins Archiv verschieben?'))return;
    btn.disabled=true;try{const ok=await rpc('fts_admin_archive_print_order_v57',{p_admin_code:credential(),p_order_id:id});if(!ok)throw new Error('Nur abgeholte Aufträge können archiviert werden.');toast('Auftrag archiviert.');await loadCore(false)}catch(e){alert(e.message)}finally{btn.disabled=false}
  }
  function bind57(root){
    root.querySelectorAll('[data-toggle-order]').forEach(b=>b.onclick=()=>b.closest('.order')?.classList.toggle('collapsed'));
    root.querySelectorAll('[data-view-photo]').forEach(b=>b.onclick=e=>{e.stopPropagation();showPhoto(b.dataset.viewPhoto)});
    root.querySelectorAll('[data-print-order]').forEach(b=>b.onclick=()=>printOrder(b.dataset.printOrder));
    root.querySelectorAll('[data-print-item]').forEach(b=>b.onclick=()=>printOrder(b.dataset.printItem,Number(b.dataset.itemIndex)));
    root.querySelectorAll('[data-mark-printed]').forEach(b=>b.onclick=()=>markPrinted(b.dataset.markPrinted,b));
    root.querySelectorAll('[data-picked-up]').forEach(b=>b.onclick=()=>markPicked(b.dataset.pickedUp,b));
    root.querySelectorAll('[data-archive-order]').forEach(b=>b.onclick=()=>archivePickup(b.dataset.archiveOrder,b));
    root.querySelectorAll('[data-order-receipt]').forEach(b=>b.onclick=()=>openReceiptByOrder(b.dataset.orderReceipt));
  }
  function sortNew(rows){return [...rows].sort((a,b)=>String(b.created_at||'').localeCompare(String(a.created_at||'')))}
  function readStationState58(){
    try{
      const s=JSON.parse(localStorage.getItem('fts_print_station_state_v58')||'null');
      if(!s||Date.now()-Number(s.savedAt||0)>7*24*60*60*1000)return null;
      return s;
    }catch{return null}
  }
  function saveStationState58(openOrder){
    try{
      const current=openOrder||document.querySelector('.order:not(.collapsed)[data-order-card]')?.dataset.orderCard||'';
      localStorage.setItem('fts_print_station_state_v58',JSON.stringify({
        tab:activeTab||'live',
        event:$('#eventFilter')?.value||'',
        archiveEvent:$('#archiveEventFilter')?.value||'',
        onlyReady:!!onlyReady,
        openOrder:current,
        scrollY:Math.max(0,Math.round(window.scrollY||0)),
        savedAt:Date.now()
      }));
      if(matchMedia('(display-mode: standalone)').matches||navigator.standalone===true)localStorage.setItem('fts_admin_surface_v1','print');
    }catch{}
  }
  let currentStock70=null,stockLoadSeq70=0;
  function n70(v){const n=Number(v||0);return Number.isFinite(n)?Math.trunc(n):0}
  function date70(v){if(!v)return'—';const d=new Date(String(v)+'T12:00:00');return Number.isNaN(d.getTime())?String(v):d.toLocaleDateString('de-DE',{weekday:'short',day:'2-digit',month:'2-digit'})}
  function resetStock70(message='Event auswählen, um Bestand und Tagesverbrauch zu sehen.'){
    currentStock70=null;
    $('#stockInfo').textContent=message;$('#stockAvailable').textContent='—';$('#stockBig').classList.remove('blocked');
    $('#stockPrinted').textContent='0';$('#stockWaiting').textContent='0';$('#stockCamera').textContent='0';$('#stockTest').textContent='0';$('#stockMisprint').textContent='0';$('#stockReprint').textContent='0';
    $('#stockUnknown').classList.add('hidden');$('#stockDays').innerHTML='<div class="stockEmpty">'+esc(message)+'</div>';
    $('#stockAdjustBtn').disabled=true;
  }
  function renderStock70(s){
    currentStock70=s||null;
    if(!s||s.managed!==true){resetStock70('Materialbestand ist für dieses Event noch nicht eingerichtet. Mit „Bestand hinzufügen“ kann die Print Station ihn starten.');$('#stockAdjustBtn').disabled=false;return}
    const available=n70(s.safe_available);
    $('#stockAvailable').textContent=String(available);$('#stockBig').classList.toggle('blocked',available<=0);
    $('#stockPrinted').textContent=String(n70(s.selfie_printed));$('#stockWaiting').textContent=String(n70(s.selfie_waiting)+n70(s.active_reservations));
    $('#stockCamera').textContent=String(n70(s.camera_prints));$('#stockTest').textContent=String(n70(s.test_prints));$('#stockMisprint').textContent=String(n70(s.misprints));$('#stockReprint').textContent=String(n70(s.reprints));
    $('#stockInfo').textContent='Start sicher '+n70(s.safe_start_qty)+' · hinzugefügt '+n70(s.added_stock)+' · Korrektur '+(n70(s.correction_delta)>=0?'+':'')+n70(s.correction_delta)+' · verbraucht gesamt '+n70(s.total_consumed)+(available<=0?' · VERKAUF GESPERRT':'');
    $('#stockUnknown').classList.toggle('hidden',s.open_stock_unknown!==true);
    if(s.open_stock_unknown===true){
      const est=s.open_stock_estimate==null?'':' · Schätzung '+n70(s.open_stock_estimate);
      $('#stockUnknown').textContent='Geöffneter Bestand ist unbekannt'+est+' und wird nicht für neue Zahlungen mitgerechnet.';
    }
    const days=Array.isArray(s.days)?s.days:[];
    $('#stockDays').innerHTML=days.length?days.map(d=>{
      return '<div class="stockDay"><strong>'+esc(date70(d.event_day))+'</strong><span>Selfie <b>'+n70(d.selfie_printed)+'</b></span><span>wartend <b>'+n70(d.selfie_waiting)+'</b></span><span>Kamera <b>'+n70(d.camera_prints)+'</b></span><span>Test <b>'+n70(d.test_prints)+'</b> · Fehler <b>'+n70(d.misprints)+'</b> · Nachdruck <b>'+n70(d.reprints)+'</b></span><span>Verbrauch <b>'+n70(d.consumed_total)+'</b></span></div>';
    }).join(''):'<div class="stockEmpty">Noch keine Tagesbewegungen.</div>';
    if(!$('#stockDay').value&&days[0]?.event_day)$('#stockDay').value=String(days[0].event_day);
    $('#stockAdjustBtn').disabled=false;
  }
  async function loadStock70(silent=true){
    const token=$('#eventFilter')?.value||'';
    const seq=++stockLoadSeq70;
    if(!token){resetStock70();return}
    if(!silent)$('#stockInfo').textContent='Materialbestand wird geladen …';
    try{
      const s=await rpc('fts_admin_get_print_stock_v70',{p_admin_code:credential(),p_event_token:token});
      if(seq!==stockLoadSeq70)return;
      renderStock70(s);
    }catch(e){
      if(seq!==stockLoadSeq70)return;
      console.warn('Materialbestand',e);resetStock70('Materialbestand konnte nicht geladen werden.');
    }
  }
  async function bookStock70(){
    const token=$('#eventFilter')?.value||'';if(!token)return alert('Bitte zuerst ein Event auswählen.');
    const kind=$('#stockKind').value,qty=Math.trunc(Number($('#stockQty').value||0)),day=$('#stockDay').value||null,note=$('#stockNoteAdjust').value.trim()||null;
    if(!qty)return alert('Bitte eine Menge eintragen.');
    if(kind!=='CORRECTION'&&qty<0)return alert('Bei dieser Buchung bitte eine positive Menge eingeben.');
    const btn=$('#stockAdjustBtn');btn.disabled=true;
    try{
      const s=await rpc('fts_admin_adjust_print_stock_v70',{p_admin_code:credential(),p_event_token:token,p_event_day:day,p_kind:kind,p_quantity:qty,p_note:note});
      $('#stockNoteAdjust').value='';$('#stockQty').value='1';toast(kind==='ADD_STOCK'?'Bestand hinzugefügt.':'Materialverbrauch gebucht.');
      await loadStock70(false);
    }catch(e){alert('Bestand konnte nicht gebucht werden: '+String(e?.message||e))}
    finally{btn.disabled=false}
  }
  renderOrders=function(){
    const evf=$('#eventFilter').value;
    let live=sortNew(orders.filter(o=>o.pickup_status!=='ARCHIVED'&&(!evf||o.event_token===evf)));
    if(onlyReady)live=live.filter(canPrint);
    $('#liveOrders').innerHTML=live.length?live.map(card).join(''):'<div class="empty">Aktuell keine passenden Druckaufträge.</div>';bind57($('#liveOrders'));
    const aev=$('#archiveEventFilter').value,arch=sortNew(orders.filter(o=>o.pickup_status==='ARCHIVED'&&(!aev||o.event_token===aev)));
    $('#archiveOrders').innerHTML=arch.length?arch.map(card).join(''):'<div class="empty">Noch keine archivierten Druckaufträge.</div>';bind57($('#archiveOrders'));
    computeMetrics(orders.filter(o=>!o.is_test));
    if(launchOrder){const el=document.querySelector('[data-order-card="'+CSS.escape(launchOrder)+'"]');if(el){el.classList.remove('collapsed');setTimeout(()=>el.scrollIntoView({behavior:'smooth',block:'center'}),120)}}
  };
  loadCore=async function(showStatus=true){
    if(showStatus)$('#statusText').textContent='Aktualisiere …';
    try{
      const [e,o,y]=await Promise.all([
        rpc('fts_admin_print_station_events_v47',{p_admin_code:credential()}),
        rpc('fts_admin_print_station_orders_v57',{p_admin_code:credential(),p_event_token:null}),
        rpc('fts_admin_print_year_summary_v57',{p_admin_code:credential()})
      ]);
      events=e||[];orders=o||[];years=y||[];
      eventOptions($('#eventFilter'),false);eventOptions($('#archiveEventFilter'),true);
      const savedState=readStationState58();
      if(launchEvent)$('#eventFilter').value=launchEvent;
      else if(savedState?.event&&[...$('#eventFilter').options].some(x=>x.value===savedState.event))$('#eventFilter').value=savedState.event;
      if(savedState?.archiveEvent&&[...$('#archiveEventFilter').options].some(x=>x.value===savedState.archiveEvent))$('#archiveEventFilter').value=savedState.archiveEvent;
      if(savedState)onlyReady=!!savedState.onlyReady;
      $('#onlyReadyBtn').textContent=onlyReady?'Alle Aufträge anzeigen':'Nur druckbereit';
      if(savedState?.tab&&['live','archive','revenue'].includes(savedState.tab))setTab(savedState.tab);
      renderOrders();renderYears();await loadStock70(true);$('#statusText').textContent='Aktuell · '+new Date().toLocaleTimeString('de-DE',{hour:'2-digit',minute:'2-digit'});
      const targetOrder=launchOrder||savedState?.openOrder||'';
      if(targetOrder){
        const el=document.querySelector('[data-order-card="'+CSS.escape(String(targetOrder))+'"]');
        if(el){el.classList.remove('collapsed');el.querySelector('.orderToggle,.orderToggleLegacy')?.setAttribute('aria-expanded','true')}
      }
      if(savedState&&Number.isFinite(Number(savedState.scrollY)))setTimeout(()=>window.scrollTo({top:Number(savedState.scrollY),behavior:'auto'}),80);
      if(!timer)timer=setInterval(()=>{if(activeTab==='live')loadCore(false)},5000);
    }catch(e){console.error(e);$('#statusText').textContent='Verbindung wird erneut versucht';if(isCredentialError(e)){localStorage.removeItem(DEVICE_KEY);setLoggedIn(false)}}
  };
  loadReceipts=async function(year){
    selectedYear=year;$('#receiptList').innerHTML='<div class="empty">Belege werden geladen …</div>';
    try{
      receipts=await rpc('fts_admin_print_receipts_v57',{p_admin_code:credential(),p_year:year,p_event_token:null})||[];
      $('#receiptList').innerHTML=receipts.length?receipts.map(r=>'<button class="receiptRow" data-receipt="'+r.receipt_id+'"><span><b>'+esc(r.receipt_number)+' · '+esc(r.event_title)+(r.is_test?' · TEST':'')+'</b><small>'+dt(r.paid_at)+' · '+Number(r.quantity_total)+' Print'+(Number(r.quantity_total)===1?'':'s')+' · Abholcode '+esc(r.pickup_code||'—')+'</small></span><span class="receiptAmount"><b>'+(r.is_test?'TEST':euro(r.net_cents))+'</b><small>'+esc(r.payment_status)+'</small></span></button>').join(''):'<div class="empty">Keine Belege in diesem Jahr.</div>';
      $('#receiptList').querySelectorAll('[data-receipt]').forEach(b=>b.onclick=()=>openReceipt(receipts.find(r=>r.receipt_id===b.dataset.receipt)));
    }catch(e){$('#receiptList').innerHTML='<div class="empty">Belege konnten nicht geladen werden.</div>'}
  };
  openReceiptByOrder=async function(orderId){
    let r=receipts.find(x=>String(x.order_id_snapshot)===String(orderId));
    if(!r){try{const rows=await rpc('fts_admin_print_receipts_v57',{p_admin_code:credential(),p_year:null,p_event_token:null})||[];r=rows.find(x=>String(x.order_id_snapshot)===String(orderId))}catch{}}
    if(r)openReceipt(r);else toast('Für diesen Auftrag ist noch kein Beleg vorhanden.');
  };
  receiptPaperHtml=function(r){
    const base=baseReceiptPaperHtml(r);
    const test=r?.is_test?'<div class="receiptTestBanner">TESTBELEG · PAYPAL SANDBOX · KEIN ECHTER GELDFLUSS · NICHT ALS UMSATZ BUCHEN</div>':'';
    const pickup=r?.pickup_code?'<div class="receiptPickup"><span>Abholcode</span><b>'+esc(r.pickup_code)+'</b></div>':'';
    return test+base.replace('<div class="receiptItems">',pickup+'<div class="receiptItems">');
  };
  function upgradeCompactCard(order){
    if(!order||order.dataset.compact57==='1')return;
    order.dataset.compact57='1';

    let toggle=order.querySelector(':scope > .orderToggle');
    let body=order.querySelector(':scope > .orderBody');

    if(!toggle){
      const top=order.querySelector(':scope > .orderTop');
      if(!top)return;

      body=document.createElement('div');
      body.className='orderBody';
      const move=[...order.children].filter(x=>x!==top&& !x.classList.contains('testStrip'));
      move.forEach(x=>body.appendChild(x));
      order.appendChild(body);

      top.classList.add('orderToggleLegacy');
      top.setAttribute('role','button');
      top.setAttribute('tabindex','0');
      top.setAttribute('aria-expanded','false');

      const amount=top.querySelector('.amount');
      if(amount&&!amount.querySelector('.arrow')){
        const ar=document.createElement('i');
        ar.className='arrow';ar.textContent='⌃';
        amount.appendChild(ar);
      }
      const toggleLegacy=()=>{
        const now=order.classList.toggle('collapsed');
        top.setAttribute('aria-expanded',String(!now));
        saveStationState58(now?'':order.dataset.orderCard||'');
      };
      top.addEventListener('click',toggleLegacy);
      top.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();toggleLegacy()}});
    }else{
      toggle.setAttribute('aria-expanded','false');
      toggle.onclick=()=>{
        const collapsed=order.classList.toggle('collapsed');
        toggle.setAttribute('aria-expanded',String(!collapsed));
        saveStationState58(collapsed?'':order.dataset.orderCard||'');
      };
    }

    const remembered=readStationState58()?.openOrder||'';
    if(String(launchOrder||remembered||'')===String(order.dataset.orderCard||'')){
      order.classList.remove('collapsed');
      (toggle||order.querySelector(':scope > .orderTop'))?.setAttribute('aria-expanded','true');
    }else{
      order.classList.add('collapsed');
    }
  }
  function upgradeCompactOrders(root){
    if(!root)return;
    root.querySelectorAll('.order').forEach(upgradeCompactCard);
  }
  const compactObserver=new MutationObserver(muts=>{
    for(const m of muts){
      if(m.type==='childList'){
        upgradeCompactOrders(document.getElementById('liveOrders'));
        upgradeCompactOrders(document.getElementById('archiveOrders'));
        break;
      }
    }
  });
  compactObserver.observe(document.getElementById('liveOrders'),{childList:true,subtree:false});
  compactObserver.observe(document.getElementById('archiveOrders'),{childList:true,subtree:false});
  setTimeout(()=>{upgradeCompactOrders(document.getElementById('liveOrders'));upgradeCompactOrders(document.getElementById('archiveOrders'))},0);

  addCss();viewer();
  $('#eventFilter').onchange=()=>{renderOrders();saveStationState58();loadStock70(false)};
  $('#archiveEventFilter').onchange=()=>{renderOrders();saveStationState58()};
  $('#onlyReadyBtn').onclick=()=>{onlyReady=!onlyReady;$('#onlyReadyBtn').textContent=onlyReady?'Alle Aufträge anzeigen':'Nur druckbereit';renderOrders();saveStationState58()};
  $('#stockAdjustBtn').onclick=bookStock70;
  document.querySelectorAll('.tab').forEach(b=>b.addEventListener('click',()=>setTimeout(()=>saveStationState58(),0)));
  window.addEventListener('pagehide',()=>saveStationState58());
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')saveStationState58()});
  setTimeout(()=>{if(credential())loadCore(false)},250);
})();