import SwiftUI
import AppKit
import Foundation
import CryptoKit

// MARK: - Production queue models

struct V80WorkUnit: Codable, Identifiable, Hashable {
    let unit_id: String
    let order_id: String
    let order_item_id: String
    let photo_id: String?
    let designed_path: String
    let copy_index: Int
    let item_quantity: Int
    let order_quantity: Int
    let pickup_code: String
    let unit_status: String
    let printer_key: String?
    let claimed_at: String?
    let started_at: String?
    let printed_at: String?
    let last_error: String?
    let order_created_at: String?
    var id: String { unit_id }
}

struct V80PrinterNode: Codable, Identifiable, Hashable {
    let printer_key: String
    let display_name: String
    let state: String
    let eta_seconds: Int?
    let current_unit_id: String?
    let device_label: String?
    let last_error: String?
    let last_seen_at: String?
    var id: String { printer_key }
}

struct V80Pickup: Codable, Identifiable, Hashable {
    let kind: String
    let id: String
    let customer_code: String
    let quantity: Int
    let ready_at: String?
    let receipt_number: String?
    let event_title: String?
    let source_type: String?
}

struct V80ArchiveRow: Codable, Identifiable, Hashable {
    let kind: String
    let id: String
    let customer_code: String
    let quantity: Int
    let archived_at: String?
    let receipt_number: String?
    let source_type: String?
}

struct V80Claim: Codable, Hashable {
    let ok: Bool?
    let empty: Bool?
    let busy: Bool?
    let error: String?
    let unit_id: String?
    let order_id: String?
    let order_item_id: String?
    let photo_id: String?
    let designed_path: String?
    let copy_index: Int?
    let pickup_code: String?
    let order_quantity: Int?
    let printer_key: String?
    let claim_expires_at: String?
}

struct V80FinishResult: Codable, Hashable {
    let ok: Bool?
    let order_completed: Bool?
    let remaining: Int?
    let unit_id: String?
    let order_id: String?
    let error: String?
}

struct V80LocalJobCreate: Codable, Hashable {
    let ok: Bool?
    let job_id: String?
    let customer_code: String?
    let status: String?
    let quantity: Int?
}

struct V92DayResetResult: Codable, Hashable {
    let ok: Bool?
    let reason: String?
    let message: String?
    let event_day: String?
    let next_number: Int?
}

struct V81Consumable: Codable, Identifiable, Hashable {
    let printer_key: String
    let paper_remaining: Int?
    let film_remaining: Int?
    let paper_loaded_at: String?
    let film_loaded_at: String?
    let last_print_at: String?
    let updated_at: String?
    var id:String { printer_key }
}

struct V80Release: Codable, Hashable {
    let version: String
    let build_number: Int
    let external_url: String?
    let storage_path: String?
    let sha256: String?
    let notes: String?
    let mandatory: Bool?
    let min_supported_version: String?
    let min_os_version: String?
    let published_at: String?
}

struct LocalPrinterSlot: Identifiable, Hashable {
    let name: String
    var enabled: Bool
    var state: String
    var eta: Int
    var currentUnit: String?
    var lastError: String?
    var id: String { name }
}

struct V80LocalPrintUnit: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case waiting, printing, printed, uncertain, cancelled }
    let id: UUID
    let jobID: UUID
    let customerCode: String
    let mediaID: String
    let imagePath: String
    let preRendered: Bool?
    let originalName: String
    let copyIndex: Int
    var status: Status
    var printerName: String?
    var startedAt: Date?
    var printedAt: Date?
    var lastError: String?
    var componentSynced: Bool?
}

struct V80LocalPrintJob: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case waiting, printing, readyForPickup, archived, cancelled, uncertain }
    let id: UUID
    let eventToken: String
    let eventDay: String?
    var customerCode: String
    let sourceType: String
    let sourceLabel: String
    let createdAt: Date
    var status: Status
    var units: [V80LocalPrintUnit]
    var idString: String { id.uuidString }
}

struct V80LocalQueueFile: Codable {
    var jobs: [V80LocalPrintJob] = []
}

enum V80QueueStore {
    static func url(folderPath: String) -> URL {
        URL(fileURLWithPath: folderPath).appendingPathComponent(".fts-local-print-queue-v80.json")
    }

    static func load(folderPath: String) -> V80LocalQueueFile {
        let u = url(folderPath: folderPath)
        guard let d = try? Data(contentsOf: u),
              var q = try? JSONDecoder().decode(V80LocalQueueFile.self, from: d) else { return V80LocalQueueFile() }
        // A crash while a unit was physically printing is deliberately not auto-reprinted.
        for ji in q.jobs.indices {
            for ui in q.jobs[ji].units.indices where q.jobs[ji].units[ui].status == .printing {
                q.jobs[ji].units[ui].status = .uncertain
                q.jobs[ji].units[ui].lastError = "App wurde während des Drucks beendet. Ausdruck prüfen."
            }
            if q.jobs[ji].units.contains(where: { $0.status == .uncertain }) {
                q.jobs[ji].status = .uncertain
            }
        }
        return q
    }

    static func save(_ queue: V80LocalQueueFile, folderPath: String) throws {
        let d = try JSONEncoder().encode(queue)
        try d.write(to: url(folderPath: folderPath), options: .atomic)
    }
}

// MARK: - Borderless silent printing

final class V80BorderlessPrintView: NSView {
    let image: NSImage
    init(image: NSImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        let iw = max(image.size.width, 1), ih = max(image.size.height, 1)
        // CP1500 borderless safety bleed: fill the nominal 10×15 surface and
        // overscan 1.8% so driver/paper tolerances cannot expose a white hairline.
        let scale = max(bounds.width / iw, bounds.height / ih) * 1.018
        let s = NSSize(width: iw * scale, height: ih * scale)
        let r = NSRect(
            x: (bounds.width - s.width) / 2,
            y: (bounds.height - s.height) / 2,
            width: s.width,
            height: s.height
        )
        image.draw(in: r, from: .zero, operation: .copy, fraction: 1)
    }
}

enum V80MacSpooler {
    // CP1500 postcard prints are around the low-40-second range once printing begins.
    // Never declare a photo finished merely because the CUPS queue clears early.
    static let minimumPhysicalSeconds: TimeInterval = 42
    static let defaultSeconds: TimeInterval = 44

