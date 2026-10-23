import SwiftUI

struct LogView: View {
    let googleId: String
    @State private var logs: [OutfitLog] = []
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
                } else if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.xmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No outfit history yet")
                            .foregroundStyle(.secondary)
                        Text("After analyzing an outfit, tap Log to record it.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(log.occasion.isEmpty ? "Casual" : log.occasion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formattedDate(log.date))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(log.pieces.joined(separator: " · "))
                                .font(.subheadline)
                                .lineLimit(2)
                            if !log.notes.isEmpty {
                                Text(log.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Outfit History")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            logs = try await APIService.fetchLogs(googleId: googleId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
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
