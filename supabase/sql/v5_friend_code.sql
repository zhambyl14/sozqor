-- supabase/sql/v5_friend_code.sql
--
-- v5.0 — a number you can read down a phone line.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run.
--
-- Finding a friend meant knowing their @username, and a username is the worst
-- possible handle for the job: people change it, it is case-confusing, it is
-- full of letters that sound alike out loud, and a learner who has not chosen
-- one yet has nothing to give.
--
-- A friend code is nine digits, assigned once and never again. It is shown in
-- groups of three, so it is read aloud and typed the way a phone number is,
-- and it cannot be edited — which is the whole point of an identifier.

alter table public.profiles
  add column if not exists friend_code text;

create unique index if not exists profiles_friend_code_key
  on public.profiles (friend_code) where friend_code is not null;

-- Nine digits, never starting with a zero so the leading digit survives being
-- pasted into anything that treats it as a number.
create or replace function public._new_friend_code()
returns text
language plpgsql
as $$
declare
  code text;
  tries integer := 0;
begin
  loop
    tries := tries + 1;
    code := (100000000 + floor(random() * 899999999))::bigint::text;
    exit when not exists (
      select 1 from public.profiles p where p.friend_code = code);
    if tries > 24 then
      raise exception 'could not allocate a friend code';
    end if;
  end loop;
  return code;
end;
$$;

-- Assigned lazily on first read rather than by a backfill, so an account that
-- never opens the friends screen never uses one up, and every existing
-- account gets one the moment it looks.
create or replace function public.my_friend_code()
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid  uuid := auth.uid();
  code text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select friend_code into code from public.profiles where id = uid;
  if code is not null and code <> '' then return code; end if;

  code := public._new_friend_code();
  update public.profiles set friend_code = code where id = uid;
  return code;
end;
$$;

-- Give everyone who already exists one now as well, so nobody has to open a
-- particular screen before a friend can find them.
update public.profiles
   set friend_code = public._new_friend_code()
 where friend_code is null or friend_code = '';

-- ── Finding somebody ───────────────────────────────────────
--
-- The code first, because it is the one thing that is exact and permanent.
-- The @username still works for people who know it; the account id still
-- works for a pasted share link. Spaces and dashes are stripped, so
-- "482 739 154" and "482-739-154" both find the same person.
create or replace function public.search_users(p_query text, p_limit integer default 20)
returns setof public.board_row
language sql
stable
security definer
set search_path to 'public', 'extensions'
as $$
  with q as (
    select btrim(coalesce(p_query, '')) as raw,
           regexp_replace(coalesce(p_query, ''), '[^0-9]', '', 'g') as digits
  )
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level, p.elo, 0
  from public.profiles p, q
  where p.id <> auth.uid()
    and not p.is_guest
    and (
      (length(q.digits) = 9 and p.friend_code = q.digits)
      or (length(q.raw) >= 3 and lower(p.username) = lower(ltrim(q.raw, '@')))
      or (q.raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          and p.id = q.raw::uuid)
    )
  limit greatest(1, least(coalesce(p_limit, 20), 5));
$$;

-- ── The league somebody is in, on their profile ────────────
--
-- A ladder nobody can see you standing on is not a ladder. This is the one
-- call the public profile makes for it, and it is the same band table the
-- league screen reads so the two can never disagree.
create or replace function public.public_profile(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  p   public.profiles;
  b   record;
  rel text;
  uid uuid := auth.uid();
begin
  select * into p from public.profiles where id = p_user;
  if p.id is null then return null; end if;

  select * into b from public.league_bands() x
   where coalesce(p.elo, 1000) between x.min_elo and x.max_elo;

  select f.status into rel from public.friendships f
   where (f.requester = uid and f.addressee = p_user)
      or (f.requester = p_user and f.addressee = uid)
   limit 1;

  return jsonb_build_object(
    'user_id',       p.id,
    'username',      p.username,
    'display_name',  p.display_name,
    'avatar_emoji',  p.avatar_emoji,
    'friend_code',   p.friend_code,
    'cefr',          p.cefr_level,
    'elo',           coalesce(p.elo, 1000),
    'xp',            coalesce(p.xp, 0),
    'streak',        coalesce(p.streak, 0),
    'battles_won',   coalesce(p.battles_won, 0),
    'battles_played',coalesce(p.battles_played, 0),
    'words_total',   coalesce(p.words_total, 0),
    'is_guest',      p.is_guest,
    'tier',          b.tier,
    'tier_kk',       b.name_kk,
    'tier_ru',       b.name_ru,
    'tier_colour',   b.colour,
    'friendship',    coalesce(rel, 'none'),
    -- Everything the "add friend" button needs to decide whether to exist.
    'can_add',       uid is not null and uid <> p_user
                     and coalesce(rel, 'none') = 'none' and not p.is_guest
  );
end;
$$;

grant execute on function public.my_friend_code()          to authenticated;
grant execute on function public.public_profile(uuid)      to authenticated;
grant execute on function public.search_users(text, integer) to authenticated;
revoke execute on function public._new_friend_code() from authenticated, anon;

notify pgrst, 'reload schema';
