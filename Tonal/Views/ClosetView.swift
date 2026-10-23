import SwiftUI

struct ClosetView: View {
    let googleId: String
    @State private var items: [ClosetItem] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var showAdd = false

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
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Your closet is empty")
                            .foregroundStyle(.secondary)
                        Text("Add key pieces and Tonal will use them as hints when analyzing your outfits.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).fontWeight(.medium)
                                HStack(spacing: 8) {
                                    if let type = item.type, !type.isEmpty {
                                        Text(type).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let color = item.color, !color.isEmpty {
                                        Text("· \(color)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let desc = item.description, !desc.isEmpty {
                                    Text(desc).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteItem)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("My Closet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showAdd) {
                AddClosetItemView(googleId: googleId) { await load() }
            }
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await APIService.fetchCloset(googleId: googleId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteItem(at offsets: IndexSet) {
        let toDelete = offsets.map { items[$0] }
        items.remove(atOffsets: offsets)
        Task {
            do {
                for item in toDelete {
                    try await APIService.deleteClosetItem(googleId: googleId, itemId: item.id)
                }
            } catch {
                await load()
            }
        }
    }
}

struct AddClosetItemView: View {
    let googleId: String
    let onSave: () async -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var type = ""
    @State private var color = ""
    @State private var description = ""
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name (e.g. White Oxford Shirt)", text: $name)
                    TextField("Type (e.g. Top, Pants, Shoes)", text: $type)
                    TextField("Color (e.g. Navy Blue)", text: $color)
                    TextField("Description (optional)", text: $description)
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Add to Closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            saving = true
                            saveError = nil
                            defer { saving = false }
                            do {
                                _ = try await APIService.addClosetItem(
                                    googleId: googleId,
                                    name: name, type: type,
                                    color: color, description: description
                                )
                                await onSave()
                                dismiss()
                            } catch {
                                saveError = "Couldn't save — \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(name.isEmpty || saving)
                }
            }
        }
    }
}
