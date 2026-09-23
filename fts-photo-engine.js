/* FTS Selfie Studio v56 – compact guest rendering helpers */
(function(){
  const catalog={
    natural:{cat:'standard',de:'Original',en:'Original',fr:'Original',descDe:'Natürlich',descEn:'Natural',descFr:'Naturel'},
    warm:{cat:'standard',de:'Warm',en:'Warm',fr:'Chaud',descDe:'weicher Hautton',descEn:'softer skin tones',descFr:'tons plus doux'},
    vivid:{cat:'standard',de:'Lebendig',en:'Vivid',fr:'Vif',descDe:'mehr Farbe',descEn:'more colour',descFr:'plus de couleur'},
    cool:{cat:'standard',de:'Kühl',en:'Cool',fr:'Froid',descDe:'moderner Look',descEn:'modern look',descFr:'look moderne'},
    soft:{cat:'standard',de:'Soft',en:'Soft',fr:'Doux',descDe:'weich & hell',descEn:'soft & bright',descFr:'doux & lumineux'},
    mono:{cat:'classic',de:'Schwarz-Weiß',en:'B&W',fr:'Noir & blanc',descDe:'klassisch',descEn:'classic',descFr:'classique'},
    mono_warm:{cat:'classic',de:'B&W Warm',en:'Warm B&W',fr:'N&B chaud',descDe:'warm getönt',descEn:'warm toned',descFr:'ton chaud'},
    mono_blue:{cat:'classic',de:'B&W Blau',en:'Blue B&W',fr:'N&B bleu',descDe:'kühl getönt',descEn:'cool toned',descFr:'ton froid'},
    sepia:{cat:'retro',de:'Sepia',en:'Sepia',fr:'Sépia',descDe:'alte Fotografie',descEn:'old photo',descFr:'photo ancienne'},
    oldfilm:{cat:'retro',de:'Old Film',en:'Old Film',fr:'Vieux film',descDe:'Korn & Filmlook',descEn:'grain & film',descFr:'grain & film'},
    fade:{cat:'retro',de:'Faded',en:'Faded',fr:'Délavé',descDe:'verblasste Farben',descEn:'faded colours',descFr:'couleurs délavées'},
    retro90:{cat:'retro',de:'90er Retro',en:'90s Retro',fr:'Rétro 90',descDe:'Einwegkamera-Look',descEn:'disposable-camera look',descFr:'look appareil jetable'},
    polaroid:{cat:'retro',de:'Polaroid',en:'Polaroid',fr:'Polaroid',descDe:'warm & cremig',descEn:'warm & creamy',descFr:'chaud & crémeux'},
    noir:{cat:'classic',de:'Noir',en:'Noir',fr:'Noir',descDe:'kontrastreich',descEn:'high contrast',descFr:'fort contraste'},
    festival:{cat:'event',de:'Festival Pop',en:'Festival Pop',fr:'Festival Pop',descDe:'knallig & bunt',descEn:'bright & colourful',descFr:'vif & coloré'},
    comic_soft:{cat:'comic',de:'Comic Soft',en:'Comic Soft',fr:'Comic doux',descDe:'sanft gezeichnet',descEn:'soft cartoon',descFr:'dessin doux'},
    comic_pop:{cat:'comic',de:'Comic Pop',en:'Comic Pop',fr:'Comic pop',descDe:'kräftiger Cartoon',descEn:'bold cartoon',descFr:'cartoon intense'},
    sketch:{cat:'comic',de:'Sketch',en:'Sketch',fr:'Croquis',descDe:'Zeichnung',descEn:'drawing',descFr:'dessin'},
    pumpkin:{cat:'event',de:'Kürbis',en:'Pumpkin',fr:'Citrouille',descDe:'Gesicht im Kürbis',descEn:'face in pumpkin',descFr:'visage dans citrouille'}
  };
  const filterInfo={};
  for(const [id,x] of Object.entries(catalog)){
    filterInfo[id]={labelText:{de:x.de,en:x.en,fr:x.fr},descText:{de:x.descDe,en:x.descEn,fr:x.descFr},category:x.cat};
  }

  function clamp(v){return v<0?0:v>255?255:v}
  function q(v,steps){const s=255/(steps-1);return Math.round(v/s)*s}
  function pxFilter(canvas,key){
    if(!canvas)return true;
    if(key==='natural'||key==='pumpkin')return true;
    const c=canvas.getContext('2d',{willReadFrequently:true});
    const im=c.getImageData(0,0,canvas.width,canvas.height),d=im.data;
    for(let i=0;i<d.length;i+=4){
      if(d[i+3]===0)continue;
      let r=d[i],g=d[i+1],b=d[i+2];
      const y=.2126*r+.7152*g+.0722*b;
      switch(key){
        case 'warm': r=y+(r-y)*1.08+9;g=y+(g-y)*1.05+3;b=y+(b-y)*.92-5;break;
        case 'vivid': r=y+(r-y)*1.38;g=y+(g-y)*1.38;b=y+(b-y)*1.38;r=(r-128)*1.10+128;g=(g-128)*1.10+128;b=(b-128)*1.10+128;break;
        case 'cool': r=y+(r-y)*.98-5;g=y+(g-y)*1.02+1;b=y+(b-y)*1.10+10;break;
        case 'soft': r=r*.96+13;g=g*.96+12;b=b*.96+10;break;
        case 'mono': r=g=b=(y-128)*1.10+128;break;
        case 'mono_warm': r=y+14;g=y+7;b=y-5;break;
        case 'mono_blue': r=y-7;g=y+2;b=y+16;break;
        case 'sepia': r=y*1.08+24;g=y*.96+10;b=y*.78;break;
        case 'oldfilm': r=y+(r-y)*.72+18;g=y+(g-y)*.66+10;b=y+(b-y)*.55-4;{const n=((i*17)%23)-11;r+=n;g+=n;b+=n;}break;
        case 'fade': r=y+(r-y)*.70+20;g=y+(g-y)*.70+18;b=y+(b-y)*.70+16;break;
        case 'retro90': r=(r-128)*1.08+140;g=(g-128)*1.02+132;b=(b-128)*.92+118;break;
        case 'polaroid': r=y+(r-y)*.88+18;g=y+(g-y)*.82+12;b=y+(b-y)*.75+5;break;
        case 'noir': {const z=(y-128)*1.45+128;r=g=b=z;}break;
        case 'festival': r=y+(r-y)*1.55+6;g=y+(g-y)*1.48+2;b=y+(b-y)*1.55+8;break;
        case 'comic_soft': r=q((r-128)*1.12+128,7);g=q((g-128)*1.12+128,7);b=q((b-128)*1.12+128,7);break;
        case 'comic_pop': r=q(y+(r-y)*1.55,5);g=q(y+(g-y)*1.55,5);b=q(y+(b-y)*1.55,5);break;
        case 'sketch': {const z=y>170?255:y>110?205:y>60?105:30;r=g=b=z;}break;
        default:return false;
      }
      d[i]=clamp(r);d[i+1]=clamp(g);d[i+2]=clamp(b);
    }
    c.putImageData(im,0,0);return true;
  }

  function filterCss(key){
    return ({
      natural:'none',warm:'saturate(1.08) sepia(.14) contrast(1.03)',vivid:'saturate(1.38) contrast(1.10)',
      cool:'saturate(.96) hue-rotate(10deg) brightness(1.03)',soft:'brightness(1.08) saturate(.9)',
      mono:'grayscale(1) contrast(1.09)',mono_warm:'grayscale(1) sepia(.25)',mono_blue:'grayscale(1) sepia(.18) hue-rotate(160deg)',
      sepia:'sepia(.72) saturate(.78)',oldfilm:'sepia(.32) saturate(.7) contrast(.92)',fade:'saturate(.7) contrast(.9) brightness(1.08)',
      retro90:'sepia(.16) saturate(1.18) contrast(1.06)',polaroid:'sepia(.14) saturate(.9) brightness(1.08)',
      noir:'grayscale(1) contrast(1.45)',festival:'saturate(1.55) contrast(1.12)',comic_soft:'saturate(1.15) contrast(1.15)',
      comic_pop:'saturate(1.6) contrast(1.25)',sketch:'grayscale(1) contrast(1.8)',pumpkin:'saturate(1.08) sepia(.12)'
    })[key]||'none';
  }

  function fontStack(id){
    return ({
      clean:'Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif',
      bold:'"Arial Black",Impact,system-ui,sans-serif',
      rock:'Impact,"Arial Black",system-ui,sans-serif',
      elegant:'Georgia,"Times New Roman",serif',
      retro:'"Courier New",Courier,monospace',
      pop:'"Trebuchet MS","Arial Black",system-ui,sans-serif',
      handwritten:'"Brush Script MT","Segoe Print",cursive'
    })[id]||'system-ui,sans-serif';
  }
  function alpha(hex,a){
    const h=String(hex||'#071315').replace('#','');
    const n=parseInt(h.length===3?h.split('').map(x=>x+x).join(''):h,16);
    if(!Number.isFinite(n))return 'rgba(7,19,21,'+a+')';
    return 'rgba('+((n>>16)&255)+','+((n>>8)&255)+','+(n&255)+','+a+')';
  }
  function cfgOf(ev){return ev?.studio_v56&&typeof ev.studio_v56==='object'?ev.studio_v56:{}}
  function textValue(spec,ev,fallback){
    const custom=String(spec?.text||'').trim();
    if(custom)return custom;
    const src=spec?.source||fallback;
    if(src==='title')return String(ev?.title||'');
    if(src==='subtitle')return String(ev?.subtitle||'');
    if(src==='overlay')return String(ev?.overlay_text||'');
    if(src==='location')return String(ev?.location||'');
    return '';
  }
  function fit(ctx,text,maxWidth,start,min,font){
    let s=start;
    for(;s>min;s-=2){ctx.font=font(s);if(ctx.measureText(text).width<=maxWidth)break}
    return s;
  }
  function drawMulti(ctx,text,x,y,spec,maxWidth){
    if(!text)return;
    const weight=Number(spec?.weight||900),fontId=spec?.font||'clean',scaleBase=Math.min(ctx.canvas.width,ctx.canvas.height);
    const scale=Math.max(.52,Math.min(1,Number(spec?._scale||1)));
    const start=Math.max(12,Number(spec?.size_pct||5.8)*scaleBase/100*scale);
    const min=Math.max(11,start*.55);
    const size=fit(ctx,text,maxWidth,start,min,s=>weight+' '+s+'px '+fontStack(fontId));
    ctx.font=weight+' '+size+'px '+fontStack(fontId);
    ctx.textBaseline='alphabetic';ctx.textAlign=spec?.align||'left';
    ctx.shadowColor=spec?.shadow===false?'transparent':'rgba(0,0,0,.55)';ctx.shadowBlur=spec?.shadow===false?0:Math.max(3,ctx.canvas.width*.004);
    const colors=Array.isArray(spec?.colors)&&spec.colors.length?spec.colors:[spec?.color||'#ffffff'];
    if(!spec?.multicolor||colors.length<2){ctx.fillStyle=colors[0];ctx.fillText(text,x,y,maxWidth);return}
    const chars=[...text],widths=chars.map(ch=>ctx.measureText(ch).width),total=widths.reduce((a,b)=>a+b,0);
    let left=x;if(ctx.textAlign==='center')left=x-total/2;else if(ctx.textAlign==='right')left=x-total;
    ctx.textAlign='left';
    chars.forEach((ch,i)=>{ctx.fillStyle=colors[i%colors.length];ctx.fillText(ch,left,y);left+=widths[i]});
  }

  function pumpkinFrame(ctx,w,h){
    const layer=document.createElement('canvas');layer.width=w;layer.height=h;
    const p=layer.getContext('2d'),cx=w*.5,cy=h*.42,rx=Math.min(w*.35,h*.28),ry=rx*.82;
    p.globalAlpha=.94;
    p.fillStyle='#ef7d1a';p.strokeStyle='#8b3d08';p.lineWidth=Math.max(8,w*.009);
    for(const dx of [-.42,-.2,0,.2,.42]){
      p.beginPath();p.ellipse(cx+rx*dx,cy,rx*.47,ry,0,0,Math.PI*2);p.fill();p.stroke();
    }
    p.globalCompositeOperation='destination-out';
    p.beginPath();p.ellipse(cx,cy,rx*.55,ry*.60,0,0,Math.PI*2);p.fill();
    p.globalCompositeOperation='source-over';
    p.fillStyle='#3b6b27';p.beginPath();p.roundRect(cx-rx*.07,cy-ry*1.15,rx*.14,ry*.33,Math.max(4,rx*.04));p.fill();
    ctx.drawImage(layer,0,0);
  }

  function clampNum(v,min,max){return Math.min(max,Math.max(min,Number(v)||0))}
  function adaptiveDefaults(){
    return {
      enabled:true,auto_orientation:true,auto_crop:true,face_safe_area:true,
      face_padding_ratio:.34,face_gap_pct:2.5,min_text_scale:.68,
      portrait:{banner_max_pct:18,banner_min_pct:12},
      landscape:{banner_max_pct:22,banner_min_pct:14},
      print:{ratio:'10x15',bleed_pct:1.5}
    };
  }
  function adaptiveConfig(config){
    const d=adaptiveDefaults(),a=config?.adaptive&&typeof config.adaptive==='object'?config.adaptive:{};
    return {...d,...a,portrait:{...d.portrait,...(a.portrait||{})},landscape:{...d.landscape,...(a.landscape||{})},print:{...d.print,...(a.print||{})}};
  }
  function sourceOrientation(img,selectedLayout,config){
    const a=adaptiveConfig(config),w=Math.max(1,img?.naturalWidth||img?.width||1),h=Math.max(1,img?.naturalHeight||img?.height||1),ratio=w/h;
    if(a.enabled!==false&&a.auto_orientation!==false){
      if(ratio>1.04)return'landscape';
      if(ratio<.96)return'portrait';
    }
    return String(selectedLayout||'').includes('wide')?'landscape':'portrait';
  }
  function outputSpec(img,selectedLayout,config){
    const orientation=sourceOrientation(img,selectedLayout,config);
    return orientation==='landscape'?{w:1800,h:1200,orientation}:{w:1200,h:1800,orientation};
  }
  function unionBoxes(boxes,padRatio,w,h){
    if(!Array.isArray(boxes)||!boxes.length)return null;
    let x1=Infinity,y1=Infinity,x2=-Infinity,y2=-Infinity;
    for(const b of boxes){
      if(!b)continue;
      const bw=Math.max(0,Number(b.w??b.width)||0),bh=Math.max(0,Number(b.h??b.height)||0);
      if(bw<2||bh<2)continue;
      const pad=Math.max(bw,bh)*padRatio,bx=Number(b.x)||0,by=Number(b.y)||0;
      x1=Math.min(x1,bx-pad);y1=Math.min(y1,by-pad);x2=Math.max(x2,bx+bw+pad);y2=Math.max(y2,by+bh+pad);
    }
    if(!Number.isFinite(x1))return null;
    return{x:clampNum(x1,0,w),y:clampNum(y1,0,h),right:clampNum(x2,0,w),bottom:clampNum(y2,0,h)};
  }
  function buildPlan(img,selectedLayout,config,faces=[]){
    const sw=Math.max(1,img?.naturalWidth||img?.width||1),sh=Math.max(1,img?.naturalHeight||img?.height||1);
    const out=outputSpec(img,selectedLayout,config),tw=out.w,th=out.h,target=tw/th,source=sw/sh,a=adaptiveConfig(config);
    let cw,ch,cx,cy;
    if(source>target){ch=sh;cw=sh*target;cx=(sw-cw)/2;cy=0}
    else{cw=sw;ch=sw/target;cx=0;cy=(sh-ch)/2}
    const mode=out.orientation==='landscape'?a.landscape:a.portrait;
    const normal=clampNum(mode.banner_max_pct,out.orientation==='landscape'?14:12,out.orientation==='landscape'?26:22);
    const minimum=clampNum(mode.banner_min_pct,10,normal);
    const gap=clampNum(a.face_gap_pct,1,8);
    const faceUnion=a.enabled!==false&&a.face_safe_area!==false?unionBoxes(faces,clampNum(a.face_padding_ratio,.12,.65),sw,sh):null;
    if(faceUnion&&a.auto_crop!==false){
      // Wenn das Ausgangsformat vertikal keinen Beschnittsspielraum bietet und ein Gesicht tief sitzt,
      // schaffen wir mit einem sehr kleinen kontrollierten Zoom Platz zum Hochschieben.
      const bottomRatio=faceUnion.bottom/sh;
      if(ch>=sh*.995&&bottomRatio>.72){
        const zoom=clampNum(1+(bottomRatio-.72)*.28,1,1.10);
        ch=sh/zoom;cw=ch*target;
        if(cw>sw){cw=sw;ch=sw/target}
        cx=clampNum((sw-cw)/2,0,Math.max(0,sw-cw));
        cy=clampNum((sh-ch)/2,0,Math.max(0,sh-ch));
      }
      if(cw<sw){const desired=(faceUnion.x+faceUnion.right)/2-cw/2;cx=clampNum(desired,0,sw-cw)}
      if(ch<sh){
        const targetBottom=1-(minimum+gap)/100;
        const needed=faceUnion.bottom-targetBottom*ch;
        const centerDesired=(faceUnion.y+faceUnion.bottom)/2-ch*.42;
        cy=clampNum(Math.max(cy,needed,centerDesired),0,sh-ch);
      }
    }
    const mapped=(faces||[]).map(b=>({
      x:((Number(b.x)||0)-cx)*tw/cw,y:((Number(b.y)||0)-cy)*th/ch,
      w:(Number(b.w??b.width)||0)*tw/cw,h:(Number(b.h??b.height)||0)*th/ch
    })).filter(b=>b.w>2&&b.h>2&&b.x+b.w>0&&b.y+b.h>0&&b.x<tw&&b.y<th);
    let faceBottom=0;
    for(const b of mapped){const pad=Math.max(b.w,b.h)*clampNum(a.face_padding_ratio,.12,.65);faceBottom=Math.max(faceBottom,(b.y+b.h+pad)/th)}
    let bannerPct=normal,unresolved=false;
    if(faceBottom>0){
      const available=(1-faceBottom-gap/100)*100;
      if(available<normal)bannerPct=Math.max(minimum,available);
      unresolved=available<minimum;
    }
    bannerPct=clampNum(bannerPct,minimum,normal);
    const minScale=clampNum(a.min_text_scale,.52,.92),textScale=clampNum((bannerPct/Math.max(normal,1))*.98,minScale,1);
    return{w:tw,h:th,orientation:out.orientation,crop:{x:cx,y:cy,w:cw,h:ch},faces:mapped,
      adaptive:{enabled:a.enabled!==false,bannerPct,normalBannerPct:normal,minimumBannerPct:minimum,textScale,faceCount:mapped.length,unresolved,faceBottomRatio:faceBottom,gapPct:gap}};
  }
  function drawPhoto(ctx,img,plan){
    const p=plan?.crop;if(!p){ctx.drawImage(img,0,0,ctx.canvas.width,ctx.canvas.height);return}
    ctx.drawImage(img,p.x,p.y,p.w,p.h,0,0,ctx.canvas.width,ctx.canvas.height);
  }

  async function drawOverlay(ctx,canvas,ev,config,helpers={}){
    const conf=config&&Object.keys(config).length?config:cfgOf(ev),ov=conf.overlay||{},w=canvas.width,h=canvas.height;
    if(helpers.selectedFilter==='pumpkin')pumpkinFrame(ctx,w,h);
    if(ov.enabled===false){
      if(helpers.drawEventLogos)await helpers.drawEventLogos(ctx,w,h,'photo');
      if(helpers.drawEventDecorations)await Promise.resolve(helpers.drawEventDecorations(ctx,w,h,'photo'));
      return;
    }
    const a=adaptiveConfig(conf),orientation=helpers.adaptiveState?.orientation||(w>h?'landscape':'portrait'),mode=orientation==='landscape'?a.landscape:a.portrait;
    const banner=ov.banner||{},requestedHeight=clampNum(banner.height_pct||30,12,48);
    const normalCap=clampNum(mode.banner_max_pct,orientation==='landscape'?14:12,orientation==='landscape'?26:22),minimum=clampNum(mode.banner_min_pct,10,normalCap);
    const automatic=a.enabled!==false,adaptiveHeight=helpers.adaptiveState?.bannerPct;
    const heightPct=automatic?clampNum(Number.isFinite(Number(adaptiveHeight))?adaptiveHeight:Math.min(requestedHeight,normalCap),minimum,normalCap):requestedHeight;
    const textScale=automatic?clampNum(helpers.adaptiveState?.textScale??1,clampNum(a.min_text_scale,.52,.92),1):1;
    const bh=h*heightPct/100,by=h-bh;
    if(banner.enabled!==false){
      const type=banner.type||'gradient',op=Math.max(0,Math.min(1,Number(banner.opacity??.86))),color=banner.color||'#071315';
      if(type==='solid'){ctx.fillStyle=alpha(color,op);ctx.fillRect(0,by,w,bh)}
      else{const g=ctx.createLinearGradient(0,by,0,h);g.addColorStop(0,alpha(color,0));g.addColorStop(.28,alpha(color,op*.7));g.addColorStop(1,alpha(color,op));ctx.fillStyle=g;ctx.fillRect(0,by,w,bh)}
      if(banner.image_path&&helpers.assetUrl&&helpers.loadRemoteImage){
        const img=await helpers.loadRemoteImage(helpers.assetUrl(banner.image_path));
        if(img){ctx.save();ctx.globalAlpha=Math.max(0,Math.min(1,Number(banner.image_opacity??.35)));const s=Math.max(w/img.naturalWidth,bh/img.naturalHeight),dw=img.naturalWidth*s,dh=img.naturalHeight*s;ctx.drawImage(img,(w-dw)/2,by+(bh-dh)/2,dw,dh);ctx.restore()}
      }
    }
    const pad=w*Math.max(.025,Math.min(.10,Number(ov.padding_pct||4.5)/100)),maxW=w-pad*2,title=ov.title||{},sub=ov.subtitle||{},line=ov.line||{};
    const align=title.align||'left',x=align==='center'?w/2:align==='right'?w-pad:pad,titleY=by+bh*.40,subY=by+bh*.67,lineY=by+bh*.87;
    if(title.enabled!==false)drawMulti(ctx,textValue(title,ev,'title'),x,titleY,{...title,_scale:textScale},maxW);
    if(sub.enabled!==false){const aa=sub.align||align,xx=aa==='center'?w/2:aa==='right'?w-pad:pad;drawMulti(ctx,textValue(sub,ev,'subtitle'),xx,subY,{...sub,align:aa,size_pct:sub.size_pct||3.2,weight:sub.weight||800,color:sub.color||ev.accent||'#d9b56d',_scale:textScale},maxW)}
    if(line.enabled!==false){
      let txt=textValue(line,ev,'overlay');if(line.include_date!==false&&helpers.photoEventDayText){const d=helpers.photoEventDayText();if(d)txt=txt?txt+' · '+d:d}
      const aa=line.align||align,xx=aa==='center'?w/2:aa==='right'?w-pad:pad;drawMulti(ctx,txt,xx,lineY,{...line,align:aa,size_pct:line.size_pct||2.1,weight:line.weight||600,color:line.color||'#e8efed',_scale:textScale},maxW);
    }
    if((ev?.photo_branding||'bottom')!=='none'&&ov.branding!==false){ctx.save();ctx.textAlign='right';ctx.textBaseline='alphabetic';ctx.fillStyle='rgba(255,255,255,.68)';const base=Math.min(w,h);ctx.font='600 '+Math.max(11,base*.014*textScale)+'px system-ui';ctx.fillText('FTS.lu · Selfie Event',w-pad,h-Math.max(11,h*.012));ctx.restore()}
    if(helpers.drawEventLogos)await helpers.drawEventLogos(ctx,w,h,'photo');
    if(helpers.drawEventDecorations)await Promise.resolve(helpers.drawEventDecorations(ctx,w,h,'photo'));
  }

  window.FTS_PHOTO_ENGINE={version:76,catalog,filterInfo,applyFilter:pxFilter,filterCss,drawOverlay,fontStack,pumpkinFrame,adaptiveDefaults,adaptiveConfig,sourceOrientation,outputSpec,buildPlan,drawPhoto};
})();