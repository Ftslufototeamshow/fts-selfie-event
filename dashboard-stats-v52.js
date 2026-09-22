(()=>{
  const page=(location.pathname.split('/').pop()||'').toLowerCase();
  if(page!=='dashboard.html'||window.__ftsDashboardStatsV52)return;
  window.__ftsDashboardStatsV52=true;
  let tries=0;const timer=setInterval(()=>{tries++;if(install()||tries>150)clearInterval(timer)},100);

  function install(){
    if(typeof rpc!=='function'||typeof credential!=='function'||typeof loadScanStats!=='function'||typeof openStats!=='function'||typeof render!=='function')return false;
    const oldLoad=loadScanStats;
    loadScanStats=async function(){
      try{
        const [legacy,newer]=await Promise.all([
          rpc('fts_admin_event_scan_stats_v12',{p_admin_code:credential()}).catch(()=>[]),
          rpc('fts_admin_event_visit_stats_v49',{p_admin_code:credential()}).catch(()=>[])
        ]);
        const oldMap=new Map((legacy||[]).map(x=>[String(x.event_token),x]));
        const newMap=new Map((newer||[]).map(x=>[String(x.event_token),x]));
        const keys=new Set([...oldMap.keys(),...newMap.keys()]);
        scanStats=new Map([...keys].map(k=>{const o=oldMap.get(k)||{},n=newMap.get(k)||{};const legacyTotal=Number(o.scan_count||0),legacyToday=Number(o.scan_today||0),newUnique=Number(n.unique_scans||0),newToday=Number(n.unique_today||0);return[k,{total:legacyTotal+newUnique,today:legacyToday+newToday,unique:newUnique,legacy:legacyTotal,legacyToday,newUnique,newUniqueToday:newToday,pageViews:Number(n.page_views||0),pageViewsToday:Number(n.page_views_today||0),returns:Number(n.returning_visits||0),returnsToday:Number(n.returning_today||0)}] }));
      }catch(e){console.warn('Besucherstatistik v52',e);await oldLoad()}
    };
    scanEventText=function(e,count){return `${Number(count||0).toLocaleString('de-DE')} QR-Aufrufe gesamt`};

    const previousRender=render;
    render=function(){const out=previousRender.apply(this,arguments);setTimeout(fixListLabels,25);return out};
    function fixListLabels(){
      document.querySelectorAll('.event .badge,.countLabel').forEach(el=>{
        const t=String(el.textContent||'');
        if(/neue QR-Besucher gesamt/i.test(t))el.textContent=t.replace(/neue QR-Besucher gesamt/ig,'QR-Aufrufe gesamt');
        else if(/QR-Besucher gesamt/i.test(t))el.textContent=t.replace(/QR-Besucher gesamt/ig,'QR-Aufrufe gesamt');
      });
    }

    const previousOpen=openStats;
    openStats=async function(token){await previousOpen(token);await patchModal(token)};

    async function patchModal(token){
      try{
        const [legacyDaily,newDaily]=await Promise.all([
          rpc('fts_admin_event_scan_daily_v12',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_event_visit_daily_v49',{p_admin_code:credential(),p_event_token:token}).catch(()=>[])
        ]);
        const s=scanStats.get(String(token))||{total:0,legacy:0,newUnique:0,returns:0,pageViews:0};
        const cards=document.querySelector('.eventStatsCards');
        if(cards){
          const qr=document.getElementById('statsQrN');if(qr)qr.textContent=Number(s.total||0).toLocaleString('de-DE');
          const qrLabel=qr?.parentElement?.querySelector('.label');if(qrLabel)qrLabel.textContent='QR-Aufrufe gesamt';
          const ret=document.getElementById('statsSessionsN');if(ret)ret.textContent=Number(s.returns||0).toLocaleString('de-DE');
          const retLabel=ret?.parentElement?.querySelector('.label');if(retLabel)retLabel.textContent='Wiederbesuche seit 22.09.';
          let unique=document.getElementById('statsUniqueV52');if(!unique){const card=document.createElement('div');card.className='eventStatsCard';card.innerHTML='<div class="value" id="statsUniqueV52">0</div><div class="label">Neue eindeutige Besucher seit 22.09.</div>';cards.appendChild(card);unique=card.querySelector('#statsUniqueV52')}
          unique.textContent=Number(s.newUnique||0).toLocaleString('de-DE');
          const pv=document.getElementById('statsPageViewsV49');if(pv)pv.textContent=Number(s.pageViews||0).toLocaleString('de-DE');
        }
        const summary=document.getElementById('statsSummary');if(summary)summary.textContent=`Historische QR-Aufrufe bleiben erhalten (${Number(s.legacy||0).toLocaleString('de-DE')} vor der neuen Zählung). Seit 22.09.2026 zählt ein Browser/Gerät pro Event nur einmal als neuer Besucher; weitere Öffnungen werden als Wiederbesuche und Seitenaufrufe erfasst.`;

        const oldMap=new Map((legacyDaily||[]).map(x=>[String(x.scan_day||'').slice(0,10),x]));
        const newMap=new Map((newDaily||[]).map(x=>[String(x.visit_day||'').slice(0,10),x]));
        const days=[...new Set([...oldMap.keys(),...newMap.keys()])].filter(Boolean).sort();
        const daily=document.getElementById('dailyStats');if(daily){daily.classList.add('v49');daily.innerHTML='<div class="dailyRow dailyHead"><span>Tag</span><span>QR alt</span><span>Neue Besucher</span><span>Wiederbesuche</span><span>Seitenaufrufe</span></div>'+days.map(d=>{const o=oldMap.get(d)||{},n=newMap.get(d)||{};return `<div class="dailyRow"><span>${typeof fmtDate==='function'?fmtDate(d):d}</span><span>${Number(o.scan_count||0)}</span><span>${Number(n.unique_scans||0)}</span><span>${Number(n.returning_visits||0)}</span><span>${Number(n.page_views||0)}</span></div>`}).join('')}
      }catch(e){console.warn('Statistik v52 anzeigen',e)}
    }

    setTimeout(async()=>{try{await loadScanStats();if(typeof loadEvents==='function')await loadEvents(false);setTimeout(fixListLabels,50)}catch{}},0);
    return true;
  }
})();