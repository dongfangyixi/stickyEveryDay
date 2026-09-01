# Pinaday Data Migrations

Pinaday's local JSON file is user data. A schema change must never silently replace it with an empty file.

## Adding a Schema Version

1. Increase `AppData.currentSchemaVersion` by exactly one.
2. Add one sequential `AppDataMigrationStep` to `AppDataMigrationPlan.production`.
3. Make the step idempotent at the field level: preserve existing values and only add or transform what the new schema requires.
4. Keep backward-compatible `Codable` defaults as a second line of defense.
5. Add a realistic fixture for the previous version, including Markdown, attachment references, and settings.
6. Test every intermediate version through to the current version.

## Safety Contract

- Parse and migrate in memory first.
- Decode the completed document as the current `AppData` model before touching the live file.
- Copy the exact original bytes to a timestamped pre-migration backup.
- Replace the live file atomically only after validation and backup succeed.
- If reading, decoding, or migration fails, preserve the live file and block writes for the rest of that store session.
- Never recover from a migration failure by creating or saving empty data.
- Attachment files are not modified by JSON migrations unless a migration explicitly owns an attachment change.

## Release Checklist

- Run migration fixtures and the full unit-test suite.
- Launch against a copy of a real previous-version Application Support directory.
- Verify notes, task states, Markdown, image rendering, settings, and search.
- Verify the pre-migration backup can be decoded by the previous app version.
- Test the update through TestFlight before App Store rollout.
- Prefer phased release for any build that changes persisted data.
