# watchOS companion: manual "Sync now" from the wrist

## Problem / goal

Tom wants to trigger a sync from his Apple Watch — the same action as the
"Sync now" button in `ContentView.swift:73` — without taking the phone out. The
motivating moment: just finished a ride, watch is on-wrist, wants to kick the
Strava→HealthKit pipeline now rather than wait for the hourly BG fire.

## Key architectural decision: the watch does NOT run the sync

The watch is a **remote control**, not a second sync engine. It sends a
"sync now" command; the **phone runs the existing `SyncOrchestrator` unchanged**
and reports the result back. Rationale — the sync needs three things the watch
can't reliably supply on its own:

1. **The Strava refresh token** lives only in the phone Keychain
   (`com.holmes1371.FitnessLoadTracker` / `StravaRefreshToken`,
   `Keychain.swift`). Sharing it to the watch (App Group + shared Keychain)
   would widen the secret's surface for no benefit.
2. **Reliable network** for the Strava API — the watch often has none without
   the phone nearby.
3. **The whole pipeline** (`SyncOrchestrator`, `StravaClient`,
   `HealthKitManager`, the matcher/dedup/heal logic) is phone-resident and not
   built to run on watchOS.

So: **no token ever leaves the phone, no sync logic is ported.** The watch app
is a button + a thin `WCSession` message. This keeps the security surface
identical to today.

### Why not standalone (watch syncs alone, tokens on the watch)

The only reason to transfer the Strava tokens to the watch is to let it sync
with the **phone absent entirely** (watch alone on cellular). We reject that —
not just because it's harder, but because it's structurally wrong for this
pipeline: the sync's job is to reconcile Strava activities against the
**phone's** HealthKit store and write effort scores **there**. The watch has its
own separate HealthKit store that syncs up to the phone; it can't see the full
matching picture the matcher/dedup/heal logic depends on. Even with the tokens,
a watch-alone sync couldn't do the reconciliation correctly. Tom has phone
cellular and the phone is paired/reachable from the wrist in practice, so the
"phone absent" case barely exists for him.

## Transport: WatchConnectivity (`WCSession`)

- **Watch → phone, reachable path:** `sendMessage(_:replyHandler:)` when
  `WCSession.isReachable` (phone awake + nearby + app installed). The phone's
  `WCSessionDelegate.didReceiveMessage` calls
  `await sync.syncRecentActivities(source: .watch, healthKit: manager)` and
  returns a small status payload (succeeded/failed, count, last-sync timestamp)
  via the `replyHandler`. The watch shows ✅ N synced / ⚠ error.
- **Not-reachable fallback:** if `isReachable` is false, fall back to
  `transferUserInfo` (queued, delivered when the phone wakes). The watch then
  shows "queued" rather than a live result, since there's no synchronous reply.

### Caveat to surface to Tom

`transferUserInfo` can wake the phone app in the **background**, where the
existing `BackgroundSync` guard bails when HealthKit is locked
("Protected health data is inaccessible"). So the queued path may defer to the
next real sync rather than running immediately. The **reliable** UX is
"watch + phone nearby, phone recently unlocked" — which is exactly the
post-workout situation. v1 optimizes for the reachable path and treats the
queued path as best-effort.

## Watch UI scope (decided: app-grid icon, no complication)

- **App:** a single-screen watchOS SwiftUI app — one "Sync now" button, a status
  line (last result + last-sync time), and an in-flight spinner. Mirrors the
  phone's sync section, stripped to one action.
- **Launch surface:** the watch app's **app-grid icon** (every watch app gets
  one automatically). Tom uses a modular face on the Ultra 2 but explicitly does
  **not** want a watch-face complication — tapping the app icon is enough. This
  drops the WidgetKit complication target entirely. A complication remains a
  possible follow-up if he later wants last-sync recency on the face itself.

## Phone-side changes

