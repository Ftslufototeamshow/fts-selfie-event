import SwiftUI
import AppKit
import Foundation
import Security
import CryptoKit
import ImageIO

// MARK: - Configuration

enum FTSConfig {
    static let supabaseURL = URL(string: "https://hivmiqktbaatghuaxfvg.supabase.co")!
    static let publishableKey = "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P"
    static let liveBucket = "fts-selfie-live"
}

// MARK: - JSON

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON") }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var double: Double? {
        switch self { case .number(let v): return v; case .string(let s): return Double(s); default: return nil }
    }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    subscript(_ key: String) -> JSONValue? { object?[key] }
}

// MARK: - API Models

struct DeviceAdminChoice: Codable, Identifiable, Hashable {
    let user_id: String
    let display_name: String
    var id: String { user_id }
}

struct StaffChoice: Codable, Identifiable, Hashable {
    let user_id: String
    let display_name: String
    let role: String
    var id: String { user_id }
    var roleLabel: String { role == "printer_admin" ? "Printer-Administrator" : "Mitarbeiter" }
}

struct SessionInfo: Codable, Hashable {
    let session_token: String?
    let user_id: String?
    let display_name: String?
    let role: String?
    let expires_at: String?
    let valid: Bool?
    var roleLabel: String { role == "printer_admin" ? "Printer-Administrator" : "Mitarbeiter" }
}

struct EventRow: Codable, Identifiable, Hashable {
    let event_token: String
    let short_code: String?
    let event_title: String
    let subtitle: String?
    let overlay_text: String?
    let organizer_name: String?
    let location: String?
    let event_date: String?
    let expires_at: String?
    let print_enabled: Bool?
    let print_starts_at: String?
    let print_ends_at: String?
    let print_window_active: Bool?
    let operation_mode: String?
    let local_camera_photos: Bool?
    let event_days: JSONValue?
    let accent: String?
    let photo_branding: String?
    let logo_items: JSONValue?
    let decoration_items: JSONValue?
    let studio_config: JSONValue?
    let stock: JSONValue?
    var id: String { event_token }
}

struct OrderItem: Codable, Hashable, Identifiable {
    let photo_id: String?
    let designed_path: String?
    let quantity: Int?
    var id: String { (photo_id ?? UUID().uuidString) + "-" + (designed_path ?? "") }
}

struct PrintOrder: Codable, Identifiable, Hashable {
    let order_id: String
    let event_token: String
    let event_title: String?
    let quantity_total: Int?
    let total_cents: Int?
    let currency: String?
    let payment_status: String?
    let print_status: String?
    let pickup_code: String?
    let pickup_status: String?
    let created_at: String?
    let paid_at: String?
    let printed_at: String?
    let receipt_number: String?
    let is_test: Bool?
    let items: [OrderItem]?
    var id: String { order_id }
    var ready: Bool {
        ["COMPLETED","COVERED","FREE"].contains((payment_status ?? "").uppercased()) && (print_status ?? "").uppercased() == "READY"
    }
}

struct StockSnapshot: Codable, Hashable {
    let managed: Bool?
    let safe_start_qty: Int?
    let open_stock_unknown: Bool?
    let open_stock_estimate: Int?
    let safe_available: Int?
    let selfie_printed: Int?
    let selfie_waiting: Int?
    let active_reservations: Int?
    let camera_waiting: Int?
    let camera_prints: Int?
    let test_prints: Int?
    let misprints: Int?
    let reprints: Int?
    let added_stock: Int?
    let correction_delta: Int?
    let total_consumed: Int?
    let total_committed: Int?
    let note: String?
}

struct Receipt: Codable, Identifiable, Hashable {
    let receipt_number: String?
    let event_title: String?
    let organizer_name: String?
    let event_date: String?
    let quantity_total: Int?
    let total_cents: Int?
    let refund_cents: Int?
    let currency: String?
    let payment_method: String?
    let payment_environment: String?
    let is_test: Bool?
    let pickup_code: String?
    let payment_status: String?
    let paid_at: String?
    let items: JSONValue?
    var id: String { receipt_number ?? UUID().uuidString }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "lu.fts.printer.secure.v2"
    @discardableResult
    static func set(_ value: String, key: String) -> Bool {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func remove(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - API

struct APIErrorPayload: Codable { let message: String?; let hint: String?; let details: String? }

final class FTSAPI {
    static let shared = FTSAPI()
    private let decoder = JSONDecoder()

    func rpc<T: Decodable>(_ name: String, body: [String: Any], as type: T.Type = T.self) async throws -> T {
        var req = URLRequest(url: FTSConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        req.httpMethod = "POST"
        req.setValue(FTSConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(FTSConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let p = try? decoder.decode(APIErrorPayload.self, from: data) {
                throw NSError(domain: "FTSPrinter", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                              userInfo: [NSLocalizedDescriptionKey: p.message ?? p.hint ?? "Serverfehler"])
            }
            let text = String(data: data, encoding: .utf8) ?? "Serverfehler"
            throw NSError(domain: "FTSPrinter", code: -1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        return try decoder.decode(T.self, from: data)
    }

    func imageData(storagePath: String) async throws -> Data {
        let encoded = storagePath.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let url = FTSConfig.supabaseURL.appendingPathComponent("storage/v1/object/public/\(FTSConfig.liveBucket)/\(encoded)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "FTSPrinter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Foto konnte nicht geladen werden."])
        }
        return data
    }

    func imageURL(storagePath: String) -> URL? {
        let encoded = storagePath.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "\(FTSConfig.supabaseURL.absoluteString)/storage/v1/object/public/\(FTSConfig.liveBucket)/\(encoded)")
    }
}

// MARK: - Printing

final class ImagePrintView: NSView {
    let image: NSImage
    init(image: NSImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let iw = max(image.size.width, 1), ih = max(image.size.height, 1)
        let scale = min(bounds.width / iw, bounds.height / ih)
        let size = NSSize(width: iw * scale, height: ih * scale)
        let rect = NSRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    }
}

enum Printer {
    @MainActor
    static func printImage(_ image: NSImage, copies: Int, title: String) -> Bool {
        let landscape = image.size.width > image.size.height
        let paper = landscape ? NSSize(width: 432, height: 288) : NSSize(width: 288, height: 432)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = paper
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.dictionary()[NSPrintInfo.AttributeKey(rawValue: "NSPrintCopies")] = max(1, copies)
        let view = ImagePrintView(image: image, size: paper)
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = title
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        return op.run()
    }

    @MainActor
    static func printReceipt(_ text: String) -> Bool {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 760))
        view.string = text
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textColor = .black
        view.backgroundColor = .white
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = "FTS Kundenbeleg"
        op.showsPrintPanel = true
        return op.run()
    }
}

// MARK: - Local Event Folder and Card Import

struct LocalActivation: Codable {
    let eventToken: String
    let folderPath: String
    let activatedAt: Date
}

struct ImportRecord: Codable, Identifiable, Hashable {
    var id: String { sha256 }
    let sha256: String
    let sourcePath: String
    let importedPath: String
    let originalName: String
    let cardID: String
    let cameraID: String?
    let importedAt: Date
}

struct ImportManifest: Codable {
    var records: [ImportRecord] = []
}

@MainActor
final class LocalImportManager: ObservableObject {
    @Published var activation: LocalActivation?
    @Published var imported: [ImportRecord] = []
    @Published var status = "Lokaler Eventordner noch nicht freigegeben."
    @Published var lastSource = ""
    @Published var scanning = false

    private func key(_ event: EventRow) -> String { "fts.local.activation.\(event.event_token)" }

    func load(event: EventRow) {
        guard let data = UserDefaults.standard.data(forKey: key(event)),
              let a = try? JSONDecoder().decode(LocalActivation.self, from: data) else {
            activation = nil; imported = []; status = "Ordner ist vorbereitet. Erst mit Freigabe wird er auf diesem Mac erstellt."; return
        }
        activation = a
        loadManifest()
        status = "Lokaler Eventordner aktiv."
    }

    func activate(event: EventRow) throws {
        let fm = FileManager.default
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let root = pictures.appendingPathComponent("FTS Print Events", isDirectory: true)
        let code = sanitize(event.short_code ?? event.event_token)
        let name = sanitize(event.event_title)
        let folder = root.appendingPathComponent("\(code) - \(name)", isDirectory: true)
        try fm.createDirectory(at: folder.appendingPathComponent("Kamera Original", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("Bearbeitet", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("Druckbereit", isDirectory: true), withIntermediateDirectories: true)
        let a = LocalActivation(eventToken: event.event_token, folderPath: folder.path, activatedAt: Date())
        activation = a
        let data = try JSONEncoder().encode(a)
        UserDefaults.standard.set(data, forKey: key(event))
        if !fm.fileExists(atPath: folder.appendingPathComponent(".fts-import-index.json").path) {
            try JSONEncoder().encode(ImportManifest()).write(to: folder.appendingPathComponent(".fts-import-index.json"), options: .atomic)
        }
        loadManifest()
        status = "Event lokal freigegeben. Neue Fotos auf eingelegten Karten werden automatisch erkannt."
    }

    func revealFolder() {
        guard let activation else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: activation.folderPath))
    }

    func scan(event: EventRow) async {
        guard let activation, !scanning else { return }
        scanning = true
        status = "Speicherkarten werden geprüft …"
        do {
            let result = try await Task.detached(priority: .utility) {
                try Self.scanSync(activation: activation)
            }.value
            imported = result.records.sorted { $0.importedAt > $1.importedAt }
            lastSource = result.lastSource
            status = result.newCount > 0 ? "\(result.newCount) neue Foto\(result.newCount == 1 ? "" : "s") importiert." : "Keine neuen Fotos. Kartenüberwachung aktiv."
        } catch {
            status = "Kartenprüfung: \(error.localizedDescription)"
        }
        scanning = false
    }

    private func loadManifest() {
        guard let activation else { return }
        let url = URL(fileURLWithPath: activation.folderPath).appendingPathComponent(".fts-import-index.json")
        guard let data = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(ImportManifest.self, from: data) else {
            imported = []; return
        }
        imported = m.records.sorted { $0.importedAt > $1.importedAt }
    }

    nonisolated private static func scanSync(activation: LocalActivation) throws -> (records: [ImportRecord], newCount: Int, lastSource: String) {
        let fm = FileManager.default
        let eventFolder = URL(fileURLWithPath: activation.folderPath)
        let originalFolder = eventFolder.appendingPathComponent("Kamera Original", isDirectory: true)
        let manifestURL = eventFolder.appendingPathComponent(".fts-import-index.json")
        var manifest = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(ImportManifest.self, from: $0) } ?? ImportManifest()
        var hashes = Set(manifest.records.map(\.sha256))
        var newCount = 0
        var sourceLabel = ""

        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey, .volumeNameKey, .volumeIdentifierKey]
        let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        for volume in volumes {
            let rv = try? volume.resourceValues(forKeys: keys)
            let removable = rv?.volumeIsRemovable == true || rv?.volumeIsEjectable == true
            let internalVol = rv?.volumeIsInternal == true
            if !removable || internalVol { continue }
            let volumeName = rv?.volumeName ?? volume.lastPathComponent
            let volumeID = rv?.volumeIdentifier.map { String(describing: $0) } ?? volumeName
            sourceLabel = "\(volumeName) · \(volumeID)"
            let dcim = volume.appendingPathComponent("DCIM", isDirectory: true)
            let start = fm.fileExists(atPath: dcim.path) ? dcim : volume
            guard let en = fm.enumerator(at: start, includingPropertiesForKeys: [.isRegularFileKey,.contentModificationDateKey], options: [.skipsHiddenFiles,.skipsPackageDescendants]) else { continue }

            for case let file as URL in en {
                let ext = file.pathExtension.lowercased()
                guard ["jpg","jpeg","heic","png"].contains(ext) else { continue }
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey,.contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }
                if let mod = values?.contentModificationDate, mod < activation.activatedAt.addingTimeInterval(-300) { continue }

                let hash = try sha256(file)
                if hashes.contains(hash) { continue }

                let dest = uniqueDestination(folder: originalFolder, name: file.lastPathComponent)
                try fm.copyItem(at: file, to: dest)
                let rec = ImportRecord(
                    sha256: hash,
                    sourcePath: file.path,
                    importedPath: dest.path,
                    originalName: file.lastPathComponent,
                    cardID: volumeID,
                    cameraID: cameraIdentity(file),
                    importedAt: Date()
                )
                manifest.records.append(rec)
                hashes.insert(hash)
                newCount += 1
            }
        }
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        return (manifest.records, newCount, sourceLabel)
    }

    nonisolated private static func sha256(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            guard let data = try h.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func uniqueDestination(folder: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)_\(i).\(ext)")
            i += 1
        }
        return candidate
    }

