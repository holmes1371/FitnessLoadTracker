# 2026-06-06 — Strava/WorkOutDoors sync-timing race (#43)

- Diagnosed: BG sync can hit the `.noMatch` create path before WorkOutDoors' HK twin lands → duplicate; `moving_time`/`elapsed_time` gap then blocks both `Matching` and #39 from reconciling.
- Filed **#43** + `design/strava-workoutdoors-sync-timing.md`: fix = A grace period before create, B start-only create suppression, C self-heal (delete our copy when a native twin exists, fenced by a hard contract).
- **No code written** — Tom verifies/deploys from his laptop (Xcode); plan/design only this session.
- Open: `createGracePeriod` value (tentative 6h) needs Tom's sign-off; precedence locked as "native twin always wins over our app-authored copy."
- #43 not yet placed on the Projects v2 board (no board-mutation tool in the web MCP set) — needs the Todo-column add via `gh`/UI.