    static func installedPrinterNames() async -> [String] {
        let configured = await MainActor.run {
            NSPrinter.printerNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        // CUPS/ioreg can occasionally pause while a network printer is changing state.
        // Run those probes off the UI thread so the Mac cursor never beachballs the app.
        return await Task.detached(priority:.utility) {
            filterConfiguredPrinters(configured)
        }.value
    }

    private static func filterConfiguredPrinters(_ configured:[String]) -> [String] {
        var names=configured

        // If a Canon SELPHY is connected directly by USB, prefer that physical path
        // and suppress stale Wi-Fi/AirPrint duplicates for the same SELPHY model.
        let meta=Dictionary(uniqueKeysWithValues:names.map { name in
            (name,(deviceURI(printerName:name),printerDetails(printerName:name)))
        })
        let usbSELPHYPresence=usbSELPHYPresent()
        names=names.filter { name in
            let info=meta[name] ?? ("","")
            let hay=(name+" "+info.0+" "+info.1).lowercased()
            let isUSBSELPHY=info.0.lowercased().hasPrefix("usb://") && (hay.contains("selphy") || hay.contains("cp1500"))
            return !(isUSBSELPHY && !usbSELPHYPresence)
        }

        let hasUSBSELPHY=usbSELPHYPresence && names.contains { name in
            let info=meta[name] ?? ("","")
            let hay=(name+" "+info.0+" "+info.1).lowercased()
            return info.0.lowercased().hasPrefix("usb://") && (hay.contains("selphy") || hay.contains("cp1500"))
        }
        if hasUSBSELPHY {
            names=names.filter { name in
                let info=meta[name] ?? ("","")
                let uri=info.0.lowercased()
                let hay=(name+" "+info.0+" "+info.1).lowercased()
                let isSELPHY=hay.contains("selphy") || hay.contains("cp1500")
                let isNetwork=uri.hasPrefix("ipp://") || uri.hasPrefix("ipps://") || uri.hasPrefix("dnssd://") || uri.hasPrefix("lpd://") || uri.hasPrefix("socket://")
                return !(isSELPHY && isNetwork)
            }
        }
        return names
    }

    private static func usbSELPHYPresent()->Bool {
        guard let text=runProcess("/usr/sbin/ioreg",["-p","IOUSB","-l","-w","0"],timeout:1.5) else {
            // If hardware enumeration itself fails, do not hide a valid configured queue.
            return true
        }
        let lower=text.lowercased()
        return lower.contains("selphy") || lower.contains("cp1500")
    }

    private static func deviceURI(printerName:String)->String {
        runLPStat(["-v",printerName])
    }

    private static func printerDetails(printerName:String)->String {
        runLPStat(["-l","-p",printerName])
    }

    private static func runLPStat(_ arguments:[String])->String {
        runProcess("/usr/bin/lpstat",arguments,timeout:1.5)?
            .trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
    }

    private static func runProcess(_ executable:String,_ arguments:[String],timeout:TimeInterval)->String? {
        let p=Process()
        p.executableURL=URL(fileURLWithPath:executable)
        p.arguments=arguments
        let out=Pipe()
        p.standardOutput=out
        p.standardError=Pipe()
        do {
            try p.run()
            let deadline=Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval:0.03)
            }
            if p.isRunning {
                p.terminate()
                return nil
            }
            guard p.terminationStatus==0 else{return nil}
            let d=out.fileHandleForReading.readDataToEndOfFile()
            return String(data:d,encoding:.utf8)
        } catch {
            return nil
        }
    }

    @MainActor
    static func submit(image: NSImage, printerName: String, title: String) throws -> String {
        guard NSPrinter(name: printerName) != nil else {
            throw NSError(domain: "FTSPrinter", code: 80, userInfo: [NSLocalizedDescriptionKey: "Drucker \(printerName) ist nicht mehr installiert."])
        }

        let landscape = image.size.width > image.size.height
        // SELPHY postcard media is 100 × 148 mm. Create an exact PDF page and let
        // CUPS submit that immutable page. /usr/bin/lp returns a real CUPS request
        // id that we can track before declaring a print finished.
        let portrait = NSSize(width: 283.46, height: 419.53)
        let paper = landscape ? NSSize(width: portrait.height, height: portrait.width) : portrait
        let view = V80BorderlessPrintView(image: image, size: paper)
        let pdf = view.dataWithPDF(inside: view.bounds)

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts-print-" + UUID().uuidString + ".pdf")
        try pdf.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
        p.arguments = ["-d", printerName, "-t", title, temp.path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        do {
            try p.run()
            let deadline = Date().addingTimeInterval(12)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.03)
            }
            if p.isRunning {
                p.terminate()
                throw NSError(domain:"FTSPrinter",code:181,userInfo:[NSLocalizedDescriptionKey:"macOS-Drucksystem antwortet beim Senden nicht."])
            }
            let stdout = String(data:out.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
            let stderr = String(data:err.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
            guard p.terminationStatus == 0 else {
                let msg = stderr.trimmingCharacters(in:.whitespacesAndNewlines)
                throw NSError(domain:"FTSPrinter",code:182,userInfo:[NSLocalizedDescriptionKey:msg.isEmpty ? "CUPS hat den Druckauftrag abgelehnt." : msg])
            }

            let marker = "request id is "
            if let r = stdout.lowercased().range(of: marker) {
                let offset = stdout.distance(from: stdout.startIndex, to: r.upperBound)
                let originalStart = stdout.index(stdout.startIndex, offsetBy: offset)
                let tail = stdout[originalStart...]
                if let id = tail.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).first, !id.isEmpty {
                    return String(id)
                }
            }
            throw NSError(domain:"FTSPrinter",code:183,userInfo:[NSLocalizedDescriptionKey:"Druckauftrag wurde gesendet, aber macOS lieferte keine CUPS-Auftragsnummer. Nicht automatisch als gedruckt markieren."])
        } catch let e as NSError where e.domain == "FTSPrinter" {
            throw e
        } catch {
            throw NSError(domain:"FTSPrinter",code:184,userInfo:[NSLocalizedDescriptionKey:"Druckauftrag konnte nicht an CUPS übergeben werden: \(error.localizedDescription)"])
        }
    }

    static func isAccepting(printerName: String) -> Bool? {
        guard let raw=runProcess("/usr/bin/lpstat",["-a",printerName],timeout:1.5) else{return nil}
        let text=raw.lowercased()
        if text.contains("not accepting") || text.contains("disabled") { return false }
        return !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }

    static func queueHasJobs(printerName: String) -> Bool? {
        guard let raw=runProcess("/usr/bin/lpstat",["-W","not-completed","-o",printerName],timeout:1.5) else{return nil}
        return !raw.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }

    static func cupsJobState(printerName:String, requestID:String) -> (active:Bool, completed:Bool, reachable:Bool) {
        let activeText=runProcess("/usr/bin/lpstat",["-W","not-completed","-o",printerName],timeout:1.5)
        let completedText=runProcess("/usr/bin/lpstat",["-W","completed","-o",printerName],timeout:1.5)
        let reachable = activeText != nil || completedText != nil
        let needle=requestID.lowercased()
        let active=(activeText ?? "").lowercased().contains(needle)
        let completed=(completedText ?? "").lowercased().contains(needle)
        return (active,completed,reachable)
    }

    static func learnedSeconds(printerName: String) -> TimeInterval {
        let k = "fts.printer.duration.v80." + printerName
        let v = UserDefaults.standard.double(forKey: k)
        return v > 10 ? min(max(v, 30), 120) : defaultSeconds
    }

    static func rememberDuration(_ duration: TimeInterval, printerName: String) {
        guard duration >= 25, duration <= 180 else { return }
        let old = learnedSeconds(printerName: printerName)
        let blended = old * 0.7 + duration * 0.3
        UserDefaults.standard.set(blended, forKey: "fts.printer.duration.v80." + printerName)
    }

    static func waitUntilLikelyFinished(printerName: String, requestID:String, started: Date, estimated: TimeInterval) async throws {
        var sawActive = false
        var sawCompleted = false
        var sawReachable = false
        let timeout = max(estimated * 2.8, 125)

        while true {
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > timeout {
                throw NSError(domain:"FTSPrinter",code:82,userInfo:[NSLocalizedDescriptionKey:"CUPS-Auftrag \(requestID) wurde nicht sicher abgeschlossen. Ausdruck am Drucker prüfen."])
            }

            let state = await Task.detached(priority:.utility) {
                cupsJobState(printerName:printerName,requestID:requestID)
            }.value
            sawActive = sawActive || state.active
            sawCompleted = sawCompleted || state.completed
            sawReachable = sawReachable || state.reachable

            if elapsed >= minimumPhysicalSeconds {
                if sawCompleted || (sawActive && !state.active) { return }

                if elapsed >= estimated + 8 && !sawActive && !sawCompleted {
                    let why = sawReachable
                      ? "macOS hat den Auftrag nicht in der CUPS-Warteschlange bestätigt."
                      : "CUPS konnte während des Drucks nicht abgefragt werden."
                    throw NSError(domain:"FTSPrinter",code:185,userInfo:[NSLocalizedDescriptionKey:"\(why) Kein automatisches 'gedruckt'. Bitte Drucker prüfen."])
                }
            }
            try await Task.sleep(for:.seconds(2))
        }
    }
}

