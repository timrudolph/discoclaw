import SwiftUI
import ClawClient

struct BeadDetailView: View {
    let beadId: String
    let api: APIClient
    let onUpdated: (Bead) -> Void

    @State private var bead: Bead?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingClose = false
    @State private var closeReason = ""
    @State private var isClosing = false
    @State private var showingEdit = false
    @State private var newLabel = ""
    @State private var isAddingLabel = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let bead {
                ScrollView {
                  GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(bead.statusEmoji)
                                    .font(.title2)
                                Text(bead.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .glassEffect(.regular, in: .capsule)
                                Spacer()
                                if !bead.displayPriority.isEmpty {
                                    Text(bead.displayPriority)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .glassEffect(.regular.tint(.orange), in: .capsule)
                                }
                            }
                            Text(bead.title)
                                .font(.title2.bold())
                        }

                        Divider()

                        // Status picker
                        if bead.status != "closed" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Status")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Status", selection: Binding(
                                    get: { bead.status },
                                    set: { newStatus in Task { await changeStatus(to: newStatus) } }
                                )) {
                                    Text("🟢 Open").tag("open")
                                    Text("🟡 In Progress").tag("in_progress")
                                    Text("⚠️ Blocked").tag("blocked")
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // Description
                        if let desc = bead.description, !desc.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(desc)
                                    .font(.body)
                            }
                        }

                        // Metadata
                        VStack(alignment: .leading, spacing: 8) {
                            if let owner = bead.owner {
                                LabeledValue(label: "Owner", value: owner)
                            }
                            if let created = bead.createdAt {
                                LabeledValue(label: "Created", value: created)
                            }
                            if let updated = bead.updatedAt {
                                LabeledValue(label: "Updated", value: updated)
                            }
                            if bead.status == "closed", let closed = bead.closedAt {
                                LabeledValue(label: "Closed", value: closed)
                            }
                            if let reason = bead.closeReason, !reason.isEmpty {
                                LabeledValue(label: "Close reason", value: reason)
                            }
                        }

                        // Labels
                        labelsSection(for: bead)

                        // Close button
                        if bead.status != "closed" {
                            Divider()
                            Button(role: .destructive) {
                                showingClose = true
                            } label: {
                                Label("Close Bead", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .tint(.red)
                        }
                    }
                    .padding()
                  }
                }
            } else if error != nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(bead?.title ?? "Bead")
        .toolbar {
            if let bead, bead.status != "closed" {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
        }
        .alert("Close Bead", isPresented: $showingClose) {
            TextField("Reason (optional)", text: $closeReason)
            Button("Close", role: .destructive) {
                Task { await close() }
            }
            Button("Cancel", role: .cancel) { closeReason = "" }
        } message: {
            Text("Mark this bead as closed?")
        }
        .sheet(isPresented: $showingEdit) {
            if let bead {
                BeadEditView(bead: bead, api: api) { updated in
                    self.bead = updated
                    onUpdated(updated)
                }
            }
        }
        .task(id: beadId) { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            bead = try await api.getBead(id: beadId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func changeStatus(to newStatus: String) async {
        guard let current = bead else { return }
        do {
            if let updated = try await api.updateBead(id: current.id, status: newStatus) {
                bead = updated
                onUpdated(updated)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addLabel() async {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let current = bead else { return }
        isAddingLabel = true
        do {
            let updated = try await api.addBeadLabel(id: current.id, label: trimmed)
            bead = updated
            onUpdated(updated)
            newLabel = ""
        } catch {
            self.error = error.localizedDescription
        }
        isAddingLabel = false
    }

    private func close() async {
        guard let current = bead else { return }
        isClosing = true
        do {
            if let closed = try await api.closeBead(id: current.id, reason: closeReason.isEmpty ? nil : closeReason) {
                bead = closed
                onUpdated(closed)
            }
        } catch {
            self.error = error.localizedDescription
        }
        closeReason = ""
        isClosing = false
    }

    @ViewBuilder
    private func labelsSection(for bead: Bead) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Labels")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let labels = bead.labels, !labels.isEmpty {
                GlassEffectContainer {
                    FlowLayout(labels) { label in
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            if bead.status != "closed" {
                HStack(spacing: 6) {
                    TextField("Add label…", text: $newLabel)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await addLabel() } }
                    Button {
                        Task { await addLabel() }
                    } label: {
                        Image(systemName: isAddingLabel ? "arrow.triangle.2.circlepath" : "plus.circle")
                    }
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingLabel)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Edit sheet

struct BeadEditView: View {
    let bead: Bead
    let api: APIClient
    let onSaved: (Bead) -> Void

    @State private var title: String
    @State private var description: String
    @State private var priority: String
    @State private var owner: String
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(bead: Bead, api: APIClient, onSaved: @escaping (Bead) -> Void) {
        self.bead = bead
        self.api = api
        self.onSaved = onSaved
        _title = State(initialValue: bead.title)
        _description = State(initialValue: bead.description ?? "")
        _priority = State(initialValue: bead.priority.map(String.init) ?? "")
        _owner = State(initialValue: bead.owner ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
                Section("Priority") {
                    TextField("1–5 (lower = higher priority)", text: $priority)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Section("Owner") {
                    TextField("Optional", text: $owner)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Bead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func save() async {
        isSaving = true
        do {
            let p = Int(priority)
            if let updated = try await api.updateBead(
                id: bead.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.isEmpty ? nil : description,
                priority: p,
                owner: owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : owner.trimmingCharacters(in: .whitespacesAndNewlines)
            ) {
                onSaved(updated)
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Create sheet

struct BeadCreateView: View {
    let api: APIClient
    let onCreate: (Bead) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var priority = ""
    @State private var owner = ""
    @State private var isCreating = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("What needs to be done?", text: $title)
                }
                Section("Description (optional)") {
                    TextEditor(text: $description)
                        .frame(minHeight: 60)
                }
                Section("Priority (optional)") {
                    TextField("1–5", text: $priority)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Section("Owner (optional)") {
                    TextField("Who's responsible?", text: $owner)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New Bead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func create() async {
        isCreating = true
        do {
            let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
            let bead = try await api.createBead(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.isEmpty ? nil : description,
                priority: Int(priority),
                owner: trimmedOwner.isEmpty ? nil : trimmedOwner
            )
            onCreate(bead)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Helpers

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
        }
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        // Simple wrapping row layout using lazy HStack fallback
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), alignment: .leading)], alignment: .leading) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
    }
}
