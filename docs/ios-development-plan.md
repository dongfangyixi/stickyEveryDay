# Pinaday iOS Development Plan

Status: The approved foundation and local vertical slice are implemented on
`codex/ios-foundation`. Physical-device CloudKit qualification and complete
editor-parity work remain release gates.

Baseline: Pinaday macOS 1.0 build 44, commit `ce22b6f`, tag
`v1.0.0-build44`.

Development branch: `codex/ios-foundation`.

## 1. Executive Decision

Build Pinaday for iPhone and iPad in the existing repository and Xcode project,
using a separate iOS application target and a shared core module.

The macOS and iOS products will share data definitions, migrations, Markdown
parsing, search, localization, and CloudKit behavior. They will not share
platform-specific editor or window implementations.

The macOS 1.0 source remains frozen on `main` while it is in App Review. No iOS
work is merged to `main` until the shared-code changes pass the complete macOS
suite and the iOS vertical slice is proven safe.

## 2. Product Goal

Pinaday on iOS should feel like the same product, not a reduced web-style copy
of the Mac app:

- One Markdown note for every calendar day.
- Immediate movement between days through the date dial.
- Fast capture with a software or hardware keyboard.
- Native editing of text, nested lists, tasks, tables, code, and images.
- Local-first storage with optional private iCloud synchronization.
- Search across notes and OCR text.
- The same visual identity, themes, languages, and data safety guarantees as
  the Mac app.

The first release is iPhone-first, but the target must remain usable on iPad,
including portrait, landscape, and split-view widths.

## 3. Non-Goals For iOS 1.0

- Reproducing macOS window pinning, window opacity, window resizing, window
  position restoration, or launch-at-login.
- A calendar dashboard, project hierarchy, reminders, widgets, Watch app, or
  collaboration system.
- A second account system or a Pinaday-owned server.
- Changing the existing JSON schema or CloudKit record schema merely to make
  the port easier.
- Replacing Markdown as the canonical note representation.
- Shipping partial editor behavior as a production substitute for the Mac
  editor. Intermediate prototypes may be incomplete, but the release may not.
- Automatic transfer of Mac local-only data to iPhone. Cross-device transfer
  requires the user to enable iCloud on both devices.

## 4. Release Protection

### 4.1 Frozen Mac Baseline

The submitted Mac build is recoverable from `v1.0.0-build44`. The following
rules apply while the review is active:

1. Do all iOS work on `codex/ios-foundation` or smaller branches created from
   it.
2. Do not merge iOS scaffolding or shared-module extraction into `main` during
   review.
3. If App Review requires a Mac fix, branch from `v1.0.0-build44`, apply only
   the review fix, run the full Mac suite, and upload a new Mac build number.
4. Never use an iOS refactor as an opportunity to alter unrelated Mac UI or
   editor behavior.
5. Keep generated prototypes and screenshots under `artifacts/` and outside
   source commits.

### 4.2 Shared-Code Change Rule

Every commit that moves or changes code used by macOS must satisfy all of the
following before the next commit begins:

- The macOS app builds in Debug and Release.
- The complete `PinadayTests` suite passes.
- The relevant manual item in `docs/editor-regression-checklist.md` is checked
  when editor behavior is involved.
- Stored Markdown and JSON output are byte-equivalent unless the commit is an
  explicitly reviewed migration.
- The change is structural or cross-platform; it must not redesign the Mac
  experience.

## 5. Repository And Target Structure

The preferred structure is:

```text
stickyEveryDay/
  DailySticky.xcodeproj
  DailySticky/                  Existing macOS application
    App/
    Platform/macOS/
    Views/
  PinadayIOS/                   New iOS application
    App/
    Platform/iOS/
    Views/
    Resources/
  Packages/
    PinadayCore/                Local Swift package
      Sources/PinadayCore/
      Tests/PinadayCoreTests/
  DailyStickyTests/             macOS integration/regression tests
  PinadayIOSTests/              iOS integration tests
  PinadayIOSUITests/            focused end-to-end UI tests
  docs/
```

### 5.1 Targets And Schemes

| Target | Platform | Responsibility |
| --- | --- | --- |
| `Pinaday` | macOS 13+ | Existing shipping Mac application |
| `Pinaday iOS` | iOS/iPadOS 17+ proposed | Native mobile application |
| `PinadayCore` | macOS 13+, iOS 17+ | Platform-neutral product behavior |
| `PinadayTests` | macOS | Existing Mac integration and regression coverage |
| `PinadayCoreTests` | macOS and iOS simulator | Shared contracts and fixtures |
| `PinadayIOSTests` | iOS simulator | iOS state, storage, sync, and view-model behavior |
| `PinadayIOSUITests` | iOS simulator/device | Critical touch and keyboard workflows |

