# 2026-06-24 — watchOS sync-trigger planning

- Filed #47: watchOS companion to trigger sync from the wrist (button + complication).
- Locked design ([`design/watch-sync-trigger.md`](../../design/watch-sync-trigger.md)): watch is a remote control over `WCSession` — phone runs the unchanged `SyncOrchestrator`; no token leaves the phone, no sync logic ported.
- Phone-side change is tiny: new `SyncLogEntry.Source.watch` case + a `WCSessionDelegate` that calls the existing orchestrator and replies with status.
- Planning only — no code written, no approval to build yet. Open questions on #47 (complication families, min watchOS target, bundle ids) need Tom before implementation.
- Next session branches from main to build #47; design note is already on main.
