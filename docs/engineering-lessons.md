# Engineering Lessons

This project has a few hard-earned guardrails. Read this before changing window behavior, editor behavior, or persisted app state.

## Match The Bug Layer

Fix the layer the user actually reported.

- Hover or cursor issue: change hover/cursor feedback only.
- Drag issue: change drag handling only after proving native behavior is insufficient.
- Layout issue: change layout constraints or frame calculation only.
- Persistence issue: inspect the actual saved state first.

Do not solve a signal-layer problem by replacing interaction-layer behavior.

## Window Resize Rule

For the sticky note window, native AppKit resize behavior is the source of truth.

- Do not add `mouseDown`, `mouseDragged`, or `leftMouseDragged` handling for window resize unless the user explicitly asks to replace native resizing.
- Do not call `setFrame` during a user drag for hover/cursor fixes.
- If the bug is edge hover feedback, only update cursor/hover affordance.
- Keep `isMovableByWindowBackground` interactions in mind: a missed resize edge can become a window move.

## Verify The Running App

Before saying a UI fix works, verify the exact binary and process being tested.

- Confirm the running PID and app path.
- Avoid testing `/Applications/Pinaday.app` when the intended target is the Debug build.
- Kill stale Xcode/debugserver-launched processes if they keep old app instances alive.
- Relaunch cleanly and confirm the visible window belongs to the expected process.

## Sandbox State

After App Sandbox is enabled, the app reads and writes data under the container path:

`~/Library/Containers/com.makeeverydaybetter.dailysticky/Data/Library/Application Support/DailySticky/`

Do not debug current app state using only the old non-sandbox path:

`~/Library/Application Support/DailySticky/`

When a saved window frame, theme, opacity, or note content looks wrong, inspect the sandbox container first.

## Theme Ownership

Pinaday's in-app controls must render from `AppTheme.Palette`, not from each Mac's system Accent Color.

- Do not use an implicit native `.bordered` button inside an app-themed surface. Use a shared Pinaday button style instead.
- A native `.borderedProminent` button is allowed only when it immediately applies `.tint(palette.accent)`.
- AppKit controls must use `palette.accentNS`; never use `NSColor.controlAccentColor` for Pinaday UI.
- Define enabled, pressed, and disabled foreground/background colors explicitly in shared styles.
- System menus may follow macOS appearance because they live outside Pinaday's themed surfaces.
- Run `ThemeConsistencyTests` after adding or changing a control. The test intentionally rejects implicit system-accent dependencies.

## Cloud Sync Data Safety

CloudKit responses are asynchronous snapshots, never replacements for the live editor state.

- Never assign a returned cloud page dictionary directly over `AppState.data.pages`.
- Reconcile every result with a three-way merge: the snapshot that started the request, the current in-memory pages, and the synchronized cloud pages.
- A note edited while sync is running must remain local and be uploaded by a follow-up sync.
- When local and remote both changed from the request snapshot, preserve both versions; never choose one silently.
- Sync requests are serialized. New requests queue the latest snapshot instead of repeatedly cancelling active CloudKit work.
- The local JSON store remains the offline source of truth and must be saved before any cloud request is scheduled.
- Run the complete `CloudSyncTests` suite after changing persistence, autosave, app lifecycle, or CloudKit behavior.

## Definition Of Done

For UI behavior fixes:

- Build Debug.
- Run the exact built app.
- Confirm PID/path.
- Reproduce the original issue.
- Verify only the requested behavior changed.
- Build Release before handing back.
