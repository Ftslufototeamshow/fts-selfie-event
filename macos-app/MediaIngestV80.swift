import SwiftUI
import AppKit
import Foundation
import CryptoKit
import ImageIO

struct V80MediaActivation: Codable, Hashable {
    let eventToken: String
    let eventDay: String?
    let folderPath: String
    let wlanInputPath: String
    let activatedAt: Date
}

struct V80CardMarker: Codable, Hashable {
    let version: Int
    let eventToken: String
    let cardUUID: String
    let label: String
    let registeredAt: Date
}

struct V80DetectedCard: Identifiable, Hashable {
    let id: String
    let volumePath: String
    let volumeName: String
    let technicalID: String
    let marker: V80CardMarker?
    let writable: Bool

    var label: String? { marker?.label }
    var registered: Bool { marker != nil }
}

struct V80CardBaseline: Codable, Hashable {
    let cardUUID: String
    let label: String
    var knownSourceKeys: Set<String>
    var knownFingerprints: [String:String]?
    let createdAt: Date
}

struct V80MediaItem: Codable, Identifiable, Hashable {
    let id: String
    let sha256: String
    let sourcePath: String
    let importedPath: String
    let originalName: String
    let sourceType: String
    let sourceLabel: String
    let cardUUID: String?
    let cameraID: String?
    let importedAt: Date
}

struct V80MediaManifest: Codable {
    var items: [V80MediaItem] = []
    var baselines: [String: V80CardBaseline] = [:]
    var wlanKnownSourceKeys: Set<String> = []
    var wlanFingerprints: [String:String]?
}

@MainActor
final class MediaIngestV80: ObservableObject {
    @Published var activation: V80MediaActivation?
    @Published var selectedDay = ""
    @Published var items: [V80MediaItem] = []
    @Published var detectedCards: [V80DetectedCard] = []
    @Published var registeredCardLabels: Set<String> = []
    @Published var status = "Lokales Event-Album noch nicht aktiviert."
    @Published var scanning = false
    @Published var lastImportedCount = 0

    private func legacyActivationKey(_ event: EventRow) -> String { "fts.media.activation.v80.\(event.event_token)" }
    private func activationKey(_ event: EventRow, day: String) -> String { "fts.media.activation.v92.\(event.event_token).\(day)" }
    private func daySelectionKey(_ event: EventRow) -> String { "fts.media.day.v92.\(event.event_token)" }

    func eventDays(_ event: EventRow) -> [String] {
        var days:[String]=[]
        if let values=event.event_days?.array {
            for value in values {
                if let d=value.string, !d.isEmpty, !days.contains(d) { days.append(d) }
            }
        }
        if days.isEmpty, let d=event.event_date, !d.isEmpty { days=[d] }
        return days.sorted()
    }

    private func todayString() -> String {
        let f=DateFormatter()
        f.calendar=Calendar(identifier:.gregorian)
        f.locale=Locale(identifier:"en_US_POSIX")
        f.timeZone=TimeZone(identifier:"Europe/Luxembourg") ?? .current
        f.dateFormat="yyyy-MM-dd"
        return f.string(from:Date())
    }

    private func preferredDay(for event: EventRow) -> String {
        let days=eventDays(event)
        let saved=UserDefaults.standard.string(forKey:daySelectionKey(event))
        if let saved,days.contains(saved){return saved}
        let today=todayString()
        if days.contains(today){return today}
        return days.first ?? event.event_date ?? today
    }

    func load(event: EventRow) {
        let day=selectedDay.isEmpty ? preferredDay(for:event) : selectedDay
        selectedDay=eventDays(event).contains(day) ? day : preferredDay(for:event)
        UserDefaults.standard.set(selectedDay,forKey:daySelectionKey(event))

        if UserDefaults.standard.data(forKey:activationKey(event,day:selectedDay)) == nil,
           UserDefaults.standard.data(forKey:legacyActivationKey(event)) != nil {
            try? createDailyAlbums(event:event)
        }

        guard let d=UserDefaults.standard.data(forKey:activationKey(event,day:selectedDay)),
              let a=try? JSONDecoder().decode(V80MediaActivation.self,from:d),
              FileManager.default.fileExists(atPath:a.folderPath) else {
            activation=nil;items=[];detectedCards=[];registeredCardLabels=[]
            status="Tagesalbum \(selectedDay) noch nicht aktiviert.";return
        }
        activation=a
        loadManifest()
        status="Tagesalbum \(selectedDay) aktiv."
    }

