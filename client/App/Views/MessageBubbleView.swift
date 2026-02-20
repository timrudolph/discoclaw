import SwiftUI
import MarkdownUI
import ClawClient

struct MessageBubbleView: View {
    let message: Message
    /// Non-nil while a tool call is in progress for this message.
    let toolLabel: String?

    @State private var showTimestamp = false

    private var isUser: Bool { message.role == .user }
    private var isStreaming: Bool { message.status == .streaming }
    private var isError: Bool { message.status == .error }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 52) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Tool activity pill — shown above the bubble for assistant messages.
                if let toolLabel, !isUser {
                    ToolActivityView(label: toolLabel)
                }

                // Bubble or streaming placeholder.
                if !message.content.isEmpty || isError {
                    bubbleContent
                } else if isStreaming {
                    // Empty bubble while waiting for first delta.
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
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            if !isUser { Spacer(minLength: 52) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(.easeInOut(duration: 0.15)) { showTimestamp.toggle() }
            }
        )
    }

    @ViewBuilder
    private var bubbleContent: some View {
        textContent
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contextMenu {
                if !message.content.isEmpty && !isError {
                    Button {
                        copyToClipboard(message.content)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
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
            Label(message.error ?? "Unknown error", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
        } else if message.status == .complete && !isUser {
            // Full block-level markdown rendering for assistant responses.
            Markdown(message.content)
                .markdownTheme(.gitHub)
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

    private var backgroundColor: Color {
        if isError { return Color.red.opacity(0.1) }
        return isUser ? Color.accentColor : Color.secondary.opacity(0.12)
    }

    private var foregroundColor: Color {
        if isError { return .red }
        return isUser ? .white : .primary
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
