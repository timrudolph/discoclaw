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

// MARK: - Schedule picker

private struct ScheduleChipPicker: View {
    @Binding var schedule: String

    private enum RepeatMode: String, CaseIterable, Identifiable {
        case daily    = "Daily"
        case weekdays = "Weekdays"
        case weekends = "Weekends"
        case weekly   = "Weekly"
        case hourly   = "Hourly"
        case interval = "Interval"
        case custom   = "Custom"
        var id: String { rawValue }
    }

    @State private var mode: RepeatMode
    @State private var timeDate: Date
    @State private var weekday: Int
    @State private var intervalMinutes: Int

    private let weekdayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    private let intervalOptions = [5, 10, 15, 20, 30, 45, 60]

    init(schedule: Binding<String>) {
        _schedule = schedule
        let (m, t, d, i) = Self.parse(schedule.wrappedValue)
        _mode            = State(initialValue: m)
        _timeDate        = State(initialValue: t)
        _weekday         = State(initialValue: d)
        _intervalMinutes = State(initialValue: i)
    }

    var body: some View {
        Group {
            Picker("Repeat", selection: $mode) {
                ForEach(RepeatMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .onChange(of: mode) { _, _ in rebuildCron() }

            if mode == .weekly {
                Picker("Day", selection: $weekday) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(weekdayNames[d]).tag(d)
                    }
                }
                .onChange(of: weekday) { _, _ in rebuildCron() }
            }

            if [.daily, .weekdays, .weekends, .weekly].contains(mode) {
                DatePicker("Time", selection: $timeDate, displayedComponents: .hourAndMinute)
                    .onChange(of: timeDate) { _, _ in rebuildCron() }
            }

            if mode == .interval {
                Picker("Every", selection: $intervalMinutes) {
                    ForEach(intervalOptions, id: \.self) { n in
                        Text(n < 60 ? "\(n) minutes" : "1 hour").tag(n)
                    }
                }
                .onChange(of: intervalMinutes) { _, _ in rebuildCron() }
            }

            if mode == .custom {
                TextField("minute hour day month weekday", text: $schedule)
                    .fontDesign(.monospaced)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.asciiCapable)
                    #endif
            }
        }
    }

    // MARK: Parse cron → state

    private static func parse(_ expr: String) -> (RepeatMode, Date, Int, Int) {
        var c = DateComponents(); c.hour = 9; c.minute = 0
        let nine = Calendar.current.date(from: c) ?? Date()

        let parts = expr.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else { return (.custom, nine, 1, 30) }
        let (min, hour, dom, month, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])
        guard dom == "*", month == "*" else { return (.custom, nine, 1, 30) }

        if min.hasPrefix("*/"), let n = Int(min.dropFirst(2)), hour == "*", dow == "*" {
            let snapped = [5,10,15,20,30,45,60].contains(n) ? n : 30
            return (.interval, nine, 1, snapped)
        }
        if min == "0", hour == "*", dow == "*" { return (.hourly, nine, 1, 30) }

        guard let h = Int(hour), let m = Int(min) else { return (.custom, nine, 1, 30) }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        let t = Calendar.current.date(from: comps) ?? nine

        switch dow {
        case "*":    return (.daily,    t, 1, 30)
        case "1-5":  return (.weekdays, t, 1, 30)
        case "0,6":  return (.weekends, t, 1, 30)
        default:
            if let d = Int(dow), d >= 0, d <= 6 { return (.weekly, t, d, 30) }
            return (.custom, t, 1, 30)
        }
    }

    // MARK: State → cron

    private func rebuildCron() {
        guard mode != .custom else { return }
        let cal = Calendar.current
        let h = cal.component(.hour, from: timeDate)
        let m = cal.component(.minute, from: timeDate)
        switch mode {
        case .daily:    schedule = "\(m) \(h) * * *"
        case .weekdays: schedule = "\(m) \(h) * * 1-5"
        case .weekends: schedule = "\(m) \(h) * * 0,6"
        case .weekly:   schedule = "\(m) \(h) * * \(weekday)"
        case .hourly:   schedule = "0 * * * *"
        case .interval: schedule = "*/\(intervalMinutes) * * * *"
        case .custom:   break
        }
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
        .overlay {
            if isLoading {
                ProgressView("Loading…")
            } else if jobs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Scheduled Prompts")
                        .font(.headline)
                    Text(error ?? "No jobs found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await reload() } }) {
            CronJobFormView(api: api, conversations: conversations, existingJob: nil) { _ in }
        }
        .sheet(item: $editingJob, onDismiss: { Task { await reload() } }) { job in
            CronJobFormView(api: api, conversations: conversations, existingJob: job) { _ in }
        }
        .task { await load() }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { jobs = try await api.listCronJobs().jobs }
        catch { self.error = error.localizedDescription }
    }

    /// Silent refresh — updates the list without showing the loading spinner.
    private func reload() async {
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
        HStack(alignment: .top, spacing: 12) {
            // Text area — tap opens editor
            VStack(alignment: .leading, spacing: 5) {
                Text(job.name)
                    .font(.headline)

                Label(cronDescription(job.schedule), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(job.enabled ? Color.accentColor : Color.secondary)

                Text(promptPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Label(conversationName, systemImage: "bubble.left.fill")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(lastRunText)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            // Toggle is its own hit target — doesn't bleed into the row tap
            Toggle("", isOn: Binding(get: { job.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
        .opacity(job.enabled ? 1 : 0.5)
        .contextMenu {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
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
                            .buttonStyle(.glassProminent)
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
