import SwiftUI
import AppKit
import Foundation

// MARK: - Shared design typography
// One source of truth for both the production renderer and the manual editor.

enum FTSDesignTypography {
    struct Option: Identifiable, Hashable {
        let id:String
        let label:String
    }

    static let options:[Option] = [
        .init(id:"clean",label:"Clean"),
        .init(id:"bold",label:"Bold"),
        .init(id:"elegant",label:"Elegant"),
        .init(id:"retro",label:"Retro"),
        .init(id:"pop",label:"Pop"),
        .init(id:"handwritten",label:"Handschrift")
    ]

    static func nsFont(id:String,size:CGFloat,weight:Int)->NSFont {
        let systemWeight:NSFont.Weight =
            weight>=900 ? .black :
            weight>=800 ? .heavy :
            weight>=700 ? .bold :
            weight>=600 ? .semibold : .regular

        switch id {
        case "bold","rock":
            return NSFont(name:"Impact",size:size) ?? NSFont.systemFont(ofSize:size,weight:.black)
        case "elegant":
            return NSFont(name:"Georgia",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "retro":
            return NSFont(name:"Courier New",size:size) ?? NSFont.monospacedSystemFont(ofSize:size,weight:systemWeight)
        case "pop":
            return NSFont(name:"Trebuchet MS Bold",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "handwritten":
            return NSFont(name:"Brush Script MT",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        default:
            return NSFont.systemFont(ofSize:size,weight:systemWeight)
        }
    }

    static func swiftUIFont(id:String,size:CGFloat,weight:Int)->Font {
        let swiftWeight:Font.Weight =
            weight>=900 ? .black :
            weight>=800 ? .heavy :
            weight>=700 ? .bold :
            weight>=600 ? .semibold : .regular

        switch id {
        case "bold","rock": return .custom("Impact",size:size).weight(.black)
        case "elegant": return .custom("Georgia",size:size).weight(swiftWeight)
        case "retro": return .custom("Courier New",size:size).weight(swiftWeight)
        case "pop": return .custom("Trebuchet MS Bold",size:size).weight(swiftWeight)
        case "handwritten": return .custom("Brush Script MT",size:size).weight(swiftWeight)
        default: return .system(size:size,weight:swiftWeight)
        }
    }
}

// MARK: - Manual event identity

extension EventRow {
    var isManualPrinterEvent:Bool {
        studio_config?["printer_manual"]?.bool == true
    }

    var printerSourceLabel:String {
        isManualPrinterEvent ? "MANUELL" : "MYSELFIE"
    }
}

private enum FTSManualEventDate {
    static let formatter:DateFormatter = {
        let f=DateFormatter()
        f.locale=Locale(identifier:"en_US_POSIX")
        f.calendar=Calendar(identifier:.gregorian)
        f.dateFormat="yyyy-MM-dd"
        return f
    }()

    static func string(_ date:Date)->String { formatter.string(from:date) }
    static func date(_ raw:String?)->Date {
        guard let raw,let value=formatter.date(from:raw) else{return Date()}
        return value
    }
}

struct FTSManualEventRPCResult:Codable {
    let ok:Bool?
    let event_token:String?
    let event_id:String?
    let short_code:String?
    let event_title:String?
}

// MARK: - One editable model -> same studio_config consumed by ProductionRendererV76

@MainActor
final class FTSManualPrinterDesignDraft:ObservableObject {
    @Published var eventTitle:String
    @Published var eventDate:Date
    @Published var location:String

    @Published var designEnabled:Bool
    @Published var bannerType:String
    @Published var bannerColorHex:String
    @Published var bannerOpacity:Double
    @Published var align:String

    @Published var titleEnabled:Bool
    @Published var titleText:String
    @Published var titleFont:String
    @Published var titleSize:Double
    @Published var titleWeight:Int
    @Published var titleColorHex:String

    @Published var subtitleEnabled:Bool
    @Published var subtitleText:String
    @Published var subtitleFont:String
    @Published var subtitleSize:Double
    @Published var subtitleWeight:Int
    @Published var subtitleColorHex:String

    @Published var lineEnabled:Bool
    @Published var lineText:String
    @Published var lineFont:String
    @Published var lineSize:Double
    @Published var lineWeight:Int
    @Published var lineColorHex:String
    @Published var includeDate:Bool

    @Published var showFTSBranding:Bool
    @Published var logoPath:String?
    @Published var logoPosition:String
    @Published var logoSize:String

    init(event:EventRow) {
        let config=event.studio_config?.object ?? [:]
        let overlay=config["overlay"]?.object ?? [:]
        let banner=overlay["banner"]?.object ?? [:]
        let title=overlay["title"]?.object ?? [:]
        let subtitle=overlay["subtitle"]?.object ?? [:]
        let line=overlay["line"]?.object ?? [:]
        let firstLogo=event.logo_items?.array?.compactMap{$0.object}.first

        eventTitle=event.event_title
        eventDate=FTSManualEventDate.date(event.event_date)
        location=event.location ?? ""

        designEnabled=overlay["enabled"]?.bool != false
        bannerType=banner["type"]?.string == "gradient" ? "gradient":"solid"
        bannerColorHex=banner["color"]?.string ?? "#071315"
        bannerOpacity=max(0.10,min(1,banner["opacity"]?.double ?? 0.72))
        align=title["align"]?.string ?? "left"

        titleEnabled=title["enabled"]?.bool != false
        titleText=title["text"]?.string ?? event.event_title
        titleFont=title["font"]?.string ?? "clean"
        titleSize=max(2.5,min(7,title["size_pct"]?.double ?? 5.0))
        titleWeight=Int(title["weight"]?.double ?? 900)
        titleColorHex=title["color"]?.string ?? "#FFFFFF"

        subtitleEnabled=subtitle["enabled"]?.bool == true
        subtitleText=subtitle["text"]?.string ?? event.subtitle ?? ""
        subtitleFont=subtitle["font"]?.string ?? "clean"
        subtitleSize=max(1.8,min(5,subtitle["size_pct"]?.double ?? 3.0))
        subtitleWeight=Int(subtitle["weight"]?.double ?? 700)
        subtitleColorHex=subtitle["color"]?.string ?? "#D9B56D"

        lineEnabled=line["enabled"]?.bool == true
        lineText=line["text"]?.string ?? event.overlay_text ?? ""
        lineFont=line["font"]?.string ?? "clean"
        lineSize=max(1.4,min(4,line["size_pct"]?.double ?? 2.1))
        lineWeight=Int(line["weight"]?.double ?? 600)
        lineColorHex=line["color"]?.string ?? "#E8EFED"
        includeDate=line["include_date"]?.bool != false

        showFTSBranding=overlay["branding"]?.bool == true && event.photo_branding != "none"
        logoPath=firstLogo?["path"]?.string
        logoPosition=firstLogo?["position"]?.string ?? "top-right"
        logoSize=firstLogo?["size"]?.string ?? "medium"
    }

    func loadFTSStandard() {
        designEnabled=true
        bannerType="solid"
        bannerColorHex="#071315"
        bannerOpacity=0.72
        align="left"

        titleEnabled=true
        titleText=eventTitle
        titleFont="clean"
        titleSize=5.0
        titleWeight=900
        titleColorHex="#FFFFFF"

        subtitleEnabled=false
        subtitleText=""
        subtitleFont="clean"
        subtitleSize=3.0
        subtitleWeight=700
        subtitleColorHex="#D9B56D"

        lineEnabled=false
        lineText=location
        lineFont="clean"
        lineSize=2.1
        lineWeight=600
        lineColorHex="#E8EFED"
        includeDate=true
        showFTSBranding=false
    }

    func studioConfigPayload()->[String:Any] {
        [
            "version":76,
            "printer_manual":true,
            "manual_design_version":144,
            "filters":["default":"natural"],
            "overlay":[
                "enabled":designEnabled,
                "branding":showFTSBranding,
                "padding_pct":4.5,
                "banner":[
                    "enabled":designEnabled,
                    "type":bannerType,
                    "color":bannerColorHex,
                    "opacity":bannerOpacity,
                    "height_pct":22,
                    "image_path":"",
                    "image_opacity":1
                ],
                "title":[
                    "enabled":titleEnabled,
                    "source":"title",
                    "text":titleText,
                    "font":titleFont,
                    "size_pct":titleSize,
                    "weight":titleWeight,
                    "color":titleColorHex,
                    "align":align,
                    "shadow":true
                ],
                "subtitle":[
                    "enabled":subtitleEnabled,
                    "source":"subtitle",
                    "text":subtitleText,
                    "font":subtitleFont,
                    "size_pct":subtitleSize,
                    "weight":subtitleWeight,
                    "color":subtitleColorHex,
                    "align":align,
                    "shadow":true
                ],
                "line":[
                    "enabled":lineEnabled,
                    "source":"overlay",
                    "text":lineText,
                    "font":lineFont,
                    "size_pct":lineSize,
                    "weight":lineWeight,
                    "color":lineColorHex,
                    "align":align,
                    "shadow":true,
                    "include_date":includeDate
                ]
            ],
            "adaptive":[
                "enabled":true,
                "auto_crop":true,
                "auto_orientation":true,
                "face_safe_area":true,
                "face_gap_pct":2.5,
                "face_padding_ratio":0.34,
                "min_text_scale":0.68,
                "print":["ratio":"10x15","bleed_pct":1.5],
                "landscape":["banner_max_pct":22,"banner_min_pct":14],
                "portrait":["banner_max_pct":18,"banner_min_pct":12]
            ]
        ]
    }

    func logoItemsPayload()->[[String:Any]] {
        guard let logoPath,!logoPath.isEmpty else{return []}
        return [[
            "path":logoPath,
            "position":logoPosition,
            "size":logoSize,
            "show_photo":true
        ]]
    }
}

enum FTSManualPrinterAssets {
    static func root(eventToken:String)throws->URL {
        let fm=FileManager.default
        let pictures=fm.urls(for:.picturesDirectory,in:.userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let folder=pictures
            .appendingPathComponent("FTS Print Events",isDirectory:true)
            .appendingPathComponent("Manual Assets",isDirectory:true)
            .appendingPathComponent(eventToken,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        return folder
    }

    static func copyLogo(_ source:URL,eventToken:String)throws->String {
        let folder=try root(eventToken:eventToken)
        let ext=source.pathExtension.isEmpty ? "png":source.pathExtension.lowercased()
        let dest=folder.appendingPathComponent("logo-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at:source,to:dest)
        return dest.path
    }
}

// MARK: - App actions

extension AppState {
    func createManualPrinterEvent(title:String,date:Date,location:String) async -> String? {
        guard currentUser?.role=="printer_admin" else {
            errorMessage="Nur Printer-Administratoren können manuelle Events anlegen."
            return nil
        }
        guard let dev=deviceToken,let session=sessionToken else{return nil}
        let clean=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else {
            errorMessage="Bitte einen Eventnamen eingeben."
            return nil
        }

        busy=true
        defer{busy=false}
        do {
            let result:FTSManualEventRPCResult=try await FTSAPI.shared.rpc(
                "fts_printer_manual_event_create_v144",
                body:[
                    "p_device_token":dev,
                    "p_session_token":session,
                    "p_title":clean,
                    "p_event_date":FTSManualEventDate.string(date),
                    "p_location":location.trimmingCharacters(in:.whitespacesAndNewlines)
                ]
            )
            guard result.ok==true,let token=result.event_token else {
                throw NSError(domain:"FTSPrinter",code:310,userInfo:[NSLocalizedDescriptionKey:"Manuelles Event konnte nicht angelegt werden."])
            }
            _=await loadEvents()
            await selectEvent(token)
            status="Manuelles Printer-Event angelegt."
            return token
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
            return nil
        }
    }

    func updateManualPrinterEvent(event:EventRow,draft:FTSManualPrinterDesignDraft) async -> Bool {
        guard event.isManualPrinterEvent else {
            errorMessage="MySelfie-Events werden im Printer nicht überschrieben."
            return false
        }
        guard currentUser?.role=="printer_admin",
              let dev=deviceToken,let session=sessionToken else{return false}

        busy=true
        defer{busy=false}
        do {
            let result:FTSManualEventRPCResult=try await FTSAPI.shared.rpc(
                "fts_printer_manual_event_update_v144",
                body:[
                    "p_device_token":dev,
                    "p_session_token":session,
                    "p_event_token":event.event_token,
                    "p_title":draft.eventTitle.trimmingCharacters(in:.whitespacesAndNewlines),
                    "p_event_date":FTSManualEventDate.string(draft.eventDate),
                    "p_location":draft.location.trimmingCharacters(in:.whitespacesAndNewlines),
                    "p_studio_config":draft.studioConfigPayload(),
                    "p_logo_items":draft.logoItemsPayload(),
                    "p_photo_branding":draft.showFTSBranding ? "bottom":"none"
                ]
            )
            guard result.ok==true else {
                throw NSError(domain:"FTSPrinter",code:311,userInfo:[NSLocalizedDescriptionKey:"Manuelles Event konnte nicht gespeichert werden."])
            }
            _=await loadEvents()
            if let current=selectedEvent,mediaIngest.activation != nil {
                await mediaIngest.refreshDesign(event:current)
            }
            status="Manuelles Event und Fotodesign gespeichert."
            return true
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
            return false
        }
    }

    func duplicateManualPrinterEvent(_ event:EventRow) async -> String? {
        guard event.isManualPrinterEvent,currentUser?.role=="printer_admin",
              let dev=deviceToken,let session=sessionToken else{return nil}
        busy=true
        defer{busy=false}
        do {
            let result:FTSManualEventRPCResult=try await FTSAPI.shared.rpc(
                "fts_printer_manual_event_duplicate_v144",
                body:[
                    "p_device_token":dev,
                    "p_session_token":session,
                    "p_event_token":event.event_token
                ]
            )
            guard result.ok==true,let token=result.event_token else {
                throw NSError(domain:"FTSPrinter",code:312,userInfo:[NSLocalizedDescriptionKey:"Event konnte nicht dupliziert werden."])
            }
            _=await loadEvents()
            await selectEvent(token)
            status="Manuelles Event dupliziert."
            return token
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
            return nil
        }
    }

    func archiveManualPrinterEvent(_ event:EventRow) async -> Bool {
        guard event.isManualPrinterEvent,currentUser?.role=="printer_admin",
              let dev=deviceToken,let session=sessionToken else{return false}
        busy=true
        defer{busy=false}
        do {
            let result:FTSManualEventRPCResult=try await FTSAPI.shared.rpc(
                "fts_printer_manual_event_archive_v144",
                body:[
                    "p_device_token":dev,
                    "p_session_token":session,
                    "p_event_token":event.event_token
                ]
            )
            guard result.ok==true else {
                throw NSError(domain:"FTSPrinter",code:313,userInfo:[NSLocalizedDescriptionKey:"Event konnte nicht archiviert werden."])
            }
            _=await loadEvents()
            status="Manuelles Event archiviert."
            return true
        } catch {
            if !(await recoverAuthentication(from:error)) { errorMessage=error.localizedDescription }
            return false
        }
    }
}

// MARK: - Create sheet

struct FTSManualPrinterEventCreateSheet:View {
    @ObservedObject var state:AppState
    var onCreated:(String)->Void = {_ in}

    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var date=Date()
    @State private var location=""
    @State private var saving=false

    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:3) {
                    Text("Manuelles Printer-Event").font(.title2.bold()).foregroundStyle(FTSTheme.gold)
                    Text("Ohne MySelfie · nutzt trotzdem denselben FTS-Druckweg.")
                        .font(.caption).foregroundStyle(FTSTheme.muted)
                }
                Spacer()
                Button("Schließen"){dismiss()}
            }

            GroupBox("Grunddaten") {
                VStack(alignment:.leading,spacing:10) {
                    TextField("Eventname, z. B. Geburtstag Lisa",text:$title)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("Datum",selection:$date,displayedComponents:.date)
                    TextField("Ort (optional)",text:$location)
                        .textFieldStyle(.roundedBorder)
                }.padding(.vertical,4)
            }

            Label(
                "Das Event wird als echtes Printer-only-Event angelegt. SD/WLAN, Canon, Material, Archiv, Green Screen und Druckwarteschlange benutzen danach den vorhandenen Produktionsweg.",
                systemImage:"checkmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(FTSTheme.muted)

            HStack {
                Spacer()
                Button("Abbrechen"){dismiss()}
                Button(saving ? "Wird angelegt …":"Event erstellen") {
                    saving=true
                    Task {
                        if let token=await state.createManualPrinterEvent(title:title,date:date,location:location) {
                            onCreated(token)
                            dismiss()
                        }
                        saving=false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width:620)
    }
}

// MARK: - Manual design editor

struct FTSManualPrinterEventEditor:View {
    @ObservedObject var state:AppState
    let event:EventRow
    @StateObject private var draft:FTSManualPrinterDesignDraft

    @Environment(\.dismiss) private var dismiss
    @State private var saving=false
    @State private var message=""

    init(state:AppState,event:EventRow) {
        self.state=state
        self.event=event
        _draft=StateObject(wrappedValue:FTSManualPrinterDesignDraft(event:event))
    }

    private var previewPhoto:NSImage? {
        guard let item=state.mediaIngest.items
            .filter({FileManager.default.fileExists(atPath:$0.importedPath)})
            .sorted(by:{$0.importedAt>$1.importedAt})
            .first else{return nil}
        return NSImage(contentsOfFile:item.importedPath)
    }

    var body:some View {
        HStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        VStack(alignment:.leading,spacing:3) {
                            Text("Manuelles Fotodesign").font(.title2.bold()).foregroundStyle(FTSTheme.gold)
                            Text("Eine Designstruktur · derselbe ProductionRendererV76 wie bei MySelfie.")
                                .font(.caption).foregroundStyle(FTSTheme.muted)
                        }
                        Spacer()
                        Button("FTS-Standarddesign laden"){draft.loadFTSStandard()}
                    }

                    GroupBox("Event") {
                        VStack(alignment:.leading,spacing:8) {
                            TextField("Eventname",text:$draft.eventTitle).textFieldStyle(.roundedBorder)
                            DatePicker("Datum",selection:$draft.eventDate,displayedComponents:.date)
                            TextField("Ort",text:$draft.location).textFieldStyle(.roundedBorder)
                        }.padding(.vertical,3)
                    }

                    GroupBox("Unterer FTS-Balken · 148 × 15 mm") {
                        VStack(alignment:.leading,spacing:9) {
                            Toggle("Fotodesign / Balken aktiv",isOn:$draft.designEnabled)
                            if draft.designEnabled {
                                Picker("Balken",selection:$draft.bannerType) {
                                    Text("Einfarbig").tag("solid")
                                    Text("Verlauf").tag("gradient")
                                }.pickerStyle(.segmented)

                                HStack {
                                    Text("Farbe")
                                    TextField("#071315",text:$draft.bannerColorHex)
                                        .textFieldStyle(.roundedBorder).frame(width:110)
                                    Spacer()
                                    Text("Transparenz")
                                    Slider(value:$draft.bannerOpacity,in:0.10...1,step:0.01)
                                        .frame(width:150)
                                    Text(String(format:"%.0f %%",draft.bannerOpacity*100))
                                        .monospacedDigit().frame(width:50,alignment:.trailing)
                                }.font(.caption)

                                Picker("Ausrichtung",selection:$draft.align) {
                                    Text("Links").tag("left")
                                    Text("Mitte").tag("center")
                                    Text("Rechts").tag("right")
                                }.pickerStyle(.segmented)
                            }
                        }.padding(.vertical,3)
                    }

                    if draft.designEnabled {
                        textSection(
                            title:"Titel",
                            enabled:$draft.titleEnabled,
                            text:$draft.titleText,
                            font:$draft.titleFont,
                            size:$draft.titleSize,
                            weight:$draft.titleWeight,
                            color:$draft.titleColorHex,
                            sizeRange:2.5...7
                        )

                        textSection(
                            title:"Untertitel",
                            enabled:$draft.subtitleEnabled,
                            text:$draft.subtitleText,
                            font:$draft.subtitleFont,
                            size:$draft.subtitleSize,
                            weight:$draft.subtitleWeight,
                            color:$draft.subtitleColorHex,
                            sizeRange:1.8...5
                        )

                        GroupBox("Dritte Zeile") {
                            VStack(alignment:.leading,spacing:8) {
                                Toggle("Dritte Zeile anzeigen",isOn:$draft.lineEnabled)
                                if draft.lineEnabled {
                                    TextField("Text",text:$draft.lineText).textFieldStyle(.roundedBorder)
                                    HStack {
                                        fontPicker(selection:$draft.lineFont)
                                        Picker("Stärke",selection:$draft.lineWeight) {
                                            Text("Normal").tag(500)
                                            Text("Halbfett").tag(600)
                                            Text("Fett").tag(700)
                                            Text("Extra Fett").tag(900)
                                        }.frame(width:150)
                                    }
                                    HStack {
                                        Text("Größe").font(.caption)
                                        Slider(value:$draft.lineSize,in:1.4...4,step:0.1)
                                        Text(String(format:"%.1f",draft.lineSize)).font(.caption).monospacedDigit().frame(width:40)
                                        Text("Farbe").font(.caption)
                                        TextField("#E8EFED",text:$draft.lineColorHex)
                                            .textFieldStyle(.roundedBorder).frame(width:100)
                                    }
                                    Toggle("Datum automatisch anhängen",isOn:$draft.includeDate)
                                }
                            }.padding(.vertical,3)
                        }

                        GroupBox("Logo & Branding") {
                            VStack(alignment:.leading,spacing:8) {
                                HStack {
                                    Button("Logo auswählen"){chooseLogo()}
                                    if draft.logoPath != nil {
                                        Button("Logo entfernen",role:.destructive){draft.logoPath=nil}
                                    }
                                    Spacer()
                                    Toggle("FTS.lu · Selfie Event",isOn:$draft.showFTSBranding)
                                }
                                if let path=draft.logoPath {
                                    Text(URL(fileURLWithPath:path).lastPathComponent)
                                        .font(.caption2).foregroundStyle(FTSTheme.muted).lineLimit(1)
                                    HStack {
                                        Picker("Position",selection:$draft.logoPosition) {
                                            Text("Oben links").tag("top-left")
                                            Text("Oben rechts").tag("top-right")
                                            Text("Unten links").tag("bottom-left")
                                            Text("Unten rechts").tag("bottom-right")
                                        }.frame(width:190)
                                        Picker("Größe",selection:$draft.logoSize) {
                                            Text("Klein").tag("small")
                                            Text("Mittel").tag("medium")
                                            Text("Groß").tag("large")
                                        }.frame(width:130)
                                    }
                                }
                            }.padding(.vertical,3)
                        }
                    }

                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(18)
            }
            .frame(minWidth:560)

            Divider()

            VStack(alignment:.leading,spacing:12) {
                Text("Live-Designvorschau").font(.headline).foregroundStyle(FTSTheme.gold)
                FTSManualPrinterDesignPreview(draft:draft,photo:previewPhoto)
                    .frame(minWidth:500,minHeight:380)
                Text("Die Vorschau zeigt die Gestaltung. Nach Speichern werden echte Fotos weiterhin ausschließlich mit dem vorhandenen ProductionRendererV76 und der festen 148 × 15-mm-Bannerlogik gerendert.")
                    .font(.caption2).foregroundStyle(FTSTheme.muted)

                Spacer()

                HStack {
                    Button("Abbrechen"){dismiss()}
                    Spacer()
                    Button(saving ? "Speichert …":"Speichern & Fotos aktualisieren") {
                        saving=true
                        message=""
                        Task {
                            let ok=await state.updateManualPrinterEvent(event:event,draft:draft)
                            saving=false
                            if ok { dismiss() }
                            else { message=state.errorMessage ?? "Speichern fehlgeschlagen." }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || draft.eventTitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18)
            .frame(width:570)
        }
        .frame(minWidth:1180,minHeight:760)
    }

    @ViewBuilder
    private func textSection(
        title:String,
        enabled:Binding<Bool>,
        text:Binding<String>,
        font:Binding<String>,
        size:Binding<Double>,
        weight:Binding<Int>,
        color:Binding<String>,
        sizeRange:ClosedRange<Double>
    )->some View {
        GroupBox(title) {
            VStack(alignment:.leading,spacing:8) {
                Toggle("\(title) anzeigen",isOn:enabled)
                if enabled.wrappedValue {
                    TextField(title,text:text).textFieldStyle(.roundedBorder)
                    HStack {
                        fontPicker(selection:font)
                        Picker("Stärke",selection:weight) {
                            Text("Normal").tag(500)
                            Text("Halbfett").tag(600)
                            Text("Fett").tag(700)
                            Text("Extra Fett").tag(900)
                        }.frame(width:150)
                    }
                    HStack {
                        Text("Größe").font(.caption)
                        Slider(value:size,in:sizeRange,step:0.1)
                        Text(String(format:"%.1f",size.wrappedValue)).font(.caption).monospacedDigit().frame(width:40)
                        Text("Farbe").font(.caption)
                        TextField("#FFFFFF",text:color)
                            .textFieldStyle(.roundedBorder).frame(width:100)
                    }
                }
            }.padding(.vertical,3)
        }
    }

    private func fontPicker(selection:Binding<String>)->some View {
        Picker("Schrift",selection:selection) {
            ForEach(FTSDesignTypography.options) { option in
                Text(option.label).tag(option.id)
            }
        }
        .frame(width:180)
    }

    private func chooseLogo() {
        let panel=NSOpenPanel()
        panel.title="Logo für manuelles Printer-Event"
        panel.canChooseFiles=true
        panel.canChooseDirectories=false
        panel.allowsMultipleSelection=false
        panel.allowedFileTypes=["png","jpg","jpeg","heic","tif","tiff"]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            draft.logoPath=try FTSManualPrinterAssets.copyLogo(url,eventToken:event.event_token)
        } catch {
            message="Logo konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}

struct FTSManualPrinterDesignPreview:View {
    @ObservedObject var draft:FTSManualPrinterDesignDraft
    let photo:NSImage?

    private func previewFont(_ id:String,_ pct:Double,_ weight:Int,_ base:CGFloat)->Font {
        FTSDesignTypography.swiftUIFont(id:id,size:max(9,base*CGFloat(pct)/100),weight:weight)
    }

    var body:some View {
        GeometryReader { geo in
            let w=max(1,geo.size.width)
            let h=max(1,geo.size.height)
            ZStack(alignment:.bottom) {
                if let photo {
                    Image(nsImage:photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width:w,height:h)
                        .clipped()
                } else {
                    LinearGradient(
                        colors:[Color.gray.opacity(0.45),Color.black.opacity(0.82)],
                        startPoint:.topLeading,endPoint:.bottomTrailing
                    )
                    VStack(spacing:6) {
                        Image(systemName:"person.crop.rectangle").font(.system(size:72))
                        Text("Beispielfoto").font(.headline)
                    }.foregroundStyle(.white.opacity(0.55))
                }

                if draft.designEnabled {
                    let bh=max(76,h*0.18)
                    ZStack(alignment:alignment) {
                        Group {
                            if draft.bannerType=="gradient" {
                                LinearGradient(
                                    colors:[
                                        Color(nsColor:NSColor(hex:draft.bannerColorHex)).opacity(draft.bannerOpacity),
                                        Color(nsColor:NSColor(hex:draft.bannerColorHex)).opacity(draft.bannerOpacity*0.72),
                                        Color.clear
                                    ],
                                    startPoint:.bottom,endPoint:.top
                                )
                            } else {
                                Color(nsColor:NSColor(hex:draft.bannerColorHex)).opacity(draft.bannerOpacity)
                            }
                        }

                        HStack(alignment:.center,spacing:12) {
                            VStack(alignment:textAlignment,spacing:0) {
                                if draft.titleEnabled && !draft.titleText.isEmpty {
                                    Text(draft.titleText)
                                        .font(previewFont(draft.titleFont,draft.titleSize,draft.titleWeight,min(w,h)))
                                        .foregroundStyle(Color(nsColor:NSColor(hex:draft.titleColorHex)))
                                        .lineLimit(1).minimumScaleFactor(0.55)
                                }
                                if draft.subtitleEnabled && !draft.subtitleText.isEmpty {
                                    Text(draft.subtitleText)
                                        .font(previewFont(draft.subtitleFont,draft.subtitleSize,draft.subtitleWeight,min(w,h)))
                                        .foregroundStyle(Color(nsColor:NSColor(hex:draft.subtitleColorHex)))
                                        .lineLimit(1).minimumScaleFactor(0.55)
                                }
                                if draft.lineEnabled {
                                    let dateText=draft.includeDate ? FTSManualEventDate.string(draft.eventDate) : ""
                                    let value=[draft.lineText,dateText].filter{!$0.isEmpty}.joined(separator:" · ")
                                    if !value.isEmpty {
                                        Text(value)
                                            .font(previewFont(draft.lineFont,draft.lineSize,draft.lineWeight,min(w,h)))
                                            .foregroundStyle(Color(nsColor:NSColor(hex:draft.lineColorHex)))
                                            .lineLimit(1).minimumScaleFactor(0.55)
                                    }
                                }
                            }
                            .frame(maxWidth:.infinity,alignment:alignment)

                            if let path=draft.logoPath,let logo=NSImage(contentsOfFile:path) {
                                Image(nsImage:logo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width:draft.logoSize=="small" ? 54:(draft.logoSize=="large" ? 104:78),
                                           height:bh*0.72)
                            }
                        }
                        .padding(.horizontal,22)
                        .padding(.vertical,9)
                    }
                    .frame(height:bh)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(FTSTheme.border))
        }
    }

    private var alignment:Alignment {
        switch draft.align {
        case "center":return .center
        case "right":return .trailing
        default:return .leading
        }
    }

    private var textAlignment:HorizontalAlignment {
        switch draft.align {
        case "center":return .center
        case "right":return .trailing
        default:return .leading
        }
    }
}
