/* FTS Print Station pickup workflow v57 */
(()=>{
  'use strict';
  if((location.pathname.split('/').pop()||'').toLowerCase()!=='print.html')return;
  const baseReceiptPaperHtml=receiptPaperHtml;
  function addCss(){
    if(document.getElementById('ftsPickupStationCss57'))return;
    const s=document.createElement('style');s.id='ftsPickupStationCss57';s.textContent=`
.order{overflow:hidden}.orderToggle{width:100%;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:12px;text-align:left;padding:14px;background:transparent!important;color:inherit!important;border:0!important;border-radius:0!important}.orderToggle .amount{align-self:center}.orderToggle .arrow{display:inline-grid;place-items:center;width:27px;height:27px;margin-left:7px;border-radius:999px;background:#172829;color:var(--gold);font-size:1rem;vertical-align:middle}.order.collapsed .orderBody{display:none}.order:not(.collapsed) .orderToggle .arrow{transform:rotate(180deg)}.orderBody{border-top:1px solid #202a2b}.pickupStrip{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 14px;background:#0b1718}.pickupStrip span{font-size:.68rem;color:var(--muted);font-weight:800}.pickupStrip strong{font-size:1.3rem;letter-spacing:.12em;color:var(--gold)}.testStrip{padding:8px 14px;background:#5a3b17;color:#ffe1a0;font-weight:950;font-size:.72rem;letter-spacing:.04em}.photos{padding-top:12px}.photoItem{position:relative}.photoItem .viewPhoto{display:block;padding:0;width:100%;background:transparent;border:0}.photoItem .singlePrint{width:100%;margin-top:6px;padding:7px 6px;border-radius:8px;background:#182829;color:#e8efed;border:1px solid #ffffff12;font-size:.66rem}.pickupBtn{background:#265a44!important;color:#d7ffe8!important}.archiveBtn{background:#293335!important;color:#e5ecea!important}.pickupWait{background:#46351b!important;color:#ffe19b!important}.receiptTestBanner{padding:10px 12px;margin:0 0 18px;border:2px solid #a76c16;background:#fff2cf;color:#714300;font-weight:950;text-align:center;letter-spacing:.05em}.receiptPickup{margin:14px 0;padding:12px;border:1px solid #d6c9ac;background:#fffaf0;border-radius:10px}.receiptPickup b{display:block;font-size:1.7rem;letter-spacing:.14em;margin-top:3px}.photoViewer57{position:fixed;inset:0;z-index:9999;background:#000d;display:none;place-items:center;padding:14px}.photoViewer57.show{display:grid}.photoViewer57 .box{position:relative;max-width:min(960px,100%);max-height:96vh}.photoViewer57 img{display:block;max-width:100%;max-height:92vh;object-fit:contain;border-radius:12px;background:#050909}.photoViewer57 button{position:absolute;right:8px;top:8px;border:0;border-radius:999px;width:38px;height:38px;background:#111d;color:#fff;font-size:1.1rem}.orderActions{grid-template-columns:repeat(2,minmax(0,1fr))}@media(max-width:720px){.orderActions{grid-template-columns:1fr}.orderToggle{padding:12px}.pickupStrip{padding:9px 12px}}
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
      if(launchEvent)$('#eventFilter').value=launchEvent;
      renderOrders();renderYears();$('#statusText').textContent='Aktuell · '+new Date().toLocaleTimeString('de-DE',{hour:'2-digit',minute:'2-digit'});
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
  addCss();viewer();
  setTimeout(()=>{if(credential())loadCore(false)},250);
})();