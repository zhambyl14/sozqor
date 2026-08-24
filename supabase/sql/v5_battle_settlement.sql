-- supabase/sql/v5_battle_settlement.sql
--
-- v5.0 — EN-18 / KK-3: a finished match must always move both players.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- Three separate defects lived in submit_battle_result:
--
--   1. The reward block ran only for `uid` — the player who happened to
--      submit SECOND. Whoever finished first got no XP, no battles_won and
--      no daily_progress row, which is what "the match did not count" looked
--      like from inside the app.
--   2. round(k * (1 - exp1)) is 0 once the Elo gap is wide enough, so a win
--      against a much weaker opponent moved neither rating by a single point.
--   3. Nothing settled a match whose second player never submitted. The row
--      stayed 'active' forever and neither Elo ever changed — the literal
--      report in the PRD.
--
-- Settlement now lives in one place, awards both sides, and can be reached
-- either by the second submission or by a forfeit claim after a grace period.

alter table public.battles
  add column if not exists p1_done_at timestamptz,
  add column if not exists p2_done_at timestamptz;

-- ensure_league() reads auth.uid(), so it cannot award the opponent. Split
-- the body out to an explicitly-addressed version and keep the old name as a
-- thin wrapper so nothing else has to change.
create or replace function public._ensure_league_for(p_user uuid)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  ws  date := public.week_start(current_date);
  my_tier int;
  lid bigint;
begin
  if p_user is null then return null; end if;
  if exists (select 1 from public.profiles where id = p_user and is_guest) then
    return null;
  end if;

  select lm.league_id into lid
  from public.league_members lm
  join public.leagues l on l.id = lm.league_id
  where lm.user_id = p_user and l.week_start = ws
  limit 1;
  if lid is not null then return lid; end if;

  select least(4, greatest(0, l.tier)) into my_tier
  from public.league_members lm
  join public.leagues l on l.id = lm.league_id
  where lm.user_id = p_user
  order by l.week_start desc
  limit 1;
  my_tier := coalesce(my_tier, 0);

  select l.id into lid
  from public.leagues l
  where l.week_start = ws and l.tier = my_tier
    and (select count(*) from public.league_members m where m.league_id = l.id) < 30
  order by l.id
  limit 1;

  if lid is null then
    insert into public.leagues (tier, week_start) values (my_tier, ws) returning id into lid;
  end if;

  insert into public.league_members (league_id, user_id, xp)
  values (lid, p_user, 0)
  on conflict (league_id, user_id) do nothing;

  return lid;
end;
$$;

create or replace function public.ensure_league()
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Лигаға қосылу үшін тіркелу керек';
  end if;
  return public._ensure_league_for(uid);
end;
$$;

