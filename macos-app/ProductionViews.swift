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
    @State private var issueTarget:V126PrintIssueTarget?

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
                FTSHostPowerView(status:core.hostPower,compact:true)
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

            if let warning=core.hostPowerWarning {
                Label(warning,systemImage:"battery.25")
                    .font(.caption.bold())
                    .foregroundStyle(core.hostPower.critical ? Color.red : Color.orange)
                    .padding(8)
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .background((core.hostPower.critical ? Color.red : Color.orange).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius:8))
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
                                    Button("Druckproblem lösen") {
                                        issueTarget=V126PrintIssueTarget(
                                            kind:.server,
                                            serverUnit:unit,
                                            localJobID:nil,
                                            localUnitID:nil,
                                            customerCode:unit.pickup_code,
                                            title:"SELFIE · \(unit.pickup_code)",
                                            previewPath:unit.designed_path,
                                            canConfirmNotPrinted:true
                                        )
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
                                    Button("Druckproblem lösen") {
                                        issueTarget=V126PrintIssueTarget(
                                            kind:.local,
                                            serverUnit:nil,
                                            localJobID:job.id,
                                            localUnitID:unit.id,
                                            customerCode:job.customerCode,
                                            title:"\(job.sourceType) · \(job.customerCode)",
                                            previewPath:core.localIssuePreviewPath(jobID:job.id,unitID:unit.id),
                                            canConfirmNotPrinted:true
                                        )
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
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(30))
                await core.refreshHostPower()
            }
        }
        .sheet(item:$issueTarget) { target in
            V126PrintIssueSheet(target:target,state:state,core:core)
                .frame(minWidth:720,minHeight:620)
        }
    }
}

struct V126PrintIssueTarget:Identifiable {
    enum Kind { case server,local }
    let id=UUID()
    let kind:Kind
    let serverUnit:V80WorkUnit?
    let localJobID:UUID?
    let localUnitID:UUID?
    let customerCode:String
    let title:String
    let previewPath:String?
    let canConfirmNotPrinted:Bool
}

struct V126PrintIssueSheet:View {
    let target:V126PrintIssueTarget
    @ObservedObject var state:AppState
    @ObservedObject var core:ProductionCore
    @Environment(\.dismiss) private var dismiss
    @State private var resolution="MISPRINT"
    @State private var reason="COLOR_ERROR"
    @State private var note=""
    @State private var selectedAdmin=""
    @State private var adminCode=""
    @State private var busy=false

    private let reasons:[(String,String)]=[
        ("COLOR_ERROR","Farben / Streifen fehlerhaft"),
        ("PAPER_JAM","Papierstau / hängen geblieben"),
        ("PARTIAL_PRINT","Foto nur teilweise gedruckt"),
        ("POWER_LOSS","Stromunterbrechung"),
        ("DAMAGED_PAPER","Papier / Foto beschädigt"),
        ("OTHER","Sonstiger Druckfehler")
    ]

    private var preview:some View {
        Group {
            if target.kind == .server,
               let path=target.previewPath,
               let url=FTSAPI.shared.imageURL(storagePath:path) {
                AsyncImage(url:url) { phase in
                    if case .success(let image)=phase { image.resizable().scaledToFit() }
                    else { ZStack{Color.black.opacity(0.08);ProgressView()} }
                }
            } else if let path=target.previewPath,
                      let image=NSImage(contentsOfFile:path) {
                Image(nsImage:image).resizable().scaledToFit()
            } else {
                ZStack {
                    Color.black.opacity(0.08)
                    Image(systemName:"photo").font(.system(size:42)).foregroundStyle(.secondary)
                }
            }
        }
    }

    var body:some View {
        HStack(spacing:16) {
            preview
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius:12))

            VStack(alignment:.leading,spacing:12) {
                Text("Druckproblem · \(target.customerCode)").font(.title2.bold())
                Text("Der Originalauftrag bleibt dokumentiert. Ein Fehldruck wird als nicht berechenbarer Materialverlust protokolliert und genau einmal ersetzt.")
                    .font(.caption).foregroundStyle(.secondary)

                if target.canConfirmNotPrinted {
                    Picker("Was ist passiert?",selection:$resolution) {
                        Text("Foto unbrauchbar · Ersatzdruck").tag("MISPRINT")
                        Text("Gar nicht gedruckt · erneut freigeben").tag("NOT_PRINTED")
                    }
                    .pickerStyle(.radioGroup)
                } else {
                    Label("Foto unbrauchbar · Ersatzdruck",systemImage:"arrow.triangle.2.circlepath")
                        .font(.headline).foregroundStyle(.orange)
                }

                Picker("Grund",selection:$reason) {
                    ForEach(reasons,id:\.0){Text($0.1).tag($0.0)}
                }

                TextField("Notiz optional",text:$note)
                    .textFieldStyle(.roundedBorder)

                Button(busy ? "Wird gesendet …" : "📱 An Admin-Handy senden") {
                    sendToRemoteAdmin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                Text("Der Administrator bekommt eine Push-Nachricht und kann vom Handy freigeben oder antworten.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()
                Text("Oder Administrator direkt hier").font(.headline)
                Picker("Administrator",selection:$selectedAdmin) {
                    ForEach(state.deviceAdmins){a in Text(a.display_name).tag(a.user_id)}
                }
                SecureField("Administrator-Code",text:$adminCode)
                    .textFieldStyle(.roundedBorder)

                if !core.printIssueStatus.isEmpty {
                    Text(core.printIssueStatus).font(.caption).foregroundStyle(.green)
                }

                Spacer()
                HStack {
                    Button("Abbrechen",role:.cancel){dismiss()}
                    Spacer()
                    Button(busy ? "Wird geprüft …" : (resolution=="MISPRINT" ? "Fehldruck bestätigen · Ersatz" : "Nicht gedruckt bestätigen")) {
                        submit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || selectedAdmin.isEmpty || adminCode.isEmpty)
                }
            }
            .frame(width:330)
        }
        .padding(16)
        .task {
            if state.deviceAdmins.isEmpty { await state.loadDeviceAdmins() }
            if selectedAdmin.isEmpty {
                if state.currentUser?.role=="printer_admin",
                   let own=state.currentUser?.user_id,
                   state.deviceAdmins.contains(where:{$0.user_id==own}) {
                    selectedAdmin=own
                } else {
                    selectedAdmin=state.deviceAdmins.first?.user_id ?? ""
                }
            }
        }
    }

    private func sendToRemoteAdmin() {
        guard !busy else{return}
        busy=true
        Task {
            let ok:Bool
            switch target.kind {
            case .server:
                guard let unit=target.serverUnit else{busy=false;return}
                ok=await core.reportRemoteIssue(
                    targetKind:"SELFIE",targetUnitID:unit.unit_id,targetJobID:unit.order_id,
                    customerCode:target.customerCode,requestedResolution:resolution,
                    reasonCode:reason,note:note,state:state
                )
            case .local:
                guard let jobID=target.localJobID,let unitID=target.localUnitID else{busy=false;return}
                ok=await core.reportRemoteIssue(
                    targetKind:"LOCAL",targetUnitID:unitID.uuidString,targetJobID:jobID.uuidString,
                    customerCode:target.customerCode,requestedResolution:resolution,
                    reasonCode:reason,note:note,state:state
                )
            }
            busy=false
            if ok { dismiss() }
        }
    }

    private func submit() {
        guard !busy else{return}
        busy=true
        Task {
            let ok:Bool
            switch target.kind {
            case .server:
                guard let unit=target.serverUnit else{busy=false;return}
                ok=await core.adminResolveServerIssue(
                    unitID:unit.unit_id,
                    resolution:resolution,
                    reasonCode:reason,
                    note:note,
                    adminUserID:selectedAdmin,
                    adminCode:adminCode,
                    state:state
                )
            case .local:
                guard let jobID=target.localJobID,let unitID=target.localUnitID else{busy=false;return}
                if resolution=="NOT_PRINTED" {
                    ok=await core.adminResolveLocalNotPrinted(
                        jobID:jobID,unitID:unitID,reasonCode:reason,note:note,
                        adminUserID:selectedAdmin,adminCode:adminCode,state:state
                    )
                } else {
                    ok=await core.adminResolveLocalMisprint(
                        jobID:jobID,unitID:unitID,reasonCode:reason,note:note,
                        adminUserID:selectedAdmin,adminCode:adminCode,state:state
                    )
                }
            }
            busy=false
            if ok { dismiss() }
        }
    }
}


