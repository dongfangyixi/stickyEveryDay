# DailySticky Product Spec

## MVP

DailySticky is a small desktop sticky-note app organized by day. The sticky note window is the main interface. There is no separate dashboard, project system, calendar month view, account system, reminders, or sync in the MVP.

## Window Behavior

- The app opens one draggable, resizable sticky-note window.
- The window restores its last saved frame when possible.
- The window supports pinned and unpinned modes.
- Pinned mode uses an always-on-top floating window level.
- Unpinned mode uses a normal window level.
- The app remembers the pin state, last opened date, and window frame.
- The macOS version uses SwiftUI for content and AppKit for window behavior.

## Daily Pages

- Each page represents one local calendar day.
- Each page is identified by a `yyyy-MM-dd` date key.
- The app opens to the last opened date, or today when no previous state exists.
- Previous day, next day, and today navigation are available in the sticky note.
- Opening a day with no content creates an empty page automatically.

## Daily Editor

- Each day has one editor.
- The editor contains Markdown notes and Markdown task-list todos together.
- There is no separate todo panel or add-task input.
- Users edit notes and todo text in the same text surface.
- Todo state is encoded inline in `noteText` with Markdown task-list markers.
- Task lines render as real clickable checkboxes in the editor.
- Indentation represents hierarchy.
- The canonical task syntax is `- [ ] item` and `- [x] item`.
- Shorthand forms such as `[] item` or `- [] item` are plain text, not todos.
- Common inline Markdown is parsed with `swift-markdown` and styled while editing: headings, `**bold**`, `*italic*`, inline code, and strikethrough.

Example:

```text
- [ ] Draft launch notes
    - [x] Outline MVP
    - [ ] Polish editor
        - [ ] Check keyboard behavior
        - [ ] Check storage JSON
```

## Editing

- The note auto-saves while typing.
- Toggling a checkbox updates the inline marker.
- Pressing Return at the end of a task line creates a new task at the same indentation level.
- Full Markdown preview/export, attachments, and formatting controls are outside the MVP.

## Storage and Recovery

- Storage is a local JSON file in Application Support.
- Dates are encoded as ISO 8601 strings.
- The schema has an explicit `schemaVersion`.
- Missing storage creates a fresh default file.
- Corrupted JSON is backed up to a timestamped file before fresh data is created.
