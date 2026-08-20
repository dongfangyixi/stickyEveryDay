# DailySticky Storage Schema

DailySticky stores app data as platform-neutral JSON. Future macOS, Windows, and Linux implementations should preserve this shape unless `schemaVersion` is incremented with a documented migration.

## Storage Modes

Pinaday is local-first in both modes:

- `localOnly` is the default. Notes and attachments stay in Application Support and no CloudKit API is called.
- `iCloud` keeps the same local files as the offline source of truth, then mirrors note pages and attachments into the user's private CloudKit database.

The user's explicit choice is stored in `AppSettings.storageMode` and `AppSettings.hasChosenStorageMode`. Existing data written before these fields defaults to local-only and asks the user once.

## CloudKit Schema

Container: `iCloud.com.makeeverydaybetter.dailysticky`

Custom zone: `PinadayNotes`

`DayPage` records use the stable date key as identity and contain `dateKey`, `noteText`, `createdAt`, and `updatedAt`.

`Attachment` records contain a stable relative path, modified date, and a `CKAsset`. Paths remain compatible with existing Markdown image references under `attachments/<date>/...`.

Search indexes, window position, theme, language, pinning, opacity, and login behavior remain device-local.

## Merge Safety

`cloud-sync-metadata.json` stores the last synchronized content hash for each date. If both local and remote text changed from that baseline, Pinaday keeps the newer text as the page and appends the other text under `## Sync conflict copy`. It never silently discards either version.

A response is also merged against the exact local snapshot that started its request. Text typed while that request is running cannot be replaced by the older response. Pinaday queues a follow-up upload whenever the live note changed during synchronization.

Local edits are uploaded after autosave. While Pinaday is active, it also checks for changes from other devices every 20 seconds; activating the app or pressing **Sync Now** checks immediately. Sync requests run serially so slower CloudKit operations cannot race each other.

## File Location

macOS MVP:

```text
~/Library/Application Support/DailySticky/daily-sticky.json
```

Other platforms should choose the local application data directory expected by that operating system.

## Date Keys

Daily pages are keyed by local calendar date using:

```text
yyyy-MM-dd
```

Example:

```text
2026-06-24
```

## Root Object

```json
{
  "schemaVersion": 1,
  "pages": {
    "2026-06-24": {
      "dateKey": "2026-06-24",
      "noteText": "Notes and Markdown tasks for this day\n\n- [ ] Example task\n    - [x] Completed child task",
      "createdAt": "2026-06-24T10:30:00Z",
      "updatedAt": "2026-06-24T10:30:00Z"
    }
  },
  "settings": {
    "lastOpenedDateKey": "2026-06-24",
    "isPinned": true,
    "windowFrame": {
      "x": 100,
      "y": 100,
      "width": 360,
      "height": 520
    }
  }
}
```

## Fields

`schemaVersion`: Integer storage schema version. The MVP writes `1`.

`pages`: Object keyed by date key. Each value is a day page.

`DayPage.dateKey`: The same `yyyy-MM-dd` key used in the parent object.

`DayPage.noteText`: Markdown note content for the day. This is also the source of truth for inline task-list todos.

`createdAt` and `updatedAt`: ISO 8601 timestamps in UTC-compatible string form.

`settings.lastOpenedDateKey`: Date key restored on app launch.

`settings.isPinned`: Whether the sticky window should open in always-on-top mode.

`settings.windowFrame`: Optional platform-neutral window rectangle.

## Markdown Task Syntax

Todo items live inside `noteText` as Markdown task-list lines. This keeps storage portable and easy for future native Windows or Linux apps to implement.

Unchecked todo:

```text
- [ ] Write design notes
```

Checked todo:

```text
- [x] Write design notes
```

Hierarchy is represented with indentation:

```text
- [ ] Parent task
    - [ ] Child task
        - [x] Finished detail
```

Shorthand lines such as `[ ] Task`, `[] Task`, or `- [] Task` are plain Markdown text. App-generated task lines should use the canonical `- [ ] Task` form.

## Inline Markdown

The macOS MVP uses `swift-markdown` to parse common Markdown while editing and stores the original Markdown text unchanged.

Examples:

```text
# Heading
**Bold text**
*Italic text*
`inline code`
~~struck text~~
```

Bold text uses double asterisks or double underscores. Single asterisks are italic in Markdown.