-- Pays one side of a finished battle. Called once per player by
-- _settle_battle, never by the client.
create or replace function public._award_battle_side(b public.battles, p_user uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  won    bool;
  amount int;
  lid    bigint;
begin
  if p_user is null then return; end if;
  won    := coalesce(b.winner = p_user, false);
  amount := case when won then 60 when b.is_draw then 30 else 15 end;

  update public.profiles
     set battles_played = battles_played + 1,
         battles_won    = battles_won + (case when won then 1 else 0 end),
         xp             = greatest(0, xp + amount),
         coins          = greatest(0, coins + greatest(0, amount / 10))
   where id = p_user;

  insert into public.xp_log (user_id, amount, source)
  values (p_user, amount, 'battle_' || b.mode);

  insert into public.daily_progress (user_id, day, battles_played, battles_won, xp_earned)
  values (p_user, current_date, 1, case when won then 1 else 0 end, amount)
  on conflict (user_id, day) do update set
    battles_played = public.daily_progress.battles_played + 1,
    battles_won    = public.daily_progress.battles_won + (case when won then 1 else 0 end),
    xp_earned      = public.daily_progress.xp_earned + amount;

  lid := public._ensure_league_for(p_user);
  if lid is not null then
    update public.league_members set xp = xp + amount
     where league_id = lid and user_id = p_user;
  end if;
end;
$$;

-- The single place a battle becomes 'finished'. Idempotent: the caller holds
-- the row lock and the status check makes a second entry a no-op.
create or replace function public._settle_battle(p_battle uuid)
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  b public.battles;
  e1 int; e2 int; exp1 numeric; d1 int; d2 int;
  k int := 32;
begin
  select * into b from public.battles where id = p_battle;
  if b.id is null or b.status = 'finished' then return b; end if;

  if b.p1_score > b.p2_score then
    update public.battles set winner = b.p1, is_draw = false where id = p_battle;
  elsif b.p2_score > b.p1_score then
    update public.battles set winner = b.p2, is_draw = false where id = p_battle;
  else
    update public.battles set winner = null, is_draw = true where id = p_battle;
  end if;

  -- Rating moves in ranked play only. A friend battle never touches Elo, so
  -- two accounts cannot trade wins to farm rating (EN-18).
  if b.mode = 'ranked' and b.p2 is not null then
    select elo into e1 from public.profiles where id = b.p1;
    select elo into e2 from public.profiles where id = b.p2;
    e1 := coalesce(e1, 1000);
    e2 := coalesce(e2, 1000);
    exp1 := 1.0 / (1.0 + power(10, (e2 - e1)::numeric / 400));

    if b.p1_score > b.p2_score then
      d1 := round(k * (1 - exp1));
    elsif b.p2_score > b.p1_score then
      d1 := round(k * (0 - exp1));
    else
      d1 := round(k * (0.5 - exp1));
    end if;

    -- A decisive result must never round away to nothing, however lopsided
    -- the pairing was.
    if d1 = 0 and b.p1_score <> b.p2_score then
      d1 := case when b.p1_score > b.p2_score then 1 else -1 end;
    end if;

    d2 := -d1;
    update public.profiles set elo = greatest(100, elo + d1) where id = b.p1;
    update public.profiles set elo = greatest(100, elo + d2) where id = b.p2;
    update public.battles set p1_elo_delta = d1, p2_elo_delta = d2 where id = p_battle;
  end if;

  update public.battles set status = 'finished', ended_at = now() where id = p_battle;
  select * into b from public.battles where id = p_battle;

  perform public._award_battle_side(b, b.p1);
  if b.p2 is not null then
    perform public._award_battle_side(b, b.p2);
  end if;

  return b;
end;
$$;

create or replace function public.submit_battle_result(
  p_battle uuid, p_score integer, p_correct integer, p_opp_score integer default null)
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b public.battles;
  is_p1 bool;
  qn int;
  cap int;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into b from public.battles where id = p_battle for update;
  if b.id is null then raise exception 'battle not found'; end if;
  if uid <> b.p1 and uid <> coalesce(b.p2, '00000000-0000-0000-0000-000000000000'::uuid) then
    raise exception 'not a participant';
  end if;
  if b.status = 'finished' then return b; end if;

  is_p1 := (uid = b.p1);

  -- A round is worth 10 points plus a speed and a combo bonus; nothing can
  -- put a single question past 40. Clamping to the question count stops a
  -- patched client from posting an arbitrary score (EN-51).
  qn  := greatest(1, coalesce(jsonb_array_length(b.questions), 10));
  cap := qn * 40;
  p_score   := greatest(0, least(coalesce(p_score, 0), cap));
  p_correct := greatest(0, least(coalesce(p_correct, 0), qn));

  if is_p1 then
    update public.battles
       set p1_score = p_score, p1_correct = p_correct,
           p1_done = true, p1_done_at = now()
     where id = p_battle;
  else
    update public.battles
       set p2_score = p_score, p2_correct = p_correct,
           p2_done = true, p2_done_at = now()
     where id = p_battle;
  end if;

  if b.mode = 'bot' then
    update public.battles
       set p2_score = greatest(0, least(coalesce(p_opp_score, 0), cap)),
           p2_done = true, p2_done_at = now()
     where id = p_battle;
  end if;

  select * into b from public.battles where id = p_battle;

  if b.p1_done and b.p2_done then
    b := public._settle_battle(p_battle);
  end if;

  return b;
end;
$$;

-- EN-20: a player who finishes and then waits out the grace period wins the
-- match the opponent walked away from, instead of both sides keeping the
-- rating they started with.
create or replace function public.claim_battle_forfeit(p_battle uuid)
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b public.battles;
  grace constant interval := interval '75 seconds';
  mine_done_at timestamptz;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into b from public.battles where id = p_battle for update;
  if b.id is null then raise exception 'battle not found'; end if;
  if uid <> b.p1 and uid <> coalesce(b.p2, '00000000-0000-0000-0000-000000000000'::uuid) then
    raise exception 'not a participant';
  end if;
  if b.status = 'finished' or b.p2 is null then return b; end if;

  -- Only a player who has already posted their own result may claim, and
  -- only once the opponent has had the full grace period to come back.
  if uid = b.p1 then
    if not b.p1_done then return b; end if;
    mine_done_at := b.p1_done_at;
  else
    if not b.p2_done then return b; end if;
    mine_done_at := b.p2_done_at;
  end if;

  if mine_done_at is null or now() < mine_done_at + grace then
    return b;
  end if;

  if uid = b.p1 then
    update public.battles set p2_score = 0, p2_correct = 0,
           p2_done = true, p2_done_at = now() where id = p_battle;
  else
    update public.battles set p1_score = 0, p1_correct = 0,
           p1_done = true, p1_done_at = now() where id = p_battle;
  end if;

  return public._settle_battle(p_battle);
end;
$$;

revoke execute on function public._settle_battle(uuid) from authenticated, anon;
revoke execute on function public._award_battle_side(public.battles, uuid) from authenticated, anon;
revoke execute on function public._ensure_league_for(uuid) from authenticated, anon;
grant execute on function public.claim_battle_forfeit(uuid) to authenticated;
