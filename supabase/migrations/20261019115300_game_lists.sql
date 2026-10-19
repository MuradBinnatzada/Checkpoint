-- Custom lists: a member's own named lists of games ("Cozy games", "Best of
-- 2026"), in the order they choose, private or public.
--
--   game_lists        one row per list: its owner, title (1-80 characters),
--                     description (at most 500) and whether it is public
--   game_list_items   the games of a list, with their position
--
-- Who sees what: a member reads and writes their own lists. A public list (and
-- its games) is readable by every signed-in member, like a profile; a private
-- one by its owner only. Nobody else writes to it. A list holds any game of the
-- catalog, in the library or not.
--
-- Limits, so the tables can't be used as free storage: 100 lists per member,
-- 500 games per list.
--
-- Lists go with the account (on delete cascade from auth.users), so
-- delete-account needs no change. Games in lists point at the shared catalog,
-- so merge_game_into (20261016120000_unify_game_ids_on_igdb_id.sql), which folds
-- a duplicate game into another and then deletes it, now moves list entries too;
-- without that the delete would fail on them.
--
-- Deploy order: apply this migration before shipping the app build with lists.

create table if not exists public.game_lists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title       text not null,
  description text not null default '',
  is_public   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint game_lists_title_length check (char_length(btrim(title)) between 1 and 80),
  constraint game_lists_description_length check (char_length(description) <= 500)
);

create index if not exists game_lists_user_idx on public.game_lists (user_id, updated_at desc);

create table if not exists public.game_list_items (
  list_id  uuid not null references public.game_lists (id) on delete cascade,
  game_id  uuid not null references public.games (id),
  position integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (list_id, game_id)
);

create index if not exists game_list_items_game_idx on public.game_list_items (game_id);

comment on table public.game_lists is
  'A member''s named lists of games. Public ones are readable by signed-in members.';
comment on table public.game_list_items is
  'The games of a list, ordered by position.';

-- 1. Row level security -------------------------------------------------------

alter table public.game_lists enable row level security;
alter table public.game_list_items enable row level security;

drop policy if exists game_lists_select on public.game_lists;
create policy game_lists_select
  on public.game_lists
  for select
  to authenticated
  using (user_id = (select auth.uid()) or is_public);

drop policy if exists game_lists_insert_own on public.game_lists;
create policy game_lists_insert_own
  on public.game_lists
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists game_lists_update_own on public.game_lists;
create policy game_lists_update_own
  on public.game_lists
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists game_lists_delete_own on public.game_lists;
create policy game_lists_delete_own
  on public.game_lists
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- An item is as visible as its list, and only the list's owner changes it.
drop policy if exists game_list_items_select on public.game_list_items;
create policy game_list_items_select
  on public.game_list_items
  for select
  to authenticated
  using (exists (
    select 1 from public.game_lists l
    where l.id = list_id and (l.user_id = (select auth.uid()) or l.is_public)
  ));

drop policy if exists game_list_items_write_own on public.game_list_items;
create policy game_list_items_write_own
  on public.game_list_items
  for all
  to authenticated
  using (exists (
    select 1 from public.game_lists l
    where l.id = list_id and l.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.game_lists l
    where l.id = list_id and l.user_id = (select auth.uid())
  ));

revoke all on public.game_lists, public.game_list_items from anon;
revoke truncate, references, trigger on public.game_lists, public.game_list_items from authenticated;
grant select, insert, update, delete on public.game_lists, public.game_list_items to authenticated;

-- 2. Limits and bookkeeping ----------------------------------------------------

create or replace function public.game_lists_enforce_limits()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'game_lists' then
    if (select count(*) from public.game_lists where user_id = new.user_id) >= 100 then
      raise exception 'A member can have at most 100 lists.' using errcode = 'check_violation';
    end if;
  -- Not counting the game itself: reordering upserts every item of a full list.
  elsif (
    select count(*) from public.game_list_items
    where list_id = new.list_id and game_id <> new.game_id
  ) >= 500 then
    raise exception 'A list can hold at most 500 games.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists game_lists_enforce_limits on public.game_lists;
