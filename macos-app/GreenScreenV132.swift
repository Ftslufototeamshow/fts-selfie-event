import SwiftUI
import AppKit
import Foundation
import Vision
import CoreImage

enum FTSPhotoEffect: String, Codable, Hashable, CaseIterable {
    case normal
    case mono
    case oldschool
    case film
    case warm
    case vivid
    case cool
    case soft
    case monoWarm
    case monoBlue
    case sepia
    case comic

    var label:String {
        switch self {
        case .normal: return "Normal"
        case .mono: return "Schwarz-Weiß"
        case .oldschool: return "Oldschool"
        case .film: return "Film-Look"
        case .warm: return "Warm"
        case .vivid: return "Kräftig"
        case .cool: return "Kühl"
        case .soft: return "Soft"
        case .monoWarm: return "S/W warm"
        case .monoBlue: return "S/W kühl"
        case .sepia: return "Sepia"
        case .comic: return "Comic · Person"
        }
    }
}

enum FTSGreenBackgroundMode: String, Codable, Hashable, CaseIterable {
    case color
    case image
    case comicBurst
    case fireworks

    var label:String {
        switch self {
        case .color: return "Farbe"
        case .image: return "Bild"
        case .comicBurst: return "Comic-Burst"
        case .fireworks: return "Feuerwerk"
        }
    }
}

struct FTSGreenScreenSettings: Codable, Hashable {
    var enabled=false
    var backgroundMode:FTSGreenBackgroundMode = .color
    var backgroundColorHex="#1A73E8"
    var backgroundImagePath:String?=nil
    var edgeSoftness:Double=5.0

    var signature:String {
        [
            enabled ? "1":"0",
            backgroundMode.rawValue,
            backgroundColorHex.uppercased(),
            backgroundImagePath ?? "",
            String(format:"%.2f",edgeSoftness)
        ].joined(separator:"|")
    }
}

enum FTSGreenScreenStore {
    private static func key(_ eventToken:String)->String {
        "fts.green.screen.v132.\(eventToken)"
    }

    static func settings(eventToken:String)->FTSGreenScreenSettings {
        guard let data=UserDefaults.standard.data(forKey:key(eventToken)),
              let value=try? JSONDecoder().decode(FTSGreenScreenSettings.self,from:data) else {
            return FTSGreenScreenSettings()
        }
        return value
    }

    static func save(_ value:FTSGreenScreenSettings,eventToken:String) {
        guard let data=try? JSONEncoder().encode(value) else{return}
        UserDefaults.standard.set(data,forKey:key(eventToken))
    }

    static func copyBackground(_ source:URL,activation:V80MediaActivation)throws->URL {
        let fm=FileManager.default
        let eventRoot=URL(fileURLWithPath:activation.folderPath,isDirectory:true).deletingLastPathComponent()
        let folder=eventRoot.appendingPathComponent("Green Screen Hintergründe",isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let ext=source.pathExtension.isEmpty ? "jpg":source.pathExtension
        let base=source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of:"/",with:"-")
            .replacingOccurrences(of:":",with:"-")
        var dest=folder.appendingPathComponent("\(base).\(ext)")
        var i=2
        while fm.fileExists(atPath:dest.path) {
            dest=folder.appendingPathComponent("\(base)-\(i).\(ext)")
            i += 1
        }
        try fm.copyItem(at:source,to:dest)
        return dest
    }

    static func removeBackgroundCopy(_ path:String?,activation:V80MediaActivation) {
        guard let path,!path.isEmpty else{return}
        let fm=FileManager.default
        let eventRoot=URL(fileURLWithPath:activation.folderPath,isDirectory:true).deletingLastPathComponent()
        let folder=eventRoot.appendingPathComponent("Green Screen Hintergründe",isDirectory:true).standardizedFileURL
        let file=URL(fileURLWithPath:path).standardizedFileURL
        let prefix=folder.path.hasSuffix("/") ? folder.path : folder.path+"/"
        guard file.path.hasPrefix(prefix) else{return}
        try? fm.removeItem(at:file)
    }
}

