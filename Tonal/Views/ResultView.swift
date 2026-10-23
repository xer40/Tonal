import SwiftUI

struct ResultView: View {
    let analysis: OutfitAnalysis
    let occasion: String
    let weather: WeatherData
    let googleId: String

    @Environment(\.dismiss) var dismiss
    @State private var saved = false
    @State private var logged = false
    @State private var saving = false
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Rating + Verdict ──────────────────────────────
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(ratingColor.opacity(0.2), lineWidth: 6)
                                .frame(width: 72, height: 72)
                            Circle()
                                .trim(from: 0, to: CGFloat(analysis.rating) / 10)
                                .stroke(ratingColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 72, height: 72)
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(analysis.rating)")
                                    .font(.system(size: 26, weight: .bold))
                                Text("/10")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(analysis.verdict)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    // ── Wear This ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wear This")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(analysis.pieces, id: \.self) { piece in
                                Text(piece)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    // ── Quick Notes ───────────────────────────────────
                    VStack(spacing: 0) {
                        noteRow(icon: "🎨", text: analysis.colorAnalysis)
                        Divider().padding(.leading, 36)
                        noteRow(icon: "🌡️", text: analysis.weatherCheck)
                        Divider().padding(.leading, 36)
                        noteRow(icon: "📍", text: analysis.occasionFit)
                        Divider().padding(.leading, 36)
                        noteRow(icon: "✨", text: analysis.elevationTip)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    // ── Rain Alert ────────────────────────────────────
                    if analysis.rainAlert {
                        Label("Rain likely — bring an umbrella or jacket", systemImage: "cloud.rain.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                    }

                    // ── Action Buttons ────────────────────────────────
                    HStack(spacing: 12) {
                        Button {
                            Task { await saveCombo() }
                        } label: {
                            Label(saved ? "Saved" : "Save", systemImage: saved ? "heart.fill" : "heart")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(saved ? Color.pink : Color.primary, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(Color(UIColor.systemBackground))
                        }
                        .disabled(saved || saving)

                        Button {
                            Task { await logOutfit() }
                        } label: {
                            Label(logged ? "Logged" : "Log", systemImage: logged ? "checkmark" : "clock")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.primary)
                        }
                        .disabled(logged || saving)
                    }

                    if let actionError {
                        Label(actionError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle("Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    func noteRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon).font(.body)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var ratingColor: Color {
        switch analysis.rating {
        case 8...10: return .green
        case 6...7: return .yellow
        default: return .orange
        }
    }

    func saveCombo() async {
        saving = true
        defer { saving = false }
        actionError = nil
        do {
            _ = try await APIService.saveCombo(googleId: googleId, analysis: analysis, occasion: occasion, weather: weather)
            saved = true
        } catch {
            actionError = "Couldn't save — \(error.localizedDescription)"
        }
    }

    func logOutfit() async {
        saving = true
        defer { saving = false }
        actionError = nil
        do {
            try await APIService.logOutfit(googleId: googleId, analysis: analysis, occasion: occasion, weather: weather)
            logged = true
        } catch {
            actionError = "Couldn't log — \(error.localizedDescription)"
        }
    }
}

// ── Flow Layout for piece chips ───────────────────────────────────────────────
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0, +)
            + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        let maxWidth = proposal.width ?? 0
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x + w > maxWidth && !rows.last!.isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += w + spacing
        }
        return rows
    }
}
