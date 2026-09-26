import SwiftUI
import AppKit

struct ProductionQueueView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ProductionQueueContent(state: state, core: state.production)
    }
}

struct ProductionQueueContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var core: ProductionCore

    var groupedOrders: [(String,[V80WorkUnit])] {
        Dictionary(grouping: core.workUnits, by: \.order_id)
            .map { ($0.key,$0.value) }
            .sorted {
                let a=$0.1.first?.order_created_at ?? ""
                let b=$1.1.first?.order_created_at ?? ""
                return a < b
            }
    }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:3) {
                    Text("Automatische Druckwarteschlange").font(.title3.bold())
                    Text(core.queueStatus.isEmpty ? "Selfie- und Kameraaufträge werden sicher verteilt." : core.queueStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Automatik",isOn:Binding(
                    get:{core.autoDispatch},
                    set:{v in
                        core.autoDispatch=v
                        if v {
                            Task {
                                await core.discoverPrinters()
                                core.dispatchAvailable(state:state)
                            }
                        }
                    }
                )).toggleStyle(.switch)
                Button("Neu laden"){Task{await core.refresh(state:state)}}
                Button("Fehlgeschlagene löschen",role:.destructive){
                    Task{await core.purgeFailedLocalJobs(state:state)}
                }
            }

            if core.printerSlots.isEmpty {
                Text("Kein Drucker angeschlossen oder im Netzwerk erreichbar.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if core.printerSlots.filter(\.enabled).isEmpty {
                Text("Drucker erkannt, aber noch nicht als Ausgabedrucker aktiviert.")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                ScrollView(.horizontal,showsIndicators:true) {
                    HStack(spacing:8) {
                        ForEach(core.printerSlots.filter(\.enabled)) { p in
                            VStack(alignment:.leading,spacing:5) {
                                FTSPrinterLiveTile(slot:p)
                                if p.eta>0 {
                                    Text("Druck läuft · ca. \(p.eta) Sek.")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.orange)
                                }
                                if let material=core.materialMessage(for:p.name) {
                                    Label(material,systemImage:"exclamationmark.triangle.fill")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.red)
                                }
                                if p.state=="ERROR" {
                                    Button("Fehler geprüft"){core.clearPrinterError(p.name)}
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            ScrollView(.vertical,showsIndicators:true) {
                LazyVStack(alignment:.leading,spacing:10) {
                    if groupedOrders.isEmpty && core.localQueue.jobs.filter({$0.status != .archived && $0.status != .cancelled && $0.status != .readyForPickup}).isEmpty {
                        VStack(spacing:10){
                            Image(systemName:"printer").font(.system(size:34)).foregroundStyle(.secondary)
                            Text("Keine Druckaufträge").font(.headline)
                            Text("Sobald ein Selfie bezahlt oder ein lokaler Auftrag freigegeben ist, erscheint er hier.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity).padding(40)
                    }

                    ForEach(groupedOrders,id:\.0) { orderID,units in
                        let printed=units.filter{$0.unit_status=="PRINTED"}.count
                        let waiting=units.filter{["READY","CLAIMED","PRINTING"].contains($0.unit_status)}.count
                        let uncertain=units.filter{$0.unit_status=="UNCERTAIN"}
                        VStack(alignment:.leading,spacing:7) {
                            HStack {
                                Text("SELFIE · \(units.first?.pickup_code ?? "------")").font(.headline.monospacedDigit())
                                Spacer()
                                Text("\(printed)/\(units.count) gedruckt").font(.caption.bold())
                            }
                            ProgressView(value:Double(printed),total:Double(max(1,units.count)))
                            Text("\(waiting) offen · Auftrag \(orderID.prefix(8).uppercased())")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(uncertain) { unit in
                                HStack {
                                    Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    Text("Druckstatus unklar · Exemplar \(unit.copy_index)").font(.caption)
                                    Spacer()
                                    Button("Nicht gedruckt · erneut freigeben") {
                                        Task{await core.requeueServerUnit(unit,state:state,confirmedNotPrinted:true)}
                                    }.font(.caption)
                                }
                                .padding(8).background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:8))
                            }
                        }
                        .padding(12).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12))
                    }

                    ForEach(core.localQueue.jobs.filter{$0.status != .archived && $0.status != .cancelled && $0.status != .readyForPickup}) { job in
                        let printed=job.units.filter{$0.status == .printed}.count
                        VStack(alignment:.leading,spacing:7) {
                            HStack(alignment:.top,spacing:10) {
                                if let first=job.units.first,
                                   let image=NSImage(contentsOfFile:first.imagePath) {
                                    Image(nsImage:image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width:72,height:94)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius:8))
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius:8).fill(Color.secondary.opacity(0.10))
                                        Image(systemName:"photo").foregroundStyle(.secondary)
                                    }
                                    .frame(width:72,height:94)
                                }
                                VStack(alignment:.leading,spacing:6) {
                                    HStack {
                                        Text("\(job.sourceType) · \(job.customerCode)").font(.headline.monospacedDigit())
                                        Spacer()
                                        Text("\(printed)/\(job.units.count) gedruckt").font(.caption.bold())
                                    }
                                    ProgressView(value:Double(printed),total:Double(max(1,job.units.count)))
                                    Text(job.status.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
                                    if let first=job.units.first {
                                        Text(first.originalName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            ForEach(job.units.filter{$0.status == .uncertain}) { unit in
                                HStack {
                                    Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    Text("\(unit.originalName) · Status unklar").font(.caption)
                                    Spacer()
                                    Button("Nicht gedruckt · erneut") {
                                        Task {
                                            await core.requeueLocalUnit(jobID:job.id,unitID:unit.id,confirmedNotPrinted:true,state:state)
                                        }
                                    }.font(.caption)
                                }
                                .padding(8).background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:8))
                            }
                            if job.status == .waiting {
                                Button("Auftrag stornieren",role:.destructive){Task{await core.cancelLocalJob(job,state:state)}}.font(.caption)
                            }
                        }
                        .padding(12).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12))
                    }
                }.padding(6)
            }
        }.padding(8)
        .task {
            await core.discoverPrinters()
            await core.refresh(state:state)
        }
    }
}

