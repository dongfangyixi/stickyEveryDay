# Future Cross-Desktop Plan

## Strategy

DailySticky should keep product behavior and storage portable while allowing each platform to use native UI technology.

The macOS app does not attempt to share UI code with Windows or Linux. Instead, future apps should share the documented JSON schema, product behavior, Markdown task-list syntax, and mutation rules.

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
