-- Discussions: boards the app ships with, threads members start on them (about a
-- game or not), replies, reports, and blocking a member.
--
--   discussion_boards     the pre-made boards (General, What should I play? ...).
--                         Seeded below; the owner adds or renames them here.
--   discussion_threads    a thread: a title and an opening text, on a board and
--                         optionally about a game. Keeps its reply count and the
--                         time of its last post (triggers).
--   discussion_posts      the replies to a thread, oldest first. Flat: a reply
--                         answers the thread, not another reply.
--   discussion_reports    a member's report of a thread or a reply. Write only:
--                         nothing in the app reads it back, the reports are for
--                         whoever moderates (the Supabase dashboard). What the
--                         member reported is left out for them.
--   discussion_blocks     a member blocking another: neither their threads nor
--                         their replies show for the blocker any more.
--
-- Who writes what. Members never write threads or replies themselves: the
-- `discussions` Edge Function does, with the service role, after it has counted
-- the member's rate limit, refused the worst words and checked the lengths
-- (supabase/functions/_shared/discussions.ts). The tables have no privileges for
-- members at all, so nothing can go around it. A member deletes their own thread
-- or reply with delete_discussion_thread / delete_discussion_post, reports with an
-- insert into discussion_reports and blocks with an insert into discussion_blocks
-- (both own rows only), and reads through the functions below. Those run as their
-- owner (SECURITY DEFINER), name every column they return (never add email,
-- steam_id or the like) and answer signed-in members who passed two-factor only
-- (20261019135155_require_mfa.sql).
--
-- Moderating, from the dashboard: delete a row to remove a thread or reply; set
-- `locked` on a thread to stop replies, `pinned` to keep it on top of its board.
--
-- Deploy order: apply this migration, deploy the `discussions` function, then ship
-- the app build. Until then the Discussions tab shows nothing and posting fails.

-- 1. Boards -------------------------------------------------------------------

create table if not exists public.discussion_boards (
  id          text primary key
    constraint discussion_boards_id_check check (id ~ '^[a-z0-9-]{2,30}$'),
  title       text not null
    constraint discussion_boards_title_check check (char_length(title) between 1 and 60),
  description text not null default ''
    constraint discussion_boards_description_check check (char_length(description) <= 200),
  position    integer not null default 0
);

comment on table public.discussion_boards is
  'The pre-made discussion boards. English title and description; the app shows its own translation of the ones it knows by id.';

insert into public.discussion_boards (id, title, description, position) values
  ('general',         'General',              'Anything about games and gaming.',                     10),
  ('games',           'Game talk',            'Talk about one game: its story, builds, bosses, tips.', 20),
  ('recommendations', 'What should I play?',  'Ask for a game, or suggest one.',                      30),
  ('help',            'Help & tips',          'Stuck? Ask, and share what helped you.',               40),
  ('news',            'News talk',            'What did you read today?',                             50),
  ('off-topic',       'Off-topic',            'Everything else, kept friendly.',                      60),
  ('feedback',        'Checkpoint feedback',  'Ideas, bugs and questions about the app.',             70)
on conflict (id) do nothing;

-- 2. Threads and replies ---------------------------------------------------------

create table if not exists public.discussion_threads (
  id           uuid primary key default gen_random_uuid(),
  board_id     text not null references public.discussion_boards (id),
  -- The game the thread is about; kept (without it) when the game leaves the catalog.
  game_id      uuid references public.games (id) on delete set null,
  author_id    uuid not null references auth.users (id) on delete cascade,
  title        text not null
    constraint discussion_threads_title_check check (char_length(title) between 3 and 120),
  body         text not null
    constraint discussion_threads_body_check check (char_length(body) between 1 and 3000),
  created_at   timestamptz not null default now(),
  -- Kept by the triggers below: when the thread was last written in, and how many replies it has.
  last_post_at timestamptz not null default now(),
  reply_count  integer not null default 0,
  pinned       boolean not null default false,
  locked       boolean not null default false
);

