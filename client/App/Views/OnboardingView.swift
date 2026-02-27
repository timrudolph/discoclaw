import SwiftUI
import ClawClient

struct OnboardingView: View {
    let onComplete: (SessionConfig) -> Void

    @State private var serverURL = "http://localhost:4242"
    @State private var setupToken = ""
    @State private var deviceName = ""
    @State private var isRegistering = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Connect to ClawServer")
                    .font(.title2.bold())
                Text("Enter your server address and setup token.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                SecureField("Setup token", text: $setupToken)
                    .textFieldStyle(.roundedBorder)

                TextField("Device name (optional)", text: $deviceName)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await register() }
            } label: {
                HStack {
                    if isRegistering { ProgressView().scaleEffect(0.8) }
                    Text(isRegistering ? "Registering…" : "Register Device")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isRegistering || serverURL.isEmpty || setupToken.isEmpty)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 400)
    }

    private func register() async {
        isRegistering = true
        errorMessage = nil
        defer { isRegistering = false }

        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid server URL."
            return
        }

        do {
            guard let url = URL(string: "/auth/register", relativeTo: base)?.absoluteURL else {
                errorMessage = "Could not build registration URL."
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = InitialRegisterRequest(
                name: deviceName.isEmpty ? nil : deviceName,
                platform: platformName,
                setupToken: setupToken
            )
            req.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                errorMessage = msg ?? "Server returned \(http.statusCode)."
                return
            }

            let result = try JSONDecoder().decode(RegisterResponse.self, from: data)
            let session = SessionConfig(
                serverURL: base,
                token: result.token,
                userId: result.userId,
                deviceId: result.deviceId
            )
            onComplete(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var platformName: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }
}
