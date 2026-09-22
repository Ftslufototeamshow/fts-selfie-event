(()=>{
  const page=(location.pathname.split('/').pop()||'').toLowerCase();if(page!=='dashboard.html')return;
  const PRECISE_START='22.09.2026';
  const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  let tries=0;
  const timer=setInterval(()=>{tries++;if(install()||tries>120)clearInterval(timer)},100);

  function install(){
    if(typeof rpc!=='function'||typeof credential!=='function'||typeof loadScanStats!=='function'||typeof openStats!=='function'||typeof render!=='function')return false;
    if(window.__ftsDashboardStatsV51)return true;window.__ftsDashboardStatsV51=true;

    const style=document.createElement('style');style.textContent=`
      .eventStatsCards.v51{grid-template-columns:repeat(5,1fr)}.eventStatsCard.pageviews .value{color:#7b55b5}.eventStatsCard.precise .value{color:#2f9f6c}
      .dailyStats.v51 .dailyRow{grid-template-columns:1.15fr .65fr .85fr .9fr .9fr .9fr}
      .v49SimpleRows{display:grid;gap:7px}.v49SimpleRow{display:grid;grid-template-columns:minmax(110px,1fr) auto;gap:10px;padding:8px 10px;border-radius:10px;background:#071719;border:1px solid rgba(255,255,255,.07)}.v49SimpleRow b{color:#f0ce82}.v49TimelineRow{display:grid;grid-template-columns:minmax(135px,.9fr) minmax(90px,.6fr) minmax(100px,.8fr);gap:8px;padding:8px 9px;border-bottom:1px solid rgba(255,255,255,.06);font-size:.72rem}.v49First{color:#83dda8;font-weight:900}.v49Return{color:#f0ce82;font-weight:900}
      .engagementGridV49{display:grid;grid-template-columns:1fr 1fr;gap:10px}.engagementBoxV49{padding:11px;border-radius:12px;background:#071719;border:1px solid rgba(255,255,255,.07)}.engagementBoxV49 h3{margin:0 0 8px;color:#f0ce82;font-size:.86rem}
      @media(max-width:900px){.eventStatsCards.v51{grid-template-columns:1fr 1fr}.dailyStats.v51 .dailyRow{grid-template-columns:1fr 1fr}.dailyStats.v51 .dailyRow span:first-child{grid-column:1/-1}.engagementGridV49{grid-template-columns:1fr}.v49TimelineRow{grid-template-columns:1fr 1fr}.v49TimelineRow span:last-child{grid-column:1/-1}}
    `;document.head.appendChild(style);

    loadScanStats=async function(){
      try{
        const [fresh,legacy]=await Promise.all([
          rpc('fts_admin_event_visit_stats_v49',{p_admin_code:credential()}).catch(()=>[]),
          rpc('fts_admin_event_scan_stats_v12',{p_admin_code:credential()}).catch(()=>[])
        ]);
        const fm=new Map((fresh||[]).map(x=>[String(x.event_token),x]));
        const lm=new Map((legacy||[]).map(x=>[String(x.event_token),x]));
        const keys=new Set([...fm.keys(),...lm.keys()]);
        scanStats=new Map([...keys].map(token=>{
          const f=fm.get(token)||{},l=lm.get(token)||{};
          return [token,{
            total:Number(l.scan_count||0),today:Number(l.scan_today||0),legacyUniqueSessions:Number(l.unique_sessions||0),
            preciseUnique:Number(f.unique_scans||0),preciseUniqueToday:Number(f.unique_today||0),
            pageViews:Number(f.page_views||0),pageViewsToday:Number(f.page_views_today||0),
            returns:Number(f.returning_visits||0),returnsToday:Number(f.returning_today||0)
          }];
        }));
      }catch(e){console.warn('Besucherstatistik v51',e);scanStats=new Map()}
    };

    scanEventText=function(e,count){return `${Number(count||0).toLocaleString('de-DE')} QR-Aufrufe`};

    const oldOpen=openStats;openStats=async function(token){await oldOpen(token);await patchStatsModal(token)};

    async function patchStatsModal(token){
      try{
        const [dailyFresh,dailyLegacy,hourly,devices,countries,timeline,gallery,social,photos]=await Promise.all([
          rpc('fts_admin_event_visit_daily_v49',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_event_scan_daily_v12',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_event_visit_hourly_v49',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_event_visit_devices_v49',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_event_visit_countries_v49',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_event_visit_timeline_v49',{p_admin_code:credential(),p_event_token:token,p_limit:300}).catch(()=>[]),
          rpc('fts_admin_gallery_link_stats_v48',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_social_stats_v49',{p_admin_code:credential(),p_event_token:token}).catch(()=>[]),
          rpc('fts_admin_get_event_photos',{p_admin_code:credential(),p_event_token:token,p_view:'active'}).catch(()=>[])
        ]);
        const s=scanStats.get(String(token))||{total:0,today:0,preciseUnique:0,pageViews:0,returns:0};
        const cards=document.querySelector('.eventStatsCards');if(cards){
          cards.classList.add('v51');
          const q=cards.querySelector('#statsQrN')?.parentElement?.querySelector('.label');if(q)q.textContent='QR-Aufrufe gesamt';
          const ss=cards.querySelector('#statsSessionsN')?.parentElement?.querySelector('.label');if(ss)ss.textContent=`Wiederbesuche ab ${PRECISE_START}`;
          const qr=document.getElementById('statsQrN');if(qr)qr.textContent=Number(s.total||0).toLocaleString('de-DE');
          const ret=document.getElementById('statsSessionsN');if(ret)ret.textContent=Number(s.returns||0).toLocaleString('de-DE');
          let pu=document.getElementById('statsPreciseUniqueV51');if(!pu){const box=document.createElement('div');box.className='eventStatsCard precise';box.innerHTML=`<div class="value" id="statsPreciseUniqueV51">0</div><div class="label">Eindeutige Besucher ab ${PRECISE_START}</div>`;cards.appendChild(box);pu=document.getElementById('statsPreciseUniqueV51')}
          pu.textContent=Number(s.preciseUnique||0).toLocaleString('de-DE');
          let pv=document.getElementById('statsPageViewsV49');if(!pv){const box=document.createElement('div');box.className='eventStatsCard pageviews';box.innerHTML='<div class="value" id="statsPageViewsV49">0</div><div class="label">Seitenaufrufe ab 22.09.</div>';cards.appendChild(box);pv=document.getElementById('statsPageViewsV49')}
          pv.textContent=Number(s.pageViews||0).toLocaleString('de-DE');
        }
        const summary=document.getElementById('statsSummary');if(summary)summary.textContent=`Die bisherigen QR-Aufrufe bleiben vollständig erhalten. Ab ${PRECISE_START} wird zusätzlich unterschieden: ein Browser/Gerät zählt einmal als eindeutiger Besucher, spätere Öffnungen als Wiederbesuch; Seitenaufrufe werden separat gezählt.`;

        const pMap=new Map();for(const p of photos||[]){if(p.is_test)continue;const d=String(p.event_day||'').slice(0,10);if(d)pMap.set(d,(pMap.get(d)||0)+1)}
        const fMap=new Map((dailyFresh||[]).map(x=>[String(x.visit_day||'').slice(0,10),x]));
        const lMap=new Map((dailyLegacy||[]).map(x=>[String(x.scan_day||'').slice(0,10),x]));
        const days=[...new Set([...pMap.keys(),...fMap.keys(),...lMap.keys()])].filter(Boolean).sort();
        const dailyEl=document.getElementById('dailyStats');if(dailyEl){dailyEl.classList.add('v51');dailyEl.innerHTML='<div class="dailyRow dailyHead"><span>Tag</span><span>Selfies</span><span>QR-Aufrufe</span><span>Eindeutige Besucher</span><span>Wiederbesuche</span><span>Seitenaufrufe</span></div>'+days.map(d=>{const f=fMap.get(d)||{},l=lMap.get(d)||{};return `<div class="dailyRow"><span>${typeof fmtDate==='function'?fmtDate(d):esc(d)}</span><span>${pMap.get(d)||0}</span><span>${Number(l.scan_count||0)}</span><span>${Number(f.unique_scans||0)}</span><span>${Number(f.returning_visits||0)}</span><span>${Number(f.page_views||0)}</span></div>`}).join('')}

        const byDay=new Map();for(const x of hourly||[]){const d=String(x.visit_day||'').slice(0,10),arr=byDay.get(d)||[];arr.push(x);byDay.set(d,arr)}
        const hourEl=document.getElementById('hourlyStats');if(hourEl)hourEl.innerHTML=[...byDay.entries()].map(([d,arr])=>`<div class="engagementBoxV49"><h3>${typeof fmtDate==='function'?fmtDate(d):esc(d)}</h3><div class="v49SimpleRows">${arr.map(x=>`<div class="v49SimpleRow"><span>${String(Number(x.visit_hour||0)).padStart(2,'0')}:00 Uhr</span><b>${Number(x.page_views||0)} Aufrufe · ${Number(x.unique_visitors||0)} Besucher · ${Number(x.returning_visits||0)} Wiederkehrer</b></div>`).join('')}</div></div>`).join('')||`<div class="empty">Präzise Stundenstatistik startet ab ${PRECISE_START}.</div>`;
        const devEl=document.getElementById('deviceStats');if(devEl)devEl.innerHTML='<div class="v49SimpleRows">'+(devices||[]).map(x=>`<div class="v49SimpleRow"><span>${esc(x.device_type||'Unbekannt')}</span><b>${Number(x.unique_visitors||0)}</b></div>`).join('')+'</div>';
        const countryEl=document.getElementById('countryStats');if(countryEl)countryEl.innerHTML='<div class="v49SimpleRows">'+(countries||[]).map(x=>`<div class="v49SimpleRow"><span>${esc(x.country_code||'XX')}</span><b>${Number(x.unique_visitors||0)}</b></div>`).join('')+'</div>';
        const tl=document.getElementById('scanTimeline');if(tl)tl.innerHTML=(timeline||[]).length?(timeline||[]).map(x=>`<div class="v49TimelineRow"><span>${new Date(x.visited_at).toLocaleString('de-DE',{dateStyle:'short',timeStyle:'short'})}</span><span class="${x.visit_kind==='first'?'v49First':'v49Return'}">${x.visit_kind==='first'?'Erster Besuch':'Wiederbesuch'}</span><span>${esc(x.device_type||'')} · ${esc(x.country_code||'XX')}</span></div>`).join(''):`<div class="empty">Präzise Besuchs-Timeline startet ab ${PRECISE_START}.</div>`;

        renderEngagement(gallery||[],social||[]);
      }catch(e){console.warn('Statistik v51 anzeigen',e)}
    }

    function renderEngagement(gallery,social){
      const modal=document.querySelector('#statsModal .modalPanel');if(!modal)return;
      let fold=document.getElementById('engagementFoldV49');if(!fold){fold=document.createElement('details');fold.id='engagementFoldV49';fold.className='statsFold';fold.dataset.statsFold='';fold.innerHTML='<summary>Online-Fotos & Social Media</summary><div class="statsFoldBody"><div id="engagementStatsV49"></div></div>';const ad=[...modal.querySelectorAll('.statsFold')].find(x=>/Werbe-Statistik/.test(x.querySelector('summary')?.textContent||''));if(ad)ad.insertAdjacentElement('afterend',fold);else modal.appendChild(fold)}
      const g=(gallery||[]).map(x=>`<div class="v49SimpleRow"><span>${esc(x.link_label||x.link_id||'Album')}</span><b>${Number(x.click_count||0).toLocaleString('de-DE')} Klicks</b></div>`).join('')||'<div class="note">Noch keine Album-/Galerie-Klicks.</div>';
      const names={facebook:'Facebook',instagram:'Instagram',tiktok:'TikTok'};const s=(social||[]).map(x=>`<div class="v49SimpleRow"><span>${names[x.platform]||esc(x.platform)}</span><b>${Number(x.click_count||0).toLocaleString('de-DE')} Klicks · ${Number(x.unique_visitors||0).toLocaleString('de-DE')} Besucher</b></div>`).join('')||'<div class="note">Noch keine Social-Media-Klicks.</div>';
      const root=document.getElementById('engagementStatsV49');if(root)root.innerHTML=`<div class="engagementGridV49"><div class="engagementBoxV49"><h3>Fotoalben / Galerien</h3><div class="v49SimpleRows">${g}</div></div><div class="engagementBoxV49"><h3>Social Follow</h3><div class="v49SimpleRows">${s}</div></div></div>`;
    }

    setTimeout(()=>{if(typeof loadEvents==='function')void loadEvents(false)},0);
    return true;
  }
})();