-- Steam IDs come from Steam: a member proves the account is theirs.
--
-- Until now a member typed a Steam ID64 in Settings, the app saved it on their
-- own profiles row, and profiles_check_values (20261019132900) only checked that
-- it is 17 digits. Anyone could type someone else's ID and have sync-steam and
-- sync-achievements import that account's public library, playtime and
-- achievements onto their own profile, where other members see them as theirs.
--
-- Now the steam-link Edge Function is the only writer: the member signs in
-- through Steam (OpenID 2.0), Steam confirms the answer, and the function saves
-- the SteamID64 Steam vouched for with the service role (and takes it off any
-- other profile). A member's own insert has no Steam ID, and a member's update
-- keeps the one the row had; clearing it (Disconnect) is still allowed, and an
-- empty one is stored as NULL. The service role is not affected. sync-steam and
-- sync-achievements read steam_id from the row, never from the request, so
-- nothing changes for them.
--
-- Steam IDs saved before this migration were typed in, not proven, and stay as
-- they are. When an account's owner connects it through Steam, steam-link takes
-- it off every other profile. To have every member prove theirs now instead:
--   update public.profiles set steam_id = null where steam_id is not null;
--
-- Deploy order: deploy steam-link (with supabase/config.toml, which lets Steam's
-- return through without a Supabase token; deploy-supabase.yml does both)
-- together with or before this migration, then ship the app. App builds from
-- before this change can't connect Steam any more: the ID they save is ignored
-- (Steam shows as connected until the profile is read again). Disconnect keeps
-- working on them.

create or replace function public.profiles_check_values()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  is_new constant boolean := tg_op = 'INSERT';
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.display_name is not null
     and (is_new or new.display_name is distinct from old.display_name) then
    new.display_name := left(
      btrim(regexp_replace(new.display_name, '[\x01-\x1f\x7f‎‏‪-‮⁦-⁩]', '', 'g')),
      100
    );
    if new.display_name = '' then
      new.display_name := 'Player';
    end if;
  end if;

  if is_new or new.handle is distinct from old.handle then
    -- citext compares case-insensitively, regular expressions included: test the text.
    if new.handle is not null and new.handle::text !~ '^[a-z0-9_]{3,30}$' then
      raise exception 'A handle is 3 to 30 characters: a-z, 0-9 and _.'
        using errcode = 'check_violation';
    end if;
  end if;

  if (is_new or new.bio is distinct from old.bio) and char_length(new.bio) > 500 then
    raise exception 'A bio is at most 500 characters.' using errcode = 'check_violation';
  end if;

  if (is_new or new.avatar_url is distinct from old.avatar_url)
     and new.avatar_url is not null
     and not public.profiles_avatar_url_ok(new.avatar_url, new.id) then
    if is_new then
      new.avatar_url := null;
    else
      raise exception 'A profile photo must be uploaded to Checkpoint.' using errcode = 'check_violation';
    end if;
  end if;

  -- Only steam-link (the service role) sets a Steam ID. A member may clear theirs.
  if is_new then
    new.steam_id := null;
  elsif new.steam_id is distinct from old.steam_id then
    if nullif(btrim(new.steam_id), '') is null then
      new.steam_id := null;
    else
      new.steam_id := old.steam_id;
    end if;
  end if;

  return new;
end;
$$;

comment on column public.profiles.steam_id is
  'The SteamID64 the member proved is theirs by signing in through Steam. Written by the steam-link Edge Function only; a member may clear it.';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'profiles_check_values'
      and tgenabled <> 'D'
  ) then
    raise exception 'The profiles_check_values trigger is missing or disabled';
  end if;
  if pg_get_functiondef('public.profiles_check_values()'::regprocedure) !~ 'new\.steam_id := old\.steam_id' then
    raise exception 'profiles_check_values does not keep the Steam ID';
  end if;
end;
$$;