    nonisolated private static func cameraIdentity(_ url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return nil }
        let tiff = props["{TIFF}"] as? [String: Any]
        let exif = props["{Exif}"] as? [String: Any]
        let make = (tiff?["Make"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (tiff?["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let serial = (exif?["BodySerialNumber"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [make, model, serial].compactMap { ($0?.isEmpty == false) ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sanitize(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return s.components(separatedBy: illegal).joined(separator: "-").replacingOccurrences(of: "  ", with: " ")
    }
}

// MARK: - Local Event Renderer

enum LocalRenderer {
    static func renderedImage(sourceURL: URL, event: EventRow) throws -> NSImage {
        guard let source = NSImage(contentsOf: sourceURL) else {
            throw NSError(domain: "FTSPrinter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lokales Foto konnte nicht geöffnet werden."])
        }
        let landscape = source.size.width > source.size.height
        let canvas = landscape ? NSSize(width: 1800, height: 1200) : NSSize(width: 1200, height: 1800)
        let out = NSImage(size: canvas)
        out.lockFocus()
        defer { out.unlockFocus() }

        NSColor.black.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        drawAspectFill(source, in: NSRect(origin: .zero, size: canvas))

        let overlay = event.studio_config?["overlay"]?.object
        let banner = overlay?["banner"]?.object
        let requested = banner?["height_pct"]?.double ?? 30
        let heightPct = landscape ? min(max(requested, 16), 24) : min(max(requested, 12), 48)
        let bannerH = canvas.height * heightPct / 100
        let bannerRect = NSRect(x: 0, y: 0, width: canvas.width, height: bannerH)
        let color = NSColor(hex: banner?["color"]?.string ?? "#071315")
        let opacity = banner?["opacity"]?.double ?? 0.86
        if banner?["enabled"]?.bool != false {
            color.withAlphaComponent(opacity).setFill()
            bannerRect.fill()
        }

        let pad = canvas.width * 0.045
        let shortSide = min(canvas.width, canvas.height)
        let titleSpec = overlay?["title"]?.object
        let subSpec = overlay?["subtitle"]?.object
        let lineSpec = overlay?["line"]?.object
        let title = nonEmpty(titleSpec?["text"]?.string) ?? event.event_title
        let subtitle = nonEmpty(subSpec?["text"]?.string) ?? event.subtitle ?? ""
        let line = nonEmpty(lineSpec?["text"]?.string) ?? event.overlay_text ?? ""

        var y = bannerH - pad * 0.35
        if !title.isEmpty {
            let sz = max(28, shortSide * (titleSpec?["size_pct"]?.double ?? 5.8) / 100)
            drawText(title, x: pad, topY: y, maxWidth: canvas.width-pad*2, size: sz, weight: .heavy, color: NSColor(hex: titleSpec?["color"]?.string ?? "#ffffff"))
            y -= sz * 1.25
        }
        if !subtitle.isEmpty {
            let sz = max(20, shortSide * (subSpec?["size_pct"]?.double ?? 3.2) / 100)
            drawText(subtitle, x: pad, topY: y, maxWidth: canvas.width-pad*2, size: sz, weight: .bold, color: NSColor(hex: subSpec?["color"]?.string ?? event.accent ?? "#d9b56d"))
            y -= sz * 1.28
        }
        if !line.isEmpty {
            let sz = max(16, shortSide * (lineSpec?["size_pct"]?.double ?? 2.1) / 100)
            drawText(line, x: pad, topY: y, maxWidth: canvas.width-pad*2, size: sz, weight: .semibold, color: NSColor(hex: lineSpec?["color"]?.string ?? "#e8efed"))
        }

        if event.photo_branding != "none" {
            let brand = "FTS.lu · Selfie Event" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(14, shortSide*0.015), weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.68)
            ]
            let size = brand.size(withAttributes: attrs)
            brand.draw(at: NSPoint(x: canvas.width-pad-size.width, y: 14), withAttributes: attrs)
        }
        return out
    }

