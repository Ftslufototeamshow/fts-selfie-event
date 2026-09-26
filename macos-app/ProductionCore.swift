import SwiftUI
import AppKit
import Foundation
import CryptoKit
import ApplicationServices

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
    var connection: String
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

    private struct NativePaperChoice {
        let id:String
        let name:String
        let width:Double
        let height:Double
    }

    private static func nativePrinter(named displayName:String) -> PMPrinter? {
        var unmanaged:Unmanaged<CFArray>?
        guard PMServerCreatePrinterList(nil,&unmanaged) == noErr,
              let array=unmanaged?.takeRetainedValue() else { return nil }

        let count=CFArrayGetCount(array)
        for i in 0..<count {
            guard let raw=CFArrayGetValueAtIndex(array,i) else { continue }
            let printer=OpaquePointer(raw)
            let name=(PMPrinterGetName(printer)?.takeUnretainedValue() as String?) ?? ""
            if name == displayName {
                _ = PMRetain(UnsafeRawPointer(printer))
                return printer
            }
        }
        return nil
    }

    static func nativeQueueState(printerName:String) -> String? {
        guard let printer=nativePrinter(named:printerName) else { return nil }
        defer { PMRelease(UnsafeRawPointer(printer)) }
        var state:PMPrinterState = PMPrinterState(kPMPrinterIdle)
        guard PMPrinterGetState(printer,&state) == noErr else { return nil }
        switch Int(state) {
        case kPMPrinterProcessing: return "PROCESSING"
        case kPMPrinterStopped: return "STOPPED"
        default: return "IDLE"
        }
    }

    static func nativeDeviceURI(printerName:String) -> String? {
        guard let printer=nativePrinter(named:printerName) else { return nil }
        defer { PMRelease(UnsafeRawPointer(printer)) }
        var unmanaged:Unmanaged<CFURL>?
        guard PMPrinterCopyDeviceURI(printer,&unmanaged) == noErr,
              let url=unmanaged?.takeRetainedValue() else { return nil }
        return (url as URL).absoluteString
    }

    private static func nativePaperChoices(printerName:String) -> [NativePaperChoice] {
        guard let printer=nativePrinter(named:printerName) else { return [] }
        defer { PMRelease(UnsafeRawPointer(printer)) }

        var unmanaged:Unmanaged<CFArray>?
        guard PMPrinterGetPaperList(printer,&unmanaged) == noErr,
              let array=unmanaged?.takeUnretainedValue() else { return [] }

        var out:[NativePaperChoice]=[]
        let count=CFArrayGetCount(array)
        for i in 0..<count {
            guard let raw=CFArrayGetValueAtIndex(array,i) else { continue }
            let paper=OpaquePointer(raw)
            var width:Double=0,height:Double=0
            guard PMPaperGetWidth(paper,&width)==noErr,
                  PMPaperGetHeight(paper,&height)==noErr else { continue }

            var idRef:Unmanaged<CFString>?
            let idStatus=PMPaperGetID(paper,&idRef)
            let id=idStatus==noErr ? ((idRef?.takeUnretainedValue() as String?) ?? "") : ""

            var nameRef:Unmanaged<CFString>?
            let nameStatus=PMPaperCreateLocalizedName(paper,printer,&nameRef)
            let name=nameStatus==noErr ? ((nameRef?.takeRetainedValue() as String?) ?? id) : id

            if !id.isEmpty {
                out.append(NativePaperChoice(id:id,name:name,width:width,height:height))
            }
        }
        return out
    }

    private static func bestPostcardPaper(printerName:String) -> NativePaperChoice? {
        let targetW=283.46,targetH=419.53 // 100 × 148 mm SELPHY postcard
        let choices=nativePaperChoices(printerName:printerName)
        return choices.min { a,b in
            let adim=min(abs(a.width-targetW)+abs(a.height-targetH),abs(a.width-targetH)+abs(a.height-targetW))
            let bdim=min(abs(b.width-targetW)+abs(b.height-targetH),abs(b.width-targetH)+abs(b.height-targetW))
            // FTS prints borderless. Canon exposes separate Postcard and Postcard-fullbleed
            // media profiles. Prefer the printer's explicit full-bleed profile whenever
            // dimensions are otherwise equivalent; zero margins on plain Postcard can
            // leave the AirPrint/IPP-USB queue processing without the SELPHY starting.
            let afull=(a.id.lowercased().contains("fullbleed") || a.name.lowercased().contains("randlos")) ? 0.0 : 1000.0
            let bfull=(b.id.lowercased().contains("fullbleed") || b.name.lowercased().contains("randlos")) ? 0.0 : 1000.0
            return (adim+afull) < (bdim+bfull)
        }
    }

    private static func paperDiagnostic(printerName:String) -> String {
        nativePaperChoices(printerName:printerName).map {
            "\($0.name) [\($0.id)] \(Int($0.width))x\(Int($0.height))pt"
        }.joined(separator:" | ")
    }

    private struct ConnectionProbe {
        let connected:Bool
        let summary:String
    }

    static func connectionSummary(printerName:String) -> String {
        let statuses=systemPrinterStatuses()
        return connectionProbe(printerName:printerName,macStatuses:statuses).summary
    }

    static func internetConnectionSummary() -> String {
        let wifi=wifiLinkSummary()
        let started=Date()
        let output=runProcess(
            "/usr/bin/curl",
            ["-sS","-o","/dev/null","--connect-timeout","2","--max-time","3","-w","%{http_code}",
             "https://hivmiqktbaatghuaxfvg.supabase.co/rest/v1/"],
            timeout:3.5
        )
        let ms=max(1,Int(Date().timeIntervalSince(started)*1000))
        if let output,!output.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            return "FTS-Server: erreichbar · \(ms) ms" + (wifi.isEmpty ? "" : "\n"+wifi)
        }
        return "FTS-Server: nicht erreichbar" + (wifi.isEmpty ? "" : "\n"+wifi)
    }

    private static func connectionProbe(printerName:String,macStatuses:[String:String]?=nil) -> ConnectionProbe {
        let statuses=macStatuses ?? systemPrinterStatuses()
        if let macStatus=statuses[printerName] {
            if !printerStatusIsOnline(macStatus) {
                return ConnectionProbe(connected:false,summary:"macOS: \(macStatus)")
            }
        }

        let rawURI=nativeDeviceURI(printerName:printerName) ?? ""
        let uri=rawURI.lowercased()
        let lowerName=printerName.lowercased()
        let isSelphy=lowerName.contains("selphy") || lowerName.contains("cp1500")
        let usbPresent=isSelphy ? usbSELPHYPresent() : false
        let usbTransport=uri.hasPrefix("usb:")
            || uri.contains("ippusb")
            || uri.contains("ipp-usb")
            || (uri.contains("localhost") && isSelphy)

        if usbTransport || (rawURI.isEmpty && usbPresent) {
            let macStatus=statuses[printerName]
            let macOnline=macStatus.map(printerStatusIsOnline) ?? false
            // macOS Print Center is authoritative for local USB/IPP-USB readiness.
            // Hardware/latency probes add diagnostics but must not hide a queue that
            // macOS itself reports as ready/idle/printing.
            let latency = rawURI.isEmpty ? nil : networkPrinterLatency(uri:rawURI)
            guard macOnline || latency != nil || usbPresent else {
                return ConnectionProbe(connected:false,summary:"USB · nicht angeschlossen")
            }
            let details=usbLinkSummary()
            var summary="USB · verbunden"
            if let latency { summary += " · \(latency) ms" }
            if !details.isEmpty { summary += " · "+details }
            return ConnectionProbe(connected:true,summary:summary)
        }

        let networkTransport=uri.hasPrefix("dnssd:")
            || uri.hasPrefix("ipp:")
            || uri.hasPrefix("ipps:")
            || uri.hasPrefix("http:")
            || uri.hasPrefix("https:")
            || uri.contains("_ipp")

        if networkTransport {
            guard let latency=networkPrinterLatency(uri:rawURI) else {
                return ConnectionProbe(connected:false,summary:"AirPrint/WLAN · Drucker nicht erreichbar")
            }
            let wifi=wifiLinkSummary()
            return ConnectionProbe(
                connected:true,
                summary:"AirPrint/WLAN · Drucker erreichbar · \(latency) ms" + (wifi.isEmpty ? "" : "\n"+wifi)
            )
        }

        if let macStatus=statuses[printerName],printerStatusIsOnline(macStatus) {
            return ConnectionProbe(connected:true,summary:"macOS-Drucker · \(macStatus)")
        }
        if nativeQueueState(printerName:printerName)=="PROCESSING" {
            return ConnectionProbe(connected:true,summary:"macOS-Drucker · aktive Verbindung")
        }
        return ConnectionProbe(connected:false,summary:"Drucker nicht physisch erreichbar")
    }

    static func wifiSignalStatus() -> (bars:Int,label:String,detail:String) {
        let airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        guard let text=runProcess(airport,["-I"],timeout:1.2) else {
            return (0,"nicht messbar","")
        }
        func number(_ key:String)->Int? {
            for line in text.split(separator:"\n") {
                let s=String(line).trimmingCharacters(in:.whitespaces)
                if s.lowercased().hasPrefix(key.lowercased()+":"),
                   let value=Int(s.split(separator:":",maxSplits:1).last?.trimmingCharacters(in:.whitespaces) ?? "") {
                    return value
                }
            }
            return nil
        }
        let rssi=number("agrCtlRSSI")
        let noise=number("agrCtlNoise")
        let tx=number("lastTxRate")
        guard rssi != nil || tx != nil else{return (0,"nicht messbar","")}
        var parts:[String]=[]
        var bars=3
        var label="mittel"
        if let rssi {
            switch rssi {
            case -50...0: bars=5;label="sehr gut"
            case -60 ... -51: bars=4;label="gut"
            case -70 ... -61: bars=3;label="mittel"
            case -80 ... -71: bars=2;label="schwach"
            default: bars=1;label="sehr schwach"
            }
            parts.append("\(rssi) dBm")
        }
        if let noise,let rssi { parts.append("SNR \(max(0,rssi-noise)) dB") }
        if let tx { parts.append("\(tx) Mb/s") }
        return (bars,label,parts.joined(separator:" · "))
    }

    private static func wifiLinkSummary() -> String {
        let status=wifiSignalStatus()
        guard status.bars>0 else{return ""}
        return "Mac-WLAN \(status.detail) (\(status.label))"
    }

    private static func usbLinkSummary() -> String {
        guard let text=runProcess("/usr/sbin/system_profiler",["SPUSBDataType","-detailLevel","mini"],timeout:2.5) else{return ""}
        let lines=text.components(separatedBy:.newlines)
        guard let start=lines.firstIndex(where:{
            let l=$0.lowercased()
            return l.contains("selphy") || l.contains("cp1500")
        }) else{return ""}
        let end=min(lines.count,start+18)
        let block=Array(lines[start..<end])
        func value(containing keys:[String])->String? {
            for line in block {
                let lower=line.lowercased()
                if keys.contains(where:{lower.contains($0)}),
                   let colon=line.firstIndex(of:":") {
                    let v=String(line[line.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }
        var parts:[String]=[]
        if let speed=value(containing:["speed","geschwindigkeit"]) { parts.append("Link \(speed)") }
        if let current=value(containing:["current available","verfügbarer strom","available current"]) {
            parts.append("USB-Strom \(current)")
        }
        return parts.joined(separator:" · ")
    }

    private static func networkPrinterLatency(uri:String) -> Int? {
        let lower=uri.lowercased()
        var host:String?
        var port:Int=631

        if lower.hasPrefix("dnssd:") || lower.contains("._ipp") {
            if let endpoint=resolveDNSSD(uri:uri) {
                host=endpoint.host
                port=endpoint.port
            }
        } else if let url=URL(string:uri),let h=url.host {
            host=h
            if let p=url.port { port=p }
            else if url.scheme?.lowercased()=="https" { port=443 }
        }

        guard let host,!host.isEmpty else{return nil}
        let started=Date()
        guard runProcess("/usr/bin/nc",["-G","1","-z",host,String(port)],timeout:1.4) != nil else{return nil}
        return max(1,Int(Date().timeIntervalSince(started)*1000))
    }

    private static func resolveDNSSD(uri:String) -> (host:String,port:Int)? {
        guard let decoded=uri.removingPercentEncoding else{return nil}
        let body:String
        if let schemeRange=decoded.range(of:"://") {
            body=String(decoded[schemeRange.upperBound...])
        } else {
            body=decoded
        }
        let serviceTypes=["._ipps._tcp","._ipp._tcp"]
        guard let type=serviceTypes.first(where:{body.lowercased().contains($0)}) else{return nil}
        guard let range=body.lowercased().range(of:type) else{return nil}
        let instance=String(body[..<range.lowerBound]).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        guard !instance.isEmpty else{return nil}
        let serviceType=type.contains("_ipps") ? "_ipps._tcp" : "_ipp._tcp"
        guard let output=runTimedOutput("/usr/bin/dns-sd",["-L",instance,serviceType,"local."],timeout:1.4) else{return nil}
        for line in output.split(separator:"\n") {
            for tokenSub in line.split(whereSeparator:{$0==" " || $0=="\t"}) {
                let token=String(tokenSub)
                if token.contains(".local.:") || token.contains(".local:") {
                    let clean=token.trimmingCharacters(in:CharacterSet(charactersIn:"()"))
                    guard let colon=clean.lastIndex(of:":"),
                          let p=Int(clean[clean.index(after:colon)...]) else{continue}
                    let h=String(clean[..<colon]).trimmingCharacters(in:CharacterSet(charactersIn:"."))
                    if !h.isEmpty { return (h,p) }
                }
            }
        }
        return nil
    }

    private static func runTimedOutput(_ executable:String,_ arguments:[String],timeout:TimeInterval)->String? {
        let p=Process()
        p.executableURL=URL(fileURLWithPath:executable)
        p.arguments=arguments
        let out=Pipe()
        p.standardOutput=out
        p.standardError=Pipe()
        do {
            try p.run()
            let deadline=Date().addingTimeInterval(timeout)
            while p.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.03) }
            if p.isRunning {
                p.terminate()
                Thread.sleep(forTimeInterval:0.08)
            }
            let data=out.fileHandleForReading.readDataToEndOfFile()
            let text=String(data:data,encoding:.utf8) ?? ""
            return text.isEmpty ? nil : text
        } catch { return nil }
    }

    private static func firstExecutable(_ candidates:[String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath:$0) }
    }

    static func installedPrinterNames() async -> [String] {
        let configured = await MainActor.run {
            NSPrinter.printerNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return await Task.detached(priority:.utility) {
            let macStatus=systemPrinterStatuses()
            return configured.filter { name in
                if let status=macStatus[name] {
                    return printerStatusIsOnline(status)
                }
                return connectionProbe(printerName:name,macStatuses:macStatus).connected
            }
        }.value
    }

    private static func systemPrinterStatuses()->[String:String] {
        guard let raw=runProcess(
            "/usr/sbin/system_profiler",
            ["-json","SPPrintersDataType"],
            timeout:4.0
        ),let data=raw.data(using:.utf8),
          let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
          let printers=root["SPPrintersDataType"] as? [[String:Any]] else {
            return [:]
        }
        var out:[String:String]=[:]
        for printer in printers {
            let name=(printer["_name"] as? String)
                ?? (printer["printer_name"] as? String)
                ?? ""
            let status=(printer["status"] as? String)
                ?? (printer["printer_status"] as? String)
                ?? ""
            if !name.isEmpty,!status.isEmpty {
                out[name]=status.lowercased()
            }
        }
        return out
    }

    private static func printerStatusIsOnline(_ status:String)->Bool {
        let s=status.lowercased()
        if s.contains("offline") || s.contains("unavailable") || s.contains("not connected") {
            return false
        }
        return s.contains("idle")
            || s.contains("ready")
            || s.contains("printing")
            || s.contains("processing")
            || s.contains("busy")
    }

    private static func usbSELPHYPresent()->Bool {
        guard let text=runProcess("/usr/sbin/ioreg",["-p","IOUSB","-l","-w","0"],timeout:1.5) else {
            // Build 103 is strict: if hardware cannot be confirmed, do not show a ghost USB printer.
            return false
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
        guard let printer = NSPrinter(name: printerName) else {
            throw NSError(domain:"FTSPrinter",code:80,userInfo:[NSLocalizedDescriptionKey:"Drucker \(printerName) ist nicht mehr in macOS installiert."])
        }

        let pixelRep=image.representations
            .filter{$0.pixelsWide>0 && $0.pixelsHigh>0}
            .max{($0.pixelsWide*$0.pixelsHigh) < ($1.pixelsWide*$1.pixelsHigh)}
        let landscape:Bool
        if let rep=pixelRep {
            landscape=rep.pixelsWide > rep.pixelsHigh
        } else {
            landscape=image.size.width > image.size.height
        }
        let nominalPortrait=NSSize(width:283.46,height:419.53)

        // Native-only path. Use a paper profile actually advertised by this printer.
        // A custom 100×148 size can be accepted by Print Center yet remain held forever
        // on AirPrint/SELPHY queues if the driver expects its built-in 4×6/Postcard profile.
        let info=(NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.printer=printer

        var portraitPaper=nominalPortrait
        if let supported=bestPostcardPaper(printerName:printerName) {
            let baseW=min(supported.width,supported.height)
            let baseH=max(supported.width,supported.height)
            portraitPaper=NSSize(width:baseW,height:baseH)
            info.paperName=NSPrinter.PaperName(rawValue:supported.id)
            info.paperSize=portraitPaper
        } else {
            info.paperSize=portraitPaper
        }

        info.orientation = landscape ? .landscape : .portrait
        info.topMargin=0;info.bottomMargin=0;info.leftMargin=0;info.rightMargin=0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered=true
        info.isVerticallyCentered=true

        let drawingPaper=landscape
            ? NSSize(width:portraitPaper.height,height:portraitPaper.width)
            : portraitPaper
        let view=V80BorderlessPrintView(image:image,size:drawingPaper)
        let op=NSPrintOperation(view:view,printInfo:info)
        op.jobTitle=title
        op.showsPrintPanel=false
        op.showsProgressPanel=false
        guard op.run() else {
            throw NSError(domain:"FTSPrinter",code:81,userInfo:[NSLocalizedDescriptionKey:"macOS hat den Druckauftrag nicht angenommen."])
        }
        return "NATIVE:"+UUID().uuidString
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

    static func diagnosticSnapshot(printerName:String) -> [String:String] {
        let uri=deviceURI(printerName:printerName)
        let details=printerDetails(printerName:printerName)
        let accepting=runLPStat(["-a",printerName])
        let active=runLPStat(["-W","not-completed","-o",printerName])
        let completed=runLPStat(["-W","completed","-o",printerName])
        let options=runProcess("/usr/bin/lpoptions",["-p",printerName,"-l"],timeout:2.0) ?? ""
        return [
            "device_uri":String(uri.prefix(1200)),
            "native_device_uri":String((nativeDeviceURI(printerName:printerName) ?? "").prefix(1200)),
            "native_queue_state":nativeQueueState(printerName:printerName) ?? "UNKNOWN",
            "native_papers":String(paperDiagnostic(printerName:printerName).prefix(8000)),
            "selected_postcard_paper":bestPostcardPaper(printerName:printerName).map { "\($0.name) [\($0.id)] \(Int($0.width))x\(Int($0.height))pt" } ?? "NONE",
            "connection_summary":connectionSummary(printerName:printerName),
            "usb_selphy_present":usbSELPHYPresent() ? "true" : "false",
            "lp_executable":firstExecutable(["/usr/bin/lp","/usr/sbin/lp","/bin/lp"]) ?? "MISSING",
            "lpstat_executable":firstExecutable(["/usr/bin/lpstat","/usr/sbin/lpstat","/bin/lpstat"]) ?? "MISSING",
            "printer_details":String(details.prefix(2000)),
            "accepting":String(accepting.prefix(1200)),
            "active_jobs":String(active.prefix(2000)),
            "completed_jobs":String(completed.prefix(2000)),
            "lpoptions":String(options.prefix(6000))
        ]
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

    static func waitUntilLikelyFinished(printerName:String,requestID:String,started:Date,estimated:TimeInterval) async throws {
        if requestID.hasPrefix("NATIVE:") {
            var sawProcessing=false
            let timeout=max(estimated*2.8,125)
            while true {
                try Task.checkCancellation()
                let elapsed=Date().timeIntervalSince(started)
                let state=await Task.detached(priority:.utility) {
                    nativeQueueState(printerName:printerName)
                }.value
                if state=="PROCESSING" { sawProcessing=true }
                if elapsed >= minimumPhysicalSeconds && sawProcessing && state=="IDLE" { return }
                if elapsed > timeout {
                    throw NSError(domain:"FTSPrinter",code:186,userInfo:[NSLocalizedDescriptionKey:"macOS hat den Auftrag angenommen, aber der physische Druck konnte nicht automatisch bestätigt werden. Ausdruck prüfen."])
                }
                try await Task.sleep(for:.seconds(2))
            }
        }

        let cupsID=requestID.hasPrefix("CUPS:") ? String(requestID.dropFirst(5)) : requestID
        var sawActive=false,sawCompleted=false,sawReachable=false
        let timeout=max(estimated*2.8,125)
        while true {
            try Task.checkCancellation()
            let elapsed=Date().timeIntervalSince(started)
            if elapsed>timeout {
                throw NSError(domain:"FTSPrinter",code:82,userInfo:[NSLocalizedDescriptionKey:"CUPS-Auftrag \(cupsID) wurde nicht sicher abgeschlossen. Ausdruck am Drucker prüfen."])
            }
            let state=await Task.detached(priority:.utility) {
                cupsJobState(printerName:printerName,requestID:cupsID)
            }.value
            sawActive = sawActive || state.active
            sawCompleted = sawCompleted || state.completed
            sawReachable = sawReachable || state.reachable
            if elapsed >= minimumPhysicalSeconds {
                if sawCompleted || (sawActive && !state.active) { return }
                if elapsed >= estimated+8 && !sawActive && !sawCompleted {
                    let why=sawReachable ? "macOS hat den Auftrag nicht in der CUPS-Warteschlange bestätigt." : "CUPS konnte während des Drucks nicht abgefragt werden."
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
    static let version = "1.1.21-fast-sd-auto-dispatch"
    static let build = 112

    @Published var workUnits: [V80WorkUnit] = []
    @Published var printerNodes: [V80PrinterNode] = []
    @Published var pickups: [V80Pickup] = []
    @Published var archived: [V80ArchiveRow] = []
    @Published var consumables: [V81Consumable] = []
    @Published var localQueue = V80LocalQueueFile()
    @Published var printerSlots: [LocalPrinterSlot] = []
    @Published var internetStatus = "FTS-Server: Verbindung wird geprüft …"
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

            // One-time cleanup for the failed test queue from the pre-native print builds.
            // Do not touch successful/ready jobs.
            let migrationKey="fts.printer.cleanup.failed.v94"
            if !UserDefaults.standard.bool(forKey:migrationKey) {
                localQueue.jobs.removeAll { $0.status == .uncertain || $0.status == .cancelled }
                UserDefaults.standard.set(true,forKey:migrationKey)
            }
            try? V80QueueStore.save(localQueue, folderPath: folderPath)
            reconcileMediaWorkflow()
        }
    }

    private func mediaIDs(in job:V80LocalPrintJob)->Set<String> {
        Set(job.units.map{$0.mediaID})
    }

    private func mediaIDsNeededByOtherActiveJobs(excluding jobID:UUID)->Set<String> {
        var ids=Set<String>()
        for job in localQueue.jobs where job.id != jobID && [.waiting,.printing,.uncertain].contains(job.status) {
            ids.formUnion(mediaIDs(in:job))
        }
        return ids
    }

    private func reconcileMediaWorkflow() {
        guard !loadedFolderPath.isEmpty else{return}
        var active=Set<String>()
        var produced=Set<String>()
        var delivered=Set<String>()
        var errors=Set<String>()
        for job in localQueue.jobs {
            switch job.status {
            case .waiting,.printing,.uncertain:
                active.formUnion(mediaIDs(in:job))
            case .readyForPickup:
                produced.formUnion(mediaIDs(in:job))
            case .archived:
                delivered.formUnion(mediaIDs(in:job))
            case .cancelled:
                errors.formUnion(mediaIDs(in:job))
            }
        }
        produced.subtract(active)
        delivered.subtract(active)
        errors.subtract(active)
        errors.subtract(produced)
        errors.subtract(delivered)
        try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:active,status:.queued,moveDesignedFile:false)
        try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:errors,status:.error,moveDesignedFile:true)
        try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:produced,status:.produced,moveDesignedFile:true)
        try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:delivered,status:.delivered,moveDesignedFile:true)
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
        async let namesTask = V80MacSpooler.installedPrinterNames()
        async let internetTask = Task.detached(priority:.utility) {
            V80MacSpooler.internetConnectionSummary()
        }.value
        var names = await namesTask
        internetStatus = await internetTask
        names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var enabled = Set(UserDefaults.standard.stringArray(forKey: "fts.enabled.printers.v80") ?? [])
        let liveEnabled=names.filter{enabled.contains($0)}
        if liveEnabled.isEmpty {
            let liveSelphy=names.filter {
                let lower=$0.lowercased()
                return lower.contains("selphy") || lower.contains("cp1500")
            }
            if liveSelphy.count==1,let only=liveSelphy.first {
                enabled.insert(only)
                UserDefaults.standard.set(Array(enabled).sorted(),forKey:"fts.enabled.printers.v80")
            }
        }

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
                slot.connection = V80MacSpooler.connectionSummary(printerName:name)
                next.append(slot)
            } else {
                next.append(LocalPrinterSlot(name: name, enabled: enabled.contains(name), state: "IDLE", eta: 0, currentUnit: nil, lastError: nil, connection: V80MacSpooler.connectionSummary(printerName:name)))
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
        async let installedTask = V80MacSpooler.installedPrinterNames()
        async let internetTask = Task.detached(priority:.utility) {
            V80MacSpooler.internetConnectionSummary()
        }.value
        let installed=Set(await installedTask)
        internetStatus=await internetTask

        // Build 103: no ghost printers. As soon as a transport is no longer physically
        // confirmed/reachable, remove that printer from every local display.
        printerSlots.removeAll { !installed.contains($0.name) }
        printerConnectivityFailures=printerConnectivityFailures.filter{installed.contains($0.key)}

        for slot in printerSlots where slot.enabled {
            guard activePrinterTasks[slot.name] == nil else { continue }
            guard slot.state == "IDLE" || slot.state == "ERROR" else { continue }
            let name=slot.name
            printerConnectivityFailures[name]=0
            let nativeState=await Task.detached(priority:.utility) {
                V80MacSpooler.nativeQueueState(printerName:name)
            }.value
            let connection=await Task.detached(priority:.utility) {
                V80MacSpooler.connectionSummary(printerName:name)
            }.value
            if let i=printerSlots.firstIndex(where:{$0.name==name}) {
                printerSlots[i].connection=connection
            }
            if nativeState=="STOPPED" && slot.state != "ERROR" {
                setSlot(name,state:"ERROR",eta:0,current:nil,error:"macOS-Druckwarteschlange ist gestoppt. Drucker in macOS prüfen.")
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
            let diagnostic = await Task.detached(priority:.utility) {
                V80MacSpooler.diagnosticSnapshot(printerName:printerName)
            }.value
            let _:Bool? = try? await api.rpc("fts_printer_mark_local_uncertain_v95",body:[
                "p_device_token":dev,
                "p_session_token":session,
                "p_local_job_id":jobID.uuidString,
                "p_printer_key":backendPrinterKey(printerName),
                "p_error":error.localizedDescription,
                "p_details":diagnostic
            ],as:Bool.self)
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
            let stillNeeded=mediaIDsNeededByOtherActiveJobs(excluding:jobID)
            let finishedIDs=mediaIDs(in:localQueue.jobs[ji]).subtracting(stillNeeded)
            do {
                try MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:finishedIDs,status:.produced,moveDesignedFile:true)
            } catch {
                lastError="Druck fertig, aber die lokale Datei konnte nicht nach Archiv/Produziert verschoben werden: \(error.localizedDescription)"
            }
            await refresh(state:state)
        } catch {
            localQueue.jobs[ji].status = .uncertain
            saveLocalQueue()
            lastError="Alle Ausdrucke sind fertig, aber der Abschluss konnte noch nicht synchronisiert werden. Keine Fotos erneut drucken."
        }
    }

    func requeueLocalUnit(jobID:UUID,unitID:UUID,confirmedNotPrinted:Bool,state:AppState) async {
        guard confirmedNotPrinted,
              let dev=state.deviceToken,let session=state.sessionToken,
              let ji=localQueue.jobs.firstIndex(where:{$0.id==jobID}),
              let ui=localQueue.jobs[ji].units.firstIndex(where:{$0.id==unitID}),
              localQueue.jobs[ji].units[ui].status == .uncertain else{return}

        let oldPrinter=localQueue.jobs[ji].units[ui].printerName
        do {
            let ok:Bool = try await api.rpc("fts_printer_requeue_local_job_v95",body:[
                "p_device_token":dev,"p_session_token":session,"p_local_job_id":jobID.uuidString
            ])
            guard ok else {
                throw NSError(domain:"FTSPrinter",code:195,userInfo:[NSLocalizedDescriptionKey:"Auftrag konnte serverseitig nicht erneut freigegeben werden."])
            }

            localQueue.jobs[ji].units[ui].status = .waiting
            localQueue.jobs[ji].units[ui].printerName = nil
            localQueue.jobs[ji].units[ui].startedAt = nil
            localQueue.jobs[ji].units[ui].lastError = nil
            localQueue.jobs[ji].status = .waiting
            saveLocalQueue()

            if let oldPrinter { clearPrinterError(oldPrinter) }
            lastError=nil
            await refresh(state:state)
            dispatchAvailable(state:state)
        } catch {
            lastError=error.localizedDescription
        }
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
            do {
                try MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:Set(filtered.map{$0.key.id}),status:.queued,moveDesignedFile:false)
            } catch {
                lastError="Auftrag angelegt, aber die Fotos konnten nicht aus der aktiven Auswahl ausgeblendet werden: \(error.localizedDescription)"
            }
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

    func purgeFailedLocalJobs(state: AppState) async {
        guard let dev=state.deviceToken,let session=state.sessionToken,!state.selectedEventToken.isEmpty else{return}
        do {
            let failedIDs=Set(localQueue.jobs
                .filter{$0.status == .uncertain || $0.status == .cancelled || $0.status == .waiting}
                .flatMap{$0.units.map{$0.mediaID}})
            let deleted:Int = try await api.rpc("fts_printer_purge_failed_local_jobs_v96",body:[
                "p_device_token":dev,
                "p_session_token":session,
                "p_event_token":state.selectedEventToken
            ])
            localQueue.jobs.removeAll {
                $0.status == .uncertain || $0.status == .cancelled || $0.status == .waiting
            }
            saveLocalQueue()
            try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:failedIDs,status:.error,moveDesignedFile:true)
            // A failed local print can leave the slot red. Purging the failed jobs
            // is an explicit operator decision that none of them should run.
            for slot in printerSlots where slot.state == "ERROR" || slot.state == "OFFLINE" {
                clearPrinterError(slot.name)
            }
            lastError = deleted > 0 ? "\(deleted) alte/fehlgeschlagene Druckaufträge entfernt." : nil
            await refresh(state:state)
        } catch {
            lastError=error.localizedDescription
        }
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
                let failedIDs=mediaIDs(in:localQueue.jobs[i])
                try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:failedIDs,status:.error,moveDesignedFile:true)
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
                let jobID=localQueue.jobs[ji].id
                localQueue.jobs[ji].status = .archived
                saveLocalQueue()
                let stillNeeded=mediaIDsNeededByOtherActiveJobs(excluding:jobID)
                let deliveredIDs=mediaIDs(in:localQueue.jobs[ji]).subtracting(stillNeeded)
                try? MediaIngestV80.setWorkflowSync(folderPath:loadedFolderPath,mediaIDs:deliveredIDs,status:.delivered,moveDesignedFile:true)
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

        let fm=FileManager.default
        let ext=u.pathExtension.isEmpty ? "dmg" : u.pathExtension
        let dest=fm.urls(for:.downloadsDirectory,in:.userDomainMask).first!
            .appendingPathComponent("FTS-Printer-\(r.version).\(ext)")

        // If a previous attempt already completed correctly, reuse it instead of downloading again.
        if fm.fileExists(atPath:dest.path),
           (try? Self.fileSHA256(dest))==expected {
            lastError=nil
            return dest
        }
        try? fm.removeItem(at:dest)

        var finalError:Error?
        for attempt in 1...3 {
            do {
                var request=URLRequest(url:u,cachePolicy:.reloadIgnoringLocalAndRemoteCacheData,timeoutInterval:180)
                request.setValue("application/octet-stream",forHTTPHeaderField:"Accept")
                let (tmp,response)=try await URLSession.shared.download(for:request)
                if let http=response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(domain:"FTSPrinter",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:"Update-Server HTTP \(http.statusCode)"])
                }
                let actual=try Self.fileSHA256(tmp)
                guard actual==expected else {
                    try? fm.removeItem(at:tmp)
                    throw NSError(domain:"FTSPrinter",code:88,userInfo:[NSLocalizedDescriptionKey:"Update-Prüfsumme stimmt nicht. Datei wurde verworfen."])
                }
                try? fm.removeItem(at:dest)
                try fm.moveItem(at:tmp,to:dest)
                lastError=nil
                return dest
            } catch {
                finalError=error
                if attempt<3 {
                    try? await Task.sleep(for:.seconds(Double(attempt)))
                }
            }
        }

        lastError="Update konnte nach 3 Versuchen nicht geladen werden: \(finalError?.localizedDescription ?? "Unbekannter Fehler")"
        return nil
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
