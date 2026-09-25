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

enum V80MediaWorkflow: String, Codable, Hashable {
    case active = "ACTIVE"
    case queued = "QUEUED"
    case produced = "PRODUZIERT"
    case error = "FEHLER"
    case delivered = "ABGEGEBEN"
    case hidden = "HIDDEN"
}

struct V80MediaItem: Codable, Identifiable, Hashable {
    let id: String
    let sha256: String
    let sourcePath: String
    let importedPath: String
    var designedPath: String?
    var designSignature: String?
    let originalName: String
    let sourceType: String
    let sourceLabel: String
    let cardUUID: String?
    let cameraID: String?
    let importedAt: Date
    var workflowStatus: V80MediaWorkflow? = nil
    var workflowUpdatedAt: Date? = nil

    var effectiveWorkflow: V80MediaWorkflow { workflowStatus ?? .active }
    var visibleInPrinter: Bool { effectiveWorkflow == .active }
}

struct V80MediaManifest: Codable {
    var items: [V80MediaItem] = []
    var baselines: [String: V80CardBaseline] = [:]
    var wlanKnownSourceKeys: Set<String> = []
    var wlanFingerprints: [String:String]?
    var importedHashes: Set<String>?
}

struct V80LocalCardRegistry: Codable {
    var cards: [String:V80CardMarker] = [:]
    var signatures: [String:V80CardMarker]? = nil
    var releasedTechnicalIDs: Set<String>? = nil
    var releasedSignatures: Set<String>? = nil
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
    @Published var wlanCameraActive = false
    @Published var wlanCameraName = ""
    @Published var wlanCameraBars = 0
    @Published var wlanCameraQuality = ""
    @Published var wlanCameraDetail = ""

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
           let legacyData=UserDefaults.standard.data(forKey:legacyActivationKey(event)),
           let legacy=try? JSONDecoder().decode(V80MediaActivation.self,from:legacyData) {
            try? createDailyAlbums(event:event)
            if let dayData=UserDefaults.standard.data(forKey:activationKey(event,day:selectedDay)),
               let dayActivation=try? JSONDecoder().decode(V80MediaActivation.self,from:dayData),
               var legacyManifest=try? Self.loadManifestSync(legacy),
               var dayManifest=try? Self.loadManifestSync(dayActivation) {
                dayManifest.baselines=legacyManifest.baselines
                dayManifest.wlanKnownSourceKeys=legacyManifest.wlanKnownSourceKeys
                dayManifest.wlanFingerprints=legacyManifest.wlanFingerprints
                try? Self.saveManifestSync(dayManifest,dayActivation)
                legacyManifest.items=[]
            }
        }

        guard let d=UserDefaults.standard.data(forKey:activationKey(event,day:selectedDay)),
              let a=try? JSONDecoder().decode(V80MediaActivation.self,from:d),
              FileManager.default.fileExists(atPath:a.folderPath) else {
            activation=nil;items=[];detectedCards=[];registeredCardLabels=[]
            wlanCameraActive=false;wlanCameraName="";wlanCameraBars=0;wlanCameraQuality="";wlanCameraDetail=""
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
        status="Tagesalbum \(selectedDay) aktiv. SD-Karten können A/B/C/D/E zugeordnet werden."
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
            let archive=folder.appendingPathComponent("Archiv",isDirectory:true)
            try fm.createDirectory(at:archive.appendingPathComponent("Produziert",isDirectory:true),withIntermediateDirectories:true)
            try fm.createDirectory(at:archive.appendingPathComponent("Fehler",isDirectory:true),withIntermediateDirectories:true)
            try fm.createDirectory(at:archive.appendingPathComponent("Abgegeben",isDirectory:true),withIntermediateDirectories:true)
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

    func revealArchiveFolder() {
        guard let a=activation else{return}
        let archive=URL(fileURLWithPath:a.folderPath,isDirectory:true).appendingPathComponent("Archiv",isDirectory:true)
        try? FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true)
        NSWorkspace.shared.open(archive)
    }

    func reveal(card:V80DetectedCard) {
        let url=URL(fileURLWithPath:card.volumePath,isDirectory:true)
        NSWorkspace.shared.open(url)
    }

