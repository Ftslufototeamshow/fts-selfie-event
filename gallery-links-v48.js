(()=>{
  const page=(location.pathname.split('/').pop()||'index.html').toLowerCase();
  const isAdmin=page==='admin.html';
  const isGuest=page==='index.html'||page==='';
  if(!isAdmin&&!isGuest)return;

  const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  const kindLabels={album:'Album',facebook:'Facebook',instagram:'Instagram',gallery:'Galerie',other:'Link'};

  if(isAdmin)initAdmin();
  if(isGuest)initGuest();

  function initAdmin(){
    let tries=0;
    const timer=setInterval(()=>{
      tries++;
      if(installAdmin()||tries>80)clearInterval(timer);
    },100);
  }

  function installAdmin(){
    if(typeof galleryLinks==='undefined'||typeof renderGalleryLinks!=='function'||typeof normalizedGalleryLinks!=='function'||!document.getElementById('galleryLinkManager'))return false;
    if(window.__ftsGalleryV48Admin)return true;
    window.__ftsGalleryV48Admin=true;

    const style=document.createElement('style');
    style.textContent=`
      .galleryLinkRowV48{display:grid;grid-template-columns:minmax(150px,.9fr) minmax(115px,.55fr) minmax(220px,1.5fr) auto;gap:8px;align-items:end;padding:11px;border:1px solid rgba(255,255,255,.08);border-radius:13px;background:#081d1f}
      .galleryLinkMetaV48{grid-column:1/-1;display:grid;grid-template-columns:minmax(190px,1fr) minmax(200px,1fr) auto;gap:8px;align-items:center;padding-top:2px}
      .galleryLiveV48{display:flex!important;align-items:center;gap:8px;margin:0;color:#dce6e3!important;font-weight:800}.galleryLiveV48 input{width:auto!important;transform:scale(1.12)}
      .galleryClicksV48{justify-self:end;border:1px solid rgba(217,181,109,.28);background:rgba(217,181,109,.08);color:#f0cf83;border-radius:999px;padding:7px 10px;font-size:.72rem;font-weight:900;white-space:nowrap}
      .galleryStatsHeadV48{display:flex;justify-content:space-between;gap:10px;align-items:center;padding:8px 2px 4px;color:#91a5a1;font-size:.75rem}.galleryStatsHeadV48 b{color:#f0cf83}
      @media(max-width:850px){.galleryLinkRowV48{grid-template-columns:1fr 1fr}.galleryLinkRowV48 .urlV48{grid-column:1/-1}.galleryLinkMetaV48{grid-template-columns:1fr}.galleryClicksV48{justify-self:start}.galleryLinkRowV48 .removeV48{width:100%}}
      @media(max-width:560px){.galleryLinkRowV48{grid-template-columns:1fr}.galleryLinkRowV48 .urlV48{grid-column:auto}}
    `;
    document.head.appendChild(style);

    let stats=new Map();
    const ensureShape=(item,index)=>{
      if(!item.id)item.id=(crypto.randomUUID?crypto.randomUUID():'link-'+Date.now()+'-'+index);
      if(!item.kind)item.kind=guessKind(item.url);
      if(typeof item.live_enabled!=='boolean')item.live_enabled=false;
      if(!item.publish_at)item.publish_at='';
      return item;
    };
    const guessKind=url=>{
      const u=String(url||'').toLowerCase();
      if(u.includes('facebook.com')||u.includes('fb.com'))return'facebook';
      if(u.includes('instagram.com'))return'instagram';
      return'album';
    };
    const toLocal=value=>{
      if(!value)return'';
      const d=new Date(value);if(!Number.isFinite(d.getTime()))return String(value).slice(0,16);
      const p=n=>String(n).padStart(2,'0');
      return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
    };
    const toIso=value=>{if(!value)return'';const d=new Date(value);return Number.isFinite(d.getTime())?d.toISOString():value};

    addGalleryLink=function(label='Fotos ansehen',url=''){
      galleryLinks.push({id:crypto.randomUUID(),label:String(label||''),url:String(url||''),kind:guessKind(url),live_enabled:false,publish_at:''});
      renderGalleryLinks();
    };

    renderGalleryLinks=function(){
      const box=document.getElementById('galleryLinkManager');if(!box)return;
      galleryLinks.forEach(ensureShape);
      if(!galleryLinks.length){box.innerHTML='<div class="galleryLinkEmpty">Noch kein Link eingetragen.</div>';return}
      const total=[...stats.values()].reduce((n,x)=>n+Number(x.click_count||0),0);
      box.innerHTML=`<div class="galleryStatsHeadV48"><span>Alben / Social-Links · Klickstatistik seit Aktivierung</span><b>${total.toLocaleString('de-DE')} Klicks gesamt</b></div>`+galleryLinks.map((x,i)=>{
        const s=stats.get(String(x.id));
        const clicks=Number(s?.click_count||0);
        const last=s?.last_clicked_at?` · zuletzt ${new Date(s.last_clicked_at).toLocaleString('de-DE',{dateStyle:'short',timeStyle:'short'})}`:'';
        return `<div class="galleryLinkRowV48" data-gallery-link-id="${esc(x.id)}">
          <div><label>Button-Text / Album</label><input class="galleryLinkLabel" value="${esc(x.label||'')}" placeholder="z. B. Fotos Samstag"></div>
          <div><label>Art</label><select class="galleryLinkKind"><option value="album"${x.kind==='album'?' selected':''}>Album</option><option value="gallery"${x.kind==='gallery'?' selected':''}>Galerie</option><option value="facebook"${x.kind==='facebook'?' selected':''}>Facebook</option><option value="instagram"${x.kind==='instagram'?' selected':''}>Instagram</option><option value="other"${x.kind==='other'?' selected':''}>Sonstiger Link</option></select></div>
          <div class="urlV48"><label>Internet-Link</label><input class="galleryLinkUrl" type="url" value="${esc(x.url||'')}" placeholder="https://..."></div>
          <button type="button" class="secondary galleryLinkRemove removeV48">Entfernen</button>
          <div class="galleryLinkMetaV48">
            <label class="galleryLiveV48"><input class="galleryLinkLive" type="checkbox"${x.live_enabled?' checked':''}> <span>Schon während des laufenden Events veröffentlichen</span></label>
            <div><label>Sichtbar ab (optional)</label><input class="galleryLinkPublishAt" type="datetime-local" value="${esc(toLocal(x.publish_at))}"></div>
            <div class="galleryClicksV48">${clicks.toLocaleString('de-DE')} Klick${clicks===1?'':'s'}${last}</div>
          </div>
        </div>`;
      }).join('');
      box.querySelectorAll('.galleryLinkRowV48').forEach(row=>{
        const item=galleryLinks.find(x=>String(x.id)===String(row.dataset.galleryLinkId));if(!item)return;
        row.querySelector('.galleryLinkLabel').oninput=e=>item.label=e.target.value;
        row.querySelector('.galleryLinkUrl').oninput=e=>{item.url=e.target.value;if(!item.kind||item.kind==='album')item.kind=guessKind(item.url)};
        row.querySelector('.galleryLinkKind').onchange=e=>item.kind=e.target.value;
        row.querySelector('.galleryLinkLive').onchange=e=>item.live_enabled=e.target.checked;
        row.querySelector('.galleryLinkPublishAt').onchange=e=>item.publish_at=toIso(e.target.value);
        row.querySelector('.galleryLinkRemove').onclick=()=>{galleryLinks=galleryLinks.filter(x=>String(x.id)!==String(item.id));renderGalleryLinks()};
      });
    };

    normalizedGalleryLinks=function(){
      const out=[];
      for(let i=0;i<galleryLinks.length;i++){
        const item=ensureShape(galleryLinks[i],i),raw=String(item.url||'').trim(),label=String(item.label||'').trim()||'Fotos ansehen';
        if(!raw)continue;
        const safe=typeof safeHttpUrl==='function'?safeHttpUrl(raw):(/^https?:\/\//i.test(raw)?raw:'');
        if(!safe)throw new Error('Bitte nur gültige https:// oder http:// Links bei den Galerien eintragen.');
        out.push({id:String(item.id),label,url:safe,kind:kindLabels[item.kind]?item.kind:'other',live_enabled:item.live_enabled===true,publish_at:item.publish_at?toIso(item.publish_at):''});
      }
      return out;
    };

    async function loadStats(){
      const token=typeof EDIT_TOKEN!=='undefined'&&EDIT_TOKEN?EDIT_TOKEN:'';if(!token||typeof rpc!=='function'||typeof authCredential!=='function')return;
      try{
        const rows=await rpc('fts_admin_gallery_link_stats_v48',{p_admin_code:authCredential(),p_event_token:token})||[];
        stats=new Map(rows.map(x=>[String(x.link_id),x]));
        renderGalleryLinks();
      }catch(e){console.warn('Galerie-Klickstatistik',e)}
    }

    renderGalleryLinks();
    void loadStats();
    return true;
  }

  function initGuest(){
    let tries=0;
    const timer=setInterval(()=>{
      tries++;
      if(installGuest()||tries>100)clearInterval(timer);
    },100);
  }

  function installGuest(){
    if(typeof lifecycleConfig!=='function'||typeof rpc!=='function'||typeof render!=='function'||!document.getElementById('card'))return false;
    if(window.__ftsGalleryV48Guest)return true;
    window.__ftsGalleryV48Guest=true;

    const style=document.createElement('style');
    style.textContent=`
      .ftsGalleryV48{margin:12px 0 4px;border:1px solid rgba(217,181,109,.28);border-radius:16px;background:rgba(217,181,109,.07);overflow:hidden}
      .ftsGalleryV48>summary{list-style:none;cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 15px;color:#f5f0e7}.ftsGalleryV48>summary::-webkit-details-marker{display:none}
      .ftsGalleryV48>summary strong{display:block;color:var(--accent);font-size:.98rem}.ftsGalleryV48>summary small{display:block;color:#91a5a1;margin-top:3px;font-size:.72rem;font-weight:600}.ftsGalleryArrowV48{font-size:1.15rem;color:var(--accent);transition:transform .2s}.ftsGalleryV48[open] .ftsGalleryArrowV48{transform:rotate(90deg)}
      .ftsGalleryListV48{display:grid;gap:7px;padding:0 10px 11px}.ftsGalleryItemV48{display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:10px;align-items:center;padding:12px;border-radius:12px;background:#0a2426;border:1px solid rgba(255,255,255,.08);color:#f3f0e8;text-decoration:none}.ftsGalleryItemV48:hover{border-color:rgba(217,181,109,.35)}
      .ftsGalleryKindV48{min-width:62px;text-align:center;border-radius:999px;padding:5px 7px;background:#15383a;color:#b9cbc7;font-size:.61rem;font-weight:900;letter-spacing:.04em;text-transform:uppercase}.ftsGalleryLabelV48{font-weight:900;overflow:hidden;text-overflow:ellipsis}.ftsGalleryGoV48{color:var(--accent);font-weight:950}.galleryMainList{display:none!important}
    `;
    document.head.appendChild(style);

    const oldRender=render;
    render=function(){const result=oldRender.apply(this,arguments);setTimeout(renderAlbums,0);return result};

    function liveText(key){
      const l=typeof lang!=='undefined'?lang:'de';
      const dict={
        title:{de:'Fotos jetzt ansehen',en:'View photos now',fr:'Voir les photos maintenant'},
        sub:{de:'Alben, Facebook, Instagram & Galerien',en:'Albums, Facebook, Instagram & galleries',fr:'Albums, Facebook, Instagram et galeries'}
      };
      return dict[key]?.[l]||dict[key].de;
    }
    function safeUrl(raw){
      if(typeof safeAdLink==='function')return safeAdLink(raw||'');
      try{const u=new URL(String(raw||''));return /^https?:$/.test(u.protocol)?u.href:''}catch{return''}
    }
    function availableLinks(){
      const lc=lifecycleConfig();let raw=Array.isArray(lc?.galleryLinks)?lc.galleryLinks:[];
      if(!raw.length&&lc?.galleryUrl)raw=[{id:'legacy-main',label:typeof tr==='function'?tr('galleryButton'):'Fotos ansehen',url:lc.galleryUrl,kind:'gallery'}];
      const mode=typeof routeMode!=='undefined'?String(routeMode):'';
      if(mode==='expired')return[];
      const afterEvent=mode==='gallery';
      const now=Date.now();
      return raw.map((x,i)=>{
        const url=safeUrl(x?.url||'');if(!url)return null;
        const publishAt=x?.publish_at?Date.parse(x.publish_at):NaN;
        if(Number.isFinite(publishAt)&&now<publishAt)return null;
        const live=x?.live_enabled===true||String(x?.live_enabled)==='true';
        if(!afterEvent&&!live)return null;
        return {id:String(x?.id||('legacy-'+(i+1))),label:String(x?.label||'Fotos ansehen').trim()||'Fotos ansehen',url,kind:kindLabels[x?.kind]?x.kind:'other'};
      }).filter(Boolean);
    }
    function renderAlbums(){
      const card=document.getElementById('card');if(!card)return;
      document.getElementById('ftsGalleryV48')?.remove();
      const old=card.querySelector('.galleryMainList');if(old)old.style.display='none';
      const links=availableLinks();if(!links.length)return;
      const details=document.createElement('details');details.id='ftsGalleryV48';details.className='ftsGalleryV48';
      details.innerHTML=`<summary><span><strong>${esc(liveText('title'))}</strong><small>${esc(liveText('sub'))} · ${links.length}</small></span><span class="ftsGalleryArrowV48">›</span></summary><div class="ftsGalleryListV48">${links.map(x=>`<a class="ftsGalleryItemV48" href="${esc(x.url)}" target="_blank" rel="noopener noreferrer" data-fts-gallery-id="${esc(x.id)}"><span class="ftsGalleryKindV48">${esc(kindLabels[x.kind]||'Link')}</span><span class="ftsGalleryLabelV48">${esc(x.label)}</span><span class="ftsGalleryGoV48">→</span></a>`).join('')}</div>`;
      const anchor=document.getElementById('net')||card.querySelector('.eventStatus');
      if(anchor)anchor.insertAdjacentElement('afterend',details);else card.prepend(details);
      details.querySelectorAll('[data-fts-gallery-id]').forEach(a=>a.addEventListener('click',()=>{
        const token=typeof ev!=='undefined'?(ev.event_token||ev.token||ev.short_code||''):'';
        if(!token)return;
        void rpc('fts_selfie_track_gallery_click_v48',{p_event_token:token,p_link_id:a.dataset.ftsGalleryId}).catch(()=>{});
      }));
    }

    setTimeout(renderAlbums,0);
    return true;
  }
})();