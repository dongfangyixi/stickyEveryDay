# DailySticky

DailySticky is a lightweight native macOS sticky-note calendar and to-do app.

The first version is macOS-only, built with SwiftUI and AppKit. The data model and JSON storage format are intentionally platform-neutral so a future Windows or Linux native app can read and write the same data.

## Build and Run

1. Open `DailySticky.xcodeproj` in Xcode.
2. Select the `DailySticky` scheme.
3. Build and run on macOS 13 or later.

From Terminal:

```sh
xcodebuild -project DailySticky.xcodeproj -scheme DailySticky -configuration Debug build
```

## Data Location

The app stores its JSON file in:

```text
~/Library/Application Support/DailySticky/daily-sticky.json
```

If the JSON is corrupted, the app copies it to a timestamped backup in the same directory and starts with fresh local data.

## Project Shape

- `DailySticky/Models`: platform-neutral Codable data structures.
- `DailySticky/Storage`: JSON loading, saving, backup, and date encoding.
- `DailySticky/State`: app state and daily page mutations.
- `DailySticky/Services`: date-key, `swift-markdown` rendering support, Markdown task-list editing, and auto-save utilities.
- `DailySticky/Views`: SwiftUI sticky-note interface.
- `DailySticky/Platform/macOS`: AppKit window behavior.
- `docs`: product behavior, storage schema, and future desktop plan.
