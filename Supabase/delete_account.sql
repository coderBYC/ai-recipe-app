-- Ensure dependent user tables clean up automatically when auth.users row is deleted.
-- Run this in Supabase SQL editor after verifying your schema.

-- Example profiles table FK:
-- alter table public.profiles
--   add constraint profiles_id_fkey
--   foreign key (id) references auth.users(id) on delete cascade;

-- Example import_jobs with text user_id:
-- If your import_jobs.user_id is text, you cannot FK to auth.users directly.
-- Prefer migrating it to uuid for referential integrity:
--
-- alter table public.import_jobs
--   alter column user_id type uuid using user_id::uuid;
--
-- alter table public.import_jobs
--   add constraint import_jobs_user_id_fkey
--   foreign key (user_id) references auth.users(id) on delete cascade;

-- If migration to uuid is not possible yet, use a trigger cleanup fallback:
create or replace function public.handle_auth_user_deleted()
returns trigger
language plpgsql
security definer
as $$
begin
  delete from public.profiles where id = old.id;
  delete from public.import_jobs where user_id = old.id::text;
  return old;
end;
$$;

drop trigger if exists on_auth_user_deleted on auth.users;

create trigger on_auth_user_deleted
after delete on auth.users
for each row execute function public.handle_auth_user_deleted();
