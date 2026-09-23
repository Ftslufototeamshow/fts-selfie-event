/* FTS Selfie live camera preview v56 – additive, keeps native camera/file fallback */
(function(){
  'use strict';
  const cfg=window.FTS_CONFIG||{};
  let modal=null,video=null,stream=null,facing='user',busy=false;
  const labels={
    de:{open:'Kamera mit Live-Vorschau',fallback:'Oder Foto vom Handy wählen',title:'Live-Vorschau',capture:'Foto aufnehmen',switch:'Kamera wechseln',close:'Schließen',permission:'Kamera konnte nicht geöffnet werden. Du kannst weiterhin die normale Fotoauswahl benutzen.',preview:'Vorschau – das fertige Foto wird danach exakt gerendert.'},
    en:{open:'Camera with live preview',fallback:'Or choose a photo from your phone',title:'Live preview',capture:'Take photo',switch:'Switch camera',close:'Close',permission:'The camera could not be opened. You can still use the normal photo picker.',preview:'Preview – the final photo is rendered exactly after capture.'},
    fr:{open:'Caméra avec aperçu en direct',fallback:'Ou choisir une photo du téléphone',title:'Aperçu en direct',capture:'Prendre la photo',switch:'Changer de caméra',close:'Fermer',permission:'La caméra n’a pas pu être ouverte. Vous pouvez toujours utiliser la sélection photo normale.',preview:'Aperçu – la photo finale sera rendue exactement après la prise.'}
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
.ftsCamModal{position:fixed;inset:0;z-index:100000;background:#020808f2;display:none;align-items:center;justify-content:center;padding:max(10px,env(safe-area-inset-top)) 10px max(10px,env(safe-area-inset-bottom))}
.ftsCamModal.show{display:flex}.ftsCamBox{width:min(680px,100%);max-height:100%;display:grid;grid-template-rows:auto minmax(0,1fr) auto;background:#071719;border:1px solid #ffffff18;border-radius:20px;overflow:hidden;box-shadow:0 25px 80px #000b}
.ftsCamHead{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 14px}.ftsCamHead strong{font-size:.95rem}.ftsCamClose{border:1px solid #ffffff18;background:#15383a;color:#fff;border-radius:10px;padding:8px 10px;font:inherit;font-weight:800}
.ftsCamStage{position:relative;background:#000;overflow:hidden;min-height:300px;aspect-ratio:3/4}.ftsCamStage video{width:100%;height:100%;object-fit:cover;display:block;transform:scaleX(-1)}
.ftsCamOverlay{position:absolute;inset:0;pointer-events:none;display:flex;flex-direction:column;justify-content:flex-end}.ftsCamBanner{position:relative;width:100%;padding:5% 4.5% 5.2%;overflow:hidden}.ftsCamBannerBg{position:absolute;inset:0;z-index:0;background:linear-gradient(to bottom,transparent,rgba(7,19,21,.86) 30%,rgba(7,19,21,.95)) center/cover no-repeat}.ftsCamCopy{position:relative;z-index:1;text-shadow:0 3px 14px #000b}.ftsCamTitle{font-weight:900;font-size:clamp(24px,6.2vw,46px);line-height:1.02}.ftsCamSub{font-weight:800;font-size:clamp(16px,3.6vw,28px);margin-top:5px}.ftsCamLine{font-weight:650;font-size:clamp(12px,2.6vw,20px);margin-top:6px;color:#e8efed}.ftsCamBrand{position:absolute;right:4%;bottom:2%;font-size:10px;color:#ffffffaa;z-index:2}.ftsCamPumpkin{position:absolute;inset:6% 8% 24%;border:clamp(12px,4vw,26px) solid #ef7d1a;border-radius:46% 46% 43% 43%;box-shadow:inset 0 0 0 8px #8b3d08aa,0 0 0 1px #0000;display:none}.ftsCamPumpkin.show{display:block}.ftsCamPumpkin:before{content:' ';position:absolute;left:44%;top:-12%;width:12%;height:17%;background:#3b6b27;border-radius:8px}
.ftsCamNote{text-align:center;color:#91a5a1;font-size:.68rem;padding:7px 10px 0}.ftsCamControls{display:grid;grid-template-columns:auto 1fr;gap:8px;padding:10px 12px 13px}.ftsCamControls button{border:0;border-radius:12px;padding:13px 12px;font:inherit;font-weight:900;cursor:pointer}.ftsCamSwitch{background:#15383a;color:#fff;border:1px solid #ffffff18!important}.ftsCamCapture{background:var(--accent);color:#102020}
@media(min-width:650px){.ftsCamStage{aspect-ratio:4/3}.ftsCamStage video{object-fit:cover}.ftsCamBanner{padding-top:3%}}
`;document.head.appendChild(s);
  }
  function makeButton(){
    const host=document.getElementById('uploadLabel');if(!host||document.getElementById('ftsLiveCamOpen'))return;
    const wrap=document.createElement('div');wrap.id='ftsLiveCamEntry';
    wrap.innerHTML='<button type="button" class="ftsLiveCamOpen" id="ftsLiveCamOpen">📷 '+esc(t('open'))+'</button><div class="ftsLiveCamHint">'+esc(t('fallback'))+'</div>';
    host.parentNode.insertBefore(wrap,host);
    wrap.querySelector('button').onclick=openCamera;
  }
  function buildModal(){
    if(modal)return;
    modal=document.createElement('div');modal.className='ftsCamModal';modal.id='ftsCamModal';
    modal.innerHTML=`<div class="ftsCamBox">
      <div class="ftsCamHead"><strong id="ftsCamTitle"></strong><button type="button" class="ftsCamClose" id="ftsCamClose"></button></div>
      <div>
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
  async function restartStream(){
    stopStream();
    stream=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:facing},width:{ideal:1920},height:{ideal:1440}}});
    video.srcObject=stream;video.style.transform=facing==='user'?'scaleX(-1)':'none';await video.play().catch(()=>{});
  }
  function richText(el,text,spec){
    el.innerHTML='';el.style.color=spec?.color||'#fff';el.style.textAlign=spec?.align||'left';el.style.fontFamily=window.FTS_STUDIO_V56?.fontStack?.(spec?.font||'clean')||'system-ui';
    if(spec?.multicolor&&Array.isArray(spec.colors)&&spec.colors.length>1){[...String(text||'')].forEach((ch,i)=>{const sp=document.createElement('span');sp.textContent=ch;sp.style.color=spec.colors[i%spec.colors.length];el.appendChild(sp)})}
    else el.textContent=String(text||'');
  }
  function sourceText(spec,e,kind){const x=String(spec?.text||'').trim();if(x)return x;if((spec?.source||kind)==='subtitle')return e?.subtitle||'';if((spec?.source||kind)==='overlay')return e?.overlay_text||'';return e?.title||''}
  function updateOverlay(){
    if(!modal)return;const s=state(),e=s.event||{},conf=e.studio_v56||{},ov=conf.overlay||{},b=ov.banner||{},title=ov.title||{},sub=ov.subtitle||{},line=ov.line||{};
    const bg=modal.querySelector('#ftsCamBannerBg'),banner=modal.querySelector('.ftsCamBanner');
    const op=Math.max(0,Math.min(1,Number(b.opacity??.86))),color=b.color||'#071315';
    banner.style.display=ov.enabled===false?'none':'block';
    if(b.enabled===false)bg.style.background='transparent';
    else if(b.type==='solid')bg.style.background=alpha(color,op);
    else bg.style.background='linear-gradient(to bottom,'+alpha(color,0)+','+alpha(color,op*.72)+' 32%,'+alpha(color,op)+')';
    if(b.image_path){const u=assetUrl(b.image_path);bg.style.backgroundImage=(bg.style.backgroundImage?bg.style.backgroundImage+', ':'')+'url("'+u.replace(/"/g,'%22')+'")';bg.style.backgroundSize='cover';bg.style.backgroundPosition='center'}
    banner.style.minHeight=Math.max(16,Math.min(45,Number(b.height_pct||30)))+'%';
    const titleText=sourceText(title,e,'title'),subText=sourceText(sub,e,'subtitle'),lineText=sourceText(line,e,'overlay');
    richText(modal.querySelector('#ftsCamEventTitle'),titleText,title);
    richText(modal.querySelector('#ftsCamEventSub'),subText,{...sub,color:sub.color||e.accent||'#d9b56d'});
    richText(modal.querySelector('#ftsCamEventLine'),lineText,line);
    modal.querySelector('#ftsCamEventTitle').style.display=title.enabled===false?'none':'block';
    modal.querySelector('#ftsCamEventSub').style.display=sub.enabled===false?'none':'block';
    modal.querySelector('#ftsCamEventLine').style.display=line.enabled===false?'none':'block';
    const filter=s.filter||'natural';video.style.filter=window.FTS_GUEST_FILTER_CSS?.(filter)||'none';
    modal.querySelector('#ftsCamPumpkin').classList.toggle('show',filter==='pumpkin');
    modal.querySelector('#ftsCamTitle').textContent=t('title');modal.querySelector('#ftsCamClose').textContent=t('close');modal.querySelector('#ftsCamSwitch').textContent='↺ '+t('switch');modal.querySelector('#ftsCamCapture').textContent='● '+t('capture');modal.querySelector('#ftsCamNote').textContent=t('preview');
  }
  async function openCamera(){
    if(busy)return;busy=true;ensureStyle();buildModal();updateOverlay();
    if(!navigator.mediaDevices?.getUserMedia){document.getElementById('photo')?.click();busy=false;return}
    try{modal.classList.add('show');document.body.style.overflow='hidden';await restartStream();updateOverlay()}
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
  const observer=new MutationObserver(()=>{makeButton();if(modal?.classList.contains('show'))updateOverlay()});
  observer.observe(document.body,{childList:true,subtree:true});
  document.addEventListener('click',e=>{if(e.target.closest?.('[data-filter]'))setTimeout(updateOverlay,0)});
  window.addEventListener('pagehide',stopStream);document.addEventListener('visibilitychange',()=>{if(document.hidden&&modal?.classList.contains('show'))closeCamera()});
})();