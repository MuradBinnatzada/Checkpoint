-- discussion_posts_track() is a trigger function, not an API.
--
-- 20261022165000 revokes EXECUTE on every function it makes except this one, so
-- it kept the default grant to `public`: `anon` and every signed-in member could
-- see it as /rest/v1/rpc/discussion_posts_track, as a SECURITY DEFINER function
-- (the advisor's "Public can execute" and "Signed-in users can execute"
-- warnings). Called that way it only fails ("trigger functions can only be called
-- as triggers"), but there is no reason to leave it reachable. A trigger does not
-- check EXECUTE when it fires, only when it is created, so the reply counts and
-- last-post times keep following the replies: Edge Functions write them as the
-- service role, and the SECURITY DEFINER delete functions as their owner.
--
-- The block at the end fails the migration if any SECURITY DEFINER trigger
-- function in `public` is callable by anon or signed-in members, so the next one
-- that is added without a revoke is caught here rather than by the advisor.

revoke all on function public.discussion_posts_track() from public, anon, authenticated;

do $$
declare
  fn regprocedure;
begin
  for fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.prorettype = 'pg_catalog.trigger'::regtype
  loop
    if has_function_privilege('anon', fn, 'execute')
       or has_function_privilege('authenticated', fn, 'execute') then
      raise exception '% is a SECURITY DEFINER trigger function callable by members', fn;
    end if;
  end loop;
end;
$$;