struct V127RemoteIssuesPanel:View {
    @ObservedObject var state:AppState
    @ObservedObject var core:ProductionCore
    @Environment(\.dismiss) private var dismiss
    @State private var replyText:[String:String]=[:]

    private var active:[V127RemoteIssue] {
        core.remoteIssues.filter{$0.status != "RESOLVED"}.sorted{$0.created_at > $1.created_at}
    }

    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading) {
                    Text("Admin-Handy / Druckprobleme").font(.title2.bold())
                    Text("Freigaben und kurze Rückmeldungen zwischen Administrator und dieser Printer-Station.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen"){dismiss()}
            }

            if !core.remoteIssueStatus.isEmpty {
                Label(core.remoteIssueStatus,systemImage:"checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.green)
            }

            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    if active.isEmpty {
                        Text("Keine offenen Admin-Vorgänge.").foregroundStyle(.secondary).padding(30)
                    }
                    ForEach(active) { issue in
                        VStack(alignment:.leading,spacing:8) {
                            HStack {
                                Text("\(issue.target_kind) · \(issue.customer_code ?? "Druckproblem")")
                                    .font(.headline.monospacedDigit())
                                Spacer()
                                Text(statusText(issue.status)).font(.caption.bold())
                                    .foregroundStyle(statusColor(issue.status))
                            }
                            Text(issue.reason_code.replacingOccurrences(of:"_",with:" "))
                                .font(.caption).foregroundStyle(.secondary)
                            if let note=issue.admin_note,!note.isEmpty {
                                Label("Admin: \(note)",systemImage:"person.badge.shield.checkmark.fill")
                                    .font(.callout.bold()).foregroundStyle(FTSTheme.gold)
                            }
                            ForEach(issue.messages) { m in
                                HStack(alignment:.top,spacing:7) {
                                    Image(systemName:m.sender_kind=="ADMIN" ? "iphone" : (m.sender_kind=="SYSTEM" ? "gearshape.fill" : "person.fill"))
                                        .foregroundStyle(m.sender_kind=="ADMIN" ? FTSTheme.gold : FTSTheme.cyan)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(m.sender_name ?? m.sender_kind).font(.caption.bold())
                                        Text(m.body).font(.callout)
                                    }
                                }
                                .padding(7)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius:8))
                            }
                            if ["APPLIED","NEEDS_ATTENTION"].contains(issue.status) {
                                TextField("Kurze Antwort an Admin",text:Binding(
                                    get:{replyText[issue.id] ?? ""},
                                    set:{replyText[issue.id]=$0}
                                ))
                                .textFieldStyle(.roundedBorder)
                                HStack {
                                    Button("Ist okay ✓") { send(issue,outcome:"OK",fallback:"Ist okay.") }
                                        .buttonStyle(.borderedProminent)
                                    Button("Problem besteht noch") { send(issue,outcome:"STILL_PROBLEM",fallback:"Problem besteht noch.") }
                                        .buttonStyle(.bordered)
                                    Spacer()
                                    Button("Nachricht senden") { send(issue,outcome:nil,fallback:"") }
                                        .disabled((replyText[issue.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor:.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius:12))
                    }
                }
            }
        }
        .padding(16)
        .task{await core.refreshRemoteIssues(state:state)}
    }

    private func send(_ issue:V127RemoteIssue,outcome:String?,fallback:String) {
        let text=(replyText[issue.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        Task {
            let ok=await core.sendRemoteIssueReply(
                issueID:issue.id,message:text.isEmpty ? fallback : text,outcome:outcome,state:state
            )
            if ok { replyText[issue.id]="" }
        }
    }

    private func statusText(_ status:String)->String {
        switch status {
        case "PENDING_ADMIN": return "Wartet auf Admin"
        case "APPROVED": return "Admin bestätigt"
        case "APPLIED": return "Übernommen"
        case "NEEDS_ATTENTION": return "Problem besteht noch"
        case "REJECTED": return "Abgelehnt"
        default: return status
        }
    }

    private func statusColor(_ status:String)->Color {
        switch status {
        case "PENDING_ADMIN","APPROVED": return .orange
        case "APPLIED": return .green
        case "NEEDS_ATTENTION","REJECTED": return .red
        default: return .secondary
        }
    }
}

private struct FTSHostPowerView: View {
    let status:V80HostPowerStatus
    var compact=false

    var tint:Color {
        if status.onACPower { return .green }
        if status.critical { return .red }
        if status.warning { return .orange }
        return .green
    }

    var icon:String {
        if status.onACPower { return status.charging ? "battery.100.bolt" : "powerplug.fill" }
        guard let p=status.percentage else{return "battery.0"}
        if p<=10{return "battery.0"}
        if p<=35{return "battery.25"}
        if p<=70{return "battery.50"}
        return "battery.100"
    }

    var body:some View {
        HStack(spacing:6) {
            Image(systemName:icon).foregroundStyle(tint)
            Text(status.summary)
                .font(compact ? .caption2 : .callout)
                .foregroundStyle(status.critical ? .red : (status.warning ? .orange : .secondary))
                .lineLimit(compact ? 1 : 2)
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
    var consumable:V81Consumable? = nil

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
        // Show the exact printer name configured in macOS. This keeps identical
        // SELPHY devices distinguishable, e.g. "Canon SELPHY CP1500 2026".
        slot.name
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
                HStack(spacing:6) {
                    Text("RP \(consumable?.rp108_remaining.map(String.init) ?? "—")/108")
                    Text("P \(consumable?.paper_remaining.map(String.init) ?? "—")/18")
                    Text("F \(consumable?.film_remaining.map(String.init) ?? "—")/54")
                }
                .font(.system(size:9,weight:.semibold,design:.monospaced))
                .foregroundStyle(.secondary)
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
        .frame(width:300,height:(slot.lastError?.isEmpty == false ? 128 : 108),alignment:.leading)
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


private struct V128ActiveSourceTile:View {
    let source:String
    let selected:Bool
    let openCount:Int
    let printingCount:Int
    let recentDone:Int
    let errorCount:Int
    let onSelect:()->Void

    private var title:String { source=="W" ? "WLAN-Kamera" : "SD-Karte \(source)" }
    private var icon:String { source=="W" ? "camera.fill" : "sdcard.fill" }

    var body:some View {
        Button(action:onSelect) {
            HStack(spacing:9) {
                ZStack {
                    RoundedRectangle(cornerRadius:10)
                        .fill(selected ? FTSTheme.cyan.opacity(0.20) : Color.black.opacity(0.28))
                    Image(systemName:icon)
                        .font(.system(size:24,weight:.semibold))
                        .foregroundStyle(selected ? FTSTheme.cyan : FTSTheme.gold)
                }
                .frame(width:48,height:58)
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.caption.bold()).lineLimit(1)
                    HStack(spacing:6) {
                        if openCount>0 { Text("\(openCount) neu").foregroundStyle(.green) }
                        if printingCount>0 { Text("\(printingCount) im Druck").foregroundStyle(.orange) }
                        if recentDone>0 { Text("\(recentDone) fertig").foregroundStyle(FTSTheme.cyan) }
                        if errorCount>0 { Text("\(errorCount) Fehler").foregroundStyle(.red) }
                    }
                    .font(.system(size:9,weight:.semibold))
                    Text("Antippen · Fotos unten")
                        .font(.system(size:9)).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(width:205,height:76,alignment:.leading)
            .background(Color(nsColor:.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius:11)
                    .stroke(selected ? FTSTheme.cyan : Color.white.opacity(0.08),lineWidth:selected ? 1.5:1)
            )
            .clipShape(RoundedRectangle(cornerRadius:11))
        }
        .buttonStyle(.plain)
    }
}

struct V80PhotoPrintPreviewSheet: View {
    @ObservedObject var state:AppState
    let item:V80MediaItem
    let event:EventRow?
    let photoNumber:Int
    let sourceTitle:String
    let initialLayout:V80PrintLayout
    let initialQuantity:Int
    let allowPrint:Bool
    let onCancel:()->Void
    let onConfirm:(Int,V80PrintLayout)->Void

    @State private var quantity:Int
    @State private var layout:V80PrintLayout
    @State private var previewImage:NSImage?
    @State private var renderingPreview=false
    @State private var dragStartX:Double?
    @State private var dragStartY:Double?
    @State private var qrImage:NSImage?
    @State private var digitalStatus="Digitalfoto wird vorbereitet …"
    @State private var digitalURL:URL?
    @State private var digitalKey=""

    init(
        state:AppState,
        item:V80MediaItem,
        event:EventRow?,
        photoNumber:Int,
        sourceTitle:String,
        initialLayout:V80PrintLayout,
        initialQuantity:Int,
        allowPrint:Bool=true,
        onCancel:@escaping()->Void,
        onConfirm:@escaping(Int,V80PrintLayout)->Void
    ) {
        self.state=state
        self.item=item
        self.event=event
        self.photoNumber=photoNumber
        self.sourceTitle=sourceTitle
        self.initialLayout=initialLayout
        self.initialQuantity=initialQuantity
        self.allowPrint=allowPrint
        self.onCancel=onCancel
        self.onConfirm=onConfirm
        _quantity=State(initialValue:max(1,initialQuantity))
        _layout=State(initialValue:initialLayout)
        // Start with the untouched camera original. The separate print preview
        // replaces it after rendering; the original file itself is never changed.
        let seed=NSImage(contentsOfFile:item.importedPath)
        _previewImage=State(initialValue:seed)
    }

    private var liveGreenSettings:FTSGreenScreenSettings {
        guard let event else{return FTSGreenScreenSettings()}
        return FTSGreenScreenStore.settings(eventToken:event.event_token)
    }

    private var previewKey:String {
        [
            item.id,
            liveGreenSettings.signature,
            String(format:"%.3f",layout.cropZoom),
            String(format:"%.3f",layout.cropOffsetX),
            String(format:"%.3f",layout.cropOffsetY),
            layout.photoEffect.rawValue,
            layout.frameMode.rawValue,
            layout.fitMode.rawValue,
            String(format:"%.2f",layout.borderMM),
            layout.borderColorHex.uppercased()
        ].joined(separator:"|")
    }

    private var frameLabel:String {
        switch layout.frameMode {
        case .borderless:return "Randlos"
        case .white:return "Weißer Rand"
        case .color:return "Farbrand"
        }
    }

    private func refreshPreview() async {
        renderingPreview=true
        defer{renderingPreview=false}
        do {
            try await Task.sleep(nanoseconds:80_000_000)
            try Task.checkCancellation()
            let rendered:NSImage
            if let event {
                rendered=try await ProductionRendererV76.renderedImage(
                    sourceURL:URL(fileURLWithPath:item.importedPath),
                    event:event,
                    cropZoom:CGFloat(layout.cropZoom),
                    cropOffsetX:CGFloat(layout.cropOffsetX),
                    cropOffsetY:CGFloat(layout.cropOffsetY),
                    photoEffect:layout.photoEffect,
                    greenScreenSettings:liveGreenSettings
                )
            } else {
                let path=(item.designedPath?.isEmpty == false) ? item.designedPath! : item.importedPath
                guard let image=NSImage(contentsOfFile:path) else{return}
                rendered=image
            }
            try Task.checkCancellation()
            previewImage=V80PrintLayoutComposer.apply(rendered,layout:layout)
        } catch is CancellationError {
            return
        } catch {
            let path=(item.designedPath?.isEmpty == false) ? item.designedPath! : item.importedPath
            if let fallback=NSImage(contentsOfFile:path) {
                previewImage=V80PrintLayoutComposer.apply(fallback,layout:layout)
            }
        }
    }

    private func savePreparedPreview() -> String? {
        guard let image=previewImage,
              let activation=state.mediaIngest.activation,
              let tiff=image.tiffRepresentation,
              let rep=NSBitmapImageRep(data:tiff),
              let jpg=rep.representation(using:.jpeg,properties:[.compressionFactor:0.96]) else{return nil}
        let folder=URL(fileURLWithPath:activation.folderPath,isDirectory:true)
            .appendingPathComponent("Druckbereit/Varianten",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let safeID=String(item.id.prefix(20))
            let url=folder.appendingPathComponent("variant-\(safeID).jpg")
            try jpg.write(to:url,options:.atomic)
            return url.path
        } catch {
            return nil
        }
    }

    private func refreshDigitalQR(key:String) async {
        do {
            try await Task.sleep(for:.milliseconds(650))
            try Task.checkCancellation()
            guard digitalKey != key,let image=previewImage else{return}
            digitalStatus="Digitalfoto wird vorbereitet …"
            let url=try await state.createDigitalLink(
                image:image,
                fileName:"FTS-\(sourceTitle.replacingOccurrences(of:" ",with:"-"))-\(String(format:"%03d",photoNumber)).jpg"
            )
            try Task.checkCancellation()
            digitalURL=url
            qrImage=FTSQRCodeRenderer.image(for:url.absoluteString)
            digitalKey=key
            digitalStatus="Scannen und digitales Foto herunterladen · Link 7 Tage gültig."
        } catch is CancellationError {
            return
        } catch {
            qrImage=nil
            digitalURL=nil
            digitalStatus="QR derzeit nicht verfügbar: \(error.localizedDescription)"
        }
    }

    var body:some View {
        HStack(spacing:18) {
            VStack(alignment:.leading,spacing:8) {
                Text("Druckvorschau").font(.title2.bold())
                Text("\(sourceTitle) · Foto \(String(format:"%03d",photoNumber)) · \(item.originalName)")
                    .font(.caption).foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius:12).fill(Color.black.opacity(0.12))
                    if let image=previewImage {
                        Image(nsImage:image)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance:1)
                                    .onChanged { value in
                                        if dragStartX == nil {
                                            dragStartX=layout.cropOffsetX
                                            dragStartY=layout.cropOffsetY
                                        }
                                        let sx=dragStartX ?? layout.cropOffsetX
                                        let sy=dragStartY ?? layout.cropOffsetY
                                        layout.cropOffsetX=max(-1,min(1,sx-Double(value.translation.width/220)))
                                        layout.cropOffsetY=max(-1,min(1,sy-Double(value.translation.height/220)))
                                    }
                                    .onEnded { _ in
                                        dragStartX=nil
                                        dragStartY=nil
                                    }
                            )
                    } else {
                        VStack(spacing:8) {
                            Image(systemName:"photo").font(.system(size:36))
                            Text("Vorschau konnte nicht geladen werden.")
                        }.foregroundStyle(.secondary)
                    }
                    if renderingPreview {
                        ProgressView().controlSize(.small).padding(10)
                            .background(.ultraThinMaterial).clipShape(Capsule())
                    }
                }
                .frame(minWidth:520,minHeight:520)
                Text("Foto direkt in der Vorschau ziehen. Die Vorschau wird mit derselben Crop-, Rand- und Designlogik wie der Ausdruck erzeugt.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment:.leading,spacing:12) {
                Text("Druck einstellen").font(.headline)

                GroupBox("Ausschnitt") {
                    VStack(alignment:.leading,spacing:7) {
                        HStack {
                            Text("Zoom")
                            Spacer()
                            Text(String(format:"%.0f %%",layout.cropZoom*100)).monospacedDigit()
                        }.font(.caption)
                        Slider(value:$layout.cropZoom,in:1...1.35,step:0.01)
                        HStack {
                            Text("Zum Verschieben Foto links/rechts oder hoch/runter ziehen.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("Zentrieren") {
                                layout.cropZoom=1
                                layout.cropOffsetX=0
                                layout.cropOffsetY=0
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical,3)
                }

                GroupBox("Foto-Look · nur dieses Foto") {
                    VStack(alignment:.leading,spacing:7) {
                        Picker("Look",selection:$layout.photoEffect) {
                            ForEach(FTSPhotoEffect.allCases,id:\.self){effect in
                                Text(effect.label).tag(effect)
                            }
                        }
                        .pickerStyle(.menu)
                        if layout.photoEffect == .comic {
                            let greenActive = event.map{FTSGreenScreenStore.settings(eventToken:$0.event_token).enabled} ?? false
                            Text(greenActive
                                 ? "Comic: Person inklusive Gesicht, Haare und Kleidung wird gezeichnet; der aktive Green-Screen-Hintergrund wird eingesetzt."
                                 : "Comic: Nur die erkannte Person inklusive Gesicht, Haare und Kleidung wird gezeichnet. Der echte Hintergrund bleibt normal.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Dieser Look wird nur auf dieses Foto gespeichert und nicht auf das nächste Foto übernommen.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical,3)
                }

                Picker("Druckrand",selection:$layout.frameMode) {
                    Text("Randlos").tag(V80PrintFrameMode.borderless)
                    Text("Weißer Rand").tag(V80PrintFrameMode.white)
                    Text("Farbrand").tag(V80PrintFrameMode.color)
                }
                .pickerStyle(.segmented)

                if layout.frameMode != .borderless {
                    VStack(alignment:.leading,spacing:5) {
                        HStack {
                            Text("Randbreite")
                            Spacer()
                            Text(String(format:"%.1f mm",layout.borderMM)).monospacedDigit()
                        }.font(.caption)
                        Slider(value:$layout.borderMM,in:1...10,step:0.5)
                    }
                }

                if layout.frameMode == .color {
                    VStack(alignment:.leading,spacing:7) {
                        Text("Randfarbe").font(.caption.bold())
                        HStack(spacing:7) {
                            ForEach(["#FFFFFF","#000000","#D4AF37","#D93025","#1A73E8","#188038"],id:\.self) { hex in
                                Button {
                                    layout.borderColorHex=hex
                                } label: {
                                    Circle()
                                        .fill(Color(nsColor:NSColor(hex:hex)))
                                        .frame(width:24,height:24)
                                        .overlay(
                                            Circle().stroke(
                                                layout.borderColorHex.uppercased()==hex ? Color.primary : Color.secondary.opacity(0.25),
                                                lineWidth:layout.borderColorHex.uppercased()==hex ? 2:1
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        TextField("#RRGGBB",text:$layout.borderColorHex)
                            .textFieldStyle(.roundedBorder)
                            .frame(width:130)
                    }
                }

                Picker("Bildanpassung",selection:$layout.fitMode) {
                    Text("Bild füllen").tag(V80PrintFitMode.fill)
                    Text("Einpassen").tag(V80PrintFitMode.fit)
                }
                .pickerStyle(.segmented)

                Text(layout.fitMode == .fit
                     ? "Einpassen zeigt die komplette fertige Druckfläche innerhalb des gewählten Randes."
                     : "Bild füllen nutzt die Fläche vollständig.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                Stepper(value:$quantity,in:1...20) {
                    HStack {
                        Text("Anzahl").bold()
                        Spacer()
                        Text("\(quantity) ×").font(.title3.bold()).monospacedDigit()
                    }
                }
                .disabled(!allowPrint)

                Text(allowPrint
                     ? "Der Auftrag wird erst nach „OK · Zum Druck“ angelegt. Die Mengenwahl allein startet keinen Druck."
                     : "Dieses Foto ist bereits in Bearbeitung oder fertig. Es bleibt hier nur zur Kontrolle sichtbar.")
                    .font(.caption).foregroundStyle(.secondary)

                GroupBox("Digitalfoto per QR · nur große Ansicht") {
                    HStack(alignment:.center,spacing:10) {
                        if let qrImage {
                            Image(nsImage:qrImage)
                                .resizable()
                                .interpolation(.none)
                                .frame(width:104,height:104)
                                .background(.white)
                                .padding(4)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius:8))
                        } else {
                            ZStack{
                                RoundedRectangle(cornerRadius:8).fill(Color.secondary.opacity(0.08))
                                ProgressView().controlSize(.small)
                            }.frame(width:112,height:112)
                        }
                        VStack(alignment:.leading,spacing:5) {
                            Text("Digital mitnehmen").font(.caption.bold())
                            Text(digitalStatus).font(.caption2).foregroundStyle(.secondary)
                            if digitalURL != nil {
                                Label("QR ist nicht Bestandteil des Druckfotos.",systemImage:"checkmark.shield.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            }
                            Text("Nur für den bezahlten Kunden zeigen.")
                                .font(.caption2.bold()).foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                HStack {
                    Button(allowPrint ? "Abbrechen" : "Schließen"){onCancel()}
                    Spacer()
                    if allowPrint {
                        Button("OK · Zum Druck"){
                            var confirmed=layout
                            confirmed.greenScreenSnapshot=liveGreenSettings.printSnapshot
                            confirmed.preparedImagePath=savePreparedPreview()
                            onConfirm(quantity,confirmed)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(renderingPreview)
                    }
                }

                Text("Aktuell: \(frameLabel)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width:330)
        }
        .padding(16)
        .frame(minWidth:940,minHeight:680)
        .task(id:previewKey){
            await refreshPreview()
            if !Task.isCancelled { await refreshDigitalQR(key:previewKey) }
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
    @State private var submitting=false
    @State private var showClearDay=false
    @State private var clearingDay=false
    @State private var showManualCardPhotos=false
    @State private var refreshingOrganizerDesign=false
    @State private var previewItem:V80MediaItem?
    @State private var printLayouts:[String:V80PrintLayout]=[:]
    @State private var defaultPrintLayout=V80PrintLayout()
    @State private var displayClock=Date()

    private let recentFinishedWindow:TimeInterval=30*60

    var event:EventRow? { state.selectedEvent }

    func visibleInActiveWorkArea(_ item:V80MediaItem)->Bool {
        switch item.effectiveWorkflow {
        case .active,.queued,.error:
            return true
        case .produced:
            guard let updated=item.workflowUpdatedAt else{return false}
            return displayClock.timeIntervalSince(updated) < recentFinishedWindow
        case .delivered,.hidden:
            return false
        }
    }

    var sourceChoices:[String] {
        let result=Set(ingest.items.filter{visibleInActiveWorkArea($0)}.map{$0.sourceLabel})
        return result.sorted {
            if $0=="W" { return false }
            if $1=="W" { return true }
            return $0<$1
        }
    }

    var visibleItems:[V80MediaItem] {
        Array(
            ingest.items
                .filter{$0.sourceLabel==sourceLabel && visibleInActiveWorkArea($0)}
                .sorted{$0.importedAt>$1.importedAt}
                .prefix(120)
        )
    }

    func sourceCounts(_ source:String)->(open:Int,printing:Int,recentDone:Int,error:Int) {
        let sourceItems=ingest.items.filter{$0.sourceLabel==source && visibleInActiveWorkArea($0)}
        return (
            sourceItems.filter{$0.effectiveWorkflow == .active}.count,
            sourceItems.filter{$0.effectiveWorkflow == .queued}.count,
            sourceItems.filter{$0.effectiveWorkflow == .produced}.count,
            sourceItems.filter{$0.effectiveWorkflow == .error}.count
        )
    }

    func statusText(for item:V80MediaItem)->String {
        switch item.effectiveWorkflow {
        case .active: return "Neu"
        case .queued: return "Im Druck / Warteschlange"
        case .error: return "Druckproblem"
        case .produced:
            guard let updated=item.workflowUpdatedAt else{return "Fertig"}
            let seconds=max(0,recentFinishedWindow-displayClock.timeIntervalSince(updated))
            let left=max(1,Int((seconds/60.0).rounded(.up)))
            return "Fertig · noch \(left) Min sichtbar"
        case .delivered: return "Archiv"
        case .hidden: return "Ausgeblendet"
        }
    }

    func statusColor(for item:V80MediaItem)->Color {
        switch item.effectiveWorkflow {
        case .active: return .green
        case .queued: return .orange
        case .produced: return FTSTheme.cyan
        case .error: return .red
        case .delivered,.hidden: return .secondary
        }
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
        .sheet(item:$previewItem) { item in
            V80PhotoPrintPreviewSheet(
                state:state,
                item:item,
                event:event,
                photoNumber:stablePhotoNumber(item),
                sourceTitle:mediaSourceTitle(item),
                initialLayout:printLayouts[item.id] ?? defaultPrintLayout,
                initialQuantity:quantities[item.id] ?? 0,
                allowPrint:item.effectiveWorkflow == .active,
                onCancel:{previewItem=nil},
                onConfirm:{qty,layout in
                    quantities[item.id]=qty
                    printLayouts[item.id]=layout
                    var reusable=layout
                    reusable.photoEffect = .normal
                    reusable.greenScreenSnapshot = nil
                    reusable.preparedImagePath = nil
                    defaultPrintLayout=reusable
                    saveDefaultPrintLayout()
                    previewItem=nil
                    submitSelection(only:item.id)
                }
            )
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
        let connectedPrinters=core.printerSlots.filter(\.enabled)
        let unregisteredCards=ingest.detectedCards.filter{!$0.registered}
        if !connectedPrinters.isEmpty || !sourceChoices.isEmpty || !unregisteredCards.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                if !connectedPrinters.isEmpty {
                    Text("Canon-Drucker · aktuell angeschlossen").font(.caption.bold()).foregroundStyle(.secondary)
                    ScrollView(.horizontal,showsIndicators:true) {
                        HStack(spacing:8) {
                            ForEach(connectedPrinters) { printer in
                                FTSPrinterLiveTile(slot:printer,consumable:core.consumable(for:printer.name))
                            }
                        }
                        .padding(.bottom,2)
                    }
                }

                if !sourceChoices.isEmpty || !unregisteredCards.isEmpty {
                    Text("Aktive SD-/WLAN-Quellen").font(.caption.bold()).foregroundStyle(.secondary)
                    ScrollView(.horizontal,showsIndicators:true) {
                        HStack(spacing:8) {
                            ForEach(sourceChoices,id:\.self) { source in
                                let counts=sourceCounts(source)
                                V128ActiveSourceTile(
                                    source:source,
                                    selected:sourceLabel==source,
                                    openCount:counts.open,
                                    printingCount:counts.printing,
                                    recentDone:counts.recentDone,
                                    errorCount:counts.error,
                                    onSelect:{sourceLabel=source}
                                )
                            }
                            ForEach(unregisteredCards) { card in
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
                        .padding(.bottom,2)
                    }
                }
            }
        }
    }

    private var sourceToolbar: some View {
        HStack {
            if sourceChoices.isEmpty {
                Text("Keine aktive Karte / WLAN-Quelle. Erledigte Fotos verschwinden nach 30 Minuten aus dieser Arbeitsansicht.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(sourceLabel=="W" ? "WLAN-Kamera" : "Karte \(sourceLabel)")
                    .font(.headline)
                Text("· \(visibleItems.count) Foto\(visibleItems.count==1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if total>0 {
                Text("\(total) Ausdruck\(total==1 ? "" : "e") ausgewählt").font(.headline)
            }
            Button(submitting ? "Wird angelegt …" : "OK · Zum Druck"){submitSelection()}
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
        ScrollView(.horizontal,showsIndicators:true) {
            LazyHStack(alignment:.top,spacing:8) {
                ForEach(visibleItems) { item in
                    V80MediaItemCell(
                        item:item,
                        event:event,
                        photoNumber:stablePhotoNumber(item),
                        quantity:Binding(
                            get:{quantities[item.id] ?? 0},
                            set:{newValue in quantities[item.id]=newValue}
                        ),
                        statusText:statusText(for:item),
                        statusColor:statusColor(for:item),
                        canSelect:item.effectiveWorkflow == .active,
                        onPreview:{previewItem=item},
                        onHide:{
                            quantities.removeValue(forKey:item.id)
                            printLayouts.removeValue(forKey:item.id)
                            ingest.hideFromProgram(item)
                        }
                    )
                    .frame(width:180)
                }
            }
            .padding(4)
        }
        .frame(minHeight:215,maxHeight:235)
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

    private func submitSelection(only mediaID:String?=nil) {
        guard !submitting else{return}
        submitting=true
        var selection:[V80MediaItem:Int]=[:]
        for item in visibleItems {
            if let mediaID, item.id != mediaID { continue }
            let q=quantities[item.id] ?? 0
            if q>0 { selection[item]=q }
        }
        guard !selection.isEmpty else {
            submitting=false
            return
        }

        let first=selection.keys.first
        let selectedType=(first?.sourceType=="WIFI" || first?.sourceLabel=="W") ? "WIFI":"SD"
        let selectedLabel=first?.sourceLabel ?? sourceLabel
        let layouts=Dictionary(uniqueKeysWithValues:selection.keys.map {
            ($0.id,printLayouts[$0.id] ?? defaultPrintLayout)
        })
        let submittedIDs=Set(selection.keys.map{$0.id})

        Task {
            defer { submitting=false }
            if let code=await core.createLocalJob(
                state:state,
                media:selection,
                layouts:layouts,
                sourceType:selectedType,
                sourceLabel:selectedLabel,
                eventDay:ingest.selectedDay
            ) {
                lastCode=code
                for id in submittedIDs {
                    quantities.removeValue(forKey:id)
                    printLayouts.removeValue(forKey:id)
                }
                if core.autoDispatch { core.dispatchAvailable(state:state) }
            }
        }
    }

    private func mediaSourceTitle(_ item:V80MediaItem)->String {
        if item.sourceType=="WIFI" {
            if let camera=item.cameraID,!camera.isEmpty {
                let parts=camera.split(separator:"·").map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}
                if parts.count>=2 { return parts[1] }
            }
            return "WLAN-Kamera"
        }
        return "Karte \(item.sourceLabel)"
    }

    private func printLayoutDefaultsKey()->String {
        "fts.print.layout.v116.\(event?.event_token ?? "default")"
    }

    private func loadDefaultPrintLayout() {
        guard let data=UserDefaults.standard.data(forKey:printLayoutDefaultsKey()),
              let value=try? JSONDecoder().decode(V80PrintLayout.self,from:data) else {
            defaultPrintLayout=V80PrintLayout()
            return
        }
        var reusable=value
        reusable.photoEffect = .normal
        reusable.greenScreenSnapshot = nil
        reusable.preparedImagePath = nil
        defaultPrintLayout=reusable
    }

    private func saveDefaultPrintLayout() {
        if let data=try? JSONEncoder().encode(defaultPrintLayout) {
            UserDefaults.standard.set(data,forKey:printLayoutDefaultsKey())
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
        loadDefaultPrintLayout()
        printLayouts.removeAll()
        normalizeSource()
    }

    private func normalizeSource(preferNewest:Bool=false) {
        let active=ingest.items
            .filter{visibleInActiveWorkArea($0)}
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
            displayClock=Date()
            normalizeSource()
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
                    Label("Diese Karte zuerst A–Z zuordnen. Danach kann ein altes Foto zurückgeholt werden.",systemImage:"exclamationmark.triangle.fill")
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

    var allLabels:[String] { Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) }
    var freeLabels:[String] { allLabels.filter{!usedLabels.contains($0)} }
    var usedLabelsSorted:[String] { allLabels.filter{usedLabels.contains($0)} }
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
                            ForEach(Array(freeLabels.prefix(6)),id:\.self) { label in
                                Button(label){onRegister(label)}
                                    .font(.caption2.bold())
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                            }
                            if freeLabels.count>6 {
                                Menu("Weitere") {
                                    ForEach(Array(freeLabels.dropFirst(6)),id:\.self) { label in
                                        Button("Karte \(label) zuordnen"){onRegister(label)}
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                    if !usedLabelsSorted.isEmpty {
                        Menu("Formatiert / Kennung neu vergeben") {
                            ForEach(usedLabelsSorted,id:\.self) { label in
                                Button("Kennung \(label) neu vergeben") {
                                    replaceLabel=label
                                    showReplace=true
                                }
                            }
                        }
                        .font(.caption2)
                        Text("Belegt: \(usedLabelsSorted.joined(separator:", "))")
                            .font(.system(size:8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
        .frame(width:card.marker == nil ? 320 : 205,height:card.marker == nil ? 112 : 92,alignment:.leading)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:12))
        .alert("Karte \(replaceLabel) ersetzen?",isPresented:$showReplace) {
            Button("Abbrechen",role:.cancel){}
            Button("Karte \(replaceLabel) ersetzen",role:.destructive) { onReplace(replaceLabel) }
        } message: {
            Text("Die bisherige aktive Zuordnung von Karte \(replaceLabel) wird beendet. Die neu eingesteckte bzw. formatierte Karte übernimmt diese Kennung. Importierte Originale und Archivfotos bleiben erhalten.")
        }
        .alert("Karte \(card.label ?? "") freigeben?",isPresented:$showRelease) {
            Button("Abbrechen",role:.cancel){}
            Button("Freigeben",role:.destructive){onRelease()}
        } message: {
            Text("Nur die aktive FTS-Zuordnung A–Z wird entfernt. Fotos auf der Karte und bereits importierte Originale bleiben erhalten.")
        }
    }
}

struct V140GreenScreenThumbnail: View {
    let item:V80MediaItem
    let event:EventRow?
    @State private var image:NSImage?
    @State private var refreshToken=0

    private var greenSettings:FTSGreenScreenSettings {
        guard let event else{return FTSGreenScreenSettings()}
        return FTSGreenScreenStore.settings(eventToken:event.event_token)
    }

    private var renderKey:String {
        [item.id,greenSettings.signature,String(refreshToken)].joined(separator:"|")
    }

    var body:some View {
        ZStack {
            Color.black.opacity(0.10)
            if let image {
                Image(nsImage:image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id:renderKey) {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for:.ftsGreenScreenSettingsDidChange)) { note in
            guard let token=note.object as? String,token==event?.event_token else{return}
            refreshToken += 1
        }
    }

    @MainActor private func refresh() async {
        guard let source=Self.thumbnailSource(path:item.importedPath) else {
            image=nil
            return
        }
        guard let event else {
            image=source
            return
        }
        let settings=greenSettings
        let rendered=FTSPhotoEffectsV132.processedImage(
            source:source,
            event:event,
            effect:.normal,
            greenScreenSettings:settings,
            cacheKey:item.importedPath+"|tile"
        )
        if !Task.isCancelled { image=rendered }
    }

    @MainActor private static func thumbnailSource(path:String,maxDimension:CGFloat=520)->NSImage? {
        guard let source=NSImage(contentsOfFile:path) else{return nil}
        let width=max(source.size.width,1)
        let height=max(source.size.height,1)
        let scale=min(1,maxDimension/max(width,height))
        let size=NSSize(width:max(1,width*scale),height:max(1,height*scale))
        let out=NSImage(size:size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in:NSRect(origin:.zero,size:size),from:.zero,operation:.copy,fraction:1)
        out.unlockFocus()
        return out
    }
}

struct V80MediaItemCell: View {
    let item:V80MediaItem
    let event:EventRow?
    let photoNumber:Int
    @Binding var quantity:Int
    let statusText:String
    let statusColor:Color
    let canSelect:Bool
    let onPreview:()->Void
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
            // Small work-area tiles are previews, not source files. When Green Screen
            // is active they show the selected replacement immediately; the immutable
            // camera original on disk is never modified.
            Button(action:onPreview) {
                ZStack(alignment:.bottomTrailing) {
                    V140GreenScreenThumbnail(item:item,event:event)
                        .frame(maxWidth:.infinity)
                        .frame(height:100)
                        .clipShape(RoundedRectangle(cornerRadius:7))
                    Image(systemName:"arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .padding(5)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(5)
                }
            }
            .buttonStyle(.plain)
            .help("Große Druckvorschau öffnen")
            Text("\(sourceTitle) · Foto \(String(format:"%03d",photoNumber))")
                .font(.caption.bold())
                .lineLimit(1)
            HStack(spacing:5) {
                Circle().fill(statusColor).frame(width:6,height:6)
                Text(statusText).font(.caption2.bold()).foregroundStyle(statusColor).lineLimit(1)
                Spacer()
                Text(item.originalName).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing:6) {
                if canSelect {
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
                } else {
                    Label("Nur Status",systemImage:"clock.arrow.circlepath")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if canSelect {
                    Button(role:.destructive){showHide=true} label:{
                        Image(systemName:"eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help("Aus Programm entfernen")
                }
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
    @State private var previewArchive:V80ArchiveRow?
    @State private var issuePickup:V80Pickup?
    @State private var archiveQuantities:[String:Int]=[:]

    var filtered:[V80Pickup] {
        let q=search.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if q.isEmpty{return core.pickups}
        return core.pickups.filter{$0.customer_code.uppercased().contains(q)}
    }

    var filteredArchive:[V80ArchiveRow] {
        let q=search.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if q.isEmpty{return core.archived}
        return core.archived.filter{
            $0.customer_code.uppercased().contains(q)
            || $0.kind.uppercased().contains(q)
            || ($0.source_type ?? "").uppercased().contains(q)
        }
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
                TextField("Abholcode / Archiv suchen",text:$search).textFieldStyle(.roundedBorder).frame(width:270)
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
                            Button("Fehldruck / Ersatz") {
                                issuePickup=p
                            }
                            .font(.caption)
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

                    VStack(alignment:.leading,spacing:8) {
                        HStack {
                            Label("Archiv / Abgegeben",systemImage:"archivebox.fill").font(.headline)
                            Spacer()
                            Text("\(filteredArchive.count) sichtbar").font(.caption).foregroundStyle(.secondary)
                        }

                        if !core.archiveStatus.isEmpty {
                            Text(core.archiveStatus).font(.caption).foregroundStyle(.green)
                        }

                        ForEach(filteredArchive.prefix(250)) { a in
                            HStack(spacing:10) {
                                Group {
                                    if let local=core.localArchivedPreviewPath(for:a),
                                       let image=NSImage(contentsOfFile:local) {
                                        Image(nsImage:image).resizable().scaledToFill()
                                    } else if let path=core.archivedServerPhoto(for:a)?.designed_path,
                                              let url=FTSAPI.shared.imageURL(storagePath:path) {
                                        AsyncImage(url:url) { phase in
                                            if case .success(let image)=phase { image.resizable().scaledToFill() }
                                            else { ZStack{Color.secondary.opacity(0.08);Image(systemName:"photo")} }
                                        }
                                    } else {
                                        ZStack{Color.secondary.opacity(0.08);Image(systemName:"photo")}
                                    }
                                }
                                .frame(width:58,height:72)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius:7))

                                VStack(alignment:.leading,spacing:3) {
                                    Text(a.customer_code).font(.headline.monospacedDigit())
                                    Text("\(a.kind) · \(a.quantity) ×" + (a.source_type.map{" · \($0)"} ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("Bezahlt / gedruckt / abgegeben · im Archiv")
                                        .font(.caption2).foregroundStyle(.green)
                                }
                                Spacer()
                                Button("Foto ansehen"){previewArchive=a}.font(.caption)
                                Picker("",selection:Binding(
                                    get:{archiveQuantities[a.id] ?? 1},
                                    set:{archiveQuantities[a.id]=max(1,min(20,$0))}
                                )) {
                                    ForEach(1...20,id:\.self){n in Text("\(n)×").tag(n)}
                                }
                                .labelsHidden()
                                .frame(width:64)
                                Button(core.archiveReprintActionsInFlight.contains(a.id) ? "Wird angelegt …" : "\(archiveQuantities[a.id] ?? 1)× nachdrucken") {
                                    Task{await core.reprintArchived(a,quantity:archiveQuantities[a.id] ?? 1,state:state)}
                                }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                                .disabled(core.archiveReprintActionsInFlight.contains(a.id))
                                if state.currentUser?.role=="printer_admin" {
                                    Button(core.archiveActionsInFlight.contains(a.id) ? "Wird entfernt …" : "Aus Liste entfernen",role:.destructive) {
                                        Task{await core.hideArchived(a,state:state)}
                                    }
                                    .font(.caption2)
                                    .disabled(core.archiveActionsInFlight.contains(a.id))
                                }
                            }
                            .padding(9)
                            .background(Color(nsColor:.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius:10))
                        }

                        if filteredArchive.isEmpty {
                            Text("Keine passenden Archivfotos.").foregroundStyle(.secondary).padding(.vertical,14)
                        }
                    }
                    .padding(.top,12)
                }.padding(6)
            }
        }.padding(8)
        .task{await core.refresh(state:state)}
        .sheet(item:$previewArchive) { row in
            V124ArchivePreviewSheet(row:row,state:state,core:core)
                .frame(minWidth:720,minHeight:620)
        }
        .sheet(item:$issuePickup) { pickup in
            V126PickupMisprintSheet(pickup:pickup,state:state,core:core)
                .frame(minWidth:760,minHeight:650)
        }
    }
}

struct V126PickupMisprintSheet:View {
    let pickup:V80Pickup
    @ObservedObject var state:AppState
    @ObservedObject var core:ProductionCore
    @Environment(\.dismiss) private var dismiss
    @State private var selfieCandidates:[V126SelfieMisprintCandidate]=[]
    @State private var selectedServerUnit=""
    @State private var selectedLocalUnit:UUID?
    @State private var selectedAdmin=""
    @State private var adminCode=""
    @State private var reason="COLOR_ERROR"
    @State private var note=""
    @State private var loading=true
    @State private var busy=false

    private let reasons:[(String,String)]=[
        ("COLOR_ERROR","Farben / Streifen fehlerhaft"),
        ("PAPER_JAM","Papierstau / hängen geblieben"),
        ("PARTIAL_PRINT","Foto nur teilweise gedruckt"),
        ("POWER_LOSS","Stromunterbrechung"),
        ("DAMAGED_PAPER","Papier / Foto beschädigt"),
        ("OTHER","Sonstiger Druckfehler")
    ]

    private var localJob:V80LocalPrintJob? {
        guard let id=UUID(uuidString:pickup.id) else{return nil}
        return core.localQueue.jobs.first(where:{$0.id==id})
    }

    private var localCandidates:[V80LocalPrintUnit] {
        localJob?.units.filter{$0.status == .printed} ?? []
    }

    private var selectedSelfie:V126SelfieMisprintCandidate? {
        selfieCandidates.first{$0.unit_id==selectedServerUnit}
    }

    private var selectedLocal:V80LocalPrintUnit? {
        localCandidates.first{$0.id==selectedLocalUnit}
    }

    @ViewBuilder private var preview:some View {
        if pickup.kind.uppercased()=="SELFIE",
           let path=selectedSelfie?.designed_path,
           let url=FTSAPI.shared.imageURL(storagePath:path) {
            AsyncImage(url:url) { phase in
                if case .success(let image)=phase { image.resizable().scaledToFit() }
                else { ZStack{Color.black.opacity(0.08);ProgressView()} }
            }
        } else if let jobID=UUID(uuidString:pickup.id),
                  let unitID=selectedLocalUnit,
                  let path=core.localIssuePreviewPath(jobID:jobID,unitID:unitID),
                  let image=NSImage(contentsOfFile:path) {
            Image(nsImage:image).resizable().scaledToFit()
        } else {
            ZStack {
                Color.black.opacity(0.08)
                Image(systemName:"photo").font(.system(size:42)).foregroundStyle(.secondary)
            }
        }
    }

    var body:some View {
        HStack(spacing:16) {
            preview
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius:12))

            VStack(alignment:.leading,spacing:12) {
                Text("Fehldruck / Ersatz · \(pickup.customer_code)").font(.title2.bold())
                Text("Nur verwenden, wenn ein physischer Ausdruck wirklich unbrauchbar ist. Der Kunde wird nicht erneut berechnet.")
                    .font(.caption).foregroundStyle(.secondary)

                if loading {
                    ProgressView("Ausdrucke werden geladen …")
                } else if pickup.kind.uppercased()=="SELFIE" {
                    Picker("Betroffenes Exemplar",selection:$selectedServerUnit) {
                        ForEach(selfieCandidates){c in
                            Text("Exemplar \(c.copy_index)" + (c.operator_name.map{" · \($0)"} ?? "")).tag(c.unit_id)
                        }
                    }
                } else {
                    Picker("Betroffenes Exemplar",selection:Binding(
                        get:{selectedLocalUnit},
                        set:{selectedLocalUnit=$0}
                    )) {
                        ForEach(localCandidates){u in
                            Text("Exemplar \(u.copyIndex) · \(u.originalName)").tag(Optional(u.id))
                        }
                    }
                }

                Picker("Grund",selection:$reason) {
                    ForEach(reasons,id:\.0){Text($0.1).tag($0.0)}
                }
                TextField("Notiz optional",text:$note).textFieldStyle(.roundedBorder)

                Button(busy ? "Wird gesendet …" : "📱 An Admin-Handy senden") {
                    sendToRemoteAdmin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !hasSelection)
                Text("Der Administrator kann diesen Fehldruck unterwegs prüfen und genau 1 Ersatz freigeben.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()
                Text("Oder Administrator direkt hier").font(.headline)
                Picker("Administrator",selection:$selectedAdmin) {
                    ForEach(state.deviceAdmins){a in Text(a.display_name).tag(a.user_id)}
                }
                SecureField("Administrator-Code",text:$adminCode).textFieldStyle(.roundedBorder)

                Spacer()
                HStack {
                    Button("Abbrechen",role:.cancel){dismiss()}
                    Spacer()
                    Button(busy ? "Wird angelegt …" : "Fehldruck bestätigen · 1× Ersatz") { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || selectedAdmin.isEmpty || adminCode.isEmpty || !hasSelection)
                }
            }
            .frame(width:350)
        }
        .padding(16)
        .task { await load() }
    }

    private var hasSelection:Bool {
        pickup.kind.uppercased()=="SELFIE" ? !selectedServerUnit.isEmpty : selectedLocalUnit != nil
    }

    private func load() async {
        if state.deviceAdmins.isEmpty { await state.loadDeviceAdmins() }
        if selectedAdmin.isEmpty {
            if state.currentUser?.role=="printer_admin",
               let own=state.currentUser?.user_id,
               state.deviceAdmins.contains(where:{$0.user_id==own}) {
                selectedAdmin=own
            } else {
                selectedAdmin=state.deviceAdmins.first?.user_id ?? ""
            }
        }

        if pickup.kind.uppercased()=="SELFIE" {
            selfieCandidates=await core.selfieMisprintCandidates(orderID:pickup.id,state:state)
            selectedServerUnit=selfieCandidates.first?.unit_id ?? ""
        } else {
            selectedLocalUnit=localCandidates.first?.id
        }
        loading=false
    }

    private func sendToRemoteAdmin() {
        guard !busy else{return}
        busy=true
        Task {
            let ok:Bool
            if pickup.kind.uppercased()=="SELFIE" {
                guard let unit=selectedSelfie else{busy=false;return}
                ok=await core.reportRemoteIssue(
                    targetKind:"SELFIE",targetUnitID:unit.unit_id,targetJobID:unit.order_id,
                    customerCode:pickup.customer_code,requestedResolution:"MISPRINT",
                    reasonCode:reason,note:note,state:state
                )
            } else {
                guard let jobID=UUID(uuidString:pickup.id),let unitID=selectedLocalUnit else{busy=false;return}
                ok=await core.reportRemoteIssue(
                    targetKind:"LOCAL",targetUnitID:unitID.uuidString,targetJobID:jobID.uuidString,
                    customerCode:pickup.customer_code,requestedResolution:"MISPRINT",
                    reasonCode:reason,note:note,state:state
                )
            }
            busy=false
            if ok { dismiss() }
        }
    }

    private func submit() {
        guard !busy else{return}
        busy=true
        Task {
            let ok:Bool
            if pickup.kind.uppercased()=="SELFIE" {
                guard let unit=selectedSelfie else{busy=false;return}
                ok=await core.adminResolveServerIssue(
                    unitID:unit.unit_id,resolution:"MISPRINT",reasonCode:reason,note:note,
                    adminUserID:selectedAdmin,adminCode:adminCode,state:state
                )
            } else {
                guard let jobID=UUID(uuidString:pickup.id),let unitID=selectedLocalUnit else{busy=false;return}
                ok=await core.adminResolveLocalMisprint(
                    jobID:jobID,unitID:unitID,reasonCode:reason,note:note,
                    adminUserID:selectedAdmin,adminCode:adminCode,state:state
                )
            }
            busy=false
            if ok { dismiss() }
        }
    }
}

struct V124ArchivePreviewSheet:View {
    let row:V80ArchiveRow
    @ObservedObject var state:AppState
    @ObservedObject var core:ProductionCore
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage:NSImage?
    @State private var digitalStatus="Digitalfoto wird vorbereitet …"
    @State private var digitalURL:URL?
    @State private var reprintQuantity=1

    private func prepareDigitalQR() async {
        do {
            let url:URL
            let name="FTS-Archiv-\(row.customer_code).jpg"
            if let local=core.localArchivedPreviewPath(for:row),
               let image=NSImage(contentsOfFile:local) {
                url=try await state.createDigitalLink(image:image,fileName:name)
            } else if let path=core.archivedServerPhoto(for:row)?.designed_path {
                let data=try await FTSAPI.shared.imageData(storagePath:path)
                url=try await state.createDigitalLink(jpegData:data,fileName:name)
            } else {
                throw NSError(domain:"FTSPrinter",code:254,userInfo:[NSLocalizedDescriptionKey:"Archivfoto ist nicht als Datei verfügbar."])
            }
            digitalURL=url
            qrImage=FTSQRCodeRenderer.image(for:url.absoluteString)
            digitalStatus="Scannen und digitales Foto herunterladen · Link 7 Tage gültig."
        } catch {
            qrImage=nil
            digitalURL=nil
            digitalStatus="QR derzeit nicht verfügbar: \(error.localizedDescription)"
        }
    }

    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:2) {
                    Text("Archivfoto \(row.customer_code)").font(.title2.bold())
                    Text("\(row.kind) · \(row.quantity) Ausdruck\(row.quantity==1 ? "" : "e") · bereits abgegeben")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen"){dismiss()}
            }

            Group {
                if let local=core.localArchivedPreviewPath(for:row),
                   let image=NSImage(contentsOfFile:local) {
                    Image(nsImage:image).resizable().scaledToFit()
                } else if let path=core.archivedServerPhoto(for:row)?.designed_path,
                          let url=FTSAPI.shared.imageURL(storagePath:path) {
                    AsyncImage(url:url) { phase in
                        switch phase {
                        case .empty: ZStack{Color.black.opacity(0.08);ProgressView()}
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure: ZStack{Color.black.opacity(0.08);Text("Archivbild konnte nicht geladen werden.").foregroundStyle(.orange)}
                        @unknown default: Color.black.opacity(0.08)
                        }
                    }
                } else {
                    ZStack {
                        Color.black.opacity(0.08)
                        VStack(spacing:8) {
                            Image(systemName:"archivebox").font(.system(size:40))
                            Text("Das Foto ist archiviert, aber die Bilddatei ist im aktuell geöffneten Tagesalbum nicht verfügbar.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }.padding()
                    }
                }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color.black.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius:12))

            GroupBox("Digitalfoto per QR") {
                HStack(spacing:12) {
                    if let qrImage {
                        Image(nsImage:qrImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width:112,height:112)
                            .padding(5)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius:8))
                    } else {
                        ZStack{RoundedRectangle(cornerRadius:8).fill(Color.secondary.opacity(0.08));ProgressView()}
                            .frame(width:122,height:122)
                    }
                    VStack(alignment:.leading,spacing:5) {
                        Text("Digital mitnehmen").font(.headline)
                        Text(digitalStatus).font(.caption).foregroundStyle(.secondary)
                        if digitalURL != nil {
                            Text("QR ist nur in dieser großen Ansicht sichtbar und niemals auf dem Ausdruck.")
                                .font(.caption2).foregroundStyle(.green)
                        }
                    }
                    Spacer()
                }
            }

            HStack {
                Text("Der Archiv-Eintrag bleibt unverändert. Ein Nachdruck wird als neuer Auftrag angelegt.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value:$reprintQuantity,in:1...20) {
                    Text("\(reprintQuantity)×").font(.headline.monospacedDigit())
                }
                .frame(width:120)
                Button(core.archiveReprintActionsInFlight.contains(row.id) ? "Wird angelegt …" : "\(reprintQuantity)× nachdrucken") {
                    Task{await core.reprintArchived(row,quantity:reprintQuantity,state:state)}
                }
                .buttonStyle(.borderedProminent)
                .disabled(core.archiveReprintActionsInFlight.contains(row.id))
            }
        }.padding(16)
        .task(id:row.id){await prepareDigitalQR()}
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
    let startRP108:()->Void
    let setCounts:(Int,Int,Int)->Void
    let resumeAfterChange:()->Void
    let coreBusyPaper:Bool
    let coreBusyFilm:Bool
    let coreBusyRP108:Bool
    let coreBusyManual:Bool
    @State private var confirmNewRP108=false
    @State private var showManualCounts=false
    @State private var manualRP108=108
    @State private var manualPaper=18
    @State private var manualFilm=54

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
                Text("RP-108: \(consumable?.rp108_remaining.map(String.init) ?? "nicht gestartet") / 108")
                    .font(.caption.bold())
                    .foregroundStyle((consumable?.rp108_remaining ?? 108) <= 10 ? Color.red : ((consumable?.rp108_remaining ?? 108) <= 20 ? Color.orange : Color.primary))
                Text("Papier: \(consumable?.paper_remaining.map(String.init) ?? "unbekannt") / 18")
                    .font(.caption)
                Text("Farbfilm: \(consumable?.film_remaining.map(String.init) ?? "unbekannt") / 54")
                    .font(.caption)
                Spacer()
                Button("Papier gewechselt · 18 neu",action:loadPaper)
                    .font(.caption)
                    .disabled(coreBusyPaper)
                Button("Farbfilm gewechselt · 54 neu",action:loadFilm)
                    .font(.caption)
                    .disabled(coreBusyFilm)
            }
            HStack(spacing:8) {
                Button("Neues RP-108 Set starten · 108") {
                    confirmNewRP108=true
                }
                .font(.caption.bold())
                .disabled(coreBusyRP108 || ["PREPARING","TRANSFER","PRINTING"].contains(slot.state) || slot.currentUnit != nil)

                Button("Restbestand ändern …") {
                    manualRP108=consumable?.rp108_remaining ?? 108
                    manualPaper=consumable?.paper_remaining ?? 18
                    manualFilm=consumable?.film_remaining ?? 54
                    showManualCounts=true
                }
                .font(.caption)
                .disabled(coreBusyManual || ["PREPARING","TRANSFER","PRINTING"].contains(slot.state) || slot.currentUnit != nil)
                .popover(isPresented:$showManualCounts) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Restbestand · \(slot.name)").font(.headline)
                        Text("Für ein angebrochenes Set, z. B. RP-108 direkt auf 102 setzen.")
                            .font(.caption).foregroundStyle(.secondary)
                        Stepper("RP-108: \(manualRP108) / 108",value:$manualRP108,in:0...108)
                        Stepper("Papier: \(manualPaper) / 18",value:$manualPaper,in:0...18)
                        Stepper("Farbfilm: \(manualFilm) / 54",value:$manualFilm,in:0...54)
                        HStack {
                            Button("Abbrechen"){showManualCounts=false}
                            Spacer()
                            Button("Übernehmen") {
                                setCounts(manualRP108,manualPaper,manualFilm)
                                showManualCounts=false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(width:340)
                }

                if let remaining=consumable?.rp108_remaining,remaining<=20 {
                    Text(remaining==0 ? "Set leer · neues Set einsetzen" : "Nur noch \(remaining) Prints im Set")
                        .font(.caption.bold())
                        .foregroundStyle(remaining<=10 ? .red : .orange)
                }
            }
            if slot.name.lowercased().contains("selphy") || slot.name.lowercased().contains("cp1500") {
                Label("SELPHY-Akku: Canon zeigt 1–4 Balken am Druckerdisplay. macOS/AirPrint liefert dafür keinen verlässlichen Akkuprozentwert.",systemImage:"battery.50")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if slot.state=="ERROR" || (consumable?.paper_remaining ?? 1) <= 0 || (consumable?.film_remaining ?? 1) <= 0 {
                Button("Material gewechselt · Weiterdrucken",action:resumeAfterChange)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(coreBusyPaper || coreBusyFilm)
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
        .confirmationDialog("Neues RP-108 Set starten?",isPresented:$confirmNewRP108) {
            Button("Ja · Zähler auf 108 neu starten",role:.destructive){startRP108()}
            Button("Abbrechen",role:.cancel){}
        } message: {
            Text("Nur drücken, wenn wirklich ein neues RP-108 Set eingelegt wurde. Der FTS-Setzähler startet bei 108; Papierfach bei 18 und Farbfilm bei 54.")
        }
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

                GroupBox("Stromversorgung Computer") {
                    VStack(alignment:.leading,spacing:6) {
                        FTSHostPowerView(status:core.hostPower)
                        if let warning=core.hostPowerWarning {
                            Label(warning,systemImage:"exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(core.hostPower.critical ? Color.red : Color.orange)
                        } else if core.hostPower.hasBattery && core.hostPower.onACPower {
                            Text("Laptop ist am Netzteil · Eventbetrieb abgesichert.")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }.padding(.vertical,5)
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
                                startRP108:{Task{await core.startRP108Set(printerName:p.name,state:state)}},
                                setCounts:{rp,paper,film in
                                    Task{await core.setMaterialCounts(printerName:p.name,rp108:rp,paper:paper,film:film,state:state)}
                                },
                                resumeAfterChange:{Task{await core.resumeAfterMaterialChange(printerName:p.name,state:state)}},
                                coreBusyPaper:core.consumableActionBusy(printerName:p.name,component:"PAPER_PACK"),
                                coreBusyFilm:core.consumableActionBusy(printerName:p.name,component:"FILM_CASSETTE"),
                                coreBusyRP108:core.rp108ActionBusy(printerName:p.name),
                                coreBusyManual:core.consumableActionBusy(printerName:p.name,component:"MANUAL_COUNTS")
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
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(30))
                await core.refreshHostPower()
            }
        }
    }
}
