-- supabase/sql/v5_league_elo.sql
--
-- v5.0 — EN-19 / KK-3: the league is a rating ladder, not an XP one.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Run it AFTER v5_battle_settlement.sql — it replaces _ensure_league_for,
-- which that file introduces.
--
-- What was wrong. ensure_league() put you in whatever tier you were in last
-- week and my_league() ranked the room by league_members.xp. Nothing in the
-- whole chain touched Elo. So the league measured how much you PLAYED, the
-- rating measured how well you played, and the two ladders had nothing to say
-- to each other — which is what made "climb the league" and "raise your
-- rating" feel like two unrelated games running side by side.
--
-- What it is now. The band comes from profiles.elo, the room is ranked by
-- Elo, and matchmaking prefers an opponent inside your own band before it
-- widens. XP keeps doing its own job — levels, the mission path, the weekly
-- team goal — it just no longer decides who you are ranked against.
--
-- EN-19 also asks for "an appropriate top rank rather than endlessly adding
-- Leagues". Тұғыр (tier 5) is that rank: it has no upper bound and no tier
-- above it, so the ladder ends somewhere instead of inventing new rungs.

-- ── The bands ──────────────────────────────────────────────
-- One source of truth. The client reads this rather than repeating the
-- thresholds in Dart, because a ladder whose rungs disagree between the app
-- and the server is worse than no ladder.
create or replace function public.league_bands()
returns table (
  tier    integer,
  min_elo integer,
  max_elo integer,
  name_kk text,
  name_ru text,
  colour  text)
language sql
immutable
as $$
  values
    (0,    0,  999, 'Қола',    'Бронза',   '#B87333'),
    (1, 1000, 1499, 'Күміс',   'Серебро',  '#9CA3AF'),
    (2, 1500, 1999, 'Алтын',   'Золото',   '#F59E0B'),
    (3, 2000, 2499, 'Платина', 'Платина',  '#38BDF8'),
    (4, 2500, 2999, 'Алмас',   'Алмаз',    '#7C5CFF'),
    -- The top rank. 2147483647 is the integer ceiling, so nothing sits above
    -- it and no sixth league is ever needed.
    (5, 3000, 2147483647, 'Тұғыр', 'Вершина', '#F0455E');
$$;

create or replace function public.tier_for_elo(p_elo integer)
returns integer
language sql
immutable
as $$
  select coalesce(
    (select b.tier from public.league_bands() b
      where coalesce(p_elo, 1000) between b.min_elo and b.max_elo
      limit 1),
    0);
$$;

-- ── Placing a player ───────────────────────────────────────
-- Replaces the version in v5_battle_settlement.sql. Same contract — returns
-- the league id, returns null for a guest, never raises — but the tier is now
-- read off the rating instead of carried over from last week.
create or replace function public._ensure_league_for(p_user uuid)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  ws       date := public.week_start(current_date);
  my_elo   integer;
  my_tier  integer;
  lid      bigint;
  cur_tier integer;
begin
  if p_user is null then return null; end if;
  if exists (select 1 from public.profiles where id = p_user and is_guest) then
    return null;
  end if;

  select elo into my_elo from public.profiles where id = p_user;
  my_tier := public.tier_for_elo(coalesce(my_elo, 1000));

  -- Already placed this week. If their rating has since carried them into a
  -- different band, move them — otherwise a player who climbed on Monday
  -- spends the rest of the week ranked against people they have outgrown.
  select lm.league_id, l.tier into lid, cur_tier
  from public.league_members lm
  join public.leagues l on l.id = lm.league_id
  where lm.user_id = p_user and l.week_start = ws
  limit 1;

  if lid is not null then
    if cur_tier = my_tier then return lid; end if;
    delete from public.league_members where league_id = lid and user_id = p_user;
    lid := null;
  end if;

  -- A room in the right band with space left in it.
  select l.id into lid
  from public.leagues l
  where l.week_start = ws and l.tier = my_tier
    and (select count(*) from public.league_members m where m.league_id = l.id) < 30
  order by l.id
  limit 1;

  if lid is null then
    insert into public.leagues (tier, week_start) values (my_tier, ws)
    returning id into lid;
  end if;

  insert into public.league_members (league_id, user_id, xp)
  values (lid, p_user, 0)
  on conflict (league_id, user_id) do nothing;

  return lid;
end;
$$;

-- ── The standings ──────────────────────────────────────────
-- Ranked by rating, with the band's own name and range carried on every row
-- so the client needs one request to draw the whole screen.
-- The old my_league() returned a narrower row (no elo, no band name), and
-- Postgres refuses to `create or replace` a function whose return type has
-- changed -- which is exactly why this file failed the first time it was run.
-- Dropping it first is safe: nothing else in the schema calls it.
drop function if exists public.my_league();

