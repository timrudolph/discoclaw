import SwiftUI
import ClawClient

struct MemoryView: View {
    let api: APIClient

    @State private var items: [MemoryListResponse.MemoryItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var newItemText = ""
    @State private var isAdding = false
    @State private var deleting: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack {
                            TextField("Add a memory…", text: $newItemText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await addItem() } }
                            Button {
                                Task { await addItem() }
                            } label: {
                                if isAdding {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                }
                            }
                            .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
                        }
                    }

                    Section {
                        if items.isEmpty {
                            Text("No memory items yet.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(items) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.content)
                                            .font(.subheadline)
                                        Text(Date(timeIntervalSince1970: Double(item.createdAt) / 1000),
                                             style: .date)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if deleting == item.id {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Button {
                                            Task { await deleteItem(item) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    }
                }
            }
        }
        .navigationTitle("Memory")
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            let response = try await api.listMemory()
            items = response.items
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addItem() async {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isAdding = true
        do {
            _ = try await api.addMemory(content: text)
            newItemText = ""
            let response = try await api.listMemory()
            items = response.items
        } catch {
            self.error = error.localizedDescription
        }
        isAdding = false
    }

    private func deleteItem(_ item: MemoryListResponse.MemoryItem) async {
        deleting = item.id
        do {
            try await api.deleteMemory(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
        deleting = nil
    }
}