private struct FTSConnectionDots: View {
    let bars:Int
    let activeColor:Color
    var body:some View {
        HStack(spacing:3) {
            ForEach(1...5,id:\.self) { i in
                Circle()
                    .fill(i <= max(0,min(5,bars)) ? activeColor : Color.secondary.opacity(0.20))
                    .frame(width:6,height:6)
            }
        }
    }
}

private struct FTSSDCardShape: Shape {
    func path(in rect:CGRect)->Path {
        var p=Path()
        let cut=min(rect.width,rect.height)*0.22
        p.move(to:CGPoint(x:rect.minX,y:rect.minY))
        p.addLine(to:CGPoint(x:rect.maxX-cut,y:rect.minY))
        p.addLine(to:CGPoint(x:rect.maxX,y:rect.minY+cut))
        p.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
        p.addLine(to:CGPoint(x:rect.minX,y:rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct FTSSDCardBadge: View {
    let label:String?
    let accent:Color
    var body:some View {
        ZStack {
            FTSSDCardShape()
                .fill(Color.black.opacity(0.88))
                .overlay(FTSSDCardShape().stroke(accent.opacity(0.9),lineWidth:1.5))
            VStack(spacing:1) {
                Text("FTS").font(.system(size:15,weight:.black,design:.rounded)).foregroundStyle(.white)
                Text("SD").font(.system(size:9,weight:.bold)).foregroundStyle(accent)
                if let label {
                    Text("KARTE \(label)").font(.system(size:8,weight:.black,design:.rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width:58,height:72)
    }
}

private struct FTSSelphyBadge: View {
    let color:Color
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:11).fill(Color.black.opacity(0.88))
            VStack(spacing:0) {
                RoundedRectangle(cornerRadius:5)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width:48,height:13)
                    .offset(y:4)
                RoundedRectangle(cornerRadius:8)
                    .fill(Color(nsColor:.darkGray))
                    .frame(width:68,height:36)
                    .overlay(alignment:.topTrailing) {
                        Circle().fill(color).frame(width:6,height:6).padding(6)
                    }
                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width:42,height:18)
                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.5),lineWidth:1))
                    .offset(y:-2)
            }
        }
        .overlay(RoundedRectangle(cornerRadius:11).stroke(color.opacity(0.8),lineWidth:1.5))
        .frame(width:82,height:72)
    }
}

private struct FTSPrinterLiveTile: View {
    let slot:LocalPrinterSlot

    var stateColor:Color {
        switch slot.state {
        case "ERROR": return .red
        case "IDLE": return .green
        default: return .orange
        }
    }
    var stateText:String {
        switch slot.state {
        case "IDLE": return "Bereit"
        case "PRINTING": return "Druckt"
        case "TRANSFER","PREPARING": return "Übertragung"
        case "ERROR": return "Fehler"
        default: return slot.state.capitalized
        }
    }
    var bars:Int {
        let c=slot.connection.lowercased()
        if c.contains("usb") && c.contains("verbunden") { return 5 }
        if c.contains("sehr gut") || c.contains("sehr stark") { return 5 }
        if c.contains("(gut)") || c.contains("(stark)") { return 4 }
        if c.contains("mittel") { return 3 }
        if c.contains("sehr schwach") { return 1 }
        if c.contains("schwach") { return 2 }
        return 3
    }
    var displayName:String {
        let l=slot.name.lowercased()
        return (l.contains("selphy") || l.contains("cp1500")) ? "Canon SELPHY CP1500" : slot.name
    }

    var body:some View {
        HStack(spacing:9) {
            FTSSelphyBadge(color:stateColor)
            VStack(alignment:.leading,spacing:4) {
                Text(displayName).font(.caption.bold()).lineLimit(1)
                HStack(spacing:5) {
                    Circle().fill(stateColor).frame(width:7,height:7)
                    Text(stateText).font(.caption2.bold()).foregroundStyle(stateColor)
                    FTSConnectionDots(bars:bars,activeColor:slot.connection.contains("USB") ? .green : .blue)
                }
                Text(slot.connection.replacingOccurrences(of:"\n",with:" · "))
                    .font(.system(size:9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let error=slot.lastError,!error.isEmpty {
                    HStack(spacing:4) {
                        Image(systemName:"exclamationmark.triangle.fill")
                        Text(error).lineLimit(2)
                    }
                    .font(.system(size:9,weight:.semibold))
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .frame(width:260,height:(slot.lastError?.isEmpty == false ? 112 : 92),alignment:.leading)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:12))
    }
}

private struct FTSCameraLiveTile: View {
    let name:String
    let bars:Int
    let quality:String
    let detail:String
    var body:some View {
        HStack(spacing:9) {
            ZStack {
                RoundedRectangle(cornerRadius:11)
                    .fill(Color.black.opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius:11).stroke(Color.blue.opacity(0.8),lineWidth:1.5))
                Image(systemName:"camera.fill")
                    .font(.system(size:29,weight:.medium))
                    .foregroundStyle(.white)
            }
            .frame(width:72,height:72)
            VStack(alignment:.leading,spacing:4) {
                Text(name).font(.caption.bold()).lineLimit(2)
                HStack(spacing:5) {
                    Image(systemName:"wifi").font(.caption2).foregroundStyle(.blue)
                    Text(quality.isEmpty ? "WLAN aktiv" : quality.capitalized)
                        .font(.caption2.bold())
                    FTSConnectionDots(bars:bars,activeColor:.blue)
                }
                if !detail.isEmpty {
                    Text(detail).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("WLAN-Fotoeingang aktiv").font(.system(size:9)).foregroundStyle(.green)
            }
        }
        .padding(8)
        .frame(width:245,height:92,alignment:.leading)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:12))
    }
}

struct ProductionMediaView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ProductionMediaContent(state:state,ingest:state.mediaIngest,core:state.production)
    }
}