    func showExternalMediaOnDesktop() {
        Task.detached(priority:.utility) {
            let settings=[
                ("ShowExternalHardDrivesOnDesktop","true"),
                ("ShowRemovableMediaOnDesktop","true")
            ]
            var ok=true
            for (key,value) in settings {
                let p=Process()
                p.executableURL=URL(fileURLWithPath:"/usr/bin/defaults")
                p.arguments=["write","com.apple.finder",key,"-bool",value]
                do {
                    try p.run();p.waitUntilExit()
                    if p.terminationStatus != 0 { ok=false }
                } catch { ok=false }
            }
            if ok {
                let p=Process()
                p.executableURL=URL(fileURLWithPath:"/usr/bin/killall")
                p.arguments=["-HUP","Finder"]
                try? p.run();p.waitUntilExit()
            }
            let success=ok
            await MainActor.run {
                self.status = success
                    ? "Finder zeigt externe/SD-Medien jetzt auf dem Desktop. Karte kann gleichzeitig in FTS und im Finder verwendet werden."
                    : "Finder-Einstellung konnte nicht automatisch geändert werden. Karte kann weiterhin über „Im Finder öffnen“ geöffnet werden."
            }
        }
    }

    func register(card: V80DetectedCard, label: String, event: EventRow, replaceExisting: Bool = false) async {
        guard let a=activation else{return}
        let clean=label.uppercased().trimmingCharacters(in:.whitespacesAndNewlines)
        guard ["A","B","C","D","E"].contains(clean) else {
            status="Kartenname muss A, B, C, D oder E sein.";return
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

    func release(card: V80DetectedCard, event: EventRow) async {
        guard let a=activation,let marker=card.marker else{return}
        scanning=true
        defer{scanning=false}
        do {
            let result=try await Task.detached(priority:.utility) {
                try Self.releaseCardSync(card:card,marker:marker,eventToken:event.event_token,activation:a)
            }.value
            items=result.items.sorted{$0.importedAt>$1.importedAt}
            detectedCards=result.cards
            registeredCardLabels=result.labels
            status="Karte \(marker.label) wurde freigegeben. Sie ist wieder eine normale SD-/USB-Karte; importierte Fotos bleiben im lokalen Archiv."
        } catch {
            status="Karte konnte nicht freigegeben werden: \(error.localizedDescription)"
        }
    }

    func hideFromProgram(_ item:V80MediaItem) {
        guard let a=activation,item.visibleInPrinter else{return}
        do {
            try Self.setWorkflowSync(folderPath:a.folderPath,mediaIDs:Set([item.id]),status:.hidden,moveDesignedFile:false)
            items.removeAll{$0.id==item.id}
            status="\(item.originalName) aus der Printer-Ansicht entfernt. Dateien und Original bleiben auf dem Mac erhalten."
        } catch {
            status="Foto konnte nicht aus der Ansicht entfernt werden: \(error.localizedDescription)"
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
            let designed=await ensureDesignedCopies(event:event,activation:a,items:r.items)
            let wifiSignal=await Task.detached(priority:.utility) {
                V80MacSpooler.wifiSignalStatus()
            }.value
            items=designed.items.sorted{$0.importedAt>$1.importedAt}
            updateWLANCameraStatus(items:designed.items,signal:wifiSignal)
            detectedCards=r.cards
            registeredCardLabels=r.labels
            lastImportedCount=r.newCount
            if designed.failed>0 {
                status="\(r.newCount) neue Fotos übernommen · \(designed.failed) Design-Datei(en) konnten nicht erstellt werden."
            } else if r.newCount>0 || designed.created>0 {
                status="\(r.newCount) neue Foto\(r.newCount==1 ? "" : "s") übernommen · \(designed.created) Druckdesign\(designed.created==1 ? "" : "s") erstellt."
            } else if r.cards.contains(where:{$0.marker==nil}) {
                status="Unbekannte SD-Karte erkannt. Erst A/B/C/D/E zuordnen – noch kein Import."
            } else {
                status="Aktuell · keine neuen Fotos."
            }
        } catch {
            status="Importprüfung: \(error.localizedDescription)"
        }
    }

    private func updateWLANCameraStatus(items:[V80MediaItem],signal:(bars:Int,label:String,detail:String)) {
        let wifiItems=items
            .filter{$0.sourceType.uppercased()=="WIFI"}
            .sorted{$0.importedAt>$1.importedAt}
        guard let latest=wifiItems.first,
              Date().timeIntervalSince(latest.importedAt) <= 90 else {
            wlanCameraActive=false
            wlanCameraName=""
            wlanCameraBars=0
            wlanCameraQuality=""
            wlanCameraDetail=""
            return
        }
        wlanCameraActive=true
        wlanCameraName=cameraDisplayName(latest.cameraID)
        wlanCameraBars=max(1,signal.bars)
        wlanCameraQuality=signal.bars>0 ? signal.label : "Transfer aktiv"
        wlanCameraDetail=signal.detail
    }

    private func cameraDisplayName(_ raw:String?) -> String {
        guard let raw,!raw.isEmpty else{return "WLAN-Kamera"}
        let parts=raw.split(separator:"·").map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}
        if parts.count>=2 {
            let make=parts[0]
            let model=parts[1]
            if model.lowercased().contains(make.lowercased()) { return model }
            return "\(make) \(model)"
        }
        return parts.first ?? "WLAN-Kamera"
    }

    private func ensureDesignedCopies(event:EventRow,activation:V80MediaActivation,items:[V80MediaItem]) async -> (items:[V80MediaItem],created:Int,failed:Int) {
        let fm=FileManager.default
        let signature=designSignature(event)
        let readyDir=URL(fileURLWithPath:activation.folderPath,isDirectory:true).appendingPathComponent("Druckbereit",isDirectory:true)
        try? fm.createDirectory(at:readyDir,withIntermediateDirectories:true)

        var out=items
        var created=0
        var failed=0

        for i in out.indices {
            guard out[i].visibleInPrinter else{continue}
            let existing=out[i].designedPath
            if out[i].designSignature==signature,
               let existing,
               fm.fileExists(atPath:existing) {
                continue
            }

            do {
                let rendered=try await ProductionRendererV76.renderedImage(sourceURL:URL(fileURLWithPath:out[i].importedPath),event:event)
                let stem=URL(fileURLWithPath:out[i].originalName).deletingPathExtension().lastPathComponent
                let safeStem=sanitize(stem)
                let fileName="\(out[i].sourceLabel)-\(safeStem)-\(String(out[i].sha256.prefix(10))).jpg"
                let dest=readyDir.appendingPathComponent(fileName)
                guard let tiff=rendered.tiffRepresentation,
                      let rep=NSBitmapImageRep(data:tiff),
                      let jpg=rep.representation(using:.jpeg,properties:[.compressionFactor:0.96]) else {
                    throw NSError(domain:"FTSPrinter",code:190,userInfo:[NSLocalizedDescriptionKey:"Druckdesign konnte nicht als JPEG gespeichert werden."])
                }
                try jpg.write(to:dest,options:.atomic)
                out[i]=V80MediaItem(
                    id:out[i].id,sha256:out[i].sha256,sourcePath:out[i].sourcePath,importedPath:out[i].importedPath,
                    designedPath:dest.path,designSignature:signature,
                    originalName:out[i].originalName,sourceType:out[i].sourceType,sourceLabel:out[i].sourceLabel,
                    cardUUID:out[i].cardUUID,cameraID:out[i].cameraID,importedAt:out[i].importedAt,
                    workflowStatus:out[i].workflowStatus,workflowUpdatedAt:out[i].workflowUpdatedAt
                )
                created += 1
            } catch {
                failed += 1
            }
        }

        if created>0 {
            do {
                var manifest=try Self.loadManifestSync(activation)
                let map=Dictionary(uniqueKeysWithValues:out.map{($0.id,$0)})
                manifest.items=manifest.items.map{map[$0.id] ?? $0}
                try Self.saveManifestSync(manifest,activation)
            } catch {
                failed += 1
            }
        }
        return (out,created,failed)
    }

    private func designSignature(_ event:EventRow)->String {
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.sortedKeys]
        var hasher=SHA256()
        func add(_ text:String?) {
            hasher.update(data:Data((text ?? "").utf8))
            hasher.update(data:Data([0]))
        }
        func addJSON(_ value:JSONValue?) {
            if let value,let data=try? encoder.encode(value) { hasher.update(data:data) }
            hasher.update(data:Data([0]))
        }
        add(event.event_title);add(event.subtitle);add(event.overlay_text);add(event.event_date)
        add(event.accent);add(event.photo_branding)
        addJSON(event.studio_config);addJSON(event.logo_items);addJSON(event.decoration_items)
        return hasher.finalize().map{String(format:"%02x",$0)}.joined()
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

        var manifest=try loadManifestSync(activation)
        var registry=loadCardRegistry(activation)
        let existingRegistryIDs=registry.cards.filter{$0.value.eventToken==eventToken && $0.value.label==label}.map{$0.key}
        let existingIDs=manifest.baselines.filter{$0.value.label==label}.map{$0.key}
        if (!existingRegistryIDs.isEmpty || !existingIDs.isEmpty) && !replaceExisting {
            throw NSError(domain:"FTSPrinter",code:101,userInfo:[NSLocalizedDescriptionKey:"Karte \(label) ist für dieses Event bereits registriert. Zum Ersetzen ausdrücklich „\(label) ersetzen“ wählen."])
        }
        if replaceExisting {
            let oldMarkers=registry.cards.values.filter{$0.eventToken==eventToken && $0.label==label}
            let oldUUIDs=Set(oldMarkers.map{$0.cardUUID})
            for id in existingIDs { manifest.baselines.removeValue(forKey:id) }
            for id in existingRegistryIDs {
                registry.releasedTechnicalIDs=(registry.releasedTechnicalIDs ?? []).union([id])
                registry.cards.removeValue(forKey:id)
            }
            if var signatures=registry.signatures {
                let oldSignatures=signatures.filter{$0.value.eventToken==eventToken && $0.value.label==label}.map{$0.key}
                for signature in oldSignatures {
                    registry.releasedSignatures=(registry.releasedSignatures ?? []).union([signature])
                    signatures.removeValue(forKey:signature)
                }
                registry.signatures=signatures
            }
            if !oldUUIDs.isEmpty {
                let baselineKeys=manifest.baselines.keys.filter{oldUUIDs.contains($0)}
                for key in baselineKeys { manifest.baselines.removeValue(forKey:key) }
            }
        }

        let cardUUID=UUID().uuidString
        let marker=V80CardMarker(version:81,eventToken:eventToken,cardUUID:cardUUID,label:label,registeredAt:Date())
        // Important: never write registration metadata to the camera card.
        // Cards stay read-only from FTS; registration is persisted on the Mac.
        registry.cards[card.technicalID]=marker
        registry.releasedTechnicalIDs?.remove(card.technicalID)
        if let signature=cardSignature(volume) {
            var signatures=registry.signatures ?? [:]
            signatures[signature]=marker
            registry.signatures=signatures
            registry.releasedSignatures?.remove(signature)
        }
        try saveCardRegistry(registry,activation)

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
        let cards=detectCardsSync(eventToken:eventToken,activation:activation)
        return (manifest.items,cards,keys.count,Set(manifest.baselines.values.map{$0.label}))
    }

