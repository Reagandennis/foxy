# foxy

Foxy is a simple productivity app with:
- 3-slide onboarding splash
- Supabase auth (login, sign up, reset password)
- In-app password update via recovery deep link
- Realtime notes synced across devices
- Tasks with subtasks, attachments, links, and reminders

## Run with Supabase config

Secrets are loaded from compile-time variables, not hardcoded in Dart files.

1. Copy the local template:

```bash
cp supabase.local.example.json supabase.local.json
```

2. Add your values in `supabase.local.json` (already gitignored).
   Optional:
   - `SUPABASE_CLIPS_BUCKET` (defaults to `note-clips`)
   - `SUPABASE_TASKS_BUCKET` (defaults to `task-assets`)

3. Ensure your Supabase project has this redirect URL in Auth settings:

`foxy://reset-password/`

4. Run:

```bash
flutter run --dart-define-from-file=supabase.local.json
```

## Supabase notes setup

1. Open Supabase SQL editor.
2. Run the SQL from `supabase_notes_setup.sql`.
3. Confirm Realtime is enabled for `public.notes` (the script adds it).
4. Log in on two devices with the same account and edit notes to verify live sync.

This setup creates:
- `public.notes` table
- `public.tasks` table
- secure `note-clips` storage bucket policies (per-user file access)
- secure `task-assets` storage bucket policies (per-user file access)
- Row Level Security so each user accesses only their own notes/tasks
- Realtime replication for notes and tasks changes

Do not put S3 access keys in the app. The mobile client should only use
`SUPABASE_URL` + `SUPABASE_ANON_KEY` and authenticated storage policies.