struct ProductionMediaContent: View {
    @ObservedObject var state:AppState
    @ObservedObject var ingest:MediaIngestV80
    @ObservedObject var core:ProductionCore
    @State private var sourceLabel="A"
    @State private var quantities:[String:Int]=[:]
    @State private var lastCode=""
    @State private var submitting=false
    @State private var showClearDay=false
    @State private var clearingDay=false
    @State private var showManualCardPhotos=false
    @State private var autoSubmitTask:Task<Void,Never>?=nil
    @State private var refreshingOrganizerDesign=false

    var event:EventRow? { state.selectedEvent }

    var sourceChoices:[String] {
        // A source belongs in the photo picker only when it really has at least one
        // active/draggable photo. Connected cards are shown separately in Live-Geräte.
        let result=Set(ingest.items.filter{$0.visibleInPrinter}.map{$0.sourceLabel})
        return result.sorted {
            if $0=="W" { return false }
            if $1=="W" { return true }
            return $0<$1
        }
    }

    var visibleItems:[V80MediaItem] {
        Array(
            ingest.items
                .filter{$0.sourceLabel==sourceLabel && $0.visibleInPrinter}
                .sorted{$0.importedAt>$1.importedAt}
                .prefix(120)
        )
    }

    func stablePhotoNumber(_ item:V80MediaItem)->Int {
        let ordered=ingest.items
            .filter{$0.sourceLabel==item.sourceLabel && $0.sourceType==item.sourceType}
            .sorted {
                if $0.importedAt == $1.importedAt { return $0.id < $1.id }
                return $0.importedAt < $1.importedAt
            }
        return (ordered.firstIndex(where:{$0.id==item.id}) ?? 0)+1
    }

    var total:Int {
        var value=0
        for item in visibleItems { value += quantities[item.id] ?? 0 }
        return value
    }

