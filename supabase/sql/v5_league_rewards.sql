-- v5_league_rewards.sql
--
-- What the ladder is FOR.
--
-- The league ranked people and said nothing about why anybody should care.
-- A band now pays, in the two currencies the app already has:
--
--   * a weekly chest, once per ISO week, larger the higher the band;
--   * a one-off promotion bonus the first time a band is ever reached, paid
--     for every band skipped so a big rating jump is not silently swallowed.
--
-- Ledger is one row per learner. `best_tier` is a high-water mark and never
-- goes down, so dropping a band and climbing back does not pay twice.

create table if not exists public.league_rewards (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  last_weekly  date,
  best_tier    integer not null default -1,
  updated_at   timestamptz not null default now()
);

alter table public.league_rewards enable row level security;

drop policy if exists league_rewards_self on public.league_rewards;
create policy league_rewards_self on public.league_rewards
  for select using (auth.uid() = user_id);

-- The Monday of the current ISO week, in one place so the state function and
-- the claim function can never disagree about which week it is.
create or replace function public.league_week()
returns date language sql stable as $$
  select (current_date - ((extract(isodow from current_date)::int - 1)))::date;
$$;

-- The payout table, derived from the band rather than typed twice.
create or replace function public.league_payout(p_tier integer)
returns table(coins integer, xp integer)
language sql immutable as $$
  select 40 + 35 * greatest(0, p_tier), 60 + 40 * greatest(0, p_tier);
$$;

create or replace function public.league_reward_state()
returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid();
  my_elo int;
  cur record;
  led  record;
  wk   date := public.league_week();
  pay  record;
  promo_from int;
  promo_coins int := 0;
  promo_xp int := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select coalesce(elo, 1000) into my_elo from public.profiles where id = uid;
  my_elo := coalesce(my_elo, 1000);
  select * into cur from public.league_bands() b
   where my_elo between b.min_elo and b.max_elo;

  select * into led from public.league_rewards where user_id = uid;
  select * into pay from public.league_payout(cur.tier);

  -- Every band above the high-water mark pays, so a learner who jumps two
  -- bands in a week is paid for two.
  promo_from := coalesce(led.best_tier, -1);
  if cur.tier > promo_from then
    promo_coins := 100 * (cur.tier - promo_from);
    promo_xp    := 150 * (cur.tier - promo_from);
  end if;

  return jsonb_build_object(
    'tier',          cur.tier,
    'name_kk',       cur.name_kk,
    'name_ru',       cur.name_ru,
    'colour',        cur.colour,
    'week',          wk,
    'weekly_ready',  (led.last_weekly is null or led.last_weekly < wk),
    'weekly_coins',  pay.coins,
    'weekly_xp',     pay.xp,
    'promo_ready',   promo_coins > 0,
    'promo_bands',   greatest(0, cur.tier - promo_from),
    'promo_coins',   promo_coins,
    'promo_xp',      promo_xp,
    'best_tier',     promo_from,
    -- What the next band would pay, so the ladder shows what climbing buys.
    'next_coins',    (select p.coins from public.league_payout(cur.tier + 1) p),
    'next_xp',       (select p.xp    from public.league_payout(cur.tier + 1) p)
  );
end;
$$;

create or replace function public.claim_league_reward()
returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid();
  my_elo int;
  cur record;
  led  record;
  wk   date := public.league_week();
  pay  record;
  promo_from int;
  got_coins int := 0;
  got_xp int := 0;
  bands int := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then raise exception 'LEAGUE_ERR:guest'; end if;

  select coalesce(elo, 1000) into my_elo from public.profiles where id = uid;
  my_elo := coalesce(my_elo, 1000);
  select * into cur from public.league_bands() b
   where my_elo between b.min_elo and b.max_elo;

  -- The row is locked for the length of the transaction, so two taps in
  -- quick succession cannot both see an unclaimed week.
  insert into public.league_rewards (user_id) values (uid)
    on conflict (user_id) do nothing;
  select * into led from public.league_rewards where user_id = uid for update;

  promo_from := coalesce(led.best_tier, -1);
  if cur.tier > promo_from then
    bands     := cur.tier - promo_from;
    got_coins := got_coins + 100 * bands;
    got_xp    := got_xp + 150 * bands;
  end if;

  if led.last_weekly is null or led.last_weekly < wk then
    select * into pay from public.league_payout(cur.tier);
    got_coins := got_coins + pay.coins;
    got_xp    := got_xp + pay.xp;
  end if;

  if got_coins = 0 and got_xp = 0 then
    return jsonb_build_object('claimed', false, 'coins', 0, 'xp', 0,
                              'bands', 0);
  end if;

  update public.league_rewards
     set last_weekly = wk,
         best_tier   = greatest(promo_from, cur.tier),
         updated_at  = now()
   where user_id = uid;

  -- add_xp already grants a tenth of the тәжірибе in coins and moves the
  -- league board, so the chest tops the coins up to its own figure rather
  -- than paying them twice.
  perform public.add_xp(got_xp, 'league_reward');
  update public.profiles
     set coins = greatest(0, coins + greatest(0, got_coins - got_xp / 10))
   where id = uid;

  return jsonb_build_object(
    'claimed', true,
    'coins',   got_coins,
    'xp',      got_xp,
    'bands',   bands,
    'tier',    cur.tier,
    'name_kk', cur.name_kk,
    'name_ru', cur.name_ru);
end;
$$;

grant execute on function public.league_week()          to authenticated;
grant execute on function public.league_payout(integer) to authenticated, anon;
grant execute on function public.league_reward_state()  to authenticated;
grant execute on function public.claim_league_reward()  to authenticated;
