import SwiftUI
import AppKit

struct MediaOperationsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var core: ProductionCore
    @EnvironmentObject var media: MediaIngestV80
    let event: EventRow

    @State private var quantities: [String:Int] = [:]
    @State private var sourceFilter = "ALL"
    @State private var lastCreatedCode = ""

    private var sourceChoices: [String] {
        let s = Set(media.items.map { "\($0.sourceType):\($0.sourceLabel)" })
        return ["ALL"] + s.sorted()
    }

    private var shownItems: [V80MediaItem] {
        if sourceFilter == "ALL" { return Array(media.items.prefix(120)) }
        return Array(media.items.filter { "\($0.sourceType):\($0.sourceLabel)" == sourceFilter }.prefix(120))
    }

    private var selectedItems: [V80MediaItem] {
        media.items.filter { (quantities[$0.id] ?? 0) > 0 }
    }

    private var selectedSourceCount: Int {
        Set(selectedItems.map { "\($0.sourceType):\($0.sourceLabel)" }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SD-Karte / WLAN-Kamera").font(.title2.bold())
                    Text(media.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if media.activation == nil {
                    Button("Event-Album aktivieren") {
                        do {
                            try media.activate(event: event)
                            core.loadLocalQueue(folderPath: media.activation?.folderPath)
                        } catch {
                            core.lastError = error.localizedDescription
                        }
                    }.buttonStyle(.borderedProminent)
                } else {
                    Button("Eventordner") { media.revealEventFolder() }
                    Button("WLAN-Eingangsordner") { media.revealWLANFolder() }
                    Button("Jetzt prüfen") { Task { await media.scan(event: event) } }
                }
            }

            if media.activation != nil {
                if !media.detectedCards.isEmpty {
                    GroupBox("SD-Karten A / B / C / D") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(media.detectedCards) { card in
                                HStack {
                                    Text(card.volumeName).font(.headline)
                                    Text(card.marker.map { "Karte \($0.label)" } ?? "Unbekannte Karte")
                                        .foregroundStyle(card.marker == nil ? .orange : .secondary)
                                    Spacer()
                                    if card.marker == nil {
                                        ForEach(["A","B","C","D"], id:\.self) { letter in
                                            Button(letter) {
                                                Task { await media.register(card: card, label: letter, event: event) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                HStack {
                    Picker("Quelle", selection: $sourceFilter) {
                        ForEach(sourceChoices, id:\.self) { v in
                            Text(v == "ALL" ? "Alle Quellen" : v).tag(v)
                        }
                    }.frame(width: 260)

                    Spacer()

                    if !lastCreatedCode.isEmpty {
                        Text("Letzter Auftrag: \(lastCreatedCode)")
                            .font(.headline.monospacedDigit())
                    }

                    Button("GO · Zum Druck") { createJob() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedItems.isEmpty || selectedSourceCount != 1)
                }

                if selectedSourceCount > 1 {
                    Text("Für einen Auftrag bitte Fotos nur aus derselben Karte / WLAN-Quelle auswählen.")
                        .foregroundStyle(.orange)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(shownItems) { item in
                            MediaFunctionalTile(item: item, quantity: Binding(
                                get: { quantities[item.id] ?? 0 },
                                set: { quantities[item.id] = max(0, min(20, $0)) }
                            ))
                        }
                    }.padding(4)
                }
            }
        }.padding(10)
    }

    private func createJob() {
        let selected = selectedItems
        guard let first = selected.first, selectedSourceCount == 1 else { return }
        var dict:[V80MediaItem:Int]=[:]
        for m in selected { dict[m] = quantities[m.id] ?? 0 }
        Task {
            if let code = await core.createLocalJob(
                state: state,
                media: dict,
                sourceType: first.sourceType,
                sourceLabel: first.sourceLabel
            ) {
                lastCreatedCode = code
                for m in selected { quantities[m.id] = 0 }
                if core.autoDispatch { core.dispatchAvailable(state: state) }
            }
        }
    }
}

struct MediaFunctionalTile: View {
    let item: V80MediaItem
    @Binding var quantity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let im = NSImage(contentsOfFile: item.importedPath) {
                Image(nsImage: im)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.08))
            }
            Text("\(item.sourceLabel) · \(item.originalName)")
                .font(.caption.bold()).lineLimit(1)

            Stepper("Anzahl \(quantity)", value: $quantity, in: 0...20)
                .font(.caption)
        }
        .padding(8)
        .background(quantity > 0 ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