    var usedCardLabels:Set<String> {
        var result=ingest.registeredCardLabels
        for card in ingest.detectedCards {
            if let label=card.label { result.insert(label) }
        }
        return result
    }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            headerView
            if ingest.activation == nil {
                inactiveView
            } else {
                liveDevicesView
                sourceToolbar
                lastCodeView
                mediaGrid
            }
        }
        .padding(8)
        .onAppear { prepareForEvent() }
        .onDisappear { autoSubmitTask?.cancel() }
        .onChange(of:ingest.items) { _ in normalizeSource(preferNewest:true) }
        .task(id:event?.event_token) { await monitorEvent() }
        .alert("Tagesalbum leeren und Nummern zurücksetzen?",isPresented:$showClearDay) {
            Button("Abbrechen",role:.cancel){}
            Button("Tagesalbum leeren",role:.destructive){ clearSelectedDay() }
        } message: {
            Text("Das lokale Tagesalbum \(ingest.selectedDay) wird geleert. Die Albumstruktur bleibt bestehen und die nächste Kundennummer beginnt wieder bei 001. SD-Karten und WLAN-Quellen selbst werden nicht gelöscht.")
        }
        .sheet(isPresented:$showManualCardPhotos) {
            if let e=event {
                V80ManualCardPhotoBrowser(
                    ingest:ingest,
                    event:e,
                    cards:ingest.detectedCards
                )
                .frame(minWidth:820,minHeight:620)
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment:.leading,spacing:4) {
                Text("SD-Karte / WLAN-Kamera").font(.title3.bold())
                Text(ingest.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let e=event {
                Picker("Eventtag",selection:Binding(
                    get:{ingest.selectedDay},
                    set:{day in
                        ingest.selectDay(day,event:e)
                        core.loadLocalQueue(folderPath:ingest.activation?.folderPath)
                        quantities.removeAll()
                        lastCode=""
                        normalizeSource()
                    }
                )) {
                    ForEach(ingest.eventDays(e),id:\.self){day in Text(day).tag(day)}
                }
                .frame(width:230)
            }
            if ingest.activation != nil {
                Button("Eventordner"){ingest.revealEventFolder()}
                Button("Archiv"){ingest.revealArchiveFolder()}
                Button("WLAN-Eingang"){ingest.revealWLANFolder()}
                Button("SD/USB auf Desktop anzeigen"){ingest.showExternalMediaOnDesktop()}
                Button(refreshingOrganizerDesign ? "Design wird aktualisiert …":"Veranstalter-Design aktualisieren"){
                    refreshOrganizerDesign()
                }
                .disabled(refreshingOrganizerDesign || ingest.scanning)
                Button("Alte Fotos auf SD suchen"){
                    showManualCardPhotos=true
                }
                .disabled(ingest.detectedCards.isEmpty || ingest.scanning)
                if state.currentUser?.role=="printer_admin" {
                    Button(clearingDay ? "Wird geleert …":"Tagesalbum leeren"){
                        showClearDay=true
                    }
                    .disabled(clearingDay || !core.localQueue.jobs.isEmpty)
                }
                Button(ingest.scanning ? "Prüfe …":"Jetzt prüfen"){
                    if let e=event { Task{await ingest.scan(event:e)} }
                }
                .disabled(ingest.scanning)
            }
        }
    }

    private var inactiveView: some View {
        VStack(spacing:12) {
            Text("Das lokale Event-Album ist noch nicht freigegeben.")
            Button("Event-Album aktivieren"){activateAlbum()}
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
    }

    @ViewBuilder private var liveDevicesView: some View {
        let hasDevices = !core.printerSlots.isEmpty || ingest.wlanCameraActive || !ingest.detectedCards.isEmpty
        if hasDevices {
            VStack(alignment:.leading,spacing:5) {
                Text("Live-Geräte").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {
                        ForEach(core.printerSlots) { printer in
                            FTSPrinterLiveTile(slot:printer)
                        }
                        if ingest.wlanCameraActive {
                            FTSCameraLiveTile(
                                name:ingest.wlanCameraName.isEmpty ? "WLAN-Kamera" : ingest.wlanCameraName,
                                bars:ingest.wlanCameraBars,
                                quality:ingest.wlanCameraQuality,
                                detail:ingest.wlanCameraDetail
                            )
                        }
                        ForEach(ingest.detectedCards) { card in
                            V80CardRegistrationRow(
                                card:card,
                                usedLabels:usedCardLabels,
                                isScanning:ingest.scanning,
                                onReveal:{ ingest.reveal(card:card) },
                                onRelease:{
                                    guard let e=event else{return}
                                    Task{await ingest.release(card:card,event:e)}
                                },
                                onRegister:{ label in
                                    guard let e=event else{return}
                                    Task{await ingest.register(card:card,label:label,event:e)}
                                },
                                onReplace:{ label in
                                    guard let e=event else{return}
                                    Task{await ingest.register(card:card,label:label,event:e,replaceExisting:true)}
                                }
                            )
                            .disabled(ingest.scanning)
                        }
                    }
                }
            }
        }
    }

    private var sourceToolbar: some View {
        HStack {
            if sourceChoices.isEmpty {
                Text("Noch keine neuen Fotos verfügbar.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Quelle",selection:$sourceLabel) {
                    ForEach(sourceChoices,id:\.self) { source in
                        Text(source=="W" ? "WLAN-Kamera" : "Karte \(source)").tag(source)
                    }
                }
                .frame(width:220)
            }
            Spacer()
            if total>0 {
                Text("\(total) Ausdruck\(total==1 ? "" : "e") ausgewählt").font(.headline)
            }
            Button(submitting ? "Wird angelegt …" : "GO · Zum Druck"){submitSelection()}
                .buttonStyle(.borderedProminent)
                .disabled(total==0 || submitting || ingest.scanning)
        }
    }

    @ViewBuilder private var lastCodeView: some View {
        if !lastCode.isEmpty {
            Text("Auftrag angelegt: \(lastCode) · diese Nummer auf den Kundenzettel schreiben.")
                .font(.headline.monospacedDigit()).foregroundStyle(.green)
        }
    }

    private var mediaGrid: some View {
        ScrollView(.vertical,showsIndicators:true) {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:8)],spacing:8) {
                ForEach(visibleItems) { item in
                    V80MediaItemCell(
                        item:item,
                        photoNumber:stablePhotoNumber(item),
                        quantity:Binding(
                            get:{quantities[item.id] ?? 0},
                            set:{newValue in
                                quantities[item.id]=newValue
                                scheduleAutomaticSubmit()
                            }
                        ),
                        onHide:{
                            quantities.removeValue(forKey:item.id)
                            ingest.hideFromProgram(item)
                        }
                    )
                }
            }
            .padding(4)
        }
    }

    private func activateAlbum() {
        guard let e=event else{return}
        do {
            try ingest.activate(event:e)
            core.loadLocalQueue(folderPath:ingest.activation?.folderPath)
        } catch {
            core.lastError=error.localizedDescription
        }
    }

    private func scheduleAutomaticSubmit() {
        autoSubmitTask?.cancel()
        guard core.autoDispatch else{return}
        guard total>0 else{return}
        autoSubmitTask=Task { @MainActor in
            // Short debounce: pressing + twice or more builds the final quantity first.
            try? await Task.sleep(for:.milliseconds(1200))
            guard !Task.isCancelled else{return}
            while ingest.scanning && !Task.isCancelled {
                try? await Task.sleep(for:.milliseconds(150))
            }
            guard !Task.isCancelled,total>0,!submitting else{return}
            submitSelection()
        }
    }

    private func submitSelection() {
        guard total>0, !submitting else{return}
        autoSubmitTask?.cancel()
        submitting=true
        var selection:[V80MediaItem:Int]=[:]
        for item in visibleItems {
            let q=quantities[item.id] ?? 0
            if q>0 { selection[item]=q }
        }
        let selectedType = sourceLabel=="W" ? "WIFI":"SD"
        let selectedLabel = sourceLabel
        Task {
            defer { submitting=false }
            if let code=await core.createLocalJob(
                state:state,
                media:selection,
                sourceType:selectedType,
                sourceLabel:selectedLabel,
                eventDay:ingest.selectedDay
            ) {
                lastCode=code
                quantities.removeAll()
                if core.autoDispatch { core.dispatchAvailable(state:state) }
            }
        }
    }

    private func clearSelectedDay() {
        guard !clearingDay,!ingest.selectedDay.isEmpty else{return}
        clearingDay=true
        Task {
            defer { clearingDay=false }
            guard await core.resetLocalDay(state:state,eventDay:ingest.selectedDay) else{return}
            do {
                try ingest.clearCurrentDayLocal()
                core.clearEmptyLocalQueue()
                quantities.removeAll()
                lastCode=""
            } catch {
                core.lastError=error.localizedDescription
            }
        }
    }

    private func prepareForEvent() {
        guard let e=event else{return}
        ingest.load(event:e)
        core.loadLocalQueue(folderPath:ingest.activation?.folderPath)
        normalizeSource()
    }

    private func normalizeSource(preferNewest:Bool=false) {
        let active=ingest.items
            .filter{$0.visibleInPrinter}
            .sorted{$0.importedAt>$1.importedAt}
        guard let newest=active.first else {
            sourceLabel=""
            return
        }
        if preferNewest || !sourceChoices.contains(sourceLabel) || visibleItems.isEmpty {
            sourceLabel=newest.sourceLabel
        }
    }

    private func monitorEvent() async {
        guard let initial=event else{return}
        ingest.load(event:initial)
        core.loadLocalQueue(folderPath:ingest.activation?.folderPath)
        var designRefreshTicks=5
        while !Task.isCancelled {
            if designRefreshTicks>=5 {
                _=await state.refreshSelectedEventDefinition()
                designRefreshTicks=0
            }
            // Never keep the EventRow captured at screen-open time. Studio changes
            // must flow into the very next design pass without re-opening the app.
            if let current=state.selectedEvent,ingest.activation != nil {
                await ingest.scan(event:current)
            }
            try? await Task.sleep(for:.seconds(1))
            designRefreshTicks += 1
        }
    }

    private func refreshOrganizerDesign() {
        guard !refreshingOrganizerDesign else{return}
        refreshingOrganizerDesign=true
        Task {
            defer{refreshingOrganizerDesign=false}
            _=await state.refreshSelectedEventDefinition()
            if let current=state.selectedEvent {
                await ingest.refreshDesign(event:current)
            }
        }
    }
}

