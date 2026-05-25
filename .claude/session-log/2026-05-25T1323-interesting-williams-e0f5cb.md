# 2026-05-25 — Apple Developer paid team activated, architecture.md updated

- **Paid Apple Developer Program enrolled** (2026-05-25). Tom converted his existing Apple ID rather than joining a separate org team, so Team ID stays `Q4B2VW8TUA` — **no `DEVELOPMENT_TEAM` pbxproj change needed**. Don't relitigate "but the team ID didn't change" next session; that's the enrolled-personal path, working as intended.
- **`design/architecture.md` "Apple Developer / signing" section rewritten** to reflect paid reality (1-year provisioning, no weekly Xcode re-run, Strava token persistence as a downstream win). Doc-only change, no behavior diff.
- **Weekly Strava re-auth was a side effect of 7-day cert rotation**, not a token-storage bug — Keychain code at `Keychain.swift:29` uses `kSecAttrAccessibleAfterFirstUnlock` correctly. Paid provisioning fixes it organically; no Swift changes warranted.
- **In-the-wild watch items**: confirm BG App Refresh keeps firing past 7 days (was the second casualty of cert rotation per `completed/5.md`), and confirm Strava connection survives without re-auth. Both observable via Recent syncs UI from #5.
- **#17 still in Todo** — single-writer HK pipeline awaiting explicit "start coding" approval. Unchanged from last session.
