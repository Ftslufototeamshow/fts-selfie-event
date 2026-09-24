import SwiftUI
import AppKit
import Foundation
import CryptoKit
import ImageIO

struct V80MediaActivation: Codable, Hashable {
    let eventToken: String
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
}

@MainActor
final class MediaIngestV80: ObservableObject {
    @Published var activation: V80MediaActivation?
    @Published var items: [V80MediaItem] = []
    @Published var detectedCards: [V80DetectedCard] = []
    @Published var registeredCardLabels: Set<String> = []
    @Published var status = "Lokales Event-Album noch nicht aktiviert."
    @Published var scanning = false
    @Published var lastImportedCount = 0

    private func activationKey(_ event: EventRow) -> String { "fts.media.activation.v80.\(event.event_token)" }

    func load(event: EventRow) {
        guard let d=UserDefaults.standard.data(forKey:activationKey(event)),
              let a=try? JSONDecoder().decode(V80MediaActivation.self,from:d),
              FileManager.default.fileExists(atPath:a.folderPath) else {
            activation=nil;items=[];detectedCards=[];registeredCardLabels=[];status="Event-Album noch nicht aktiviert.";return
        }
        activation=a
        loadManifest()
        status="Event-Album aktiv."
    }

    func activate(event: EventRow) throws {
        let fm=FileManager.default
        let pictures=fm.urls(for:.picturesDirectory,in:.userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let root=pictures.appendingPathComponent("FTS Print Events",isDirectory:true)
        let code=sanitize(event.short_code ?? event.event_token)
        let name=sanitize(event.event_title)
        let folder=root.appendingPathComponent("\(code) - \(name)",isDirectory:true)
        let original=folder.appendingPathComponent("Kamera Original",isDirectory:true)
        let wlan=folder.appendingPathComponent("WLAN Kamera Eingang",isDirectory:true)
        try fm.createDirectory(at:original,withIntermediateDirectories:true)
        try fm.createDirectory(at:folder.appendingPathComponent("Druckbereit",isDirectory:true),withIntermediateDirectories:true)
        try fm.createDirectory(at:wlan,withIntermediateDirectories:true)

        let a=V80MediaActivation(eventToken:event.event_token,folderPath:folder.path,wlanInputPath:wlan.path,activatedAt:Date())
        activation=a
        UserDefaults.standard.set(try JSONEncoder().encode(a),forKey:activationKey(event))
        let manifestURL=folder.appendingPathComponent(".fts-media-manifest-v80.json")
        if !fm.fileExists(atPath:manifestURL.path) {
            try JSONEncoder().encode(V80MediaManifest()).write(to:manifestURL,options:.atomic)
        }
        loadManifest()
        status="Event-Album aktiv. SD-Karten können jetzt A/B/C/D zugeordnet werden."
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
        for f in files {
            if let k=sourceKey(f,root:volume){keys.insert(k)}
        }
        manifest.baselines[cardUUID]=V80CardBaseline(cardUUID:cardUUID,label:label,knownSourceKeys:keys,createdAt:Date())
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
            guard var baseline=manifest.baselines[marker.cardUUID] else {
                continue
            }

            for file in mediaFiles(on:volume) {
                guard let key=sourceKey(file,root:volume) else{continue}
                if baseline.knownSourceKeys.contains(key){continue}
                // Wait until the camera/OS has finished writing the file.
                let rv=try? file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
                if let mod=rv?.contentModificationDate,Date().timeIntervalSince(mod)<1.5{continue}
                guard (rv?.fileSize ?? 0)>0 else{continue}

                let hash=try sha256(file)
                baseline.knownSourceKeys.insert(key)
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
        if let en=fm.enumerator(at:wlan,includingPropertiesForKeys:[.isRegularFileKey,.contentModificationDateKey,.fileSizeKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) {
            for case let file as URL in en {
                guard supported(file) else{continue}
                let rv=try? file.resourceValues(forKeys:[.isRegularFileKey,.contentModificationDateKey,.fileSizeKey])
                guard rv?.isRegularFile==true,(rv?.fileSize ?? 0)>0 else{continue}
                if let mod=rv?.contentModificationDate,Date().timeIntervalSince(mod)<1.5{continue}
                guard let key=sourceKey(file,root:wlan) else{continue}
                if manifest.wlanKnownSourceKeys.contains(key){continue}
                let hash=try sha256(file)
                manifest.wlanKnownSourceKeys.insert(key)
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
        guard let en=fm.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.contentModificationDateKey,.fileSizeKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else{return[]}
        var result:[URL]=[]
        for case let f as URL in en where supported(f) {
            if (try? f.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true{result.append(f)}
        }
        return result
    }

    nonisolated private static func supported(_ u:URL)->Bool {
        ["jpg","jpeg","heic","png"].contains(u.pathExtension.lowercased())
    }

    nonisolated private static func sourceKey(_ file:URL,root:URL)->String? {
        guard let rv=try? file.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]) else{return nil}
        let rel=file.path.hasPrefix(root.path) ? String(file.path.dropFirst(root.path.count)) : file.lastPathComponent
        let size=rv.fileSize ?? 0
        let mod=Int((rv.contentModificationDate ?? .distantPast).timeIntervalSince1970)
        return "\(rel)|\(size)|\(mod)"
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