    private static func drawAspectFill(_ image: NSImage, in rect: NSRect) {
        let iw=max(image.size.width,1), ih=max(image.size.height,1)
        let scale=max(rect.width/iw,rect.height/ih)
        let size=NSSize(width:iw*scale,height:ih*scale)
        let target=NSRect(x:(rect.width-size.width)/2,y:(rect.height-size.height)/2,width:size.width,height:size.height)
        image.draw(in: target, from: .zero, operation: .copy, fraction: 1)
    }
    private static func drawText(_ text: String, x: CGFloat, topY: CGFloat, maxWidth: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:p]
        let s = text as NSString
        let h = size*1.3
        s.draw(in:NSRect(x:x,y:max(0,topY-h),width:maxWidth,height:h),withAttributes:attrs)
    }
    private static func nonEmpty(_ value:String?)->String? {
        guard let v=value?.trimmingCharacters(in:.whitespacesAndNewlines),!v.isEmpty else{return nil};return v
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s=hex.trimmingCharacters(in:.whitespacesAndNewlines)
        if s.hasPrefix("#"){s.removeFirst()}
        var v:UInt64=0;Scanner(string:s).scanHexInt64(&v)
        if s.count==6 { self.init(red:CGFloat((v>>16)&255)/255,green:CGFloat((v>>8)&255)/255,blue:CGFloat(v&255)/255,alpha:1) }
        else { self.init(white:1,alpha:1) }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    enum Phase { case boot, deviceSetup, staffLogin, main }
    @Published var phase: Phase = .boot
    @Published var deviceAdmins: [DeviceAdminChoice] = []
    @Published var staffChoices: [StaffChoice] = []
    @Published var currentUser: SessionInfo?
    @Published var events: [EventRow] = []
    @Published var selectedEventToken = ""
    @Published var orders: [PrintOrder] = []
    @Published var stock: StockSnapshot?
    @Published var currentReceipt: Receipt?
    @Published var errorMessage: String?
    @Published var busy = false
    @Published var status = ""

    let localImport = LocalImportManager()
    let mediaIngest = MediaIngestV80()
    let production = ProductionCore()
    private let api = FTSAPI.shared
    private var liveDeviceToken: String?
    private var liveSessionToken: String?
    static let appVersion = "0.2.3-printer-health"

    var deviceToken: String? { liveDeviceToken ?? Keychain.get("deviceToken") }
    var sessionToken: String? { liveSessionToken ?? Keychain.get("staffSession") }
    var selectedEvent: EventRow? { events.first(where: {$0.event_token == selectedEventToken}) }

    @discardableResult
    func recoverAuthentication(from error: Error) async -> Bool {
        let message=error.localizedDescription
        if message.localizedCaseInsensitiveContains("Printer-Gerät nicht freigeschaltet") {
            liveSessionToken=nil;liveDeviceToken=nil
            Keychain.remove("staffSession")
            Keychain.remove("deviceToken")
            currentUser=nil
            events=[];orders=[];stock=nil;selectedEventToken=""
            status="Gerätefreigabe erneuern."
            errorMessage=nil
            await loadDeviceAdmins()
            return true
        }
        if message.localizedCaseInsensitiveContains("Printer-Sitzung ist nicht gültig") {
            liveSessionToken=nil
            Keychain.remove("staffSession")
            currentUser=nil
            orders=[];stock=nil
            status="Sitzung abgelaufen · bitte Mitarbeiter neu anmelden."
            errorMessage=nil
            await loadChoices()
            return true
        }
        return false
    }

    func bootstrap() async {
        if liveDeviceToken == nil { liveDeviceToken = Keychain.get("deviceToken") }
        if liveSessionToken == nil { liveSessionToken = Keychain.get("staffSession") }
        guard let dev = deviceToken, !dev.isEmpty else { await loadDeviceAdmins(); return }
        if let session = sessionToken, !session.isEmpty {
            do {
                let info: SessionInfo = try await api.rpc("fts_printer_validate_session_v72", body: ["p_device_token":dev,"p_session_token":session])
                if info.valid == true {
                    currentUser = info
                    if await loadEvents() {
                        phase = .main
                        return
                    }
                    await loadChoices()
                    return
                }
            } catch {}
            Keychain.remove("staffSession")
        }
        await loadChoices()
    }

    func loadDeviceAdmins() async {
        busy=true; defer{busy=false}
        do {
            let rows:[DeviceAdminChoice] = try await api.rpc("fts_printer_device_admin_choices_v75",body:[:])
            deviceAdmins=rows
            phase = .deviceSetup
        } catch {
            deviceAdmins=[]
            phase = .deviceSetup
            errorMessage=error.localizedDescription
        }
    }

    func activateDevice(admin: DeviceAdminChoice, code: String) async {
        guard !code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { errorMessage="Persönlichen Administrator-Code eingeben."; return }
        busy=true; defer{busy=false}
        do {
            let token: String = try await api.rpc("fts_printer_register_device_v75", body:[
                "p_user_id":admin.user_id,
                "p_code":code,
                "p_label":"FTS Printer · \(Host.current().localizedName ?? "Mac")",
                "p_user_agent":"FTS Printer macOS 0.2.3-printer-health"
            ])
            liveDeviceToken=token
            _ = Keychain.set(token,key:"deviceToken")
            await loadChoices()
        } catch { errorMessage=error.localizedDescription }
    }

    func loadChoices() async {
        guard let dev=deviceToken else { await loadDeviceAdmins(); return }
        do {
            let rows:[StaffChoice] = try await api.rpc("fts_printer_login_choices_v72",body:["p_device_token":dev])
            staffChoices=rows;phase = .staffLogin
        } catch {
            if !(await recoverAuthentication(from:error)) {
                errorMessage=error.localizedDescription
                phase = .deviceSetup
            }
        }
    }

    func login(user: StaffChoice, code: String) async {
        guard let dev=deviceToken else{return}
        busy=true;defer{busy=false}
        do {
            let info:SessionInfo = try await api.rpc("fts_printer_login_v72",body:[
                "p_device_token":dev,"p_user_id":user.user_id,"p_code":code,
                "p_device_label":"FTS Printer · \(Host.current().localizedName ?? "Mac")",
                "p_user_agent":"FTS Printer macOS 0.2.3-printer-health"
            ])
            guard let session=info.session_token else{throw NSError(domain:"FTSPrinter",code:-1,userInfo:[NSLocalizedDescriptionKey:"Keine Printer-Sitzung erhalten."])}
            liveSessionToken=session
            _ = Keychain.set(session,key:"staffSession")
            currentUser=info
            if await loadEvents() {
                phase = .main
            } else {
                phase = .staffLogin
            }
        } catch { errorMessage=error.localizedDescription }
    }

    func switchStaff() async {
        if production.printerSlots.contains(where:{["PREPARING","TRANSFER","PRINTING"].contains($0.state)}) {
            errorMessage="Mitarbeiterwechsel erst möglich, wenn alle Drucker sicher frei sind."
            return
        }
        production.autoDispatch=false
        if let dev=deviceToken,let session=sessionToken {
            let _:Bool? = try? await api.rpc("fts_printer_logout_v72",body:["p_device_token":dev,"p_session_token":session],as:Bool.self)
        }
        liveSessionToken=nil
        Keychain.remove("staffSession");currentUser=nil;orders=[];stock=nil
        await loadChoices()
    }

    func resetDevice() {
        if production.printerSlots.contains(where:{["PREPARING","TRANSFER","PRINTING"].contains($0.state)}) {
            errorMessage="Gerätefreigabe kann während eines laufenden Drucks nicht zurückgesetzt werden."
            return
        }
        production.autoDispatch=false
        liveSessionToken=nil;liveDeviceToken=nil
        Keychain.remove("staffSession");Keychain.remove("deviceToken");currentUser=nil;events=[];orders=[];phase = .deviceSetup
    }

    @discardableResult
    func loadEvents() async -> Bool {
        guard let dev=deviceToken,let session=sessionToken else{return false}
        busy=true;defer{busy=false}
        do {
            let rows:[EventRow]=try await api.rpc("fts_printer_events_v74",body:["p_device_token":dev,"p_session_token":session])
            events=rows
            if !rows.contains(where:{$0.event_token==selectedEventToken}) { selectedEventToken=rows.first?.event_token ?? "" }
            if let e=selectedEvent {
                localImport.load(event:e)
                mediaIngest.load(event:e)
                production.loadLocalQueue(folderPath:mediaIngest.activation?.folderPath)
            }
            if selectedEventToken.isEmpty {
                orders=[]
                stock=nil
                status="Kein freigegebenes Printer-Event gefunden."
            } else {
                await refreshSelected()
            }
            return true
        } catch {
            if await recoverAuthentication(from:error) { return false }
            errorMessage="Events konnten nicht geladen werden: "+error.localizedDescription
            return false
        }
    }

    func selectEvent(_ token:String) async {
        selectedEventToken=token
        if let e=selectedEvent {
                localImport.load(event:e)
                mediaIngest.load(event:e)
                production.loadLocalQueue(folderPath:mediaIngest.activation?.folderPath)
            }
        await refreshSelected()
    }

    private func isTransientNetworkError(_ error:Error) -> Bool {
        let m=error.localizedDescription.lowercased()
        return m.contains("timed out")
            || m.contains("timeout")
            || m.contains("network")
            || m.contains("internet")
            || m.contains("connection")
            || m.contains("offline")
            || m.contains("host")
            || m.contains("socket")
            || m.contains("dns")
    }

    func refreshSelected() async {
        guard let dev=deviceToken,let session=sessionToken,!selectedEventToken.isEmpty else{return}
        do {
            async let o:[PrintOrder]=api.rpc("fts_printer_orders_v73",body:["p_device_token":dev,"p_session_token":session,"p_event_token":selectedEventToken])
            async let s:StockSnapshot=api.rpc("fts_printer_stock_v73",body:["p_device_token":dev,"p_session_token":session,"p_event_token":selectedEventToken])
            let (oo,ss)=try await(o,s);orders=oo;stock=ss
            status="Aktuell · \(Date().formatted(date:.omitted,time:.shortened))"
        } catch {
            if await recoverAuthentication(from:error) { return }
            if isTransientNetworkError(error) {
                status="Offline · Verbindung wird automatisch erneut versucht"
                return
            }
            errorMessage=error.localizedDescription
        }
    }

    func printOrder(_ order:PrintOrder) async {
        guard order.ready else{return}
        busy=true;defer{busy=false}
        do {
            guard let items=order.items,!items.isEmpty else{throw NSError(domain:"FTSPrinter",code:-1,userInfo:[NSLocalizedDescriptionKey:"Keine Druckdatei im Auftrag."])}
            for item in items {
                guard let path=item.designed_path else{continue}
                let data=try await api.imageData(storagePath:path)
                guard let image=NSImage(data:data) else{throw NSError(domain:"FTSPrinter",code:-1,userInfo:[NSLocalizedDescriptionKey:"Druckfoto konnte nicht geöffnet werden."])}
                let ok=Printer.printImage(image,copies:max(1,item.quantity ?? 1),title:"FTS Selfie · \(order.pickup_code ?? order.order_id)")
                if !ok { return }
            }
            guard let dev=deviceToken,let session=sessionToken else{return}
            let ok:Bool=try await api.rpc("fts_printer_mark_printed_v73",body:["p_device_token":dev,"p_session_token":session,"p_order_id":order.order_id])
            if !ok { throw NSError(domain:"FTSPrinter",code:-1,userInfo:[NSLocalizedDescriptionKey:"Auftrag konnte nicht als gedruckt bestätigt werden."]) }
            await refreshSelected()
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
        }
    }

    func pickedUp(_ order:PrintOrder) async {
        guard let dev=deviceToken,let session=sessionToken else{return}
        do {
            let ok:Bool=try await api.rpc("fts_printer_mark_picked_up_v73",body:["p_device_token":dev,"p_session_token":session,"p_order_id":order.order_id])
            if !ok { throw NSError(domain:"FTSPrinter",code:-1,userInfo:[NSLocalizedDescriptionKey:"Auftrag ist noch nicht abholbereit."]) }
            await refreshSelected()
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
        }
    }

    func showReceipt(_ order:PrintOrder) async {
        guard let dev=deviceToken,let session=sessionToken else{return}
        do {
            let r:Receipt?=try await api.rpc("fts_printer_receipt_v73",body:["p_device_token":dev,"p_session_token":session,"p_order_id":order.order_id],as:Receipt?.self)
            currentReceipt=r
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
        }
    }

    func adjustStock(kind:String,quantity:Int,code:String,note:String) async -> Bool {
        guard let dev=deviceToken,let session=sessionToken,let event=selectedEvent else{return false}
        do {
            let day=event.event_date ?? ISO8601DateFormatter().string(from:Date()).prefix(10).description
            let s:StockSnapshot=try await api.rpc("fts_printer_adjust_stock_v73",body:[
                "p_device_token":dev,"p_session_token":session,"p_code":code,"p_event_token":event.event_token,
                "p_event_day":day,"p_kind":kind,"p_quantity":quantity,"p_note":note
            ])
            stock=s;return true
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
            return false
        }
    }

    func printLocalPhoto(_ record:ImportRecord) async {
        guard let event=selectedEvent,let dev=deviceToken,let session=sessionToken else{return}
        busy=true;defer{busy=false}
        do {
            let rendered=try LocalRenderer.renderedImage(sourceURL:URL(fileURLWithPath:record.importedPath),event:event)
            let ok=Printer.printImage(rendered,copies:1,title:"FTS Kamera · \(record.originalName)")
            if !ok{return}
            let day=event.event_date ?? ISO8601DateFormatter().string(from:Date()).prefix(10).description
            let s:StockSnapshot=try await api.rpc("fts_printer_log_camera_print_v73",body:[
                "p_device_token":dev,"p_session_token":session,"p_event_token":event.event_token,
                "p_event_day":day,"p_quantity":1,"p_file_name":record.originalName
            ])
            stock=s
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
        }
    }

    func receiptText(_ r:Receipt)->String {
        let cents=max(0,(r.total_cents ?? 0)-(r.refund_cents ?? 0))
        let amount=String(format:"%.2f",Double(cents)/100).replacingOccurrences(of:".",with:",")
        return """
        FTS.LU · FOTO-PRINT
        
        Beleg: \(r.receipt_number ?? "—")
        Event: \(r.event_title ?? "—")
        Veranstalter: \(r.organizer_name ?? "—")
        Eventdatum: \(r.event_date ?? "—")
        Bezahlt: \(r.paid_at ?? "—")
        
        Anzahl Prints: \(r.quantity_total ?? 0)
        Betrag: \(amount) \(r.currency ?? "EUR")
        Zahlungsart: \(r.payment_method ?? "—")
        Status: \(r.payment_status ?? "—")
        Abholcode: \(r.pickup_code ?? "—")
        
        \(r.is_test == true ? "TEST · KEIN ECHTER UMSATZ" : "")
        """
    }
}