    func selectDay(_ day:String,event:EventRow) {
        guard eventDays(event).contains(day) else{return}
        selectedDay=day
        UserDefaults.standard.set(day,forKey:daySelectionKey(event))
        load(event:event)
    }

    func activate(event: EventRow) throws {
        if selectedDay.isEmpty { selectedDay=preferredDay(for:event) }
        try createDailyAlbums(event:event)
        load(event:event)
        status="Tagesalbum \(selectedDay) aktiv. SD-Karten können A/B/C/D zugeordnet werden."
    }

    private func createDailyAlbums(event:EventRow) throws {
        let fm=FileManager.default
        let pictures=fm.urls(for:.picturesDirectory,in:.userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let root=pictures.appendingPathComponent("FTS Print Events",isDirectory:true)
        let code=sanitize(event.short_code ?? event.event_token)
        let name=sanitize(event.event_title)
        let eventRoot=root.appendingPathComponent("\(code) - \(name)",isDirectory:true)
        try fm.createDirectory(at:eventRoot,withIntermediateDirectories:true)

        var days=eventDays(event)
        if days.isEmpty { days=[selectedDay.isEmpty ? todayString() : selectedDay] }
        for day in days {
            let folder=eventRoot.appendingPathComponent(day,isDirectory:true)
            let original=folder.appendingPathComponent("Kamera Original",isDirectory:true)
            let wlan=folder.appendingPathComponent("WLAN Kamera Eingang",isDirectory:true)
            try fm.createDirectory(at:original,withIntermediateDirectories:true)
            try fm.createDirectory(at:folder.appendingPathComponent("Druckbereit",isDirectory:true),withIntermediateDirectories:true)
            try fm.createDirectory(at:wlan,withIntermediateDirectories:true)

            let a=V80MediaActivation(eventToken:event.event_token,eventDay:day,folderPath:folder.path,wlanInputPath:wlan.path,activatedAt:Date())
            UserDefaults.standard.set(try JSONEncoder().encode(a),forKey:activationKey(event,day:day))
            let manifestURL=folder.appendingPathComponent(".fts-media-manifest-v80.json")
            if !fm.fileExists(atPath:manifestURL.path) {
                try JSONEncoder().encode(V80MediaManifest()).write(to:manifestURL,options:.atomic)
            }
        }
    }

    func clearCurrentDayLocal() throws {
        guard let a=activation else{return}
        let fm=FileManager.default
        var manifest=try Self.loadManifestSync(a)
        let folder=URL(fileURLWithPath:a.folderPath,isDirectory:true)
        for name in ["Kamera Original","Druckbereit"] {
            let u=folder.appendingPathComponent(name,isDirectory:true)
            if fm.fileExists(atPath:u.path){try fm.removeItem(at:u)}
            try fm.createDirectory(at:u,withIntermediateDirectories:true)
        }
        manifest.items=[]
        try Self.saveManifestSync(manifest,a)
        let queue=folder.appendingPathComponent(".fts-local-print-queue-v80.json")
        if fm.fileExists(atPath:queue.path){try fm.removeItem(at:queue)}
        items=[]
        lastImportedCount=0
        status="Tagesalbum \(selectedDay) geleert. Karte/WLAN-Startbestand bleibt geschützt."
    }

    func revealEventFolder() {
        guard let a=activation else{return}
        NSWorkspace.shared.open(URL(fileURLWithPath:a.folderPath))
    }

    func revealWLANFolder() {
        guard let a=activation else{return}
        NSWorkspace.shared.open(URL(fileURLWithPath:a.wlanInputPath))
    }

    func register(card: V80DetectedCard, label: String, event: EventRow, replaceExisting: Bool = false) async {
        guard let a=activation else{return}
        let clean=label.uppercased().trimmingCharacters(in:.whitespacesAndNewlines)
        guard ["A","B","C","D"].contains(clean) else {
            status="Kartenname muss A, B, C oder D sein.";return
        }
        scanning=true
        defer{scanning=false}
        do {
            let result=try await Task.detached(priority:.utility) {
                try Self.registerSync(card:card,label:clean,eventToken:event.event_token,activation:a,replaceExisting:replaceExisting)
            }.value
            items=result.items.sorted{$0.importedAt>$1.importedAt}
            detectedCards=result.cards
            registeredCardLabels=result.labels
            status="Karte \(clean) registriert. \(result.baselineCount) vorhandene Fotos wurden als Altbestand markiert."
        } catch {
            status="Karte konnte nicht registriert werden: \(error.localizedDescription)"
        }
    }

    func scan(event: EventRow) async {
        guard let a=activation,!scanning else{return}
        scanning=true
        status="SD-Karten und WLAN-Eingang werden geprüft …"
        defer{scanning=false}
        do {
            let r=try await Task.detached(priority:.utility) {
                try Self.scanSync(eventToken:event.event_token,activation:a)
            }.value
            items=r.items.sorted{$0.importedAt>$1.importedAt}
            detectedCards=r.cards
            registeredCardLabels=r.labels
            lastImportedCount=r.newCount
            if r.newCount>0 {
                status="\(r.newCount) neue Foto\(r.newCount==1 ? "" : "s") übernommen."
            } else if r.cards.contains(where:{$0.marker==nil}) {
                status="Unbekannte SD-Karte erkannt. Erst A/B/C/D zuordnen – noch kein Import."
            } else {
                status="Aktuell · keine neuen Fotos."
            }
        } catch {
            status="Importprüfung: \(error.localizedDescription)"
        }
    }

    private func loadManifest() {
        guard let a=activation else{return}
        let u=URL(fileURLWithPath:a.folderPath).appendingPathComponent(".fts-media-manifest-v80.json")
        guard let d=try? Data(contentsOf:u),let m=try? JSONDecoder().decode(V80MediaManifest.self,from:d) else {
            items=[];return
        }
        items=m.items.sorted{$0.importedAt>$1.importedAt}
        registeredCardLabels=Set(m.baselines.values.map{$0.label})
    }

    nonisolated private static func registerSync(card:V80DetectedCard,label:String,eventToken:String,activation:V80MediaActivation,replaceExisting:Bool) throws -> (items:[V80MediaItem],cards:[V80DetectedCard],baselineCount:Int,labels:Set<String>) {
        let fm=FileManager.default
        let volume=URL(fileURLWithPath:card.volumePath,isDirectory:true)
        guard fm.isWritableFile(atPath:volume.path) else {
            throw NSError(domain:"FTSPrinter",code:100,userInfo:[NSLocalizedDescriptionKey:"SD-Karte ist schreibgeschützt."])
        }

        var manifest=try loadManifestSync(activation)
        let existingIDs=manifest.baselines.filter{$0.value.label==label}.map{$0.key}
        if !existingIDs.isEmpty && !replaceExisting {
            throw NSError(domain:"FTSPrinter",code:101,userInfo:[NSLocalizedDescriptionKey:"Karte \(label) ist für dieses Event bereits registriert. Zum Ersetzen ausdrücklich „\(label) ersetzen“ wählen."])
        }
        if replaceExisting {
            for id in existingIDs { manifest.baselines.removeValue(forKey:id) }
        }

        let cardUUID=UUID().uuidString
        let marker=V80CardMarker(version:80,eventToken:eventToken,cardUUID:cardUUID,label:label,registeredAt:Date())
        let markerURL=volume.appendingPathComponent(".fts-printer-card-v80.json")
        try JSONEncoder().encode(marker).write(to:markerURL,options:.atomic)

        let files=mediaFiles(on:volume)
        var keys=Set<String>()
        var fingerprints:[String:String]=[:]
        for f in files {
            if let k=sourceKey(f,root:volume){
                keys.insert(k)
                fingerprints[k]=try sha256(f)
            }
        }
        manifest.baselines[cardUUID]=V80CardBaseline(
            cardUUID:cardUUID,label:label,knownSourceKeys:keys,
            knownFingerprints:fingerprints,createdAt:Date()
        )
        try saveManifestSync(manifest,activation)
        let cards=detectCardsSync(eventToken:eventToken)
        return (manifest.items,cards,keys.count,Set(manifest.baselines.values.map{$0.label}))
    }

    nonisolated private static func scanSync(eventToken:String,activation:V80MediaActivation) throws -> (items:[V80MediaItem],cards:[V80DetectedCard],newCount:Int,labels:Set<String>) {
        let fm=FileManager.default
        var manifest=try loadManifestSync(activation)
        var hashes=Set(manifest.items.map(\.sha256))
        var newCount=0
        let cards=detectCardsSync(eventToken:eventToken)

        for card in cards {
            guard let marker=card.marker,marker.eventToken==eventToken else{continue}
            let volume=URL(fileURLWithPath:card.volumePath,isDirectory:true)
            if manifest.baselines[marker.cardUUID] == nil {
                var keys=Set<String>()
                var fingerprints:[String:String]=[:]
                for file in mediaFiles(on:volume) {
                    if let key=sourceKey(file,root:volume) {
                        keys.insert(key)
                        fingerprints[key]=(try? sha256(file)) ?? ""
                    }
                }
                manifest.baselines[marker.cardUUID]=V80CardBaseline(
                    cardUUID:marker.cardUUID,label:marker.label,knownSourceKeys:keys,
                    knownFingerprints:fingerprints,createdAt:Date()
                )
                continue
            }
            guard var baseline=manifest.baselines[marker.cardUUID] else { continue }

            for file in mediaFiles(on:volume) {
                guard let key=sourceKey(file,root:volume) else{continue}
                // Wait until the camera/OS has finished writing the file.
                let rv=try? file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
                if let mod=rv?.contentModificationDate,Date().timeIntervalSince(mod)<1.5{continue}
                guard (rv?.fileSize ?? 0)>0 else{continue}

                if baseline.knownSourceKeys.contains(key) {
                    if let oldHash=baseline.knownFingerprints?[key] {
                        let currentHash=try sha256(file)
                        if currentHash==oldHash { continue }
                        // Same path/size/time but different bytes: treat as a new camera file.
                    } else {
                        // Compatibility with baselines created before fingerprint tracking.
                        continue
                    }
                }

                let hash=try sha256(file)
                baseline.knownSourceKeys.insert(key)
                if baseline.knownFingerprints == nil { baseline.knownFingerprints=[:] }
                baseline.knownFingerprints?[key]=hash
                if hashes.contains(hash){continue}

                let folder=URL(fileURLWithPath:activation.folderPath)
                    .appendingPathComponent("Kamera Original",isDirectory:true)
                    .appendingPathComponent("SD \(marker.label)",isDirectory:true)
                try fm.createDirectory(at:folder,withIntermediateDirectories:true)
                let dest=uniqueDestination(folder:folder,name:file.lastPathComponent)
                try fm.copyItem(at:file,to:dest)
                let item=V80MediaItem(
                    id:hash,sha256:hash,sourcePath:file.path,importedPath:dest.path,
                    originalName:file.lastPathComponent,sourceType:"SD",sourceLabel:marker.label,
                    cardUUID:marker.cardUUID,cameraID:cameraIdentity(file),importedAt:Date()
                )
                manifest.items.append(item);hashes.insert(hash);newCount+=1
            }
            manifest.baselines[marker.cardUUID]=baseline
        }

        // WLAN folder: Canon EOS Utility writes here. Existing files become known after first scan,
        // and every stable new image is copied into the local original archive.
        let wlan=URL(fileURLWithPath:activation.wlanInputPath,isDirectory:true)
        let wlanArchive=URL(fileURLWithPath:activation.folderPath)
            .appendingPathComponent("Kamera Original/WLAN",isDirectory:true)
        try fm.createDirectory(at:wlanArchive,withIntermediateDirectories:true)
        for file in preferredMediaFiles(root:wlan) {
            let rv=try? file.resourceValues(forKeys:[.isRegularFileKey,.contentModificationDateKey,.fileSizeKey])
            guard rv?.isRegularFile==true,(rv?.fileSize ?? 0)>0 else{continue}
            if let mod=rv?.contentModificationDate,Date().timeIntervalSince(mod)<1.5{continue}
            guard let key=sourceKey(file,root:wlan) else{continue}
            if manifest.wlanKnownSourceKeys.contains(key) {
                if let oldHash=manifest.wlanFingerprints?[key] {
                    let currentHash=try sha256(file)
                    if currentHash==oldHash { continue }
                } else {
                    continue
                }
            }
            let hash=try sha256(file)
            manifest.wlanKnownSourceKeys.insert(key)
            if manifest.wlanFingerprints == nil { manifest.wlanFingerprints=[:] }
            manifest.wlanFingerprints?[key]=hash
            if hashes.contains(hash){continue}
            let dest=uniqueDestination(folder:wlanArchive,name:file.lastPathComponent)
            try fm.copyItem(at:file,to:dest)
            let item=V80MediaItem(
                id:hash,sha256:hash,sourcePath:file.path,importedPath:dest.path,
                originalName:file.lastPathComponent,sourceType:"WIFI",sourceLabel:"W",
                cardUUID:nil,cameraID:cameraIdentity(file),importedAt:Date()
            )
            manifest.items.append(item);hashes.insert(hash);newCount+=1
        }

        try saveManifestSync(manifest,activation)
        return (manifest.items,cards,newCount,Set(manifest.baselines.values.map{$0.label}))
    }

    nonisolated private static func detectCardsSync(eventToken:String) -> [V80DetectedCard] {
        let fm=FileManager.default
        let keys:Set<URLResourceKey>=[.volumeIsRemovableKey,.volumeIsEjectableKey,.volumeIsInternalKey,.volumeNameKey,.volumeIdentifierKey,.isWritableKey]
        let volumes=fm.mountedVolumeURLs(includingResourceValuesForKeys:Array(keys),options:[.skipHiddenVolumes]) ?? []
        var out:[V80DetectedCard]=[]
        for v in volumes {
            let rv=try? v.resourceValues(forKeys:keys)
            let removable=rv?.volumeIsRemovable==true || rv?.volumeIsEjectable==true
            if !removable || rv?.volumeIsInternal==true{continue}
            let name=rv?.volumeName ?? v.lastPathComponent
            let tid=rv?.volumeIdentifier.map{String(describing:$0)} ?? v.path
            let markerURL=v.appendingPathComponent(".fts-printer-card-v80.json")
            var marker:V80CardMarker?=nil
            if let d=try? Data(contentsOf:markerURL),let m=try? JSONDecoder().decode(V80CardMarker.self,from:d),m.eventToken==eventToken {
                marker=m
            }
            out.append(V80DetectedCard(
                id:tid,volumePath:v.path,volumeName:name,technicalID:tid,marker:marker,
                writable:rv?.isWritable ?? fm.isWritableFile(atPath:v.path)
            ))
        }
        return out.sorted{$0.volumeName.localizedCaseInsensitiveCompare($1.volumeName) == .orderedAscending}
    }

    nonisolated private static func mediaFiles(on volume:URL) -> [URL] {
        let fm=FileManager.default
        let dcim=volume.appendingPathComponent("DCIM",isDirectory:true)
        let root=fm.fileExists(atPath:dcim.path) ? dcim : volume
        return preferredMediaFiles(root:root)
    }

    // Cameras often save RAW + JPEG with the same base filename.
    // FTS imports exactly one file per pair and prefers the much smaller JPEG.
    // RAW remains a fallback only when no JPEG/HEIC/PNG partner exists.
    nonisolated private static func preferredMediaFiles(root:URL) -> [URL] {
        let fm=FileManager.default
        guard let en=fm.enumerator(
            at:root,
            includingPropertiesForKeys:[.isRegularFileKey,.contentModificationDateKey,.fileSizeKey],
            options:[.skipsHiddenFiles,.skipsPackageDescendants]
        ) else{return[]}

        var best:[String:URL]=[:]
        for case let f as URL in en {
            guard supported(f),(try? f.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true else{continue}
            let parent=f.deletingLastPathComponent().path.lowercased()
            let stem=f.deletingPathExtension().lastPathComponent.lowercased()
            let key=parent+"|"+stem
            if let old=best[key] {
                if preferenceRank(f)<preferenceRank(old){best[key]=f}
            } else {
                best[key]=f
            }
        }
        return best.values.sorted{$0.path.localizedCaseInsensitiveCompare($1.path)==.orderedAscending}
    }

    nonisolated private static func supported(_ u:URL)->Bool {
        ["jpg","jpeg","heic","hif","png","cr3","cr2","dng","nef","arw","raf"].contains(u.pathExtension.lowercased())
    }

    nonisolated private static func preferenceRank(_ u:URL)->Int {
        switch u.pathExtension.lowercased() {
        case "jpg","jpeg": return 0
        case "heic","hif": return 1
        case "png": return 2
        default: return 10
        }
    }

    nonisolated private static func sourceKey(_ file:URL,root:URL)->String? {
        guard let rv=try? file.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]) else{return nil}
        let rel=file.path.hasPrefix(root.path) ? String(file.path.dropFirst(root.path.count)) : file.lastPathComponent
        let size=rv.fileSize ?? 0
        let mod=Int((rv.contentModificationDate ?? .distantPast).timeIntervalSince1970)
        let capture=captureTimestamp(file) ?? ""
        return "\(rel)|\(size)|\(mod)|\(capture)"
    }

