importScripts('./config.js');
const cfg=self.FTS_CONFIG;
const CACHE='fts-selfie-v16-guest-tablet-20260920';
const CORE=['./','./index.html','./config.js','./manifest.webmanifest','./offline.html','./icon-192.png','./icon-512.png'];

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
  if(u.hostname.endsWith('.supabase.co')){
    event.respondWith((async()=>{
      try{
        const fresh=await fetch(req);
        if(fresh.ok){const cache=await caches.open(CACHE);cache.put(req,fresh.clone()).catch(()=>{});}
        return fresh;
      }catch{
        return (await caches.match(req)) || Response.error();
      }
    })());
    return;
  }
  if(req.mode==='navigate'){
    event.respondWith((async()=>{
      try{
        const fresh=await fetch(req);
        const cache=await caches.open(CACHE);cache.put(req,fresh.clone()).catch(()=>{});
        return fresh;
      }catch{
        return (await caches.match(req)) || (await caches.match('./index.html')) || (await caches.match('./offline.html'));
      }
    })());
    return;
  }
  event.respondWith((async()=>{
    const cached=await caches.match(req);
    if(cached)return cached;
    try{
      const fresh=await fetch(req);
      const cache=await caches.open(CACHE);cache.put(req,fresh.clone()).catch(()=>{});
      return fresh;
    }catch{return Response.error()}
  })());
});

const DB_NAME='fts_selfie_offline_v1',STORE='queue';
function openDB(){
  return new Promise((resolve,reject)=>{
    const req=indexedDB.open(DB_NAME,1);
    req.onupgradeneeded=()=>{const db=req.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:'id'})};
    req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);
  });
}
async function allItems(){
  const db=await openDB();
  return new Promise((resolve,reject)=>{
    const tx=db.transaction(STORE,'readonly'),r=tx.objectStore(STORE).getAll();
    r.onsuccess=()=>resolve(r.result||[]);r.onerror=()=>reject(r.error);
  });
}
async function del(id){
  const db=await openDB();
  return new Promise((resolve,reject)=>{
    const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).delete(id);
    tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);
  });
}
function encPath(p){return p.split('/').map(encodeURIComponent).join('/')}
async function uploadObject(path,blob,type){
  const url=`${cfg.supabaseUrl}/storage/v1/object/${encodeURIComponent(cfg.liveBucket)}/${encPath(path)}`;
  const r=await fetch(url,{method:'POST',headers:{'apikey':cfg.publishableKey,'Authorization':'Bearer '+cfg.publishableKey,'Content-Type':type||'application/octet-stream','x-upsert':'false'},body:blob});
  if(!r.ok){
    const txt=await r.text();
    if(r.status===409 || /already exists/i.test(txt))return;
    throw new Error(txt||`Storage ${r.status}`);
  }
}
async function register(item){
  const r=await fetch(`${cfg.supabaseUrl}/rest/v1/rpc/fts_register_photo_v10`,{
    method:'POST',
    headers:{'apikey':cfg.publishableKey,'Authorization':'Bearer '+cfg.publishableKey,'Content-Type':'application/json'},
    body:JSON.stringify({p_event_token:item.eventToken,p_original_path:item.originalPath,p_designed_path:item.designedPath,p_guest_session_id:item.guestSessionId||null})
  });
  if(!r.ok)throw new Error(await r.text());
}
async function flush(){
  const items=await allItems();
  for(const item of items){
    try{
      await uploadObject(item.originalPath,item.originalBlob,item.originalType);
      await uploadObject(item.designedPath,item.designedBlob,'image/jpeg');
      await register(item);
      await del(item.id);
    }catch(e){
      console.warn('FTS background upload stopped',e);
      throw e;
    }
  }
  const clients=await self.clients.matchAll({includeUncontrolled:true,type:'window'});
  clients.forEach(c=>c.postMessage({type:'FTS_QUEUE_FLUSHED'}));
}
self.addEventListener('sync',event=>{
  if(event.tag==='fts-upload-queue')event.waitUntil(flush());
});
self.addEventListener('message',event=>{
  if(event.data?.type==='FTS_FLUSH_QUEUE')event.waitUntil(flush());
});


// ---------- FTS Admin Push ----------
self.addEventListener('push', event => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : '' };
  }

  const title = data.title || 'FTS Selfie';
  const options = {
    body: data.body || 'Ein neues Eventfoto ist da.',
    icon: './icon-192.png',
    badge: './icon-192.png',
    tag: data.tag || ('fts-photo-' + Date.now()),
    renotify: true,
    data: {
      url: data.url || './dashboard.html'
    }
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();

  event.waitUntil((async () => {
    const target = new URL(
      event.notification?.data?.url || './dashboard.html',
      self.registration.scope
    ).href;

    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    });

    for (const client of windows) {
      if ('focus' in client) {
        try {
          if ('navigate' in client) await client.navigate(target);
        } catch {}
        return client.focus();
      }
    }

    if (self.clients.openWindow) {
      return self.clients.openWindow(target);
    }
  })());
});
