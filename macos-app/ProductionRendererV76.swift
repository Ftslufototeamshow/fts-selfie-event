import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// Native counterpart of fts-photo-engine.js v76 for local SD/WLAN camera files.
// Keeps local camera photos off the public Selfie storage while applying the same
// 10×15 orientation, adaptive crop, banner and studio text rules.

@MainActor
enum ProductionRendererV76 {
    private struct FaceBox {
        var x: CGFloat
        var y: CGFloat       // top-left coordinate system
        var w: CGFloat
        var h: CGFloat
        var right: CGFloat { x + w }
        var bottom: CGFloat { y + h }
    }

    private struct Plan {
        let canvas: NSSize
        let cropTopLeft: NSRect
        let landscape: Bool
        let bannerPct: CGFloat
        let textScale: CGFloat
        let unresolved: Bool
    }

    private static let api = FTSAPI.shared
    private static let ciContext = CIContext(options: [.cacheIntermediates: true])

    static func renderedImage(
        sourceURL: URL,
        event: EventRow,
        cropZoom: CGFloat = 1,
        cropOffsetX: CGFloat = 0,
        cropOffsetY: CGFloat = 0
    ) async throws -> NSImage {
        guard let source = uprightImage(contentsOf: sourceURL) else {
            throw NSError(domain:"FTSPrinter",code:176,userInfo:[NSLocalizedDescriptionKey:"Lokales Foto konnte nicht geöffnet werden."])
        }

        let config = event.studio_config?.object ?? [:]
        let faces = detectFaces(source)
        let plan = buildPlan(
            source:source,config:config,faces:faces,
            cropZoom:cropZoom,cropOffsetX:cropOffsetX,cropOffsetY:cropOffsetY
        )

        let out = NSImage(size: plan.canvas)
        out.lockFocus()
        defer { out.unlockFocus() }

        NSColor.black.setFill()
        NSRect(origin:.zero,size:plan.canvas).fill()
        drawPhoto(source, plan: plan)

        let defaultFilter = config["filters"]?.object?["default"]?.string ?? "natural"
        if defaultFilter != "natural" && defaultFilter != "pumpkin" {
            applyFilter(defaultFilter, image: out)
        }

        if defaultFilter == "pumpkin" {
            drawPumpkinFrame(canvas: plan.canvas)
        }

        let overlay = config["overlay"]?.object ?? [:]
        let banner = overlay["banner"]?.object ?? [:]
        let fullPhoto =
            overlay["enabled"]?.bool == false ||
            banner["enabled"]?.bool == false

        if !fullPhoto {
            try await drawOverlay(event:event,config:config,plan:plan)
            try await drawEventLogos(event:event,canvas:plan.canvas)
            drawEventDecorations(event:event,canvas:plan.canvas)
        }

        return out
    }

