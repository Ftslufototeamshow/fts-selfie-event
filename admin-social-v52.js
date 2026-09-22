(()=>{
  const page=(location.pathname.split('/').pop()||'').toLowerCase();
  if(page!=='admin.html'||window.__ftsAdminSocialV52)return;
  window.__ftsAdminSocialV52=true;

  const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]||m));
  const detect=url=>{try{const h=new URL(String(url||'').trim()).hostname.toLowerCase();if(h==='facebook.com'||h.endsWith('.facebook.com')||h==='fb.com'||h.endsWith('.fb.com'))return'facebook';if(h==='instagram.com'||h.endsWith('.instagram.com'))return'instagram';if(h==='tiktok.com'||h.endsWith('.tiktok.com'))return'tiktok'}catch{}return''};
  let tries=0;const timer=setInterval(()=>{tries++;if(install()||tries>120)clearInterval(timer)},100);

  function install(){
    if(typeof rpc!=='function'||typeof authCredential!=='function'||typeof persistEventLifecycle!=='function')return false;
    const manager=document.getElementById('galleryLinkManager');if(!manager)return false;
    if(document.getElementById('eventSocialV52'))return true;
    const host=manager.closest('.full')||manager.parentElement,p=document.createElement('div');
    p.id='eventSocialV52';p.style.cssText='margin-top:14px;padding:13px;border:1px solid rgba(217,181,109,.22);border-radius:14px;background:#081d1f';
    p.innerHTML=`<b style="display:block;color:#f0cf83;margin-bottom:5px">Social Media des Veranstalters</b><div class="hint" style="margin-bottom:10px">Maximal drei Buttons. Nur Plattformen mit eingetragenem Link erscheinen auf der Gastseite.</div><div class="grid"><div><label>Facebook</label><input id="eventFacebookV52" type="url" placeholder="Facebook-Link"><div class="hint" id="facebookStatV52"></div></div><div><label>Instagram</label><input id="eventInstagramV52" type="url" placeholder="Instagram-Link"><div class="hint" id="instagramStatV52"></div></div><div class="full"><label>TikTok</label><input id="eventTiktokV52" type="url" placeholder="TikTok-Link"><div class="hint" id="tiktokStatV52"></div></div></div>`;
    host.appendChild(p);
    const f={facebook:document.getElementById('eventFacebookV52'),instagram:document.getElementById('eventInstagramV52'),tiktok:document.getElementById('eventTiktokV52')};
    for(const [name,input] of Object.entries(f))input.addEventListener('change',()=>{const val=input.value.trim(),det=detect(val);if(val&&det&&det!==name){f[det].value=val;input.value='';f[det].focus()}});
    const original=persistEventLifecycle;
    persistEventLifecycle=async function(eventToken){await original(eventToken);await rpc('fts_admin_set_event_social_v49',{p_admin_code:authCredential(),p_event_token:eventToken,p_facebook_url:f.facebook.value.trim(),p_instagram_url:f.instagram.value.trim(),p_tiktok_url:f.tiktok.value.trim()})};
    const edit=typeof EDIT_TOKEN!=='undefined'&&EDIT_TOKEN?EDIT_TOKEN:'';
    if(edit)void(async()=>{try{const rows=await rpc('fts_admin_get_event_social_v49',{p_admin_code:authCredential(),p_event_token:edit})||[],s=Array.isArray(rows)?rows[0]:rows;if(s){f.facebook.value=s.facebook_url||'';f.instagram.value=s.instagram_url||'';f.tiktok.value=s.tiktok_url||''}const stats=await rpc('fts_admin_social_stats_v49',{p_admin_code:authCredential(),p_event_token:edit})||[],m=new Map(stats.map(x=>[String(x.platform),x]));for(const k of Object.keys(f)){const x=m.get(k),el=document.getElementById(k+'StatV52');if(el)el.textContent=x?`${Number(x.click_count||0).toLocaleString('de-DE')} Klicks · ${Number(x.unique_visitors||0).toLocaleString('de-DE')} Besucher`:'Noch keine Klicks erfasst.'}}catch(e){console.warn('Social Media Eventdaten',e)}})();
    return true;
  }
})();
