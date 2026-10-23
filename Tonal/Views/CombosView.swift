import SwiftUI

struct CombosView: View {
    let googleId: String
    @State private var combos: [SavedCombo] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Can't Reach Tonal", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else if combos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No saved combos yet")
                            .foregroundStyle(.secondary)
                        Text("After analyzing an outfit, tap Save to keep it here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(combos) { combo in
                            ComboRow(combo: combo)
                        }
                        .onDelete(perform: deleteCombo)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Saved Combos")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            combos = try await APIService.fetchCombos(googleId: googleId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteCombo(at offsets: IndexSet) {
        let toDelete = offsets.map { combos[$0] }
        combos.remove(atOffsets: offsets)
        Task {
            do {
                for combo in toDelete {
                    try await APIService.deleteCombo(googleId: googleId, comboId: combo.id)
                }
            } catch {
                await load()
            }
        }
    }
}

struct ComboRow: View {
    let combo: SavedCombo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let rating = combo.rating {
                    Text("\(rating)/10")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                }
                Text(combo.occasion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedDate(combo.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(combo.verdict)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(combo.pieces.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let out = DateFormatter()
            out.dateStyle = .medium
            return out.string(from: d)
        }
        return iso
    }
}
