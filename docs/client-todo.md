# ClawApp Client — Feature Backlog

Audited 2026-02-20. Items ordered by priority within each tier.

---

## High Priority — Noticeable missing features

- [x] **1. Connection status indicator** — `SyncEngine.isConnected` is `@Published` but never shown. Users get no feedback when the WebSocket drops mid-stream. Show a dot or banner in `ChatView`/`ConversationListView`.

- [x] **2. Last message preview in conversation list** — `ConversationListItem.lastMessage` exists in the DTO but `ConversationRow` never renders it. Every chat app shows this subtitle.

- [x] **3. Stop/cancel generation button** — No way to interrupt a running Claude response. Needs a server `DELETE /conversations/:id/messages/:id/cancel` (or similar) endpoint plus a button in `ChatView` during streaming.

- [x] **4. Retry button on failed messages** — Error bubbles show the error and have "Copy Error" but no "Retry" / "Resend" action.

- [x] **5. Shift+Return for newlines in compose** — On macOS, Return sends. There is currently no way to insert a newline. Shift+Return is the universal convention; requires modifier-key detection in `ComposeBarView`.

- [x] **6. App-level keyboard shortcuts** — No `.commands {}` block. Need at minimum: `Cmd+N` (new chat), `Cmd+F` (focus search), `Cmd+,` (settings). (`Cmd+N` added to New Chat button; `Cmd+F` is built into `.searchable`; `Cmd+,` via Settings scene.)

---

## Medium Priority — Affects daily use

- [x] **7. Settings scene** — Appearance picker is buried in the sidebar hamburger menu. Should be a `Settings { }` scene opened with `Cmd+,`.

- [x] **8. Conversation title doesn't live-update** — Renaming a conversation via the sidebar while it's open doesn't update `navigationTitle` in `ChatView`. `selectedConversation` is a one-time fetch; needs a GRDB observation.

- [x] **9. Cron timezone picker is unusable** — ~600 timezones in a flat `Picker` renders as an unbounded unsearchable dropdown. Needs grouping or a searchable list.

- [x] **10. Exponential backoff on WebSocket reconnect** — Currently retries every fixed 5 s regardless of downtime. Should use exponential backoff with a cap.

- [x] **11. SyncCursor not reset on sign-out** — `AppDatabase.destroy()` is called but `SyncCursor.value` in UserDefaults survives. On next login (possibly to a different server) the delta sync starts from a stale cursor. One-line fix in the sign-out path.

- [x] **12. Unsaved changes confirmation in Workspace Files editor** — `isDirty` is tracked but dismissal has no "You have unsaved changes" warning.

- [x] **13. Bead list doesn't live-update** — Beads are fetched once on filter change. Changes from Claude tool calls don't appear until the user manually switches the filter. Needs WebSocket events for bead updates (server + client work).

- [x] **14. Context module edit/delete** — Custom modules can be created but not edited or deleted from the UI (server endpoint needed for delete).

---

## Polish — UX refinements

- [x] **15. Copy code block button** — The context menu copies the whole message. Individual code blocks should have an inline copy button (standard in AI chat apps). Requires a custom `InlineCodeBlock` component or MarkdownUI block override.

- [x] **16. Date separators between messages** — No visual separation between messages from different days; only timestamps on tap.

- [x] **17. Max-width cap on assistant bubbles** — `Spacer(minLength: 52)` doesn't prevent bubbles from spanning full width on wide windows. Long paragraphs become hard to read at 1200 px+. Cap at ~700 pt.

- [x] **18. Draft persistence across conversation switches** — Compose draft is `@State`; switching conversations loses it. Store in `AppStorage` keyed by conversation ID.

- [x] **19. Attachment chip UI** — File attachments paste the raw fenced markdown block into the compose field. A small removable attachment chip would be cleaner.

- [x] **20. Auth token in Keychain** — Token is stored in UserDefaults (acknowledged in a code comment). Should use Keychain on macOS/iOS.

- [x] **21. Reconnect on app foreground** — No trigger to immediately reconnect the WebSocket when the app regains focus after being backgrounded.

- [x] **22. Memory item timestamps + editing** — Items show content but not when they were added. No inline editing — only add/delete. (Timestamps added; inline editing is a future enhancement.)

- [x] **23. Message search** — Sidebar search filters by conversation title only. Searching message content requires server-side full-text or local SQLite FTS5. (Implemented via LIKE query on server, shown as "Messages" section below conversation matches.)

---

## Notes

- Items marked with "needs server work" require changes to `src/server/` in addition to the client.
- Items 3, 13, 14 (delete) all require new server endpoints before client work can begin.
- The Beads live-update (#13) requires a new `WsEvent` type on the server (`beads.updated` or similar).
