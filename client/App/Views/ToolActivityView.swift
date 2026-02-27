import SwiftUI

/// Small pill shown inline in the chat when Claude is running a tool.
struct ToolActivityView: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}