`PinadayCore` should be a local Swift package because a separate module makes
platform boundaries compiler-enforced. Do not add AppKit or UIKit to this
module. Platform frameworks such as Vision and CloudKit may live in small
shared service targets only when both platforms compile and behave identically;
otherwise expose a protocol from core and implement it in each app.

### 5.2 Dependency Direction

```text
Pinaday macOS UI  ----\
                      -> PinadayCore <- shared tests
Pinaday iOS UI    ----/

Platform adapters -> PinadayCore protocols
PinadayCore must never import either application target.
```

Avoid a large collection of `#if os(macOS)` branches. A small conditional for a
genuinely identical API is acceptable, but editor, window, pasteboard, image,
and lifecycle behavior belongs in platform-specific files.

## 6. Existing Code Classification

This table is the initial extraction map. Classification must be validated by
compiling each file for iOS before moving it.

| Existing area | Plan | Notes |
| --- | --- | --- |
| `Models/AppData.swift` | Share | Keep schema version 2 unchanged |
| `Models/DayPage.swift` | Share | Canonical per-day record |
| `Models/AppSettings.swift` | Share initially | Preserve Mac-only fields; iOS ignores them |
| `Models/AppLanguage*.swift` | Share | Declare all eight bundle localizations |
| `Models/StorageMode.swift` | Share | Same local-only/iCloud choice |
| `Models/StoredWindowFrame.swift` | Preserve in schema | Mac-only behavior, harmless Codable data on iOS |
| `Storage/*` | Share after URL injection | Never hard-code a platform container path in core |
| `Storage/AppDataMigration.swift` | Share | One migration sequence for both products |
| `Services/DateKeyService.swift` | Share | Same date keys and localized dial content |
| `Services/Markdown*Parser.swift` | Share | Pure parsing and source-range behavior |
| `Search/NoteSearchEngine.swift` | Share | Preserve ranking, precision, and performance tests |
| `Search/NoteDateSearchEngine.swift` | Share | Preserve localized date-order behavior |
| `Search/CurrentNoteFind.swift` | Split | Share match engine and models; platform UI remains separate |
| `Search/OCRSearchIndexer.swift` | Share | Repository is injected already |
| `Services/ImageOCRRepository.swift` | Share/adapt | Vision and ImageIO are available on iOS; inject file resolution |
| `Services/AttachmentStore.swift` | Split | File/path logic shared; `NSImage` encoding replaced by iOS adapter |
| `Sync/SyncMergeEngine.swift` | Share | Highest-risk shared data behavior; retain all tests |
| `Sync/CloudSyncModels.swift` | Share | Stable cross-platform contract |
| `Sync/CloudSyncCoordinator.swift` | Share/adapt | iOS lifecycle and background suspension need explicit handling |
| `Sync/CloudKitSyncService.swift` | Share/adapt | Same container, zone, record IDs, and fields |
| `State/AppState.swift` | Split then converge | Data behavior is shareable; UI/window/search presentation is not |
| `Views/DateTickerView.swift` | Adapt | Share projection math; build touch/accessibility wrapper for iOS |
| `Views/DailyNoteEditorView.swift` | Rewrite UI | AppKit implementation must not compile into iOS |
| `Search/NoteSearchView.swift` | Rewrite UI | Replace floating `NSWindow` panel with iOS sheet/navigation |
| `App/AppDelegate.swift` | macOS only | iOS uses SwiftUI scene lifecycle |
| `Platform/macOS/*` | macOS only | Never add to iOS target membership |
| `Theme/AppTheme.swift` | Split | Shared semantic tokens, platform-specific color conversion |

## 7. Shared Data Contract

### 7.1 Canonical Note Model

The canonical note remains `DayPage.noteText`. Rendered checkboxes, list
numbers, tables, code styling, images, and OCR overlays are presentations of
the stored Markdown and must not create a second document model.

Each page continues to contain:

- `dateKey`: local-calendar `yyyy-MM-dd` identifier.
- `noteText`: canonical Markdown source.
- `createdAt`: creation timestamp.
- `updatedAt`: last content mutation timestamp.

### 7.2 Local JSON

iOS uses its own sandboxed Application Support directory and the same logical
layout:

```text
Library/Application Support/DailySticky/
  daily-sticky.json
  cloud-sync-metadata.json
  ocr-text-cache.json
  attachments/<date-key>/<image-file>
```