create index if not exists discussion_threads_board_idx
  on public.discussion_threads (board_id, pinned desc, last_post_at desc);
create index if not exists discussion_threads_latest_idx
  on public.discussion_threads (last_post_at desc);
create index if not exists discussion_threads_game_idx
  on public.discussion_threads (game_id, last_post_at desc) where game_id is not null;
create index if not exists discussion_threads_author_idx
  on public.discussion_threads (author_id);

create table if not exists public.discussion_posts (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references public.discussion_threads (id) on delete cascade,
  author_id  uuid not null references auth.users (id) on delete cascade,
  body       text not null
    constraint discussion_posts_body_check check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists discussion_posts_thread_idx
  on public.discussion_posts (thread_id, created_at, id);
create index if not exists discussion_posts_author_idx
  on public.discussion_posts (author_id);

-- A thread's reply count and the time of its last post follow its replies.
create or replace function public.discussion_posts_track()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid := coalesce(new.thread_id, old.thread_id);
begin
  update public.discussion_threads t
     set reply_count = (select count(*) from public.discussion_posts p where p.thread_id = target),
         last_post_at = coalesce(
           (select max(p.created_at) from public.discussion_posts p where p.thread_id = target),
           t.created_at)
   where t.id = target;
  return null;
end;
$$;

drop trigger if exists discussion_posts_track on public.discussion_posts;
create trigger discussion_posts_track
  after insert or delete on public.discussion_posts
  for each row execute function public.discussion_posts_track();

alter table public.discussion_boards enable row level security;
alter table public.discussion_threads enable row level security;
alter table public.discussion_posts enable row level security;

-- Boards are readable by signed-in members; threads and replies only through the
-- functions below. Nobody but the service role writes any of them.
drop policy if exists discussion_boards_select on public.discussion_boards;
create policy discussion_boards_select
  on public.discussion_boards
  for select
  to authenticated
  using ((select public.mfa_satisfied()));

revoke all on public.discussion_boards from public, anon, authenticated;
revoke all on public.discussion_threads from public, anon, authenticated;
revoke all on public.discussion_posts from public, anon, authenticated;
grant select on public.discussion_boards to authenticated;

-- 3. Reports and blocks ---------------------------------------------------------

create table if not exists public.discussion_reports (
  reporter_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  thread_id   uuid references public.discussion_threads (id) on delete cascade,
  post_id     uuid references public.discussion_posts (id) on delete cascade,
  reason      text not null
    constraint discussion_reports_reason_check
    check (reason in ('spam', 'abuse', 'other')),
  created_at  timestamptz not null default now(),
  -- A report is about a thread or a reply, not both and not neither.
  constraint discussion_reports_one_target
    check ((thread_id is null) <> (post_id is null))
);

-- One report per member and thing reported: reporting again changes nothing.
create unique index if not exists discussion_reports_thread_once
  on public.discussion_reports (reporter_id, thread_id) where thread_id is not null;
create unique index if not exists discussion_reports_post_once
  on public.discussion_reports (reporter_id, post_id) where post_id is not null;

comment on table public.discussion_reports is
  'A member''s report of a thread or a reply. Write only for members: moderators read it in the dashboard.';

create table if not exists public.discussion_blocks (
  blocker_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  blocked_id uuid not null
    references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint discussion_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists discussion_blocks_blocked_idx
  on public.discussion_blocks (blocked_id);

comment on table public.discussion_blocks is
  'A member blocking another one in the discussions: the blocked member''s threads and replies are left out for the blocker. Own rows only.';

alter table public.discussion_reports enable row level security;
alter table public.discussion_blocks enable row level security;

-- A member reports as themselves, and reads back only their own reports (an
-- insert on conflict needs to see the row it would conflict with).
drop policy if exists discussion_reports_select_own on public.discussion_reports;
create policy discussion_reports_select_own
  on public.discussion_reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

drop policy if exists discussion_reports_insert_own on public.discussion_reports;
create policy discussion_reports_insert_own
  on public.discussion_reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));

