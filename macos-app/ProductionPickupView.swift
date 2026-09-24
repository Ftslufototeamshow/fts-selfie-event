import SwiftUI

struct PickupOperationsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var core: ProductionCore
    @State private var search = ""

    private var shown: [V80Pickup] {
        let s=search.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if s.isEmpty { return core.pickups }
        return core.pickups.filter { $0.customer_code.uppercased().contains(s) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kundenabholung").font(.title2.bold())
                Spacer()
                TextField("Abholcode suchen", text: $search).frame(width: 260)
            }

            if shown.isEmpty {
                Text("Keine abholbereiten Fotos.")
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                List(shown) { p in
                    HStack {
                        Text(p.customer_code)
                            .font(.title3.bold().monospacedDigit())
                            .frame(width:100,alignment:.leading)

                        VStack(alignment:.leading) {
                            Text(p.kind == "SELFIE" ? "Selfie" : "Kamera / \(p.source_type ?? "lokal")")
                            Text("\(p.quantity) Foto\(p.quantity == 1 ? "" : "s") · \(p.event_title ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if p.kind == "SELFIE", p.receipt_number != nil,
                           let order=state.orders.first(where:{$0.order_id==p.id}) {
                            Button("Beleg für Kunden") {
                                Task { await state.showReceipt(order) }
                            }
                        }

                        Button("Foto abgeholt") {
                            Task { await core.markPickedUp(p, state: state) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(10)
    }
}

struct ArchiveOperationsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var core: ProductionCore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archiv").font(.title2.bold())

            Text("Kamera-/SD-Dateien bleiben lokal auf dem Event-Computer. Entfernen aus dieser Liste löscht nicht automatisch Belege oder Buchhaltungsdaten.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if core.archived.isEmpty {
                Text("Archiv ist leer.")
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                List(core.archived) { a in
                    HStack {
                        Text(a.customer_code)
                            .font(.headline.monospacedDigit())
                            .frame(width:100,alignment:.leading)

                        Text(a.kind == "SELFIE" ? "Selfie" : "Kamera / \(a.source_type ?? "lokal")")
                        Text("\(a.quantity) ×").foregroundStyle(.secondary)
                        Spacer()

                        if let receipt=a.receipt_number {
                            Text(receipt).font(.caption.monospaced())
                        }

                        if state.currentUser?.role == "printer_admin" {
                            Button("Aus Archiv entfernen", role: .destructive) {
                                Task { await core.hideArchived(a, state: state) }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}