    nonisolated private static func scanSync(eventToken:String,activation:V80MediaActivation) throws -> (items:[V80MediaItem],cards:[V80DetectedCard],newCount:Int,labels:Set<String>) {
        let fm=FileManager.default
        var manifest=try loadManifestSync(activation)
        // Event-wide duplicate protection: a photo imported on another event day must
        // never be copied again when the same registered card is reinserted.
        var hashes=importedHashesAcrossEvent(activation)
        hashes.formUnion(manifest.items.map(\.sha256))
        var localLedger=manifest.importedHashes ?? []
        localLedger.formUnion(manifest.items.map(\.sha256))
        manifest.importedHashes=localLedger
        hashes.formUnion(localLedger)
        var newCount=0
        var registry=loadCardRegistry(activation)
        let cards=detectCardsSync(eventToken:eventToken,activation:activation)

        for card in cards {
            guard let marker=card.marker,marker.eventToken==eventToken else{continue}
            if registry.cards[card.technicalID] == nil {
                registry.cards[card.technicalID]=marker
                if let signature=cardSignature(URL(fileURLWithPath:card.volumePath,isDirectory:true)) {
                    var signatures=registry.signatures ?? [:]
                    signatures[signature]=marker
                    registry.signatures=signatures
                }
                try? saveCardRegistry(registry,activation)
            }
            let volume=URL(fileURLWithPath:card.volumePath,isDirectory:true)
            let recoveringBaseline = manifest.baselines[marker.cardUUID] == nil
            var baseline = manifest.baselines[marker.cardUUID] ?? V80CardBaseline(
                cardUUID:marker.cardUUID,label:marker.label,knownSourceKeys:[],
                knownFingerprints:[:],createdAt:Date()
            )

            for file in mediaFiles(on:volume) {
                guard let key=sourceKey(file,root:volume) else{continue}
                // Wait until the camera/OS has finished writing the file.
                let rv=try? file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
                if let mod=rv?.contentModificationDate {
                    let age=Date().timeIntervalSince(mod)
                    if age >= 0 && age < 1.5 { continue }
                }
                guard (rv?.fileSize ?? 0)>0 else{continue}

                let knownKey=baseline.knownSourceKeys.contains(key)
                let oldHash=baseline.knownFingerprints?[key]
                let hash=try sha256(file)
                let bytesChanged=knownKey && oldHash != nil && oldHash != hash

                baseline.knownSourceKeys.insert(key)
                if baseline.knownFingerprints == nil { baseline.knownFingerprints=[:] }
                baseline.knownFingerprints?[key]=hash

                // "Known" is not the same as "already copied": Build 96 could mark a
                // whole card as known when a day baseline was missing. The durable
                // imported-hash ledger is authoritative for duplicate prevention.
                if hashes.contains(hash){continue}

                // A never-imported file that clearly predates card registration is old
                // stock. A file newer than registration must be recovered/imported even
                // when an older build already put it into knownSourceKeys.
                if !bytesChanged,
                   let mod=rv?.contentModificationDate,
                   mod <= marker.registeredAt.addingTimeInterval(2.0) {
                    continue
                }

                let folder=URL(fileURLWithPath:activation.folderPath)
                    .appendingPathComponent("Kamera Original",isDirectory:true)
                    .appendingPathComponent("SD \(marker.label)",isDirectory:true)
                try fm.createDirectory(at:folder,withIntermediateDirectories:true)
                let dest=uniqueDestination(folder:folder,name:file.lastPathComponent)
                try fm.copyItem(at:file,to:dest)
                let item=V80MediaItem(
                    id:hash,sha256:hash,sourcePath:file.path,importedPath:dest.path,
                    designedPath:nil,designSignature:nil,
                    originalName:file.lastPathComponent,sourceType:"SD",sourceLabel:marker.label,
                    cardUUID:marker.cardUUID,cameraID:cameraIdentity(file),importedAt:Date()
                )
                manifest.items.append(item)
                var ledger=manifest.importedHashes ?? []
                ledger.insert(hash)
                manifest.importedHashes=ledger
                hashes.insert(hash);newCount+=1
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
            if let mod=rv?.contentModificationDate {
                    let age=Date().timeIntervalSince(mod)
                    if age >= 0 && age < 1.5 { continue }
                }
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
                designedPath:nil,designSignature:nil,
                originalName:file.lastPathComponent,sourceType:"WIFI",sourceLabel:"W",
                cardUUID:nil,cameraID:cameraIdentity(file),importedAt:Date()
            )
            manifest.items.append(item)
            var ledger=manifest.importedHashes ?? []
            ledger.insert(hash)
            manifest.importedHashes=ledger
            hashes.insert(hash);newCount+=1
        }

        try saveManifestSync(manifest,activation)
        return (manifest.items,cards,newCount,Set(manifest.baselines.values.map{$0.label}))
    }

