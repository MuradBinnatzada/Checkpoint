-- Achievement totals of a member, small enough to show on every profile.
--
-- public_achievement_summary (20261017140000) is one row per game and is fetched
-- only when a viewer asks for it. A profile now also shows ONE number up front: how
-- many achievements the member has unlocked, out of how many, over every game that
-- has achievements stored. It is counted in SQL like the summary: no achievement
-- rows leave the database, only a single row of four integers.
--
-- Same rules as the other two achievement functions: a signed-in caller only (the
-- grants keep anon out), SECURITY DEFINER because RLS works on rows and would hand
-- over the `achievements` JSONB with them, and nothing but counts in the result.
-- Unlike the summary this has no LIMIT: it covers every game, not the first 100.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- Without it the profile falls back to the "View Achievements" button.

create or replace function public.public_achievement_totals(target_user uuid)
returns table (unlocked integer, total integer, games integer, completed_games integer)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(s.unlocked), 0)::integer,
         coalesce(sum(s.total), 0)::integer,
         count(*)::integer,
         (count(*) filter (where s.unlocked = s.total))::integer
  from public.user_games ug
  cross join lateral (
    select count(*) filter (where a ->> 'unlocked' = 'true')::integer as unlocked,
           count(*)::integer as total
    from jsonb_array_elements(
      case when jsonb_typeof(ug.achievements) = 'array' then ug.achievements else '[]'::jsonb end
    ) as a
  ) s
  where ug.user_id = target_user
    and (select auth.uid()) is not null
    and s.total > 0
$$;

comment on function public.public_achievement_totals(uuid) is
  'Unlocked / total achievements and game counts of a member, for the profile page. Counts only, never the achievements themselves.';

revoke all on function public.public_achievement_totals(uuid) from public, anon, authenticated;
grant execute on function public.public_achievement_totals(uuid) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if has_function_privilege('anon', 'public.public_achievement_totals(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.public_achievement_totals(uuid)', 'execute') then
    raise exception 'public_achievement_totals has the wrong grants';
  end if;
end;
$$;