    nonisolated private static func loadManifestSync(_ activation:V80MediaActivation) throws -> V80MediaManifest {
        let u=URL(fileURLWithPath:activation.folderPath).appendingPathComponent(".fts-media-manifest-v80.json")
        guard let d=try? Data(contentsOf:u) else{return V80MediaManifest()}
        return (try? JSONDecoder().decode(V80MediaManifest.self,from:d)) ?? V80MediaManifest()
    }

    nonisolated private static func saveManifestSync(_ manifest:V80MediaManifest,_ activation:V80MediaActivation) throws {
        let u=URL(fileURLWithPath:activation.folderPath).appendingPathComponent(".fts-media-manifest-v80.json")
        try JSONEncoder().encode(manifest).write(to:u,options:.atomic)
    }

    nonisolated private static func sha256(_ url:URL)throws->String{
        let h=try FileHandle(forReadingFrom:url);defer{try? h.close()}
        var hasher=SHA256()
        while true{
            guard let d=try h.read(upToCount:1_048_576),!d.isEmpty else{break}
            hasher.update(data:d)
        }
        return hasher.finalize().map{String(format:"%02x",$0)}.joined()
    }

    nonisolated private static func uniqueDestination(folder:URL,name:String)->URL{
        let fm=FileManager.default
        var candidate=folder.appendingPathComponent(name)
        if !fm.fileExists(atPath:candidate.path){return candidate}
        let base=(name as NSString).deletingPathExtension
        let ext=(name as NSString).pathExtension
        var i=2
        while fm.fileExists(atPath:candidate.path){
            candidate=folder.appendingPathComponent(ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)")
            i+=1
        }
        return candidate
    }