    nonisolated private static func releaseCardSync(card:V80DetectedCard,marker:V80CardMarker,eventToken:String,activation:V80MediaActivation) throws -> (items:[V80MediaItem],cards:[V80DetectedCard],labels:Set<String>) {
        let fm=FileManager.default
        let volume=URL(fileURLWithPath:card.volumePath,isDirectory:true)
        var registry=loadCardRegistry(activation)

        let cardIDs=registry.cards.filter{$0.value.eventToken==eventToken && $0.value.cardUUID==marker.cardUUID}.map{$0.key}
        for id in cardIDs {
            registry.cards.removeValue(forKey:id)
            registry.releasedTechnicalIDs=(registry.releasedTechnicalIDs ?? []).union([id])
        }
        if var signatures=registry.signatures {
            let signatureIDs=signatures.filter{$0.value.eventToken==eventToken && $0.value.cardUUID==marker.cardUUID}.map{$0.key}
            for signature in signatureIDs {
                signatures.removeValue(forKey:signature)
                registry.releasedSignatures=(registry.releasedSignatures ?? []).union([signature])
            }
            registry.signatures=signatures
        }
        registry.releasedTechnicalIDs=(registry.releasedTechnicalIDs ?? []).union([card.technicalID])
        if let signature=cardSignature(volume) {
            registry.releasedSignatures=(registry.releasedSignatures ?? []).union([signature])
        }
        try saveCardRegistry(registry,activation)

        // Older FTS builds wrote this hidden compatibility marker onto some cards.
        // Remove it only when the medium is writable; the card's photos are never modified.
        let legacyMarker=volume.appendingPathComponent(".fts-printer-card-v80.json")
        if card.writable,fm.fileExists(atPath:legacyMarker.path) {
            try? fm.removeItem(at:legacyMarker)
        }

        // Baselines are per day; release the same physical card across the whole event.
        let eventRoot=URL(fileURLWithPath:activation.folderPath,isDirectory:true).deletingLastPathComponent()
        let children=(try? fm.contentsOfDirectory(at:eventRoot,includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles])) ?? []
        for child in children {
            guard (try? child.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true else{continue}
            let manifestURL=child.appendingPathComponent(".fts-media-manifest-v80.json")
            guard let data=try? Data(contentsOf:manifestURL),
                  var manifest=try? JSONDecoder().decode(V80MediaManifest.self,from:data) else{continue}
            manifest.baselines.removeValue(forKey:marker.cardUUID)
            try? JSONEncoder().encode(manifest).write(to:manifestURL,options:.atomic)
        }

        let current=try loadManifestSync(activation)
        let cards=detectCardsSync(eventToken:eventToken,activation:activation)
        return (current.items,cards,Set(current.baselines.values.map{$0.label}))
    }

