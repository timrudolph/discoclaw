import SwiftUI
import ClawClient

// MARK: - Cron description helper

/// Converts a 5-field cron expression into plain English.
private func cronDescription(_ expr: String) -> String {
    let parts = expr.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 5 else { return expr }
    let (min, hour, dom, month, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])

    func timeStr() -> String? {
        guard let h = Int(hour), let m = Int(min) else { return nil }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        guard let date = Calendar.current.date(from: comps) else { return nil }
        return date.formatted(.dateTime.hour().minute())
    }

    let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    if min.hasPrefix("*/"), let n = Int(min.dropFirst(2)), hour == "*", dom == "*", month == "*", dow == "*" {
        return "Every \(n) minute\(n == 1 ? "" : "s")"
    }
    if min == "0", hour == "*", dom == "*", month == "*", dow == "*" { return "Every hour" }
    if dom == "*", month == "*" {
        if let t = timeStr() {
            switch dow {
            case "*":   return "Daily at \(t)"
            case "1-5": return "Weekdays at \(t)"
            case "6-7", "0,6": return "Weekends at \(t)"
            default:
                if let d = Int(dow), d >= 0, d <= 6 { return "Every \(weekdayNames[d]) at \(t)" }
            }
        }
    }
    return expr
}

// MARK: - Schedule chip picker

private struct ScheduleChipPicker: View {
    @Binding var schedule: String

    private let presets: [(label: String, value: String)] = [
        ("Daily 9am",     "0 9 * * *"),
        ("Weekdays 9am",  "0 9 * * 1-5"),
        ("Mondays 9am",   "0 9 * * 1"),
        ("Every hour",    "0 * * * *"),
        ("Every 30 min",  "*/30 * * * *"),
    ]

    private var isCustom: Bool { !presets.map(\.value).contains(schedule) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.value) { preset in
                        chip(preset.label, active: schedule == preset.value) {
                            schedule = preset.value
                        }
                    }
                    chip("Custom", active: isCustom) {
                        if !isCustom { schedule = "" }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }

            if isCustom {
                TextField("minute hour day month weekday", text: $schedule)
                    .fontDesign(.monospaced)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.asciiCapable)
                    #endif
            }

            let desc = cronDescription(schedule)
            if !schedule.isEmpty {
                Label(desc == schedule ? "Custom schedule" : desc, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: Capsule())
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main list view

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
                    description: Text("Create a prompt that fires automatically on a schedule — daily briefings, weekly reviews, reminders.")
                )
            } else {
                List {
                    ForEach(jobs) { job in
                        CronJobRow(
                            job: job,
                            conversations: conversations,
                            onToggle: { Task { await toggle(job) } },
                            onDelete: { Task { await delete(job) } },
                            onEdit: { editingJob = job }
                        )
                    }
                }
                .listStyle(.inset)
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
            CronJobFormView(api: api, conversations: conversations, existingJob: nil) { newJob in
                jobs.append(newJob)
            }
        }
        .sheet(item: $editingJob) { job in
            CronJobFormView(api: api, conversations: conversations, existingJob: job) { updated in
                if let idx = jobs.firstIndex(where: { $0.id == updated.id }) {
                    jobs[idx] = updated
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { jobs = try await api.listCronJobs().jobs }
        catch { self.error = error.localizedDescription }
    }

    private func toggle(_ job: CronJob) async {
        do {
            let updated = try await api.updateCronJob(id: job.id, enabled: !job.enabled)
            if let idx = jobs.firstIndex(where: { $0.id == job.id }) { jobs[idx] = updated }
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ job: CronJob) async {
        do {
            try await api.deleteCronJob(id: job.id)
            jobs.removeAll { $0.id == job.id }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Row

private struct CronJobRow: View {
    let job: CronJob
    let conversations: [Conversation]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    private var conversationName: String {
        conversations.first(where: { $0.id == job.conversationId })?.title ?? "Unknown chat"
    }

    private var promptPreview: String {
        job.prompt
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? job.prompt
    }

    private var lastRunText: String {
        guard let ms = job.lastRunAt else { return "Never run" }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
            .formatted(.relative(presentation: .named))
    }

    var body: some View {
        HStack(spacing: 14) {
            // Clock icon badge
            ZStack {
                Circle()
                    .fill(job.enabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: job.enabled ? "clock.fill" : "clock")
                    .font(.system(size: 20))
                    .foregroundStyle(job.enabled ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.headline)
                    .foregroundStyle(job.enabled ? .primary : .secondary)

                Text(cronDescription(job.schedule))
                    .font(.subheadline)
                    .foregroundStyle(job.enabled ? .secondary : .tertiary)

                Text(promptPreview)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.caption2)
                    Text(conversationName)
                        .font(.caption)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(lastRunText)
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: .constant(job.enabled))
                .labelsHidden()
                .onTapGesture { onToggle() }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

// MARK: - Create / Edit form (unified)

struct CronJobFormView: View {
    let api: APIClient
    let conversations: [Conversation]
    let existingJob: CronJob?
    let onSaved: (CronJob) -> Void

    @State private var name: String
    @State private var schedule: String
    @State private var timezone: String
    @State private var prompt: String
    @State private var selectedConversationId: String
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { existingJob != nil }

    init(api: APIClient, conversations: [Conversation], existingJob: CronJob?, onSaved: @escaping (CronJob) -> Void) {
        self.api = api
        self.conversations = conversations
        self.existingJob = existingJob
        self.onSaved = onSaved
        _name     = State(initialValue: existingJob?.name     ?? "")
        _schedule = State(initialValue: existingJob?.schedule ?? "0 9 * * 1-5")
        _timezone = State(initialValue: existingJob?.timezone ?? TimeZone.current.identifier)
        _prompt   = State(initialValue: existingJob?.prompt   ?? "")
        _selectedConversationId = State(initialValue: existingJob?.conversationId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Name ──────────────────────────────────────────────────
                Section("Name") {
                    TextField("Daily standup, Weekly summary…", text: $name)
                }

                // ── Schedule ──────────────────────────────────────────────
                Section {
                    ScheduleChipPicker(schedule: $schedule)
                        .padding(.vertical, 4)
                    NavigationLink {
                        TimeZonePickerView(selected: $timezone)
                    } label: {
                        LabeledContent("Timezone", value: shortTimezone)
                    }
                } header: {
                    Text("Schedule")
                }

                // ── Prompt ────────────────────────────────────────────────
                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Prompt")
                } footer: {
                    Text("This text is sent to Claude on each scheduled run.")
                        .foregroundStyle(.secondary)
                }

                // ── Deliver to ────────────────────────────────────────────
                if !isEditing {
                    Section("Deliver to") {
                        Picker("Conversation", selection: $selectedConversationId) {
                            Text("Select…").tag("")
                            ForEach(conversations.filter { !$0.isArchived }) { conv in
                                Text(conv.title ?? "Untitled").tag(conv.id)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Scheduled Prompt" : "New Scheduled Prompt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(isEditing ? "Save" : "Create") { Task { await save() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSave)
                    }
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
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 540)
        #endif
    }

    private var shortTimezone: String {
        // Show just the city portion for readability
        timezone.components(separatedBy: "/").last ?? timezone
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isEditing || !selectedConversationId.isEmpty)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimName     = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimSchedule = schedule.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimPrompt   = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let job: CronJob
            if let existing = existingJob {
                job = try await api.updateCronJob(
                    id: existing.id, name: trimName,
                    schedule: trimSchedule, timezone: timezone, prompt: trimPrompt
                )
            } else {
                job = try await api.createCronJob(
                    name: trimName, schedule: trimSchedule, timezone: timezone,
                    prompt: trimPrompt, conversationId: selectedConversationId
                )
            }
            onSaved(job)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Timezone picker

/// Searchable, grouped-by-region timezone selector.
private struct TimeZonePickerView: View {
    @Binding var selected: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var sections: [(region: String, identifiers: [String])] {
        let filtered = searchText.isEmpty
            ? TimeZone.knownTimeZoneIdentifiers
            : TimeZone.knownTimeZoneIdentifiers.filter { $0.localizedCaseInsensitiveContains(searchText) }
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
                                Text(label.isEmpty ? tz : label).foregroundStyle(.primary)
                                Spacer()
                                if tz == selected {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
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