    nonisolated private static func captureTimestamp(_ url:URL)->String?{
        guard let src=CGImageSourceCreateWithURL(url as CFURL,nil),
              let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [String:Any] else{return nil}
        let exif=props["{Exif}"] as? [String:Any]
        let tiff=props["{TIFF}"] as? [String:Any]
        return (exif?["DateTimeOriginal"] as? String)
            ?? (exif?["DateTimeDigitized"] as? String)
            ?? (tiff?["DateTime"] as? String)
    }

    nonisolated private static func cameraIdentity(_ url:URL)->String?{
        guard let src=CGImageSourceCreateWithURL(url as CFURL,nil),
              let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [String:Any] else{return nil}
        let tiff=props["{TIFF}"] as? [String:Any]
        let exif=props["{Exif}"] as? [String:Any]
        let make=(tiff?["Make"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
        let model=(tiff?["Model"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
        let serial=(exif?["BodySerialNumber"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
        let parts=[make,model,serial].compactMap{($0?.isEmpty==false) ? $0:nil}
        return parts.isEmpty ? nil:parts.joined(separator:" · ")
    }

    private func sanitize(_ s:String)->String{
        let illegal=CharacterSet(charactersIn:"/:\\?%*|\"<>")
        return s.components(separatedBy:illegal).joined(separator:"-").replacingOccurrences(of:"  ",with:" ")
    }
}