@MainActor
enum FTSPhotoEffectsV132 {
    private static let ciContext=CIContext(options:[.cacheIntermediates:true])
    private static let personMaskCache:NSCache<NSString,CIImage> = {
        let cache=NSCache<NSString,CIImage>()
        cache.countLimit=80
        cache.totalCostLimit=128*1024*1024
        return cache
    }()

    static func clearTransientCache() {
        personMaskCache.removeAllObjects()
    }

    static func processedImage(
        source:NSImage,
        event:EventRow,
        effect:FTSPhotoEffect,
        greenScreenSettings:FTSGreenScreenSettings?=nil,
        cacheKey:String?=nil
    )->NSImage {
        let green=greenScreenSettings ?? FTSGreenScreenStore.settings(eventToken:event.event_token)
        if effect == .normal && !green.enabled { return source }
        guard let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return source}

        let original=CIImage(cgImage:cg)
        let extent=original.extent
        var result=original
        let needsPersonMask = green.enabled || effect == .comic
        let mask = needsPersonMask
            ? personMask(cgImage:cg,extent:extent,softness:green.edgeSoftness,cacheKey:cacheKey)
            : nil

        if effect == .comic {
            let comic=comicImage(original)
            if let mask {
                let background = green.enabled ? backgroundImage(settings:green,extent:extent) : original
                result=blend(foreground:comic,background:background,mask:mask) ?? comic
            } else {
                result=comic
            }
        } else {
            if green.enabled,let mask {
                let background=backgroundImage(settings:green,extent:extent)
                result=blend(foreground:original,background:background,mask:mask) ?? original
            }
            result=apply(effect:effect,to:result)
        }