    private static func uprightImage(contentsOf url:URL)->NSImage? {
        // Kamera-JPEGs speichern Hochformat oft als Querformat-Pixel plus EXIF-Drehung.
        // Vor Gesichtserkennung, Crop und Druck wird die EXIF-Ausrichtung angewendet.
        if let ci=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]),
           let cg=ciContext.createCGImage(ci,from:ci.extent) {
            return NSImage(cgImage:cg,size:NSSize(width:CGFloat(cg.width),height:CGFloat(cg.height)))
        }
        return NSImage(contentsOf:url)
    }

    // MARK: - v77 adaptive crop

    private static func buildPlan(
        source:NSImage,
        config:[String:JSONValue],
        faces:[FaceBox],
        cropZoom:CGFloat,
        cropOffsetX:CGFloat,
        cropOffsetY:CGFloat
    )->Plan {
        let sw=max(source.size.width,1), sh=max(source.size.height,1), ratio=sw/sh
        let adaptive=config["adaptive"]?.object ?? [:]
        let autoOrientation=adaptive["auto_orientation"]?.bool != false
        let landscape = autoOrientation ? (ratio > 1.04 ? true : (ratio < 0.96 ? false : sw > sh)) : sw > sh
        let canvas=landscape ? NSSize(width:1800,height:1200) : NSSize(width:1200,height:1800)
        let target=canvas.width/canvas.height

        var cw:CGFloat
        var ch:CGFloat
        var cx:CGFloat
        var cy:CGFloat
        if sw/sh > target {
            ch=sh; cw=sh*target; cx=(sw-cw)/2; cy=0
        } else {
            cw=sw; ch=sw/target; cx=0; cy=(sh-ch)/2
        }

        // Fixed FTS banner height: 15 mm. Landscape spans the physical 148 mm
        // paper width; portrait spans the 100 mm width.
        let physicalWidthMM:CGFloat=landscape ? 148.0 : 100.0
        let fixedBannerPx=canvas.width*15.0/physicalWidthMM
        let fixedBannerPct=fixedBannerPx/canvas.height*100.0
        let normal=fixedBannerPct
        let minimum=fixedBannerPct
        let gap=clamp(CGFloat(adaptive["face_gap_pct"]?.double ?? 2.5),1,8)
        let padding=clamp(CGFloat(adaptive["face_padding_ratio"]?.double ?? 0.34),0.12,0.65)
        let adaptiveEnabled=adaptive["enabled"]?.bool != false
        let faceSafe=adaptive["face_safe_area"]?.bool != false
        let autoCrop=adaptive["auto_crop"]?.bool != false

        let union=(adaptiveEnabled && faceSafe) ? unionFaces(faces,pad:padding,sw:sw,sh:sh) : nil

        if var face=union, autoCrop {
            let bottomRatio=face.bottom/sh
            if ch >= sh*0.995 && bottomRatio > 0.72 {
                let zoom=clamp(1+(bottomRatio-0.72)*0.28,1,1.10)
                ch=sh/zoom; cw=ch*target
                if cw>sw { cw=sw; ch=sw/target }
                cx=clamp((sw-cw)/2,0,max(0,sw-cw))
                cy=clamp((sh-ch)/2,0,max(0,sh-ch))
                face = unionFaces(faces,pad:padding,sw:sw,sh:sh) ?? face
            }
            if cw < sw {
                let desired=(face.x+face.right)/2-cw/2
                cx=clamp(desired,0,sw-cw)
            }
            if ch < sh {
                let targetBottom=1-(minimum+gap)/100
                let needed=face.bottom-targetBottom*ch
                let centerDesired=(face.y+face.bottom)/2-ch*0.42
                cy=clamp(max(cy,max(needed,centerDesired)),0,sh-ch)
            }
        }

        // Manual crop adjustment happens after the existing automatic face-safe crop.
        // This keeps the organizer overlay fixed while only the underlying photo crop moves.
        let zoom=clamp(cropZoom,1,1.35)
        if zoom>1.0001 {
            let midX=cx+cw/2,midY=cy+ch/2
            cw=max(1,cw/zoom);ch=max(1,ch/zoom)
            cx=clamp(midX-cw/2,0,max(0,sw-cw))
            cy=clamp(midY-ch/2,0,max(0,sh-ch))
        }
        let ox=clamp(cropOffsetX,-1,1),oy=clamp(cropOffsetY,-1,1)
        if sw>cw+0.5 {
            let room=ox>=0 ? max(0,sw-cw-cx) : max(0,cx)
            cx=clamp(cx+ox*room,0,max(0,sw-cw))
        }
        if sh>ch+0.5 {
            let room=oy>=0 ? max(0,sh-ch-cy) : max(0,cy)
            cy=clamp(cy+oy*room,0,max(0,sh-ch))
        }

        var faceBottom:CGFloat=0
        for b in faces {
            let mapped=FaceBox(
                x:(b.x-cx)*canvas.width/cw,
                y:(b.y-cy)*canvas.height/ch,
                w:b.w*canvas.width/cw,
                h:b.h*canvas.height/ch
            )
            if mapped.w<=2 || mapped.h<=2 { continue }
            let p=max(mapped.w,mapped.h)*padding
            faceBottom=max(faceBottom,(mapped.bottom+p)/canvas.height)
        }

        let bannerPct=normal
        let unresolved=faceBottom>0 && ((1-faceBottom-gap/100)*100 < normal)
        let textScale:CGFloat=1

        return Plan(
            canvas:canvas,
            cropTopLeft:NSRect(x:cx,y:cy,width:cw,height:ch),
            landscape:landscape,
            bannerPct:bannerPct,
            textScale:textScale,
            unresolved:unresolved
        )
    }

    private static func unionFaces(_ boxes:[FaceBox],pad:CGFloat,sw:CGFloat,sh:CGFloat)->FaceBox? {
        guard !boxes.isEmpty else{return nil}
        var x1=CGFloat.greatestFiniteMagnitude,y1=CGFloat.greatestFiniteMagnitude
        var x2:CGFloat=0,y2:CGFloat=0
        var found=false
        for b in boxes where b.w>=2 && b.h>=2 {
            let p=max(b.w,b.h)*pad
            x1=min(x1,b.x-p); y1=min(y1,b.y-p)
            x2=max(x2,b.right+p); y2=max(y2,b.bottom+p)
            found=true
        }
        guard found else{return nil}
        return FaceBox(x:clamp(x1,0,sw),y:clamp(y1,0,sh),
                       w:clamp(x2,0,sw)-clamp(x1,0,sw),
                       h:clamp(y2,0,sh)-clamp(y1,0,sh))
    }

    private static func detectFaces(_ image:NSImage)->[FaceBox] {
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return[]}
        let req=VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage:cg,orientation:.up,options:[:]).perform([req])
            let sw=CGFloat(cg.width),sh=CGFloat(cg.height)
            return (req.results ?? []).map { obs in
                let b=obs.boundingBox
                return FaceBox(
                    x:b.origin.x*sw,
                    y:(1-b.origin.y-b.height)*sh,
                    w:b.width*sw,
                    h:b.height*sh
                )
            }
        } catch {
            return []
        }
    }

    private static func drawPhoto(_ image:NSImage,plan:Plan) {
        let sw=max(image.size.width,1),sh=max(image.size.height,1)
        let c=plan.cropTopLeft
        // NSImage source coordinates are bottom-left; v76 crop math is top-left.
        let from=NSRect(x:c.minX,y:sh-c.minY-c.height,width:c.width,height:c.height)
        image.draw(in:NSRect(origin:.zero,size:plan.canvas),from:from,operation:.copy,fraction:1)
    }

    // MARK: - Filters

    private static func applyFilter(_ key:String,image:NSImage) {
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return}
        var ci=CIImage(cgImage:cg)

        switch key {
        case "warm":
            ci=colorControls(ci,saturation:1.08,brightness:0.025,contrast:1.03)
            let sepia=CIFilter.sepiaTone();sepia.inputImage=ci;sepia.intensity=0.14;ci=sepia.outputImage ?? ci
        case "vivid":
            ci=colorControls(ci,saturation:1.38,brightness:0,contrast:1.10)
        case "cool":
            ci=colorControls(ci,saturation:0.96,brightness:0.03,contrast:1.02)
            ci=colorTemperature(ci,neutral:6500,target:7600)
        case "soft":
            ci=colorControls(ci,saturation:0.90,brightness:0.08,contrast:0.98)
        case "mono":
            ci=colorControls(ci,saturation:0,brightness:0,contrast:1.09)
        case "mono_warm":
            ci=colorControls(ci,saturation:0,brightness:0,contrast:1.05)
            let s=CIFilter.sepiaTone();s.inputImage=ci;s.intensity=0.25;ci=s.outputImage ?? ci
        case "mono_blue":
            ci=colorControls(ci,saturation:0,brightness:0,contrast:1.05)
            ci=colorTemperature(ci,neutral:6500,target:9000)
        case "sepia":
            let s=CIFilter.sepiaTone();s.inputImage=ci;s.intensity=0.72;ci=s.outputImage ?? ci
        case "oldfilm":
            ci=colorControls(ci,saturation:0.70,brightness:0.02,contrast:0.92)
            let s=CIFilter.sepiaTone();s.inputImage=ci;s.intensity=0.32;ci=s.outputImage ?? ci
        case "fade":
            ci=colorControls(ci,saturation:0.70,brightness:0.08,contrast:0.90)
        case "retro90":
            ci=colorControls(ci,saturation:1.18,brightness:0.03,contrast:1.06)
            let s=CIFilter.sepiaTone();s.inputImage=ci;s.intensity=0.16;ci=s.outputImage ?? ci
        case "polaroid":
            ci=colorControls(ci,saturation:0.90,brightness:0.08,contrast:1.0)
            let s=CIFilter.sepiaTone();s.inputImage=ci;s.intensity=0.14;ci=s.outputImage ?? ci
        case "noir":
            ci=colorControls(ci,saturation:0,brightness:0,contrast:1.45)
        case "festival":
            ci=colorControls(ci,saturation:1.55,brightness:0.015,contrast:1.12)
        case "comic_soft":
            ci=colorControls(ci,saturation:1.15,brightness:0,contrast:1.15)
            let p=CIFilter.colorPosterize();p.inputImage=ci;p.levels=7;ci=p.outputImage ?? ci
        case "comic_pop":
            ci=colorControls(ci,saturation:1.60,brightness:0,contrast:1.25)
            let p=CIFilter.colorPosterize();p.inputImage=ci;p.levels=5;ci=p.outputImage ?? ci
        case "sketch":
            ci=colorControls(ci,saturation:0,brightness:0.02,contrast:1.8)
            let p=CIFilter.colorPosterize();p.inputImage=ci;p.levels=4;ci=p.outputImage ?? ci
        default:
            return
        }

        guard let out=ciContext.createCGImage(ci,from:ci.extent) else{return}
        NSImage(cgImage:out,size:image.size).draw(in:NSRect(origin:.zero,size:image.size),from:.zero,operation:.copy,fraction:1)
    }

    private static func colorControls(_ image:CIImage,saturation:Float,brightness:Float,contrast:Float)->CIImage {
        let f=CIFilter.colorControls()
        f.inputImage=image;f.saturation=saturation;f.brightness=brightness;f.contrast=contrast
        return f.outputImage ?? image
    }

    private static func colorTemperature(_ image:CIImage,neutral:CGFloat,target:CGFloat)->CIImage {
        let f=CIFilter.temperatureAndTint()
        f.inputImage=image
        f.neutral=CIVector(x:neutral,y:0)
        f.targetNeutral=CIVector(x:target,y:0)
        return f.outputImage ?? image
    }

    // MARK: - Overlay

    private static func drawOverlay(event:EventRow,config:[String:JSONValue],plan:Plan) async throws {
        let ov=config["overlay"]?.object ?? [:]
        let banner=ov["banner"]?.object ?? [:]
        let w=plan.canvas.width,h=plan.canvas.height
        let heightPct=plan.bannerPct
        let bh=h*heightPct/100
        let visualTextScale=plan.textScale

        let finishedBannerImage:NSImage?
        if let path=nonEmpty(banner["image_path"]?.string) {
            finishedBannerImage=try? await remoteImage(path)
        } else {
            finishedBannerImage=nil
        }

        if let img=finishedBannerImage {
            // Uploaded FTS banners are finished 148×15 mm artwork. Keep the
            // complete design, its text and accent bar at 100% opacity.
            img.draw(
                in:NSRect(x:0,y:0,width:w,height:bh),
                from:.zero,
                operation:.sourceOver,
                fraction:1
            )
        } else {
            let color=NSColor(hex:banner["color"]?.string ?? "#071315")
            let opacity=clamp(CGFloat(banner["opacity"]?.double ?? 0.86),0,1)
            let type=banner["type"]?.string ?? "gradient"

            if type=="solid" {
                color.withAlphaComponent(opacity).setFill()
                NSRect(x:0,y:0,width:w,height:bh).fill()
            } else if let ctx=NSGraphicsContext.current?.cgContext {
                let c0=color.withAlphaComponent(opacity).cgColor
                let c1=color.withAlphaComponent(opacity*0.70).cgColor
                let c2=color.withAlphaComponent(0).cgColor
                if let grad=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[c0,c1,c2] as CFArray,locations:[0,0.72,1]) {
                    ctx.saveGState()
                    ctx.addRect(CGRect(x:0,y:0,width:w,height:bh))
                    ctx.clip()
                    ctx.drawLinearGradient(grad,start:CGPoint(x:0,y:0),end:CGPoint(x:0,y:bh),options:[])
                    ctx.restoreGState()
                }
            }
        }

        let padPct=clamp(CGFloat(ov["padding_pct"]?.double ?? 4.5)/100,0.025,0.10)
        let printSafeInset=max(18,min(w,h)*0.02)
        let pad=max(w*padPct,printSafeInset),maxW=max(1,w-pad*2)
        let safeBottom=printSafeInset
        let safeTop=max(safeBottom+1,bh-printSafeInset)
        let safeHeight=max(1,safeTop-safeBottom)
        let titleRect=NSRect(x:pad,y:safeBottom+safeHeight*0.52,width:maxW,height:safeHeight*0.48)
        let subtitleRect=NSRect(x:pad,y:safeBottom+safeHeight*0.23,width:maxW,height:safeHeight*0.29)
        let lineRect=NSRect(x:pad,y:safeBottom,width:maxW,height:safeHeight*0.23)
        let title=ov["title"]?.object ?? [:]
        let sub=ov["subtitle"]?.object ?? [:]
        let line=ov["line"]?.object ?? [:]
        let titleAlign=title["align"]?.string ?? "left"

        if finishedBannerImage == nil && title["enabled"]?.bool != false {
            drawText(
                textValue(title,event:event,fallback:"title"),
                safeRect:titleRect,
                spec:title,
                fallbackAlign:titleAlign,
                defaultSize:5.8,
                defaultWeight:900,
                defaultColor:"#ffffff",
                textScale:visualTextScale,
                canvas:plan.canvas
            )
        }

        if finishedBannerImage == nil && sub["enabled"]?.bool != false {
            drawText(
                textValue(sub,event:event,fallback:"subtitle"),
                safeRect:subtitleRect,
                spec:sub,
                fallbackAlign:titleAlign,
                defaultSize:3.2,
                defaultWeight:800,
                defaultColor:event.accent ?? "#d9b56d",
                textScale:visualTextScale,
                canvas:plan.canvas
            )
        }

        if finishedBannerImage == nil && line["enabled"]?.bool != false {
            var value=textValue(line,event:event,fallback:"overlay")
            if line["include_date"]?.bool != false {
                let d=eventDayText(event)
                if !d.isEmpty { value=value.isEmpty ? d : value+" · "+d }
            }
            drawText(
                value,
                safeRect:lineRect,
                spec:line,
                fallbackAlign:titleAlign,
                defaultSize:2.1,
                defaultWeight:600,
                defaultColor:"#e8efed",
                textScale:visualTextScale,
                canvas:plan.canvas
            )
        }

        if finishedBannerImage == nil && event.photo_branding != "none" && ov["branding"]?.bool != false {
            let base=min(w,h)
            let brandScale=plan.landscape ? 0.014:0.010
            let font=NSFont.systemFont(ofSize:max(10,base*brandScale*visualTextScale),weight:.semibold)
            let attrs:[NSAttributedString.Key:Any]=[
                .font:font,
                .foregroundColor:NSColor.white.withAlphaComponent(0.68)
            ]
            let s="FTS.lu · Selfie Event" as NSString
            let size=s.size(withAttributes:attrs)
            s.draw(at:NSPoint(x:max(pad,w-pad-size.width),y:printSafeInset),withAttributes:attrs)
        }
    }

    private static func drawText(_ text:String,safeRect:NSRect,spec:[String:JSONValue],fallbackAlign:String,
                                 defaultSize:CGFloat,defaultWeight:Int,defaultColor:String,textScale:CGFloat,
                                 canvas:NSSize) {
        guard !text.isEmpty,safeRect.width>1,safeRect.height>1 else{return}
        let align=spec["align"]?.string ?? fallbackAlign
        let weight=Int(spec["weight"]?.double ?? Double(defaultWeight))
        let fontID=spec["font"]?.string ?? "clean"
        let base=min(canvas.width,canvas.height)
        let start=max(12,CGFloat(spec["size_pct"]?.double ?? Double(defaultSize))*base/100*textScale)
        let minSize=max(10,min(start*0.55,safeRect.height*0.72))
        let shadowEnabled=spec["shadow"]?.bool != false
        let multicolor=spec["multicolor"]?.bool == true
        let colors=(spec["colors"]?.array ?? []).compactMap{$0.string}
        let fallbackColor=spec["color"]?.string ?? defaultColor
        let palette=colors.isEmpty ? [fallbackColor] : colors

        var size=min(start,safeRect.height*0.72)
        while size>minSize {
            let font=fontFor(fontID,size:size,weight:weight)
            let width=(text as NSString).size(withAttributes:[.font:font]).width
            if width<=safeRect.width { break }
            size-=2
        }

        let font=fontFor(fontID,size:size,weight:weight)
        let p=NSMutableParagraphStyle()
        p.alignment = align=="center" ? .center : (align=="right" ? .right:.left)
        let textHeight=min(safeRect.height,max(size*1.30,size+4))
        let rect=NSRect(x:safeRect.minX,y:safeRect.midY-textHeight/2,width:safeRect.width,height:textHeight)
        let shadow=NSShadow()
        shadow.shadowColor=shadowEnabled ? NSColor.black.withAlphaComponent(0.55) : .clear
        shadow.shadowBlurRadius=shadowEnabled ? max(3,canvas.width*0.004):0

        if !multicolor || palette.count<2 {
            let attrs:[NSAttributedString.Key:Any]=[
                .font:font,
                .foregroundColor:NSColor(hex:palette[0]),
                .paragraphStyle:p,
                .shadow:shadow
            ]
            (text as NSString).draw(in:rect,withAttributes:attrs)
            return
        }

        let chars=Array(text)
        let widths=chars.map { (String($0) as NSString).size(withAttributes:[.font:font]).width }
        let total=widths.reduce(0,+)
        var left=align=="center" ? safeRect.midX-total/2 : (align=="right" ? safeRect.maxX-total : safeRect.minX)
        let y=safeRect.midY-size*0.45
        for (i,ch) in chars.enumerated() {
            let attrs:[NSAttributedString.Key:Any]=[
                .font:font,
                .foregroundColor:NSColor(hex:palette[i % palette.count]),
                .shadow:shadow
            ]
            String(ch).draw(at:NSPoint(x:left,y:y),withAttributes:attrs)
            left += widths[i]
        }
    }

    private static func textValue(_ spec:[String:JSONValue],event:EventRow,fallback:String)->String {
        if let t=nonEmpty(spec["text"]?.string){return t}
        let source=spec["source"]?.string ?? fallback
        switch source {
        case "title": return event.event_title
        case "subtitle": return event.subtitle ?? ""
        case "overlay": return event.overlay_text ?? ""
        case "location": return event.location ?? ""
        default: return ""
        }
    }

    private static func fontFor(_ id:String,size:CGFloat,weight:Int)->NSFont {
        let systemWeight:NSFont.Weight = weight>=900 ? .black : weight>=800 ? .heavy : weight>=700 ? .bold : weight>=600 ? .semibold : .regular
        switch id {
        case "bold","rock": return NSFont(name:"Impact",size:size) ?? NSFont.systemFont(ofSize:size,weight:.black)
        case "elegant": return NSFont(name:"Georgia",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "retro": return NSFont(name:"Courier New",size:size) ?? NSFont.monospacedSystemFont(ofSize:size,weight:systemWeight)
        case "pop": return NSFont(name:"Trebuchet MS Bold",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "handwritten": return NSFont(name:"Brush Script MT",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        default: return NSFont.systemFont(ofSize:size,weight:systemWeight)
        }
    }

    // MARK: - Logos and decorations

    private static func drawEventLogos(event:EventRow,canvas:NSSize) async throws {
        let items=(event.logo_items?.array ?? []).compactMap{$0.object}.filter {
            nonEmpty($0["path"]?.string) != nil && $0["show_photo"]?.bool != false
        }
        guard !items.isEmpty else{return}

        var groups:[String:[([String:JSONValue],NSImage)]] = [:]
        for item in items {
            guard let path=nonEmpty(item["path"]?.string),let img=try? await remoteImage(path) else{continue}
            groups[item["position"]?.string ?? "top-right",default:[]].append((item,img))
        }

        let w=canvas.width,h=canvas.height,pad=max(22,max(w*0.035,min(w,h)*0.025)),gap=max(10,w*0.012)
        for (position,arr) in groups {
            var dims:[([String:JSONValue],NSImage,CGFloat,CGFloat)]=[]
            for (item,img) in arr {
                let size=item["size"]?.string ?? "medium"
                let pair = size=="small" ? (CGFloat(0.12),CGFloat(0.075)) : (size=="large" ? (0.26,0.145):(0.18,0.105))
                let maxW=w*pair.0,maxH=h*pair.1
                let scale=min(1,min(maxW/max(img.size.width,1),maxH/max(img.size.height,1)))
                dims.append((item,img,img.size.width*scale,img.size.height*scale))
            }
            let totalW=dims.reduce(0){$0+$1.2}+gap*CGFloat(max(0,dims.count-1))
            let rowH=dims.map{$0.3}.max() ?? 0
            var x=position.contains("center") ? (w-totalW)/2 : (position.contains("right") ? w-pad-totalW:pad)
            let y:CGFloat
            if position.hasPrefix("middle") { y=(h-rowH)/2 }
            else if position.hasPrefix("bottom") { y=pad }
            else { y=h-pad-rowH }

            for d in dims {
                let yy=y+(rowH-d.3)/2
                let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.45);shadow.shadowBlurRadius=max(6,w*0.008);shadow.shadowOffset=NSSize(width:0,height:-max(3,w*0.004))
                NSGraphicsContext.saveGraphicsState();shadow.set()
                d.1.draw(in:NSRect(x:x,y:yy,width:d.2,height:d.3),from:.zero,operation:.sourceOver,fraction:1)
                NSGraphicsContext.restoreGraphicsState()
                x += d.2+gap
            }
        }
    }

    private static func drawEventDecorations(event:EventRow,canvas:NSSize) {
        let items=(event.decoration_items?.array ?? []).compactMap{$0.object}.filter {
            nonEmpty($0["symbol"]?.string) != nil && $0["show_photo"]?.bool != false
        }
        guard !items.isEmpty else{return}
        var groups:[String:[[String:JSONValue]]]=[:]
        for item in items { groups[item["position"]?.string ?? "bottom-right",default:[]].append(item) }

        let w=canvas.width,h=canvas.height,pad=max(24,max(w*0.035,min(w,h)*0.025)),gap=max(8,w*0.01)
        for (position,arr) in groups {
            let dims=arr.map { item -> ([String:JSONValue],CGFloat,CGFloat,CGFloat) in
                let size=item["size"]?.string ?? "medium"
                let px=size=="small" ? max(34,w*0.038) : (size=="large" ? max(70,w*0.078):max(50,w*0.055))
                return (item,px,px*1.25,px*1.25)
            }
            let totalW=dims.reduce(0){$0+$1.2}+gap*CGFloat(max(0,dims.count-1))
            let rowH=dims.map{$0.3}.max() ?? 0
            var x=position.contains("center") ? (w-totalW)/2 : (position.contains("right") ? w-pad-totalW:pad)
            let y:CGFloat
            if position.hasPrefix("middle") { y=(h-rowH)/2 }
            else if position.hasPrefix("bottom") { y=pad }
            else { y=h-pad-rowH }

            for d in dims {
                let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.45);shadow.shadowBlurRadius=max(6,w*0.008)
                let attrs:[NSAttributedString.Key:Any]=[
                    .font:NSFont.systemFont(ofSize:d.1,weight:.bold),
                    .foregroundColor:NSColor.white,
                    .shadow:shadow
                ]
                let s=d.0["symbol"]?.string ?? ""
                let size=(s as NSString).size(withAttributes:attrs)
                (s as NSString).draw(at:NSPoint(x:x+d.2/2-size.width/2,y:y+rowH/2-size.height/2),withAttributes:attrs)
                x += d.2+gap
            }
        }
    }

    private static func remoteImage(_ storagePath:String) async throws -> NSImage {
        let data=try await api.imageData(storagePath:storagePath)
        guard let image=NSImage(data:data) else {
            throw NSError(domain:"FTSPrinter",code:177,userInfo:[NSLocalizedDescriptionKey:"Design-Grafik konnte nicht geladen werden."])
        }
        return image
    }

    private static func drawAspectFill(_ image:NSImage,in rect:NSRect,fraction:CGFloat=1) {
        let iw=max(image.size.width,1),ih=max(image.size.height,1)
        let scale=max(rect.width/iw,rect.height/ih)
        let size=NSSize(width:iw*scale,height:ih*scale)
        let target=NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height)
        image.draw(in:target,from:.zero,operation:.sourceOver,fraction:fraction)
    }

    private static func drawPumpkinFrame(canvas:NSSize) {
        // Native approximation of the v76 pumpkin overlay.
        let w=canvas.width,h=canvas.height,cx=w*0.5,cy=h*0.58,rx=min(w*0.35,h*0.28),ry=rx*0.82
        let orange=NSColor(calibratedRed:0.94,green:0.49,blue:0.10,alpha:0.94)
        let stroke=NSColor(calibratedRed:0.55,green:0.24,blue:0.03,alpha:0.94)
        for dx in [-0.42,-0.2,0,0.2,0.42] {
            let p=NSBezierPath(ovalIn:NSRect(x:cx+rx*CGFloat(dx)-rx*0.47,y:cy-ry,width:rx*0.94,height:ry*2))
            orange.setFill();p.fill();stroke.setStroke();p.lineWidth=max(8,w*0.009);p.stroke()
        }
        let stem=NSBezierPath(roundedRect:NSRect(x:cx-rx*0.07,y:cy+ry*0.82,width:rx*0.14,height:ry*0.33),xRadius:max(4,rx*0.04),yRadius:max(4,rx*0.04))
        NSColor(calibratedRed:0.23,green:0.42,blue:0.15,alpha:1).setFill();stem.fill()
    }

    private static func eventDayText(_ event:EventRow)->String {
        var raw=event.event_date ?? ""
        let today=DateFormatter.ftsISO.string(from:Date())
        if let days=event.event_days?.array?.compactMap({$0.string}),days.contains(today){raw=today}
        let p=raw.split(separator:"-")
        guard p.count==3 else{return ""}
        return "\(p[2]).\(p[1]).\(String(p[0].suffix(2)))"
    }

    private static func nonEmpty(_ s:String?)->String? {
        guard let s=s?.trimmingCharacters(in:.whitespacesAndNewlines),!s.isEmpty else{return nil}
        return s
    }

    private static func clamp(_ v:CGFloat,_ minV:CGFloat,_ maxV:CGFloat)->CGFloat {
        min(max(v,minV),maxV)
    }
}

private extension DateFormatter {
    static let ftsISO: DateFormatter = {
        let f=DateFormatter()
        f.locale=Locale(identifier:"en_US_POSIX")
        f.timeZone=TimeZone(identifier:"Europe/Luxembourg")
        f.dateFormat="yyyy-MM-dd"
        return f
    }()
}
