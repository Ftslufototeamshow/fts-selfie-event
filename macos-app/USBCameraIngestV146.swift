import Foundation
import ImageCaptureCore
import CryptoKit

struct V146USBCameraSnapshot: Hashable {
    let connected: Bool
    let name: String
    let detail: String
    let error: String?
}

struct V146USBCameraSyncResult {
    let downloadedCount: Int
    let snapshot: V146USBCameraSnapshot
}

private struct V146USBCameraLedger: Codable {
    var remoteKeys: Set<String> = []
}

final class V146USBCameraSessionDelegate: NSObject, ICDeviceDelegate {
    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {}
    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {}
    func didRemove(_ device: ICDevice) {}
}

final class V146USBCameraBridge: NSObject, ICDeviceBrowserDelegate {
    static let shared=V146USBCameraBridge()

    private let browser=ICDeviceBrowser()
    private var cameras:[String:ICCameraDevice]=[:]
    private var delegates:[String:V146USBCameraSessionDelegate]=[:]
    private var lastErrors:[String:String]=[:]
    private var started=false

    override private init() {
        super.init()
        browser.delegate=self
        browser.browsedDeviceTypeMask = .camera
        if browser.contentsAuthorizationStatus == .notDetermined {
            browser.requestContentsAuthorization { _ in }
        }
        browser.start()
        started=true
    }

    deinit {
        if started { browser.stop() }
        for camera in cameras.values where camera.hasOpenSession {
            camera.requestCloseSession()
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera=device as? ICCameraDevice else{return}
        guard isDirectUSBCamera(camera) else{return}
        let id=deviceID(camera)
        cameras[id]=camera
        let delegate=V146USBCameraSessionDelegate()
        delegates[id]=delegate
        camera.delegate=delegate
        openIfNeeded(camera,id:id)
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard let camera=device as? ICCameraDevice else{return}
        let id=deviceID(camera)
        cameras.removeValue(forKey:id)
        delegates.removeValue(forKey:id)
        lastErrors.removeValue(forKey:id)
    }

    func snapshot() -> V146USBCameraSnapshot {
        let live=cameras.values.filter{isDirectUSBCamera($0)}
        guard !live.isEmpty else {
            let authorization=browser.contentsAuthorizationStatus
            if authorization == .denied || authorization == .restricted {
                return V146USBCameraSnapshot(
                    connected:false,
                    name:"",
                    detail:"Kamerazugriff in macOS nicht erlaubt.",
                    error:"FTS benötigt Zugriff auf angeschlossene Kameras."
                )
            }
            return V146USBCameraSnapshot(connected:false,name:"",detail:"",error:nil)
        }

        let names=live.map{cameraName($0)}.sorted()
        let openCount=live.filter{$0.hasOpenSession}.count
        let error=live.compactMap{lastErrors[deviceID($0)]}.first
        return V146USBCameraSnapshot(
            connected:true,
            name:names.joined(separator:" · "),
            detail:"USB/PTP · \(openCount)/\(live.count) bereit",
            error:error
        )
    }

    func sync(to root:URL,since:Date) async -> V146USBCameraSyncResult {
        let fm=FileManager.default
        let staging=root.appendingPathComponent("USB Kamera Eingang",isDirectory:true)
        do {
            try fm.createDirectory(at:staging,withIntermediateDirectories:true)
        } catch {
            return V146USBCameraSyncResult(
                downloadedCount:0,
                snapshot:V146USBCameraSnapshot(
                    connected:!cameras.isEmpty,
                    name:cameras.values.map{cameraName($0)}.joined(separator:" · "),
                    detail:"USB/PTP",
                    error:error.localizedDescription
                )
            )
        }

        var ledger=loadLedger(staging)
        var downloaded=0
        let cutoff=since.addingTimeInterval(-300)

        for camera in cameras.values.filter({isDirectUSBCamera($0)}) {
            let id=deviceID(camera)
            do {
                try await ensureOpen(camera,id:id)

                // ImageCapture may still be cataloguing the card immediately after
                // the cable is connected. A later one-second scan will continue.
                let media=(camera.mediaFiles ?? []).compactMap{$0 as? ICCameraFile}
                let preferred=preferredCameraFiles(media)
                let cameraFolder=staging.appendingPathComponent(safeComponent(id),isDirectory:true)
                try fm.createDirectory(at:cameraFolder,withIntermediateDirectories:true)

                for file in preferred {
                    let date=file.exifCreationDate
                        ?? file.fileCreationDate
                        ?? file.creationDate
                        ?? file.fileModificationDate
                        ?? file.modificationDate
                        ?? .distantPast
                    guard file.wasAddedAfterContentCatalogCompleted || date >= cutoff else{continue}

                    let original=file.originalFilename ?? file.name ?? "camera-photo.jpg"
                    guard supported(original) else{continue}
                    let key=remoteKey(camera:camera,file:file,original:original,date:date)
                    if ledger.remoteKeys.contains(key){continue}

                    let prefix=String(SHA256.hash(data:Data(key.utf8)).map{String(format:"%02x",$0)}.joined().prefix(16))
                    let filename="ftsusb-\(prefix)__\(safeFilename(original))"
                    let destination=cameraFolder.appendingPathComponent(filename)
                    if fm.fileExists(atPath:destination.path) {
                        ledger.remoteKeys.insert(key)
                        continue
                    }

                    try await download(file,to:cameraFolder,filename:filename)
                    ledger.remoteKeys.insert(key)
                    downloaded+=1
                }
                lastErrors.removeValue(forKey:id)
            } catch {
                lastErrors[id]=error.localizedDescription
            }
        }

        saveLedger(ledger,staging)
        return V146USBCameraSyncResult(downloadedCount:downloaded,snapshot:snapshot())
    }

    private func openIfNeeded(_ camera:ICCameraDevice,id:String) {
        guard !camera.hasOpenSession else{return}
        camera.requestOpenSession(options:nil) { [weak self,weak camera] error in
            guard let self else{return}
            if let error {
                self.lastErrors[id]=error.localizedDescription
            } else if camera?.hasOpenSession == true {
                self.lastErrors.removeValue(forKey:id)
            }
        }
    }

    private func ensureOpen(_ camera:ICCameraDevice,id:String) async throws {
        if camera.hasOpenSession{return}
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            camera.requestOpenSession(options:nil) { [weak self] error in
                if let error {
                    self?.lastErrors[id]=error.localizedDescription
                    continuation.resume(throwing:error)
                } else {
                    self?.lastErrors.removeValue(forKey:id)
                    continuation.resume()
                }
            }
        }
    }