        guard let out=ciContext.createCGImage(result,from:extent) else{return source}
        return NSImage(cgImage:out,size:source.size)
    }

    private static func personMask(cgImage:CGImage,extent:CGRect,softness:Double,cacheKey:String?)->CIImage? {
        let key=cacheKey.map{
            "\($0)|\(cgImage.width)x\(cgImage.height)|\(String(format:"%.2f",softness))" as NSString
        }
        if let key,let cached=personMaskCache.object(forKey:key) { return cached }

        let request=VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(cgImage:cgImage,orientation:.up,options:[:]).perform([request])
            guard let observation=request.results?.first else{return nil}
            var mask=CIImage(cvPixelBuffer:observation.pixelBuffer)
            let sx=extent.width/max(mask.extent.width,1)
            let sy=extent.height/max(mask.extent.height,1)
            mask=mask.transformed(by:CGAffineTransform(scaleX:sx,y:sy)).cropped(to:extent)
            if softness>0.1,
               let blur=CIFilter(name:"CIGaussianBlur",parameters:[
                    kCIInputImageKey:mask,
                    kCIInputRadiusKey:max(0,min(18,softness))
               ])?.outputImage {
                mask=blur.cropped(to:extent)
            }
            if let key {
                personMaskCache.setObject(mask,forKey:key,cost:max(1,cgImage.width*cgImage.height/8))
            }
            return mask
        } catch {
            return nil
        }
    }

    private static func blend(foreground:CIImage,background:CIImage,mask:CIImage)->CIImage? {
        CIFilter(name:"CIBlendWithMask",parameters:[
            kCIInputImageKey:foreground,
            kCIInputBackgroundImageKey:background,
            "inputMaskImage":mask
        ])?.outputImage
    }

    private static func comicImage(_ image:CIImage)->CIImage {
        CIFilter(name:"CIComicEffect",parameters:[kCIInputImageKey:image])?.outputImage ?? image
    }

    private static func apply(effect:FTSPhotoEffect,to image:CIImage)->CIImage {
        switch effect {
        case .normal,.comic:
            return image
        case .mono:
            return colorControls(image,saturation:0,brightness:0,contrast:1.10)
        case .oldschool:
            let base=colorControls(image,saturation:0.82,brightness:0.015,contrast:1.08)
            let sep=CIFilter(name:"CISepiaTone",parameters:[kCIInputImageKey:base,kCIInputIntensityKey:0.38])?.outputImage ?? base
            return vignette(sep,intensity:0.65,radius:1.35)
        case .film:
            let base=colorControls(image,saturation:0.92,brightness:0.01,contrast:1.12)
            return vignette(base,intensity:0.78,radius:1.55)
        case .warm:
            let base=colorControls(image,saturation:1.08,brightness:0.025,contrast:1.03)
            return CIFilter(name:"CISepiaTone",parameters:[kCIInputImageKey:base,kCIInputIntensityKey:0.14])?.outputImage ?? base
        case .vivid:
            return colorControls(image,saturation:1.38,brightness:0,contrast:1.10)
        case .cool:
            let base=colorControls(image,saturation:0.96,brightness:0.03,contrast:1.02)
            return temperature(base,neutral:6500,target:7600)
        case .soft:
            return colorControls(image,saturation:0.90,brightness:0.08,contrast:0.98)
        case .monoWarm:
            let base=colorControls(image,saturation:0,brightness:0,contrast:1.05)
            return CIFilter(name:"CISepiaTone",parameters:[kCIInputImageKey:base,kCIInputIntensityKey:0.25])?.outputImage ?? base
        case .monoBlue:
            return temperature(colorControls(image,saturation:0,brightness:0,contrast:1.05),neutral:6500,target:9000)
        case .sepia:
            return CIFilter(name:"CISepiaTone",parameters:[kCIInputImageKey:image,kCIInputIntensityKey:0.72])?.outputImage ?? image
        }
    }

    private static func colorControls(_ image:CIImage,saturation:Double,brightness:Double,contrast:Double)->CIImage {
        CIFilter(name:"CIColorControls",parameters:[
            kCIInputImageKey:image,
            kCIInputSaturationKey:saturation,
            kCIInputBrightnessKey:brightness,
            kCIInputContrastKey:contrast
        ])?.outputImage ?? image
    }

    private static func temperature(_ image:CIImage,neutral:CGFloat,target:CGFloat)->CIImage {
        CIFilter(name:"CITemperatureAndTint",parameters:[
            kCIInputImageKey:image,
            "inputNeutral":CIVector(x:neutral,y:0),
            "inputTargetNeutral":CIVector(x:target,y:0)
        ])?.outputImage ?? image
    }

    private static func vignette(_ image:CIImage,intensity:Double,radius:Double)->CIImage {
        CIFilter(name:"CIVignette",parameters:[
            kCIInputImageKey:image,
            kCIInputIntensityKey:intensity,
            kCIInputRadiusKey:radius
        ])?.outputImage ?? image
    }

    private static func backgroundImage(settings:FTSGreenScreenSettings,extent:CGRect)->CIImage {
        switch settings.backgroundMode {
        case .image:
            if let path=settings.backgroundImagePath,!path.isEmpty,
               let image=CIImage(contentsOf:URL(fileURLWithPath:path),options:[.applyOrientationProperty:true]) {
                return aspectFill(image,to:extent)
            }
            return solid(settings.backgroundColorHex,extent:extent)
        case .comicBurst:
            if let cg=generatedBackground(size:extent.size,mode:.comicBurst,colorHex:settings.backgroundColorHex)
                .cgImage(forProposedRect:nil,context:nil,hints:nil) {
                return CIImage(cgImage:cg).cropped(to:extent)
            }
            return solid(settings.backgroundColorHex,extent:extent)
        case .fireworks:
            if let cg=generatedBackground(size:extent.size,mode:.fireworks,colorHex:settings.backgroundColorHex)
                .cgImage(forProposedRect:nil,context:nil,hints:nil) {
                return CIImage(cgImage:cg).cropped(to:extent)
            }
            return solid("#071315",extent:extent)
        case .color:
            return solid(settings.backgroundColorHex,extent:extent)
        }
    }

    private static func solid(_ hex:String,extent:CGRect)->CIImage {
        let c=(NSColor(hex:hex).usingColorSpace(.deviceRGB) ?? .systemBlue)
        let ci=CIColor(red:c.redComponent,green:c.greenComponent,blue:c.blueComponent,alpha:1)
        return CIImage(color:ci).cropped(to:extent)
    }

    private static func aspectFill(_ image:CIImage,to extent:CGRect)->CIImage {
        let iw=max(image.extent.width,1),ih=max(image.extent.height,1)
        let scale=max(extent.width/iw,extent.height/ih)
        var result=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        result=result.transformed(by:CGAffineTransform(
            translationX:extent.midX-result.extent.midX,
            y:extent.midY-result.extent.midY
        ))
        return result.cropped(to:extent)
    }

    private static func generatedBackground(size:NSSize,mode:FTSGreenBackgroundMode,colorHex:String)->NSImage {
        let out=NSImage(size:size)
        out.lockFocus()
        defer{out.unlockFocus()}
        let rect=NSRect(origin:.zero,size:size)

        if mode == .fireworks {
            NSColor(hex:"#071315").setFill()
            rect.fill()
            let centers=[
                NSPoint(x:size.width*0.25,y:size.height*0.70),
                NSPoint(x:size.width*0.72,y:size.height*0.62),
                NSPoint(x:size.width*0.52,y:size.height*0.30)
            ]
            let colors=[NSColor.systemYellow,NSColor.systemPink,NSColor.systemCyan]
            for (index,center) in centers.enumerated() {
                colors[index % colors.count].setStroke()
                for ray in 0..<18 {
                    let a=CGFloat(ray)/18*CGFloat.pi*2
                    let r1=min(size.width,size.height)*0.045
                    let r2=min(size.width,size.height)*0.15
                    let p=NSBezierPath()
                    p.move(to:NSPoint(x:center.x+cos(a)*r1,y:center.y+sin(a)*r1))
                    p.line(to:NSPoint(x:center.x+cos(a)*r2,y:center.y+sin(a)*r2))
                    p.lineWidth=max(2,min(size.width,size.height)*0.004)
                    p.stroke()
                }
            }
            return out
        }

        let base=NSColor(hex:colorHex)
        base.setFill()
        rect.fill()
        let center=NSPoint(x:size.width*0.5,y:size.height*0.52)
        let radius=max(size.width,size.height)*0.85
        for i in 0..<28 {
            let a1=CGFloat(i)/28*CGFloat.pi*2
            let a2=CGFloat(i+1)/28*CGFloat.pi*2
            if i % 2 == 0 {
                NSColor.white.withAlphaComponent(0.22).setFill()
                let p=NSBezierPath()
                p.move(to:center)
                p.line(to:NSPoint(x:center.x+cos(a1)*radius,y:center.y+sin(a1)*radius))
                p.line(to:NSPoint(x:center.x+cos(a2)*radius,y:center.y+sin(a2)*radius))
                p.close()
                p.fill()
            }
        }
        return out
    }
}