// MARK: - Views

enum FTSTheme {
    static let background = Color(red:0.018, green:0.025, blue:0.028)
    static let sidebar = Color(red:0.025, green:0.045, blue:0.052)
    static let panel = Color(red:0.035, green:0.060, blue:0.066)
    static let panelRaised = Color(red:0.045, green:0.078, blue:0.084)
    static let cyan = Color(red:0.00, green:0.76, blue:0.84)
    static let gold = Color(red:0.86, green:0.68, blue:0.34)
    static let muted = Color.white.opacity(0.64)
    static let border = Color.white.opacity(0.12)
}

struct FTSBrandImage: View {
    let name:String
    var contentMode:ContentMode = .fill
    var body: some View {
        Group {
            if let url=Bundle.main.url(forResource:name,withExtension:"jpg"),
               let image=NSImage(contentsOf:url) {
                Image(nsImage:image).resizable().aspectRatio(contentMode:contentMode)
            } else {
                ZStack {
                    FTSTheme.panelRaised
                    Image(systemName:"printer.fill").font(.system(size:46,weight:.bold)).foregroundStyle(FTSTheme.gold)
                }
            }
        }
    }
}

extension View {
    func ftsCard(_ radius:CGFloat = 14) -> some View {
        self.padding(14)
            .background(FTSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius:radius,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(FTSTheme.border,lineWidth:1))
    }
}

enum FTSSection:Int {
    case dashboard, events, orders, media, pickup, printers, finance, settings, help
}