    private func download(_ file:ICCameraFile,to directory:URL,filename:String) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            let options:[ICDownloadOption:Any]=[
                .downloadsDirectoryURL:directory as NSURL,
                .saveAsFilename:filename as NSString,
                .overwrite:false,
                .deleteAfterSuccessfulDownload:false,
                .sidecarFiles:false
            ]
            _=file.requestDownload(options:options) { _,error in
                if let error { continuation.resume(throwing:error) }
                else { continuation.resume() }
            }
        }
    }

    private func preferredCameraFiles(_ files:[ICCameraFile])->[ICCameraFile] {
        var best:[String:ICCameraFile]=[:]
        for file in files {
            let name=(file.originalFilename ?? file.name ?? "").lowercased()
            guard supported(name) else{continue}
            let stem=(name as NSString).deletingPathExtension
            if let old=best[stem] {
                let oldName=(old.originalFilename ?? old.name ?? "").lowercased()
                if preferenceRank(name)<preferenceRank(oldName){best[stem]=file}
            } else {
                best[stem]=file
            }
        }
        return best.values.sorted {
            let a=$0.exifCreationDate ?? $0.fileCreationDate ?? $0.creationDate ?? .distantPast
            let b=$1.exifCreationDate ?? $1.fileCreationDate ?? $1.creationDate ?? .distantPast
            return a<b
        }
    }

    private func remoteKey(camera:ICCameraDevice,file:ICCameraFile,original:String,date:Date)->String {
        [
            deviceID(camera),
            original,
            String(file.fileSize),
            String(Int(date.timeIntervalSince1970)),
            String(file.ptpObjectHandle)
        ].joined(separator:"|")
    }

    private func isDirectUSBCamera(_ camera:ICCameraDevice)->Bool {
        if camera.usbVendorID != 0 { return true }
        let transport=(camera.transportType ?? "").lowercased()
        return transport.contains("usb")
    }

    private func deviceID(_ camera:ICCameraDevice)->String {
        camera.persistentIDString
            ?? camera.uuidString
            ?? "\(camera.usbVendorID)-\(camera.usbProductID)-\(camera.name ?? "camera")"
    }

    private func cameraName(_ camera:ICCameraDevice)->String {
        let name=camera.name?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        if !name.isEmpty{return name}
        let kind=camera.productKind?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return kind.isEmpty ? "USB-Kamera" : kind
    }

    private func supported(_ name:String)->Bool {
        ["jpg","jpeg","heic","hif","png","cr3","cr2","dng","nef","arw","raf"]
            .contains((name as NSString).pathExtension.lowercased())
    }

    private func preferenceRank(_ name:String)->Int {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg","jpeg": return 0
        case "heic","hif": return 1
        case "png": return 2
        default: return 10
        }
    }

    private func safeComponent(_ value:String)->String {
        value.replacingOccurrences(of:"/",with:"-")
            .replacingOccurrences(of:":",with:"-")
            .replacingOccurrences(of:"\\",with:"-")
    }

    private func safeFilename(_ value:String)->String {
        let illegal=CharacterSet(charactersIn:"/:\\?%*|\"<>")
        let cleaned=value.components(separatedBy:illegal).joined(separator:"-")
        return cleaned.isEmpty ? "camera-photo.jpg" : cleaned
    }

    private func ledgerURL(_ staging:URL)->URL {
        staging.appendingPathComponent(".fts-usb-ledger-v146.json")
    }

    private func loadLedger(_ staging:URL)->V146USBCameraLedger {
        guard let data=try? Data(contentsOf:ledgerURL(staging)),
              let ledger=try? JSONDecoder().decode(V146USBCameraLedger.self,from:data) else {
            return V146USBCameraLedger()
        }
        return ledger
    }

    private func saveLedger(_ ledger:V146USBCameraLedger,_ staging:URL) {
        guard let data=try? JSONEncoder().encode(ledger) else{return}
        try? data.write(to:ledgerURL(staging),options:.atomic)
    }
}
