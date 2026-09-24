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
                    set:{v in core.autoDispatch=v;if v{core.discoverPrinters();core.dispatchAvailable(state:state)}}
                )).toggleStyle(.switch)
                Button("Neu laden"){Task{await core.refresh(state:state)}}
            }

            if core.printerSlots.filter(\.enabled).isEmpty {
                Text("Noch kein Ausgabedrucker aktiviert. Unter „System & Printer“ mindestens einen Canon-Drucker auswählen.")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {
                        ForEach(core.printerSlots.filter(\.enabled)) { p in
                            VStack(alignment:.leading,spacing:4) {
                                Text(p.name).font(.caption.bold()).lineLimit(1)
                                Text(p.state).font(.caption2).foregroundStyle(p.state=="ERROR" ? .red : (p.state=="IDLE" ? .green : .orange))
                                if p.eta>0 { Text("ca. \(p.eta) Sek.").font(.caption2.monospacedDigit()) }
                                if p.state=="ERROR" {
                                    Button("Fehler geprüft"){core.clearPrinterError(p.name)}.font(.caption2)
                                }
                            }
                            .padding(10).frame(width:180,alignment:.leading)
                            .background(Color(nsColor:.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius:10))
                        }
                    }
                }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    if groupedOrders.isEmpty && core.localQueue.jobs.filter({$0.status != .archived && $0.status != .cancelled}).isEmpty {
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

                    ForEach(core.localQueue.jobs.filter{$0.status != .archived && $0.status != .cancelled}) { job in
                        let printed=job.units.filter{$0.status == .printed}.count
                        VStack(alignment:.leading,spacing:7) {
                            HStack {
                                Text("\(job.sourceType) · \(job.customerCode)").font(.headline.monospacedDigit())
                                Spacer()
                                Text("\(printed)/\(job.units.count) gedruckt").font(.caption.bold())
                            }
                            ProgressView(value:Double(printed),total:Double(max(1,job.units.count)))
                            Text(job.status.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
                            ForEach(job.units.filter{$0.status == .uncertain}) { unit in
                                HStack {
                                    Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    Text("\(unit.originalName) · Status unklar").font(.caption)
                                    Spacer()
                                    Button("Nicht gedruckt · erneut") {
                                        core.requeueLocalUnit(jobID:job.id,unitID:unit.id,confirmedNotPrinted:true)
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
            core.discoverPrinters()
            await core.refresh(state:state)
        }
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

    var event:EventRow? { state.selectedEvent }

    var sourceChoices:[String] {
        var result=Set<String>()
        for item in ingest.items { result.insert(item.sourceLabel) }
        for card in ingest.detectedCards {
            if let label=card.label { result.insert(label) }
        }
        result.insert("W")
        return result.sorted()
    }

    var visibleItems:[V80MediaItem] {
        var result:[V80MediaItem]=[]
        for item in ingest.items where item.sourceLabel==sourceLabel {
            result.append(item)
            if result.count>=120 { break }
        }
        return result
    }

    var total:Int {
        var value=0
        for item in visibleItems { value += quantities[item.id] ?? 0 }
        return value
    }

    var usedCardLabels:Set<String> {
        var result=Set<String>()
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
                registeredCardsView
                sourceToolbar
                lastCodeView
                mediaGrid
            }
        }
        .padding(8)
        .onAppear { prepareForEvent() }
        .onChange(of:ingest.items) { _ in normalizeSource() }
        .task(id:event?.event_token) { await monitorEvent() }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment:.leading) {
                Text("SD-Karte / WLAN-Kamera").font(.title3.bold())
                Text(ingest.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ingest.activation != nil {
                Button("Eventordner"){ingest.revealEventFolder()}
                Button("WLAN-Eingang"){ingest.revealWLANFolder()}
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

    private var registeredCardsView: some View {
        GroupBox("SD-Karten A / B / C / D") {
            VStack(alignment:.leading,spacing:8) {
                if ingest.detectedCards.isEmpty {
                    Text("Keine SD-Karte eingesteckt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(ingest.detectedCards) { card in
                    V80CardRegistrationRow(
                        card:card,
                        usedLabels:usedCardLabels,
                        onRegister:{ label in
                            guard let e=event else{return}
                            Task{await ingest.register(card:card,label:label,event:e)}
                        }
                    )
                }
            }.padding(.vertical,4)
        }
    }

    private var sourceToolbar: some View {
        HStack {
            Picker("Quelle",selection:$sourceLabel) {
                ForEach(sourceChoices,id:\.self) { source in
                    Text(source=="W" ? "WLAN" : "Karte \(source)").tag(source)
                }
            }
            .frame(width:220)
            Spacer()
            if total>0 {
                Text("\(total) Ausdruck\(total==1 ? "" : "e") ausgewählt").font(.headline)
            }
            Button("GO · Zum Druck"){submitSelection()}
                .buttonStyle(.borderedProminent)
                .disabled(total==0)
        }
    }

    @ViewBuilder private var lastCodeView: some View {
        if !lastCode.isEmpty {
            Text("Auftrag angelegt: \(lastCode) · diese Nummer auf den Kundenzettel schreiben.")
                .font(.headline.monospacedDigit()).foregroundStyle(.green)
        }
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:180),spacing:10)],spacing:10) {
                ForEach(visibleItems) { item in
                    V80MediaItemCell(
                        item:item,
                        quantity:Binding(
                            get:{quantities[item.id] ?? 0},
                            set:{quantities[item.id]=$0}
                        )
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

    private func submitSelection() {
        guard total>0 else{return}
        var selection:[V80MediaItem:Int]=[:]
        for item in visibleItems {
            let q=quantities[item.id] ?? 0
            if q>0 { selection[item]=q }
        }
        let selectedType = sourceLabel=="W" ? "WIFI":"SD"
        let selectedLabel = sourceLabel
        Task {
            if let code=await core.createLocalJob(
                state:state,
                media:selection,
                sourceType:selectedType,
                sourceLabel:selectedLabel
            ) {
                lastCode=code
                quantities.removeAll()
                if core.autoDispatch { core.dispatchAvailable(state:state) }
            }
        }
    }

    private func prepareForEvent() {
        guard let e=event else{return}
        ingest.load(event:e)
        core.loadLocalQueue(folderPath:ingest.activation?.folderPath)
        normalizeSource()
    }

    private func normalizeSource() {
        if !sourceChoices.contains(sourceLabel) {
            sourceLabel=sourceChoices.first ?? "A"
        }
    }

    private func monitorEvent() async {
        guard let e=event else{return}
        ingest.load(event:e)
        core.loadLocalQueue(folderPath:ingest.activation?.folderPath)
        while !Task.isCancelled {
            if ingest.activation != nil { await ingest.scan(event:e) }
            try? await Task.sleep(for:.seconds(3))
        }
    }
}

struct V80CardRegistrationRow: View {
    let card:V80DetectedCard
    let usedLabels:Set<String>
    let onRegister:(String)->Void

    var body: some View {
        HStack {
            Image(systemName:"sdcard")
            VStack(alignment:.leading) {
                Text(card.label.map{"Karte \($0)"} ?? "Unbekannte Karte").bold()
                Text(card.volumeName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if card.marker == nil {
                ForEach(["A","B","C","D"],id:\.self) { label in
                    Button(label){onRegister(label)}
                        .disabled(usedLabels.contains(label))
                }
            } else {
                Text("erkannt").font(.caption.bold()).foregroundStyle(.green)
            }
        }
    }
}

struct V80MediaItemCell: View {
    let item:V80MediaItem
    @Binding var quantity:Int

    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            if let image=NSImage(contentsOfFile:item.importedPath) {
                Image(nsImage:image)
                    .resizable()
                    .scaledToFill()
                    .frame(height:145)
                    .frame(maxWidth:.infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius:8))
            }
            Text(item.originalName).font(.caption.bold()).lineLimit(1)
            Text(item.sourceType=="WIFI" ? "WLAN" : "Karte \(item.sourceLabel)")
                .font(.caption2).foregroundStyle(.secondary)
            Stepper(value:$quantity,in:0...20) {
                Text("Anzahl: \(quantity)").font(.caption.bold())
            }
        }
        .padding(9)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:12))
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
            ScrollView {
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
                            Button("Foto abgeholt") {
                                Task{await core.markPickedUp(p,state:state)}
                            }.buttonStyle(.borderedProminent)
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
            HStack(spacing:12) {
                Text("Papier: \(consumable?.paper_remaining.map(String.init) ?? "unbekannt") / 18")
                    .font(.caption)
                Text("Farbfilm: \(consumable?.film_remaining.map(String.init) ?? "unbekannt") / 54")
                    .font(.caption)
                Spacer()
                Button("18 Blatt eingelegt",action:loadPaper).font(.caption)
                Button("Farbfilm eingelegt",action:loadFilm).font(.caption)
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

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("System & Printer").font(.title3.bold())
                    Spacer()
                    Button("Drucker neu erkennen"){core.discoverPrinters()}
                }

                GroupBox("Installierte Drucker") {
                    VStack(alignment:.leading,spacing:8) {
                        if core.printerSlots.isEmpty { Text("Keine macOS-Drucker erkannt.").foregroundStyle(.secondary) }
                        ForEach(core.printerSlots) { p in
                            V81PrinterConsumableRow(
                                slot:p,
                                consumable:core.consumable(for:p.name),
                                enabled:Binding(
                                    get:{p.enabled},
                                    set:{core.setPrinter(p.name,enabled:$0)}
                                ),
                                loadPaper:{Task{await core.loadConsumable(printerName:p.name,component:"PAPER_PACK",state:state)}},
                                loadFilm:{Task{await core.loadConsumable(printerName:p.name,component:"FILM_CASSETTE",state:state)}}
                            )
                        }
                    }.padding(.vertical,5)
                }

                GroupBox("Printer-Aktivität") {
                    VStack(alignment:.leading,spacing:7) {
                        if core.printerNodes.isEmpty{Text("Noch keine aktiven Printer-Nodes.").foregroundStyle(.secondary)}
                        ForEach(core.printerNodes) { n in
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
                    GroupBox("Letzter Hinweis") { Text(e).foregroundStyle(.red).textSelection(.enabled).padding(.vertical,4) }
                }
            }.padding(8)
        }
        .onAppear{core.discoverPrinters()}
        .task{await core.checkUpdate(platform:"macos");await core.refresh(state:state)}
    }
}