drop policy if exists discussion_reports_aal2_if_mfa on public.discussion_reports;
create policy discussion_reports_aal2_if_mfa
  on public.discussion_reports
  as restrictive
  for all to authenticated
  using ((select public.mfa_satisfied()))
  with check ((select public.mfa_satisfied()));

revoke all on public.discussion_reports from public, anon, authenticated;
grant select, insert on public.discussion_reports to authenticated;

drop policy if exists discussion_blocks_select_own on public.discussion_blocks;
create policy discussion_blocks_select_own
  on public.discussion_blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

drop policy if exists discussion_blocks_insert_own on public.discussion_blocks;
create policy discussion_blocks_insert_own
  on public.discussion_blocks
  for insert to authenticated
  with check (blocker_id = (select auth.uid()));

drop policy if exists discussion_blocks_delete_own on public.discussion_blocks;
create policy discussion_blocks_delete_own
  on public.discussion_blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));

drop policy if exists discussion_blocks_aal2_if_mfa on public.discussion_blocks;
create policy discussion_blocks_aal2_if_mfa
  on public.discussion_blocks
  as restrictive
  for all to authenticated
  using ((select public.mfa_satisfied()))
  with check ((select public.mfa_satisfied()));

revoke all on public.discussion_blocks from public, anon, authenticated;
grant select, insert, delete on public.discussion_blocks to authenticated;

-- 4. What the Discussions tab reads -----------------------------------------------

