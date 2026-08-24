-- supabase/sql/v5_tournament_survival.sql
--
-- v5.0 — EN-23 / KK-4: the tournament stops being another classic test.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- A tournament round was PlayMode.tournament, which is PlayMode.classic with a
-- different label and a different place to post the score. The PRD is blunt
-- about it: "Tournament must not feel like another Classic Test."
--
-- Survival is what it becomes, because it is the one shape nothing else in
-- this app has: a run you can LOSE, and a decision about whether to risk what
-- you have already banked.
--
--   * Three lives a day for the whole tournament, not per run.
--   * Questions come in waves, and each wave answers faster than the last —
--     twelve seconds down to five.
--   * One wrong answer costs a life.
--   * Between waves you choose: bank what you have, or push on and risk it.
--
-- Lives are decremented server-side. Kept on the device they would reset with
-- a reinstall, and a survival mode with unlimited retries is not one.
--
-- The board ranks on the deepest wave reached, then on score — the number the
-- mode is actually about, rather than the number you can accumulate by playing
-- all day.

alter table public.tournaments
  add column if not exists kind text not null default 'survival'
    check (kind in ('classic', 'survival')),
  -- A tournament had no Russian title at all, so it rendered Kazakh-only next
  -- to fully bilingual events and shop items.
  add column if not exists title_ru text not null default '',
  add column if not exists subtitle text not null default '',
  add column if not exists subtitle_ru text not null default '',
  -- Without this a tournament created with the wrong dates or the wrong CEFR
  -- band stays in the catalogue for ever; the moderator console has no way to
  -- retire one today.
  add column if not exists is_active boolean not null default true;

alter table public.tournament_entries
  add column if not exists lives_left integer not null default 3,
  add column if not exists best_wave integer not null default 0,
  add column if not exists runs integer not null default 0,
  add column if not exists day date not null default (now() at time zone 'utc')::date;

-- ── The rules, in one place ────────────────────────────────
create or replace function public.tournament_rules()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'lives_per_day',   3,
    'wave_size',       6,
    'first_wave_secs', 12,
    'last_wave_secs',  5,
    'max_wave',        10
  );
$$;

-- Seconds a wave allows per question. Written as SQL so the client and the
-- server cannot disagree about how hard wave 7 is.
create or replace function public.wave_seconds(p_wave integer)
returns integer
language sql
immutable
as $$
  select greatest(5, 13 - greatest(1, coalesce(p_wave, 1)));
$$;

-- ── Starting or resuming a run ─────────────────────────────
create or replace function public.tournament_state(p_tournament bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid   uuid := auth.uid();
  today date := (now() at time zone 'utc')::date;
  e     public.tournament_entries;
  t     public.tournaments;
  r     jsonb := public.tournament_rules();
  my_rank integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into t from public.tournaments where id = p_tournament;
  if t.id is null then raise exception 'no such tournament'; end if;

  insert into public.tournament_entries (tournament_id, user_id, day, lives_left)
  values (p_tournament, uid, today, (r->>'lives_per_day')::int)
  on conflict (tournament_id, user_id) do nothing;

  select * into e from public.tournament_entries
   where tournament_id = p_tournament and user_id = uid;

  -- A new day refills the lives. Doing it lazily on read means there is no
  -- scheduler to run and no window where a learner is locked out waiting for
  -- one.
  if e.day is distinct from today then
    update public.tournament_entries
       set day = today, lives_left = (r->>'lives_per_day')::int
     where tournament_id = p_tournament and user_id = uid
    returning * into e;
  end if;

  select count(*) + 1 into my_rank
    from public.tournament_entries x
   where x.tournament_id = p_tournament
     and (x.best_wave > e.best_wave
       or (x.best_wave = e.best_wave and x.score > e.score));

  return jsonb_build_object(
    'rules',       r,
    'kind',        t.kind,
    'title',       t.title,
    'title_ru',    nullif(t.title_ru, ''),
    'lives_left',  e.lives_left,
    'best_wave',   e.best_wave,
    'score',       e.score,
    'runs',        e.runs,
    'rank',        my_rank,
    'ends_at',     t.ends_at
  );
end;
$$;

-- ── Finishing a run ────────────────────────────────────────
-- Called once per run, whether it was banked or lost. `p_lost` is what spends
-- the life: banking out costs nothing, which is the entire decision the mode
-- is built around.
create or replace function public.submit_tournament_run(
  p_tournament bigint,
  p_wave       integer,
  p_score      integer,
  p_lost       boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid   uuid := auth.uid();
  today date := (now() at time zone 'utc')::date;
  r     jsonb := public.tournament_rules();
  e     public.tournament_entries;
  wave  integer;
  gained integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into e from public.tournament_entries
   where tournament_id = p_tournament and user_id = uid
   for update;
  if e.user_id is null then raise exception 'not entered'; end if;
  if e.day is distinct from today then
    raise exception 'stale run';
  end if;
  if e.lives_left <= 0 and p_lost then
    raise exception 'GUEST_LOCKED: Бүгінгі өмірлерің бітті';
  end if;

  -- Clamp to what a real run can produce: a wave is six questions and nothing
  -- puts one past 40 points, so the ceiling is the wave count times that.
  wave   := greatest(0, least(coalesce(p_wave, 0), (r->>'max_wave')::int));
  gained := greatest(0, least(coalesce(p_score, 0),
                              wave * (r->>'wave_size')::int * 40));

  update public.tournament_entries
     set score      = greatest(score, gained),
         best_wave  = greatest(best_wave, wave),
         runs       = runs + 1,
         rounds     = rounds + wave,
         lives_left = greatest(0, lives_left - (case when p_lost then 1 else 0 end)),
         updated_at = now()
   where tournament_id = p_tournament and user_id = uid
  returning * into e;

  -- A run that got somewhere is worth XP whether it was banked or lost; the
  -- mode is meant to be worth entering even on a bad day.
  if wave > 0 then
    perform public.add_xp(wave * 15, 'tournament_survival');
  end if;

  return jsonb_build_object(
    'lives_left', e.lives_left,
    'best_wave',  e.best_wave,
    'score',      e.score,
    'runs',       e.runs
  );
end;
$$;

-- ── The board ──────────────────────────────────────────────
-- Ranked on the deepest wave first. Score alone would reward playing all day
-- over surviving, which is the opposite of what this mode is about.
create or replace function public.tournament_board(
  p_tournament bigint, p_limit integer default 50)
returns table (
  user_id      uuid,
  username     text,
  display_name text,
  avatar_emoji text,
  cefr_level   text,
  value        integer,
  rank         integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level,
         e.score,
         rank() over (order by e.best_wave desc, e.score desc, e.updated_at)::int
  from public.tournament_entries e
  join public.profiles p on p.id = e.user_id
  where e.tournament_id = p_tournament
  order by e.best_wave desc, e.score desc, e.updated_at
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

-- ── Retiring one ───────────────────────────────────────────
create or replace function public.admin_set_tournament_active(
  p_tournament bigint, p_active boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  update public.tournaments set is_active = p_active where id = p_tournament;
end;
$$;

grant execute on function public.tournament_rules()                to authenticated, anon;
grant execute on function public.wave_seconds(integer)             to authenticated, anon;
grant execute on function public.tournament_state(bigint)          to authenticated;
grant execute on function public.submit_tournament_run(bigint, integer, integer, boolean)
  to authenticated;
grant execute on function public.admin_set_tournament_active(bigint, boolean)
  to authenticated;

notify pgrst, 'reload schema';