struct DeviceSetupView: View {
    @EnvironmentObject var state:AppState
    @State private var selected=""
    @State private var code=""
    var admin:DeviceAdminChoice?{state.deviceAdmins.first{$0.user_id==selected}}
    var body:some View {
        ZStack {
            FTSTheme.background.ignoresSafeArea()
            HStack(spacing:34){
                FTSBrandImage(name:"fts_printer_icon",contentMode:.fit)
                    .frame(width:230,height:230)
                    .clipShape(RoundedRectangle(cornerRadius:34,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:34).stroke(FTSTheme.gold.opacity(0.65),lineWidth:1))
                VStack(alignment:.leading,spacing:18){
                    Text("FTS PRINTER").font(.system(size:36,weight:.black,design:.rounded)).foregroundStyle(FTSTheme.gold)
                    Text("Gerät freischalten").font(.title.bold()).foregroundStyle(.white)
                    Text("Diesen Mac einmalig mit einem Printer-Administrator freischalten. Administrator auswählen und persönlichen Printer-Code eingeben.")
                        .foregroundStyle(FTSTheme.muted).frame(maxWidth:520,alignment:.leading)
                    if state.deviceAdmins.isEmpty {
                        Text("Kein aktiver Printer-Administrator gefunden. Im FTS Cockpit zuerst mindestens einen Printer-Administrator anlegen.")
                            .foregroundStyle(.orange).frame(maxWidth:520,alignment:.leading)
                        Button("Administratoren neu laden"){Task{await state.loadDeviceAdmins()}}
                    } else {
                        Picker("Printer-Administrator",selection:$selected){
                            Text("Bitte auswählen …").tag("")
                            ForEach(state.deviceAdmins){a in Text(a.display_name).tag(a.user_id)}
                        }.frame(maxWidth:440)
                        SecureField("Persönlicher Administrator-Code",text:$code)
                            .textFieldStyle(.roundedBorder).frame(maxWidth:380)
                            .onSubmit{if let a=admin{Task{await state.activateDevice(admin:a,code:code)}}}
                        HStack{
                            Button("Mac freischalten"){if let a=admin{Task{await state.activateDevice(admin:a,code:code)}}}
                                .buttonStyle(.borderedProminent).disabled(admin==nil||code.isEmpty||state.busy)
                            Button("Administratoren aktualisieren"){Task{await state.loadDeviceAdmins()}}
                        }
                    }
                    Text("FTS Printer v\(AppState.appVersion)").font(.caption).foregroundStyle(FTSTheme.muted)
                }
                .ftsCard(18)
            }.padding(46)
        }.frame(minWidth:860,minHeight:600)
        .onAppear{if selected.isEmpty{selected=state.deviceAdmins.first?.user_id ?? ""}}
        .onChange(of:state.deviceAdmins){_ in if !state.deviceAdmins.contains(where:{$0.user_id==selected}){selected=state.deviceAdmins.first?.user_id ?? ""}}
    }
}

struct StaffLoginView: View {
    @EnvironmentObject var state:AppState
    @State private var selected:String=""
    @State private var code=""
    var choice:StaffChoice?{state.staffChoices.first{$0.user_id==selected}}
    var body:some View {
        ZStack {
            FTSTheme.background.ignoresSafeArea()
            HStack(spacing:34){
                FTSBrandImage(name:"fts_printer_icon",contentMode:.fit)
                    .frame(width:220,height:220)
                    .clipShape(RoundedRectangle(cornerRadius:32,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:32).stroke(FTSTheme.gold.opacity(0.65),lineWidth:1))
                VStack(alignment:.leading,spacing:18){
                    Text("FTS PRINTER").font(.system(size:34,weight:.black,design:.rounded)).foregroundStyle(FTSTheme.gold)
                    Text("Wer arbeitet am Printer?").font(.title.bold()).foregroundStyle(.white)
                    Text("Mitarbeiter auswählen und persönlichen Code eingeben. Jeder Druck wird dieser Person zugeordnet.")
                        .foregroundStyle(FTSTheme.muted)
                    Picker("Mitarbeiter",selection:$selected){
                        Text("Bitte auswählen …").tag("")
                        ForEach(state.staffChoices){u in Text("\(u.display_name) · \(u.roleLabel)").tag(u.user_id)}
                    }.frame(maxWidth:480)
                    SecureField("Persönlicher Code",text:$code).textFieldStyle(.roundedBorder).frame(maxWidth:340)
                    HStack{
                        Button("Anmelden"){if let u=choice{Task{await state.login(user:u,code:code)}}}
                            .buttonStyle(.borderedProminent).disabled(choice==nil||code.isEmpty||state.busy)
                        Button("Liste aktualisieren"){Task{await state.loadChoices()}}
                    }
                    Button("Gerätefreigabe zurücksetzen",role:.destructive){state.resetDevice()}.buttonStyle(.plain).foregroundStyle(FTSTheme.muted)
                    Text("FTS Printer v\(AppState.appVersion)").font(.caption).foregroundStyle(FTSTheme.muted)
                }
                .ftsCard(18)
            }.padding(46)
        }.frame(minWidth:860,minHeight:600)
        .onAppear{if selected.isEmpty{selected=state.staffChoices.first?.user_id ?? ""}}
    }
}



struct MainView: View {
    @EnvironmentObject var state:AppState
    @State private var section:FTSSection = .dashboard
    @State private var showStock=false
    @State private var updatePrompt=false
    @State private var updateInstalling=false
    @State private var postponedUpdateBuild:Int?=nil

    var printingActive:Bool {
        state.production.printerSlots.contains{["PREPARING","TRANSFER","PRINTING"].contains($0.state)}
    }

    var canUseMedia:Bool {
        guard let e=state.selectedEvent else{return false}
        return e.operation_mode=="print_only" || e.local_camera_photos==true
    }

