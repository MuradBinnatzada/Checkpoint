-- Play sessions can be edited: hours, platform, note and when it was played.
--
-- 20261017120000_enforce_row_ownership.sql gave log_entries no permissive UPDATE
-- policy, because the app only ever inserted and deleted sessions. Editing one (a
-- typo in the hours, a session logged on the wrong day) needs it. The restrictive
-- log_entries_update_own_only from that migration still applies, so a member can
-- only change their own sessions and can't hand one to someone else.
--
-- The value limits from 20261019013500_value_limits_and_atomic_deletes.sql apply
-- to an edited session as to a new one: more than 0 and at most 100 000 hours, a
-- note of at most 1 000 characters, and a date no more than a day ahead.
--
-- Deploy order: apply this migration before shipping the app build that edits
-- sessions. Before it, an edit is refused and the app puts the session back.

drop policy if exists log_entries_update_own on public.log_entries;
create policy log_entries_update_own
  on public.log_entries
  as permissive
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant update on public.log_entries to authenticated;

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'log_entries'
      and policyname = 'log_entries_update_own' and permissive = 'PERMISSIVE'
  ) or not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'log_entries'
      and cmd = 'UPDATE' and permissive = 'RESTRICTIVE'
  ) then
    raise exception 'log_entries needs both its own-row UPDATE policies';
  end if;
end;
$$;
