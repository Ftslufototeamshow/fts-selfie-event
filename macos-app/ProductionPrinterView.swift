import SwiftUI
import AppKit

struct ProductionOpsRoot: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var core: ProductionCore
    @EnvironmentObject var media: MediaIngestV80
    let event: EventRow

    @State private var tab = 0
    @State private var showUpdatePrompt = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Druckzentrale") { tab = 0 }
                Button("SD / WLAN") { tab = 1 }
                Button("Kundenabholung \(core.pickups.count)") { tab = 2 }
                Button("Archiv") { tab = 3 }
                Spacer()
                if core.updateAvailable {
                    Button("Update verfügbar") { showUpdatePrompt = true }
                }
            }.padding(.horizontal, 8)

            Divider()

            Group {
                switch tab {
                case 1: MediaOperationsView(event: event)
                case 2: PickupOperationsView()
                case 3: ArchiveOperationsView()
                default: PrinterOperationsView()
                }
            }
        }
        .task(id: event.event_token) {
            media.load(event: event)
            core.loadLocalQueue(folderPath: media.activation?.folderPath)
            core.discoverPrinters()
            await core.checkUpdate(platform: "macos")
            if core.updateAvailable { showUpdatePrompt = true }

            while !Task.isCancelled {
                if media.activation != nil {
                    await media.scan(event: event)
                    core.loadLocalQueue(folderPath: media.activation?.folderPath)
                }
                await state.refreshSelected()
                await core.refresh(state: state)
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .alert("Neue FTS Printer Version verfügbar", isPresented: $showUpdatePrompt) {
            if core.updateRelease?.mandatory == true {
                Button("Jetzt aktualisieren") { beginUpdate() }
            } else {
                Button("Jetzt aktualisieren") { beginUpdate() }
                Button("Später", role: .cancel) {}
            }
        } message: {
            Text(updateMessage)
        }
    }

    private var updateMessage: String {
        guard let r = core.updateRelease else { return "Eine neue Version ist verfügbar." }
        let notes = (r.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "Installiert: Build \(ProductionCore.build)\nNeu: \(r.version) · Build \(r.build_number)" +
            (notes.isEmpty ? "" : "\n\n\(notes)")
    }

    private func beginUpdate() {
        let busy = core.printerSlots.contains { ["PREPARING","TRANSFER","PRINTING"].contains($0.state) }
        if busy {
            core.lastError = "Update wartet: Mindestens ein Drucker arbeitet noch."
            return
        }
        Task {
            if let file = await core.downloadUpdate() {
                NSWorkspace.shared.open(file)
            }
        }
    }
}

struct PrinterOperationsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var core: ProductionCore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Drucker").font(.title2.bold())
                    Spacer()
                    Toggle("Automatisch verteilen", isOn: Binding(
                        get: { core.autoDispatch },
                        set: {
                            core.autoDispatch = $0
                            UserDefaults.standard.set($0, forKey: "fts.autodispatch.v80")
                            if $0 { core.dispatchAvailable(state: state) }
                        }
                    )).toggleStyle(.switch)
                    Button("Drucker neu erkennen") { core.discoverPrinters() }
                }

                if core.printerSlots.isEmpty {
                    Text("Noch kein macOS-Drucker installiert oder erkannt.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(core.printerSlots) { p in
                        PrinterFunctionalRow(slot: p)
                    }
                }

                Divider()

                HStack {
                    Text("Warteschlange").font(.title2.bold())
                    Spacer()
                    Text(core.queueStatus).foregroundStyle(.secondary)
                    Button("Jetzt aktualisieren") { Task { await core.refresh(state: state) } }
                }

                let uncertain = core.workUnits.filter { $0.unit_status == "UNCERTAIN" }
                if !uncertain.isEmpty {
                    GroupBox("Prüfen – nicht automatisch nachdrucken") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(uncertain) { unit in
                                HStack {
                                    Text("Selfie \(unit.pickup_code) · Exemplar \(unit.copy_index)/\(unit.item_quantity)")
                                    Spacer()
                                    Text(unit.last_error ?? "Druckstatus unklar").foregroundStyle(.orange)
                                    Button("Sicher NICHT gedruckt → erneut") {
                                        Task { await core.requeueServerUnit(unit, state: state, confirmedNotPrinted: true) }
                                    }
                                }
                            }
                        }
                    }
                }

                ForEach(core.workUnits) { unit in
                    HStack(spacing: 12) {
                        Text(unit.pickup_code).font(.headline.monospacedDigit()).frame(width: 90, alignment: .leading)
                        Text("Selfie · Exemplar \(unit.copy_index)/\(unit.item_quantity)")
                        Spacer()
                        Text(unit.printer_key ?? "—").foregroundStyle(.secondary)
                        QueueStatusBadge(status: unit.unit_status)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(core.localQueue.jobs.filter { $0.status != .archived && $0.status != .cancelled }) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(job.customerCode).font(.headline.monospacedDigit())
                            Text("\(job.sourceType) · \(job.sourceLabel)").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(job.units.filter{$0.status == .printed}.count)/\(job.units.count) fertig")
                            QueueStatusBadge(status: job.status.rawValue.uppercased())
                            if job.status == .waiting {
                                Button("Stornieren") { Task { await core.cancelLocalJob(job, state: state) } }
                            }
                        }

                        ForEach(job.units.filter{$0.status == .uncertain}) { u in
                            HStack {
                                Text("\(u.originalName) · Exemplar \(u.copyIndex)")
                                Spacer()
                                Text(u.lastError ?? "Druckstatus unklar").foregroundStyle(.orange)
                                Button("Sicher NICHT gedruckt → erneut") {
                                    core.requeueLocalUnit(jobID: job.id, unitID: u.id, confirmedNotPrinted: true)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }.padding(10)
        }
        .alert("FTS Printer", isPresented: Binding(
            get: { core.lastError != nil },
            set: { if !$0 { core.lastError = nil } }
        )) {
            Button("OK") { core.lastError = nil }
        } message: {
            Text(core.lastError ?? "")
        }
    }
}

