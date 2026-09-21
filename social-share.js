(function(){
'use strict';
const protectedCache=new Map();
let mpLoader=null,mpDetector=null,mpQueue=Promise.resolve(),mpResolve=null;

function clean(v){return String(v||'').trim()}
function hashtag(v){
  const s=clean(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/ß/g,'ss').replace(/[^a-zA-Z0-9]+/g,'');
  return s?('#'+s.slice(0,38)):'';
}
function hashtags(data){
  const out=[hashtag(data?.eventTitle),hashtag(data?.organizer),'#MySelfie','#FTSlu'].filter(Boolean);
  return [...new Set(out)].join(' ');
}
function shareText(mode,data={},lang='de'){
  const eventTitle=clean(data.eventTitle)||'Event';
  const organizer=clean(data.organizer)||eventTitle;
  const tags=hashtags({eventTitle,organizer});
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
    mpDetector.setOptions({model:'short',minDetectionConfidence:0.55});
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
function normBox(b,w,h){
  if(!b)return null;
  if(Number.isFinite(b.x)&&Number.isFinite(b.y)&&Number.isFinite(b.width)&&Number.isFinite(b.height))return{x:b.x,y:b.y,w:b.width,h:b.height};
  const rb=b.relativeBoundingBox||b;
  if(Number.isFinite(rb.xMin)&&Number.isFinite(rb.yMin))return{x:rb.xMin*w,y:rb.yMin*h,w:rb.width*w,h:rb.height*h};
  if(Number.isFinite(b.xCenter)&&Number.isFinite(b.yCenter))return{x:(b.xCenter-b.width/2)*w,y:(b.yCenter-b.height/2)*h,w:b.width*w,h:b.height*h};
  return null;
}
async function detectFaces(img){
  const w=img.naturalWidth||img.width,h=img.naturalHeight||img.height;
  if('FaceDetector'in window){
    try{
      const d=new window.FaceDetector({fastMode:true,maxDetectedFaces:20});
      const rows=await d.detect(img);
      const boxes=rows.map(x=>normBox(x.boundingBox,w,h)).filter(Boolean);
      if(boxes.length)return boxes;
    }catch(e){console.warn('Native face detection',e)}
  }
  try{
    await ensureMediaPipe();
    const run=()=>new Promise(async(resolve,reject)=>{
      let timer=setTimeout(()=>{mpResolve=null;reject(new Error('Gesichtserkennung Timeout'))},15000);
      mpResolve=results=>{
        clearTimeout(timer);
        const boxes=(results?.detections||[]).map(d=>normBox(d.boundingBox||d.locationData?.relativeBoundingBox,w,h)).filter(Boolean);
        resolve(boxes);
      };
      try{await mpDetector.send({image:img})}catch(e){clearTimeout(timer);mpResolve=null;reject(e)}
    });
    const p=mpQueue.then(run,run);mpQueue=p.catch(()=>{});return await p;
  }catch(e){console.warn('MediaPipe face detection',e);throw e}
}
function backgroundFaces(boxes,w,h){
  if(!boxes||boxes.length<2)return[];
  const rows=boxes.map(b=>({...b,area:Math.max(1,b.w*b.h),cx:b.x+b.w/2,cy:b.y+b.h/2})).sort((a,b)=>b.area-a.area);
  const lead=rows[0],diag=Math.hypot(w,h),max=lead.area;
  return rows.slice(1).filter(b=>{
    const ratio=b.area/max,dist=Math.hypot(b.cx-lead.cx,b.cy-lead.cy)/diag;
    return ratio<0.34||(ratio<0.52&&dist>0.30);
  });
}
function pixelateFace(ctx,img,b,w,h){
  const pad=Math.max(b.w,b.h)*0.28;
  const x=Math.max(0,b.x-pad),y=Math.max(0,b.y-pad),rw=Math.min(w-x,b.w+pad*2),rh=Math.min(h-y,b.h+pad*2);
  if(rw<3||rh<3)return;
  const small=document.createElement('canvas'),sw=Math.max(6,Math.round(rw/18)),sh=Math.max(6,Math.round(rh/18));
  small.width=sw;small.height=sh;const sx=small.getContext('2d');sx.imageSmoothingEnabled=true;sx.drawImage(img,x,y,rw,rh,0,0,sw,sh);
  ctx.save();ctx.beginPath();ctx.ellipse(x+rw/2,y+rh/2,rw*.49,rh*.49,0,0,Math.PI*2);ctx.clip();ctx.imageSmoothingEnabled=false;ctx.drawImage(small,0,0,sw,sh,x,y,rw,rh);ctx.restore();ctx.imageSmoothingEnabled=true;
}
async function protect(url){
  if(protectedCache.has(url))return protectedCache.get(url);
  const task=(async()=>{
    const res=await fetch(url,{mode:'cors',cache:'no-store'});if(!res.ok)throw new Error('Bild konnte nicht geladen werden ('+res.status+')');
    const sourceBlob=await res.blob(),img=await imageFromBlob(sourceBlob),w=img.naturalWidth||img.width,h=img.naturalHeight||img.height;
    const faces=await detectFaces(img),blur=backgroundFaces(faces,w,h);
    if(!blur.length)return{blob:sourceBlob,detected:faces.length,protectedCount:0,unchanged:true};
    const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0,w,h);
    blur.forEach(b=>pixelateFace(ctx,img,b,w,h));
    const blob=await new Promise((resolve,reject)=>canvas.toBlob(x=>x?resolve(x):reject(new Error('Bild konnte nicht erstellt werden.')),'image/jpeg',0.94));
    return{blob,detected:faces.length,protectedCount:blur.length,unchanged:false};
  })();
  protectedCache.set(url,task);try{return await task}catch(e){protectedCache.delete(url);throw e}
}
async function blobFor(url,privacy){
  if(privacy)return (await protect(url)).blob;
  const r=await fetch(url,{mode:'cors',cache:'no-store'});if(!r.ok)throw new Error('Bild konnte nicht geladen werden ('+r.status+')');return r.blob();
}
function filename(name='FTS-Selfie.jpg'){return clean(name).replace(/[^a-zA-Z0-9._-]+/g,'-')||'FTS-Selfie.jpg'}
function saveBlob(blob,name){
  const u=URL.createObjectURL(blob),a=document.createElement('a');a.href=u;a.download=filename(name);document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),2500);
}
async function download(url,name,privacy=false){const blob=await blobFor(url,privacy);saveBlob(blob,name);return true}
function canShareFiles(files){try{return !!navigator.share&&(!navigator.canShare||navigator.canShare({files}))}catch{return false}}
async function shareOne({url,name='FTS-Selfie.jpg',text='',privacy=false}){
  const copied=await copyText(text);
  const blob=await blobFor(url,privacy),file=new File([blob],filename(name),{type:blob.type||'image/jpeg'});
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
window.FTS_SOCIAL={shareText,hashtags,copyText,protect,download,shareOne,shareMany,setPreview,blobFor};
})();