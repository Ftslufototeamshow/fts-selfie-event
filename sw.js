importScripts('./config.js');
const cfg=self.FTS_CONFIG;
const CACHE='fts-selfie-v64-compact-print-flow-20260923';
const CORE=['./','./index.html','./dashboard.html','./studio.html','./print.html','./config.js','./print-billing-v47.js','./print-billing-v47-fix.js','./print-billing-guest-v54.js','./gallery-links-v48.js','./guest-runtime-v52.js','./dashboard-stats-v49.js','./dashboard-stats-v52.js','./social-share.js','./studio-guest-v56.js','./camera-live-v56.js','./print-pickup-guest-v57.js','./print-pickup-station-v57.js','./manifest.webmanifest','./dashboard.webmanifest','./print.webmanifest','./offline.html','./icon-192.png','./icon-512.png'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const u=new URL(req.url);

  if(u.hostname.endsWith('.supabase.co'))return;

  if(req.mode==='navigate'){
    event.respondWith((async()=>{
      try{const fresh=await fetch(req,{cache:'no-store'});const cache=await caches.open(CACHE);cache.put(req,fresh.clone()).catch(()=>{});return fresh}
      catch{return (await caches.match(req)) || (await caches.match('./index.html')) || (await caches.match('./offline.html'))}
    })());return;
  }
  const runtimeFile=u.origin===self.location.origin && (u.pathname.endsWith('.js') || u.pathname.endsWith('.json') || u.pathname.endsWith('.webmanifest'));
  if(runtimeFile){
    event.respondWith((async()=>{
      try{const fresh=await fetch(req,{cache:'no-store'});if(fresh.ok){const cache=await caches.open(CACHE);cache.put(req,fresh.clone()).catch(()=>{});}return fresh}
      catch{return (await caches.match(req)) || Response.error()}
    })());return;
  }
  event.respondWith((async()=>{
    const cached=await caches.match(req);if(cached)return cached;
    try{const fresh=await fetch(req);const cache=await caches.open(CACHE);cache.put(req,fresh.clone()).catch(()=>{});return fresh}catch{return Response.error()}
  })());
});

const DB_NAME='fts_selfie_offline_v1',STORE='queue';
function openDB(){return new Promise((resolve,reject)=>{const req=indexedDB.open(DB_NAME,1);req.onupgradeneeded=()=>{const db=req.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:'id'})};req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error)})}
async function allItems(){const db=await openDB();return new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readonly'),r=tx.objectStore(STORE).getAll();r.onsuccess=()=>resolve(r.result||[]);r.onerror=()=>reject(r.error)})}
async function del(id){const db=await openDB();return new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).delete(id);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error)})}
function encPath(p){return p.split('/').map(encodeURIComponent).join('/')}
async function uploadObject(path,blob,type){const url=`${cfg.supabaseUrl}/storage/v1/object/${encodeURIComponent(cfg.liveBucket)}/${encPath(path)}`;const r=await fetch(url,{method:'POST',headers:{'apikey':cfg.publishableKey,'Authorization':'Bearer '+cfg.publishableKey,'Content-Type':type||'application/octet-stream','x-upsert':'false'},body:blob});if(!r.ok){const txt=await r.text();if(r.status===409 || /already exists/i.test(txt))return;throw new Error(txt||`Storage ${r.status}`)}}
async function rpcCall(name,body){const r=await fetch(`${cfg.supabaseUrl}/rest/v1/rpc/${name}`,{method:'POST',headers:{'apikey':cfg.publishableKey,'Authorization':'Bearer '+cfg.publishableKey,'Content-Type':'application/json'},body:JSON.stringify(body||{})});if(!r.ok)throw new Error(await r.text());return r}
async function register(item){await rpcCall('fts_register_photo_v60',{p_event_token:item.eventToken,p_original_path:item.originalPath,p_designed_path:item.designedPath,p_publication_designed_path:item.onlinePublicationConsent?item.publicationPath:null,p_guest_session_id:item.guestSessionId||null,p_captured_at:new Date(item.createdAt||Date.now()).toISOString(),p_online_publication_consent:item.onlinePublicationConsent===true,p_people_rights_confirmed:item.onlinePublicationConsent===true&&item.peopleRightsConfirmed===true,p_online_consent_locale:item.onlineConsentLocale||'de'})}
async function persistGuestPrivacy(item){if(!item?.basePrivacyAccepted||!item?.guestSessionId)return;await rpcCall('fts_guest_accept_privacy_v62',{p_event_token:item.eventToken,p_guest_session_id:item.guestSessionId,p_consent_version:item.basePrivacyVersion||'FTS-BASE-PRIVACY-V62-2026-09-23',p_consent_locale:item.basePrivacyLocale||item.onlineConsentLocale||'de'})}
async function reportIssue(item,type,message,error,resolved=false){if(!item?.eventToken)return;try{await fetch(`${cfg.supabaseUrl}/functions/v1/fts-client-issue`,{method:'POST',headers:{'apikey':cfg.publishableKey,'Content-Type':'application/json'},body:JSON.stringify({event_token:item.eventToken,issue_type:type,severity:resolved?'info':'error',message,details:error?{error:String(error).slice(0,500)}:{},session_id:item.guestSessionId||'',issue_key:item.id||'background',resolved})})}catch{}}
async function flush(){const items=await allItems();for(const item of items){try{await persistGuestPrivacy(item);await uploadObject(item.originalPath,item.originalBlob,item.originalType);await uploadObject(item.designedPath,item.designedBlob,'image/jpeg');if(item.onlinePublicationConsent&&item.publicationPath&&item.publicationBlob)await uploadObject(item.publicationPath,item.publicationBlob,'image/jpeg');await register(item);await del(item.id);await reportIssue(item,'background_upload_failed','Hintergrund-Upload wurde erfolgreich nachgeholt.','',true)}catch(e){console.warn('FTS background upload stopped',e);await reportIssue(item,'background_upload_failed','Hintergrund-Upload konnte nicht abgeschlossen werden.',e,false);throw e}}const clients=await self.clients.matchAll({includeUncontrolled:true,type:'window'});clients.forEach(c=>c.postMessage({type:'FTS_QUEUE_FLUSHED'}))}
self.addEventListener('sync',event=>{if(event.tag==='fts-upload-queue')event.waitUntil(flush())});
self.addEventListener('message',event=>{if(event.data?.type==='FTS_FLUSH_QUEUE')event.waitUntil(flush());if(event.data?.type==='FTS_CLEAR_PHOTO_NOTIFICATIONS')event.waitUntil(clearPhotoNotifications(String(event.data?.eventToken||'')))});

