/* FTS Printer staff management v72 */
(()=>{
  'use strict';
  const DEVICE_KEY='fts_device_token_v1',LEGACY_CODE_KEY='fts_cockpit_admin_code';
  let mounted=false,users=[],editingId=null;
  const $=(s,r=document)=>r.querySelector(s);
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  const cfg=()=>window.FTS_CONFIG||null;
  const credential=()=>localStorage.getItem(DEVICE_KEY)||localStorage.getItem(LEGACY_CODE_KEY)||'';
  const headers=()=>({'apikey':cfg()?.publishableKey||'','Authorization':'Bearer '+(cfg()?.publishableKey||''),'Content-Type':'application/json'});
  async function rpc(name,body){
    const c=cfg();if(!c)throw new Error('FTS-Konfiguration fehlt.');
    const r=await fetch(c.supabaseUrl+'/rest/v1/rpc/'+name,{method:'POST',headers:headers(),body:JSON.stringify(body)});
    const t=await r.text();let data=null;try{data=t?JSON.parse(t):null}catch{data=t}
    if(!r.ok){const msg=typeof data==='string'?data:(data?.message||data?.hint||('HTTP '+r.status));throw new Error(msg)}
    return data;
  }
  function css(){
    if(document.getElementById('ftsPrinterStaffCss72'))return;
    const s=document.createElement('style');s.id='ftsPrinterStaffCss72';s.textContent=`
.ftsPrinterStaff{border:1px solid rgba(217,181,109,.24);background:#071719;border-radius:18px;padding:14px;color:#f5f1e8}
.ftsPrinterStaff h2,.ftsPrinterStaff h3{margin:0}.ftsPrinterStaffHead{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap}
.ftsPrinterStaffHead p{margin:5px 0 0;color:#91a5a1;font-size:.76rem;line-height:1.45;max-width:760px}.ftsPrinterStaffForm{display:grid;grid-template-columns:minmax(140px,1.3fr) minmax(150px,.9fr) minmax(130px,.8fr) auto;gap:8px;margin-top:13px}
.ftsPrinterStaff input,.ftsPrinterStaff select{width:100%;padding:10px 11px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:#0a2426;color:#fff;font:inherit}
.ftsPrinterStaff button{border:0;border-radius:10px;padding:10px 12px;background:#d9b56d;color:#102020;font-weight:900;cursor:pointer}.ftsPrinterStaff button.secondary{background:#15383a!important;color:#f4f1e8!important;border:1px solid rgba(255,255,255,.09)!important}
.ftsPrinterStaff button.danger{background:#472020!important;color:#ffc1c1!important}.ftsPrinterStaff button:disabled{opacity:.5;cursor:wait}.ftsPrinterStaffActions{display:flex;gap:7px;flex-wrap:wrap;margin-top:9px}
.ftsPrinterStaffList{display:grid;gap:8px;margin-top:13px}.ftsPrinterPerson{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:11px;border-radius:12px;background:#0a2426;border:1px solid rgba(255,255,255,.07)}
.ftsPrinterPerson.off{opacity:.6}.ftsPrinterName{font-weight:950}.ftsPrinterMeta{font-size:.7rem;color:#91a5a1;margin-top:4px;line-height:1.4}.ftsPrinterRole{display:inline-flex;padding:4px 7px;border-radius:999px;font-size:.62rem;font-weight:950;background:#173d40;color:#cde7e4;margin-left:6px}.ftsPrinterRole.admin{background:#594519;color:#ffe49b}
.ftsPrinterEmpty{color:#91a5a1;padding:12px 0;font-size:.78rem}.ftsPrinterHint{margin-top:9px;color:#809793;font-size:.72rem;line-height:1.45}.ftsPrinterEditBanner{margin-top:10px;padding:8px 10px;border-radius:10px;background:#4a371d;color:#ffd787;font-size:.72rem;font-weight:850}
.ftsPrinterAudit{margin-top:13px;border-top:1px solid rgba(255,255,255,.07);padding-top:11px}.ftsPrinterAudit summary{cursor:pointer;font-weight:900;color:#d9b56d}.ftsPrinterAuditRows{display:grid;gap:6px;margin-top:9px}.ftsPrinterAuditRow{display:grid;grid-template-columns:minmax(120px,1fr) 1.2fr auto;gap:8px;padding:8px 9px;border-radius:9px;background:#081d1f;font-size:.68rem;color:#a8b6b3}.ftsPrinterAuditRow b{color:#f2eee6}
@media(max-width:720px){.ftsPrinterStaffForm{grid-template-columns:1fr}.ftsPrinterPerson{grid-template-columns:1fr}.ftsPrinterAuditRow{grid-template-columns:1fr 1fr}.ftsPrinterAuditRow span:last-child{grid-column:1/-1}}
`;document.head.appendChild(s);
  }
  function roleLabel(role){return role==='printer_admin'?'Printer-Administrator':'Mitarbeiter'}
  function dt(v){if(!v)return'noch nie';try{return new Date(v).toLocaleString('de-DE',{dateStyle:'short',timeStyle:'short'})}catch{return String(v)}}
  function host(){return document.getElementById('printerStaffHost')}
  function renderShell(){
    const h=host();if(!h)return;
    h.innerHTML=`<section class="ftsPrinterStaff">
      <div class="ftsPrinterStaffHead"><div><h2>Printer · Mitarbeiter & Zugänge</h2><p>Global für alle Veranstaltungen. Jeder arbeitet in der Printer-App mit seinem eigenen Namen und persönlichen Code. Codes werden nicht lesbar gespeichert.</p></div><button type="button" class="secondary" data-ps-refresh>Aktualisieren</button></div>
      <div id="ftsPrinterEditBanner" class="ftsPrinterEditBanner" hidden></div>
      <div class="ftsPrinterStaffForm">
        <input id="ftsPrinterName" maxlength="80" placeholder="Name, z. B. Marc">
        <select id="ftsPrinterRole"><option value="employee">Mitarbeiter</option><option value="printer_admin">Printer-Administrator</option></select>
        <input id="ftsPrinterCode" type="password" inputmode="numeric" autocomplete="new-password" pattern="[0-9]*" maxlength="12" placeholder="Persönlicher Code">
        <button type="button" id="ftsPrinterSave">Speichern</button>
      </div>
      <div class="ftsPrinterStaffActions"><button type="button" class="secondary" id="ftsPrinterCancel" hidden>Bearbeiten abbrechen</button></div>
      <div class="ftsPrinterHint">Neuer Benutzer: Code mit 4–12 Ziffern eingeben. Beim Bearbeiten darf das Code-Feld leer bleiben; dann bleibt der bisherige Code unverändert. Mitarbeiter sehen später nur den laufenden Printer-Betrieb. Printer-Administratoren erhalten zusätzliche Printer-Verwaltungsrechte, aber keinen Zugriff auf die FTS-Firmenbuchhaltung.</div>
      <div id="ftsPrinterList" class="ftsPrinterStaffList"><div class="ftsPrinterEmpty">Mitarbeiter werden geladen …</div></div>
      <details class="ftsPrinterAudit"><summary>Printer-Aktivität</summary><div id="ftsPrinterAuditRows" class="ftsPrinterAuditRows"><div class="ftsPrinterEmpty">Beim Öffnen werden die letzten Aktivitäten geladen.</div></div></details>
    </section>`;
    $('[data-ps-refresh]',h).onclick=()=>refresh();
    $('#ftsPrinterSave',h).onclick=save;
    $('#ftsPrinterCancel',h).onclick=resetForm;
    $('.ftsPrinterAudit',h).addEventListener('toggle',e=>{if(e.currentTarget.open)loadAudit()});
  }
  function resetForm(){
    editingId=null;const h=host();if(!h)return;
    $('#ftsPrinterName',h).value='';$('#ftsPrinterRole',h).value='employee';$('#ftsPrinterCode',h).value='';
    $('#ftsPrinterCode',h).placeholder='Persönlicher Code';
    $('#ftsPrinterCancel',h).hidden=true;$('#ftsPrinterEditBanner',h).hidden=true;$('#ftsPrinterSave',h).textContent='Speichern';
  }
  function edit(id){
    const u=users.find(x=>String(x.user_id)===String(id));if(!u)return;
    const h=host();editingId=u.user_id;$('#ftsPrinterName',h).value=u.display_name||'';$('#ftsPrinterRole',h).value=u.role||'employee';$('#ftsPrinterCode',h).value='';$('#ftsPrinterCode',h).placeholder='leer = Code behalten';
    $('#ftsPrinterCancel',h).hidden=false;const b=$('#ftsPrinterEditBanner',h);b.hidden=false;b.textContent='Bearbeiten: '+u.display_name+' · '+roleLabel(u.role);$('#ftsPrinterSave',h).textContent='Änderungen speichern';
    h.scrollIntoView({behavior:'smooth',block:'nearest'});
  }
  async function toggle(id){
    const u=users.find(x=>String(x.user_id)===String(id));if(!u)return;
    const verb=u.enabled?'sperren':'wieder aktivieren';
    if(!confirm(u.display_name+' wirklich '+verb+'?'))return;
    try{
      await rpc('fts_admin_save_printer_user_v72',{p_admin_code:credential(),p_user_id:u.user_id,p_display_name:u.display_name,p_role:u.role,p_code:null,p_enabled:!u.enabled});
      await refresh();
    }catch(e){alert('Änderung fehlgeschlagen: '+e.message)}
  }
  async function save(){
    const h=host(),btn=$('#ftsPrinterSave',h),name=$('#ftsPrinterName',h).value.trim(),role=$('#ftsPrinterRole',h).value,code=$('#ftsPrinterCode',h).value.trim();
    if(name.length<2)return alert('Bitte den Namen eintragen.');
    if(!editingId&&!/^[0-9]{4,12}$/.test(code))return alert('Für einen neuen Mitarbeiter einen persönlichen Code mit 4–12 Ziffern eingeben.');
    if(code&&!/^[0-9]{4,12}$/.test(code))return alert('Der persönliche Code muss 4–12 Ziffern haben.');
    btn.disabled=true;
    try{
      await rpc('fts_admin_save_printer_user_v72',{p_admin_code:credential(),p_user_id:editingId||null,p_display_name:name,p_role:role,p_code:code||null,p_enabled:true});
      resetForm();await refresh();
    }catch(e){alert('Mitarbeiter konnte nicht gespeichert werden: '+e.message)}
    finally{btn.disabled=false}
  }
  function renderUsers(){
    const list=$('#ftsPrinterList',host());if(!list)return;
    if(!users.length){list.innerHTML='<div class="ftsPrinterEmpty">Noch keine Printer-Mitarbeiter angelegt.</div>';return}
    list.innerHTML=users.map(u=>`<div class="ftsPrinterPerson ${u.enabled?'':'off'}">
      <div><span class="ftsPrinterName">${esc(u.display_name)}</span><span class="ftsPrinterRole ${u.role==='printer_admin'?'admin':''}">${esc(roleLabel(u.role))}</span>
      <div class="ftsPrinterMeta">${u.enabled?'aktiv':'gesperrt'} · letzte Anmeldung: ${esc(dt(u.last_login_at))} · Code wird niemals angezeigt</div></div>
      <div class="ftsPrinterStaffActions"><button type="button" class="secondary" data-ps-edit="${esc(u.user_id)}">Bearbeiten / Code ändern</button><button type="button" class="${u.enabled?'danger':'secondary'}" data-ps-toggle="${esc(u.user_id)}">${u.enabled?'Sperren':'Aktivieren'}</button></div>
    </div>`).join('');
    list.querySelectorAll('[data-ps-edit]').forEach(b=>b.onclick=()=>edit(b.dataset.psEdit));
    list.querySelectorAll('[data-ps-toggle]').forEach(b=>b.onclick=()=>toggle(b.dataset.psToggle));
  }
  async function refresh(){
    const list=$('#ftsPrinterList',host());if(!credential()){if(list)list.innerHTML='<div class="ftsPrinterEmpty">Cockpit-Gerät zuerst freischalten.</div>';return}
    if(list)list.innerHTML='<div class="ftsPrinterEmpty">Mitarbeiter werden geladen …</div>';
    try{users=await rpc('fts_admin_list_printer_users_v72',{p_admin_code:credential()})||[];renderUsers()}
    catch(e){if(list)list.innerHTML='<div class="ftsPrinterEmpty">Mitarbeiter konnten nicht geladen werden.</div>';console.warn('Printer staff',e)}
  }
  async function loadAudit(){
    const box=$('#ftsPrinterAuditRows',host());if(!box||!credential())return;
    box.innerHTML='<div class="ftsPrinterEmpty">Aktivität wird geladen …</div>';
    try{
      const rows=await rpc('fts_admin_printer_audit_v72',{p_admin_code:credential(),p_limit:40})||[];
      box.innerHTML=rows.length?rows.map(x=>`<div class="ftsPrinterAuditRow"><b>${esc(x.display_name||'Benutzer')}</b><span>${esc(x.action||'')}</span><span>${esc(dt(x.created_at))}</span></div>`).join(''):'<div class="ftsPrinterEmpty">Noch keine Printer-Aktivität.</div>';
    }catch(e){box.innerHTML='<div class="ftsPrinterEmpty">Aktivität konnte nicht geladen werden.</div>'}
  }
  function mount(){
    if(mounted||!host())return;mounted=true;css();renderShell();refresh();
    window.addEventListener('fts:admin-authenticated',()=>refresh());
  }
  window.FTS_PRINTER_STAFF_V72={mount,refresh};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount);else mount();
})();