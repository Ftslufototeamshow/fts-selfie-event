(()=>{
  const page=(location.pathname.split('/').pop()||'index.html').toLowerCase();
  const isGuest=page==='index.html'||page==='';
  const isAdmin=page==='admin.html';
  if(!isGuest&&!isAdmin)return;

  function load(src,marker){
    if(document.querySelector(`script[${marker}]`))return;
    const s=document.createElement('script');s.src=src;s.async=true;s.setAttribute(marker,'1');document.head.appendChild(s);
  }

  // Compatibility shim for older cached config versions.
  // The old v49 guest implementation used a MutationObserver that could trigger
  // itself while moving gallery/ad elements and freeze Chrome on mobile.
  if(isGuest){
    load('./guest-runtime-v52.js?v=53','data-fts-guest-runtime-v52');
    return;
  }

  if(isAdmin){
    load('./admin-social-v52.js?v=53','data-fts-admin-social-v52');
  }
})();
