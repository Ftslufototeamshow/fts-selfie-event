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
    case none
    case color
    case image
    case comicBurst
    case fireworks

    var label:String {
        switch self {
        case .none: return "Keiner"
        case .color: return "Farbe"
        case .image: return "Bild / GIF"
        case .comicBurst: return "Comic-Burst"
        case .fireworks: return "Feuerwerk"
        }
    }
}

enum FTSGreenBackgroundAssetKind: String, Codable, Hashable {
    case image
    case animatedGIF

    var label:String { self == .animatedGIF ? "GIF · animiert" : "Bild" }

    static func kind(for path:String)->FTSGreenBackgroundAssetKind {
        URL(fileURLWithPath:path).pathExtension.lowercased()=="gif" ? .animatedGIF : .image
    }
}

struct FTSGreenBackgroundAsset: Codable, Hashable, Identifiable {
    var id:String
    var name:String
    var path:String
    var assignedDay:String?
    var kind:FTSGreenBackgroundAssetKind
    var createdAt:Date
}

struct FTSGreenScreenSettings: Codable, Hashable {
    var enabled=false
    var backgroundMode:FTSGreenBackgroundMode = .none
    var backgroundColorHex="#1A73E8"
    // Kept for print snapshots and backwards compatibility. For library assets
    // this always mirrors the currently manually selected asset.
    var backgroundImagePath:String?=nil
    var backgroundAssets:[FTSGreenBackgroundAsset]=[]
    var activeBackgroundID:String?=nil
    var edgeSoftness:Double=5.0

    var activeBackground:FTSGreenBackgroundAsset? {
        if let id=activeBackgroundID,
           let asset=backgroundAssets.first(where:{$0.id==id}) { return asset }
        if let path=backgroundImagePath,
           let asset=backgroundAssets.first(where:{$0.path==path}) { return asset }
        return nil
    }

    var hasReplacementBackground:Bool {
        guard enabled else{return false}
        switch backgroundMode {
        case .none:return false
        case .image:
            guard let path=backgroundImagePath,!path.isEmpty else{return false}
            return FileManager.default.fileExists(atPath:path)
        case .color,.comicBurst,.fireworks:return true
        }
    }

    var signature:String {
        [
            enabled ? "1":"0",
            backgroundMode.rawValue,
            backgroundColorHex.uppercased(),
            backgroundImagePath ?? "",
            activeBackgroundID ?? "",
            String(format:"%.2f",edgeSoftness)
        ].joined(separator:"|")
    }

    var printSnapshot:FTSGreenScreenSettings {
        var value=self
        if let active=activeBackground {
            value.backgroundAssets=[active]
            value.activeBackgroundID=active.id
            value.backgroundImagePath=active.path
        } else {
            value.backgroundAssets=[]
            value.activeBackgroundID=nil
            if backgroundMode == .image { value.backgroundImagePath=nil }
        }
        return value
    }

    init() {}

    private enum CodingKeys:String,CodingKey {
        case enabled,backgroundMode,backgroundColorHex,backgroundImagePath
        case backgroundAssets,activeBackgroundID,edgeSoftness
    }

    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        enabled=try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? false
        backgroundMode=try c.decodeIfPresent(FTSGreenBackgroundMode.self,forKey:.backgroundMode) ?? .none
        backgroundColorHex=try c.decodeIfPresent(String.self,forKey:.backgroundColorHex) ?? "#1A73E8"
        backgroundImagePath=try c.decodeIfPresent(String.self,forKey:.backgroundImagePath)
        backgroundAssets=try c.decodeIfPresent([FTSGreenBackgroundAsset].self,forKey:.backgroundAssets) ?? []
        activeBackgroundID=try c.decodeIfPresent(String.self,forKey:.activeBackgroundID)
        edgeSoftness=try c.decodeIfPresent(Double.self,forKey:.edgeSoftness) ?? 5.0