    var body:some View {
        HStack(spacing:0){
            sidebar
            Rectangle().fill(FTSTheme.gold.opacity(0.22)).frame(width:1)
            VStack(spacing:0){
                header
                if let event=state.selectedEvent {
                    eventBar(event)
                    content(event)
                } else {
                    VStack(spacing:14){
                        Image(systemName:"calendar.badge.exclamationmark").font(.system(size:46)).foregroundStyle(FTSTheme.gold)
                        Text("Kein Printer-Event").font(.title2.bold())
                        Text("Im FTS Cockpit zuerst ein Event mit Print oder lokaler Kamera freigeben.").foregroundStyle(FTSTheme.muted)
                        Button("Events neu laden"){Task{_ = await state.loadEvents()}}.buttonStyle(.borderedProminent)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                HStack{
                    Circle().fill(state.status.lowercased().contains("offline") ? Color.orange : Color.green).frame(width:7,height:7)
                    Text(state.status).font(.caption).foregroundStyle(FTSTheme.muted)
                    Spacer()
                    Text("v\(AppState.appVersion)").font(.caption2).foregroundStyle(FTSTheme.muted)
                }.padding(.horizontal,16).padding(.vertical,7).background(Color.black.opacity(0.26))
            }
        }
        .background(FTSTheme.background.ignoresSafeArea())
        .foregroundStyle(.white)
        .frame(minWidth:1080,minHeight:720)
        .sheet(isPresented:$showStock){StockSheet(isPresented:$showStock).environmentObject(state)}
        .sheet(item:$state.currentReceipt){r in ReceiptSheet(receipt:r).environmentObject(state)}
        .alert("FTS Printer",isPresented:Binding(get:{state.errorMessage != nil},set:{if !$0{state.errorMessage=nil}})){
            Button("OK"){state.errorMessage=nil}
        } message:{Text(state.errorMessage ?? "")}
        .alert("Neue FTS Printer Version verfügbar",isPresented:$updatePrompt){
            Button("Jetzt aktualisieren"){
                guard !printingActive else{return}
                updateInstalling=true
                Task{
                    if let url=await state.production.downloadUpdate(){NSWorkspace.shared.open(url)}
                    updateInstalling=false
                }
            }
            if state.production.updateRelease?.mandatory != true {
                Button("Später",role:.cancel){postponedUpdateBuild=state.production.updateRelease?.build_number}
            }
        } message:{
            if let release=state.production.updateRelease {
                Text("Installiert: \(AppState.appVersion) · Neu: \(release.version)\n\n\(release.notes ?? "")")
            } else { Text("Eine neue FTS Printer Version ist verfügbar.") }
        }
        .task(id:state.selectedEventToken){
            section = .dashboard
            state.production.discoverPrinters()
            if let e=state.selectedEvent {
                state.mediaIngest.load(event:e)
                state.production.loadLocalQueue(folderPath:state.mediaIngest.activation?.folderPath)
            }
            await state.production.checkUpdate(platform:"macos")
            if state.production.updateAvailable,
               state.production.updateRelease?.build_number != postponedUpdateBuild,
               !printingActive { updatePrompt=true }
            var updateCheckTicks = 0
            while !Task.isCancelled {
                await state.refreshSelected()
                await state.production.refresh(state:state)
                updateCheckTicks += 1
                if updateCheckTicks >= 450 {
                    updateCheckTicks = 0
                    await state.production.checkUpdate(platform:"macos")
                }
                if state.production.updateAvailable,
                   state.production.updateRelease?.build_number != postponedUpdateBuild,
                   !printingActive,!updatePrompt,!updateInstalling { updatePrompt=true }
                try? await Task.sleep(for:.seconds(2))
            }
        }
    }

    var sidebar:some View {
        VStack(alignment:.leading,spacing:8){
            VStack(spacing:8){
                FTSBrandImage(name:"fts_printer_icon",contentMode:.fit)
                    .frame(width:112,height:112)
                    .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:22).stroke(FTSTheme.gold.opacity(0.65),lineWidth:1))
                Text("FTS Printer").font(.headline).foregroundStyle(.white)
            }.frame(maxWidth:.infinity).padding(.bottom,14)

            nav("Dashboard","house.fill",.dashboard)
            nav("Events","calendar",.events)
            nav("Druckaufträge","printer.fill",.orders)
            nav("SD-Karte / Import","sdcard.fill",.media,disabled:!canUseMedia)
            Button(action:{showStock=true}) {
                Label("Materialbestand",systemImage:"shippingbox.fill")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,10)
            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.88))
            nav("Kundenabholung","shippingbox",.pickup)
            nav("Printer-Aktivität","waveform.path.ecg",.printers)
            if state.currentUser?.role=="printer_admin" {
                nav("Finanzen","eurosign.circle.fill",.finance)
            } else {
                HStack{Image(systemName:"lock.fill");Text("Finanzen");Spacer()}
                    .font(.callout).foregroundStyle(FTSTheme.muted).padding(.horizontal,12).padding(.vertical,10)
            }
            Divider().overlay(FTSTheme.gold.opacity(0.25)).padding(.vertical,4)
            nav("Einstellungen","gearshape.fill",.settings)
            nav("Hilfe","questionmark.circle.fill",.help)
            Spacer()
        }
        .padding(14)
        .frame(width:220)
        .background(LinearGradient(colors:[FTSTheme.sidebar,Color.black.opacity(0.92)],startPoint:.top,endPoint:.bottom))
    }

    func nav(_ title:String,_ icon:String,_ value:FTSSection,disabled:Bool=false)->some View {
        Button{
            if !disabled { section=value }
        } label:{
            Label(title,systemImage:icon)
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.horizontal,12).padding(.vertical,10)
                .background(section==value ? FTSTheme.cyan.opacity(0.82) : Color.clear)
                .foregroundStyle(section==value ? Color.black : (disabled ? FTSTheme.muted.opacity(0.55) : Color.white.opacity(0.9)))
                .clipShape(RoundedRectangle(cornerRadius:9,style:.continuous))
        }.buttonStyle(.plain).disabled(disabled)
    }

    var header:some View {
        ZStack(alignment:.bottom){
            FTSBrandImage(name:"fts_printer_header",contentMode:.fill).frame(height:164).clipped()
            LinearGradient(colors:[Color.clear,FTSTheme.background.opacity(0.98)],startPoint:.top,endPoint:.bottom).frame(height:92)
            HStack{
                VStack(alignment:.leading,spacing:2){
                    Text("FTS PRINTER").font(.system(size:25,weight:.black,design:.rounded)).foregroundStyle(FTSTheme.gold)
                    Text("Professionelle Event-Druckstation").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                VStack(alignment:.trailing,spacing:2){
                    Text(state.currentUser?.display_name ?? "").font(.headline)
                    Text(state.currentUser?.roleLabel ?? "").font(.caption).foregroundStyle(FTSTheme.muted)
                }
            }.padding(.horizontal,18).padding(.bottom,10)
        }
    }

    func eventBar(_ event:EventRow)->some View {
        HStack(spacing:12){
            VStack(alignment:.leading,spacing:3){
                Text("Event auswählen").font(.caption.bold()).foregroundStyle(FTSTheme.gold)
                Picker("",selection:Binding(get:{state.selectedEventToken},set:{v in Task{await state.selectEvent(v)}})){
                    ForEach(state.events){e in Text(e.event_title).tag(e.event_token)}
                }.labelsHidden().frame(minWidth:300)
                Text([event.location,event.event_date].compactMap{$0}.joined(separator:" · "))
                    .font(.caption2).foregroundStyle(FTSTheme.muted).lineLimit(1)
            }
            Spacer()
            StockPill(stock:state.stock)
            Button{Task{_ = await state.loadEvents()}} label:{Label("Events neu laden",systemImage:"arrow.clockwise")}
                .buttonStyle(.borderedProminent)
            Button{Task{await state.switchStaff()}} label:{Label("Mitarbeiter wechseln",systemImage:"person.2.fill")}
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(FTSTheme.panelRaised)
        .overlay(Rectangle().frame(height:1).foregroundStyle(FTSTheme.gold.opacity(0.22)),alignment:.bottom)
    }

    @ViewBuilder
    func content(_ event:EventRow)->some View {
        switch section {
        case .dashboard:
            FTSDashboardView(openOrders:{section = .orders},openMedia:{section = .media},openPrinters:{section = .printers},openPickup:{section = .pickup},openStock:{showStock=true})
                .environmentObject(state)
        case .events:
            FTSEventOverviewView(event:event).environmentObject(state)
        case .orders:
            ProductionQueueView().environmentObject(state)
        case .media:
            if canUseMedia { ProductionMediaView().environmentObject(state) }
            else { FTSHelpView(title:"SD-Karte / Import",text:"Für dieses Event ist kein lokaler Kamera-/Print-Only-Modus aktiviert.") }
        case .pickup:
            ProductionPickupView().environmentObject(state)
        case .printers:
            ProductionSystemView().environmentObject(state)
        case .finance:
            FTSFinanceView().environmentObject(state)
        case .settings:
            ProductionSystemView().environmentObject(state)
        case .help:
            FTSHelpView(title:"Hilfe",text:"FTS Printer verwaltet Druckaufträge, Materialbestand, SD-/WLAN-Import, Kundenabholung und mehrere Drucker. Kritische Buchungen und Wiederholungen bleiben gegen Doppelklick/Doppelauslösung geschützt.")
        }
    }
}

struct FTSDashboardView:View {
    @EnvironmentObject var state:AppState
    let openOrders:()->Void
    let openMedia:()->Void
    let openPrinters:()->Void
    let openPickup:()->Void
    let openStock:()->Void

    var activeUnits:Int { state.production.workUnits.filter{["READY","CLAIMED","PRINTING","UNCERTAIN"].contains($0.unit_status)}.count }
    var printedOrders:Int { state.orders.filter{($0.print_status ?? "").uppercased()=="PRINTED"}.count }

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12){
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12){
                    Button(action:openStock){
                        VStack(alignment:.leading,spacing:10){
                            HStack{Label("Materialbestand",systemImage:"shippingbox.fill").font(.headline).foregroundStyle(FTSTheme.gold);Spacer();Image(systemName:"chevron.right")}
                            HStack(spacing:18){
                                metric("Papier / Prints",state.stock?.safe_available ?? 0,.green)
                                metric("Selfie",state.stock?.selfie_printed ?? 0,FTSTheme.cyan)
                                metric("Kamera",state.stock?.camera_prints ?? 0,.orange)
                            }
                            Text("RP-108 · Papier/Farbfilm werden je Drucker separat überwacht.").font(.caption).foregroundStyle(FTSTheme.muted)
                        }.ftsCard()
                    }.buttonStyle(.plain)

                    Button(action:openOrders){
                        VStack(alignment:.leading,spacing:10){
                            HStack{Label("Druckaufträge",systemImage:"printer.fill").font(.headline).foregroundStyle(FTSTheme.gold);Spacer();Image(systemName:"chevron.right")}
                            HStack(spacing:18){
                                metric("Aktiv",activeUnits,FTSTheme.cyan)
                                metric("Gedruckt",printedOrders,.green)
                                metric("Aufträge",state.orders.count,.white)
                            }
                            Text("Mehrdrucker-Verteilung, Warteschlange und UNCERTAIN-Schutz bleiben aktiv.").font(.caption).foregroundStyle(FTSTheme.muted)
                        }.ftsCard()
                    }.buttonStyle(.plain)

                    Button(action:openMedia){
                        VStack(alignment:.leading,spacing:10){
                            HStack{Label("SD-Karte / Import",systemImage:"sdcard.fill").font(.headline).foregroundStyle(FTSTheme.gold);Spacer();Image(systemName:"chevron.right")}
                            Text(state.mediaIngest.status).font(.callout).foregroundStyle(.white)
                            Text("SD-Karten A/B/C/D und WLAN-Kamera-Album").font(.caption).foregroundStyle(FTSTheme.muted)
                        }.ftsCard()
                    }.buttonStyle(.plain)

                    Button(action:openPrinters){
                        VStack(alignment:.leading,spacing:10){
                            HStack{Label("Printer-Aktivität",systemImage:"waveform.path.ecg").font(.headline).foregroundStyle(FTSTheme.gold);Spacer();Image(systemName:"chevron.right")}
                            Text("\(state.production.printerNodes.count) Printer verbunden").font(.title3.bold())
                            Text(state.production.printerNodes.prefix(2).map{"\($0.display_name): \($0.state)"}.joined(separator:" · ")).font(.caption).foregroundStyle(FTSTheme.muted).lineLimit(2)
                        }.ftsCard()
                    }.buttonStyle(.plain)
                }

                Button(action:openPickup){
                    HStack{
                        VStack(alignment:.leading){
                            Label("Kundenabholung",systemImage:"shippingbox").font(.headline).foregroundStyle(FTSTheme.gold)
                            Text("\(state.production.pickups.count) Auftrag\(state.production.pickups.count == 1 ? "" : "e") wartet/warten auf Abholung.").font(.caption).foregroundStyle(FTSTheme.muted)
                        }
                        Spacer();Image(systemName:"chevron.right")
                    }.ftsCard()
                }.buttonStyle(.plain)

                VStack(alignment:.leading,spacing:8){
                    Text("Letzte Druckaufträge").font(.headline).foregroundStyle(FTSTheme.gold)
                    if state.orders.isEmpty { Text("Noch keine Druckaufträge.").foregroundStyle(FTSTheme.muted) }
                    ForEach(Array(state.orders.prefix(6))){o in
                        HStack{
                            Text(o.pickup_code ?? "------").font(.body.monospaced().bold())
                            Text("\(o.quantity_total ?? 0) ×").foregroundStyle(FTSTheme.muted)
                            Text(o.event_title ?? state.selectedEvent?.event_title ?? "").lineLimit(1)
                            Spacer()
                            Text(o.print_status ?? "—").font(.caption.bold()).foregroundStyle((o.print_status ?? "").uppercased()=="PRINTED" ? .green : FTSTheme.gold)
                        }
                        Divider().overlay(FTSTheme.border)
                    }
                }.ftsCard()
            }.padding(14)
        }
    }

    func metric(_ label:String,_ value:Int,_ color:Color)->some View {
        VStack(alignment:.leading,spacing:2){
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(FTSTheme.muted)
        }
    }
}