Using the same bundle identifier does not make local Mac files visible to iOS.
Local-only mode means each device has an independent local collection.

The `JSONAppDataStore` initializer must accept an injected root URL. Each app
resolves its own Application Support location and passes it into core. Tests
always use a temporary directory.

### 7.3 Schema And Migration Rules

- iOS 1.0 starts with `AppData.currentSchemaVersion == 2`.
- Do not increment the schema merely to add an iOS target.
- iOS must decode fixtures from schema versions 0, 1, and 2.
- Unknown/newer schemas fail closed and block writes.
- Every future schema migration is written once in `PinadayCore` and tested on
  both platforms.
- The original bytes are backed up before a migrated file is committed.
- A migration failure must never replace user data with an empty note file.

The full contract in `docs/data-migrations.md` remains mandatory.

### 7.4 Settings

Settings remain device-local and are not synchronized through CloudKit.

For iOS 1.0:

- `theme`, `language`, `storageMode`, `hasChosenStorageMode`, and
  `hasSeenWelcome` are meaningful.
- `isPinned`, `windowFrame`, `noteOpacity`, and the Mac interpretation of
  `noteZoom` are retained for decoding compatibility but not presented in iOS
  settings.
- The initial language should match a supported system language on first
  launch, then persist the user's explicit selection. Existing Mac users keep
  their saved selection.

### 7.5 Date And Time-Zone Semantics

- Date keys represent named local calendar days, not UTC day buckets.
- Opening a device in a new time zone changes which key is called "today" but
  does not move existing notes to another key.
- Both platforms must use the same Gregorian date-key parsing and validation.
- Tests must cover month/year boundaries, daylight-saving transitions, and two
  devices in different time zones.

## 8. CloudKit Compatibility

The iOS target must use the production contract already shipped by macOS:

```text
Bundle identifier:  com.makeeverydaybetter.dailysticky
Cloud container:    iCloud.com.makeeverydaybetter.dailysticky
Private zone:       PinadayNotes
Page record type:   DayPage
Attachment type:    Attachment
```

### 8.1 Record Contract

`DayPage` fields:

- `dateKey`
- `noteText`
- `createdAt`
- `updatedAt`

`Attachment` fields:

- `relativePath`
- `updatedAt`
- `file` as `CKAsset`

Record identifiers and relative attachment paths must remain unchanged so
build 44 can read everything written by the iOS app.

### 8.2 Synchronization Invariants

- Save local JSON before scheduling any cloud request.
- Fetch and merge before uploading a newly created device snapshot.
- Reconcile a cloud response against the snapshot that started the request and
  the current live local state.
- Never replace text typed during an in-flight request with an older response.
- If local and remote changed from the same baseline, preserve both under the
  existing `Sync conflict copy` representation.
- Serialize cloud requests; queue the newest pending snapshot.
- Switching to local-only cancels and invalidates in-flight cloud results.
- Attachment files use immutable unique paths. A platform must not reuse a path
  for different bytes.
- No platform may introduce CloudKit deletion until tombstones and backward
  compatibility are designed explicitly.

### 8.3 iOS Lifecycle

iOS cannot rely on a continuously running 20-second foreground timer.

- Synchronize when the app becomes active.
- Synchronize immediately after a committed local save when active.
- Save immediately when the scene enters inactive/background state.
- Cancel UI-owned indexing work in the background.
- Treat background execution as an optimization, never as a correctness
  requirement.
- On foreground return, always reconcile with CloudKit before claiming the app
  is up to date.

### 8.4 Cross-Platform Sync Qualification

Before TestFlight external testing, prove all of these with two physical
devices and a disposable iCloud account:

1. Mac build 44 creates text; iPhone receives it.
2. iPhone edits text; Mac build 44 receives it.
3. Each platform adds an image; the other renders and OCR-indexes it.
4. Both edit the same day while offline; reconnecting preserves both versions.
5. One platform edits while the other has a sync request in flight; the newer
   local typing survives.
6. Switching either device to local-only prevents every CloudKit call.
7. Re-enabling iCloud merges rather than replacing the local collection.
8. An old Mac build can still read records written by the iOS release build.

TestFlight uses the production CloudKit environment. Never perform destructive
experiments with the developer's real notes.

## 9. iOS Experience Specification

### 9.1 Application Structure

The first screen is the current day's note, not a dashboard or landing page.

Use a SwiftUI scene for lifecycle and navigation, with UIKit wrappers only for
the editor behavior that SwiftUI text controls cannot provide reliably.

Primary presentation:

- A full-screen paper surface.
- A compact top header inside the safe area.
- Date dial, search, and settings controls in the header.
- The editor fills all remaining space.
- Search, settings, Quick Start, and Help use sheets or navigation destinations,
  not floating windows.

### 9.2 Date Dial

Preserve the current product behavior and physical model:

- Fixed compact dial rather than a width-stretching ribbon.
- 40-point visible band.
- 20 degrees of rotation per day.
- 46-point compact face pitch and 92-point selected face.
- 300-point perspective equivalent.
- 44 points of drag translation per day.
- Flick projection capped at five days.
- The existing curved shading, edge fade, face opacity, blur, and culling rules.
- Clicking/tapping a visible face navigates to that exact date.
- Returning to today uses a distance-dependent angular speed with a consistent
  total duration.
- CJK selected labels keep month-day-weekday order and bare numeric days.

iOS-specific behavior:

- Touch targets are at least 44 by 44 points even when the visible face is
  smaller.
- Horizontal dial drag must not conflict with vertical note scrolling or the
  system back gesture.
- A short drag that does not pass the navigation threshold returns to rest.
- VoiceOver exposes the selected date and adjustable increment/decrement
  actions; drag is never the only navigation method.
- Reduce Motion replaces 3D travel with a short crossfade/slide while preserving
  the selected date.

### 9.3 Date Navigation And Focus

- Changing to an empty note focuses the editor and presents the keyboard so the
  user can type immediately.
- Changing to a populated note does not guess a caret position or force the
  keyboard open.
- Navigating away commits the current text immediately before changing pages.
- The editor selection is stored per currently visible session only; it is not
  persisted in `DayPage` or CloudKit.
- Returning from a search result preserves the existing search-origin behavior.

### 9.4 Editor Architecture

Create an iOS-specific `UITextView`/TextKit editor wrapped for SwiftUI. Do not
attempt to compile the AppKit `DailyNoteEditorView` for iOS.

The editor must follow the same invariants that protect the Mac editor:

- One canonical source string and one canonical source-to-layout mapping.
- Line geometry depends on structure and available width, never on caret,
  focus, typing attributes, or current selection.
- Markers, overlays, selection, caret placement, hit testing, and scrolling all
  consume the same layout geometry.
- Empty terminal code blocks use the same layout path as populated blocks.
- An overlay receives touches only inside its visible interactive target.
- Structured rendering never makes later text unreachable by tapping.

The port should extract pure editing transformations from the Mac editor behind
tests instead of duplicating them. Examples include:

- Return behavior for task, bullet, and numbered items.
- Indent and outdent transformations.
- Numbered-list renumbering.
- Backspace behavior at generated markers.
- Slash-command insertion and code-block splitting.
- Canonical copy/paste conversion.

### 9.5 Keyboard And Editing Controls

Software keyboard:

- A compact keyboard accessory row provides dismiss, undo, redo, indent,
  outdent, task, list, and formatting actions.
- Indent/outdent buttons substitute for the Tab key on iPhone.
- Typing `/` on an empty line opens the slash menu near the caret when space
  allows, otherwise above the keyboard.

Hardware keyboard:

- Tab and Shift-Tab change hierarchy for tasks, bullets, and numbered items.
- Tab inserts indentation in plain text.
- Command-F opens Find in Note.
- Command-P opens Go To Note.
- Command-Plus, Command-Minus, and Command-0 are supported only if semantic note
  zoom is intentionally included on iOS.
- Standard copy, paste, select all, undo, and redo remain native.

IME behavior:

- Never re-render attributed text while `markedTextRange` is active.
- Defer structural formatting, theme changes, and zoom changes until composition
  ends.
- Test Simplified Chinese, Japanese, and Korean composition on physical devices.

### 9.6 Markdown Features

Release parity requires:

- Headings
- Bold, italic, strikethrough, and inline code
- Links
- Blockquotes
- Dividers
- Bullet and numbered lists with nesting
- Todo lists with nested real checkboxes
- Fenced code blocks and language selection
- Tables
- Images with persisted logical width

All operations must round-trip through canonical Markdown. A feature is not
complete merely because it renders; editing, selection, copy/paste, undo/redo,
accessibility, and reopening must also work.

### 9.7 Images And OCR

iOS 1.0 should support:

- Paste from the system pasteboard.
- Insert from Photos using the system picker.
- Insert from Files.
- Copy, resize, select, delete, undo, and redo.
- Automatic on-device Vision OCR.
- Search and Find in Note across OCR text.
- Character-level OCR selection when the platform APIs permit a reliable
  implementation.

