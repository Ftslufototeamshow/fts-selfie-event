(function(){
'use strict';
const protectedCache=new Map(),manualMasks=new Map();
const MASK_STORE_KEY='fts_social_privacy_masks_local_v2';
let mpLoader=null,mpDetector=null,mpQueue=Promise.resolve(),mpResolve=null;

function maskKey(url){try{const u=new URL(String(url||''),location.href);return u.origin+u.pathname}catch{return String(url||'').split('?')[0]}}
function clamp(v,min,max){return Math.min(max,Math.max(min,Number(v)||0))}
function sanitizeMasks(rows){
  if(!Array.isArray(rows))return[];
  return rows.slice(0,30).map(m=>({x:clamp(m?.x,.02,.98),y:clamp(m?.y,.02,.98),r:clamp(m?.r,.025,.22)}));
}
function readMaskStore(){
  try{const x=JSON.parse(localStorage.getItem(MASK_STORE_KEY)||'{}');return x&&typeof x==='object'?x:{}}catch{return{}}
}
function writeMaskStore(key,masks){
  try{const x=readMaskStore();if(masks.length)x[key]=masks;else delete x[key];localStorage.setItem(MASK_STORE_KEY,JSON.stringify(x))}catch{}
}
function getManualMasks(url){
  const key=maskKey(url);
  if(!manualMasks.has(key)){const stored=sanitizeMasks(readMaskStore()[key]);manualMasks.set(key,stored)}
  return (manualMasks.get(key)||[]).map(x=>({...x}));
}
function setManualMasks(url,masks,{persist=true}={}){
  const key=maskKey(url),clean=sanitizeMasks(masks);
  manualMasks.set(key,clean);protectedCache.delete(key);protectedCache.delete(String(url||''));
  if(persist)writeMaskStore(key,clean);
  return getManualMasks(url);
}
function addManualMask(url,mask,opts){const rows=getManualMasks(url);rows.push(mask);return setManualMasks(url,rows,opts)}
function removeLastManualMask(url,opts){const rows=getManualMasks(url);rows.pop();return setManualMasks(url,rows,opts)}

function clean(v){return String(v||'').trim()}
function hashtag(v){
  const s=clean(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/ß/g,'ss').replace(/[^a-zA-Z0-9]+/g,'');
  return s?('#'+s.slice(0,38)):'';
}
function hashtags(data){
  const out=[hashtag(data?.eventTitle),hashtag(data?.organizer),'#MySelfie','#FTSlu'].filter(Boolean);
  return [...new Set(out)].join(' ');
}
function eventDayInfo(data={},lang='de'){
  const raw=clean(data?.eventDay);
  if(!/^\d{4}-\d{2}-\d{2}$/.test(raw))return null;
  const d=new Date(raw+'T12:00:00');
  if(Number.isNaN(d.getTime()))return null;
  const locale=lang==='fr'?'fr-FR':lang==='en'?'en-GB':'de-DE';
  const weekday=d.toLocaleDateString(locale,{weekday:'long'});
  const date=d.toLocaleDateString(locale,{day:'2-digit',month:'2-digit',year:'numeric'});
  const index=Math.max(0,Number(data?.eventDayIndex)||0);
  return {raw,weekday,date,label:lang==='fr'?weekday+' '+date:weekday+', '+date,index};
}
function shareText(mode,data={},lang='de'){
  const eventTitle=clean(data.eventTitle)||'Event';
  const organizer=clean(data.organizer)||eventTitle;
  const tags=hashtags({eventTitle,organizer});
  const day=eventDayInfo(data,lang);
  const variant=day?day.index%3:0;

  if(day&&lang==='fr'){
    if(mode==='organizer'){
      if(variant===1)return `${day.label} · Encore une belle journée à « ${eventTitle} ». 📸 Merci à toutes les personnes présentes ce ${day.weekday}. Voici les selfies de cette journée.\n\n${tags}`;
      if(variant===2)return `${day.label} · Les selfies du ${day.weekday} à « ${eventTitle} ». 📸 ${organizer} vous remercie d’avoir participé. Voici les moments de cette journée.\n\n${tags}`;
      return `${day.label} · Les moments selfie de « ${eventTitle} ». 📸 ${organizer} remercie toutes les personnes présentes ce jour-là. Voici quelques souvenirs du ${day.weekday}.\n\n${tags}`;
    }
    if(mode==='fts'){
      if(variant===1)return `${day.label} · Deuxième série de moments MySelfie à « ${eventTitle} ». 📸 Merci à ${organizer} et à tous les participants de cette journée.\n\n${tags}`;
      if(variant===2)return `${day.label} · Retour sur le ${day.weekday} à « ${eventTitle} ». 📸 MySelfie by FTS.lu a créé de nouveaux souvenirs avec les visiteurs de cette journée.\n\n${tags}`;
      return `${day.label} · Souvenirs MySelfie de « ${eventTitle} ». 📸 Merci à ${organizer} et à toutes les personnes présentes ce ${day.weekday}.\n\n${tags}`;
    }
    return `${day.label} · Mon selfie de « ${eventTitle} ». 📸 Un souvenir du ${day.weekday} à partager.\n\n${tags}`;
  }

  if(day&&lang==='en'){
    if(mode==='organizer'){
      if(variant===1)return `${day.label} · Another great day at “${eventTitle}”. 📸 Thanks to everyone who joined us on ${day.weekday}. Here are the selfies from this day.\n\n${tags}`;
      if(variant===2)return `${day.label} · Our ${day.weekday} selfies from “${eventTitle}”. 📸 ${organizer} says thank you for joining in. Here are the moments from this event day.\n\n${tags}`;
      return `${day.label} · Selfie moments from “${eventTitle}”. 📸 ${organizer} thanks everyone who was there that day. Here are a few memories from ${day.weekday}.\n\n${tags}`;
    }
    if(mode==='fts'){
      if(variant===1)return `${day.label} · Another set of MySelfie moments from “${eventTitle}”. 📸 Thanks to ${organizer} and everyone who took part that day.\n\n${tags}`;
      if(variant===2)return `${day.label} · Looking back at ${day.weekday} at “${eventTitle}”. 📸 MySelfie by FTS.lu created more personal memories with the visitors of that day.\n\n${tags}`;
      return `${day.label} · MySelfie memories from “${eventTitle}”. 📸 Thanks to ${organizer} and everyone who joined us on ${day.weekday}.\n\n${tags}`;
    }
    return `${day.label} · My selfie from “${eventTitle}”. 📸 A ${day.weekday} memory to share.\n\n${tags}`;
  }

  if(day){
    if(mode==='organizer'){
      if(variant===1)return `${day.label} · Ein weiterer schöner Event-Tag bei „${eventTitle}“. 📸 Danke an alle Gäste, die am ${day.weekday} mitgemacht haben. Hier kommen die Selfies dieses Tages.\n\n${tags}`;
      if(variant===2)return `${day.label} · Unsere Selfies vom ${day.weekday} bei „${eventTitle}“. 📸 ${organizer} sagt Danke fürs Mitmachen – hier sind die Momente dieses Event-Tages.\n\n${tags}`;
      return `${day.label} · Selfie-Momente bei „${eventTitle}“. 📸 ${organizer} bedankt sich bei allen, die an diesem Tag dabei waren. Hier sind einige Eindrücke vom ${day.weekday}.\n\n${tags}`;
    }
    if(mode==='fts'){
      if(variant===1)return `${day.label} · Noch mehr MySelfie-Momente von „${eventTitle}“. 📸 Danke an ${organizer} und alle Gäste, die an diesem Event-Tag mitgemacht haben.\n\n${tags}`;
      if(variant===2)return `${day.label} · Rückblick auf den ${day.weekday} bei „${eventTitle}“. 📸 MySelfie von FTS.lu hat auch an diesem Tag persönliche Erinnerungen mit den Gästen festgehalten.\n\n${tags}`;
      return `${day.label} · MySelfie-Erinnerungen von „${eventTitle}“. 📸 Danke an ${organizer} und alle Gäste, die am ${day.weekday} dabei waren.\n\n${tags}`;
    }
    return `${day.label} · Mein Selfie von „${eventTitle}“. 📸 Eine schöne Erinnerung vom ${day.weekday} zum Teilen.\n\n${tags}`;
  }

  if(lang==='fr'){
    if(mode==='organizer')return `${organizer} remercie tous les visiteurs pour ces beaux moments lors de ${eventTitle}. 📸 C’était un plaisir de les partager avec vous ! Voici quelques selfies de l’événement. Merci d’avoir participé.\n\n${tags}`;
    if(mode==='fts')return `De beaux moments lors de ${eventTitle}. 📸 Avec MySelfie by FTS.lu, de nombreux souvenirs personnels ont été créés. Merci à ${organizer} pour la collaboration et à tous les visiteurs pour leur participation. Voici quelques impressions de l’événement.\n\n${tags}`;
    return `Mon selfie de ${eventTitle} 📸 Merci à ${organizer} pour ce bel événement et ce souvenir à emporter.\n\n${tags}`;
  }
  if(lang==='en'){
    if(mode==='organizer')return `${organizer} would like to thank everyone for the great moments at ${eventTitle}. 📸 It was fantastic having you with us! Here are a few of the event selfies. Thanks for joining in.\n\n${tags}`;
    if(mode==='fts')return `Great moments at ${eventTitle}. 📸 MySelfie by FTS.lu captured plenty of personal event memories. Thank you to ${organizer} for the collaboration and to everyone who joined in. Here are a few impressions from the event.\n\n${tags}`;
    return `My selfie from ${eventTitle} 📸 Thanks to ${organizer} for a great event and a memory to take home.\n\n${tags}`;
  }
  if(mode==='organizer')return `${organizer} bedankt sich bei allen Gästen für die tollen Momente bei „${eventTitle}“. 📸 Es war großartig mit euch! Hier zeigen wir einige Eindrücke aus den Selfies des Events. Danke fürs Mitmachen und Teilen.\n\n${tags}`;
  if(mode==='fts')return `Viele echte Eventmomente bei „${eventTitle}“. 📸 Mit MySelfie von FTS.lu sind persönliche Erinnerungen direkt vor Ort entstanden. Danke an ${organizer} für die Zusammenarbeit und an alle Gäste fürs Mitmachen. Hier zeigen wir einige ausgewählte Selfies vom Event.\n\n${tags}`;
  return `Mein Selfie von „${eventTitle}“ 📸 Danke an ${organizer} für das tolle Event – ein schöner Moment zum Mitnehmen.\n\n${tags}`;
}
async function copyText(text){
  try{if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(text);return true}}catch{}
  try{const t=document.createElement('textarea');t.value=text;t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();const ok=document.execCommand('copy');t.remove();return ok}catch{return false}
}
function loadScript(src){
  return new Promise((resolve,reject)=>{
    const old=[...document.scripts].find(x=>x.src===src);if(old){if(window.FaceDetection)return resolve();old.addEventListener('load',resolve,{once:true});old.addEventListener('error',reject,{once:true});return}
    const s=document.createElement('script');s.src=src;s.async=true;s.onload=resolve;s.onerror=reject;document.head.appendChild(s);
  });
}
async function ensureMediaPipe(){
  if(window.FaceDetection&&mpDetector)return mpDetector;
  if(mpLoader)return mpLoader;
  mpLoader=(async()=>{
    await loadScript('https://cdn.jsdelivr.net/npm/@mediapipe/face_detection@0.4.1646425229/face_detection.js');
    if(!window.FaceDetection)throw new Error('Gesichtserkennung konnte nicht geladen werden.');
    mpDetector=new window.FaceDetection({locateFile:file=>`https://cdn.jsdelivr.net/npm/@mediapipe/face_detection@0.4.1646425229/${file}`});
    mpDetector.setOptions({modelSelection:1,minDetectionConfidence:0.35});
    mpDetector.onResults(results=>{const fn=mpResolve;mpResolve=null;if(fn)fn(results)});
    return mpDetector;
  })();
  return mpLoader;
}
function imageFromBlob(blob){
  return new Promise((resolve,reject)=>{
    const u=URL.createObjectURL(blob),img=new Image();
    img.onload=()=>{URL.revokeObjectURL(u);resolve(img)};img.onerror=e=>{URL.revokeObjectURL(u);reject(e)};img.src=u;
  });
}
async function resizeBlob(blob,maxLongEdge=0,quality=.8){
  const max=Math.max(0,Number(maxLongEdge)||0);
  if(!max)return blob;
  const img=await imageFromBlob(blob),w=img.naturalWidth||img.width,h=img.naturalHeight||img.height,long=Math.max(w,h);
  if(!w||!h||long<=max)return blob;
  const scale=max/long,nw=Math.max(1,Math.round(w*scale)),nh=Math.max(1,Math.round(h*scale));
  const c=document.createElement('canvas');c.width=nw;c.height=nh;
  const x=c.getContext('2d');x.imageSmoothingEnabled=true;x.imageSmoothingQuality='high';x.drawImage(img,0,0,nw,nh);
  return await new Promise((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(new Error('Web-Version konnte nicht erzeugt werden.')),'image/jpeg',Math.max(.45,Math.min(.95,Number(quality)||.8))));
}
function normBox(b,w,h){
  if(!b)return null;
  if(Number.isFinite(b.x)&&Number.isFinite(b.y)&&Number.isFinite(b.width)&&Number.isFinite(b.height))return{x:b.x,y:b.y,w:b.width,h:b.height};
  const rb=b.relativeBoundingBox||b;
  if(Number.isFinite(rb.xMin)&&Number.isFinite(rb.yMin))return{x:rb.xMin*w,y:rb.yMin*h,w:rb.width*w,h:rb.height*h};
  if(Number.isFinite(b.xCenter)&&Number.isFinite(b.yCenter))return{x:(b.xCenter-b.width/2)*w,y:(b.yCenter-b.height/2)*h,w:b.width*w,h:b.height*h};
  return null;
}
async function detectFaces(img){
  const w=img.naturalWidth||img.width,h=img.naturalHeight||img.height,boxes=[];
  if('FaceDetector'in window){
    try{
      const d=new window.FaceDetector({fastMode:false,maxDetectedFaces:30});
      const rows=await d.detect(img);
      boxes.push(...rows.map(x=>normBox(x.boundingBox,w,h)).filter(Boolean));
    }catch(e){console.warn('Native face detection',e)}
  }
  try{
    await ensureMediaPipe();
    const run=()=>new Promise(async(resolve,reject)=>{
      const timer=setTimeout(()=>{mpResolve=null;reject(new Error('Gesichtserkennung Timeout'))},18000);
      mpResolve=results=>{
        clearTimeout(timer);
        const out=(results?.detections||[]).map(d=>normBox(d.boundingBox||d.locationData?.relativeBoundingBox,w,h)).filter(Boolean);
        resolve(out);
      };
      try{await mpDetector.send({image:img})}catch(e){clearTimeout(timer);mpResolve=null;reject(e)}
    });
    const p=mpQueue.then(run,run);mpQueue=p.catch(()=>{});
    boxes.push(...await p);
  }catch(e){console.warn('MediaPipe face detection',e)}
  return mergeFaceBoxes(boxes);
}
function boxIou(a,b){
  const x1=Math.max(a.x,b.x),y1=Math.max(a.y,b.y),x2=Math.min(a.x+a.w,b.x+b.w),y2=Math.min(a.y+a.h,b.y+b.h);
  const inter=Math.max(0,x2-x1)*Math.max(0,y2-y1),union=a.w*a.h+b.w*b.h-inter;
  return union>0?inter/union:0;
}
function mergeFaceBoxes(boxes){
  const out=[];
  for(const b0 of boxes||[]){
    const b={x:Number(b0.x)||0,y:Number(b0.y)||0,w:Number(b0.w)||0,h:Number(b0.h)||0};
    if(b.w<3||b.h<3)continue;
    const hit=out.findIndex(x=>boxIou(x,b)>.42);
    if(hit<0)out.push(b);
    else{
      const a=out[hit];
      out[hit]={x:(a.x+b.x)/2,y:(a.y+b.y)/2,w:Math.max(a.w,b.w),h:Math.max(a.h,b.h)};
    }
  }
  return out;
}
function backgroundFaces(boxes,w,h){
  if(!boxes||boxes.length<2)return[];
  const rows=boxes.map(b=>({...b,area:Math.max(1,b.w*b.h),cx:b.x+b.w/2,cy:b.y+b.h/2})).sort((a,b)=>b.area-a.area);
  const max=rows[0].area,diag=Math.hypot(w,h);
  const foreground=rows.filter(r=>r.area>=max*.46);
  const fx=foreground.reduce((n,r)=>n+r.cx,0)/foreground.length,fy=foreground.reduce((n,r)=>n+r.cy,0)/foreground.length;
  return rows.filter(r=>{
    if(foreground.includes(r))return false;
    const ratio=r.area/max,dist=Math.hypot(r.cx-fx,r.cy-fy)/diag;
    return ratio<.30||(ratio<.46&&dist>.24);
  });
}
function pixelateFace(ctx,img,b,w,h){
  const pad=Math.max(b.w,b.h)*0.38;
  const x=Math.max(0,b.x-pad),y=Math.max(0,b.y-pad),rw=Math.min(w-x,b.w+pad*2),rh=Math.min(h-y,b.h+pad*2);
  if(rw<3||rh<3)return;
  const small=document.createElement('canvas'),sw=Math.max(5,Math.round(rw/24)),sh=Math.max(5,Math.round(rh/24));
  small.width=sw;small.height=sh;const sx=small.getContext('2d');sx.imageSmoothingEnabled=true;sx.drawImage(img,x,y,rw,rh,0,0,sw,sh);
  ctx.save();ctx.beginPath();ctx.ellipse(x+rw/2,y+rh/2,rw*.49,rh*.49,0,0,Math.PI*2);ctx.clip();ctx.imageSmoothingEnabled=false;ctx.drawImage(small,0,0,sw,sh,x,y,rw,rh);ctx.restore();ctx.imageSmoothingEnabled=true;
}
function manualBox(mask,w,h){
  const size=Math.min(w,h)*mask.r;
  return{x:mask.x*w-size,y:mask.y*h-size,w:size*2,h:size*2};
}
async function protect(url){
  const key=maskKey(url);
  if(protectedCache.has(key))return protectedCache.get(key);
  const task=(async()=>{
    const res=await fetch(url,{mode:'cors',cache:'no-store'});if(!res.ok)throw new Error('Bild konnte nicht geladen werden ('+res.status+')');
    const sourceBlob=await res.blob(),img=await imageFromBlob(sourceBlob),w=img.naturalWidth||img.width,h=img.naturalHeight||img.height;
    const faces=await detectFaces(img),autoBlur=backgroundFaces(faces,w,h),manual=getManualMasks(url);
    if(!autoBlur.length&&!manual.length)return{blob:sourceBlob,detected:faces.length,autoProtectedCount:0,manualCount:0,protectedCount:0,unchanged:true};
    const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0,w,h);
    autoBlur.forEach(b=>pixelateFace(ctx,img,b,w,h));
    manual.forEach(m=>pixelateFace(ctx,img,manualBox(m,w,h),w,h));
    const blob=await new Promise((resolve,reject)=>canvas.toBlob(x=>x?resolve(x):reject(new Error('Bild konnte nicht erstellt werden.')),'image/jpeg',0.95));
    return{blob,detected:faces.length,autoProtectedCount:autoBlur.length,manualCount:manual.length,protectedCount:autoBlur.length+manual.length,unchanged:false};
  })();
  protectedCache.set(key,task);
  try{return await task}catch(e){protectedCache.delete(key);throw e}
}
async function blobFor(url,privacy){
  if(privacy)return (await protect(url)).blob;
  const r=await fetch(url,{mode:'cors',cache:'no-store'});if(!r.ok)throw new Error('Bild konnte nicht geladen werden ('+r.status+')');return r.blob();
}
function filename(name='FTS-Selfie.jpg'){return clean(name).replace(/[^a-zA-Z0-9._-]+/g,'-')||'FTS-Selfie.jpg'}
function saveBlob(blob,name){
  const u=URL.createObjectURL(blob),a=document.createElement('a');a.href=u;a.download=filename(name);document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),2500);
}
async function download(url,name,privacy=false,options={}){let blob=await blobFor(url,privacy);blob=await resizeBlob(blob,options?.maxLongEdge||0,options?.quality??.8);saveBlob(blob,name);return true}
function canShareFiles(files){try{return !!navigator.share&&(!navigator.canShare||navigator.canShare({files}))}catch{return false}}
async function shareOne({url,name='FTS-Selfie.jpg',text='',privacy=false,maxLongEdge=0,quality=.8}){
  const copied=await copyText(text);
  let blob=await blobFor(url,privacy);blob=await resizeBlob(blob,maxLongEdge,quality);
  const file=new File([blob],filename(name),{type:blob.type||'image/jpeg'});
  if(canShareFiles([file])){
    await navigator.share({files:[file],title:'MySelfie',text});
    return{shared:true,copied};
  }
  saveBlob(blob,name);return{shared:false,copied,downloaded:true};
}
async function shareMany({items,text='',title='MySelfie Event'}){
  const copied=await copyText(text),files=[];
  for(const item of items){
    const blob=await blobFor(item.url,!!item.privacy);
    files.push(new File([blob],filename(item.name||'FTS-Selfie.jpg'),{type:blob.type||'image/jpeg'}));
  }
  if(canShareFiles(files)){
    await navigator.share({files,title,text});return{shared:true,copied,count:files.length};
  }
  return{shared:false,copied,count:files.length,unsupported:true};
}
async function setPreview(img,url,on){
  if(!img)return{on:false};
  if(!on){
    const old=img.dataset.ftsOriginal||url;img.src=old;img.dataset.ftsPrivacy='0';
    const prev=img.dataset.ftsProtectedUrl;if(prev){URL.revokeObjectURL(prev);delete img.dataset.ftsProtectedUrl}
    return{on:false};
  }
  if(!img.dataset.ftsOriginal)img.dataset.ftsOriginal=img.currentSrc||img.src||url;
  const result=await protect(url);
  const u=URL.createObjectURL(result.blob);
  const old=img.dataset.ftsProtectedUrl;if(old)URL.revokeObjectURL(old);
  img.dataset.ftsProtectedUrl=u;img.src=u;img.dataset.ftsPrivacy='1';
  return{on:true,...result};
}
function ensureEditorStyles(){
  if(document.getElementById('ftsPrivacyEditorStyle'))return;
  const st=document.createElement('style');st.id='ftsPrivacyEditorStyle';st.textContent=`
  .ftsPrivacyEditor{position:fixed;inset:0;z-index:99999;background:rgba(2,8,9,.96);display:flex;flex-direction:column;padding:max(10px,env(safe-area-inset-top)) 10px max(12px,env(safe-area-inset-bottom));color:#fff;font-family:Inter,system-ui,sans-serif}
  .ftsPrivacyEditorHead{display:flex;align-items:center;justify-content:space-between;gap:10px;max-width:1100px;width:100%;margin:0 auto 8px}.ftsPrivacyEditorHead strong{font-size:.92rem}.ftsPrivacyEditorClose{border:0;border-radius:10px;background:#18383a;color:#fff;padding:9px 12px;font-weight:900}
  .ftsPrivacyStage{flex:1;min-height:0;display:flex;align-items:center;justify-content:center;overflow:auto}.ftsPrivacyStage img{display:block;max-width:100%;max-height:72vh;object-fit:contain;border-radius:12px;background:#000;box-shadow:0 12px 45px rgba(0,0,0,.45);touch-action:pinch-zoom}
  .ftsPrivacyEditorStatus{max-width:1100px;width:100%;margin:8px auto;padding:8px 10px;border-radius:10px;background:#0d292b;color:#b8cfca;font-size:.74rem;line-height:1.35}
  .ftsPrivacyEditorStatus.warn{background:#342c16;color:#f1d690}.ftsPrivacyEditorTools{max-width:1100px;width:100%;margin:0 auto;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px}
  .ftsPrivacyEditorTools button{border:0;border-radius:10px;padding:10px 8px;font-weight:900;font-size:.76rem}.ftsEditorPrimary{background:#2a684f;color:#fff}.ftsEditorSecondary{background:#173b3d;color:#fff}.ftsEditorDanger{background:#563333;color:#fff}.ftsEditorActive{outline:2px solid #d9b56d}
  @media(min-width:720px){.ftsPrivacyEditorTools{grid-template-columns:repeat(5,minmax(0,1fr))}.ftsPrivacyStage img{max-height:78vh}}
  `;document.head.appendChild(st);
}
async function openPrivacyEditor({url,title='Datenschutz-Vorschau',masks=null,onMasksChange=null,initialProtected=true}={}){
  if(!url)throw new Error('Kein Bild');
  ensureEditorStyles();
  if(Array.isArray(masks))setManualMasks(url,masks,{persist:true});
  return new Promise(resolve=>{
    let protectedView=!!initialProtected,addMode=false,objectUrl='';
    const root=document.createElement('div');root.className='ftsPrivacyEditor';
    root.innerHTML=`<div class="ftsPrivacyEditorHead"><strong></strong><button type="button" class="ftsPrivacyEditorClose">Schließen</button></div><div class="ftsPrivacyStage"><img alt="Datenschutz-Vorschau"></div><div class="ftsPrivacyEditorStatus">Vorschau wird vorbereitet …</div><div class="ftsPrivacyEditorTools"><button type="button" class="ftsEditorSecondary" data-view>Original anzeigen</button><button type="button" class="ftsEditorPrimary" data-add>Person hinzufügen</button><button type="button" class="ftsEditorDanger" data-undo>Letzte Markierung entfernen</button><button type="button" class="ftsEditorSecondary" data-share-note>Tippen = schließen</button><button type="button" class="ftsEditorSecondary" data-done>Fertig</button></div>`;
    document.body.appendChild(root);document.body.style.overflow='hidden';
    root.querySelector('strong').textContent=title;
    const img=root.querySelector('img'),status=root.querySelector('.ftsPrivacyEditorStatus'),viewBtn=root.querySelector('[data-view]'),addBtn=root.querySelector('[data-add]');
    function cleanup(){if(objectUrl)URL.revokeObjectURL(objectUrl);root.remove();document.body.style.overflow='';resolve({masks:getManualMasks(url)})}
    async function saveMasks(){if(onMasksChange)try{await onMasksChange(getManualMasks(url))}catch(e){console.warn('Privacy masks speichern',e);status.textContent='Markierung ist lokal aktiv, konnte aber nicht online gespeichert werden.';status.classList.add('warn')}}
    async function render(){
      addMode=false;addBtn.classList.remove('ftsEditorActive');addBtn.textContent='Person hinzufügen';status.classList.remove('warn');
      if(objectUrl){URL.revokeObjectURL(objectUrl);objectUrl=''}
      if(!protectedView){img.src=url;viewBtn.textContent='Geschützte Ansicht';status.textContent='Originalansicht. Tippe auf das Bild, um zur Galerie zurückzukehren.';return}
      status.textContent='Gesichter werden geprüft …';viewBtn.textContent='Original anzeigen';
      try{
        const r=await protect(url);objectUrl=URL.createObjectURL(r.blob);img.src=objectUrl;
        const auto=r.autoProtectedCount||0,manual=r.manualCount||0;
        if(auto+manual)status.textContent=`Geschützt: ${auto} automatisch · ${manual} manuell. Prüfe das Bild groß. Falls jemand übersehen wurde: „Person hinzufügen“ und dann auf das Gesicht tippen.`;
        else{status.textContent='Kein zusätzliches Hintergrund-Gesicht automatisch erkannt. Bitte groß prüfen; über „Person hinzufügen“ kannst du ein übersehenes Gesicht manuell schützen.';status.classList.add('warn')}
      }catch(e){img.src=url;status.textContent='Automatischer Hintergrundschutz konnte nicht erstellt werden. Du kannst Personen manuell markieren.';status.classList.add('warn')}
    }
    root.querySelector('.ftsPrivacyEditorClose').onclick=cleanup;root.querySelector('[data-done]').onclick=cleanup;
    root.querySelector('[data-view]').onclick=()=>{protectedView=!protectedView;render()};
    root.querySelector('[data-add]').onclick=()=>{protectedView=true;addMode=!addMode;addBtn.classList.toggle('ftsEditorActive',addMode);addBtn.textContent=addMode?'Jetzt auf das Gesicht tippen':'Person hinzufügen';status.textContent=addMode?'Tippe im großen Bild genau auf das Gesicht, das zusätzlich geschützt werden soll.':'Person hinzufügen beendet.'};
    root.querySelector('[data-undo]').onclick=async()=>{removeLastManualMask(url);await saveMasks();protectedView=true;render()};
    root.querySelector('[data-share-note]').onclick=()=>{status.textContent='Ohne aktiven „Person hinzufügen“-Modus schließt ein Tipp auf das große Foto die Vorschau.'};
    img.onclick=async e=>{
      if(!addMode)return cleanup();
      const rect=img.getBoundingClientRect();
      if(!rect.width||!rect.height)return;
      const x=clamp((e.clientX-rect.left)/rect.width,.02,.98),y=clamp((e.clientY-rect.top)/rect.height,.02,.98);
      addManualMask(url,{x,y,r:.065});await saveMasks();protectedView=true;render();
    };
    root.onclick=e=>{if(e.target===root)cleanup()};
    render();
  });
}

window.FTS_SOCIAL={shareText,hashtags,copyText,protect,download,shareOne,shareMany,setPreview,blobFor,getManualMasks,setManualMasks,addManualMask,removeLastManualMask,openPrivacyEditor,detectFaces};
})();