struct FTSEventOverviewView:View {
    @EnvironmentObject var state:AppState
    let event:EventRow
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14){
                Text(event.event_title).font(.title.bold()).foregroundStyle(FTSTheme.gold)
                Text([event.organizer_name,event.location,event.event_date].compactMap{$0}.joined(separator:" · ")).foregroundStyle(FTSTheme.muted)
                HStack{
                    VStack(alignment:.leading){Text("Print-Fenster").font(.caption).foregroundStyle(FTSTheme.muted);Text(event.print_window_active == true ? "Aktiv" : "Nicht aktiv").bold()}
                    Spacer()
                    VStack(alignment:.leading){Text("Betriebsart").font(.caption).foregroundStyle(FTSTheme.muted);Text(event.operation_mode ?? "Standard").bold()}
                    Spacer()
                    VStack(alignment:.leading){Text("Lokale Kamera").font(.caption).foregroundStyle(FTSTheme.muted);Text(event.local_camera_photos == true ? "Ja" : "Nein").bold()}
                }.ftsCard()
                Button("Eventdaten aktualisieren"){Task{await state.refreshSelected()}}.buttonStyle(.borderedProminent)
            }.padding(16)
        }
    }
}

struct FTSFinanceView:View {
    @EnvironmentObject var state:AppState
    var isAdmin:Bool { state.currentUser?.role=="printer_admin" }
    var liveRevenue:Int {
        state.orders.filter{$0.is_test != true && ["COMPLETED","COVERED"].contains(($0.payment_status ?? "").uppercased())}
            .reduce(0){$0 + ($1.total_cents ?? 0)}
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14){
                if isAdmin {
                    Label("Finanzen · Administrator",systemImage:"lock.open.fill").font(.title2.bold()).foregroundStyle(FTSTheme.gold)
                    HStack{
                        VStack(alignment:.leading){Text(String(format:"%.2f €",Double(liveRevenue)/100.0)).font(.largeTitle.bold()).foregroundStyle(.green);Text("Aktuelle bezahlte Aufträge im geladenen Event").font(.caption).foregroundStyle(FTSTheme.muted)}
                        Spacer()
                        VStack(alignment:.trailing){Text("\(state.orders.filter{$0.is_test != true}.count)").font(.title.bold());Text("Nicht-Test-Aufträge").font(.caption).foregroundStyle(FTSTheme.muted)}
                    }.ftsCard()
                    Text("Belege bleiben über die jeweiligen Aufträge und die Kundenabholung abrufbar. Test-/Sandbox-Aufträge werden hier nicht als Umsatz gezählt.")
                        .foregroundStyle(FTSTheme.muted).ftsCard()
                } else {
                    Label("Finanzen nur für Administratoren",systemImage:"lock.fill").font(.title2.bold()).foregroundStyle(FTSTheme.gold)
                    Text("Dieser Bereich ist für Mitarbeiter gesperrt.").foregroundStyle(FTSTheme.muted).ftsCard()
                }
            }.padding(16)
        }
    }
}

struct FTSHelpView:View {
    let title:String
    let text:String
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12){
                Text(title).font(.title.bold()).foregroundStyle(FTSTheme.gold)
                Text(text).foregroundStyle(.white.opacity(0.88))
                Text("Status- und Bedienflächen sind scrollbar; alle wichtigen Aktionen bleiben über die vorhandenen Sicherheitsabfragen und Sperren geschützt.")
                    .font(.caption).foregroundStyle(FTSTheme.muted)
            }.ftsCard().padding(16)
        }
    }
}


struct StockPill:View{
    let stock:StockSnapshot?

    var levelColor:Color {
        guard stock?.managed==true else{return .gray}
        let n=stock?.safe_available ?? 0
        if n==0{return .purple}
        if n<=10{return .red}
        if n<=20{return .orange}
        return .green
    }

    var body:some View{
        HStack(spacing:6){
            Image(systemName:"shippingbox.fill")
            Text(stock?.managed==true ? "\(stock?.safe_available ?? 0) sicher" : "nicht eingerichtet").bold()
        }
        .font(.callout).padding(.horizontal,12).padding(.vertical,7)
        .background(levelColor.opacity(0.16))
        .foregroundStyle(levelColor)
        .clipShape(Capsule())
    }
}

struct OrdersView:View{
    @EnvironmentObject var state:AppState
    var live:[PrintOrder]{state.orders.filter{$0.pickup_status?.uppercased() != "PICKED_UP"}}
    var body:some View{
        ScrollView{
            LazyVStack(spacing:12){
                if live.isEmpty{
                    VStack(spacing:10){
                        Image(systemName:"printer").font(.system(size:36)).foregroundStyle(.secondary)
                        Text("Keine aktuellen Druckaufträge").font(.headline)
                    }.frame(maxWidth:.infinity).padding(50)
                }
                ForEach(live){o in OrderCard(order:o).environmentObject(state)}
            }.padding(8)
        }
    }
}