Images should be converted to a stable local representation without changing
the existing Markdown path format. Decode/downsample images for display rather
than loading full-resolution camera images into memory unnecessarily.

Camera capture is deferred until after the photo/file flow is stable. Adding it
requires camera permission copy, physical-device tests, and a privacy-policy
review.

### 9.8 Go To Note Search

Reuse the search and date-query engines, including:

- Date queries in localized month-day and day-month orders.
- Latin and CJK normalization.
- Whole-word typo tolerance and prefix behavior.
- OCR supplemental lines.
- Sorting content results by match count, then date.
- One result per day with total match count.
- Last query, results, and selection retained when the sheet reopens.

iOS presentation:

- Use a full-height sheet on iPhone and a resizable sheet/popover on iPad.
- The search field receives focus when first opened.
- Tapping a result opens the day and selects/reveals the first match.
- Enter and Shift-Enter navigate next/previous matches with a hardware keyboard.
- Visible previous/next controls provide the same behavior for touch users.
- Returning to search restores the prior query and selection.

### 9.9 Find In Note

- Present a compact bar above the keyboard or at the top of the editor.
- Show current/total match count.
- Provide previous, next, and close controls.
- Enter advances; Shift-Enter moves backward on hardware keyboards.
- Reveal matches in normal text, lists, tables, code, and OCR regions.
- Closing Find restores editor focus and selection predictably.

### 9.10 Settings, Help, And About

iOS settings include:

- Language
- Yellow, Light, and Dark themes
- Local-only or iCloud storage
- Current sync status and Sync Now
- Quick Start
- Help
- Send Feedback
- Privacy Policy
- Version and build number

Do not show Mac-only pinning, window opacity, window frame, or launch-at-login
controls.

### 9.11 Localization

Support the same eight languages from the first iOS release:

- English
- French
- Spanish (Spain)
- Simplified Chinese
- Japanese
- Korean
- German
- Portuguese (Brazil)

Declare these languages in the iOS bundle as well as in the custom language
picker. New installations select the closest supported system language once;
after that, the user's explicit setting wins.

Every feature adds localization keys and completeness tests in the same commit.
Date labels, dial order, pluralization, search text, accessibility labels, and
permission descriptions must be localized.

### 9.12 Accessibility

The iOS release is not complete until it supports:

- VoiceOver labels, values, hints, and actions.
- Dynamic Type without clipped controls or overlapping editor content.
- Sufficient contrast in all three themes.
- Reduce Motion behavior for the dial and transitions.
- Differentiate Without Color for selection, today, sync state, and errors.
- Full hardware-keyboard navigation on iPad.
- Touch targets of at least 44 by 44 points.

## 10. Platform Feature Matrix

| Capability | macOS | iOS plan |
| --- | --- | --- |
| Daily pages | Existing | Full parity |
| Date dial | Mouse/trackpad | Touch, tap, VoiceOver adjustable action |
| Markdown editor | AppKit/TextKit | UIKit/TextKit implementation |
| Nested tasks/lists | Tab/Shift-Tab | Accessory buttons plus hardware Tab |
| Code/tables/images | Existing | Full editing parity before release |
| Paste image | `NSPasteboard` | `UIPasteboard`, Photos, Files |
| OCR | Vision on device | Vision on device |
| Go To search | Floating panel | Sheet/popover |
| Find in note | Editor overlay | Keyboard/top bar |
| Local-only storage | Mac sandbox | iOS sandbox; independent data |
| iCloud sync | Private CloudKit | Same private container and schema |
| Theme/language | Existing | Same choices |
| Note zoom | Semantic zoom | Decision deferred; Dynamic Type required |
| Pin/opacity/window frame | Existing | Not applicable |
| Launch at login | Existing | Not applicable |

## 11. Implementation Milestones

Each milestone ends in a reviewable commit or small series of commits. A later
milestone must not conceal a failing exit gate from an earlier one.

### Milestone 0: Documentation And Baseline

Deliverables:

- This plan reviewed and accepted.
- Mac build 44 source frozen and tagged.
- Existing documentation marked where it no longer reflects current features.
- Baseline test timing and representative large-note fixtures recorded.

Exit gate:

- No application-code change.
- Clean branch except intentionally untracked artifacts.

### Milestone 1: iOS Target Skeleton

Deliverables:

- Add `Pinaday iOS` target and scheme to the existing Xcode project.
- Configure iPhone and iPad destinations, signing, app icon, bundle identifier,
  versioning, localization declarations, and iCloud entitlement.
- Add an iOS SwiftUI scene with a static placeholder note surface.
- Add iOS unit and UI test targets.

