import SwiftUI
import MarkdownUI
import ClawClient

struct MessageBubbleView: View {
    let message: Message
    /// Non-nil while a tool call is in progress for this message.
    let toolLabel: String?
    /// Author display name (e.g. assistant name or user name).
    var authorName: String? = nil
    /// Pre-resolved author avatar image.
    var authorImage: Image? = nil
    /// Accent color for assistant bubbles; nil falls back to secondary fill.
    var accentColor: Color? = nil
    /// Called when the user taps "Retry" on a failed user message.
    var onRetry: (() -> Void)? = nil
    /// API client for "Save to Memory" — nil disables the option.
    var api: APIClient? = nil
    /// If set, "Save to Memory" saves to this conversation's chat memory.
    var conversationId: String? = nil

    @State private var showTimestamp = false
    @State private var isSavingMemory = false
    @State private var memorySaved = false

    private var isUser: Bool { message.role == .user }
    private var isStreaming: Bool { message.status == .streaming }
    private var isError: Bool { message.status == .error }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 52)
            } else {
                avatarCircle
                Spacer().frame(width: 8)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Author name label
                if let name = authorName {
                    Text(name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                // Tool activity pill — shown above the content for assistant messages.
                if let toolLabel, !isUser {
                    ToolActivityView(label: toolLabel)
                }

                // Content or streaming placeholder.
                if !message.content.isEmpty || isError {
                    bubbleContent
                } else if isStreaming {
                    // Typing indicator while waiting for first delta.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .frame(width: 6, height: 6)
                                    .foregroundStyle(.secondary)
                                    .opacity(0.6)
                                    .scaleEffect(isStreaming ? 1 : 0.5)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(i) * 0.2),
                                        value: isStreaming
                                    )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(assistantBubbleFill)
                        )
                    }
                }

                // Inline retry button — shown below a failed user message.
                if isUser && isError, let onRetry {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 4)
                }

                // Timestamp — revealed by tapping the message row.
                if showTimestamp {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            // Cap width so long paragraphs don't span the full window on wide layouts.
            .frame(maxWidth: 700, alignment: isUser ? .trailing : .leading)

            if isUser {
                Spacer().frame(width: 8)
                avatarCircle
            } else {
                Spacer(minLength: 52)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(.easeInOut(duration: 0.15)) { showTimestamp.toggle() }
            }
        )
    }

    // MARK: - Avatar circle

    @ViewBuilder
    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(avatarBackground)
                .frame(width: 36, height: 36)
            if let image = authorImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                Text(monogram)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
    }

    private var monogram: String {
        guard let name = authorName, !name.isEmpty else { return "?" }
        return String(name.prefix(1)).uppercased()
    }

    private var avatarBackground: Color {
        if let accentColor, !isUser { return accentColor.opacity(0.8) }
        if isUser { return .accentColor }
        // Hash-based color for assistant monogram
        guard let name = authorName, !name.isEmpty else { return .secondary.opacity(0.5) }
        let hue = Double(abs(name.hashValue) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.7)
    }

    // MARK: - Bubble content

    @ViewBuilder
    private var bubbleContent: some View {
        textContent
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bubbleFill)
            )
            .foregroundStyle(foregroundColor)
            .contextMenu {
                if !message.content.isEmpty && !isError {
                    Button { copyToClipboard(message.content) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if let api {
                        Button {
                            Task { await saveToMemory(api: api) }
                        } label: {
                            if memorySaved {
                                Label("Saved to Memory", systemImage: "checkmark")
                            } else {
                                Label("Save to Memory", systemImage: "brain")
                            }
                        }
                        .disabled(isSavingMemory)
                    }
                }
                if isError, let errText = message.error, !errText.isEmpty {
                    Button { copyToClipboard(errText) } label: {
                        Label("Copy Error", systemImage: "doc.on.doc")
                    }
                }
                if isError, let onRetry {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    /// If the error is a rate limit, returns the date when the limit resets.
    private var rateLimitRetryDate: Date? {
        guard let error = message.error, error.hasPrefix("rate_limit:"),
              let ms = Double(error.dropFirst("rate_limit:".count))
        else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    @ViewBuilder
    private var textContent: some View {
        if isError, let retryDate = rateLimitRetryDate {
            VStack(alignment: .leading, spacing: 4) {
                Label("Rate limit reached", systemImage: "clock.badge.exclamationmark.fill")
                    .font(.subheadline.bold())
                Group {
                    if retryDate > Date() {
                        Text("Try again ") + Text(retryDate, style: .relative)
                    } else {
                        Text("You can try again now.")
                    }
                }
                .font(.caption)
            }
        } else if isError {
            VStack(alignment: .leading, spacing: 6) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                if let errText = message.error, !errText.isEmpty {
                    Text(errText)
                        .font(.caption.monospaced())
                        .lineLimit(10)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if message.status == .complete && !isUser {
            // Full block-level markdown rendering for assistant responses.
            Markdown(message.content)
                .markdownTheme(.chat)
                .markdownCodeSyntaxHighlighter(AppCodeSyntaxHighlighter.shared)
        } else if message.status == .complete {
            // User messages: render inline markdown (bold, italic, code) but
            // keep the single-line bubble layout.
            if let attributed = try? AttributedString(
                markdown: message.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
            } else {
                Text(message.content)
            }
        } else {
            Text(message.content)
        }
    }

    private var assistantBubbleFill: AnyShapeStyle {
        if let accentColor { return AnyShapeStyle(accentColor.opacity(0.15)) }
        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }

    private var bubbleFill: AnyShapeStyle {
        if isError { return AnyShapeStyle(Color.red.opacity(0.15)) }
        if isUser  { return AnyShapeStyle(Color.accentColor) }
        return assistantBubbleFill
    }

    private var foregroundColor: Color {
        if isError { return .red }
        if isUser  { return .white }
        return .primary
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func saveToMemory(api: APIClient) async {
        guard !message.content.isEmpty else { return }
        isSavingMemory = true
        if let convId = conversationId {
            _ = try? await api.addConversationMemory(conversationId: convId, content: message.content)
        } else {
            _ = try? await api.addMemory(content: message.content)
        }
        isSavingMemory = false
        memorySaved = true
        try? await Task.sleep(for: .seconds(2))
        memorySaved = false
    }
}
