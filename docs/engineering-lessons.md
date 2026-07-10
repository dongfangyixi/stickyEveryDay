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

## Definition Of Done

For UI behavior fixes:

- Build Debug.
- Run the exact built app.
- Confirm PID/path.
- Reproduce the original issue.
- Verify only the requested behavior changed.
- Build Release before handing back.
