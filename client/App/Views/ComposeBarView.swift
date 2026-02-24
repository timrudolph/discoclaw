import SwiftUI
import UniformTypeIdentifiers

// MARK: - Auto-expanding editor

/// A TextEditor that starts at one line and expands to fit its content.
///
/// Height is driven by measuring the text with NSAttributedString.boundingRect
/// on every change, which is synchronous and reliable on both platforms.
private struct GrowingTextEditor: View {
    @Binding var text: String
    var placeholder: String = "Message"
    var maxLines: Int = 8
    /// Called when Return is pressed without Shift (macOS only).
    var onReturnKey: (() -> Void)? = nil

    @State private var editorHeight: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    // macOS: vPadding is added via .padding(.vertical) on TextEditor so the
    //        cursor sits centred in the box (NSTextView has no built-in inset).
    // iOS:   UITextView already has 8 pt top+bottom textContainerInset, so we
    //        don't add extra padding — but we DO account for it in height math.
    #if os(macOS)
    private let vPadding: CGFloat = 4
    private let hInset:   CGFloat = 5   // NSTextView lineFragmentPadding default
    private let fallback: CGFloat = 28  // 1-line fallback before geometry fires
    #else
    private let vPadding: CGFloat = 8
    private let hInset:   CGFloat = 5
    private let fallback: CGFloat = 38
    #endif

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            #if os(macOS)
            .padding(.vertical, vPadding)
            .onKeyPress(.return) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return .ignored }
                onReturnKey?()
                return .handled
            }
            #endif
            .frame(height: editorHeight > 0 ? editorHeight : fallback)
            // GeometryReader in background captures the real container width.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            containerWidth = geo.size.width
                            updateHeight()
                        }
                        .onChange(of: geo.size.width) { _, w in
                            containerWidth = w
                            updateHeight()
                        }
                }
            }
            .onChange(of: text) { updateHeight() }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, hInset)
                        .padding(.top, vPadding)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Recompute editorHeight using NSAttributedString metrics so the result is
    /// always synchronous with the text change (no layout-pass dependency).
    private func updateHeight() {
        guard containerWidth > 0 else { return }

        let str = text.isEmpty ? " " : text
        let w = max(containerWidth - hInset * 2, 1)

        #if os(macOS)
        let f = NSFont.preferredFont(forTextStyle: .body)
        #else
        let f = UIFont.preferredFont(forTextStyle: .body)
        #endif
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        #if os(macOS)
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        #else
        let opts: NSStringDrawingOptions = [.usesLineFragmentOrigin]
        #endif
        let bounds = CGSize(width: w, height: 1_000_000)

        let oneH  = ceil((" " as NSString).boundingRect(with: bounds, options: opts, attributes: attrs, context: nil).height)
        let rawH  = ceil((str  as NSString).boundingRect(with: bounds, options: opts, attributes: attrs, context: nil).height)

        let minH = oneH + vPadding * 2
        let maxH = oneH * CGFloat(maxLines) + vPadding * 2
        let newH = min(max(rawH + vPadding * 2, minH), maxH)

        if abs(newH - editorHeight) > 0.5 { editorHeight = newH }
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
