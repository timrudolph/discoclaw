import SwiftUI
import ClawClient

struct BeadsListView: View {
    @Binding var selectedId: String?
    let api: APIClient
    @Binding var sidebarMode: SidebarMode
    @EnvironmentObject private var syncEngine: SyncEngine

    @State private var beads: [Bead] = []
    @State private var filter: String = "open"
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingCreate = false

    private static let filters: [(label: String, value: String)] = [
        ("Open",       "open"),
        ("Active",     "in_progress"),
        ("Blocked",    "blocked"),
        ("All",        "all"),
    ]

    var body: some View {
        List(beads, selection: $selectedId) { bead in
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                NavigationLink(value: PhoneNav(dest: .bead, id: bead.id)) {
                    BeadRow(bead: bead)
                }
            } else {
                BeadRow(bead: bead)
                    .tag(bead.id)
            }
            #else
            BeadRow(bead: bead)
                .tag(bead.id)
            #endif
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
        #if os(iOS)
        .navigationTitle(UIDevice.current.userInterfaceIdiom == .phone ? "" : "Beads")
        .navigationBarHidden(UIDevice.current.userInterfaceIdiom == .phone)
        #else
        .navigationTitle("Beads")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Label("New Bead", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 10) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Self.filters, id: \.value) { f in
                            Text(f.label).tag(f.value)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 4) {
                        // Chats tab — inactive
                        Button { sidebarMode = .chats } label: {
                            Label("Chats", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        // Beads tab — active
                        Button {} label: {
                            Label("Beads", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.bar)
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if beads.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Beads",
                    systemImage: "checkmark.circle",
                    description: Text(filter == "all" ? "No tasks found." : "No \(filter.replacingOccurrences(of: "_", with: " ")) tasks.")
                )
            }
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .sheet(isPresented: $showingCreate) {
            BeadCreateView(api: api) { newBead in
                beads.insert(newBead, at: 0)
                selectedId = newBead.id
            }
        }
        .task(id: filter) { await load() }
        .onChange(of: syncEngine.beadsVersion) { Task { await load() } }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.listBeads(status: filter)
            beads = response.beads
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Row

private struct BeadRow: View {
    let bead: Bead

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(bead.statusEmoji)
                    .font(.caption)
                Text(bead.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if !bead.displayPriority.isEmpty {
                    Text(bead.displayPriority)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
            HStack(spacing: 4) {
                Text(bead.id)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let labels = bead.labels, !labels.isEmpty {
                    let tagLabels = labels.filter { $0.hasPrefix("tag:") }.map { String($0.dropFirst(4)) }
                    ForEach(tagLabels.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