create or replace function public.my_league()
returns table (
  league_id    bigint,
  tier         integer,
  week_start   date,
  user_id      uuid,
  username     text,
  display_name text,
  avatar_emoji text,
  xp           integer,
  elo          integer,
  rank         integer,
  is_me        boolean,
  tier_kk      text,
  tier_ru      text,
  tier_colour  text,
  tier_min     integer,
  tier_max     integer)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  lid bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  lid := public._ensure_league_for(uid);
  if lid is null then return; end if;

  return query
    select l.id, l.tier, l.week_start,
           p.id, p.username, p.display_name, p.avatar_emoji,
           m.xp, p.elo,
           rank() over (order by p.elo desc, m.xp desc, m.joined_at)::int,
           (p.id = uid),
           b.name_kk, b.name_ru, b.colour, b.min_elo, b.max_elo
    from public.league_members m
    join public.leagues l on l.id = m.league_id
    join public.profiles p on p.id = m.user_id
    join public.league_bands() b on b.tier = l.tier
    where m.league_id = lid
    order by p.elo desc, m.xp desc, m.joined_at;
end;
$$;

-- ── Matchmaking inside the band ────────────────────────────
-- Prefers an opponent in the same league band and only widens to a
-- neighbouring one once the queue has had time to fail (EN-19). The Elo maths
-- itself is untouched — it lives in _settle_battle and is already fair across
-- a gap, which is exactly why widening is safe when nobody closer is waiting.
create or replace function public.find_or_queue_match(
  p_cefr text default 'A1', p_questions jsonb default '[]'::jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  my_elo int;
  my_tier int;
  opp uuid;
  bid uuid;
  waited interval;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Рейтингті баттл үшін тіркелу керек';
  end if;

  select elo into my_elo from public.profiles where id = uid;
  my_elo := coalesce(my_elo, 1000);
  my_tier := public.tier_for_elo(my_elo);

  -- Somebody already paired with us while we were away.
  select b.id into bid from public.battles b
  where b.mode = 'ranked' and b.status in ('waiting','active')
    and (b.p1 = uid or b.p2 = uid)
    and b.p2 is not null
    and b.created_at > now() - interval '3 minutes'
  order by b.created_at desc limit 1;
  if bid is not null then
    delete from public.mm_queue where user_id = uid;
    return bid;
  end if;

  -- How long we have been queued decides how far we are willing to look.
  -- Under 8 seconds: same band only. After that, neighbouring bands. After 20,
  -- anybody — a rated match against someone further away still settles fairly,
  -- and no match at all is the worse outcome.
  select now() - joined_at into waited from public.mm_queue where user_id = uid;
  waited := coalesce(waited, interval '0');

  delete from public.mm_queue q
  where q.user_id = (
    select q2.user_id from public.mm_queue q2
    where q2.user_id <> uid
      and q2.joined_at > now() - interval '2 minutes'
      and (
        waited > interval '20 seconds'
        or (waited > interval '8 seconds'
            and abs(public.tier_for_elo(q2.elo) - my_tier) <= 1)
        or public.tier_for_elo(q2.elo) = my_tier
      )
    order by abs(public.tier_for_elo(q2.elo) - my_tier),
             abs(q2.elo - my_elo),
             q2.joined_at
    limit 1
    for update skip locked
  )
  returning q.user_id into opp;

  if opp is not null then
    delete from public.mm_queue where user_id = uid;
    insert into public.battles (mode, status, p1, p2, questions, cefr, started_at)
    values ('ranked', 'active', opp, uid, p_questions, p_cefr, now())
    returning id into bid;
    return bid;
  end if;

  -- Deliberately NOT touching joined_at on conflict. The client polls this
  -- function every couple of seconds, so the old `joined_at = now()` reset the
  -- clock on every poll — which would mean `waited` never grew past zero and
  -- the search never widened past the player's own band. Keeping the original
  -- timestamp is what makes the widening above actually happen.
  insert into public.mm_queue (user_id, elo, cefr)
  values (uid, my_elo, p_cefr)
  on conflict (user_id) do update set elo = excluded.elo, cefr = excluded.cefr;

  return null;
end;
$$;

grant execute on function public.league_bands()        to authenticated, anon;
grant execute on function public.tier_for_elo(integer) to authenticated, anon;
revoke execute on function public._ensure_league_for(uuid) from authenticated, anon;

notify pgrst, 'reload schema';
