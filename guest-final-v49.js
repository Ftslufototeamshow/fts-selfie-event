(()=>{
  const page=(location.pathname.split('/').pop()||'index.html').toLowerCase();
  const isGuest=page==='index.html'||page==='';
  const isAdmin=page==='admin.html';
  if(!isGuest&&!isAdmin)return;

  const VISITOR_KEY='fts_anonymous_visitor_v49';
  const pageVisitId=(crypto.randomUUID?crypto.randomUUID():'v_'+Date.now().toString(36)+'_'+Math.random().toString(36).slice(2));
  const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  function visitorId(){
    try{
      let id=localStorage.getItem(VISITOR_KEY)||'';
      if(!id){id=crypto.randomUUID?crypto.randomUUID():'d_'+Date.now().toString(36)+'_'+Math.random().toString(36).slice(2);localStorage.setItem(VISITOR_KEY,id)}
      return id;
    }catch{return 'session_'+pageVisitId}
  }
  function eventToken(){
    try{return String(ev?.event_token||ev?.token||ev?.short_code||'')}catch{return''}
  }
  function deviceType(){
    try{
      if(typeof scanDeviceType==='function')return scanDeviceType();
      const ua=navigator.userAgent||'',touch=navigator.maxTouchPoints||0,w=Math.min(screen.width||innerWidth,screen.height||innerHeight);
      if(/iPad|Tablet|SM-T|Tab/i.test(ua)||(touch>1&&w>=600))return'tablet';
      if(/Mobi|Android|iPhone|Phone/i.test(ua)||w<600)return'mobile';
      return'desktop';
    }catch{return'unknown'}
  }
  async function sendVisit(){
    const token=eventToken();if(!token||!navigator.onLine||window.__ftsVisitV49Sent)return false;
    window.__ftsVisitV49Sent=true;
    try{
      const r=await fetch(`${cfg.supabaseUrl}/functions/v1/fts-scan`,{
        method:'POST',keepalive:true,
        headers:{'apikey':cfg.publishableKey,'Content-Type':'application/json'},
        body:JSON.stringify({
          event_token:token,visitor_id:visitorId(),visit_id:pageVisitId,device_type:deviceType(),
          browser_language:navigator.language||'',browser_timezone:Intl.DateTimeFormat().resolvedOptions().timeZone||''
        })
      });
      if(!r.ok)throw new Error(await r.text());
      return true;
    }catch(e){window.__ftsVisitV49Sent=false;console.warn('Besucherstatistik v49',e);return false}
  }

  if(isAdmin)initAdminSocial();
  if(isGuest)initGuestFinal();

  function initAdminSocial(){
    let tries=0;
    const timer=setInterval(()=>{tries++;if(installAdminSocial()||tries>100)clearInterval(timer)},100);
  }
  function installAdminSocial(){
    if(typeof rpc!=='function'||typeof authCredential!=='function'||typeof persistEventLifecycle!=='function')return false;
    const manager=document.getElementById('galleryLinkManager');if(!manager)return false;
    if(window.__ftsSocialAdminV49)return true;window.__ftsSocialAdminV49=true;

    const host=manager.closest('.full')||manager.parentElement;
    const panel=document.createElement('div');panel.id='eventSocialV49';
    panel.style.cssText='margin-top:14px;padding:13px;border:1px solid rgba(217,181,109,.22);border-radius:14px;background:#081d1f';
    panel.innerHTML=`<b style="display:block;color:#f0cf83;margin-bottom:5px">Social Media des Veranstalters</b>
      <div class="hint" style="margin-bottom:10px">Maximal drei Follow-Buttons. Nur Plattformen mit eingetragenem Link werden auf der Gastseite angezeigt.</div>
      <div class="grid">
        <div><label>Facebook</label><input id="eventFacebookV49" type="url" placeholder="https://facebook.com/..."><div class="hint" id="facebookStatV49"></div></div>
        <div><label>Instagram</label><input id="eventInstagramV49" type="url" placeholder="https://instagram.com/..."><div class="hint" id="instagramStatV49"></div></div>
        <div class="full"><label>TikTok</label><input id="eventTiktokV49" type="url" placeholder="https://tiktok.com/@..."><div class="hint" id="tiktokStatV49"></div></div>
      </div>`;
    host.appendChild(panel);

    const fields={facebook:document.getElementById('eventFacebookV49'),instagram:document.getElementById('eventInstagramV49'),tiktok:document.getElementById('eventTiktokV49')};
    const oldPersist=persistEventLifecycle;
    const wrapped=async function(token){
      await oldPersist(token);
      await rpc('fts_admin_set_event_social_v49',{
        p_admin_code:authCredential(),p_event_token:token,
        p_facebook_url:String(fields.facebook.value||'').trim(),p_instagram_url:String(fields.instagram.value||'').trim(),p_tiktok_url:String(fields.tiktok.value||'').trim()
      });
    };
    wrapped.__ftsSocialV49=true;persistEventLifecycle=wrapped;

    async function loadExisting(){
      const token=typeof EDIT_TOKEN!=='undefined'&&EDIT_TOKEN?EDIT_TOKEN:'';if(!token)return;
      try{
        const rows=await rpc('fts_admin_get_event_social_v49',{p_admin_code:authCredential(),p_event_token:token})||[];
        const s=Array.isArray(rows)?rows[0]:rows;if(s){fields.facebook.value=s.facebook_url||'';fields.instagram.value=s.instagram_url||'';fields.tiktok.value=s.tiktok_url||''}
        const stats=await rpc('fts_admin_social_stats_v49',{p_admin_code:authCredential(),p_event_token:token})||[];
        const map=new Map(stats.map(x=>[String(x.platform),x]));
        for(const p of ['facebook','instagram','tiktok']){
          const x=map.get(p),el=document.getElementById(p+'StatV49');if(!el)continue;
          el.textContent=x?`${Number(x.click_count||0).toLocaleString('de-DE')} Klicks · ${Number(x.unique_visitors||0).toLocaleString('de-DE')} Besucher`:'Noch keine Klicks erfasst.';
        }
      }catch(e){console.warn('Social Media Eventdaten',e)}
    }
    void loadExisting();
    return true;
  }

  function initGuestFinal(){
    const style=document.createElement('style');
    style.textContent=`
      .ftsSocialV49{margin:8px 0 10px;padding:10px 11px;border:1px solid rgba(255,255,255,.08);border-radius:13px;background:rgba(3,13,15,.62)}
      .ftsSocialIntroV49{font-size:.73rem;color:#a7b6b3;line-height:1.35;margin:0 0 8px;text-align:center}.ftsSocialButtonsV49{display:flex;gap:7px;justify-content:center;flex-wrap:wrap}
      .ftsSocialBtnV49{min-width:0;flex:1 1 96px;max-width:170px;display:flex;align-items:center;justify-content:center;gap:7px;padding:9px 10px;border-radius:11px;text-decoration:none;color:#fff;font-size:.76rem;font-weight:900;border:1px solid rgba(255,255,255,.12)}
      .ftsSocialBtnV49 svg{width:20px;height:20px;flex:0 0 20px}.ftsSocialBtnV49.facebook{background:#1877f2}.ftsSocialBtnV49.instagram{background:linear-gradient(135deg,#833ab4,#fd1d1d,#fcb045)}.ftsSocialBtnV49.tiktok{background:#090909}
      .ftsGalleryReturnHintV49{padding:0 14px 11px;color:#aab8b5;font-size:.72rem;line-height:1.4}.ftsGalleryReturnHintV49 b{color:#f0cf83}
      @media(max-width:680px){
        .wrap{width:calc(100% - 10px)!important;padding:7px 0 20px!important}.card{padding:10px!important;border-radius:18px!important}
        .langBar{margin:-1px 0 6px!important;gap:4px!important}.langBar button{padding:5px 8px!important;font-size:.68rem!important}
        h1{font-size:clamp(1.55rem,7vw,2.35rem)!important;margin:4px 0 3px!important}.sub{font-size:.96rem!important;margin-bottom:5px!important}.meta{font-size:.7rem!important;margin-bottom:6px!important}
        .eventStatus{padding:7px 9px!important;margin-bottom:7px!important;font-size:.72rem!important}.net{padding:6px 8px!important;margin-bottom:7px!important;font-size:.72rem!important}
        .adSlot{margin:7px 0 5px!important}.adLabel{font-size:.55rem!important;margin-bottom:3px!important}.adFrame{border-radius:9px!important;box-shadow:0 6px 18px rgba(0,0,0,.2)!important}
        .moduleTitle{font-size:.82rem!important;margin:9px 0 5px!important}.choiceRow{display:flex!important;grid-template-columns:none!important;gap:5px!important;overflow-x:auto!important;padding-bottom:3px!important;scrollbar-width:thin}.choice{flex:0 0 104px!important;padding:6px 5px!important;font-size:.68rem!important;border-radius:10px!important}.choice small{font-size:.58rem!important;margin-top:2px!important}.frameMini{height:36px!important;margin-bottom:4px!important}.frameMini.portrait{width:26px!important}.frameMini.duo{width:29px!important}.frameMini.wide{width:48px!important;height:31px!important}.frameMini.story{width:23px!important;height:39px!important}.frameMini.free{width:39px!important;height:34px!important}
        .upload{min-height:98px!important;padding:10px!important;margin-top:8px!important;border-radius:14px!important}.upload strong{font-size:.98rem!important}.upload span{font-size:.72rem!important;margin-top:4px!important}
        .compare{margin-top:8px!important}.privacyInfo{margin:8px 0 5px!important;padding:8px 9px!important;font-size:.72rem!important}.consent{margin:7px 0 9px!important;font-size:.78rem!important;gap:7px!important}button.main{padding:12px!important;border-radius:12px!important}
        .mySelfiesAccess{margin:7px 0 2px!important;padding:9px 10px!important}.ftsGalleryV48{margin:7px 0 4px!important;border-radius:12px!important}.ftsGalleryV48>summary{padding:10px 11px!important}.ftsGalleryV48>summary strong{font-size:.86rem!important}.ftsGalleryV48>summary small{font-size:.64rem!important}.ftsGalleryReturnHintV49{padding:0 11px 8px!important;font-size:.65rem!important}.ftsGalleryItemV48{padding:9px!important;gap:7px!important}.ftsSocialV49{padding:8px!important;margin:5px 0 7px!important}.ftsSocialIntroV49{font-size:.66rem!important;margin-bottom:6px!important}.ftsSocialBtnV49{padding:8px 7px!important;font-size:.68rem!important;gap:5px!important}.ftsSocialBtnV49 svg{width:17px;height:17px;flex-basis:17px}
        .foot{margin-top:10px!important;font-size:.66rem!important}
      }`;
    document.head.appendChild(style);

    let socialLoaded=false,socialData=null;
    const socialIcon=p=>p==='facebook'
      ?`<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="white" d="M13.7 22v-8h2.7l.4-3.1h-3.1V8.9c0-.9.3-1.5 1.6-1.5H17V4.6c-.3 0-1.3-.1-2.5-.1-2.5 0-4.2 1.5-4.2 4.3v2.1H7.5V14h2.8v8h3.4z"/></svg>`
      :p==='instagram'
      ?`<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="16" height="16" rx="5" fill="none" stroke="white" stroke-width="2"/><circle cx="12" cy="12" r="3.5" fill="none" stroke="white" stroke-width="2"/><circle cx="17.3" cy="6.8" r="1.2" fill="white"/></svg>`
      :`<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#25F4EE" d="M14.3 4.1c.6 2 1.8 3.2 3.8 3.4v3c-1.3 0-2.5-.4-3.7-1.2v6.2a5.6 5.6 0 1 1-4.8-5.5v3a2.6 2.6 0 1 0 1.8 2.5V2h2.9v2.1z"/><path fill="#FE2C55" opacity=".9" d="M15.3 4.7c.7 1.2 1.7 1.9 3.1 2.1v2.6a6.7 6.7 0 0 1-4-1.3v7.4a5.6 5.6 0 0 1-7.9 5.1 5.6 5.6 0 0 0 8.8-4.6V4.7z"/><path fill="white" d="M13.4 4c.6 2 1.8 3.2 3.8 3.4v2.1a6.4 6.4 0 0 1-3.7-1.2v7.2a4.7 4.7 0 1 1-4-4.6v2.2a2.6 2.6 0 1 0 1.8 2.5V4h2.1z"/></svg>`;

    function langText(key){
      const l=typeof lang!=='undefined'?lang:'de';
      const d={
        follow:{de:'Noch mehr vom Event? Folge dem Veranstalter gerne auf seinen Social-Media-Kanälen.',en:'Want more from the event? Follow the organiser on social media.',fr:'Envie de voir plus de l’événement ? Suivez l’organisateur sur les réseaux sociaux.'},
        return:{de:'Schau gerne wieder vorbei: Bei mehrtägigen Events können erste Fotoalben schon am selben oder nächsten Tag online sein.',en:'Come back again: at multi-day events, the first photo albums may already be online the same day or the next day.',fr:'Revenez nous voir : lors des événements sur plusieurs jours, les premiers albums peuvent être en ligne le jour même ou le lendemain.'}
      };return d[key]?.[l]||d[key].de;
    }
    async function loadSocial(){
      const token=eventToken();if(!token||socialLoaded||typeof rpc!=='function')return;
      socialLoaded=true;
      try{const rows=await rpc('fts_selfie_event_social_v49',{p_event_token:token})||[];socialData=Array.isArray(rows)?rows[0]:rows}catch(e){console.warn('Social Links',e);socialData=null}
      renderSocial();
    }
    function renderSocial(){
      document.getElementById('ftsSocialV49')?.remove();
      if(!socialData)return;
      const links=[['facebook',socialData.facebook_url],['instagram',socialData.instagram_url],['tiktok',socialData.tiktok_url]].filter(([,u])=>/^https:\/\//i.test(String(u||'')));
      if(!links.length)return;
      const box=document.createElement('section');box.id='ftsSocialV49';box.className='ftsSocialV49';
      box.innerHTML=`<div class="ftsSocialIntroV49">${esc(langText('follow'))}</div><div class="ftsSocialButtonsV49">${links.map(([p,u])=>`<a class="ftsSocialBtnV49 ${p}" href="${esc(u)}" target="_blank" rel="noopener noreferrer" data-social-v49="${p}">${socialIcon(p)}<span>${p==='facebook'?'Facebook':p==='instagram'?'Instagram':'TikTok'}</span></a>`).join('')}</div>`;
      const gallery=document.getElementById('ftsGalleryV48'),ad=document.getElementById('adSlot'),net=document.getElementById('net');
      if(gallery)gallery.insertAdjacentElement('afterend',box);else if(ad)ad.insertAdjacentElement('afterend',box);else net?.insertAdjacentElement('afterend',box);
      box.querySelectorAll('[data-social-v49]').forEach(a=>a.addEventListener('click',()=>{const token=eventToken();if(!token||typeof rpc!=='function')return;void rpc('fts_selfie_track_social_click_v49',{p_event_token:token,p_platform:a.dataset.socialV49,p_visitor_id:visitorId()}).catch(()=>{})}));
    }
    function enhanceGallery(){
      const d=document.getElementById('ftsGalleryV48');if(!d)return;
      if(!d.querySelector('.ftsGalleryReturnHintV49')){
        const hint=document.createElement('div');hint.className='ftsGalleryReturnHintV49';hint.innerHTML=`<b>↻</b> ${esc(langText('return'))}`;
        const summary=d.querySelector('summary');summary?.insertAdjacentElement('afterend',hint);
      }else d.querySelector('.ftsGalleryReturnHintV49').innerHTML=`<b>↻</b> ${esc(langText('return'))}`;
    }

    let adsInstalled=false;
    function installAds(){
      if(adsInstalled||typeof startAds!=='function'||typeof showCurrentAd!=='function'||typeof stopAds!=='function'||typeof adItemsFor!=='function')return false;
      adsInstalled=true;
      const baseShow=showCurrentAd;
      const epochFor=()=>{
        const token=eventToken()||'event',key='fts_ad_epoch_v49_'+token;let n=0;
        try{n=Number(localStorage.getItem(key)||0);if(!n){n=Date.now();localStorage.setItem(key,String(n))}}catch{n=Date.now()}
        return n;
      };
      startAds=function(){
        stopAds();keepAdsVisible=true;const items=adItemsFor();if(!items.length){baseShow();return}
        const epoch=epochFor();let last=-1;
        const sync=()=>{
          const liveItems=adItemsFor();if(!liveItems.length){baseShow();return}
          const idx=Math.floor(Math.max(0,Date.now()-epoch)/3000)%liveItems.length;
          const slot=document.getElementById('adSlot');
          if(idx!==last||!slot?.classList.contains('show')){adIndex=idx;last=idx;baseShow()}
        };
        sync();if(items.length>1)adTimer=setInterval(sync,500);
      };
      if(typeof resetForNewSelfie==='function'){
        const oldReset=resetForNewSelfie;resetForNewSelfie=function(){const r=oldReset.apply(this,arguments);setTimeout(()=>{keepAdsVisible=true;positionTop();startAds()},20);return r};
      }
      return true;
    }
    function positionTop(){
      const net=document.getElementById('net'),ad=document.getElementById('adSlot');if(!net||!ad)return;
      if(typeof routeMode!=='undefined'&&routeMode==='expired'){ad.classList.remove('show');return}
      net.insertAdjacentElement('afterend',ad);
      const gallery=document.getElementById('ftsGalleryV48');if(gallery)ad.insertAdjacentElement('afterend',gallery);
      const social=document.getElementById('ftsSocialV49');if(social)(gallery||ad).insertAdjacentElement('afterend',social);
    }
    function afterRender(){
      installAds();positionTop();enhanceGallery();renderSocial();
      if(typeof routeMode==='undefined'||routeMode!=='expired'){try{keepAdsVisible=true;startAds()}catch(e){console.warn('Werbung v49',e)}}
    }

    let tries=0;
    const timer=setInterval(()=>{
      tries++;
      if(typeof ev!=='undefined'&&ev){void sendVisit();void loadSocial();afterRender();clearInterval(timer)}
      else if(tries>120)clearInterval(timer);
    },100);

    let renderWrapped=false;
    const wrapTimer=setInterval(()=>{
      if(renderWrapped||typeof render!=='function')return;
      renderWrapped=true;clearInterval(wrapTimer);
      const oldRender=render;render=function(){const r=oldRender.apply(this,arguments);setTimeout(afterRender,25);return r};
    },100);

    const mo=new MutationObserver(()=>{enhanceGallery();if(socialData)renderSocial();positionTop()});
    const card=document.getElementById('card');if(card)mo.observe(card,{childList:true,subtree:true});
    window.addEventListener('online',()=>{void sendVisit()});
  }
})();