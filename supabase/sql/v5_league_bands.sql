-- supabase/sql/v5_league_bands.sql
--
-- v5.0 — the league is a rating threshold, not a leaderboard cut.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run. Run it AFTER v5_league_elo.sql — it replaces that file's
-- `league_bands()` with wider bands and adds the progress reading the screen
-- needs.
--
-- What was wrong, in the words of the report: "көтерілу аймағы топ 10 келесі
-- лигаға өтпейді ғой, кім келесі лиганың минимум кубогына жетті сол өтеді".
-- Exactly. Promotion by finishing in the top ten means your week depends on
-- who else happened to be in your room; promotion by REACHING a number means
-- it depends on you. Clash of Clans has worked that way for a decade and
-- everybody already understands it.
--
-- So there is no promotion zone. There is a threshold, and `league_progress`
-- says how far away it is.
--
-- The bands start at 1000 because that is where a new account starts: Қола is
-- everything up to 1500, and the ladder ends at Тұғыр, which begins at 5000
-- and has nothing above it.

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
    (0,    0, 1499, 'Қола',    'Бронза',   '#B87333'),
    (1, 1500, 1999, 'Күміс',   'Серебро',  '#9CA3AF'),
    (2, 2000, 2499, 'Алтын',   'Золото',   '#F59E0B'),
    (3, 2500, 2999, 'Платина', 'Платина',  '#38BDF8'),
    (4, 3000, 3999, 'Алмас',   'Алмаз',    '#7C5CFF'),
    (5, 4000, 4999, 'Шебер',   'Мастер',   '#12B981'),
    -- The top rank. 2147483647 is the integer ceiling, so nothing sits above
    -- it and no eighth league is ever needed.
    (6, 5000, 2147483647, 'Тұғыр', 'Вершина', '#F0455E');
$$;

-- Everything the league header needs, in one row: where you are, what the
-- band is called, and the single number that moves you up or down.
create or replace function public.league_progress()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  my_elo integer;
  cur record;
  nxt record;
  prv record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(elo, 1000) into my_elo from public.profiles where id = uid;
  my_elo := coalesce(my_elo, 1000);

  select * into cur from public.league_bands() b where my_elo between b.min_elo and b.max_elo;
  select * into nxt from public.league_bands() b where b.tier = cur.tier + 1;
  select * into prv from public.league_bands() b where b.tier = cur.tier - 1;

  return jsonb_build_object(
    'elo',         my_elo,
    'tier',        cur.tier,
    'name_kk',     cur.name_kk,
    'name_ru',     cur.name_ru,
    'colour',      cur.colour,
    'band_min',    cur.min_elo,
    'band_max',    case when cur.max_elo > 1000000 then null else cur.max_elo end,
    'next_name_kk', nxt.name_kk,
    'next_name_ru', nxt.name_ru,
    'next_colour',  nxt.colour,
    'next_at',      nxt.min_elo,
    -- What the screen actually says: this many points to the next band.
    'to_next',      case when nxt.min_elo is null then null
                    else greatest(0, nxt.min_elo - my_elo) end,
    'prev_name_kk', prv.name_kk,
    'prev_name_ru', prv.name_ru,
    -- And how much room there is before dropping out of this one.
    'drop_at',      prv.max_elo,
    'to_drop',      case when prv.max_elo is null then null
                    else greatest(0, my_elo - prv.max_elo) end,
    'is_top',       nxt.tier is null,
    'bands', (select jsonb_agg(jsonb_build_object(
                'tier', b.tier, 'min', b.min_elo,
                'max', case when b.max_elo > 1000000 then null else b.max_elo end,
                'kk', b.name_kk, 'ru', b.name_ru, 'colour', b.colour)
                order by b.tier)
              from public.league_bands() b)
  );
end;
$$;

grant execute on function public.league_bands()     to authenticated, anon;
grant execute on function public.league_progress()  to authenticated;

notify pgrst, 'reload schema';
