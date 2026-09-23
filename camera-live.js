/* FTS Selfie live camera preview v56 – additive, keeps native camera/file fallback */
(function(){
  'use strict';
  const cfg=window.FTS_CONFIG||{};
  let modal=null,video=null,stream=null,facing='user',busy=false;
  const labels={
    de:{open:'Kamera mit Live-Vorschau aufnehmen',fallback:'',title:'Live-Vorschau',capture:'Foto aufnehmen',switch:'Kamera wechseln',close:'Schließen',permission:'Die Kamera konnte nicht geöffnet werden. Bitte erlaube den Kamerazugriff im Browser und versuche es erneut.',preview:'Vorschau – das fertige Foto wird danach exakt gerendert.'},
    en:{open:'Take photo with live camera preview',fallback:'',title:'Live preview',capture:'Take photo',switch:'Switch camera',close:'Close',permission:'The camera could not be opened. Please allow camera access in your browser and try again.',preview:'Preview – the final photo is rendered exactly after capture.'},
    fr:{open:'Prendre la photo avec aperçu caméra',fallback:'',title:'Aperçu en direct',capture:'Prendre la photo',switch:'Changer de caméra',close:'Fermer',permission:'La caméra n’a pas pu être ouverte. Autorisez l’accès à la caméra dans le navigateur puis réessayez.',preview:'Aperçu – la photo finale sera rendue exactement après la prise.'}
  };
  function state(){try{return window.FTS_GUEST_CAMERA_STATE?.()||{}}catch{return {}}}
  function t(k){const l=state().lang||'de';return labels[l]?.[k]||labels.de[k]||k}
  function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
  function encPath(p){return String(p||'').split('/').map(encodeURIComponent).join('/')}
  function assetUrl(path){return path&&cfg.supabaseUrl&&cfg.liveBucket?cfg.supabaseUrl+'/storage/v1/object/public/'+encodeURIComponent(cfg.liveBucket)+'/'+encPath(path):''}
  function alpha(hex,a){
    const h=String(hex||'#071315').replace('#','');
    const v=parseInt(h.length===3?h.split('').map(x=>x+x).join(''):h,16);
    if(!Number.isFinite(v))return 'rgba(7,19,21,'+a+')';
    return 'rgba('+((v>>16)&255)+','+((v>>8)&255)+','+(v&255)+','+a+')';
  }
  function ensureStyle(){
    if(document.getElementById('ftsLiveCameraStyle'))return;
    const s=document.createElement('style');s.id='ftsLiveCameraStyle';s.textContent=`
.ftsLiveCamOpen{width:100%;border:1px solid color-mix(in srgb,var(--accent) 55%,transparent);background:linear-gradient(135deg,#15383a,#102628);color:#fff;border-radius:15px;padding:14px 16px;font:inherit;font-weight:900;cursor:pointer;margin-top:14px}
.ftsLiveCamHint{text-align:center;color:#829592;font-size:.7rem;margin:7px 0 0}
.ftsCamModal{position:fixed;inset:0;z-index:100000;background:#020808f2;display:none;align-items:center;justify-content:center;overflow:hidden;overscroll-behavior:none;padding:max(8px,env(safe-area-inset-top)) 8px max(8px,env(safe-area-inset-bottom))}
.ftsCamModal.show{display:flex}.ftsCamBox{width:min(680px,100%);height:min(900px,calc(100dvh - 16px));max-height:calc(100dvh - 16px);min-height:0;display:grid;grid-template-rows:auto minmax(0,1fr) auto;background:#071719;border:1px solid #ffffff18;border-radius:20px;overflow:hidden;box-shadow:0 25px 80px #000b}
.ftsCamHead{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:10px 12px}.ftsCamHead strong{font-size:.95rem}.ftsCamClose{border:1px solid #ffffff18;background:#15383a;color:#fff;border-radius:10px;padding:8px 10px;font:inherit;font-weight:800}
.ftsCamBody{min-height:0;overflow:hidden;display:flex;flex-direction:column}.ftsCamStage{position:relative;background:#000;overflow:hidden;min-height:0;aspect-ratio:var(--fts-camera-ratio,3/4);flex:1 1 auto}.ftsCamStage video{width:100%;height:100%;object-fit:cover;display:block;transform:scaleX(-1)}
.ftsCamOverlay{position:absolute;inset:0;pointer-events:none;display:flex;flex-direction:column;justify-content:flex-end}.ftsCamBanner{position:relative;width:100%;padding:5% 4.5% 5.2%;overflow:hidden}.ftsCamBannerBg{position:absolute;inset:0;z-index:0;background:linear-gradient(to bottom,transparent,rgba(7,19,21,.86) 30%,rgba(7,19,21,.95)) center/cover no-repeat}.ftsCamCopy{position:relative;z-index:1;text-shadow:0 3px 14px #000b}.ftsCamTitle{font-weight:900;font-size:clamp(24px,6.2vw,46px);line-height:1.02}.ftsCamSub{font-weight:800;font-size:clamp(16px,3.6vw,28px);margin-top:5px}.ftsCamLine{font-weight:650;font-size:clamp(12px,2.6vw,20px);margin-top:6px;color:#e8efed}.ftsCamBrand{position:absolute;right:4%;bottom:2%;font-size:10px;color:#ffffffaa;z-index:2}.ftsCamPumpkin{position:absolute;inset:6% 8% 24%;border:clamp(12px,4vw,26px) solid #ef7d1a;border-radius:46% 46% 43% 43%;box-shadow:inset 0 0 0 8px #8b3d08aa,0 0 0 1px #0000;display:none}.ftsCamPumpkin.show{display:block}.ftsCamPumpkin:before{content:' ';position:absolute;left:44%;top:-12%;width:12%;height:17%;background:#3b6b27;border-radius:8px}
.ftsCamNote{text-align:center;color:#91a5a1;font-size:.68rem;padding:7px 10px 0}.ftsCamControls{display:grid;grid-template-columns:auto 1fr;gap:8px;padding:10px 12px 13px}.ftsCamControls button{border:0;border-radius:12px;padding:13px 12px;font:inherit;font-weight:900;cursor:pointer}.ftsCamSwitch{background:#15383a;color:#fff;border:1px solid #ffffff18!important}.ftsCamCapture{background:var(--accent);color:#102020}
@media(min-width:650px){.ftsCamStage video{object-fit:cover}.ftsCamBanner{padding-top:3%}}
@media(orientation:landscape){
  .ftsCamModal{padding:max(4px,env(safe-area-inset-top)) max(6px,env(safe-area-inset-right)) max(4px,env(safe-area-inset-bottom)) max(6px,env(safe-area-inset-left));align-items:center}
  .ftsCamBox{width:min(1180px,100%);height:calc(100dvh - 8px);max-height:calc(100dvh - 8px);border-radius:14px;grid-template-rows:auto minmax(0,1fr) auto}
  .ftsCamHead{padding:5px 10px}.ftsCamHead strong{font-size:.82rem}.ftsCamClose{padding:6px 9px;font-size:.78rem}
  .ftsCamBody{min-height:0}.ftsCamStage{min-height:0;height:100%;aspect-ratio:auto!important}
  .ftsCamBanner{padding:2.2% 3.2% 2.4%}.ftsCamTitle{font-size:clamp(17px,3.8vw,34px)}.ftsCamSub{font-size:clamp(12px,2.5vw,22px)}.ftsCamLine{font-size:clamp(10px,1.8vw,16px);margin-top:3px}
  .ftsCamNote{display:none}
  .ftsCamControls{grid-template-columns:minmax(118px,.55fr) minmax(180px,1fr);gap:6px;padding:5px 10px max(5px,env(safe-area-inset-bottom));background:#071719}
  .ftsCamControls button{padding:9px 10px;font-size:.8rem}
}
`;document.head.appendChild(s);
  }
  function makeButton(){
    const host=document.getElementById('uploadLabel');if(!host||document.getElementById('ftsLiveCamOpen'))return;
    const wrap=document.createElement('div');wrap.id='ftsLiveCamEntry';
    wrap.innerHTML='<button type="button" class="ftsLiveCamOpen" id="ftsLiveCamOpen">📷 '+esc(t('open'))+'</button>';
    host.parentNode.insertBefore(wrap,host);
    wrap.querySelector('button').onclick=openCamera;
  }
  function buildModal(){
    if(modal)return;
    modal=document.createElement('div');modal.className='ftsCamModal';modal.id='ftsCamModal';
    modal.innerHTML=`<div class="ftsCamBox">
      <div class="ftsCamHead"><strong id="ftsCamTitle"></strong><button type="button" class="ftsCamClose" id="ftsCamClose"></button></div>
      <div class="ftsCamBody">
        <div class="ftsCamStage"><video id="ftsCamVideo" autoplay muted playsinline></video><div class="ftsCamOverlay"><div class="ftsCamPumpkin" id="ftsCamPumpkin"></div><div class="ftsCamBanner"><div class="ftsCamBannerBg" id="ftsCamBannerBg"></div><div class="ftsCamCopy"><div class="ftsCamTitle" id="ftsCamEventTitle"></div><div class="ftsCamSub" id="ftsCamEventSub"></div><div class="ftsCamLine" id="ftsCamEventLine"></div></div><div class="ftsCamBrand">FTS.lu · Selfie Event</div></div></div></div>
        <div class="ftsCamNote" id="ftsCamNote"></div>
      </div>
      <div class="ftsCamControls"><button type="button" class="ftsCamSwitch" id="ftsCamSwitch"></button><button type="button" class="ftsCamCapture" id="ftsCamCapture"></button></div>
    </div>`;
    document.body.appendChild(modal);video=modal.querySelector('video');
    modal.querySelector('#ftsCamClose').onclick=closeCamera;
    modal.querySelector('#ftsCamSwitch').onclick=async()=>{facing=facing==='user'?'environment':'user';await restartStream()};
    modal.querySelector('#ftsCamCapture').onclick=capture;
    modal.addEventListener('click',e=>{if(e.target===modal)closeCamera()});
  }
  function stopStream(){if(stream){stream.getTracks().forEach(x=>x.stop());stream=null}if(video)video.srcObject=null}
  function desiredAspect(){
    const adaptive=window.FTS_PHOTO_ENGINE?.adaptiveConfig?.(state()?.event?.studio_config||{});
    if(adaptive?.enabled!==false&&adaptive?.auto_orientation!==false){
      return window.innerWidth>window.innerHeight ? 3/2 : 2/3;
    }
    const layout=String(state().layout||'solo');
    if(layout==='groupwide')return 3/2;
    if(layout==='grouptall'||layout==='solo'||layout==='duo')return 2/3;
    return window.innerWidth>window.innerHeight?3/2:2/3;
  }
  function syncOrientation(){
    if(!modal)return;
    const landscape=window.innerWidth>window.innerHeight;
    modal.classList.toggle('landscape',landscape);
    modal.style.setProperty('--fts-camera-ratio',String(desiredAspect()));
    if(modal.classList.contains('show')){
      requestAnimationFrame(()=>{try{video?.play?.().catch(()=>{})}catch{}});
    }
  }
  function cameraConstraints(){
    const landscape=window.innerWidth>window.innerHeight;
    return landscape
      ? {facingMode:{ideal:facing},width:{ideal:1920},height:{ideal:1280},aspectRatio:{ideal:1.5}}
      : {facingMode:{ideal:facing},width:{ideal:1280},height:{ideal:1920},aspectRatio:{ideal:2/3}};
  }
  async function restartStream(){
    stopStream();syncOrientation();
    stream=await navigator.mediaDevices.getUserMedia({audio:false,video:cameraConstraints()});
    video.srcObject=stream;video.style.transform=facing==='user'?'scaleX(-1)':'none';await video.play().catch(()=>{});syncOrientation();
  }
  function richText(el,text,spec){
    el.innerHTML='';el.style.color=spec?.color||'#fff';el.style.textAlign=spec?.align||'left';el.style.fontFamily=window.FTS_PHOTO_ENGINE?.fontStack?.(spec?.font||'clean')||'system-ui';
    if(spec?.multicolor&&Array.isArray(spec.colors)&&spec.colors.length>1){[...String(text||'')].forEach((ch,i)=>{const sp=document.createElement('span');sp.textContent=ch;sp.style.color=spec.colors[i%spec.colors.length];el.appendChild(sp)})}
    else el.textContent=String(text||'');
  }
  function sourceText(spec,e,kind){const x=String(spec?.text||'').trim();if(x)return x;if((spec?.source||kind)==='subtitle')return e?.subtitle||'';if((spec?.source||kind)==='overlay')return e?.overlay_text||'';return e?.title||''}
  function updateOverlay(){
    if(!modal)return;
    const s=state(),e=s.event||{},conf=e.studio_config||{},ov=conf.overlay||{},b=ov.banner||{},title=ov.title||{},sub=ov.subtitle||{},line=ov.line||{};
    const adaptive=window.FTS_PHOTO_ENGINE?.adaptiveConfig?.(conf)||{};
    const landscape=window.innerWidth>window.innerHeight,mode=landscape?(adaptive.landscape||{}):(adaptive.portrait||{});
    const requestedHeight=Math.max(12,Math.min(45,Number(b.height_pct||30)));
    const normalCap=Number(mode.banner_max_pct||(landscape?22:18));
    const minCap=Number(mode.banner_min_pct||(landscape?14:12));
    const bannerPct=adaptive.enabled===false?requestedHeight:Math.max(minCap,Math.min(normalCap,requestedHeight));
    const previewTextScale=adaptive.enabled===false?1:Math.max(Number(adaptive.min_text_scale||.68),landscape?.82:.74);

    const bg=modal.querySelector('#ftsCamBannerBg'),banner=modal.querySelector('.ftsCamBanner');
    const op=Math.max(0,Math.min(1,Number(b.opacity??.86))),color=b.color||'#071315';
    banner.style.display=ov.enabled===false?'none':'block';
    banner.style.minHeight=bannerPct+'%';
    if(b.enabled===false)bg.style.background='transparent';
    else if(b.type==='solid')bg.style.background=alpha(color,op);
    else bg.style.background='linear-gradient(to bottom,'+alpha(color,0)+','+alpha(color,op*.72)+' 32%,'+alpha(color,op)+')';
    if(b.image_path){
      const u=assetUrl(b.image_path);
      bg.style.backgroundImage=(bg.style.backgroundImage?bg.style.backgroundImage+', ':'')+'url("'+u.replace(/"/g,'%22')+'")';
      bg.style.backgroundSize='cover';bg.style.backgroundPosition='center';
    }

    const titleText=sourceText(title,e,'title'),subText=sourceText(sub,e,'subtitle'),lineText=sourceText(line,e,'overlay');
    const titleEl=modal.querySelector('#ftsCamEventTitle'),subEl=modal.querySelector('#ftsCamEventSub'),lineEl=modal.querySelector('#ftsCamEventLine');
    richText(titleEl,titleText,title);
    richText(subEl,subText,{...sub,color:sub.color||e.accent||'#d9b56d'});
    richText(lineEl,lineText,line);
    titleEl.style.display=title.enabled===false?'none':'block';
    subEl.style.display=sub.enabled===false?'none':'block';
    lineEl.style.display=line.enabled===false?'none':'block';
    const titleBase=landscape?3.4:3.0,subBase=landscape?2.35:2.15,lineBase=landscape?1.65:1.55;
    titleEl.style.fontSize='clamp(15px,'+(titleBase*previewTextScale)+'vmin,'+(landscape?28:26)+'px)';
    subEl.style.fontSize='clamp(11px,'+(subBase*previewTextScale)+'vmin,'+(landscape?19:18)+'px)';
    lineEl.style.fontSize='clamp(9px,'+(lineBase*previewTextScale)+'vmin,14px)';

    const filter=s.filter||'natural';video.style.filter=window.FTS_GUEST_FILTER_CSS?.(filter)||'none';
    modal.querySelector('#ftsCamPumpkin').classList.toggle('show',filter==='pumpkin');
    modal.querySelector('#ftsCamTitle').textContent=t('title');modal.querySelector('#ftsCamClose').textContent=t('close');modal.querySelector('#ftsCamSwitch').textContent='↺ '+t('switch');modal.querySelector('#ftsCamCapture').textContent='● '+t('capture');
    modal.querySelector('#ftsCamNote').textContent=t('preview');
  }
  async function openCamera(){
    if(busy)return;busy=true;ensureStyle();buildModal();syncOrientation();updateOverlay();
    if(!navigator.mediaDevices?.getUserMedia){busy=false;alert(t('permission'));return}
    try{modal.classList.add('show');document.body.style.overflow='hidden';syncOrientation();await restartStream();updateOverlay();syncOrientation()}
    catch(e){console.warn('FTS Live Kamera',e);closeCamera();alert(t('permission'))}
    finally{busy=false}
  }
  function closeCamera(){stopStream();if(modal)modal.classList.remove('show');document.body.style.overflow=''}
  async function capture(){
    if(!video?.videoWidth||busy)return;busy=true;
    try{
      const c=document.createElement('canvas');c.width=video.videoWidth;c.height=video.videoHeight;const x=c.getContext('2d');
      if(facing==='user'){x.translate(c.width,0);x.scale(-1,1)}x.drawImage(video,0,0,c.width,c.height);
      const blob=await new Promise(r=>c.toBlob(r,'image/jpeg',.94));if(!blob)throw new Error('Foto konnte nicht erzeugt werden');
      const file=new File([blob],'selfie-'+Date.now()+'.jpg',{type:'image/jpeg',lastModified:Date.now()});
      closeCamera();await window.FTS_ACCEPT_CAMERA_FILE?.(file);
      document.getElementById('compare')?.scrollIntoView({behavior:'smooth',block:'center'});
    }catch(e){console.error(e);alert(String(e?.message||e))}
    finally{busy=false}
  }
  ensureStyle();buildModal();makeButton();
  const observer=new MutationObserver(()=>{makeButton()});
  observer.observe(document.body,{childList:true,subtree:true});
  document.addEventListener('click',e=>{if(e.target.closest?.('[data-filter],[data-layout]'))setTimeout(()=>{updateOverlay();syncOrientation()},0)});
  window.addEventListener('resize',syncOrientation,{passive:true});
  window.addEventListener('orientationchange',()=>setTimeout(syncOrientation,80),{passive:true});
  window.visualViewport?.addEventListener?.('resize',syncOrientation,{passive:true});
  screen.orientation?.addEventListener?.('change',()=>setTimeout(syncOrientation,60));
  window.addEventListener('pagehide',stopStream);document.addEventListener('visibilitychange',()=>{if(document.hidden&&modal?.classList.contains('show'))closeCamera()});
})();