struct V80ManualCardPhotoBrowser: View {
    @ObservedObject var ingest:MediaIngestV80
    let event:EventRow
    let cards:[V80DetectedCard]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCardID=""
    @State private var photos:[V80CardPhotoCandidate]=[]
    @State private var loading=false
    @State private var importingID:String?
    @State private var message=""

    var selectedCard:V80DetectedCard? {
        cards.first(where:{$0.id==selectedCardID}) ?? cards.first
    }

    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:3) {
                    Text("Alte Fotos auf SD-Karte suchen").font(.title2.bold())
                    Text("Ein Foto auswählen und wieder in die normale Druckauswahl holen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen"){dismiss()}
            }

            if cards.isEmpty {
                VStack(spacing:10) {
                    Image(systemName:"sdcard").font(.system(size:34)).foregroundStyle(.secondary)
                    Text("Keine SD-Karte erkannt").font(.headline)
                    Text("SD-Karte einstecken und erneut öffnen.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                HStack {
                    Picker("SD-Karte",selection:$selectedCardID) {
                        ForEach(cards) { card in
                            Text(card.label.map{"Karte \($0) · \(card.volumeName)"} ?? "Nicht zugeordnet · \(card.volumeName)")
                                .tag(card.id)
                        }
                    }
                    .frame(width:360)
                    Button(loading ? "Suche …":"Fotos neu suchen"){loadPhotos()}
                        .disabled(loading)
                    Spacer()
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let card=selectedCard,card.marker == nil {
                    Label("Diese Karte zuerst A/B/C/D/E zuordnen. Danach kann ein altes Foto zurückgeholt werden.",systemImage:"exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius:8))
                }

                if loading {
                    VStack(spacing:10) {
                        ProgressView()
                        Text("Fotos auf der SD-Karte werden gelesen …").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                } else if photos.isEmpty {
                    VStack(spacing:10) {
                        Image(systemName:"photo.on.rectangle.angled").font(.system(size:34)).foregroundStyle(.secondary)
                        Text("Keine Fotos gefunden").font(.headline)
                        Text("Auf der ausgewählten Karte wurden keine unterstützten Kamera-Fotos gefunden.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:10)],spacing:10) {
                            ForEach(photos) { photo in
                                VStack(alignment:.leading,spacing:6) {
                                    if let image=NSImage(contentsOfFile:photo.path) {
                                        Image(nsImage:image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height:115)
                                            .frame(maxWidth:.infinity)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius:8))
                                    } else {
                                        ZStack {
                                            RoundedRectangle(cornerRadius:8).fill(Color.secondary.opacity(0.10))
                                            Image(systemName:"photo").font(.title2).foregroundStyle(.secondary)
                                        }
                                        .frame(height:115)
                                    }
                                    Text(photo.originalName).font(.caption.bold()).lineLimit(1)
                                    if let date=photo.capturedAt {
                                        Text(date,format:.dateTime.day().month().year().hour().minute())
                                            .font(.system(size:9)).foregroundStyle(.secondary)
                                    }
                                    Button(importingID==photo.id ? "Wird geholt …":"Zur Fotoauswahl holen") {
                                        restore(photo)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(importingID != nil || selectedCard?.marker == nil)
                                }
                                .padding(7)
                                .background(Color(nsColor:.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius:10))
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
        .padding(14)
        .onAppear {
            if selectedCardID.isEmpty { selectedCardID=cards.first?.id ?? "" }
            loadPhotos()
        }
        .onChange(of:selectedCardID) { _ in loadPhotos() }
    }

    private func loadPhotos() {
        guard let card=selectedCard,!loading else{return}
        loading=true
        message=""
        Task {
            let result=await ingest.cardPhotos(card)
            photos=result
            loading=false
            message="\(result.count) Foto\(result.count==1 ? "" : "s") gefunden"
        }
    }

    private func restore(_ photo:V80CardPhotoCandidate) {
        guard let card=selectedCard,importingID==nil else{return}
        importingID=photo.id
        Task {
            let ok=await ingest.restoreCardPhoto(photo,from:card,event:event)
            importingID=nil
            if ok { dismiss() }
        }
    }
}

struct V80CardRegistrationRow: View {
    let card:V80DetectedCard
    let usedLabels:Set<String>
    let isScanning:Bool
    let onReveal:()->Void
    let onRelease:()->Void
    let onRegister:(String)->Void
    let onReplace:(String)->Void
    @State private var replaceLabel=""
    @State private var showReplace=false
    @State private var showRelease=false

    var freeLabels:[String] {
        ["A","B","C","D","E"].filter{!usedLabels.contains($0)}
    }
    var statusColor:Color {
        if card.marker == nil { return .orange }
        return isScanning ? .orange : .green
    }
    var statusText:String {
        if card.marker == nil { return "Neu · Zuteilung wählen" }
        return isScanning ? "Import läuft" : "Bereit"
    }

    var body: some View {
        HStack(spacing:9) {
            FTSSDCardBadge(label:card.label,accent:statusColor)
            VStack(alignment:.leading,spacing:4) {
                Text(card.label.map{"SD-Karte \($0)"} ?? "Neue SD-Karte")
                    .font(.caption.bold())
                Text(card.volumeName).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing:5) {
                    Circle().fill(statusColor).frame(width:7,height:7)
                    Text(statusText).font(.caption2.bold()).foregroundStyle(statusColor)
                }
                if card.marker == nil {
                    if !freeLabels.isEmpty {
                        HStack(spacing:4) {
                            ForEach(freeLabels,id:\.self) { label in
                                Button(label){onRegister(label)}
                                    .font(.caption2.bold())
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                            }
                        }
                    } else {
                        Menu("Kennung ersetzen") {
                            ForEach(["A","B","C","D","E"],id:\.self) { label in
                                Button("Karte \(label) ersetzen") {
                                    replaceLabel=label
                                    showReplace=true
                                }
                            }
                        }
                        .font(.caption2)
                    }
                } else {
                    HStack(spacing:6) {
                        Button("Öffnen"){onReveal()}.font(.caption2).controlSize(.mini)
                        Button("Freigeben",role:.destructive){showRelease=true}.font(.caption2).controlSize(.mini)
                    }
                }
            }
        }
        .padding(8)
        .frame(width:card.marker == nil ? 255 : 205,height:92,alignment:.leading)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:12))
        .alert("Karte \(replaceLabel) ersetzen?",isPresented:$showReplace) {
            Button("Abbrechen",role:.cancel){}
            Button("Karte \(replaceLabel) ersetzen",role:.destructive) { onReplace(replaceLabel) }
        } message: {
            Text("Die bisherige Zuordnung von Karte \(replaceLabel) wird für dieses Event gesperrt. Die neu eingesteckte Karte übernimmt diese Kennung.")
        }
        .alert("Karte \(card.label ?? "") freigeben?",isPresented:$showRelease) {
            Button("Abbrechen",role:.cancel){}
            Button("Freigeben",role:.destructive){onRelease()}
        } message: {
            Text("Nur die FTS-Zuordnung A–E wird entfernt. Fotos auf der Karte und bereits importierte Originale bleiben erhalten.")
        }
    }
}

struct V80MediaItemCell: View {
    let item:V80MediaItem
    let photoNumber:Int
    @Binding var quantity:Int
    let onHide:()->Void
    @State private var showHide=false

    var sourceTitle:String {
        if item.sourceType=="WIFI" {
            if let camera=item.cameraID,!camera.isEmpty {
                let parts=camera.split(separator:"·").map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}
                if parts.count>=2 { return parts[1] }
            }
            return "WLAN-Kamera"
        }
        return "Karte \(item.sourceLabel)"
    }

    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            let previewPath=(item.designedPath?.isEmpty == false) ? item.designedPath! : item.importedPath
            if let image=NSImage(contentsOfFile:previewPath) {
                Image(nsImage:image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth:.infinity)
                    .frame(height:100)
                    .background(Color.black.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius:7))
            }
            Text("\(sourceTitle) · Foto \(String(format:"%03d",photoNumber))")
                .font(.caption.bold())
                .lineLimit(1)
            HStack(spacing:5) {
                Circle().fill(Color.green).frame(width:6,height:6)
                Text("Neu").font(.caption2.bold()).foregroundStyle(.green)
                Spacer()
                Text(item.originalName).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing:6) {
                Button {
                    quantity=max(0,quantity-1)
                } label: {
                    Image(systemName:"minus")
                }
                .controlSize(.small)
                .disabled(quantity==0)
                Text("\(quantity)").font(.caption.bold().monospacedDigit()).frame(minWidth:18)
                Button {
                    quantity=min(20,quantity+1)
                } label: {
                    Image(systemName:"plus")
                }
                .controlSize(.small)
                Spacer()
                Button(role:.destructive){showHide=true} label:{
                    Image(systemName:"eye.slash")
                }
                .buttonStyle(.borderless)
                .help("Aus Programm entfernen")
            }
        }
        .padding(7)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:10))
        .alert("Foto aus der Printer-Ansicht entfernen?",isPresented:$showHide) {
            Button("Abbrechen",role:.cancel){}
            Button("Nur aus Programm entfernen",role:.destructive){onHide()}
        } message: {
            Text("Das Foto verschwindet aus der aktiven FTS-Auswahl. Original und vorhandene Dateien auf dem Mac werden nicht gelöscht.")
        }
    }
}