- **New `SyncLogEntry.Source.watch` case** (`SyncLog.swift:32`) so a
  watch-triggered sync is distinguishable from `.foreground` / `.background` in
  the Recent syncs list. The enum is a `String`-backed `Codable`; adding a case
  is decode-safe for existing persisted entries (they only ever decode the cases
  they were written with).
- **`WCSessionDelegate` on the phone** — activate a session at launch (alongside
  the existing `BackgroundSync.register()` in `FitnessLoadTrackerApp`), handle
  the "sync now" message, run the orchestrator, reply with status.
- **No changes to `SyncOrchestrator`, `StravaClient`, `HealthKitManager`,
  Keychain, or secrets** — the watch path reuses them verbatim. This is the
  whole point of the remote-control design.

## Watch-side reachability of HealthKit

The watch app itself does **not** touch HealthKit — it only sends a message.
HealthKit access, entitlements, and consent stay phone-only and unchanged.

## Scope

### In

- One new **watchOS app target** in the Xcode project
  (`FitnessLoadTracker.xcodeproj`, objectVersion 77, file-system synchronized
  groups). No complication target.
- Watch app: SwiftUI single screen (button + status line + spinner), launched
  from its app-grid icon.
- `WCSession` plumbing: watch sender + phone delegate, reachable
  (`sendMessage`) and queued (`transferUserInfo`) paths.
- Phone: `SyncLogEntry.Source.watch`, session activation, message handler that
  calls the existing orchestrator and replies with status.
- Status round-trip so the watch shows real success/failure, not fire-and-forget.
- Tests: a pure encode/decode round-trip for the new `.watch` Source case;
  a pure mapping function from sync result → watch status payload (so the
  message-reply shape is unit-tested without a live `WCSession`). The
  `WCSession` wiring itself is verified on-device per project convention.

### Out (deferred)

- **Standalone watch sync** (watch running Strava/HealthKit itself) — explicitly
  out; the remote-control model is the locked design.
- **Sharing the Strava token to the watch** — not needed and a security
  regression; out.
- **Rich watch UI** (per-activity breakdown, sync history on the wrist) — the
  phone owns that; the watch shows one headline result. Revisit if Tom wants more.
- **Pushing sync results to the watch proactively** (phone → watch on every BG
  sync) — v1 only replies to a watch-initiated request.
- **Watch-face complication** — Tom doesn't want one; the app-grid icon is the
  launch surface. A complication showing last-sync recency is a possible
  follow-up, and would pair with proactive push above.
- **Background refresh on the watch** — the watch never syncs on its own.

## Locked decisions

- **Watch is a remote control; phone runs the unchanged pipeline.** No sync
  logic ported, no token shared.
- **Security surface unchanged** — no App Group, no shared Keychain, no token on
  the watch.
- **Optimize for the reachable path**; queued delivery is best-effort and may
  defer behind the BG HealthKit-locked guard.
- **Reuse `SyncOrchestrator` verbatim** via a new `.watch` source tag only.

## Open questions

- **Queued-path UX** — is "queued, will sync when phone is reachable" acceptable
  wording when `isReachable` is false, or does Tom want the watch to surface that
  it didn't run live? Lean: show "queued" honestly.
- **Min deployment target** — the watch target's minimum watchOS version. Set to
  match the Ultra 2 (current watchOS).
- **App naming / bundle id** for the watch target (must nest under the phone
  app's bundle id).

## Test fixtures needed

- `SyncLogEntry` with `source: .watch` → encodes and decodes round-trip; legacy
  JSON without the case still decodes (regression on the existing decode path).
- Sync-result → watch-status-payload mapping: success with N written, success
  with 0 written (overlap re-fetch), per-item-error case, hard-failure case →
  each maps to the expected wrist headline string.
- (On-device, manual) reachable path: tap watch button with phone unlocked
  nearby → phone runs sync → watch shows result; Recent syncs row tagged
  `.watch`.
- (On-device, manual) not-reachable path: phone backgrounded/locked → tap →
  watch shows "queued" → sync lands on next phone wake.