// MARK: - Production dispatcher and shared operational state

@MainActor
final class ProductionCore: ObservableObject {
    static let version = "1.0.8-spooler"
    static let build = 89

    @Published var workUnits: [V80WorkUnit] = []
    @Published var printerNodes: [V80PrinterNode] = []
    @Published var pickups: [V80Pickup] = []
    @Published var archived: [V80ArchiveRow] = []
    @Published var consumables: [V81Consumable] = []
    @Published var localQueue = V80LocalQueueFile()
    @Published var printerSlots: [LocalPrinterSlot] = []
    @Published var autoDispatch = UserDefaults.standard.object(forKey: "fts.autodispatch.v80") == nil ? true : UserDefaults.standard.bool(forKey: "fts.autodispatch.v80")
    @Published var queueStatus = ""
    @Published var updateRelease: V80Release?
    @Published var updateAvailable = false
    @Published var lastError: String?
    @Published var pickupActionsInFlight: Set<String> = []
    @Published var archiveActionsInFlight: Set<String> = []
    @Published var consumableActionsInFlight: Set<String> = []

    private var activePrinterTasks: [String: Task<Void, Never>] = [:]
    private var lastDispatchedLocal = false
    private var lastPrinterConnectivityCheck = Date.distantPast
    private var printerConnectivityFailures: [String:Int] = [:]
    private var loadedFolderPath = ""
    private let hostID: String = {
        let key = "fts.printer.host-id.v80"
        if let existing = UserDefaults.standard.string(forKey:key), !existing.isEmpty { return existing }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey:key)
        return created
    }()
    private let api = FTSAPI.shared

    func loadLocalQueue(folderPath: String?) {
        guard let folderPath, !folderPath.isEmpty else {
            localQueue = V80LocalQueueFile(); loadedFolderPath = ""; return
        }
        if folderPath != loadedFolderPath {
            loadedFolderPath = folderPath
            localQueue = V80QueueStore.load(folderPath: folderPath)
            try? V80QueueStore.save(localQueue, folderPath: folderPath)
        }
    }

    private func saveLocalQueue() {
        guard !loadedFolderPath.isEmpty else { return }
        do { try V80QueueStore.save(localQueue, folderPath: loadedFolderPath) }
        catch { lastError = "Lokale Druckwarteschlange konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    func clearEmptyLocalQueue() {
        guard localQueue.jobs.isEmpty else {
            lastError="Tagesalbum kann nicht geleert werden, solange lokale Druckaufträge vorhanden sind."
            return
        }
        localQueue=V80LocalQueueFile()
        saveLocalQueue()
    }

    func discoverPrinters() async {
        var names = await V80MacSpooler.installedPrinterNames()
        // Never make a printer disappear in the middle of an active transfer/print.
        for old in printerSlots where ["PREPARING","TRANSFER","PRINTING"].contains(old.state) {
            if !names.contains(old.name) { names.append(old.name) }
        }
        names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let enabled = Set(UserDefaults.standard.stringArray(forKey: "fts.enabled.printers.v80") ?? [])
        var next: [LocalPrinterSlot] = []
        for name in names {
            if let old = printerSlots.first(where: { $0.name == name }) {
                var slot = old
                slot.enabled = enabled.contains(name)
                if slot.state == "OFFLINE" {
                    slot.state = "IDLE"
                    slot.eta = 0
                    slot.currentUnit = nil
                    slot.lastError = nil
                }
                next.append(slot)
            } else {
                next.append(LocalPrinterSlot(name: name, enabled: enabled.contains(name), state: "IDLE", eta: 0, currentUnit: nil, lastError: nil))
            }
        }
        printerSlots = next
    }

    func setPrinter(_ name: String, enabled: Bool) {
        guard let i = printerSlots.firstIndex(where: { $0.name == name }) else { return }
        printerSlots[i].enabled = enabled
        let names = printerSlots.filter(\.enabled).map(\.name)
        UserDefaults.standard.set(names, forKey: "fts.enabled.printers.v80")
    }

    private func isTransientTransportMessage(_ message:String)->Bool {
        let m=message.lowercased()
        return m.contains("401") || m.contains("unauthorized") || m.contains("jwt")
            || m.contains("network") || m.contains("internet") || m.contains("connection")
            || m.contains("timed out") || m.contains("timeout") || m.contains("server")
            || m.contains("503") || m.contains("502") || m.contains("504") || m.contains("429")
    }

    func refresh(state: AppState) async {
        guard let dev = state.deviceToken, let session = state.sessionToken,
              !state.selectedEventToken.isEmpty else { return }
        do {
            async let q: [V80WorkUnit] = api.rpc("fts_printer_queue_v80", body: [
                "p_device_token":dev, "p_session_token":session, "p_event_token":state.selectedEventToken
            ])
            async let n: [V80PrinterNode] = api.rpc("fts_printer_nodes_v80", body: [
                "p_device_token":dev, "p_session_token":session, "p_event_token":state.selectedEventToken
            ])
            async let p: [V80Pickup] = api.rpc("fts_printer_pickups_v80", body: [
                "p_device_token":dev, "p_session_token":session, "p_event_token":state.selectedEventToken
            ])
            async let a: [V80ArchiveRow] = api.rpc("fts_printer_archived_v80", body: [
                "p_device_token":dev, "p_session_token":session, "p_event_token":state.selectedEventToken, "p_limit":200
            ])
            async let cc: [V81Consumable] = api.rpc("fts_printer_consumables_v81", body: [
                "p_device_token":dev, "p_session_token":session, "p_event_token":state.selectedEventToken
            ])
            let (qq,nn,pp,aa,cons) = try await (q,n,p,a,cc)
            workUnits = qq; printerNodes = nn; pickups = pp; archived = aa; consumables = cons
            if let e=lastError, isTransientTransportMessage(e) { lastError=nil }
            let waitingCount = qq.filter{$0.unit_status == "READY"}.count + localWaitingCount
            let enabled = printerSlots.filter{$0.enabled}
            let materialBlocked = waitingCount > 0 && !enabled.isEmpty && enabled.allSatisfy{ !materialReady(for:$0.name) }
            queueStatus = "\(qq.filter{$0.unit_status == "READY"}.count) Selfie-Einheiten warten · \(localWaitingCount) lokale Einheiten warten" + (materialBlocked ? " · Material nachfüllen" : "")
            await heartbeatAll(state: state)
            if autoDispatch && hasDispatchableWork { dispatchAvailable(state: state) }
        } catch {
            if !(await state.recoverAuthentication(from: error)) {
                lastError = error.localizedDescription
            }
        }
    }

    var localWaitingCount: Int {
        localQueue.jobs.flatMap(\.units).filter { $0.status == .waiting }.count
    }

    var hasDispatchableWork: Bool {
        localWaitingCount > 0 || workUnits.contains { $0.unit_status == "READY" }
    }

    private func refreshPrinterConnectivity() async {
        guard Date().timeIntervalSince(lastPrinterConnectivityCheck) >= 10 else { return }
        lastPrinterConnectivityCheck = Date()
        for slot in printerSlots where slot.enabled {
            guard activePrinterTasks[slot.name] == nil else { continue }
            guard slot.state == "IDLE" || slot.state == "OFFLINE" else { continue }
            let name=slot.name
            let accepting = await Task.detached(priority:.utility) {
                V80MacSpooler.isAccepting(printerName:name)
            }.value
            guard let accepting else { continue }
            if accepting {
                printerConnectivityFailures[name]=0
                if let i=printerSlots.firstIndex(where:{$0.name==name}), printerSlots[i].state=="OFFLINE" {
                    setSlot(name,state:"IDLE",eta:0,current:nil,error:nil)
                }
            } else {
                let failures=(printerConnectivityFailures[name] ?? 0)+1
                printerConnectivityFailures[name]=failures
                // Never block a freshly queued print because of one transient AirPrint/CUPS probe.
                // Let dispatch do its own short retry so a sleeping SELPHY has time to wake.
                if hasDispatchableWork { continue }
                if failures >= 3 {
                    setSlot(name,state:"OFFLINE",eta:0,current:nil,error:"Drucker mehrfach nicht erreichbar. WLAN/Druckerstatus prüfen.")
                }
            }
        }
    }

    private func heartbeatAll(state: AppState) async {
        guard let dev=state.deviceToken, let session=state.sessionToken, !state.selectedEventToken.isEmpty else { return }
        for slot in printerSlots where slot.enabled {
            let _: Bool? = try? await api.rpc("fts_printer_heartbeat_node_v80", body: [
                "p_device_token":dev,
                "p_session_token":session,
                "p_event_token":state.selectedEventToken,
                "p_printer_key":backendPrinterKey(slot.name),
                "p_display_name":slot.name,
                "p_state":slot.state,
                "p_eta_seconds":slot.eta,
                "p_current_unit_id":((slot.currentUnit?.hasPrefix("LOCAL:") == true) ? NSNull() : (slot.currentUnit as Any? ?? NSNull())),
                "p_last_error":slot.lastError as Any? ?? NSNull()
            ], as: Bool.self)
        }
    }

    func dispatchAvailable(state: AppState) {
        guard autoDispatch && hasDispatchableWork else { return }
        for slot in printerSlots where slot.enabled && slot.state == "IDLE" && materialReady(for: slot.name) {
            guard activePrinterTasks[slot.name] == nil else { continue }
            let name = slot.name
            activePrinterTasks[name] = Task { [weak self, weak state] in
                guard let self, let state else { return }
                await self.dispatchOne(printerName: name, state: state)
                self.activePrinterTasks[name] = nil
                // Refresh the authoritative queue before feeding the next job.
                // This avoids stale local READY rows and keeps free printers continuously supplied.
                if self.autoDispatch {
                    await self.refresh(state: state)
                }
            }
        }
    }

    private func shouldTakeLocal() -> Bool {
        let hasLocal = localWaitingCount > 0
        let hasSelfie = workUnits.contains { $0.unit_status == "READY" }
        if hasLocal && hasSelfie {
            lastDispatchedLocal.toggle()
            return lastDispatchedLocal
        }
        return hasLocal
    }

    private func dispatchOne(printerName: String, state: AppState) async {
        guard let dev=state.deviceToken, let session=state.sessionToken else { return }
        setSlot(printerName, state:"PREPARING", eta:0, current:nil, error:nil)

        // Do not use `lpstat -a` as a connectivity gate here. On SELPHY/AirPrint/USB
        // macOS can report the queue as temporarily "not accepting" even while
        // System Settings shows the printer green and a real print is possible.
        // NSPrintOperation below is the authoritative submission attempt.
        printerConnectivityFailures[printerName]=0

        defer {
            if let i=printerSlots.firstIndex(where:{$0.name==printerName}), printerSlots[i].state != "ERROR" {
                setSlot(printerName, state:"IDLE", eta:0, current:nil, error:nil)
            }
        }

        if shouldTakeLocal(), let localRef = nextLocalWaitingUnit() {
            await dispatchLocal(localRef: localRef, printerName: printerName, state: state)
            return
        }

        do {
            let claim: V80Claim = try await api.rpc("fts_printer_claim_next_v80", body: [
                "p_device_token":dev, "p_session_token":session,
                "p_event_token":state.selectedEventToken, "p_printer_key":backendPrinterKey(printerName)
            ])
            if claim.error == "MATERIAL_EMPTY" { return }
            if claim.empty == true || claim.busy == true || claim.unit_id == nil { return }
            guard let unitID=claim.unit_id, let path=claim.designed_path else { return }
            setSlot(printerName,state:"TRANSFER",eta:Int(V80MacSpooler.learnedSeconds(printerName:printerName)),current:unitID,error:nil)
            do {
                let data = try await api.imageData(storagePath:path)
                guard let image = NSImage(data:data) else {
                    throw NSError(domain:"FTSPrinter",code:83,userInfo:[NSLocalizedDescriptionKey:"Druckfoto konnte nicht geöffnet werden."])
                }
                let started: Bool = try await api.rpc("fts_printer_start_unit_v80", body:[
                    "p_device_token":dev,"p_session_token":session,"p_unit_id":unitID
                ])
                guard started else { throw NSError(domain:"FTSPrinter",code:84,userInfo:[NSLocalizedDescriptionKey:"Druckeinheit konnte nicht gestartet werden."]) }

                let start=Date()
                let estimate=V80MacSpooler.learnedSeconds(printerName:printerName)
                setSlot(printerName,state:"PRINTING",eta:Int(estimate),current:unitID,error:nil)
                let cupsRequestID = try V80MacSpooler.submit(image:image,printerName:printerName,title:"FTS Selfie · \(claim.pickup_code ?? unitID.prefix(8).description)")
                let ticker=Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for:.seconds(1))
                        guard let self else{return}
                        let elapsed=Date().timeIntervalSince(start)
                        self.setSlot(printerName,state:"PRINTING",eta:max(0,Int(estimate-elapsed)),current:unitID,error:nil)
                        if Int(elapsed) % 20 == 0 {
                            let _:Bool? = try? await self.api.rpc("fts_printer_heartbeat_unit_v80",body:[
                                "p_device_token":dev,"p_session_token":session,"p_unit_id":unitID
                            ],as:Bool.self)
                        }
                    }
                }
                do {
                    try await V80MacSpooler.waitUntilLikelyFinished(printerName:printerName,requestID:cupsRequestID,started:start,estimated:estimate)
                    ticker.cancel()
                    V80MacSpooler.rememberDuration(Date().timeIntervalSince(start),printerName:printerName)
                    let _:V80FinishResult = try await api.rpc("fts_printer_finish_unit_v80",body:[
                        "p_device_token":dev,"p_session_token":session,"p_unit_id":unitID
                    ])
                    setSlot(printerName,state:"IDLE",eta:0,current:nil,error:nil)
                } catch {
                    ticker.cancel()
                    let _: JSONValue? = try? await api.rpc("fts_printer_fail_unit_v80",body:[
                        "p_device_token":dev,"p_session_token":session,"p_unit_id":unitID,
                        "p_error":error.localizedDescription,"p_confirm_not_printed":false
                    ],as:JSONValue.self)
                    setSlot(printerName,state:"ERROR",eta:0,current:unitID,error:"Status unklar – Ausdruck prüfen")
                    lastError="\(printerName): Druckstatus unklar. Ausdruck physisch prüfen, bevor nachgedruckt wird."
                }
            } catch {
                let _: JSONValue? = try? await api.rpc("fts_printer_fail_unit_v80",body:[
                    "p_device_token":dev,"p_session_token":session,"p_unit_id":unitID,
                    "p_error":error.localizedDescription,"p_confirm_not_printed":true
                ],as:JSONValue.self)
                setSlot(printerName,state:"ERROR",eta:0,current:nil,error:error.localizedDescription)
                lastError=error.localizedDescription
            }
        } catch {
            setSlot(printerName,state:"ERROR",eta:0,current:nil,error:error.localizedDescription)
            lastError=error.localizedDescription
        }
    }

    private func setSlot(_ name:String,state:String,eta:Int,current:String?,error:String?) {
        guard let i=printerSlots.firstIndex(where:{$0.name==name}) else{return}
        printerSlots[i].state=state
        printerSlots[i].eta=max(0,eta)
        printerSlots[i].currentUnit=current
        printerSlots[i].lastError=error
    }

    func loadConsumable(printerName:String,component:String,state:AppState) async {
        let key=printerName+"::"+component
        guard !consumableActionsInFlight.contains(key) else{return}
        guard let dev=state.deviceToken,let session=state.sessionToken,!state.selectedEventToken.isEmpty else{return}
        consumableActionsInFlight.insert(key)
        defer{consumableActionsInFlight.remove(key)}
        do {
            let _:JSONValue = try await api.rpc("fts_printer_load_component_v81",body:[
                "p_device_token":dev,"p_session_token":session,"p_event_token":state.selectedEventToken,
                "p_printer_key":backendPrinterKey(printerName),"p_component":component
            ])
            await refresh(state:state)
        } catch { lastError=error.localizedDescription }
    }

    func consumableActionBusy(printerName:String,component:String)->Bool {
        consumableActionsInFlight.contains(printerName+"::"+component)
    }

    func consumable(for printerName:String)->V81Consumable? {
        consumables.first{$0.printer_key==backendPrinterKey(printerName)}
    }

    func materialReady(for printerName:String) -> Bool {
        guard let c = consumable(for:printerName) else { return true }
        return (c.paper_remaining ?? 1) > 0 && (c.film_remaining ?? 1) > 0
    }

    func materialMessage(for printerName:String) -> String? {
        guard let c = consumable(for:printerName) else { return nil }
        if (c.paper_remaining ?? 1) <= 0 && (c.film_remaining ?? 1) <= 0 { return "Papier und Farbfilm leer" }
        if (c.paper_remaining ?? 1) <= 0 { return "Papier leer" }
        if (c.film_remaining ?? 1) <= 0 { return "Farbfilm leer" }
        return nil
    }

    private func backendPrinterKey(_ printerName:String) -> String {
        hostID + "::" + printerName
    }

    func clearPrinterError(_ name:String) {
        setSlot(name,state:"IDLE",eta:0,current:nil,error:nil)
    }

    private struct LocalRef { let jobIndex:Int; let unitIndex:Int }

    private func nextLocalWaitingUnit() -> LocalRef? {
        for ji in localQueue.jobs.indices {
            if localQueue.jobs[ji].status == .cancelled || localQueue.jobs[ji].status == .archived { continue }
            if let ui = localQueue.jobs[ji].units.firstIndex(where:{$0.status == .waiting}) {
                return LocalRef(jobIndex:ji,unitIndex:ui)
            }
        }
        return nil
    }

    private func dispatchLocal(localRef:LocalRef,printerName:String,state:AppState) async {
        guard localQueue.jobs.indices.contains(localRef.jobIndex),
              localQueue.jobs[localRef.jobIndex].units.indices.contains(localRef.unitIndex),
              let dev=state.deviceToken, let session=state.sessionToken else{return}

        let jobID=localQueue.jobs[localRef.jobIndex].id
        let customer=localQueue.jobs[localRef.jobIndex].customerCode
        let path=localQueue.jobs[localRef.jobIndex].units[localRef.unitIndex].imagePath
        let preRendered=localQueue.jobs[localRef.jobIndex].units[localRef.unitIndex].preRendered == true
        let original=localQueue.jobs[localRef.jobIndex].units[localRef.unitIndex].originalName

        localQueue.jobs[localRef.jobIndex].units[localRef.unitIndex].status = .printing
        localQueue.jobs[localRef.jobIndex].units[localRef.unitIndex].printerName = printerName
        localQueue.jobs[localRef.jobIndex].units[localRef.unitIndex].startedAt = Date()
        localQueue.jobs[localRef.jobIndex].status = .printing
        saveLocalQueue()
        let _:Bool? = try? await api.rpc("fts_printer_start_local_job_v80",body:[
            "p_device_token":dev,"p_session_token":session,"p_local_job_id":jobID.uuidString
        ],as:Bool.self)

        do {
            guard let event=state.selectedEvent else{throw NSError(domain:"FTSPrinter",code:85,userInfo:[NSLocalizedDescriptionKey:"Event nicht mehr ausgewählt."])}
            let rendered:NSImage
            if preRendered {
                guard let ready=NSImage(contentsOfFile:path) else {
                    throw NSError(domain:"FTSPrinter",code:189,userInfo:[NSLocalizedDescriptionKey:"Druckbereite Design-Datei konnte nicht geöffnet werden."])
                }
                rendered=ready
            } else {
                rendered=try await ProductionRendererV76.renderedImage(sourceURL:URL(fileURLWithPath:path),event:event)
            }
            let estimate=V80MacSpooler.learnedSeconds(printerName:printerName)
            let start=Date()
            setSlot(printerName,state:"PRINTING",eta:Int(estimate),current:"LOCAL:"+jobID.uuidString,error:nil)
            let cupsRequestID = try V80MacSpooler.submit(image:rendered,printerName:printerName,title:"FTS Kamera · \(customer) · \(original)")
            let ticker=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(1))
                    guard let self else{return}
                    let elapsed=Date().timeIntervalSince(start)
                    self.setSlot(printerName,state:"PRINTING",eta:max(0,Int(estimate-elapsed)),current:"LOCAL:"+jobID.uuidString,error:nil)
                }
            }
            do {
                try await V80MacSpooler.waitUntilLikelyFinished(printerName:printerName,requestID:cupsRequestID,started:start,estimated:estimate)
                ticker.cancel()
            } catch {
                ticker.cancel()
                throw error
            }
            V80MacSpooler.rememberDuration(Date().timeIntervalSince(start),printerName:printerName)
            guard let ji=localQueue.jobs.firstIndex(where:{$0.id==jobID}),
                  let ui=localQueue.jobs[ji].units.firstIndex(where:{$0.imagePath==path && $0.status == .printing}) else{return}
            let localUnitID=localQueue.jobs[ji].units[ui].id
            do {
                let componentResult:JSONValue = try await api.rpc("fts_printer_consume_local_unit_component_v87",body:[
                    "p_device_token":dev,"p_session_token":session,"p_event_token":state.selectedEventToken,
                    "p_printer_key":backendPrinterKey(printerName),"p_local_unit_id":localUnitID.uuidString
                ])
                localQueue.jobs[ji].units[ui].componentSynced = componentResult["ok"]?.bool == true
            } catch {
                localQueue.jobs[ji].units[ui].componentSynced = false
            }

            localQueue.jobs[ji].units[ui].status = .printed
            localQueue.jobs[ji].units[ui].printedAt = Date()
            let allDone=localQueue.jobs[ji].units.allSatisfy{$0.status == .printed || $0.status == .cancelled}
            if allDone {
                await finalizeLocalJob(jobID:jobID,state:state)
            } else {
                localQueue.jobs[ji].status = .printing
                saveLocalQueue()
            }
            setSlot(printerName,state:"IDLE",eta:0,current:nil,error:nil)
        } catch {
            guard let ji=localQueue.jobs.firstIndex(where:{$0.id==jobID}),
                  let ui=localQueue.jobs[ji].units.firstIndex(where:{$0.imagePath==path && $0.status == .printing}) else{return}
            localQueue.jobs[ji].units[ui].status = .uncertain
            localQueue.jobs[ji].units[ui].lastError = error.localizedDescription
            localQueue.jobs[ji].status = .uncertain
            saveLocalQueue()
            setSlot(printerName,state:"ERROR",eta:0,current:"LOCAL:"+jobID.uuidString,error:"Lokaler Druck unklar – Ausdruck prüfen")
            lastError="\(customer): Druckstatus unklar. Nicht automatisch erneut drucken."
        }
    }

    func confirmServerUnitPrinted(_ unit: V80WorkUnit, state: AppState) async {
        guard let dev=state.deviceToken,let session=state.sessionToken else{return}
        do {
            let result:JSONValue = try await api.rpc("fts_printer_confirm_uncertain_printed_v87",body:[
                "p_device_token":dev,"p_session_token":session,"p_unit_id":unit.unit_id
            ])
            guard result["ok"]?.bool == true else {
                throw NSError(domain:"FTSPrinter",code:187,userInfo:[NSLocalizedDescriptionKey:"Druckeinheit konnte nicht bestätigt werden."])
            }
            if let i=printerSlots.firstIndex(where:{$0.currentUnit==unit.unit_id}) {
                printerSlots[i].state="IDLE";printerSlots[i].eta=0;printerSlots[i].currentUnit=nil;printerSlots[i].lastError=nil
            }
            await refresh(state:state)
        } catch { lastError=error.localizedDescription }
    }

    func confirmLocalUnitPrinted(jobID:UUID,unitID:UUID,state:AppState) async {
        guard let dev=state.deviceToken,let session=state.sessionToken,
              let ji=localQueue.jobs.firstIndex(where:{$0.id==jobID}),
              let ui=localQueue.jobs[ji].units.firstIndex(where:{$0.id==unitID}),
              localQueue.jobs[ji].units[ui].status == .uncertain else{return}

        let printerName=localQueue.jobs[ji].units[ui].printerName
        if let printerName {
            do {
                let result:JSONValue = try await api.rpc("fts_printer_consume_local_unit_component_v87",body:[
                    "p_device_token":dev,"p_session_token":session,"p_event_token":state.selectedEventToken,
                    "p_printer_key":backendPrinterKey(printerName),"p_local_unit_id":unitID.uuidString
                ])
                localQueue.jobs[ji].units[ui].componentSynced = result["ok"]?.bool == true
            } catch {
                localQueue.jobs[ji].units[ui].componentSynced = false
            }
        }

        localQueue.jobs[ji].units[ui].status = .printed
        localQueue.jobs[ji].units[ui].printedAt = Date()
        localQueue.jobs[ji].units[ui].lastError = nil

        let allDone=localQueue.jobs[ji].units.allSatisfy{$0.status == .printed || $0.status == .cancelled}
        if allDone {
            await finalizeLocalJob(jobID:jobID,state:state)
        } else {
            localQueue.jobs[ji].status = .printing
            saveLocalQueue()
        }

        if let printerName { clearPrinterError(printerName) }
    }

    func retryLocalCompletion(jobID:UUID,state:AppState) async {
        await finalizeLocalJob(jobID:jobID,state:state)
    }

    private func finalizeLocalJob(jobID:UUID,state:AppState) async {
        guard let dev=state.deviceToken,let session=state.sessionToken,
              let ji=localQueue.jobs.firstIndex(where:{$0.id==jobID}) else{return}

        guard localQueue.jobs[ji].units.allSatisfy({$0.status == .printed || $0.status == .cancelled}) else{return}

        // First reconcile every physical print with the per-printer RP-108 counters.
        for ui in localQueue.jobs[ji].units.indices {
            let unit=localQueue.jobs[ji].units[ui]
            guard unit.status == .printed, unit.componentSynced != true, let printerName=unit.printerName else{continue}
            do {
                let result:JSONValue = try await api.rpc("fts_printer_consume_local_unit_component_v87",body:[
                    "p_device_token":dev,"p_session_token":session,"p_event_token":state.selectedEventToken,
                    "p_printer_key":backendPrinterKey(printerName),"p_local_unit_id":unit.id.uuidString
                ])
                localQueue.jobs[ji].units[ui].componentSynced = result["ok"]?.bool == true
            } catch {
                localQueue.jobs[ji].status = .uncertain
                saveLocalQueue()
                lastError="Drucke sind fertig. Material-/Auftragssynchronisierung wartet auf Verbindung."
                return
            }
        }

        let summary=localQueue.jobs[ji].units.map{$0.originalName}.joined(separator:", ")
        do {
            let result:JSONValue = try await api.rpc("fts_printer_complete_local_job_v80",body:[
                "p_device_token":dev,"p_session_token":session,"p_local_job_id":jobID.uuidString,
                "p_file_summary":summary
            ])
            guard result["ok"]?.bool == true else {
                throw NSError(domain:"FTSPrinter",code:188,userInfo:[NSLocalizedDescriptionKey:"Lokaler Auftrag konnte nicht abgeschlossen werden."])
            }
            localQueue.jobs[ji].status = .readyForPickup
            saveLocalQueue()
            await refresh(state:state)
        } catch {
            localQueue.jobs[ji].status = .uncertain
            saveLocalQueue()
            lastError="Alle Ausdrucke sind fertig, aber der Abschluss konnte noch nicht synchronisiert werden. Keine Fotos erneut drucken."
        }
    }

    func requeueLocalUnit(jobID:UUID,unitID:UUID,confirmedNotPrinted:Bool) {
        guard confirmedNotPrinted,
              let ji=localQueue.jobs.firstIndex(where:{$0.id==jobID}),
              let ui=localQueue.jobs[ji].units.firstIndex(where:{$0.id==unitID}),
              localQueue.jobs[ji].units[ui].status == .uncertain else{return}
        localQueue.jobs[ji].units[ui].status = .waiting
        localQueue.jobs[ji].units[ui].printerName = nil
        localQueue.jobs[ji].units[ui].startedAt = nil
        localQueue.jobs[ji].units[ui].lastError = nil
        localQueue.jobs[ji].status = .waiting
        saveLocalQueue()
    }

    func createLocalJob(state:AppState, media:[V80MediaItem:Int], sourceType:String, sourceLabel:String, eventDay:String) async -> String? {
        guard let dev=state.deviceToken,let session=state.sessionToken,!state.selectedEventToken.isEmpty,
              !loadedFolderPath.isEmpty else{return nil}
        let filtered=media.filter{$0.value>0}
        let qty=filtered.reduce(0){$0+$1.value}
        guard qty>0 else{return nil}
        let id=UUID()
        do {
            let result:V80LocalJobCreate = try await api.rpc("fts_printer_create_local_job_v92",body:[
                "p_device_token":dev,"p_session_token":session,"p_event_token":state.selectedEventToken,
                "p_event_day":eventDay,
                "p_local_job_id":id.uuidString,"p_source_type":sourceType,"p_source_label":sourceLabel,"p_quantity":qty
            ])
            guard result.ok==true,let code=result.customer_code else {
                throw NSError(domain:"FTSPrinter",code:86,userInfo:[NSLocalizedDescriptionKey:"Lokaler Auftrag konnte nicht angelegt werden."])
            }
            var units:[V80LocalPrintUnit]=[]
            for (m,count) in filtered.sorted(by:{$0.key.importedAt < $1.key.importedAt}) {
                for copy in 1...count {
                    let readyPath = (m.designedPath?.isEmpty == false) ? m.designedPath! : m.importedPath
                    units.append(V80LocalPrintUnit(
                        id:UUID(),jobID:id,customerCode:code,mediaID:m.id,imagePath:readyPath,
                        preRendered:(m.designedPath?.isEmpty == false),
                        originalName:m.originalName,copyIndex:copy,status:.waiting,printerName:nil,
                        startedAt:nil,printedAt:nil,lastError:nil,componentSynced:false
                    ))
                }
            }
            localQueue.jobs.append(V80LocalPrintJob(
                id:id,eventToken:state.selectedEventToken,eventDay:eventDay,customerCode:code,sourceType:sourceType,
                sourceLabel:sourceLabel,createdAt:Date(),status:.waiting,units:units
            ))
            saveLocalQueue()
            await state.refreshSelected()
            return code
        } catch {
            lastError=error.localizedDescription
            return nil
        }
    }

    func requeueServerUnit(_ unit: V80WorkUnit, state: AppState, confirmedNotPrinted: Bool) async {
        guard confirmedNotPrinted, let dev=state.deviceToken, let session=state.sessionToken else{return}
        do {
            let _: JSONValue = try await api.rpc("fts_printer_fail_unit_v80", body:[
                "p_device_token":dev,"p_session_token":session,"p_unit_id":unit.unit_id,
                "p_error":"Mitarbeiter hat bestätigt: nicht gedruckt","p_confirm_not_printed":true
            ])
            if let i=printerSlots.firstIndex(where:{$0.currentUnit==unit.unit_id}) {
                printerSlots[i].state="IDLE";printerSlots[i].eta=0;printerSlots[i].currentUnit=nil;printerSlots[i].lastError=nil
            }
            await refresh(state:state)
        } catch { lastError=error.localizedDescription }
    }

    func cancelLocalJob(_ job: V80LocalPrintJob, state: AppState) async {
        guard job.status == .waiting, let dev=state.deviceToken, let session=state.sessionToken else{return}
        do {
            let ok:Bool=try await api.rpc("fts_printer_cancel_local_job_v80",body:[
                "p_device_token":dev,"p_session_token":session,"p_local_job_id":job.id.uuidString
            ])
            if ok,let i=localQueue.jobs.firstIndex(where:{$0.id==job.id}) {
                localQueue.jobs[i].status = .cancelled
                for ui in localQueue.jobs[i].units.indices where localQueue.jobs[i].units[ui].status == .waiting {
                    localQueue.jobs[i].units[ui].status = .cancelled
                }
                saveLocalQueue()
            }
            await state.refreshSelected()
            await refresh(state:state)
        } catch { lastError=error.localizedDescription }
    }

    func markPickedUp(_ pickup:V80Pickup,state:AppState) async {
        guard !pickupActionsInFlight.contains(pickup.id) else { return }
        guard let dev=state.deviceToken,let session=state.sessionToken else{return}
        pickupActionsInFlight.insert(pickup.id)
        defer { pickupActionsInFlight.remove(pickup.id) }
        do {
            let name = pickup.kind.uppercased()=="LOCAL" ? "fts_printer_mark_local_picked_up_archive_v80" : "fts_printer_mark_picked_up_archive_v80"
            let body:[String:Any] = pickup.kind.uppercased()=="LOCAL"
                ? ["p_device_token":dev,"p_session_token":session,"p_local_job_id":pickup.id]
                : ["p_device_token":dev,"p_session_token":session,"p_order_id":pickup.id]
            let ok:Bool=try await api.rpc(name,body:body)
            if ok, pickup.kind.uppercased()=="LOCAL", let ji=localQueue.jobs.firstIndex(where:{$0.id.uuidString==pickup.id}) {
                localQueue.jobs[ji].status = .archived
                saveLocalQueue()
            }
            await refresh(state:state)
        } catch { lastError=error.localizedDescription }
    }

    func hideArchived(_ row: V80ArchiveRow, state: AppState) async {
        guard !archiveActionsInFlight.contains(row.id) else { return }
        guard let dev=state.deviceToken,let session=state.sessionToken else{return}
        archiveActionsInFlight.insert(row.id)
        defer { archiveActionsInFlight.remove(row.id) }
        do {
            let ok:Bool=try await api.rpc("fts_printer_hide_archived_v82",body:[
                "p_device_token":dev,"p_session_token":session,
                "p_kind":row.kind,"p_item_id":row.id
            ])
            if ok { await refresh(state:state) }
        } catch { lastError=error.localizedDescription }
    }

    func resetLocalDay(state:AppState,eventDay:String) async -> Bool {
        guard localQueue.jobs.isEmpty else {
            lastError="Für dieses Tagesalbum gibt es bereits lokale Druckaufträge. Die Nummerierung kann nicht zurückgesetzt werden."
            return false
        }
        guard let dev=state.deviceToken,let session=state.sessionToken,!state.selectedEventToken.isEmpty else{return false}
        do {
            let result:V92DayResetResult=try await api.rpc("fts_printer_reset_local_day_v92",body:[
                "p_device_token":dev,"p_session_token":session,
                "p_event_token":state.selectedEventToken,"p_event_day":eventDay
            ])
            if result.ok==true { return true }
            lastError=result.message ?? "Tageszähler konnte nicht zurückgesetzt werden."
            return false
        } catch {
            lastError=error.localizedDescription
            return false
        }
    }

    func checkUpdate(platform:String) async {
        do {
            let rows:[V80Release]=try await api.rpc("fts_printer_latest_release_v80",body:["p_platform":platform])
            guard let r=rows.first else{updateRelease=nil;updateAvailable=false;return}
            updateRelease=r
            updateAvailable=r.build_number > Self.build
        } catch {
            // Update checks are never allowed to break printing.
        }
    }

    func downloadUpdate() async -> URL? {
        guard let r=updateRelease,let s=r.external_url,let u=URL(string:s) else{return nil}
        let expected=(r.sha256 ?? "").trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard !expected.isEmpty else {
            lastError="Update wurde nicht geladen: veröffentlichte SHA-256-Prüfsumme fehlt."
            return nil
        }
        do {
            let (tmp,response) = try await URLSession.shared.download(from:u)
            if let http=response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw NSError(domain:"FTSPrinter",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:"Update-Server HTTP \(http.statusCode)"])
            }
            let actual=try Self.fileSHA256(tmp)
            guard actual==expected else {
                try? FileManager.default.removeItem(at:tmp)
                throw NSError(domain:"FTSPrinter",code:88,userInfo:[NSLocalizedDescriptionKey:"Update-Prüfsumme stimmt nicht. Datei wurde verworfen."])
            }
            let ext=u.pathExtension.isEmpty ? "dmg" : u.pathExtension
            let dest=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first!
                .appendingPathComponent("FTS-Printer-\(r.version).\(ext)")
            try? FileManager.default.removeItem(at:dest)
            try FileManager.default.moveItem(at:tmp,to:dest)
            return dest
        } catch {
            lastError="Update konnte nicht geladen werden: \(error.localizedDescription)"
            return nil
        }
    }

    private static func fileSHA256(_ url:URL) throws -> String {
        let handle=try FileHandle(forReadingFrom:url)
        defer{try? handle.close()}
        var hasher=SHA256()
        while true {
            guard let data=try handle.read(upToCount:1_048_576),!data.isEmpty else{break}
            hasher.update(data:data)
        }
        return hasher.finalize().map{String(format:"%02x",$0)}.joined()
    }
}