struct ProductionPickupView: View {
    @EnvironmentObject var state:AppState
    @State private var search=""
    var body:some View { ProductionPickupContent(state:state,core:state.production,search:$search) }
}

struct ProductionPickupContent: View {
    @ObservedObject var state:AppState
    @ObservedObject var core:ProductionCore
    @Binding var search:String

    var filtered:[V80Pickup] {
        let q=search.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if q.isEmpty{return core.pickups}
        return core.pickups.filter{$0.customer_code.uppercased().contains(q)}
    }

    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading) {
                    Text("Kundenabholung").font(.title3.bold())
                    Text("\(core.pickups.count) Auftrag\(core.pickups.count==1 ? "" : "e") warten auf Abholung.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Abholcode suchen",text:$search).textFieldStyle(.roundedBorder).frame(width:240)
                Button("Neu laden"){Task{await core.refresh(state:state)}}
            }
            ScrollView(.vertical,showsIndicators:true) {
                LazyVStack(spacing:10) {
                    ForEach(filtered) { p in
                        HStack(spacing:14) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(p.customer_code).font(.title2.bold()).monospacedDigit()
                                Text("\(p.kind) · \(p.quantity) Ausdruck\(p.quantity==1 ? "" : "e")")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let t=p.event_title{Text(t).font(.caption)}
                            }
                            Spacer()
                            if p.kind.uppercased()=="SELFIE",
                               let order=state.orders.first(where:{$0.order_id==p.id}),
                               order.receipt_number != nil {
                                Button("Beleg für Kunden"){Task{await state.showReceipt(order)}}
                            }
                            Button(core.pickupActionsInFlight.contains(p.id) ? "Wird archiviert …" : "Foto abgeholt") {
                                Task{await core.markPickedUp(p,state:state)}
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(core.pickupActionsInFlight.contains(p.id))
                        }
                        .padding(12).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12))
                    }
                    if filtered.isEmpty {
                        Text("Keine passenden Abholungen.").foregroundStyle(.secondary).padding(30)
                    }

                    DisclosureGroup("Archiv · letzte \(core.archived.count)") {
                        VStack(spacing:7) {
                            ForEach(core.archived.prefix(100)) { a in
                                HStack {
                                    Text(a.customer_code).bold().monospacedDigit()
                                    Text(a.kind).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(a.quantity) ×").font(.caption)
                                    if state.currentUser?.role=="printer_admin" {
                                        Button(core.archiveActionsInFlight.contains(a.id) ? "Wird entfernt …" : "Aus Archiv entfernen",role:.destructive) {
                                            Task{await core.hideArchived(a,state:state)}
                                        }
                                        .font(.caption)
                                        .disabled(core.archiveActionsInFlight.contains(a.id))
                                    }
                                }.padding(7)
                            }
                        }
                    }.padding(.top,12)
                }.padding(6)
            }
        }.padding(8)
        .task{await core.refresh(state:state)}
    }
}