Exit gate:

- Empty iOS app launches on the smallest supported iPhone simulator and iPad
  split view.
- Mac Debug/Release builds and full tests remain unchanged.
- No shared model has moved yet.

### Milestone 2: PinadayCore Extraction

Move one dependency leaf at a time:

1. Models and JSON codec/migrations.
2. Date service and localization.
3. Markdown parsers and pure edit transformations.
4. Search engines and match models.
5. Sync models and merge engine.

Deliverables:

- Local `PinadayCore` package.
- Existing tests moved or duplicated at the appropriate module boundary.
- Mac app consumes the package without behavior changes.

Exit gate after every extraction step:

- Full Mac tests pass.
- Golden JSON and Markdown fixtures are unchanged.
- `PinadayCore` compiles and tests for an iOS simulator destination.

### Milestone 3: Local Daily-Note Vertical Slice

Deliverables:

- iOS app state and injected Application Support root.
- Safe load/save and autosave.
- Today/previous/next date navigation.
- Plain-text editing with selection, undo/redo, and scene-background save.
- First-run local-only/iCloud choice UI, with cloud action disabled until the
  next milestone if necessary.

Exit gate:

- Relaunch preserves notes and current date.
- Corrupt/newer JSON fails closed without data replacement.
- Switching dates during typing does not lose the last edit.
- Empty-note focus policy works.

### Milestone 4: Dial And Mobile Shell

Deliverables:

- Touch date dial with shared projection math.
- Search/settings controls and responsive header.
- Theme and language settings.
- Quick Start, Help, About, feedback, and privacy links.

Exit gate:

- Slow drag, fast flick, visible-face tap, today return, month boundary, and CJK
  layouts pass automated and manual tests.
- Dial gestures never steal vertical editor scrolling or the system edge swipe.
- VoiceOver can select previous/next dates without dragging.

### Milestone 5: Structured Editor Parity

Deliverables:

- Inline Markdown presentation.
- Tasks, bullets, numbered lists, nesting, code blocks, tables, quotes, and
  dividers.
- Slash commands and keyboard accessory actions.
- Copy/paste and undo/redo across mixed structures.

Exit gate:

- Port every applicable item from `docs/editor-regression-checklist.md`.
- Reproduce the historical code-block split scenario: make a ten-line final code
  block, convert line four to a numbered list using `/`, then tap and edit every
  line in the lower code block.
- Hardware and software keyboard paths behave consistently.
- CJK marked-text composition survives formatting and navigation.

### Milestone 6: Images And OCR

Deliverables:

- Paste, Photos, and Files insertion.
- Stable attachment paths and logical image sizing.
- Vision OCR cache, search indexing, and reveal behavior.

Exit gate:

- Mac and iOS exchange attachments through the unchanged CloudKit schema.
- Large images do not cause visible typing stalls or memory termination.
- OCR processing stays on device and never logs recognized text.

### Milestone 7: Search And Find

Deliverables:

- Go To Note mobile presentation.
- Search-state restoration.
- Result match navigation.
- Find in Note for rendered text and OCR.

Exit gate:

- Existing search precision/recall corpus passes unchanged in core.
- Ten-thousand-note search remains interactive.
- Result order, counts, and reveal locations match macOS.

### Milestone 8: Production CloudKit Sync

Deliverables:

- iOS lifecycle integration with the existing coordinator.
- Local-only and iCloud settings/status.
- Cross-device attachment restoration and conflict handling.

Exit gate:

- Complete the physical-device qualification in section 8.4.
- Build 44 remains able to consume all iOS-created records.
- No data loss after offline edits, interrupted sync, force quit, or storage-mode
  changes.

### Milestone 9: Accessibility, Performance, And Store Preparation

Deliverables:

- VoiceOver, Dynamic Type, Reduce Motion, contrast, and keyboard audit.
- Performance profiling on a lower-memory supported iPhone.
- Localized metadata, screenshots, privacy copy, and TestFlight notes.
- Final release checklist and support documentation.

Exit gate:

- All automated suites pass on macOS and iOS.
- Manual device matrix passes.
- Internal TestFlight upgrade/sync test passes without reinstalling the Mac app.
- No open data-loss, unreachable-text, input, accessibility, or privacy issue.

## 12. Automated Test Strategy

### 12.1 Tests That Must Remain Shared

- Date-key creation and localized date order.
- Schema 0 -> 1 -> 2 migrations.
- Malformed/newer data write blocking.
- Markdown parsing and source ranges.
- Task/list transformations and renumbering.
- Search precision, recall, ranking, date queries, and corpus performance.
- OCR text indexing models.
- Cloud merge, in-flight typing preservation, and conflict copies.