struct PrinterFunctionalRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var core: ProductionCore
    let slot: LocalPrinterSlot

    var consumable: V81Consumable? { core.consumable(for: slot.name) }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { core.printerSlots.first(where:{$0.name == slot.name})?.enabled ?? false },
                set: { core.setPrinter(slot.name, enabled: $0) }
            )).labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(slot.name).font(.headline)
                HStack(spacing: 10) {
                    Text(slot.state)
                    if slot.state == "PRINTING" {
                        Text("ca. \(slot.eta) Sek.").monospacedDigit()
                    }
                    if let e = slot.lastError { Text(e).foregroundStyle(.orange) }
                }.font(.caption)

                HStack(spacing: 12) {
                    Text("Papier: \(componentText(consumable?.paper_remaining, max: 18))")
                    Text("Farbfilm: \(componentText(consumable?.film_remaining, max: 54))")
                }.font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("18 Blatt eingesetzt") {
                Task { await core.loadConsumable(printerName: slot.name, component: "PAPER_PACK", state: state) }
            }
            Button("Farbfilm eingesetzt") {
                Task { await core.loadConsumable(printerName: slot.name, component: "FILM_CASSETTE", state: state) }
            }
            if slot.state == "ERROR" {
                Button("Fehler geprüft") { core.clearPrinterError(slot.name) }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func componentText(_ value:Int?, max:Int) -> String {
        guard let value else { return "unbekannt" }
        return "\(value)/\(max)"
    }
}

struct QueueStatusBadge: View {
    let status:String
    var body: some View {
        Text(status.replacingOccurrences(of:"_",with:" "))
            .font(.caption.bold())
            .padding(.horizontal,8).padding(.vertical,4)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status.uppercased() {
        case "PRINTED","READYFORPICKUP","READY_FOR_PICKUP": return .green.opacity(0.18)
        case "PRINTING","TRANSFER","CLAIMED": return .blue.opacity(0.16)
        case "UNCERTAIN","ERROR","FAILED": return .orange.opacity(0.18)
        default: return .gray.opacity(0.14)
        }
    }
}
