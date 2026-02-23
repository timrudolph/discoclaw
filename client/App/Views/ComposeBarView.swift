import SwiftUI
import UniformTypeIdentifiers

// MARK: - Auto-expanding editor

/// Preference key used by the hidden sizer Text to report its height.
private struct ComposeMeasuredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A TextEditor that expands to fit its content without the lag that
/// TextField(axis: .vertical) has on macOS for soft-wrapped lines.
///
/// How it works: a hidden Text view (which measures wrap height correctly and
/// immediately) sits in the background and reports its height via a
/// PreferenceKey. The TextEditor is then sized to match.
private struct GrowingTextEditor: View {
    @Binding var text: String
    var placeholder: String = "Message"
    var maxLines: Int = 8
    /// Called when Return is pressed without Shift (macOS only). Always
    /// prevents the newline from being inserted; caller decides whether to send.
    var onReturnKey: (() -> Void)? = nil

    @State private var editorHeight: CGFloat = 28

    // macOS body font line height ~18pt; TextEditor internal inset ~4pt top+bottom → 26pt.
    // iOS body font line height ~22pt; TextEditor internal inset ~8pt top+bottom → 38pt.
    #if os(macOS)
    private let minHeight: CGFloat = 26
    private let vPadding: CGFloat = 4
    private let lineHeight: CGFloat = 20
    #else
    private let minHeight: CGFloat = 38
    private let vPadding: CGFloat = 8
    private let lineHeight: CGFloat = 22
    #endif
    private var maxHeight: CGFloat { CGFloat(maxLines) * lineHeight + vPadding * 2 }

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            #if os(macOS)
            .padding(.vertical, vPadding)
            #endif
            .frame(height: editorHeight)
            #if os(macOS)
            .onKeyPress(.return) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return .ignored }
                onReturnKey?()
                return .handled
            }
            #endif
            // Hidden Text in the background measures the true wrap height.
            // fixedSize(vertical: true) lets it grow beyond the background's bounds
            // so GeometryReader captures the actual required height.
            .background(alignment: .topLeading) {
                Text(text.isEmpty ? " " : text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, vPadding)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ComposeMeasuredHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .hidden()
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .padding(.top, vPadding)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(ComposeMeasuredHeightKey.self) { height in
                let clamped = min(max(height, minHeight), maxHeight)
                if abs(clamped - editorHeight) > 0.5 {
                    editorHeight = clamped
                }
            }
    }
}

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

                GrowingTextEditor(
                    text: $text,
                    onReturnKey: { if canSend { onSend() } }
                )
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
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
