# Future Cross-Desktop Plan

## Strategy

DailySticky should keep product behavior and storage portable while allowing each platform to use native UI technology.

The macOS app does not attempt to share UI code with Windows or Linux. Instead, future apps should share the documented JSON schema, product behavior, Markdown task-list syntax, and mutation rules.

## Apple Platform Distribution

If DailySticky expands beyond macOS to iPhone, iPad, and Apple Watch, the primary distribution path should be the App Store rather than direct-download macOS builds.

Recommended strategy:

- Ship as a free App Store app with an optional Pro unlock.
- Use StoreKit 2 and App Store in-app purchases for paid features.
- Prefer a shared Pro entitlement across macOS, iOS, iPadOS, and watchOS so one purchase unlocks the Apple-platform family.
- Include Restore Purchases on every platform.
- Keep a direct-download macOS build optional for power users only after the App Store product is stable.
- Avoid custom license keys for the main Apple-platform flow because Apple ID purchase and restore is smoother for users.

Possible paid tiers:

- Lifetime Pro unlock for simple positioning.
- Annual Pro subscription if future features include sync, cloud-backed services, or ongoing AI/server costs.
- Free basic notes remain useful without payment.

Locked-feature UX should be gentle:

- User chooses a Pro feature.
- App shows a small native unlock sheet.
- Purchase uses StoreKit.
- App unlocks immediately after successful purchase.
- No manual license key entry in the primary flow.

## Windows

A future Windows version can be built with C# using WPF or WinUI 3.

Expected platform work:

- Native sticky window.
- Always-on-top support.
- Window frame persistence.
- Optional system tray behavior.
- Same JSON schema and date-key rules.
- Same Markdown task-list parsing and `[ ]` / `[x]` mutation behavior.

## Linux

A future Linux version can use Qt, GTK, or another native-friendly toolkit.

Expected platform work:

- Native sticky window where the desktop environment supports it.
- Best-effort always-on-top behavior.
- Window frame persistence.
- Same JSON schema and date-key rules.
- Same Markdown task-list parsing and `[ ]` / `[x]` mutation behavior.

## Optional Sync

Sync is not part of the MVP. If added later, prefer file-based sync first:

- User-selected folder.
- Dropbox, OneDrive, or iCloud Drive folder.
- Backup and restore.
- Import and export JSON.

A custom sync service should only be considered after the local file format and single-device behavior are stable.
