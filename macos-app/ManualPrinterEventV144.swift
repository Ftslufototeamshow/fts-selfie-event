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
        .init(id:"clean",label:"Helvetica / Clean"),
        .init(id:"avenir",label:"Avenir Next"),
        .init(id:"futura",label:"Futura"),
        .init(id:"gill",label:"Gill Sans"),
        .init(id:"verdana",label:"Verdana"),
        .init(id:"trebuchet",label:"Trebuchet"),
        .init(id:"arial",label:"Arial"),
        .init(id:"bold",label:"Arial Black"),
        .init(id:"rock",label:"Impact / Rock"),
        .init(id:"pop",label:"Pop"),
        .init(id:"copperplate",label:"Copperplate"),
        .init(id:"optima",label:"Optima"),
        .init(id:"elegant",label:"Georgia"),
        .init(id:"baskerville",label:"Baskerville"),
        .init(id:"didot",label:"Didot"),
        .init(id:"hoefler",label:"Hoefler Text"),
        .init(id:"palatino",label:"Palatino"),
        .init(id:"times",label:"Times New Roman"),
        .init(id:"retro",label:"Courier New"),
        .init(id:"menlo",label:"Menlo"),
        .init(id:"typewriter",label:"American Typewriter"),
        .init(id:"chalkboard",label:"Chalkboard"),
        .init(id:"marker",label:"Marker Felt"),
        .init(id:"handwritten",label:"Brush Script"),
        .init(id:"snell",label:"Snell Roundhand")
    ]

    static func nsFont(id:String,size:CGFloat,weight:Int)->NSFont {
        let systemWeight:NSFont.Weight =
            weight>=900 ? .black :
            weight>=800 ? .heavy :
            weight>=700 ? .bold :
            weight>=600 ? .semibold : .regular

        switch id {
        case "avenir": return NSFont(name:"Avenir Next",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "futura": return NSFont(name:"Futura",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "gill": return NSFont(name:"Gill Sans",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "verdana": return NSFont(name:"Verdana",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "trebuchet": return NSFont(name:"Trebuchet MS",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "arial": return NSFont(name:"Arial",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "bold": return NSFont(name:"Arial Black",size:size) ?? NSFont.systemFont(ofSize:size,weight:.black)
        case "rock": return NSFont(name:"Impact",size:size) ?? NSFont.systemFont(ofSize:size,weight:.black)
        case "pop": return NSFont(name:"Trebuchet MS Bold",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "copperplate": return NSFont(name:"Copperplate",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "optima": return NSFont(name:"Optima",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "elegant": return NSFont(name:"Georgia",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "baskerville": return NSFont(name:"Baskerville",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "didot": return NSFont(name:"Didot",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "hoefler": return NSFont(name:"Hoefler Text",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "palatino": return NSFont(name:"Palatino",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "times": return NSFont(name:"Times New Roman",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "retro": return NSFont(name:"Courier New",size:size) ?? NSFont.monospacedSystemFont(ofSize:size,weight:systemWeight)
        case "menlo": return NSFont(name:"Menlo",size:size) ?? NSFont.monospacedSystemFont(ofSize:size,weight:systemWeight)
        case "typewriter": return NSFont(name:"American Typewriter",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "chalkboard": return NSFont(name:"Chalkboard",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "marker": return NSFont(name:"Marker Felt",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "handwritten": return NSFont(name:"Brush Script MT",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        case "snell": return NSFont(name:"Snell Roundhand",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        default: return NSFont(name:"Helvetica Neue",size:size) ?? NSFont.systemFont(ofSize:size,weight:systemWeight)
        }
    }

    static func swiftUIFont(id:String,size:CGFloat,weight:Int)->Font {
        let swiftWeight:Font.Weight =
            weight>=900 ? .black :
            weight>=800 ? .heavy :
            weight>=700 ? .bold :
            weight>=600 ? .semibold : .regular

        let names:[String:String] = [
            "clean":"Helvetica Neue","avenir":"Avenir Next","futura":"Futura","gill":"Gill Sans",
            "verdana":"Verdana","trebuchet":"Trebuchet MS","arial":"Arial","bold":"Arial Black",
            "rock":"Impact","pop":"Trebuchet MS Bold","copperplate":"Copperplate","optima":"Optima",
            "elegant":"Georgia","baskerville":"Baskerville","didot":"Didot","hoefler":"Hoefler Text",
            "palatino":"Palatino","times":"Times New Roman","retro":"Courier New","menlo":"Menlo",
            "typewriter":"American Typewriter","chalkboard":"Chalkboard","marker":"Marker Felt",
            "handwritten":"Brush Script MT","snell":"Snell Roundhand"
        ]
        guard let name=names[id] else{return .system(size:size,weight:swiftWeight)}
        return .custom(name,size:size).weight(id=="bold" || id=="rock" ? .black:swiftWeight)
    }
}


enum FTSDesignColor {
    static func color(_ hex:String)->Color { Color(nsColor:NSColor(hex:hex)) }

    static func hex(_ color:Color)->String {
        let ns=NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r=Int(round(ns.redComponent*255))
        let g=Int(round(ns.greenComponent*255))
        let b=Int(round(ns.blueComponent*255))
        return String(format:"#%02X%02X%02X",r,g,b)
    }

    static func palette(_ spec:[String:JSONValue],fallback:String)->[String] {
        var values=(spec["colors"]?.array ?? []).compactMap{$0.string}.filter{!$0.isEmpty}
        let defaults=[fallback,"#FFCF4A","#2EC4B6","#FF6B6B","#9B5DE5","#00BBF9"]
        while values.count<6 { values.append(defaults[values.count % defaults.count]) }
        return Array(values.prefix(6))
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
    @Published var bannerHeightMM:Double
    @Published var gapTitleSubtitle:Double
    @Published var gapSubtitleLine:Double
    @Published var align:String

    @Published var titleEnabled:Bool
    @Published var titleText:String
    @Published var titleFont:String
    @Published var titleSize:Double
    @Published var titleWeight:Int
    @Published var titleColorHex:String
    @Published var titleColorMode:String
    @Published var titleColors:[String]
    @Published var titleOutlineEnabled:Bool
    @Published var titleOutlineColorHex:String
    @Published var titleOutlineWidth:Double

    @Published var subtitleEnabled:Bool
    @Published var subtitleText:String
    @Published var subtitleFont:String
    @Published var subtitleSize:Double
    @Published var subtitleWeight:Int
    @Published var subtitleColorHex:String
    @Published var subtitleColorMode:String
    @Published var subtitleColors:[String]
    @Published var subtitleOutlineEnabled:Bool
    @Published var subtitleOutlineColorHex:String
    @Published var subtitleOutlineWidth:Double

    @Published var lineEnabled:Bool
    @Published var lineText:String
    @Published var lineFont:String
    @Published var lineSize:Double
    @Published var lineWeight:Int
    @Published var lineColorHex:String
    @Published var lineColorMode:String
    @Published var lineColors:[String]
    @Published var lineOutlineEnabled:Bool
    @Published var lineOutlineColorHex:String
    @Published var lineOutlineWidth:Double
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
        let textLayout=overlay["text_layout"]?.object ?? [:]
        let firstLogo=event.logo_items?.array?.compactMap{$0.object}.first

        eventTitle=event.event_title
        eventDate=FTSManualEventDate.date(event.event_date)
        location=event.location ?? ""

        designEnabled=overlay["enabled"]?.bool != false
        bannerType=banner["type"]?.string == "gradient" ? "gradient":"solid"
        bannerColorHex=banner["color"]?.string ?? "#071315"
        bannerOpacity=max(0.10,min(1,banner["opacity"]?.double ?? 0.72))
        bannerHeightMM=max(6,min(15,banner["height_mm"]?.double ?? 15))
        gapTitleSubtitle=max(0,min(20,textLayout["gap_title_sub_pct"]?.double ?? 0))
        gapSubtitleLine=max(0,min(20,textLayout["gap_sub_line_pct"]?.double ?? 0))
        align=title["align"]?.string ?? "left"

        titleEnabled=title["enabled"]?.bool != false
        titleText=title["text"]?.string ?? event.event_title
        titleFont=title["font"]?.string ?? "clean"
        titleSize=max(2.5,min(7,title["size_pct"]?.double ?? 5.0))
        titleWeight=Int(title["weight"]?.double ?? 900)
        titleColorHex=title["color"]?.string ?? "#FFFFFF"
        titleColorMode=title["color_mode"]?.string ?? (title["multicolor"]?.bool == true ? "per_char":"solid")
        titleColors=FTSDesignColor.palette(title,fallback:title["color"]?.string ?? "#FFFFFF")
        titleOutlineEnabled=title["outline_enabled"]?.bool == true
        titleOutlineColorHex=title["outline_color"]?.string ?? "#000000"
        titleOutlineWidth=max(0.5,min(8,title["outline_width"]?.double ?? 2.5))

        subtitleEnabled=subtitle["enabled"]?.bool == true
        subtitleText=subtitle["text"]?.string ?? event.subtitle ?? ""
        subtitleFont=subtitle["font"]?.string ?? "clean"
        subtitleSize=max(1.8,min(5,subtitle["size_pct"]?.double ?? 3.0))
        subtitleWeight=Int(subtitle["weight"]?.double ?? 700)
        subtitleColorHex=subtitle["color"]?.string ?? "#D9B56D"
        subtitleColorMode=subtitle["color_mode"]?.string ?? (subtitle["multicolor"]?.bool == true ? "per_char":"solid")
        subtitleColors=FTSDesignColor.palette(subtitle,fallback:subtitle["color"]?.string ?? "#D9B56D")
        subtitleOutlineEnabled=subtitle["outline_enabled"]?.bool == true
        subtitleOutlineColorHex=subtitle["outline_color"]?.string ?? "#000000"
        subtitleOutlineWidth=max(0.5,min(8,subtitle["outline_width"]?.double ?? 2.5))

        lineEnabled=line["enabled"]?.bool == true
        lineText=line["text"]?.string ?? event.overlay_text ?? ""
        lineFont=line["font"]?.string ?? "clean"
        lineSize=max(1.4,min(4,line["size_pct"]?.double ?? 2.1))
        lineWeight=Int(line["weight"]?.double ?? 600)
        lineColorHex=line["color"]?.string ?? "#E8EFED"
        lineColorMode=line["color_mode"]?.string ?? (line["multicolor"]?.bool == true ? "per_char":"solid")
        lineColors=FTSDesignColor.palette(line,fallback:line["color"]?.string ?? "#E8EFED")
        lineOutlineEnabled=line["outline_enabled"]?.bool == true
        lineOutlineColorHex=line["outline_color"]?.string ?? "#000000"
        lineOutlineWidth=max(0.5,min(8,line["outline_width"]?.double ?? 2.5))
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
        bannerHeightMM=15
        gapTitleSubtitle=0
        gapSubtitleLine=0
        align="left"

        titleEnabled=true
        titleText=eventTitle
        titleFont="clean"
        titleSize=5.0
        titleWeight=900
        titleColorHex="#FFFFFF"
        titleColorMode="solid"
        titleColors=["#FFFFFF","#FFCF4A","#2EC4B6","#FF6B6B","#9B5DE5","#00BBF9"]
        titleOutlineEnabled=false
        titleOutlineColorHex="#000000"
        titleOutlineWidth=2.5

        subtitleEnabled=false
        subtitleText=""
        subtitleFont="clean"
        subtitleSize=3.0
        subtitleWeight=700
        subtitleColorHex="#D9B56D"
        subtitleColorMode="solid"
        subtitleColors=["#D9B56D","#FFFFFF","#FFCF4A","#2EC4B6","#FF6B6B","#9B5DE5"]
        subtitleOutlineEnabled=false
        subtitleOutlineColorHex="#000000"
        subtitleOutlineWidth=2.5

        lineEnabled=false
        lineText=location
        lineFont="clean"
        lineSize=2.1
        lineWeight=600
        lineColorHex="#E8EFED"
        lineColorMode="solid"
        lineColors=["#E8EFED","#FFFFFF","#FFCF4A","#2EC4B6","#FF6B6B","#9B5DE5"]
        lineOutlineEnabled=false
        lineOutlineColorHex="#000000"
        lineOutlineWidth=2.5
        includeDate=true
        showFTSBranding=false
    }

    func studioConfigPayload()->[String:Any] {
        [
            "version":76,
            "printer_manual":true,
            "manual_design_version":145,
            "filters":["default":"natural"],
            "overlay":[
                "enabled":designEnabled,
                "branding":showFTSBranding,
                "padding_pct":4.5,
                "text_layout":[
                    "gap_title_sub_pct":gapTitleSubtitle,
                    "gap_sub_line_pct":gapSubtitleLine
                ],
                "banner":[
                    "enabled":designEnabled,
                    "type":bannerType,
                    "color":bannerColorHex,
                    "opacity":bannerOpacity,
                    "height_mm":bannerHeightMM,
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
                    "color_mode":titleColorMode,
                    "multicolor":titleColorMode != "solid",
                    "colors":titleColors,
                    "outline_enabled":titleOutlineEnabled,
                    "outline_color":titleOutlineColorHex,
                    "outline_width":titleOutlineWidth,
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
                    "color_mode":subtitleColorMode,
                    "multicolor":subtitleColorMode != "solid",
                    "colors":subtitleColors,
                    "outline_enabled":subtitleOutlineEnabled,
                    "outline_color":subtitleOutlineColorHex,
                    "outline_width":subtitleOutlineWidth,
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
                    "color_mode":lineColorMode,
                    "multicolor":lineColorMode != "solid",
                    "colors":lineColors,
                    "outline_enabled":lineOutlineEnabled,
                    "outline_color":lineOutlineColorHex,
                    "outline_width":lineOutlineWidth,
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

                    GroupBox("Unterer FTS-Balken · max. 148 × 15 mm") {
                        VStack(alignment:.leading,spacing:9) {
                            Toggle("Fotodesign / Balken aktiv",isOn:$draft.designEnabled)
                            if draft.designEnabled {
                                Picker("Balken",selection:$draft.bannerType) {
                                    Text("Einfarbig").tag("solid")
                                    Text("Verlauf").tag("gradient")
                                }.pickerStyle(.segmented)

                                HStack {
                                    ColorPicker(
                                        "Balkenfarbe",
                                        selection:colorBinding($draft.bannerColorHex),
                                        supportsOpacity:false
                                    )
                                    TextField("#071315",text:$draft.bannerColorHex)
                                        .textFieldStyle(.roundedBorder).frame(width:105)
                                    Spacer()
                                    Text("Transparenz").font(.caption)
                                    Slider(value:$draft.bannerOpacity,in:0.10...1,step:0.01)
                                        .frame(width:135)
                                    Text(String(format:"%.0f %%",draft.bannerOpacity*100))
                                        .font(.caption).monospacedDigit().frame(width:45,alignment:.trailing)
                                }

                                HStack {
                                    Text("Balkenhöhe").font(.caption)
                                    Slider(value:$draft.bannerHeightMM,in:6...15,step:0.5)
                                    TextField(
                                        "mm",
                                        value:$draft.bannerHeightMM,
                                        format:.number.precision(.fractionLength(1))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width:58)
                                    Text("mm · maximal 15").font(.caption2).foregroundStyle(FTSTheme.muted)
                                }

                                Picker("Ausrichtung",selection:$draft.align) {
                                    Text("Links").tag("left")
                                    Text("Mitte").tag("center")
                                    Text("Rechts").tag("right")
                                }.pickerStyle(.segmented)

                                HStack(spacing:12) {
                                    Text("Abstand Titel ↔ Untertitel").font(.caption)
                                    TextField(
                                        "%",
                                        value:$draft.gapTitleSubtitle,
                                        format:.number.precision(.fractionLength(1))
                                    )
                                    .textFieldStyle(.roundedBorder).frame(width:55)
                                    Text("%").font(.caption2).foregroundStyle(FTSTheme.muted)
                                    Spacer()
                                    Text("Abstand Untertitel ↔ Zeile 3").font(.caption)
                                    TextField(
                                        "%",
                                        value:$draft.gapSubtitleLine,
                                        format:.number.precision(.fractionLength(1))
                                    )
                                    .textFieldStyle(.roundedBorder).frame(width:55)
                                    Text("%").font(.caption2).foregroundStyle(FTSTheme.muted)
                                }
                                Text("0–20 %. Größerer Wert setzt die drei Textzeilen weiter auseinander.")
                                    .font(.caption2).foregroundStyle(FTSTheme.muted)
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
                            colorMode:$draft.titleColorMode,
                            colors:$draft.titleColors,
                            outlineEnabled:$draft.titleOutlineEnabled,
                            outlineColor:$draft.titleOutlineColorHex,
                            outlineWidth:$draft.titleOutlineWidth,
                            sizeRange:2.5...9
                        )

                        textSection(
                            title:"Untertitel",
                            enabled:$draft.subtitleEnabled,
                            text:$draft.subtitleText,
                            font:$draft.subtitleFont,
                            size:$draft.subtitleSize,
                            weight:$draft.subtitleWeight,
                            color:$draft.subtitleColorHex,
                            colorMode:$draft.subtitleColorMode,
                            colors:$draft.subtitleColors,
                            outlineEnabled:$draft.subtitleOutlineEnabled,
                            outlineColor:$draft.subtitleOutlineColorHex,
                            outlineWidth:$draft.subtitleOutlineWidth,
                            sizeRange:1.8...7
                        )

                        textSection(
                            title:"Dritte Zeile",
                            enabled:$draft.lineEnabled,
                            text:$draft.lineText,
                            font:$draft.lineFont,
                            size:$draft.lineSize,
                            weight:$draft.lineWeight,
                            color:$draft.lineColorHex,
                            colorMode:$draft.lineColorMode,
                            colors:$draft.lineColors,
                            outlineEnabled:$draft.lineOutlineEnabled,
                            outlineColor:$draft.lineOutlineColorHex,
                            outlineWidth:$draft.lineOutlineWidth,
                            sizeRange:1.4...5
                        )
                        if draft.lineEnabled {
                            Toggle("Datum automatisch an dritte Zeile anhängen",isOn:$draft.includeDate)
                                .padding(.horizontal,8)
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
                Text("Die Vorschau zeigt die Gestaltung. Der reale Ausdruck nutzt weiterhin ausschließlich ProductionRendererV76. Der Balken bleibt 148 mm breit und ist maximal 15 mm hoch; kleinere Höhen sind erlaubt.")
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
        colorMode:Binding<String>,
        colors:Binding<[String]>,
        outlineEnabled:Binding<Bool>,
        outlineColor:Binding<String>,
        outlineWidth:Binding<Double>,
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
                        TextField(
                            "Größe",
                            value:size,
                            format:.number.precision(.fractionLength(1))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width:58)
                    }

                    HStack {
                        ColorPicker("Grundfarbe",selection:colorBinding(color),supportsOpacity:false)
                        TextField("#FFFFFF",text:color)
                            .textFieldStyle(.roundedBorder).frame(width:105)
                        Spacer()
                        Picker("Farbfolge",selection:colorMode) {
                            Text("Einfarbig").tag("solid")
                            Text("Jeder Buchstabe").tag("per_char")
                            Text("Je 2 Buchstaben").tag("groups_2")
                            Text("Je 3 Buchstaben").tag("groups_3")
                        }
                        .frame(width:180)
                    }

                    if colorMode.wrappedValue != "solid" {
                        VStack(alignment:.leading,spacing:5) {
                            Text("Buchstabenfarben · frei wählen, die Palette wird wiederholt")
                                .font(.caption2).foregroundStyle(FTSTheme.muted)
                            HStack(spacing:8) {
                                ForEach(0..<6,id:\.self) { index in
                                    ColorPicker(
                                        "\(index+1)",
                                        selection:colorBinding(arrayBinding(colors,index:index)),
                                        supportsOpacity:false
                                    )
                                    .labelsHidden()
                                    .help("Farbe \(index+1)")
                                }
                            }
                        }
                    }

                    Toggle("Kontur / Außenfarbe",isOn:outlineEnabled)
                    if outlineEnabled.wrappedValue {
                        HStack {
                            ColorPicker("Konturfarbe",selection:colorBinding(outlineColor),supportsOpacity:false)
                            TextField("#000000",text:outlineColor)
                                .textFieldStyle(.roundedBorder).frame(width:105)
                            Text("Stärke").font(.caption)
                            Slider(value:outlineWidth,in:0.5...8,step:0.5)
                            TextField(
                                "Kontur",
                                value:outlineWidth,
                                format:.number.precision(.fractionLength(1))
                            )
                            .textFieldStyle(.roundedBorder).frame(width:58)
                        }
                    }
                }
            }.padding(.vertical,3)
        }
    }

    private func arrayBinding(_ values:Binding<[String]>,index:Int)->Binding<String> {
        Binding(
            get:{
                guard values.wrappedValue.indices.contains(index) else{return "#FFFFFF"}
                return values.wrappedValue[index]
            },
            set:{newValue in
                var copy=values.wrappedValue
                while copy.count<=index {copy.append("#FFFFFF")}
                copy[index]=newValue
                values.wrappedValue=copy
            }
        )
    }

    private func colorBinding(_ hex:Binding<String>)->Binding<Color> {
        Binding(
            get:{FTSDesignColor.color(hex.wrappedValue)},
            set:{hex.wrappedValue=FTSDesignColor.hex($0)}
        )
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

struct FTSManualStyledTextPreview:View {
    let text:String
    let fontID:String
    let size:Double
    let weight:Int
    let baseColor:String
    let colorMode:String
    let colors:[String]
    let outlineEnabled:Bool
    let outlineColor:String
    let outlineWidth:Double
    let base:CGFloat
    let alignment:Alignment

    private var chars:[Character] { Array(text) }
    private var groupSize:Int { colorMode=="groups_3" ? 3 : (colorMode=="groups_2" ? 2 : 1) }

    private func color(at index:Int)->Color {
        guard colorMode != "solid",!colors.isEmpty else{return FTSDesignColor.color(baseColor)}
        let visible=chars[..<index].filter{!$0.isWhitespace}.count
        return FTSDesignColor.color(colors[(visible/groupSize) % colors.count])
    }

    var body:some View {
        HStack(spacing:0) {
            ForEach(chars.indices,id:\.self) { index in
                Text(String(chars[index]))
                    .font(FTSDesignTypography.swiftUIFont(
                        id:fontID,
                        size:max(7,base*CGFloat(size)/100),
                        weight:weight
                    ))
                    .foregroundStyle(color(at:index))
                    .shadow(
                        color:outlineEnabled ? FTSDesignColor.color(outlineColor):.clear,
                        radius:0,x:CGFloat(max(0.5,outlineWidth*0.35)),y:0
                    )
                    .shadow(
                        color:outlineEnabled ? FTSDesignColor.color(outlineColor):.clear,
                        radius:0,x:-CGFloat(max(0.5,outlineWidth*0.35)),y:0
                    )
                    .shadow(
                        color:outlineEnabled ? FTSDesignColor.color(outlineColor):.clear,
                        radius:0,x:0,y:CGFloat(max(0.5,outlineWidth*0.35))
                    )
                    .shadow(
                        color:outlineEnabled ? FTSDesignColor.color(outlineColor):.clear,
                        radius:0,x:0,y:-CGFloat(max(0.5,outlineWidth*0.35))
                    )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.45)
        .frame(maxWidth:.infinity,alignment:alignment)
    }
}

struct FTSManualPrinterDesignPreview:View {
    @ObservedObject var draft:FTSManualPrinterDesignDraft
    let photo:NSImage?

    var body:some View {
        GeometryReader { geo in
            let w=max(1,geo.size.width)
            let h=max(1,geo.size.height)
            let physicalWidth:CGFloat=w>=h ? 148:100
            let bh=min(h*0.44,max(30,w*CGFloat(draft.bannerHeightMM)/physicalWidth))
            let base=min(w,h)

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
                    ZStack(alignment:alignment) {
                        Group {
                            if draft.bannerType=="gradient" {
                                LinearGradient(
                                    colors:[
                                        FTSDesignColor.color(draft.bannerColorHex).opacity(draft.bannerOpacity),
                                        FTSDesignColor.color(draft.bannerColorHex).opacity(draft.bannerOpacity*0.72),
                                        Color.clear
                                    ],
                                    startPoint:.bottom,endPoint:.top
                                )
                            } else {
                                FTSDesignColor.color(draft.bannerColorHex).opacity(draft.bannerOpacity)
                            }
                        }

                        HStack(alignment:.center,spacing:12) {
                            VStack(alignment:textAlignment,spacing:0) {
                                if draft.titleEnabled && !draft.titleText.isEmpty {
                                    FTSManualStyledTextPreview(
                                        text:draft.titleText,fontID:draft.titleFont,size:draft.titleSize,
                                        weight:draft.titleWeight,baseColor:draft.titleColorHex,
                                        colorMode:draft.titleColorMode,colors:draft.titleColors,
                                        outlineEnabled:draft.titleOutlineEnabled,
                                        outlineColor:draft.titleOutlineColorHex,
                                        outlineWidth:draft.titleOutlineWidth,base:base,alignment:alignment
                                    )
                                }

                                if draft.titleEnabled && draft.subtitleEnabled {
                                    Spacer().frame(height:bh*CGFloat(draft.gapTitleSubtitle)/100)
                                }

                                if draft.subtitleEnabled && !draft.subtitleText.isEmpty {
                                    FTSManualStyledTextPreview(
                                        text:draft.subtitleText,fontID:draft.subtitleFont,size:draft.subtitleSize,
                                        weight:draft.subtitleWeight,baseColor:draft.subtitleColorHex,
                                        colorMode:draft.subtitleColorMode,colors:draft.subtitleColors,
                                        outlineEnabled:draft.subtitleOutlineEnabled,
                                        outlineColor:draft.subtitleOutlineColorHex,
                                        outlineWidth:draft.subtitleOutlineWidth,base:base,alignment:alignment
                                    )
                                }

                                if draft.subtitleEnabled && draft.lineEnabled {
                                    Spacer().frame(height:bh*CGFloat(draft.gapSubtitleLine)/100)
                                }

                                if draft.lineEnabled {
                                    let dateText=draft.includeDate ? FTSManualEventDate.string(draft.eventDate) : ""
                                    let value=[draft.lineText,dateText].filter{!$0.isEmpty}.joined(separator:" · ")
                                    if !value.isEmpty {
                                        FTSManualStyledTextPreview(
                                            text:value,fontID:draft.lineFont,size:draft.lineSize,
                                            weight:draft.lineWeight,baseColor:draft.lineColorHex,
                                            colorMode:draft.lineColorMode,colors:draft.lineColors,
                                            outlineEnabled:draft.lineOutlineEnabled,
                                            outlineColor:draft.lineOutlineColorHex,
                                            outlineWidth:draft.lineOutlineWidth,base:base,alignment:alignment
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth:.infinity,alignment:alignment)

                            if let path=draft.logoPath,let logo=NSImage(contentsOfFile:path) {
                                Image(nsImage:logo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width:draft.logoSize=="small" ? 48:(draft.logoSize=="large" ? 92:68),
                                        height:bh*0.72
                                    )
                            }
                        }
                        .padding(.horizontal,18)
                        .padding(.vertical,4)
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