### 12.2 New iOS Unit Tests

- Application Support and attachment URL resolution.
- Scene lifecycle save/sync decisions.
- First-launch system-language selection.
- Empty/populated note focus policy.
- Touch dial threshold, flick cap, tap mapping, and today timing.
- iOS theme semantics and Dynamic Type layout metrics.
- Paste/Photos/Files image conversion.
- iOS permission-description completeness.

### 12.3 iOS UI Tests

Keep UI tests focused on failures that unit tests cannot prove:

- Tap every line after splitting a code block with a slash command.
- Tap and drag selection across structured blocks.
- Toggle nested tasks and indent/outdent from the keyboard accessory.
- Change dates with slow drag, fast flick, face tap, and VoiceOver actions.
- Type immediately after navigating to an empty note.
- Open/reopen Go To and retain its query/results.
- Insert, resize, copy, and delete an image.
- Rotate and resize the app, including iPad split view, without overlap.

### 12.4 Test Fixtures

Maintain reusable fixtures for:

- Empty page.
- Large plain-text blog page.
- Mixed Markdown page from the App Store screenshots.
- Ten-line terminal code block split by a numbered item.
- Deep nested tasks, bullets, and numbered lists.
- Wide table and long unbroken words.
- Multiple large images with multilingual OCR.
- Ten thousand note pages for search.
- Conflicting Mac/iPhone cloud snapshots.
- Schema 0, 1, 2, malformed, and future-schema JSON.

## 13. Manual Device Matrix

Minimum qualification matrix:

| Device/context | Required checks |
| --- | --- |
| Smallest supported iPhone | Header fit, dial, keyboard, slash menu, tables |
| Standard iPhone | Complete daily workflow |
| Large iPhone | Layout does not stretch into a desktop composition |
| iPhone landscape | Editor and keyboard do not hide active line |
| iPad portrait | Full workflow and hardware keyboard |
| iPad landscape | Search/settings presentation and image resizing |
| iPad split view narrow | No overlap; dial and controls remain reachable |
| Physical iPhone | IME, Photos, pasteboard, Vision OCR, iCloud, memory |
| Mac build 44 plus iPhone | Bidirectional compatibility and conflict tests |

Run the matrix in Yellow, Light, and Dark themes and at least English,
Simplified Chinese, Japanese, and German. These languages exercise different
text widths and date orders.

## 14. Performance And Reliability Budgets

Initial budgets, to be measured and adjusted from real-device baselines:

- No synchronous editor operation longer than one 60 Hz frame during ordinary
  typing.
- Date navigation updates the visible page immediately; storage and indexing do
  not block the transition.
- Search over 10,000 normal notes returns within 500 ms on a supported physical
  iPhone, while the interface remains responsive.
- Reopening an unchanged search reuses its index and feels immediate.
- OCR runs off the main actor with bounded concurrency; start with two images at
  a time on iPhone.
- Image display uses thumbnails/downsampling appropriate to rendered size.
- Autosave preserves the existing 450 ms debounce during continuous typing and
  saves immediately on navigation/backgrounding.
- A long single note of at least 100,000 characters remains editable and
  scrollable without losing selection or moving the caret.

Use `os_signpost` or equivalent debug-only instrumentation for launch, load,
save, index, search, OCR, and sync durations. Performance logs contain counts
and durations only.

## 15. Privacy And Security

- No analytics, advertising, tracking, or developer backend is introduced.
- OCR remains on device.
- Notes and images remain local unless the user explicitly enables iCloud.
- iCloud data stays in the user's private CloudKit database.
- Never log note text, OCR text, image bytes, search queries, or full local file
  paths.
- Validate all attachment relative paths and reject traversal components.
- Keep atomic writes and migration backups.
- Do not request Photos access when the system picker can provide selected
  assets without broad library permission.
- Review the privacy policy and App Privacy answers before adding camera,
  analytics, crash reporting, sharing, or any external service.

The in-app Privacy Policy URL remains:

`https://xuluthebest.com/pinaday/privacy/`

## 16. App Store And Signing Plan

The iOS platform already exists under the same App Store Connect app record.
Use that record rather than creating another app.

- Product name: Pinaday.
- Bundle identifier: `com.makeeverydaybetter.dailysticky`.
- CloudKit container: `iCloud.com.makeeverydaybetter.dailysticky`.
- iOS version starts at 1.0; its build sequence is platform-specific.
- Distribution is a universal purchase after both platform versions are
  approved. This is effectively shared ownership because Pinaday is free.
