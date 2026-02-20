# ClawClient App

SwiftUI source files for the native iOS/macOS client.
These are added directly to an Xcode app target that imports the `ClawClient` Swift Package.

## Xcode project setup

1. **Create a new app** — File → New → Project → App
   - Product name: `ClawClient`
   - Interface: SwiftUI, Language: Swift
   - Targets: iOS 17+ and/or macOS 14+

2. **Add the local package** — File → Add Package Dependencies
   - Click "Add Local…" and select the `client/` folder (this directory's parent)
   - Add `ClawClient` library to your app target

3. **Add these source files** to your app target
   - Select all files in `App/` recursively and add them to the target
   - Delete the placeholder `ContentView.swift` Xcode generated

4. **Set the entry point**
   - Delete the generated `<AppName>App.swift`
   - `ClawApp.swift` is already marked `@main`

5. **Build and run**
   - Make sure your server is running: `pnpm server` in the discoclaw directory
   - Launch the app — the onboarding screen will prompt for the server URL

## First run

On first launch you'll see the onboarding screen:
- **Server URL**: `http://<your-mac-ip>:4242` (use `127.0.0.1` for simulator/same machine)
- **Device name**: optional label (e.g. "iPhone 16")
- Tap **Register Device** — your token is stored in UserDefaults

To run on a physical iPhone, change `SERVER_HOST=0.0.0.0` in `.env` so the server
listens on all interfaces, then use your Mac's local IP address.

## File map

```
App/
  ClawApp.swift                    @main entry + root navigation
  AppContainer.swift               dependency container (db, api, repos, syncEngine)
  Views/
    OnboardingView.swift           first-run server URL + device registration
    ConversationListView.swift     sidebar — list of chats, swipe-to-delete, new chat button
    ChatView.swift                 message thread + compose bar
    MessageBubbleView.swift        individual message (user/assistant, streaming, error states)
    ComposeBarView.swift           multiline text input + send button
    ToolActivityView.swift         animated pill shown when Claude is using a tool
  ViewModels/
    ConversationListViewModel.swift  observes DB, calls API for create/delete
    ChatViewModel.swift              observes messages, handles optimistic send + streaming
```

## How streaming works (end to end)

1. User types and taps Send
2. `ChatViewModel.send()` inserts an optimistic user message in local SQLite
3. `POST /conversations/:id/messages` → server responds with `{ id, seq, assistantMessageId }`
4. `ChatViewModel` inserts a `status: .streaming` placeholder for the assistant message
5. Server invokes Claude Code; `SyncEngine` receives `message.delta` WebSocket events
6. `SyncEngine.applyEvent()` calls `MessageRepository.appendDelta()` on each delta
7. GRDB's `ValueObservation` fires → `ChatViewModel.messages` updates → `ChatView` re-renders
8. On `message.complete`, `finalize()` writes the authoritative full content
9. On `tool.start/end`, `SyncEngine.activeTools` updates → `MessageBubbleView` shows/hides the tool pill