    nonisolated static func setWorkflowSync(folderPath:String,mediaIDs:Set<String>,status:V80MediaWorkflow,moveDesignedFile:Bool) throws {
        guard !mediaIDs.isEmpty else{return}
        let fm=FileManager.default
        let folder=URL(fileURLWithPath:folderPath,isDirectory:true)
        let manifestURL=folder.appendingPathComponent(".fts-media-manifest-v80.json")
        guard let data=try? Data(contentsOf:manifestURL),
              var manifest=try? JSONDecoder().decode(V80MediaManifest.self,from:data) else{return}

        var destination:URL?=nil
        if moveDesignedFile {
            let archive=folder.appendingPathComponent("Archiv",isDirectory:true)
            switch status {
            case .produced: destination=archive.appendingPathComponent("Produziert",isDirectory:true)
            case .error: destination=archive.appendingPathComponent("Fehler",isDirectory:true)
            case .delivered: destination=archive.appendingPathComponent("Abgegeben",isDirectory:true)
            default: destination=nil
            }
            if let destination { try fm.createDirectory(at:destination,withIntermediateDirectories:true) }
        }

        for i in manifest.items.indices where mediaIDs.contains(manifest.items[i].id) {
            if let destination,
               let oldPath=manifest.items[i].designedPath,!oldPath.isEmpty {
                let old=URL(fileURLWithPath:oldPath)
                if fm.fileExists(atPath:old.path),old.deletingLastPathComponent().path != destination.path {
                    let dest=uniqueDestination(folder:destination,name:old.lastPathComponent)
                    try fm.moveItem(at:old,to:dest)
                    manifest.items[i].designedPath=dest.path
                }
            }
            manifest.items[i].workflowStatus=status
            manifest.items[i].workflowUpdatedAt=Date()
        }
        try JSONEncoder().encode(manifest).write(to:manifestURL,options:.atomic)
    }

