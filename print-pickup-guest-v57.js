/* FTS guest pickup status v57 */
(()=>{
  'use strict';
  const L={
    de:{title:'Dein Fotoprint',waiting:'Bezahlt · dein Foto wird vorbereitet',ready:'Dein Foto ist fertig ✓',readySub:'Bitte am FTS-Stand abholen und diesen Code zeigen.',picked:'Foto abgeholt ✓',pickedSub:'Danke und viel Freude mit deinem Foto.',code:'Abholcode',test:'TEST · PayPal Sandbox',prints:'Ausdrucke'},
    en:{title:'Your photo print',waiting:'Paid · your photo is being prepared',ready:'Your photo is ready ✓',readySub:'Please collect it at the FTS stand and show this code.',picked:'Photo collected ✓',pickedSub:'Thank you — enjoy your photo.',code:'Pickup code',test:'TEST · PayPal Sandbox',prints:'prints'},
    fr:{title:'Votre tirage photo',waiting:'Payé · votre photo est en préparation',ready:'Votre photo est prête ✓',readySub:'Retirez-la au stand FTS et montrez ce code.',picked:'Photo retirée ✓',pickedSub:'Merci et profitez bien de votre photo.',code:'Code de retrait',test:'TEST · PayPal Sandbox',prints:'tirages'}
  };
  let timer=null,busy=false,last='';
  const txt=k=>L[(typeof lang!=='undefined'&&L[lang])?lang:'de'][k]||k;
  function css(){
    if(document.getElementById('ftsPickupCss57'))return;
    const s=document.createElement('style');s.id='ftsPickupCss57';s.textContent=`
.ftsPickupPanel{display:none;margin:12px 0 14px;padding:14px;border-radius:15px;background:linear-gradient(145deg,#102d2f,#071719);border:1px solid rgba(217,181,109,.34);box-shadow:0 12px 34px #0003}.ftsPickupPanel.show{display:block}.ftsPickupHead{display:flex;justify-content:space-between;gap:10px;align-items:center}.ftsPickupHead strong{font-size:.95rem;color:#f5efe2}.ftsPickupTest{font-size:.62rem;font-weight:950;padding:4px 7px;border-radius:999px;background:#68491e;color:#ffd88a}.ftsPickupRows{display:grid;gap:8px;margin-top:10px}.ftsPickupRow{padding:11px;border-radius:12px;background:#061315;border:1px solid rgba(255,255,255,.08)}.ftsPickupState{font-weight:900;font-size:.86rem}.ftsPickupSub{color:#9fb0ad;font-size:.72rem;line-height:1.4;margin-top:3px}.ftsPickupCode{display:flex;justify-content:space-between;gap:12px;align-items:end;margin-top:9px;padding-top:9px;border-top:1px solid rgba(255,255,255,.08)}.ftsPickupCode span{font-size:.68rem;color:#9fb0ad}.ftsPickupCode b{font-size:clamp(1.6rem,8vw,2.4rem);letter-spacing:.12em;color:#f0ce82}.ftsPickupMeta{font-size:.65rem;color:#718581;margin-top:6px}
`;document.head.appendChild(s);
  }
  function host(){
    const anchor=document.getElementById('mySelfiesAccessBtn');if(!anchor)return null;
    let p=document.getElementById('ftsPickupPanel57');
    if(!p){p=document.createElement('section');p.id='ftsPickupPanel57';p.className='ftsPickupPanel';anchor.insertAdjacentElement('afterend',p)}
    return p;
  }
  function stateText(o){
    if(['REFUNDED','REVERSED'].includes(String(o.payment_status||'')))return {a:'Zahlung erstattet',b:'Dieser Druckauftrag ist nicht mehr zur Abholung vorgesehen.'};
    if(o.pickup_status==='READY_FOR_PICKUP')return {a:txt('ready'),b:txt('readySub')};
    if(o.pickup_status==='PICKED_UP'||o.pickup_status==='ARCHIVED')return {a:txt('picked'),b:txt('pickedSub')};
    return {a:txt('waiting'),b:''};
  }
  function render(rows){
    const p=host();if(!p)return;
    if(!rows?.length){p.classList.remove('show');p.innerHTML='';return}
    const key=JSON.stringify(rows.map(x=>[x.order_id,x.pickup_status,x.print_status,x.payment_status,x.pickup_code]));
    if(key===last&&p.innerHTML)return;last=key;
    p.innerHTML='<div class="ftsPickupHead"><strong>'+txt('title')+'</strong>'+(rows.some(x=>x.is_test)?'<span class="ftsPickupTest">'+txt('test')+'</span>':'')+'</div><div class="ftsPickupRows">'+rows.map(o=>{
      const st=stateText(o),showCode=!['PICKED_UP','ARCHIVED'].includes(o.pickup_status);
      return '<div class="ftsPickupRow"><div class="ftsPickupState">'+st.a+'</div>'+(st.b?'<div class="ftsPickupSub">'+st.b+'</div>':'')+(showCode?'<div class="ftsPickupCode"><span>'+txt('code')+'</span><b>'+String(o.pickup_code||'------')+'</b></div>':'')+'<div class="ftsPickupMeta">'+Number(o.quantity_total||0)+' '+txt('prints')+' · Auftrag '+String(o.order_id||'').slice(0,8).toUpperCase()+'</div></div>'
    }).join('')+'</div>';p.classList.add('show');
  }
  async function refresh(){
    if(busy||document.visibilityState==='hidden')return;
    let sid='';try{sid=typeof existingGuestSessionId==='function'?existingGuestSessionId():''}catch{}
    if(!sid||typeof ev==='undefined'||!ev?.event_token||typeof rpc!=='function'){render([]);return}
    busy=true;
    try{render(await rpc('fts_guest_print_pickups_v57',{p_event_token:ev.event_token,p_guest_session_id:sid})||[])}
    catch(e){console.warn('Abholstatus',e)}
    finally{busy=false}
  }
  css();
  const mo=new MutationObserver(()=>{host();void refresh()});mo.observe(document.body,{childList:true,subtree:true});
  setTimeout(refresh,800);timer=setInterval(refresh,10000);
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')refresh()});
  window.addEventListener('online',refresh);
})();