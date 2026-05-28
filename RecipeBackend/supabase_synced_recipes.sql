-- Run in Supabase SQL editor (once per project).
-- Client table for Pro recipe cloud sync (`SyncService.tableName` = synced_recipes).

create table if not exists public.synced_recipes (
  id text primary key,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  user_id uuid not null references auth.users (id) on delete cascade,
  data jsonb not null
);

create index if not exists synced_recipes_user_id_updated_at_idx
  on public.synced_recipes (user_id, updated_at);

alter table public.synced_recipes enable row level security;

create policy "synced_recipes_select_own"
  on public.synced_recipes
  for select
  using (auth.uid() = user_id);

create policy "synced_recipes_insert_own"
  on public.synced_recipes
  for insert
  with check (auth.uid() = user_id);

create policy "synced_recipes_update_own"
  on public.synced_recipes
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "synced_recipes_delete_own"
  on public.synced_recipes
  for delete
  using (auth.uid() = user_id);