    nonisolated private static func detectCardsSync(eventToken:String,activation:V80MediaActivation) -> [V80DetectedCard] {
        let fm=FileManager.default
        let registry=loadCardRegistry(activation)
        let keys:Set<URLResourceKey>=[.volumeIsRemovableKey,.volumeIsEjectableKey,.volumeIsInternalKey,.volumeNameKey,.volumeIdentifierKey,.isWritableKey]
        let volumes=fm.mountedVolumeURLs(includingResourceValuesForKeys:Array(keys),options:[.skipHiddenVolumes]) ?? []
        var out:[V80DetectedCard]=[]
        for v in volumes {
            let rv=try? v.resourceValues(forKeys:keys)
            let removable=rv?.volumeIsRemovable==true || rv?.volumeIsEjectable==true
            if rv?.volumeIsInternal==true{continue}
            let dcim=v.appendingPathComponent("DCIM",isDirectory:true)
            let cameraMedia=removable || fm.fileExists(atPath:dcim.path)
            if !cameraMedia{continue}
            let name=rv?.volumeName ?? v.lastPathComponent
            let tid=rv?.volumeIdentifier.map{String(describing:$0)} ?? v.path
            let markerURL=v.appendingPathComponent(".fts-printer-card-v80.json")
            let signature=cardSignature(v)
            let explicitlyReleased=(registry.releasedTechnicalIDs?.contains(tid) == true)
                || (signature != nil && registry.releasedSignatures?.contains(signature!) == true)
            var marker=explicitlyReleased ? nil : registry.cards[tid]
            if marker?.eventToken != eventToken { marker=nil }
            if marker == nil,!explicitlyReleased,
               let signature,
               let matched=registry.signatures?[signature],
               matched.eventToken==eventToken {
                marker=matched
            }
            if marker == nil,!explicitlyReleased,
               let d=try? Data(contentsOf:markerURL),
               let legacy=try? JSONDecoder().decode(V80CardMarker.self,from:d),
               legacy.eventToken==eventToken {
                // Legacy compatibility only. A released card is never re-claimed by this file.
                marker=legacy
            }
            out.append(V80DetectedCard(
                id:tid,volumePath:v.path,volumeName:name,technicalID:tid,marker:marker,
                writable:rv?.isWritable ?? fm.isWritableFile(atPath:v.path)
            ))
        }
        return out.sorted{$0.volumeName.localizedCaseInsensitiveCompare($1.volumeName) == .orderedAscending}
    }

