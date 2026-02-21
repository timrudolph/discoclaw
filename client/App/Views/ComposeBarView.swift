import SwiftUI
import UniformTypeIdentifiers

struct ComposeBarView: View {
    @Binding var text: String
    let isSending: Bool
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var showFileImporter = false
    @State private var attachError: String?
    @State private var attachments: [Attachment] = []

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            // Attachment chips — shown only when files are attached.
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments) { attachment in
                            AttachmentChipView(filename: attachment.filename) {
                                removeAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                Divider()
            }

            HStack(alignment: .bottom, spacing: 6) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)

                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .autocorrectionDisabled(false)
                    #endif
                    .onSubmit {
                        #if os(macOS)
                        // Shift+Return inserts a newline; plain Return sends.
                        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                            text += "\n"
                        } else if canSend {
                            onSend()
                        }
                        #endif
                    }

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.bar)
        // When the parent clears text after sending, also clear chips.
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty { attachments = [] }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.text, .sourceCode, .json, .commaSeparatedText, .xml, .data],
            allowsMultipleSelection: false
        ) { result in
            attachFile(result)
        }
        .alert("Could not read file", isPresented: Binding(
            get: { attachError != nil },
            set: { if !$0 { attachError = nil } }
        )) {
            Button("OK", role: .cancel) { attachError = nil }
        } message: {
            Text(attachError ?? "")
        }
    }

    // MARK: - Attachment handling

    private struct Attachment: Identifiable {
        let id = UUID()
        let filename: String
        let textBlock: String
    }

    private func attachFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            attachError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let filename = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                let lang = languageHint(ext)
                let block = "\n\n**\(filename)**\n```\(lang)\n\(content)\n```"
                text += block
                attachments.append(Attachment(filename: filename, textBlock: block))
            } catch {
                attachError = "Could not read \"\(url.lastPathComponent)\" as text: \(error.localizedDescription)"
            }
        }
    }

    private func removeAttachment(_ attachment: Attachment) {
        text = text.replacingOccurrences(of: attachment.textBlock, with: "")
        attachments.removeAll { $0.id == attachment.id }
    }

    private func languageHint(_ ext: String) -> String {
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx": return "javascript"
        case "py": return "python"
        case "sh", "bash", "zsh": return "bash"
        case "go": return "go"
        case "rs": return "rust"
        case "json": return "json"
        case "xml": return "xml"
        case "csv": return "csv"
        case "sql": return "sql"
        case "php": return "php"
        case "rb": return "ruby"
        case "java": return "java"
        case "kt": return "kotlin"
        case "css": return "css"
        case "html": return "html"
        case "md", "markdown": return "markdown"
        case "yaml", "yml": return "yaml"
        default: return ""
        }
    }
}

// MARK: - Chip view

private struct AttachmentChipView: View {
    let filename: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption2)
            Text(filename)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}