struct OrderCard:View{
    @EnvironmentObject var state:AppState
    let order:PrintOrder
    var firstURL:URL?{
        guard let p=order.items?.first?.designed_path else{return nil}
        return FTSAPI.shared.imageURL(storagePath:p)
    }
    var body:some View{
        HStack(alignment:.top,spacing:14){
            if let u=firstURL{
                AsyncImage(url:u){phase in
                    if let im=phase.image{im.resizable().scaledToFit()}
                    else{ZStack{Color.black.opacity(0.2);ProgressView()}}
                }.frame(width:150,height:190).background(.black.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:10))
            }
            VStack(alignment:.leading,spacing:8){
                HStack{
                    Text(order.ready ? "DRUCKBEREIT" : (order.print_status ?? "—")).font(.caption.bold()).foregroundStyle(order.ready ? .green:.secondary)
                    if order.is_test==true{Text("TEST / SANDBOX").font(.caption.bold()).foregroundStyle(.orange)}
                }
                Text("Abholcode \(order.pickup_code ?? "------")").font(.title2.bold()).monospacedDigit()
                Text("\(order.quantity_total ?? 0) × 10×15 · Zahlung \(order.payment_status ?? "—")").foregroundStyle(.secondary)
                Text("Auftrag \(order.order_id.prefix(8).uppercased())").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                HStack{
                    if order.ready{Button("Jetzt drucken"){Task{await state.printOrder(order)}}.buttonStyle(.borderedProminent)}
                    if order.print_status?.uppercased()=="PRINTED" && order.pickup_status?.uppercased()=="READY_FOR_PICKUP"{
                        Button("Abgeholt bestätigen"){Task{await state.pickedUp(order)}}.buttonStyle(.borderedProminent)
                    }
                    if order.receipt_number != nil{Button("Kundenbeleg"){Task{await state.showReceipt(order)}}}
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(14).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:14))
    }
}

struct CameraImportView:View{
    @EnvironmentObject var state:AppState
    let event:EventRow
    var body:some View{
        CameraImportContent(event:event)
            .environmentObject(state)
            .environmentObject(state.localImport)
    }
}

struct CameraImportContent:View{
    @EnvironmentObject var state:AppState
    @EnvironmentObject var manager:LocalImportManager
    let event:EventRow
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            HStack{
                VStack(alignment:.leading){
                    Text("Lokale Kamera-Fotos").font(.title3.bold())
                    Text(manager.status).font(.caption).foregroundStyle(.secondary)
                    if !manager.lastSource.isEmpty{Text("Quelle: \(manager.lastSource)").font(.caption2).foregroundStyle(.secondary)}
                }
                Spacer()
                if manager.activation==nil{
                    Button("Event lokal freigeben / Ordner erstellen"){
                        do{try manager.activate(event:event)}catch{state.errorMessage=error.localizedDescription}
                    }.buttonStyle(.borderedProminent)
                }else{
                    Button("Ordner öffnen"){manager.revealFolder()}
                    Button(manager.scanning ? "Prüfe …":"Karten jetzt prüfen"){Task{await manager.scan(event:event)}}.disabled(manager.scanning)
                }
            }
            Divider()
            ScrollView{
                LazyVGrid(columns:[GridItem(.adaptive(minimum:190),spacing:10)],spacing:10){
                    ForEach(manager.imported){r in
                        VStack(alignment:.leading,spacing:7){
                            if let im=NSImage(contentsOfFile:r.importedPath){
                                Image(nsImage:im).resizable().scaledToFit().frame(height:160).frame(maxWidth:.infinity).background(.black.opacity(0.08))
                            }
                            Text(r.originalName).font(.caption.bold()).lineLimit(1)
                            Text(r.cameraID ?? r.cardID).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            Button("Design + drucken"){Task{await state.printLocalPhoto(r)}}.buttonStyle(.borderedProminent).frame(maxWidth:.infinity)
                        }.padding(9).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12))
                    }
                }.padding(6)
            }
        }.padding(8)
        .task(id:event.event_token){
            manager.load(event:event)
            while !Task.isCancelled{
                if manager.activation != nil{await manager.scan(event:event)}
                try? await Task.sleep(for:.seconds(4))
            }
        }
    }
}

struct StockSheet:View{
    @EnvironmentObject var state:AppState
    @Binding var isPresented:Bool
    @State private var qty="108"
    @State private var kind="ADD_STOCK"
    @State private var note=""
    @State private var code=""
    @State private var booking=false
    var body:some View{
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Materialbestand").font(.title2.bold());Spacer();Button("Schließen"){isPresented=false}}
            if let s=state.stock{
                HStack(spacing:18){
                    metric("Sicher verfügbar",s.safe_available ?? 0)
                    metric("Selfie gedruckt",s.selfie_printed ?? 0)
                    metric("Kamera",s.camera_prints ?? 0)
                    metric("Test / Fehler / Nachdruck",(s.test_prints ?? 0)+(s.misprints ?? 0)+(s.reprints ?? 0))
                }
                if s.open_stock_unknown==true{Text("Geöffneter Bestand ist unbekannt und wird nicht für neue Zahlungen mitgerechnet.").foregroundStyle(.orange)}
            }
            Divider()
            Text("Bestand ändern").font(.headline)
            Text("Für jede Bestandsänderung muss der aktuell angemeldete Mitarbeiter seinen persönlichen Code nochmals bestätigen.").font(.caption).foregroundStyle(.secondary)
            Picker("Buchung",selection:$kind){
                Text("Nachschub hinzufügen").tag("ADD_STOCK")
                Text("Kamera-/Standprint").tag("CAMERA_PRINT")
                Text("Testdruck").tag("TEST_PRINT")
                Text("Fehldruck").tag("MISPRINT")
                Text("Nachdruck").tag("REPRINT")
                if state.currentUser?.role=="printer_admin"{Text("Korrektur + / −").tag("CORRECTION")}
            }
            HStack{
                TextField("Menge",text:$qty).frame(width:120)
                if kind=="ADD_STOCK"{Button("+108"){qty="108"}}
                TextField("Notiz optional",text:$note)
            }
            SecureField("Persönlichen Code erneut eingeben",text:$code)
            Button(booking ? "Buchung läuft …" : "Buchung bestätigen"){
                guard !booking else{return}
                guard let q=Int(qty),q != 0 else{state.errorMessage="Gültige Menge eingeben.";return}
                booking=true
                Task{
                    defer{booking=false}
                    if await state.adjustStock(kind:kind,quantity:q,code:code,note:note){
                        code=""
                        note=""
                        isPresented=false
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.isEmpty || booking)
        }.padding(24).frame(width:680)
    }
    func metric(_ label:String,_ value:Int)->some View{
        VStack(alignment:.leading){Text("\(value)").font(.title.bold());Text(label).font(.caption).foregroundStyle(.secondary)}
    }
}

struct ReceiptSheet:View{
    @EnvironmentObject var state:AppState
    let receipt:Receipt
    @Environment(\.dismiss) var dismiss
    var body:some View{
        VStack(alignment:.leading,spacing:14){
            HStack{Text("Kundenbeleg").font(.title2.bold());Spacer();Button("Schließen"){dismiss()}}
            ScrollView{Text(state.receiptText(receipt)).font(.system(.body,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}
            HStack{Spacer();Button("Beleg drucken"){_ = Printer.printReceipt(state.receiptText(receipt))}.buttonStyle(.borderedProminent)}
        }.padding(24).frame(width:620,height:620)
    }
}

// MARK: - App

final class FTSAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url=Bundle.main.url(forResource:"fts_printer_icon",withExtension:"jpg"),
           let image=NSImage(contentsOf:url) {
            NSApp.applicationIconImage=image
        }
    }
}


@main
struct FTSPrinterApp: App {
    @NSApplicationDelegateAdaptor(FTSAppDelegate.self) private var appDelegate
    @StateObject private var state=AppState()
    var body:some Scene{
        WindowGroup{
            Group{
                switch state.phase{
                case .boot: ProgressView("FTS Printer startet …").frame(minWidth:720,minHeight:520)
                case .deviceSetup: DeviceSetupView()
                case .staffLogin: StaffLoginView()
                case .main: MainView()
                }
            }
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .tint(FTSTheme.cyan)
            .task{if state.phase == .boot{await state.bootstrap()}}
        }
        .windowStyle(.titleBar)
        .commands{
            CommandGroup(replacing:.appInfo){
                Button("Über FTS Printer"){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"FTS Printer",.applicationVersion:AppState.appVersion])}
            }
        }
    }
}
