import SwiftUI
import UniformTypeIdentifiers

struct ComposeBarView: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    @State private var showFileImporter = false
    @State private var attachError: String?

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
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
                    if canSend { onSend() }
                    #endif
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
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
            } catch {
                attachError = "Could not read \"\(url.lastPathComponent)\" as text: \(error.localizedDescription)"
            }
        }
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
