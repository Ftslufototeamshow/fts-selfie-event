const CACHE='fts-printer-admin-v127';
const CORE=['./','./index.html','./manifest.webmanifest','../config.js','../icon-192.png','../icon-512.png'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(k=>k.startsWith('fts-printer-admin-')&&k!==CACHE).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const u=new URL(req.url);
  if(u.hostname.endsWith('.supabase.co'))return;

  if(req.mode==='navigate'){
    event.respondWith((async()=>{
      try{
        const fresh=await fetch(req,{cache:'no-store'});
        const cache=await caches.open(CACHE);
        cache.put('./index.html',fresh.clone()).catch(()=>{});
        return fresh;
      }catch{
        return (await caches.match('./index.html')) || Response.error();
      }
    })());
    return;
  }

  event.respondWith((async()=>{
    try{
      const fresh=await fetch(req,{cache:'no-store'});
      if(fresh.ok){
        const cache=await caches.open(CACHE);
        cache.put(req,fresh.clone()).catch(()=>{});
      }
      return fresh;
    }catch{
      return (await caches.match(req)) || Response.error();
    }
  })());
});

self.addEventListener('push',event=>{
  let data={};
  try{data=event.data?event.data.json():{}}
  catch{data={body:event.data?event.data.text():''}}

  const issueId=String(data.photo_id||'');
  const eventToken=String(data.event_token||'');
  const kind=String(data.kind||'');
  const isReply=kind==='printer_issue_reply';
  const title=isReply?'FTS Druckproblem · Rückmeldung':'FTS Druckproblem · Freigabe nötig';
  const target='./?event='+encodeURIComponent(eventToken)+'&issue='+encodeURIComponent(issueId);
  const options={
    body:String(data.body||data.title||'Druckproblem wurde gemeldet.'),
    icon:'../icon-192.png',
    badge:'../icon-192.png',
    tag:'fts-printer-admin-'+(issueId||Date.now()),
    renotify:true,
    data:{url:target,event_token:eventToken,issue_id:issueId,kind},
    actions:[{action:'open-printer-admin',title:'Problem öffnen'}]
  };
  event.waitUntil(self.registration.showNotification(title,options));
});

self.addEventListener('notificationclick',event=>{
  event.notification.close();
  event.waitUntil((async()=>{
    const target=new URL(event.notification?.data?.url||'./',self.registration.scope).href;
    const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    for(const client of windows){
      if('focus' in client){
        try{if('navigate' in client)await client.navigate(target)}catch{}
        return client.focus();
      }
    }
    if(self.clients.openWindow)return self.clients.openWindow(target);
  })());
});