struct ProductionSystemView: View {
    @EnvironmentObject var state:AppState
    @State private var installing=false
    var body:some View { ProductionSystemContent(state:state,core:state.production,installing:$installing) }
}

struct V81PrinterConsumableRow: View {
    let slot:LocalPrinterSlot
    let consumable:V81Consumable?
    @Binding var enabled:Bool
    let loadPaper:()->Void
    let loadFilm:()->Void
    let coreBusyPaper:Bool
    let coreBusyFilm:Bool

    var statusColor:Color {
        if slot.state=="ERROR" { return .red }
        if slot.state=="IDLE" { return .green }
        return .orange
    }

    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Toggle("",isOn:$enabled).labelsHidden()
                Text(slot.name).frame(maxWidth:.infinity,alignment:.leading)
                Text(slot.state).font(.caption.bold()).foregroundStyle(statusColor)
                if slot.eta>0{Text("\(slot.eta)s").font(.caption.monospacedDigit())}
            }
            HStack(spacing:8) {
                Image(systemName:slot.connection.contains("USB") ? "cable.connector" : "wifi")
                    .foregroundStyle(slot.connection.contains("USB") ? .green : .secondary)
                Text(slot.connection)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            HStack(spacing:12) {
                Text("Papier: \(consumable?.paper_remaining.map(String.init) ?? "unbekannt") / 18")
                    .font(.caption)
                Text("Farbfilm: \(consumable?.film_remaining.map(String.init) ?? "unbekannt") / 54")
                    .font(.caption)
                Spacer()
                Button("18 Blatt eingelegt",action:loadPaper)
                    .font(.caption)
                    .disabled(coreBusyPaper)
                Button("Farbfilm eingelegt",action:loadFilm)
                    .font(.caption)
                    .disabled(coreBusyFilm)
            }
            if let e=slot.lastError,!e.isEmpty {
                Text(e).font(.caption).foregroundStyle(slot.state=="ERROR" ? .red : .orange)
            }
            if consumable?.paper_remaining==0 {
                Text("Papierpaket leer · neues 18-Blatt-Paket einlegen.").font(.caption).foregroundStyle(.red)
            }
            if consumable?.film_remaining==0 {
                Text("Farbfilm-Kassette leer · neue 54-Print-Kassette einsetzen.").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical,4)
    }
}