struct FTSGreenScreenView: View {
    @ObservedObject var state:AppState
    let event:EventRow
    @State private var settings=FTSGreenScreenSettings()
    @State private var message=""

    private let colors=["#FFD23F","#1A73E8","#D93025","#188038","#FFFFFF","#111111","#D4AF37","#A142F4"]

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text("Green Screen / Effekte").font(.title2.bold()).foregroundStyle(FTSTheme.gold)
                        Text("Optionale Zusatzfunktion. Aus = bestehender Fotoweg bleibt unverändert.")
                            .font(.caption).foregroundStyle(FTSTheme.muted)
                    }
                    Spacer()
                    Label(settings.enabled ? "Green Screen aktiv":"Green Screen aus",
                          systemImage:settings.enabled ? "checkmark.circle.fill":"circle")
                        .foregroundStyle(settings.enabled ? .green:FTSTheme.muted)
                }

                GroupBox("Green Screen für dieses Event") {
                    VStack(alignment:.leading,spacing:10) {
                        Toggle("Grüne Wand ist aufgebaut · Green Screen verwenden",isOn:$settings.enabled)
                            .toggleStyle(.switch)
                            .onChange(of:settings.enabled){_ in saveSettings(clearEffectCache:true)}
                        Text(settings.enabled
                             ? "Neue und aktive Kamerafotos erhalten den hier gewählten Hintergrund. Originale bleiben unverändert."
                             : "Keine Freistellung und kein Hintergrundersatz. Fotos werden exakt wie bisher verarbeitet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,4)
                }

                GroupBox("Hintergrund") {
                    VStack(alignment:.leading,spacing:10) {
                        Picker("Art",selection:$settings.backgroundMode) {
                            ForEach(FTSGreenBackgroundMode.allCases,id:\.self){mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of:settings.backgroundMode){_ in saveSettings()}

                        if settings.backgroundMode == .color || settings.backgroundMode == .comicBurst {
                            Text("Farbe").font(.caption.bold())
                            HStack(spacing:8) {
                                ForEach(colors,id:\.self){hex in
                                    Button {
                                        settings.backgroundColorHex=hex
                                        saveSettings()
                                    } label:{
                                        Circle()
                                            .fill(Color(nsColor:NSColor(hex:hex)))
                                            .frame(width:30,height:30)
                                            .overlay(Circle().stroke(
                                                settings.backgroundColorHex.uppercased()==hex ? Color.primary:Color.secondary.opacity(0.25),
                                                lineWidth:settings.backgroundColorHex.uppercased()==hex ? 2:1
                                            ))
                                    }.buttonStyle(.plain)
                                }
                                TextField("#RRGGBB",text:$settings.backgroundColorHex)
                                    .textFieldStyle(.roundedBorder).frame(width:120)
                                    .onSubmit{saveSettings()}
                            }
                        }

                        if settings.backgroundMode == .image {
                            HStack {
                                Button("Hintergrundbild auswählen"){chooseBackground()}
                                    .buttonStyle(.borderedProminent)
                                if let p=settings.backgroundImagePath,!p.isEmpty {
                                    Text(URL(fileURLWithPath:p).lastPathComponent)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Button("Entfernen") {
                                        let oldPath=settings.backgroundImagePath
                                        settings.backgroundImagePath=nil
                                        saveSettings(clearEffectCache:true)
                                        if let activation=state.mediaIngest.activation {
                                            FTSGreenScreenStore.removeBackgroundCopy(oldPath,activation:activation)
                                        }
                                        message="Hintergrundbild entfernt. Kamera-Originale bleiben unverändert."
                                    }
                                }
                            }
                            Text("Das Bild wird in den Eventordner „Green Screen Hintergründe“ kopiert. Die Kamera-SD-Karte wird nicht beschrieben.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        backgroundPreview
                            .frame(maxWidth:.infinity)
                            .frame(height:230)
                            .clipShape(RoundedRectangle(cornerRadius:12))
                    }.padding(.vertical,4)
                }

                GroupBox("Freistellung") {
                    VStack(alignment:.leading,spacing:7) {
                        HStack {
                            Text("Kanten weich")
                            Spacer()
                            Text(String(format:"%.0f",settings.edgeSoftness)).monospacedDigit()
                        }.font(.caption)
                        Slider(value:$settings.edgeSoftness,in:0...18,step:1,onEditingChanged:{editing in
                            if !editing { saveSettings(clearEffectCache:true) }
                        })
                        Text("Hilft besonders bei Haaren und feinen Kanten. Die Personenerkennung umfasst Gesicht, Haare, Kleidung und sichtbaren Körper.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical,4)
                }

                GroupBox("Comic und Filter") {
                    VStack(alignment:.leading,spacing:6) {
                        Label("Comic und Foto-Filter werden pro Einzelfoto in der großen Fotoansicht gewählt.",systemImage:"person.crop.rectangle")
                        Text("Comic ohne Green Screen: nur die erkannte Person wird gezeichnet, der echte Hintergrund bleibt normal. Comic mit Green Screen: die Person wird gezeichnet und dieser Hintergrund wird eingesetzt.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,4)
                }

                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
        .task(id:event.event_token) {
            settings=FTSGreenScreenStore.settings(eventToken:event.event_token)
        }
    }

    @ViewBuilder private var backgroundPreview:some View {
        ZStack {
            RoundedRectangle(cornerRadius:12).fill(Color.black.opacity(0.12))
            switch settings.backgroundMode {
            case .image:
                if let p=settings.backgroundImagePath,
                   let image=NSImage(contentsOfFile:p) {
                    Image(nsImage:image).resizable().scaledToFill().clipped()
                } else {
                    VStack(spacing:8) {
                        Image(systemName:"photo.on.rectangle.angled").font(.system(size:34))
                        Text("Noch kein Hintergrundbild gewählt")
                    }.foregroundStyle(.secondary)
                }
            case .color:
                Color(nsColor:NSColor(hex:settings.backgroundColorHex))
            case .comicBurst:
                ZStack {
                    Color(nsColor:NSColor(hex:settings.backgroundColorHex))
                    Image(systemName:"burst.fill").font(.system(size:110)).foregroundStyle(.white.opacity(0.28))
                    Text("COMIC").font(.system(size:32,weight:.black,design:.rounded)).foregroundStyle(.white)
                }
            case .fireworks:
                ZStack {
                    Color(nsColor:NSColor(hex:"#071315"))
                    HStack(spacing:24) {
                        Image(systemName:"sparkles").font(.system(size:62)).foregroundStyle(.yellow)
                        Image(systemName:"sparkles").font(.system(size:86)).foregroundStyle(.cyan)
                        Image(systemName:"sparkles").font(.system(size:58)).foregroundStyle(.pink)
                    }
                }
            }
        }
    }

    private func saveSettings(clearEffectCache:Bool=false) {
        // Settings are lightweight and must react immediately. Never re-render the
        // whole active photo set from this control; the large print preview and
        // the print job read this current snapshot directly.
        FTSGreenScreenStore.save(settings,eventToken:event.event_token)
        if clearEffectCache { FTSPhotoEffectsV132.clearTransientCache() }
        message=settings.enabled
            ? "Green-Screen-Einstellung gespeichert · Vorschau und nächster Druck verwenden sie sofort."
            : "Green Screen ausgeschaltet · normaler Fotoweg aktiv."
    }

    private func chooseBackground() {
        guard let activation=state.mediaIngest.activation else {
            message="Zuerst das Event-Album unter SD-Karte / Import aktivieren."
            return
        }
        let panel=NSOpenPanel()
        panel.title="Green-Screen-Hintergrund auswählen"
        panel.canChooseDirectories=false
        panel.allowsMultipleSelection=false
        panel.allowedFileTypes=["jpg","jpeg","png","heic","tif","tiff"]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let oldPath=settings.backgroundImagePath
            let dest=try FTSGreenScreenStore.copyBackground(url,activation:activation)
            settings.backgroundImagePath=dest.path
            settings.backgroundMode = .image
            saveSettings(clearEffectCache:true)
            if oldPath != dest.path {
                FTSGreenScreenStore.removeBackgroundCopy(oldPath,activation:activation)
            }
            message="Hintergrund gespeichert: \(dest.lastPathComponent)"
        } catch {
            message="Hintergrund konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
