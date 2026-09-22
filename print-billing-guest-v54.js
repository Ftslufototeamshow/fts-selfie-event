(()=>{
  const page=(location.pathname.split('/').pop()||'index.html').toLowerCase();
  if(page!=='index.html'&&page!=='')return;
  if(window.__ftsGuestPrintBillingV54)return;
  window.__ftsGuestPrintBillingV54=true;

  const localLang=()=>typeof lang!=='undefined'&&['de','en','fr'].includes(lang)?lang:'de';
  const modeText={
    guest_paypal:{de:'Gast zahlt selbst · 2,00 € pro Print',en:'Guest pays · €2.00 per print',fr:'Le visiteur paie · 2,00 € par tirage'},
    organizer_flat:{de:'Vom Veranstalter übernommen',en:'Covered by the organiser',fr:'Pris en charge par l’organisateur'},
    fts_free:{de:'FTS Gratisaktion',en:'FTS complimentary print',fr:'Impression offerte par FTS'}
  };
  const tMode=m=>modeText[m]?.[localLang()]||modeText[m]?.de||m;

  let tries=0;
  const timer=setInterval(()=>{
    tries++;
    if(install()||tries>120)clearInterval(timer);
  },100);

  function install(){
    if(typeof bindPrintControls!=='function'||typeof paypalPrintApi!=='function'||typeof updatePrintSummary!=='function')return false;
    const checkout=document.getElementById('selfiePrintCheckout');
    if(!checkout)return false;

    let coveredBtn=document.getElementById('coveredPrintBtn');
    if(!coveredBtn){
      coveredBtn=document.createElement('button');
      coveredBtn.type='button';coveredBtn.id='coveredPrintBtn';coveredBtn.className='ghostBtn';
      coveredBtn.style.cssText='display:none;width:100%;margin-top:10px;padding:13px;font-weight:950;background:var(--accent);color:#102020';
      checkout.appendChild(coveredBtn);
    }

    const buttonText=()=>{
      const mode=printConfig?.billing_mode||'guest_paypal',l=localLang();
      return mode==='organizer_flat'?(l==='fr'?'Envoyer à l’impression':l==='en'?'Send to print':'Zum Drucken senden'):(l==='fr'?'Impression gratuite':l==='en'?'Request complimentary print':'Gratisdruck anfordern');
    };
    const refreshLabel=()=>{const next=buttonText();if(coveredBtn.textContent!==next)coveredBtn.textContent=next};

    const oldSummary=updatePrintSummary;
    updatePrintSummary=function(){
      const mode=printConfig?.billing_mode||'guest_paypal';
      if(mode==='guest_paypal')return oldSummary.apply(this,arguments);
      const items=selectedPrintItems(),qty=items.reduce((n,x)=>n+Number(x.quantity||0),0),count=document.getElementById('selfiePrintCount'),sum=document.getElementById('selfiePrintTotal'),host=document.getElementById('paypalPrintHost');
      if(count)count.textContent=qty+' '+ptr('prints');
      if(sum)sum.textContent=mode==='organizer_flat'?(localLang()==='fr'?'Pris en charge':localLang()==='en'?'Covered':'Übernommen'):(localLang()==='fr'?'Offert':localLang()==='en'?'Complimentary':'Gratis');
      if(host)host.classList.remove('show');
      coveredBtn.style.display=qty>0?'block':'none';refreshLabel();
    };

    const oldBind=bindPrintControls;
    bindPrintControls=function(rows){
      const mode=printConfig?.billing_mode||'guest_paypal';
      if(mode==='guest_paypal'){coveredBtn.style.display='none';return oldBind.apply(this,arguments)}
      const box=document.getElementById('selfiePrintCheckout');if(!box)return;
      const canShow=!!printConfig?.enabled&&rows.some(r=>r.photo_id);box.classList.toggle('show',canShow);if(!canShow)return;
      const title=document.getElementById('selfiePrintTitle');if(title)title.textContent=ptr('title');
      const badge=document.getElementById('selfiePrintSandbox');if(badge)badge.textContent=tMode(mode);
      const intro=document.getElementById('selfiePrintIntro');
      if(intro)intro.textContent=mode==='organizer_flat'?(localLang()==='fr'?'Choisissez vos photos. Le coût est pris en charge par l’organisateur. Aucun paiement PayPal n’est nécessaire.':localLang()==='en'?'Choose your photos. The organiser covers the cost, so no PayPal payment is required.':'Wähle deine Fotos und die Anzahl. Der Veranstalter übernimmt die Kosten – du musst hier nichts bezahlen.'):(localLang()==='fr'?'Choisissez vos photos. Cette impression est offerte par FTS.':localLang()==='en'?'Choose your photos. This print is complimentary from FTS.':'Wähle deine Fotos und die Anzahl. Dieser Fotoprint ist eine Gratisaktion von FTS.');
      const hint=document.getElementById('selfiePrintPriceHint');if(hint)hint.textContent=localLang()==='fr'?'Aucun paiement sur le QR code':localLang()==='en'?'No payment at the QR code':'Keine Zahlung am QR-Code';
      document.querySelectorAll('.mySelfiePrintChoice label span').forEach(x=>{x.textContent=localLang()==='fr'?'Imprimer cette photo':localLang()==='en'?'Print this photo':'Dieses Foto drucken'});
      printSelection.clear();
      document.querySelectorAll('[data-print-select]').forEach(check=>{
        const i=Number(check.dataset.printSelect),row=rows[i],qty=document.querySelector('[data-print-qty="'+i+'"]');if(!row?.photo_id)return;
        printSelection.set(i,{photo_id:row.photo_id,selected:false,quantity:1});
        check.onchange=()=>{const x=printSelection.get(i);x.selected=check.checked;if(qty)qty.disabled=!check.checked;updatePrintSummary()};
        if(qty)qty.onchange=()=>{const x=printSelection.get(i);x.quantity=Math.max(1,Math.min(20,Number(qty.value)||1));qty.value=String(x.quantity);updatePrintSummary()};
      });
      document.getElementById('paypalPrintHost')?.classList.remove('show');
      if(typeof printStatus==='function')printStatus('');
      if(typeof showPrintReceipt==='function')showPrintReceipt(null);
      updatePrintSummary();refreshLabel();
    };

    coveredBtn.onclick=async()=>{
      const items=selectedPrintItems();if(!items.length){printStatus(ptr('choose'),'warn');return}
      coveredBtn.disabled=true;const old=coveredBtn.textContent;coveredBtn.textContent='…';
      try{
        const result=await paypalPrintApi('create-covered-order',{items});
        currentPrintOrder={print_order_id:result.order_id||result.print_order_id,paypal_order_id:null};
        printStatus(localLang()==='fr'?'Commande envoyée à l’impression ✓':localLang()==='en'?'Print order sent ✓':'Druckauftrag an die Print Station gesendet ✓','ok');
        printSelection.clear();document.querySelectorAll('[data-print-select]').forEach(x=>x.checked=false);document.querySelectorAll('[data-print-qty]').forEach(x=>{x.disabled=true;x.value='1'});updatePrintSummary();
      }catch(e){console.error(e);printStatus(String(e?.message||'Druckauftrag konnte nicht gesendet werden.'),'err')}
      finally{coveredBtn.disabled=false;coveredBtn.textContent=old;refreshLabel()}
    };

    refreshLabel();
    return true;
  }
})();