create trigger game_lists_enforce_limits
  before insert on public.game_lists
  for each row execute function public.game_lists_enforce_limits();

drop trigger if exists game_list_items_enforce_limits on public.game_list_items;
create trigger game_list_items_enforce_limits
  before insert on public.game_list_items
  for each row execute function public.game_lists_enforce_limits();

-- A list is "updated" when it or its games change, so lists sort by last edit.
create or replace function public.game_lists_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'game_lists' then
    new.updated_at := now();
    return new;
  end if;
  update public.game_lists set updated_at = now()
   where id = coalesce(new.list_id, old.list_id);
  return null;
end;
$$;

drop trigger if exists game_lists_touch on public.game_lists;
create trigger game_lists_touch
  before update on public.game_lists
  for each row execute function public.game_lists_touch();

drop trigger if exists game_list_items_touch on public.game_list_items;
create trigger game_list_items_touch
  after insert or update or delete on public.game_list_items
  for each row execute function public.game_lists_touch();

-- 3. Merging duplicate games moves list entries -------------------------------
-- The same function as in 20261016120000_unify_game_ids_on_igdb_id.sql, plus the
-- list items: a list that already has the target game drops the duplicate,
-- others point at the target.
create or replace function public.merge_game_into(from_id uuid, into_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  from_steam bigint;
begin
  if from_id is null or into_id is null or from_id = into_id then
    return;
  end if;
  if not exists (select 1 from games where id = from_id) then
    return;
  end if;
  if not exists (select 1 from games where id = into_id) then
    raise exception 'merge_game_into: target game % does not exist', into_id;
  end if;

  select steam_app_id into from_steam from games where id = from_id;

  update user_games t
     set hours_played   = greatest(coalesce(t.hours_played, 0), coalesce(f.hours_played, 0)),
         status         = case when coalesce(f.hours_played, 0) > coalesce(t.hours_played, 0)
                               then f.status else t.status end,
         played_on      = case when coalesce(f.hours_played, 0) > coalesce(t.hours_played, 0)
                               then coalesce(f.played_on, t.played_on)
                               else coalesce(t.played_on, f.played_on) end,
         rating         = coalesce(nullif(t.rating, 0), f.rating, t.rating),
         purchase_price = coalesce(nullif(t.purchase_price, 0), f.purchase_price, t.purchase_price),
         is_favorite    = coalesce(t.is_favorite, false) or coalesce(f.is_favorite, false),
         date_added     = least(t.date_added, f.date_added),
         achievements   = coalesce(t.achievements, f.achievements)
    from user_games f
   where t.game_id = into_id
     and f.game_id = from_id
     and f.user_id = t.user_id;

  delete from user_games f
   using user_games t
   where f.game_id = from_id
     and t.game_id = into_id
     and t.user_id = f.user_id;

  update user_games set game_id = into_id where game_id = from_id;
  update log_entries set game_id = into_id where game_id = from_id;

  delete from game_list_items f
   using game_list_items t
   where f.game_id = from_id
     and t.game_id = into_id
     and t.list_id = f.list_id;
  update game_list_items set game_id = into_id where game_id = from_id;

  delete from games where id = from_id;

  if from_steam is not null then
    update games set steam_app_id = from_steam
     where id = into_id and steam_app_id is null;
  end if;
end;
$$;

revoke all on function public.merge_game_into(uuid, uuid) from public, anon, authenticated;
grant execute on function public.merge_game_into(uuid, uuid) to service_role;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  tbl text;
begin
  foreach tbl in array array['game_lists', 'game_list_items'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = tbl and c.relrowsecurity
    ) then
      raise exception 'Row level security is not enabled on public.%', tbl;
    end if;
    if has_table_privilege('anon', 'public.' || tbl, 'select') then
      raise exception 'anon can read public.%', tbl;
    end if;
  end loop;
end;
$$;