struct ProductionSystemContent:View {
    @ObservedObject var state:AppState
    @ObservedObject var core:ProductionCore
    @Binding var installing:Bool

    var printingNow:Bool {
        core.printerSlots.contains{["PREPARING","TRANSFER","PRINTING"].contains($0.state)}
    }

    var visiblePrinterNodes:[V80PrinterNode] {
        let connected=Set(core.printerSlots.map{$0.name})
        return core.printerNodes.filter{connected.contains($0.display_name)}
    }

    var body:some View {
        ScrollView(.vertical,showsIndicators:true) {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("System & Printer").font(.title3.bold())
                    Spacer()
                    Button("Drucker neu erkennen"){Task{await core.discoverPrinters()}}
                }

                GroupBox("Verbindung FTS / Internet") {
                    VStack(alignment:.leading,spacing:5) {
                        Text(core.internetStatus)
                            .font(.callout)
                            .fixedSize(horizontal:false,vertical:true)
                        Text("WLAN wird als RSSI/Linkrate gemessen. Bei USB zeigt FTS Link-Geschwindigkeit und Stromversorgung – ein Kabel hat keine WLAN-artige Signalstärke.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical,5)
                }

                GroupBox("Aktuell verbundene Drucker") {
                    VStack(alignment:.leading,spacing:8) {
                        if core.printerSlots.isEmpty { Text("Kein Drucker angeschlossen oder erreichbar.").foregroundStyle(.secondary) }
                        ForEach(core.printerSlots) { p in
                            V81PrinterConsumableRow(
                                slot:p,
                                consumable:core.consumable(for:p.name),
                                enabled:Binding(
                                    get:{p.enabled},
                                    set:{core.setPrinter(p.name,enabled:$0)}
                                ),
                                loadPaper:{Task{await core.loadConsumable(printerName:p.name,component:"PAPER_PACK",state:state)}},
                                loadFilm:{Task{await core.loadConsumable(printerName:p.name,component:"FILM_CASSETTE",state:state)}},
                                coreBusyPaper:core.consumableActionBusy(printerName:p.name,component:"PAPER_PACK"),
                                coreBusyFilm:core.consumableActionBusy(printerName:p.name,component:"FILM_CASSETTE")
                            )
                        }
                    }.padding(.vertical,5)
                }

                GroupBox("Printer-Aktivität") {
                    VStack(alignment:.leading,spacing:7) {
                        if visiblePrinterNodes.isEmpty{Text("Keine aktuell verbundenen Printer-Nodes.").foregroundStyle(.secondary)}
                        ForEach(visiblePrinterNodes) { n in
                            HStack {
                                Text(n.display_name).bold()
                                Spacer()
                                Text(n.state)
                                if let e=n.eta_seconds,e>0{Text("ca. \(e)s").monospacedDigit()}
                            }.font(.caption)
                        }
                    }.padding(.vertical,5)
                }

                GroupBox("Canon RP-108 Materiallogik") {
                    VStack(alignment:.leading,spacing:5) {
                        Text("1 RP-108 Set = 108 Prints").bold()
                        Text("6 Papierpakete × 18 Blatt · 2 Farbfilm-Kassetten × 54 Prints")
                        if let s=state.stock {
                            Text("Sicher verfügbar: \(s.safe_available ?? 0) · Selfie wartend: \(s.selfie_waiting ?? 0) · Kamera wartend: \(s.camera_waiting ?? 0)")
                        }
                    }.font(.callout).padding(.vertical,5)
                }

                GroupBox("App-Update") {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Installiert: FTS Printer Core \(ProductionCore.version) · Build \(ProductionCore.build)")
                        if core.updateAvailable,let r=core.updateRelease {
                            Text("Neue Version \(r.version) · Build \(r.build_number)").bold().foregroundStyle(.orange)
                            if let notes=r.notes,!notes.isEmpty{Text(notes).font(.caption).foregroundStyle(.secondary)}
                            HStack {
                                Button(installing ? "Wird geladen …":"Jetzt aktualisieren") {
                                    guard !printingNow else{return}
                                    installing=true
                                    Task {
                                        if let u=await core.downloadUpdate(){NSWorkspace.shared.open(u)}
                                        installing=false
                                    }
                                }.buttonStyle(.borderedProminent).disabled(printingNow || installing)
                                if printingNow{Text("Update wartet bis alle Drucker sicher frei sind.").font(.caption).foregroundStyle(.orange)}
                            }
                        } else {
                            Text("Kein neuer freigegebener Build gefunden.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Nach Update suchen"){Task{await core.checkUpdate(platform:"macos")}}
                    }.padding(.vertical,5)
                }

                if let e=core.lastError {
                    let critical=e.localizedCaseInsensitiveContains("unklar") || e.localizedCaseInsensitiveContains("physisch prüfen")
                    GroupBox(critical ? "Druck prüfen" : "Hinweis") {
                        HStack(alignment:.top,spacing:8) {
                            Image(systemName:critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .foregroundStyle(critical ? .red : .orange)
                            Text(e).foregroundStyle(critical ? .red : .secondary).textSelection(.enabled)
                        }.padding(.vertical,4)
                    }
                }
            }.padding(8)
        }
        .task{
            await core.discoverPrinters()
            await core.checkUpdate(platform:"macos")
            await core.refresh(state:state)
        }
    }
}
