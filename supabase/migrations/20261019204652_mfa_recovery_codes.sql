-- Backup codes for two-factor authentication: a way back in for a member who
-- lost their authenticator app.
--
-- With two-factor on (20261019135155_require_mfa.sql), the app asks for the
-- authenticator app's code after every sign-in and the server refuses a session
-- that hasn't entered one. A member without the app had no way past that but
-- asking the owner to remove the factor in the dashboard.
--
-- 1. public.mfa_recovery_codes: one row per backup code. The mfa-recovery Edge
--    Function writes and reads it with the service role:
--      generate  from a session that entered its code (aal2): replaces the
--                member's codes with 10 new random ones and answers them, once.
--                Only their SHA-256 hashes (of the member's id and the code)
--                are kept, so this table can't hand a code back.
--      redeem    from a session that only signed in (aal1): a code that matches
--                an unused row is marked used, every MFA factor of the member is
--                deleted (two-factor is off then) and their other codes go. The
--                app refreshes its session, which no longer owes a code, and
--                suggests turning two-factor on again.
--    Each code works once. Turning two-factor on again needs new codes (the
--    setup makes them); the old ones are gone.
--
-- 2. RLS on and no policies, and no privileges for public, anon or
--    authenticated: members can't read, count or change their codes, not even
--    with an aal2 session. Only the service role (the function) uses the table.
--    The rows go with the account (on delete cascade).
--
-- The owner can still let a member in by hand: dashboard > Authentication >
-- Users > the member > delete the authenticator factor.
--
-- Deploy order: this migration, then the Edge Functions (deploy-supabase.yml does
-- both), then the app. App builds from before this change don't offer backup
-- codes; nothing else changes for them.

create table if not exists public.mfa_recovery_codes (
  user_id    uuid not null references auth.users (id) on delete cascade,
  -- Lowercase hex SHA-256 (supabase/functions/_shared/recovery_codes.ts).
  code_hash  text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  used_at    timestamptz,
  primary key (user_id, code_hash)
);

comment on table public.mfa_recovery_codes is
  'Two-factor backup codes, as SHA-256 hashes; each works once (mfa-recovery Edge Function). Service role only.';

alter table public.mfa_recovery_codes enable row level security;
revoke all on public.mfa_recovery_codes from public, anon, authenticated;
grant select, insert, update, delete on public.mfa_recovery_codes to service_role;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  op text;
  role_name text;
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'mfa_recovery_codes' and c.relrowsecurity
  ) then
    raise exception 'Row level security is not enabled on public.mfa_recovery_codes';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mfa_recovery_codes'
  ) then
    raise exception 'public.mfa_recovery_codes must have no policies (service role only)';
  end if;

  foreach role_name in array array['anon', 'authenticated'] loop
    foreach op in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      if has_table_privilege(role_name, 'public.mfa_recovery_codes', op) then
        raise exception '% can still % public.mfa_recovery_codes', role_name, op;
      end if;
    end loop;
  end loop;

  foreach op in array array['select', 'insert', 'update', 'delete'] loop
    if not has_table_privilege('service_role', 'public.mfa_recovery_codes', op) then
      raise exception 'The service role must be able to % public.mfa_recovery_codes', op;
    end if;
  end loop;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.mfa_recovery_codes'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass
      and confdeltype = 'c'
  ) then
    raise exception 'public.mfa_recovery_codes must go with the account (on delete cascade)';
  end if;
end;
$$;
