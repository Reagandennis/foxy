create extension if not exists pgcrypto;

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  body text not null default '',
  is_pinned boolean not null default false,
  clips jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.notes
  add column if not exists is_pinned boolean not null default false;

alter table public.notes
  add column if not exists clips jsonb not null default '[]'::jsonb;

create index if not exists notes_user_updated_idx
  on public.notes (user_id, updated_at desc);

create index if not exists notes_user_pinned_updated_idx
  on public.notes (user_id, is_pinned desc, updated_at desc);

alter table public.notes enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notes'
      and policyname = 'notes_select_own'
  ) then
    create policy notes_select_own
      on public.notes
      for select
      using (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notes'
      and policyname = 'notes_insert_own'
  ) then
    create policy notes_insert_own
      on public.notes
      for insert
      with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notes'
      and policyname = 'notes_update_own'
  ) then
    create policy notes_update_own
      on public.notes
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notes'
      and policyname = 'notes_delete_own'
  ) then
    create policy notes_delete_own
      on public.notes
      for delete
      using (auth.uid() = user_id);
  end if;
end
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists set_notes_updated_at on public.notes;

create trigger set_notes_updated_at
before update on public.notes
for each row
execute function public.set_updated_at();

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  details text not null default '',
  is_completed boolean not null default false,
  due_at timestamptz,
  reminder_at timestamptz,
  links jsonb not null default '[]'::jsonb,
  attachments jsonb not null default '[]'::jsonb,
  subtasks jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.tasks
  add column if not exists details text not null default '';

alter table public.tasks
  add column if not exists is_completed boolean not null default false;

alter table public.tasks
  add column if not exists due_at timestamptz;

alter table public.tasks
  add column if not exists reminder_at timestamptz;

alter table public.tasks
  add column if not exists links jsonb not null default '[]'::jsonb;

alter table public.tasks
  add column if not exists attachments jsonb not null default '[]'::jsonb;

alter table public.tasks
  add column if not exists subtasks jsonb not null default '[]'::jsonb;

create index if not exists tasks_user_updated_idx
  on public.tasks (user_id, updated_at desc);

create index if not exists tasks_user_state_due_idx
  on public.tasks (user_id, is_completed asc, due_at asc, updated_at desc);

alter table public.tasks enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tasks'
      and policyname = 'tasks_select_own'
  ) then
    create policy tasks_select_own
      on public.tasks
      for select
      using (auth.uid() = user_id);
  end if;


  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tasks'
      and policyname = 'tasks_insert_own'
  ) then
    create policy tasks_insert_own
      on public.tasks
      for insert
      with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tasks'
      and policyname = 'tasks_update_own'
  ) then
    create policy tasks_update_own
      on public.tasks
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tasks'
      and policyname = 'tasks_delete_own'
  ) then
    create policy tasks_delete_own
      on public.tasks
      for delete
      using (auth.uid() = user_id);
  end if;
end
$$;

drop trigger if exists set_tasks_updated_at on public.tasks;

create trigger set_tasks_updated_at
before update on public.tasks
for each row
execute function public.set_updated_at();

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.notes to authenticated;
grant select, insert, update, delete on table public.tasks to authenticated;

insert into storage.buckets (id, name, public)
values ('note-clips', 'note-clips', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('task-assets', 'task-assets', false)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'notes_clips_select_own'
  ) then
    create policy notes_clips_select_own
      on storage.objects
      for select
      to authenticated
      using (
        bucket_id = 'note-clips'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'notes_clips_insert_own'
  ) then
    create policy notes_clips_insert_own
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'note-clips'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'notes_clips_update_own'
  ) then
    create policy notes_clips_update_own
      on storage.objects
      for update
      to authenticated
      using (
        bucket_id = 'note-clips'
        and (storage.foldername(name))[1] = auth.uid()::text
      )
      with check (
        bucket_id = 'note-clips'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'notes_clips_delete_own'
  ) then
    create policy notes_clips_delete_own
      on storage.objects
      for delete
      to authenticated
      using (
        bucket_id = 'note-clips'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'task_assets_select_own'
  ) then
    create policy task_assets_select_own
      on storage.objects
      for select
      to authenticated
      using (
        bucket_id = 'task-assets'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'task_assets_insert_own'
  ) then
    create policy task_assets_insert_own
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'task-assets'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'task_assets_update_own'
  ) then
    create policy task_assets_update_own
      on storage.objects
      for update
      to authenticated
      using (
        bucket_id = 'task-assets'
        and (storage.foldername(name))[1] = auth.uid()::text
      )
      with check (
        bucket_id = 'task-assets'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'task_assets_delete_own'
  ) then
    create policy task_assets_delete_own
      on storage.objects
      for delete
      to authenticated
      using (
        bucket_id = 'task-assets'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notes'
  ) then
    alter publication supabase_realtime add table public.notes;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tasks'
  ) then
    alter publication supabase_realtime add table public.tasks;
  end if;
end
$$;