    nonisolated private static func cardSignature(_ volume:URL) -> String? {
        let fm=FileManager.default
        let dcim=volume.appendingPathComponent("DCIM",isDirectory:true)
        let root=fm.fileExists(atPath:dcim.path) ? dcim : volume
        guard let en=fm.enumerator(
            at:root,
            includingPropertiesForKeys:[.isRegularFileKey,.contentModificationDateKey,.fileSizeKey],
            options:[.skipsHiddenFiles,.skipsPackageDescendants]
        ) else{return nil}
        var seeds:[String]=[]
        for case let file as URL in en {
            guard supported(file),
                  (try? file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true,
                  let key=sourceKey(file,root:volume) else{continue}
            seeds.append(key)
            if seeds.count>=8{break}
        }
        guard !seeds.isEmpty else{return nil}
        let raw=seeds.sorted().prefix(4).joined(separator:"\n")
        let digest=SHA256.hash(data:Data(raw.utf8))
        return digest.map{String(format:"%02x",$0)}.joined()
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
        return best.values.sorted{$0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending}
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

    nonisolated private static func cardRegistryURL(_ activation:V80MediaActivation) -> URL {
        URL(fileURLWithPath:activation.folderPath,isDirectory:true)
            .deletingLastPathComponent()
            .appendingPathComponent(".fts-card-registry-v81.json")
    }

    nonisolated private static func loadCardRegistry(_ activation:V80MediaActivation) -> V80LocalCardRegistry {
        let url=cardRegistryURL(activation)
        guard let data=try? Data(contentsOf:url),
              let registry=try? JSONDecoder().decode(V80LocalCardRegistry.self,from:data) else {
            return V80LocalCardRegistry()
        }
        return registry
    }

    nonisolated private static func saveCardRegistry(_ registry:V80LocalCardRegistry,_ activation:V80MediaActivation) throws {
        try JSONEncoder().encode(registry).write(to:cardRegistryURL(activation),options:.atomic)
    }

    nonisolated private static func importedHashesAcrossEvent(_ activation:V80MediaActivation) -> Set<String> {
        let fm=FileManager.default
        let dayFolder=URL(fileURLWithPath:activation.folderPath,isDirectory:true)
        let eventRoot=dayFolder.deletingLastPathComponent()
        let children=(try? fm.contentsOfDirectory(
            at:eventRoot,
            includingPropertiesForKeys:[.isDirectoryKey],
            options:[.skipsHiddenFiles]
        )) ?? []
        var hashes=Set<String>()
        for child in children {
            let rv=try? child.resourceValues(forKeys:[.isDirectoryKey])
            guard rv?.isDirectory==true else{continue}
            let u=child.appendingPathComponent(".fts-media-manifest-v80.json")
            guard let data=try? Data(contentsOf:u),
                  let m=try? JSONDecoder().decode(V80MediaManifest.self,from:data) else{continue}
            hashes.formUnion(m.items.map(\.sha256))
            hashes.formUnion(m.importedHashes ?? [])
        }
        return hashes
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
