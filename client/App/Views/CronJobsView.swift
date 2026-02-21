import SwiftUI
import ClawClient

struct CronJobsView: View {
    let api: APIClient
    let conversations: [Conversation]

    @State private var jobs: [CronJob] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingCreate = false
    @State private var editingJob: CronJob?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if jobs.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Prompts",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Tap + to create a scheduled prompt that fires Claude on a cron schedule.")
                )
            } else {
                List {
                    ForEach(jobs) { job in
                        CronJobRow(job: job,
                            onToggle: { Task { await toggle(job) } },
                            onDelete: { Task { await delete(job) } },
                            onEdit: { editingJob = job }
                        )
                    }
                }
            }
        }
        .navigationTitle("Scheduled Prompts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $showingCreate) {
            CronJobCreateView(api: api, conversations: conversations) { newJob in
                jobs.append(newJob)
            }
        }
        .sheet(item: $editingJob) { job in
            CronJobEditView(api: api, job: job, conversations: conversations) { updated in
                if let idx = jobs.firstIndex(where: { $0.id == updated.id }) {
                    jobs[idx] = updated
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            jobs = try await api.listCronJobs().jobs
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func toggle(_ job: CronJob) async {
        do {
            let updated = try await api.updateCronJob(id: job.id, enabled: !job.enabled)
            if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ job: CronJob) async {
        do {
            try await api.deleteCronJob(id: job.id)
            jobs.removeAll { $0.id == job.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct CronJobRow: View {
    let job: CronJob
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    private var lastRunText: String {
        guard let ms = job.lastRunAt else { return "Never" }
        return Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.relative(presentation: .named))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.enabled ? "clock.fill" : "clock")
                .font(.title3)
                .foregroundStyle(job.enabled ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.headline)
                    .foregroundStyle(job.enabled ? .primary : .secondary)
                Text(job.schedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
                Text("Last run: \(lastRunText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: .constant(job.enabled))
                .labelsHidden()
                .onTapGesture { onToggle() }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Create

struct CronJobCreateView: View {
    let api: APIClient
    let conversations: [Conversation]
    let onCreate: (CronJob) -> Void

    @State private var name = ""
    @State private var schedule = "0 9 * * 1-5"
    @State private var timezone = TimeZone.current.identifier
    @State private var prompt = ""
    @State private var selectedConversationId: String = ""
    @State private var isCreating = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    // Common schedule presets
    private let presets: [(label: String, value: String)] = [
        ("Daily 9am",      "0 9 * * *"),
        ("Weekdays 9am",   "0 9 * * 1-5"),
        ("Every Monday",   "0 9 * * 1"),
        ("Every hour",     "0 * * * *"),
        ("Every 30 min",   "*/30 * * * *"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Daily standup, Weekly summary…", text: $name)
                }

                Section {
                    Picker("Schedule", selection: $schedule) {
                        ForEach(presets, id: \.value) { p in
                            Text(p.label).tag(p.value)
                        }
                        Text("Custom").tag(schedule)
                    }
                    TextField("Cron expression", text: $schedule)
                        .fontDesign(.monospaced)
                        .autocorrectionDisabled()
                    NavigationLink {
                        TimeZonePickerView(selected: $timezone)
                    } label: {
                        LabeledContent("Timezone", value: timezone)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Format: minute hour day month weekday (e.g. \"0 9 * * 1-5\" = weekdays at 9am)")
                        .font(.caption)
                }

                Section("Prompt") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 80)
                }

                Section("Deliver to") {
                    Picker("Conversation", selection: $selectedConversationId) {
                        Text("Select…").tag("")
                        ForEach(conversations.filter { !$0.isArchived }) { conv in
                            Text(conv.title ?? "Untitled").tag(conv.id)
                        }
                    }
                }
            }
            .navigationTitle("New Scheduled Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!canCreate || isCreating)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
        .onAppear {
            if selectedConversationId.isEmpty {
                selectedConversationId = conversations.first(where: { !$0.isArchived })?.id ?? ""
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedConversationId.isEmpty
    }

    private func create() async {
        isCreating = true
        do {
            let job = try await api.createCronJob(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: timezone,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                conversationId: selectedConversationId
            )
            onCreate(job)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Edit

struct CronJobEditView: View {
    let api: APIClient
    let job: CronJob
    let conversations: [Conversation]
    let onSaved: (CronJob) -> Void

    @State private var name: String
    @State private var schedule: String
    @State private var timezone: String
    @State private var prompt: String
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private let presets: [(label: String, value: String)] = [
        ("Daily 9am",      "0 9 * * *"),
        ("Weekdays 9am",   "0 9 * * 1-5"),
        ("Every Monday",   "0 9 * * 1"),
        ("Every hour",     "0 * * * *"),
        ("Every 30 min",   "*/30 * * * *"),
    ]

    init(api: APIClient, job: CronJob, conversations: [Conversation], onSaved: @escaping (CronJob) -> Void) {
        self.api = api
        self.job = job
        self.conversations = conversations
        self.onSaved = onSaved
        _name = State(initialValue: job.name)
        _schedule = State(initialValue: job.schedule)
        _timezone = State(initialValue: job.timezone)
        _prompt = State(initialValue: job.prompt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                }
                Section {
                    Picker("Schedule", selection: $schedule) {
                        ForEach(presets, id: \.value) { p in
                            Text(p.label).tag(p.value)
                        }
                        Text("Custom").tag(schedule)
                    }
                    TextField("Cron expression", text: $schedule)
                        .fontDesign(.monospaced)
                        .autocorrectionDisabled()
                    NavigationLink {
                        TimeZonePickerView(selected: $timezone)
                    } label: {
                        LabeledContent("Timezone", value: timezone)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Format: minute hour day month weekday")
                        .font(.caption)
                }
                Section("Prompt") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Scheduled Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        isSaving = true
        do {
            let updated = try await api.updateCronJob(
                id: job.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: timezone,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Timezone picker

/// Searchable, grouped-by-region timezone selector.
/// Presented via NavigationLink inside a Form's NavigationStack.
private struct TimeZonePickerView: View {
    @Binding var selected: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var allIdentifiers: [String] { TimeZone.knownTimeZoneIdentifiers }

    private var sections: [(region: String, identifiers: [String])] {
        let filtered = searchText.isEmpty
            ? allIdentifiers
            : allIdentifiers.filter { $0.localizedCaseInsensitiveContains(searchText) }

        var groups: [String: [String]] = [:]
        for tz in filtered {
            let region = tz.components(separatedBy: "/").first ?? "Other"
            groups[region, default: []].append(tz)
        }
        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.region) { region, identifiers in
                Section(region) {
                    ForEach(identifiers, id: \.self) { tz in
                        let label = tz.components(separatedBy: "/").dropFirst().joined(separator: "/")
                        Button {
                            selected = tz
                            dismiss()
                        } label: {
                            HStack {
                                Text(label.isEmpty ? tz : label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if tz == selected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search timezones")
        .navigationTitle("Timezone")
    }
}
