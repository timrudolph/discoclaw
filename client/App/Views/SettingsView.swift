import SwiftUI
import ClawClient

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "auto"

    private var session: SessionConfig? { SessionConfig.load() }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $appearance) {
                    Text("System").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            if let session {
                Section("Server") {
                    LabeledContent("URL", value: session.serverURL.absoluteString)
                    LabeledContent("Device ID", value: session.deviceId)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 480)
        .padding(.vertical, 8)
    }
}