        // Migrate the single-background v132/v137 setting into the new library.
        if backgroundAssets.isEmpty,let path=backgroundImagePath,!path.isEmpty {
            let asset=FTSGreenBackgroundAsset(
                id:"legacy:"+path,
                name:URL(fileURLWithPath:path).lastPathComponent,
                path:path,
                assignedDay:nil,
                kind:FTSGreenBackgroundAssetKind.kind(for:path),
                createdAt:Date(timeIntervalSince1970:0)
            )
            backgroundAssets=[asset]
            activeBackgroundID=asset.id
        } else if activeBackgroundID == nil,let path=backgroundImagePath,
                  let asset=backgroundAssets.first(where:{$0.path==path}) {
            activeBackgroundID=asset.id
        }

        // A missing image must mean "no replacement", never a color fallback.
        if backgroundMode == .image {
            guard let path=backgroundImagePath,
                  !path.isEmpty,
                  FileManager.default.fileExists(atPath:path) else {
                backgroundMode = .none
                backgroundImagePath=nil
                activeBackgroundID=nil
                return
            }
        }
    }

    func encode(to encoder:Encoder)throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(enabled,forKey:.enabled)
        try c.encode(backgroundMode,forKey:.backgroundMode)
        try c.encode(backgroundColorHex,forKey:.backgroundColorHex)
        try c.encodeIfPresent(backgroundImagePath,forKey:.backgroundImagePath)
        try c.encode(backgroundAssets,forKey:.backgroundAssets)
        try c.encodeIfPresent(activeBackgroundID,forKey:.activeBackgroundID)
        try c.encode(edgeSoftness,forKey:.edgeSoftness)
    }
}

extension Notification.Name {
    static let ftsGreenScreenSettingsDidChange = Notification.Name("fts.green.screen.settings.changed")
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
        NotificationCenter.default.post(name:.ftsGreenScreenSettingsDidChange,object:eventToken)
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
    private static let greenBackdropDecisionCache:NSCache<NSString,NSNumber> = {
        let cache=NSCache<NSString,NSNumber>()
        cache.countLimit=800
        return cache
    }()

    static func clearTransientCache() {
        personMaskCache.removeAllObjects()
        greenBackdropDecisionCache.removeAllObjects()
    }

    static func processedImage(
        source:NSImage,
        event:EventRow,
        effect:FTSPhotoEffect,
        greenScreenSettings:FTSGreenScreenSettings?=nil,
        cacheKey:String?=nil
    )->NSImage {
        let green=greenScreenSettings ?? FTSGreenScreenStore.settings(eventToken:event.event_token)
        let replacementRequested=green.hasReplacementBackground
        if effect == .normal && !replacementRequested { return source }
        guard let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return source}

        // Green Screen is allowed only when the actual camera image contains a
        // large, connected, chroma-green background field. This blocks grass,
        // green clothing and small green objects from triggering replacement.
        let greenWallDetected = replacementRequested
            ? detectsGreenScreenBackdrop(cgImage:cg,cacheKey:cacheKey)
            : false
        let replacementActive = replacementRequested && greenWallDetected

        let original=CIImage(cgImage:cg)
        let extent=original.extent
        var result=original
        let needsPersonMask = replacementActive || effect == .comic
        let mask = needsPersonMask
            ? personMask(cgImage:cg,extent:extent,softness:green.edgeSoftness,cacheKey:cacheKey)
            : nil

        // Normal photo + no real green wall = untouched camera image. Filters still
        // work normally when the operator explicitly selected one for this photo.
        if effect == .normal && !replacementActive { return source }

        if effect == .comic {
            let comic=comicImage(original)
            if let mask {
                let background = replacementActive ? (backgroundImage(settings:green,extent:extent) ?? original) : original
                result=blend(foreground:comic,background:background,mask:mask) ?? comic
            } else {
                result=comic
            }
        } else {
            if replacementActive,let mask,
               let background=backgroundImage(settings:green,extent:extent) {
                result=blend(foreground:original,background:background,mask:mask) ?? original
            }
            result=apply(effect:effect,to:result)
        }

