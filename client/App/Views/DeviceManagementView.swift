import SwiftUI
import ClawClient

struct DeviceManagementView: View {
    let api: APIClient

    @Environment(\.dismiss) private var dismiss
    @State private var devices: [DeviceListResponse.DeviceItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var revoking: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2).foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if devices.isEmpty {
                    ContentUnavailableView(
                        "No Devices",
                        systemImage: "laptopcomputer.and.iphone",
                        description: Text("Registered devices appear here. You can revoke access for any device you no longer use.")
                    )
                } else {
                    List(devices) { device in
                        DeviceRow(device: device, isRevoking: revoking == device.id) {
                            Task { await revoke(device) }
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            devices = try await api.listDevices().devices
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func revoke(_ device: DeviceListResponse.DeviceItem) async {
        revoking = device.id
        do {
            try await api.revokeDevice(id: device.id)
            devices.removeAll { $0.id == device.id }
        } catch {
            self.error = error.localizedDescription
        }
        revoking = nil
    }
}

private struct DeviceRow: View {
    let device: DeviceListResponse.DeviceItem
    let isRevoking: Bool
    let onRevoke: () -> Void

    private var platformIcon: String {
        switch device.platform?.lowercased() {
        case "ios":   return "iphone"
        case "macos": return "laptopcomputer"
        default:      return "desktopcomputer"
        }
    }

    private var lastSeenText: String {
        guard let ms = device.lastSeen else { return "Never seen" }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
            .formatted(.relative(presentation: .named))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: platformIcon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name ?? "Unknown Device")
                        .font(.headline)
                    if device.isCurrent {
                        Text("This device")
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                Text("Last seen \(lastSeenText)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !device.isCurrent {
                if isRevoking {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button("Revoke", role: .destructive, action: onRevoke)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