-- The boards with how many threads each has and when it was last written in.
create or replace function public.discussion_boards_overview()
returns table (
  id text,
  title text,
  description text,
  board_position integer,
  thread_count integer,
  latest_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select b.id, b.title, b.description, b.position,
         count(t.id)::integer,
         max(t.last_post_at)
  from public.discussion_boards b
  left join public.discussion_threads t
    on t.board_id = b.id
   and not exists (
     select 1 from public.discussion_blocks k
     where k.blocker_id = (select auth.uid()) and k.blocked_id = t.author_id)
  where (select auth.uid()) is not null
    and (select public.mfa_satisfied())
  group by b.id, b.title, b.description, b.position
  order by b.position, b.id
$$;

-- One page of threads, the ones written in last first (pinned ones first on a
-- board): those of [board] (all boards when null) and those about [about_game]
-- (any when null). Left out: threads of members the caller blocked, and threads
-- the caller reported. [preview] is the start of the opening text.
create or replace function public.discussion_threads_page(
  board text default null,
  about_game uuid default null,
  page_size integer default 20,
  page_offset integer default 0
)
returns table (
  id uuid,
  board_id text,
  game_id uuid,
  game_title text,
  game_igdb_id integer,
  game_cover_url text,
  title text,
  preview text,
  reply_count integer,
  created_at timestamptz,
  last_post_at timestamptz,
  pinned boolean,
  locked boolean,
  author_id uuid,
  author_handle text,
  author_name text,
  author_avatar_url text,
  author_avatar_frame text,
  author_showcase text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.board_id, t.game_id,
         g.title::text, g.igdb_id::integer, g.cover_url::text,
         t.title, left(t.body, 200), t.reply_count, t.created_at, t.last_post_at,
         t.pinned, t.locked,
         p.id, p.handle::text, p.display_name::text, p.avatar_url::text,
         p.avatar_frame::text, p.showcased_milestones
  from public.discussion_threads t
  join public.profiles p on p.id = t.author_id
  left join public.games g on g.id = t.game_id
  where (select auth.uid()) is not null
    and (select public.mfa_satisfied())
    and (board is null or t.board_id = board)
    and (about_game is null or t.game_id = about_game)
    and not exists (
      select 1 from public.discussion_blocks k
      where k.blocker_id = (select auth.uid()) and k.blocked_id = t.author_id)
    and not exists (
      select 1 from public.discussion_reports r
      where r.reporter_id = (select auth.uid()) and r.thread_id = t.id)
  order by (board is not null and t.pinned) desc, t.last_post_at desc, t.id
  limit least(greatest(coalesce(page_size, 20), 1), 50)
  offset greatest(coalesce(page_offset, 0), 0)
$$;

-- One thread with its whole opening text; no row when it is gone, or the caller
-- blocked or reported it.
create or replace function public.discussion_thread(thread uuid)
returns table (
  id uuid,
  board_id text,
  game_id uuid,
  game_title text,
  game_igdb_id integer,
  game_cover_url text,
  title text,
  body text,
  reply_count integer,
  created_at timestamptz,
  last_post_at timestamptz,
  pinned boolean,
  locked boolean,
  author_id uuid,
  author_handle text,
  author_name text,
  author_avatar_url text,
  author_avatar_frame text,
  author_showcase text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.board_id, t.game_id,
         g.title::text, g.igdb_id::integer, g.cover_url::text,
         t.title, t.body, t.reply_count, t.created_at, t.last_post_at,
         t.pinned, t.locked,
         p.id, p.handle::text, p.display_name::text, p.avatar_url::text,
         p.avatar_frame::text, p.showcased_milestones
  from public.discussion_threads t
  join public.profiles p on p.id = t.author_id
  left join public.games g on g.id = t.game_id
  where t.id = thread
    and (select auth.uid()) is not null
    and (select public.mfa_satisfied())
    and not exists (
      select 1 from public.discussion_blocks k
      where k.blocker_id = (select auth.uid()) and k.blocked_id = t.author_id)
    and not exists (
      select 1 from public.discussion_reports r
      where r.reporter_id = (select auth.uid()) and r.thread_id = t.id)
$$;

-- One page of a thread's replies, oldest first, without those of members the
-- caller blocked and those the caller reported.
create or replace function public.discussion_posts_page(
  thread uuid,
  page_size integer default 30,
  page_offset integer default 0
)
returns table (
  id uuid,
  thread_id uuid,
  body text,
  created_at timestamptz,
  author_id uuid,
  author_handle text,
  author_name text,
  author_avatar_url text,
  author_avatar_frame text,
  author_showcase text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select x.id, x.thread_id, x.body, x.created_at,
         p.id, p.handle::text, p.display_name::text, p.avatar_url::text,
         p.avatar_frame::text, p.showcased_milestones
  from public.discussion_posts x
  join public.profiles p on p.id = x.author_id
  where x.thread_id = thread
    and (select auth.uid()) is not null
    and (select public.mfa_satisfied())
    and not exists (
      select 1 from public.discussion_blocks k
      where k.blocker_id = (select auth.uid()) and k.blocked_id = x.author_id)
    and not exists (
      select 1 from public.discussion_reports r
      where r.reporter_id = (select auth.uid()) and r.post_id = x.id)
  order by x.created_at, x.id
  limit least(greatest(coalesce(page_size, 30), 1), 50)
  offset greatest(coalesce(page_offset, 0), 0)
$$;

-- The members the caller blocked, newest block first, for the Blocked members screen.
create or replace function public.my_discussion_blocks()
returns table (
  id uuid,
  handle text,
  display_name text,
  avatar_url text,
  avatar_frame text,
  showcased_milestones text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.handle::text, p.display_name::text, p.avatar_url::text,
         p.avatar_frame::text, p.showcased_milestones
  from public.discussion_blocks k
  join public.profiles p on p.id = k.blocked_id
  where k.blocker_id = (select auth.uid())
    and (select auth.uid()) is not null
    and (select public.mfa_satisfied())
  order by k.created_at desc, p.id
$$;

-- 5. Deleting your own -----------------------------------------------------------

-- A member's own thread, with its replies and the reports about it.
create or replace function public.delete_discussion_thread(thread uuid)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  with removed as (
    delete from public.discussion_threads t
    where t.id = thread
      and t.author_id = (select auth.uid())
      and (select public.mfa_satisfied())
    returning 1
  )
  select exists (select 1 from removed)
$$;

-- A member's own reply.
create or replace function public.delete_discussion_post(post uuid)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  with removed as (
    delete from public.discussion_posts x
    where x.id = post
      and x.author_id = (select auth.uid())
      and (select public.mfa_satisfied())
    returning 1
  )
  select exists (select 1 from removed)
$$;

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.discussion_boards_overview() from public, anon, authenticated;
revoke all on function public.discussion_threads_page(text, uuid, integer, integer) from public, anon, authenticated;
revoke all on function public.discussion_thread(uuid) from public, anon, authenticated;
revoke all on function public.discussion_posts_page(uuid, integer, integer) from public, anon, authenticated;
revoke all on function public.my_discussion_blocks() from public, anon, authenticated;
revoke all on function public.delete_discussion_thread(uuid) from public, anon, authenticated;
revoke all on function public.delete_discussion_post(uuid) from public, anon, authenticated;
grant execute on function public.discussion_boards_overview() to authenticated;
grant execute on function public.discussion_threads_page(text, uuid, integer, integer) to authenticated;
grant execute on function public.discussion_thread(uuid) to authenticated;
grant execute on function public.discussion_posts_page(uuid, integer, integer) to authenticated;
grant execute on function public.my_discussion_blocks() to authenticated;
grant execute on function public.delete_discussion_thread(uuid) to authenticated;
grant execute on function public.delete_discussion_post(uuid) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  fn regprocedure;
begin
  foreach fn in array array[
    'public.discussion_boards_overview()'::regprocedure,
    'public.discussion_threads_page(text, uuid, integer, integer)'::regprocedure,
    'public.discussion_thread(uuid)'::regprocedure,
    'public.discussion_posts_page(uuid, integer, integer)'::regprocedure,
    'public.my_discussion_blocks()'::regprocedure,
    'public.delete_discussion_thread(uuid)'::regprocedure,
    'public.delete_discussion_post(uuid)'::regprocedure
  ] loop
    if not (select prosecdef from pg_proc where oid = fn) then
      raise exception '% must be SECURITY DEFINER', fn;
    end if;
    if has_function_privilege('anon', fn, 'execute')
       or not has_function_privilege('authenticated', fn, 'execute') then
      raise exception '% has the wrong grants', fn;
    end if;
  end loop;

  -- Members write threads and replies through the Edge Function only.
  if has_table_privilege('authenticated', 'public.discussion_threads', 'select')
     or has_table_privilege('authenticated', 'public.discussion_threads', 'insert')
     or has_table_privilege('authenticated', 'public.discussion_posts', 'select')
     or has_table_privilege('authenticated', 'public.discussion_posts', 'insert')
     or has_table_privilege('anon', 'public.discussion_boards', 'select')
     or has_table_privilege('authenticated', 'public.discussion_boards', 'insert') then
    raise exception 'The discussion tables have the wrong grants';
  end if;

  if has_table_privilege('anon', 'public.discussion_reports', 'select')
     or has_table_privilege('authenticated', 'public.discussion_reports', 'update')
     or has_table_privilege('authenticated', 'public.discussion_reports', 'delete')
     or has_table_privilege('anon', 'public.discussion_blocks', 'select')
     or has_table_privilege('authenticated', 'public.discussion_blocks', 'update') then
    raise exception 'The report and block tables have the wrong grants';
  end if;

  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('discussion_boards', 'discussion_threads', 'discussion_posts',
                        'discussion_reports', 'discussion_blocks')
      and not c.relrowsecurity
  ) then
    raise exception 'Row level security is not enabled on a discussion table';
  end if;

  if (select count(*) from pg_policies
      where schemaname = 'public'
        and policyname in ('discussion_reports_aal2_if_mfa', 'discussion_blocks_aal2_if_mfa')
        and permissive = 'RESTRICTIVE' and cmd = 'ALL') <> 2 then
    raise exception 'A discussion table has no restrictive two-factor policy';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename in ('discussion_reports', 'discussion_blocks')
      and permissive = 'PERMISSIVE'
      and coalesce(qual, '') not like '%auth.uid()%'
      and coalesce(with_check, '') not like '%auth.uid()%'
  ) then
    raise exception 'A discussion policy is not limited to the member''s own rows';
  end if;
end;
$$;
