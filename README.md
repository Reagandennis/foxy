# Foxy

Foxy is a Flutter productivity app focused on fast capture and daily execution:
- Rich notes with pinning, media clips, and realtime sync
- Tasks with subtasks, media attachments, links, reminders, and local notifications
- Calendar view powered by created tasks
- Supabase auth + secure per-user data/storage policies

This repository is open to contributions from Flutter, Supabase, and product-minded developers.

## Table Of Contents
- [Why Foxy](#why-foxy)
- [Current Feature Set](#current-feature-set)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Local Development Setup](#local-development-setup)
- [Supabase Setup](#supabase-setup)
- [Environment Variables](#environment-variables)
- [Run, Analyze, Test](#run-analyze-test)
- [Data Model Notes](#data-model-notes)
- [Notifications](#notifications)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Roadmap Ideas](#roadmap-ideas)

## Why Foxy
Foxy is designed for personal productivity workflows that require:
- Quick note capture with structure, not just plain text
- Task planning with reminders and rich context
- Tight feedback loop between tasks and calendar
- Secure cloud sync without exposing secrets in the client app

## Current Feature Set

### Onboarding + Auth
- 3-slide onboarding flow
- Supabase sign up, sign in, reset password
- In-app password recovery via deep link (`foxy://reset-password/`)

### Notes
- Rich-text note editing (titles, headings, paragraphs, lists, formatting)
- Pin/unpin notes and pinned-first sorting
- Insert clips:
  - Photo upload
  - Video upload
  - Web clip snapshot upload
- Clip preview for photos
- Realtime note sync with Supabase

### Tasks
- Create, edit, delete tasks
- Subtasks and link support
- Media attachments (image/video)
- Due date and reminder scheduling
- Local notifications and in-app permission controls
- Realtime task sync with Supabase

### Calendar
- Calendar month grid with per-day task counts
- Daily task list on date tap
- Uses task dates from `due_at`, fallback `reminder_at`, then `created_at`

## Tech Stack
- Flutter (stable channel)
- Supabase (`supabase_flutter`)
- Local notifications (`flutter_local_notifications`)
- File handling (`file_picker`)
- Rich text editor (`flutter_quill`)

## Project Structure
```text
lib/
  config/
    supabase_config.dart
  screens/
    auth/
    calendar/
    home/
    onboarding/
    tasks/
  services/
    task_notification_service.dart
  theme/
    app_colors.dart
```

## Local Development Setup

### 1) Clone and install dependencies
```bash
git clone <your-fork-or-repo-url>
cd foxy
flutter pub get
```

### 2) Configure local env
```bash
cp supabase.local.example.json supabase.local.json
```

Fill `supabase.local.json` with project values.

### 3) Configure Supabase redirect URL
In Supabase Auth settings, include:
- `foxy://reset-password/`

### 4) Run app
```bash
flutter run --dart-define-from-file=supabase.local.json
```

## Supabase Setup
Run the SQL file in Supabase SQL Editor:
- `supabase_notes_setup.sql`

What it sets up:
- `public.notes` table
- `public.tasks` table
- RLS policies (users can only access their own rows)
- storage buckets:
  - `note-clips`
  - `task-assets`
- storage object policies scoped by authenticated user folder
- triggers to maintain `updated_at`
- realtime publication entries for notes and tasks

Important:
- Do not put S3 access keys in the mobile app.
- Use only:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
- Enforce security with Supabase Auth + RLS + Storage policies.

## Environment Variables
Defined in `supabase.local.example.json`:

```json
{
  "SUPABASE_URL": "https://your-project-ref.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_your_publishable_anon_key",
  "SUPABASE_CLIPS_BUCKET": "note-clips",
  "SUPABASE_TASKS_BUCKET": "task-assets",
  "SUPABASE_RESET_REDIRECT": "foxy://reset-password/"
}
```

Notes:
- `SUPABASE_CLIPS_BUCKET` defaults to `note-clips`
- `SUPABASE_TASKS_BUCKET` defaults to `task-assets`
- `SUPABASE_RESET_REDIRECT` defaults to `foxy://reset-password/`

## Run, Analyze, Test
```bash
flutter run --dart-define-from-file=supabase.local.json
flutter analyze
flutter test
```

For Android debug APK:
```bash
flutter build apk --debug --dart-define-from-file=supabase.local.json
```

## Data Model Notes

### Notes
- `title`: plain text
- `body`: plain text or rich-text payload
  - rich format stored with `__foxy_rich_v1__:` prefix
- `is_pinned`: boolean
- `clips`: JSON array with type and storage metadata

### Tasks
- `title`, `details`
- `is_completed`
- `due_at`, `reminder_at`
- `links`, `attachments`, `subtasks` (JSON arrays)

## Notifications
Local task reminders are handled by `TaskNotificationService`.

Android setup includes:
- `POST_NOTIFICATIONS`
- `RECEIVE_BOOT_COMPLETED`
- `SCHEDULE_EXACT_ALARM`
- core library desugaring enabled in `android/app/build.gradle.kts`

If notifications are not appearing:
- open Tasks page
- tap `Enable alerts`
- tap `Test alert`
- verify OS-level notification permission for Foxy

## Troubleshooting

### Upload denied or bucket errors
- Re-run `supabase_notes_setup.sql`
- Confirm both buckets exist:
  - `note-clips`
  - `task-assets`
- Confirm storage policies are present

### Cannot request notification permission
- Check Android app notification settings in OS
- Confirm manifest permissions are present
- Rebuild app after Gradle/plugin changes

### Build error about desugaring
- Ensure `isCoreLibraryDesugaringEnabled = true` and
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`
  remain in `android/app/build.gradle.kts`

### Password recovery deep link not opening app
- Confirm URL scheme `foxy` in:
  - `android/app/src/main/AndroidManifest.xml`
  - `ios/Runner/Info.plist`
- Confirm Supabase redirect URL matches exactly

## Contributing
Contributions are welcome across UI, reliability, backend safety, and docs.

### Suggested workflow
1. Fork repository
2. Create branch: `feat/<short-name>` or `fix/<short-name>`
3. Make focused changes
4. Run:
   - `flutter analyze`
   - `flutter test`
5. Open a PR with:
   - problem statement
   - implementation summary
   - testing notes
   - screenshots/GIFs for UI changes

### Contribution quality bar
- Keep UX consistent with existing theme/components
- Preserve secure defaults (no secret keys in app code)
- Maintain backward compatibility for stored data where possible
- Prefer small, reviewable PRs

## Roadmap Ideas
- Task edit from calendar tap
- Drag/drop scheduling in calendar
- Shared projects/workspaces
- Rich note templates
- Better web clip rendering and preview
- Offline-first sync conflict handling

---

If you are interested in contributing but unsure where to start, open an issue with the label `good-first-task` request and we can scope one with you.