        guard let out=ciContext.createCGImage(result,from:extent) else{return source}
        return NSImage(cgImage:out,size:source.size)
    }

    private struct GreenComponentStats {
        var count=0
        var minX=Int.max
        var maxX=Int.min
        var minY=Int.max
        var maxY=Int.min
        var touchesLeft=false
        var touchesRight=false
        var touchesTop=false
        var touchesBottom=false
    }

    private static func canonicalDetectionKey(_ cacheKey:String?)->NSString? {
        guard let raw=cacheKey,!raw.isEmpty else{return nil}
        // Tile, large preview and physical print all use the same imported source
        // path. Strip preview-only suffixes so they share exactly one decision.
        let base=raw.split(separator:"|",maxSplits:1,omittingEmptySubsequences:false).first.map(String.init) ?? raw
        return ("green-wall-v142|"+base) as NSString
    }

    private static func detectsGreenScreenBackdrop(cgImage:CGImage,cacheKey:String?)->Bool {
        let key=canonicalDetectionKey(cacheKey)
        if let key,let cached=greenBackdropDecisionCache.object(forKey:key) {
            return cached.boolValue
        }

        let sourceW=max(cgImage.width,1)
        let sourceH=max(cgImage.height,1)
        let maxSide:CGFloat=192
        let scale=min(min(maxSide/CGFloat(sourceW),maxSide/CGFloat(sourceH)),1)
        let w=max(32,Int((CGFloat(sourceW)*scale).rounded()))
        let h=max(32,Int((CGFloat(sourceH)*scale).rounded()))
        let bytesPerRow=w*4
        var rgba=[UInt8](repeating:0,count:h*bytesPerRow)

        let rendered=rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base=raw.baseAddress,
                  let ctx=CGContext(
                    data:base,
                    width:w,
                    height:h,
                    bitsPerComponent:8,
                    bytesPerRow:bytesPerRow,
                    space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else{return false}
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage,in:CGRect(x:0,y:0,width:w,height:h))
            return true
        }
        guard rendered else{return false}

        var green=[UInt8](repeating:0,count:w*h)
        var totalGreen=0
        var upperGreen=0
        var rowCounts=[Int](repeating:0,count:h)
        var colCounts=[Int](repeating:0,count:w)

        func chromaGreen(_ r:Int,_ g:Int,_ b:Int)->Bool {
            let maxV=max(r,max(g,b))
            let minV=min(r,min(g,b))
            let delta=maxV-minV
            guard g>=82,
                  g-r>=32,
                  g-b>=18,
                  maxV>0,
                  Double(delta)/Double(maxV)>=0.34 else{return false}

            // Chroma cloth/walls can photograph much more yellow/lime than
            // textbook pure green, especially under warm event lighting. Accept
            // the full practical lime-green -> blue-green range here; false
            // positives are still blocked below by connected area, vertical span,
            // upper-frame coverage and edge/background geometry.
            let d=Double(max(delta,1))
            var hue:Double
            if maxV==r {
                hue=60.0*((Double(g-b)/d).truncatingRemainder(dividingBy:6.0))
            } else if maxV==g {
                hue=60.0*((Double(b-r)/d)+2.0)
            } else {
                hue=60.0*((Double(r-g)/d)+4.0)
            }
            if hue<0 { hue += 360 }
            return hue>=62 && hue<=178
        }

        for y in 0..<h {
            for x in 0..<w {
                let p=y*bytesPerRow+x*4
                let r=Int(rgba[p]),g=Int(rgba[p+1]),b=Int(rgba[p+2])
                if chromaGreen(r,g,b) {
                    let i=y*w+x
                    green[i]=1
                    totalGreen += 1
                    rowCounts[y] += 1
                    colCounts[x] += 1
                    if y < h/3 { upperGreen += 1 }
                }
            }
        }

        let total=max(w*h,1)
        let overallFraction=Double(totalGreen)/Double(total)
        let upperFraction=Double(upperGreen)/Double(max(w*max(h/3,1),1))

        // Small green objects/clothing can never qualify.
        guard overallFraction>=0.14,upperFraction>=0.055 else {
            if let key { greenBackdropDecisionCache.setObject(NSNumber(value:false),forKey:key) }
            return false
        }

        var visited=[UInt8](repeating:0,count:w*h)
        var best=GreenComponentStats()
        let edgeX=max(1,Int(Double(w)*0.06))
        let edgeY=max(1,Int(Double(h)*0.06))

        for start in 0..<(w*h) where green[start]==1 && visited[start]==0 {
            var stats=GreenComponentStats()
            var stack=[start]
            visited[start]=1
            while let i=stack.popLast() {
                let x=i%w,y=i/w
                stats.count += 1
                stats.minX=min(stats.minX,x);stats.maxX=max(stats.maxX,x)
                stats.minY=min(stats.minY,y);stats.maxY=max(stats.maxY,y)
                if x<edgeX {stats.touchesLeft=true}
                if x>=w-edgeX {stats.touchesRight=true}
                if y<edgeY {stats.touchesTop=true}
                if y>=h-edgeY {stats.touchesBottom=true}

                for ny in max(0,y-1)...min(h-1,y+1) {
                    for nx in max(0,x-1)...min(w-1,x+1) {
                        let n=ny*w+nx
                        if green[n]==1 && visited[n]==0 {
                            visited[n]=1
                            stack.append(n)
                        }
                    }
                }
            }
            if stats.count>best.count {best=stats}
        }

        let componentFraction=Double(best.count)/Double(total)
        let dominance=Double(best.count)/Double(max(totalGreen,1))
        let spanW=best.count>0 ? Double(best.maxX-best.minX+1)/Double(w) : 0
        let spanH=best.count>0 ? Double(best.maxY-best.minY+1)/Double(h) : 0
        let rowsCovered=Double(rowCounts.filter{$0>=max(3,Int(Double(w)*0.12))}.count)/Double(h)
        let colsCovered=Double(colCounts.filter{$0>=max(3,Int(Double(h)*0.12))}.count)/Double(w)
        let edgeTouches=[best.touchesLeft,best.touchesRight,best.touchesTop,best.touchesBottom].filter{$0}.count

        // A real backdrop is one dominant connected field spanning a substantial
        // part of both axes. Natural grass is normally confined to the lower area;
        // clothing/small props fail area, span and edge conditions.
        let normalBackdrop =
            componentFraction>=0.12 &&
            dominance>=0.52 &&
            spanW>=0.46 &&
            spanH>=0.44 &&
            rowsCovered>=0.36 &&
            colsCovered>=0.34 &&
            edgeTouches>=1

        // Allow a centered backdrop that does not quite reach the frame edges only
        // when it is unmistakably large.
        let centeredLargeBackdrop =
            componentFraction>=0.30 &&
            dominance>=0.60 &&
            spanW>=0.68 &&
            spanH>=0.58

        let result=normalBackdrop || centeredLargeBackdrop
        if let key { greenBackdropDecisionCache.setObject(NSNumber(value:result),forKey:key) }
        return result
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

    private static func backgroundImage(settings:FTSGreenScreenSettings,extent:CGRect)->CIImage? {
        switch settings.backgroundMode {
        case .none:
            return nil
        case .image:
            guard let path=settings.backgroundImagePath,!path.isEmpty,
                  let nsImage=NSImage(contentsOfFile:path),
                  let cg=nsImage.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
            // Animated GIFs move in the settings preview. A physical photo is a
            // still image, so its first/default frame is used for the print.
            return aspectFill(CIImage(cgImage:cg),to:extent)
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

final class FTSBackgroundPreviewImageView:NSImageView {
    override var intrinsicContentSize:NSSize { .zero }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}

struct FTSBackgroundFilePreview: NSViewRepresentable {
    let path:String
    let animated:Bool

    func makeNSView(context:Context)->FTSBackgroundPreviewImageView {
        let view=FTSBackgroundPreviewImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.imageFrameStyle = .none
        view.animates = animated
        view.setContentHuggingPriority(.defaultLow,for:.horizontal)
        view.setContentHuggingPriority(.defaultLow,for:.vertical)
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        view.setContentCompressionResistancePriority(.defaultLow,for:.vertical)
        return view
    }

    func updateNSView(_ view:FTSBackgroundPreviewImageView,context:Context) {
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.image = NSImage(contentsOfFile:path)
        view.animates = animated
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
                             ? "Nur Fotos mit tatsächlich erkannter großer Green-Screen-Fläche erhalten den gewählten Hintergrund. Normale Fotos bleiben unverändert."
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
                        .frame(maxWidth:760,alignment:.leading)
                        .onChange(of:settings.backgroundMode){mode in
                            if mode == .image,settings.activeBackground == nil {
                                settings.backgroundImagePath=nil
                            }
                            saveSettings()
                        }

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

                        HStack(spacing:10) {
                            Button("Bilder / GIFs hinzufügen"){chooseBackgrounds()}
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut("b",modifiers:[.command,.shift])
                            if settings.activeBackground != nil || settings.backgroundMode == .image {
                                Button("Hintergrund aus") { deactivateBackground() }
                            }
                        }

                        Text("Mehrere Hintergründe bleiben für dieses Event gespeichert. Du wechselst sie ausschließlich manuell. GIF-Dateien werden hier animiert; der Ausdruck verwendet ein Standbild.")
                            .font(.caption2).foregroundStyle(.secondary)

                        if settings.backgroundAssets.isEmpty {
                            Text("Noch keine Hintergrundbilder gespeichert.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal,showsIndicators:true) {
                                HStack(alignment:.top,spacing:10) {
                                    ForEach(settings.backgroundAssets) { asset in
                                        backgroundAssetCard(asset)
                                    }
                                }
                                .padding(.vertical,2)
                            }
                        }

                        backgroundPreview
                            .frame(maxWidth:.infinity)
                            .frame(height:220)
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
            .frame(maxWidth:.infinity,alignment:.leading)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .clipped()
        .task(id:event.event_token) {
            settings=FTSGreenScreenStore.settings(eventToken:event.event_token)
        }
    }

    @ViewBuilder private var backgroundPreview:some View {
        ZStack {
            RoundedRectangle(cornerRadius:12).fill(Color.black.opacity(0.12))
            switch settings.backgroundMode {
            case .none:
                VStack(spacing:8) {
                    Image(systemName:"rectangle.slash").font(.system(size:34))
                    Text("Kein Green-Screen-Hintergrund aktiv")
                    Text("Das echte Foto bleibt sichtbar.").font(.caption2)
                }.foregroundStyle(.secondary)
            case .image:
                if let asset=settings.activeBackground {
                    FTSBackgroundFilePreview(
                        path:asset.path,
                        animated:asset.kind == .animatedGIF
                    )
                    .allowsHitTesting(false)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .clipped()
                    .padding(8)
                    VStack {
                        HStack {
                            Spacer()
                            Text(asset.kind.label)
                                .font(.caption2.bold())
                                .padding(.horizontal,8).padding(.vertical,4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }.padding(10)
                } else {
                    VStack(spacing:8) {
                        Image(systemName:"photo.on.rectangle.angled").font(.system(size:34))
                        Text("Kein Bild aktiv · unten ein gespeichertes Bild aktivieren")
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

    @ViewBuilder private func backgroundAssetCard(_ asset:FTSGreenBackgroundAsset)->some View {
        let active=settings.activeBackgroundID==asset.id && settings.backgroundMode == .image
        VStack(alignment:.leading,spacing:7) {
            ZStack(alignment:.topTrailing) {
                RoundedRectangle(cornerRadius:9).fill(Color.black.opacity(0.08))
                FTSBackgroundFilePreview(path:asset.path,animated:asset.kind == .animatedGIF)
                    .allowsHitTesting(false)
                    .frame(width:180,height:105)
                    .clipped()
                    .padding(5)
                if active {
                    Label("Aktiv",systemImage:"checkmark.circle.fill")
                        .font(.caption2.bold()).foregroundStyle(.green)
                        .padding(5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(5)
                }
            }
            .frame(width:190,height:115)
            .clipShape(RoundedRectangle(cornerRadius:9))

            Text(asset.name).font(.caption.bold()).lineLimit(1)
            Text(asset.kind.label).font(.caption2).foregroundStyle(.secondary)

            HStack {
                Button(active ? "Aktiv" : "Aktivieren") { activateBackground(asset) }
                    .buttonStyle(.borderedProminent)
                    .disabled(active)
                Menu {
                    Button("Alle Tage") { setAssignedDay(nil,assetID:asset.id) }
                    ForEach(eventDays,id:\.self) { day in
                        Button(day) { setAssignedDay(day,assetID:asset.id) }
                    }
                } label: {
                    Label(asset.assignedDay ?? "Alle Tage",systemImage:"calendar")
                }
                .menuStyle(.borderlessButton)
            }

            Button("Aus Event löschen",role:.destructive) { deleteBackground(asset) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)
        }
        .frame(width:190)
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius:10))
    }

    private var eventDays:[String] {
        state.mediaIngest.eventDays(event)
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

    private func chooseBackgrounds() {
        guard let activation=state.mediaIngest.activation else {
            message="Zuerst das Event-Album unter SD-Karte / Import aktivieren."
            return
        }
        let panel=NSOpenPanel()
        panel.title="Green-Screen-Hintergründe auswählen"
        panel.canChooseDirectories=false
        panel.allowsMultipleSelection=true
        panel.allowedFileTypes=["jpg","jpeg","png","heic","tif","tiff","gif"]
        guard panel.runModal() == .OK,!panel.urls.isEmpty else{return}

        var added:[FTSGreenBackgroundAsset]=[]
        for url in panel.urls {
            do {
                let dest=try FTSGreenScreenStore.copyBackground(url,activation:activation)
                added.append(FTSGreenBackgroundAsset(
                    id:UUID().uuidString,
                    name:dest.lastPathComponent,
                    path:dest.path,
                    assignedDay:nil,
                    kind:FTSGreenBackgroundAssetKind.kind(for:dest.path),
                    createdAt:Date()
                ))
            } catch {
                message="Mindestens ein Hintergrund konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }

        guard !added.isEmpty else{return}
        settings.backgroundAssets.append(contentsOf:added)
        // Initial import may activate the first selected file. Later changes are
        // always manual and there is never an automatic rotation.
        if settings.activeBackground == nil,let first=added.first {
            settings.activeBackgroundID=first.id
            settings.backgroundImagePath=first.path
            settings.backgroundMode = .image
        }
        saveSettings(clearEffectCache:true)
        message="\(added.count) Hintergrund\(added.count==1 ? "" : "bilder") gespeichert · Wechsel erfolgt nur manuell."
    }

    private func activateBackground(_ asset:FTSGreenBackgroundAsset) {
        guard FileManager.default.fileExists(atPath:asset.path) else {
            message="Diese Hintergrunddatei fehlt. Bitte löschen und neu hinzufügen."
            return
        }
        settings.activeBackgroundID=asset.id
        settings.backgroundImagePath=asset.path
        settings.backgroundMode = .image
        saveSettings(clearEffectCache:true)
        message="Aktiv: \(asset.name)"
    }

    private func deactivateBackground() {
        settings.activeBackgroundID=nil
        settings.backgroundImagePath=nil
        settings.backgroundMode = .none
        saveSettings(clearEffectCache:true)
        message="Hintergrund ausgeschaltet · das echte Foto bleibt sichtbar."
    }

    private func deleteBackground(_ asset:FTSGreenBackgroundAsset) {
        let wasActive=settings.activeBackgroundID==asset.id || settings.backgroundImagePath==asset.path
        settings.backgroundAssets.removeAll{$0.id==asset.id}
        if wasActive {
            settings.activeBackgroundID=nil
            settings.backgroundImagePath=nil
            settings.backgroundMode = .none
        }
        saveSettings(clearEffectCache:true)
        // Remove it from the event library immediately, but keep the local file
        // until event cleanup so an already queued print snapshot can still use it.
        message="\(asset.name) aus diesem Event gelöscht."
    }

    private func setAssignedDay(_ day:String?,assetID:String) {
        guard let index=settings.backgroundAssets.firstIndex(where:{$0.id==assetID}) else{return}
        settings.backgroundAssets[index].assignedDay=day
        saveSettings()
        message=day.map{"Bild für Tag \($0) gekennzeichnet · Aktivierung bleibt manuell."}
            ?? "Tageskennzeichnung entfernt · Aktivierung bleibt manuell."
    }

}
