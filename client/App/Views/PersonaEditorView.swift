import SwiftUI
import PhotosUI
import ClawClient

/// Edits the per-conversation identity files (SOUL.md / IDENTITY.md / USER.md)
/// plus the assistant's display name, photo, and accent color.
/// Presented as a sheet from the chat toolbar.
struct PersonaEditorView: View {
    let api: APIClient
    let conversationId: String
    /// Pass in the current conversation so fields are pre-populated immediately.
    let conversation: Conversation?

    @Environment(\.dismiss) private var dismiss

    // Visual identity
    @State private var assistantDisplayName: String = ""
    @State private var accentColor: Color = .accentColor
    @State private var hasCustomAccent = false

    // Photo picking
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarImage: Image? = nil
    @State private var isUploadingPhoto = false
    @State private var photoError: String?

    // Persona text
    @State private var soul: String = ""
    @State private var identity: String = ""
    @State private var userBio: String = ""

    @State private var isLoadingFiles = true
    @State private var isSaving = false
    @State private var savedRecently = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                // ─── Visual Identity ─────────────────────────────────────
                Section {
                    HStack(spacing: 14) {
                        // Avatar preview + pick button
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            avatarPreview
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Assistant name", text: $assistantDisplayName)
                                .font(.body)

                            HStack(spacing: 8) {
                                ColorPicker("Accent", selection: $accentColor, supportsOpacity: false)
                                    .labelsHidden()
                                    .onChange(of: accentColor) { _, _ in hasCustomAccent = true }

                                Text("Accent color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if hasCustomAccent {
                                    Button("Reset") {
                                        hasCustomAccent = false
                                        accentColor = .accentColor
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if isUploadingPhoto {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Uploading photo…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let photoError {
                        Text(photoError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Name and photo shown in the chat header and message bubbles.")
                        .foregroundStyle(.secondary)
                }

                // ─── Persona text sections ────────────────────────────────
                if isLoadingFiles {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                } else {
                    section(
                        title: "SOUL.md",
                        subtitle: "Who the assistant fundamentally is — personality, values, essence.",
                        text: $soul
                    )
                    section(
                        title: "IDENTITY.md",
                        subtitle: "Name, vibe, and style for this chat.",
                        text: $identity
                    )
                    section(
                        title: "USER.md",
                        subtitle: "Context about who you are and what you're working on.",
                        text: $userBio
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Chat Identity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else if savedRecently {
                        Label("Saved", systemImage: "checkmark")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else {
                        Button("Save") { Task { await save() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await uploadPhoto(item) }
            }
            .onAppear { Task { await loadFilesFromAPI() } }
        }
    }

    // MARK: - Avatar preview

    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(hasCustomAccent ? accentColor.opacity(0.8) : Color.secondary.opacity(0.3))
                .frame(width: 56, height: 56)
            if let avatarImage {
                avatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .overlay(
            Circle()
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Section builder

    @ViewBuilder
    private func section(title: String, subtitle: String, text: Binding<String>) -> some View {
        Section {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
        } header: {
            Text(title)
        } footer: {
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func loadFilesFromAPI() async {
        // Pre-fill visual identity from the conversation model immediately (no wait)
        assistantDisplayName = conversation?.assistantName ?? ""
        if let hexColor = conversation?.accentSwiftUIColor {
            accentColor = hexColor
            hasCustomAccent = true
        }
        // Load identity files and avatar concurrently
        async let soulFile:     WorkspaceFileResponse? = try? api.getConversationWorkspaceFile(conversationId: conversationId, name: "SOUL.md")
        async let identityFile: WorkspaceFileResponse? = try? api.getConversationWorkspaceFile(conversationId: conversationId, name: "IDENTITY.md")
        async let userFile:     WorkspaceFileResponse? = try? api.getConversationWorkspaceFile(conversationId: conversationId, name: "USER.md")
        async let avatarData:   Data?                  = try? api.fetchAssistantAvatar(conversationId: conversationId)
        let (s, i, u, a) = await (soulFile, identityFile, userFile, avatarData)
        soul     = s?.content ?? ""
        identity = i?.content ?? ""
        userBio  = u?.content ?? ""
        if let data = a { avatarImage = imageFromData(data) }
        isLoadingFiles = false
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingPhoto = true
        photoError = nil
        defer { isUploadingPhoto = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            photoError = "Could not load image data."
            return
        }
        guard let jpeg = compressToJPEG(data, maxSize: CGSize(width: 512, height: 512)) else {
            photoError = "Could not process image."
            return
        }
        do {
            try await api.uploadAssistantAvatar(conversationId: conversationId, jpeg)
            avatarImage = imageFromData(jpeg)
        } catch {
            photoError = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            // Save identity files via workspace file API
            let writes: [(String, String)] = [
                ("SOUL.md", soul),
                ("IDENTITY.md", identity),
                ("USER.md", userBio),
            ]
            for (name, content) in writes {
                try await api.updateConversationWorkspaceFile(
                    conversationId: conversationId, name: name, content: content
                )
            }
            // Save name + accent color
            let nameToSave: String?? = assistantDisplayName.isEmpty ? .some(nil) : .some(assistantDisplayName)
            let colorToSave: String?? = hasCustomAccent ? .some(accentColor.hexString) : .some(nil)
            _ = try await api.updateConversation(
                id: conversationId,
                assistantName: nameToSave,
                accentColor: colorToSave
            )
            savedRecently = true
            try? await Task.sleep(for: .seconds(1.5))
            savedRecently = false
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func imageFromData(_ data: Data) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #endif
    }

    private func compressToJPEG(_ data: Data, maxSize: CGSize) -> Data? {
        #if os(iOS)
        guard let src = UIImage(data: data) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: maxSize)
        let resized = renderer.image { _ in
            src.draw(in: CGRect(origin: .zero, size: maxSize))
        }
        return resized.jpegData(compressionQuality: 0.82)
        #else
        guard let src = NSImage(data: data) else { return nil }
        let resized = NSImage(size: maxSize)
        resized.lockFocus()
        src.draw(
            in: NSRect(origin: .zero, size: maxSize),
            from: NSRect(origin: .zero, size: src.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }
        return jpeg
        #endif
    }
}

// MARK: - Color hex helper

private extension Color {
    var hexString: String {
        #if os(iOS)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        guard let ci = NSColor(self).usingColorSpace(.sRGB) else { return "#808080" }
        let r = ci.redComponent
        let g = ci.greenComponent
        let b = ci.blueComponent
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