self.addEventListener('push', event => {
  let data = {};try {data = event.data ? event.data.json() : {}} catch {data = { body: event.data ? event.data.text() : '' }}
  const title = data.title || 'FTS Selfie';
  const options = {body: data.body || 'Ein neues Eventfoto ist da.',icon: './icon-192.png',badge: './icon-192.png',tag: data.tag || ('fts-photo-' + Date.now()),renotify: true,data: {url: data.url || './dashboard.html',event_token: data.event_token || '',photo_id: data.photo_id || '',print_order_id: data.print_order_id || '',kind: data.kind || ''},actions: data.test ? [] : [{action: data.kind === 'print_ready' ? 'open-print' : 'open-photo',title: data.kind === 'print_ready' ? 'Druckauftrag öffnen' : 'Foto ansehen'}]};
  event.waitUntil(self.registration.showNotification(title, options));
});
async function clearPhotoNotifications(eventToken=''){try{const notes=await self.registration.getNotifications();for(const n of notes){const tag=String(n.tag||''),noteEvent=String(n.data?.event_token||'');const isLegacyPhoto=tag.startsWith('fts-photo-')&&!noteEvent;const isPhoto=isLegacyPhoto||tag.startsWith('fts-event-')||tag.startsWith('fts-photo-')||tag.startsWith('fts-guest-');const sameEvent=!eventToken||isLegacyPhoto||noteEvent===String(eventToken)||tag==='fts-event-'+eventToken;if(isPhoto&&sameEvent)n.close()}}catch{}try{if(self.navigator?.clearAppBadge)await self.navigator.clearAppBadge()}catch{}}
self.addEventListener('notificationclick', event => {const eventToken=String(event.notification?.data?.event_token||'');event.notification.close();event.waitUntil((async () => {await clearPhotoNotifications(eventToken);const target = new URL(event.notification?.data?.url || './dashboard.html',self.registration.scope).href;const windows = await self.clients.matchAll({type: 'window',includeUncontrolled: true});for(const client of windows){if('focus' in client){try{if('navigate' in client)await client.navigate(target)}catch{}return client.focus()}}if(self.clients.openWindow)return self.clients.openWindow(target)})())});