- Reuse the app identity but provide iPhone/iPad screenshots and iOS-specific
  review notes.
- App Privacy answers apply at the app level and must remain accurate for both
  platforms.
- Keep `ITSAppUsesNonExemptEncryption = NO` unless encryption behavior changes.
- Add all supported bundle localizations before the first iOS upload.

Apple references:

- Multiplatform target planning:
  https://developer.apple.com/documentation/Xcode/configuring-a-multiplatform-app-target
- Adding platforms and universal purchase:
  https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms
- SwiftUI platform integration:
  https://developer.apple.com/documentation/SwiftUI

## 17. Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| AppKit editor logic is mistaken for reusable UI | High | Share transformations, rewrite UIKit presentation |
| Core extraction regresses Mac editor behavior | High | Leaf-by-leaf moves, full Mac suite after each commit |
| iOS uploads records old Mac cannot read | Critical | Freeze CloudKit contract; test against build 44 |
| First iOS sync uploads empty pages over Mac content | Critical | Fetch/merge before upload; first-device fixtures |
| Response from in-flight sync replaces active typing | Critical | Preserve three-way reconciliation and generation invalidation |
| Overlay geometry makes lower lines untappable | High | One geometry source and historical split-code UI test |
| Software keyboard hides caret or slash menu | High | Keyboard-layout guide integration and physical-device tests |
| IME composition is interrupted by restyling | High | Defer updates while marked text exists |
| Full-resolution images exhaust mobile memory | High | Downsample display, bounded OCR concurrency |
| Dial steals scroll/back gestures | Medium | Axis lock, edge exclusion, gesture priority tests |
| Local-only users expect automatic Mac transfer | Medium | Clear onboarding copy; iCloud required for cross-device sync |
| Shared settings expose Mac-only controls | Low | Platform-specific settings views, schema fields preserved |
| App Store lists only English | Medium | Declare bundle localizations and add metadata later |

## 18. Commit And Review Discipline

- Keep commits scoped to one milestone behavior or extraction step.
- Do not combine file movement with behavior changes when avoidable.
- Record before/after test results for every shared-core extraction.
- Add a regression test before fixing any discovered editor or sync defect.
- Never weaken an existing test to make the iOS target compile.
- Review generated Xcode project changes carefully; avoid unrelated signing or
  build-setting churn.
- Do not merge the branch merely because it compiles. Merge only after the
  milestone exit gate is complete.

## 19. Decisions To Confirm Before Milestone 1

Recommended defaults are shown here so implementation can begin without
ambiguity after approval:

| Decision | Recommendation |
| --- | --- |
| Minimum OS | iOS/iPadOS 17.0 |
| Devices | Universal iPhone and iPad target; iPhone-first design |
| Shared module | Local Swift package named `PinadayCore` |
| UI framework | SwiftUI shell plus UIKit/TextKit editor |
| Bundle/App Store record | Existing Pinaday record and bundle identifier |
| Cloud storage | Existing private CloudKit container and schema |
| Local storage | Same JSON schema in iOS Application Support |
| Initial language | Closest supported system language, then persisted choice |
| Camera | Defer until after Photos/Files/paste are stable |
| Semantic note zoom | Defer decision; Dynamic Type is mandatory |
| Mac merge timing | Keep `main` frozen through Mac review |

## 20. Definition Of Done For iOS 1.0

Pinaday iOS is ready for App Review only when:

- The complete daily-note workflow works on iPhone and iPad.
- All promised Markdown structures are editable, not merely rendered.
- Historical Mac editor regressions have equivalent iOS coverage.
- Local-only mode makes no CloudKit calls.
- Mac build 44 and iOS exchange text and images without schema changes.
- Concurrent/offline edits preserve both versions.
- Migration failures never destroy or overwrite the original file.
- Search quality and performance meet the existing corpus expectations.
- Images and OCR work without blocking typing or leaking content.
- VoiceOver, Dynamic Type, Reduce Motion, touch targets, and hardware keyboard
  behavior pass review.
- Every supported language fits at compact widths.
- Privacy policy, App Privacy answers, permissions, metadata, screenshots, and
  review notes describe the shipped behavior accurately.
- The macOS Debug and Release builds and full regression suite still pass.

Implementation began after this architecture and milestone order were accepted.
The first vertical slice shares existing core files through explicit target
membership, keeping the submitted Mac target structurally unchanged. Extraction
into `PinadayCore` remains a later milestone after parity tests cover the iOS
editor and sync paths.
