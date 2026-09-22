(()=>{
  const page=(location.pathname.split('/').pop()||'').toLowerCase();
  if(page!=='print.html'||typeof printOrder!=='function')return;
  const allowed=new Set(['COMPLETED','COVERED','FREE']);
  printOrder=async function(orderId,onlyIndex=null){
    const o=orders.find(x=>String(x.order_id)===String(orderId));
    if(!o||!allowed.has(String(o.payment_status||''))||o.print_status!=='READY')return toast('Dieser Auftrag ist nicht druckbereit.');
    const popup=window.open('','_blank');
    if(!popup)return alert('Bitte Pop-ups für die FTS Print Station erlauben.');
    popup.document.write('<!doctype html><title>Druck wird vorbereitet</title><body style="font-family:system-ui;padding:24px">Druck wird vorbereitet …</body>');
    try{
      const srcItems=Array.isArray(o.items)?o.items:[],selected=onlyIndex===null?srcItems:[srcItems[onlyIndex]].filter(Boolean),pages=[];
      for(let i=0;i<selected.length;i++){
        const item=selected[i];if(!item?.designed_path)continue;
        const url=await signedPath(item.designed_path,'FTS-Print-'+String(orderId).slice(0,8)+'-'+(i+1)+'.jpg');
        for(let q=0;q<Number(item.quantity||1);q++)pages.push(url);
      }
      if(!pages.length)throw new Error('Die Fotodatei ist nicht mehr vorhanden.');
      popup.document.open();
      popup.document.write('<!doctype html><html><head><meta charset="utf-8"><title>FTS Fotoprint</title><style>@page{size:100mm 150mm;margin:0}*{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff}.page{width:100mm;height:150mm;display:flex;align-items:center;justify-content:center;page-break-after:always;break-after:page;overflow:hidden}.page:last-child{page-break-after:auto;break-after:auto}.page img{width:100%;height:100%;object-fit:contain;display:block}@media screen{body{background:#222}.page{margin:15px auto;background:white;box-shadow:0 8px 30px #0008}}</style></head><body>'+pages.map(u=>'<div class="page"><img src="'+esc(u)+'"></div>').join('')+'<script>window.onload=()=>setTimeout(()=>window.print(),350)<\/script></body></html>');
      popup.document.close();toast('Druckdialog geöffnet. Danach „Gedruckt bestätigen“.');
    }catch(e){popup.close();alert('Druck konnte nicht vorbereitet werden: '+e.message)}
  };
})();