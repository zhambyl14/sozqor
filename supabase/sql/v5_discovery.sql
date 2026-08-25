-- supabase/sql/v5_discovery.sql
--
-- v5.0 — "Жаңа сөз табылмады, кейінірек көр" must stop happening.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run.
--
-- What was wrong. `сөз тап` asked a model for words and, whenever every
-- model was busy or out of quota, showed the learner an empty screen and a
-- line telling them to come back later — while the dictionary those same
-- models had already filled sat right there, hundreds of rows, unread.
--
-- What this adds. One query that answers the actual question: which words at
-- this level has THIS learner never added? It costs no quota, cannot be rate
-- limited, and is what the edge function falls back on so the screen always
-- has something on it.
--
-- The exclusion is done server-side on purpose. The client only knows the
-- words currently on screen; the server knows the whole `words` table, which
-- is why the old filter kept offering back words the learner already owned
-- and then hid all twelve of them.

create or replace function public.dict_discover(
  p_cefr    text default null,
  p_topic   text default null,
  p_exclude text[] default '{}',
  p_limit   integer default 12,
  p_offset  integer default 0)
returns setof public.dictionary
language sql
stable
security definer
set search_path to 'public'
as $$
  with mine as (
    -- Every English form this learner already has, however it got there:
    -- added from the dictionary, typed by hand, or won in a game.
    select public.norm_term(w.en) as k
    from public.words w
    where w.user_id = auth.uid()
  ),
  skip as (
    select public.norm_term(x) as k
    from unnest(coalesce(p_exclude, '{}')) as x
    union
    select k from mine
  )
  select d.*
  from public.dictionary d
  where coalesce(d.en, '') <> ''
    and coalesce(d.kk, '') <> ''
    and (p_cefr is null or p_cefr = '' or d.cefr = p_cefr)
    and (p_topic is null or p_topic = '' or p_topic = 'general' or d.topic = p_topic)
    and public.norm_term(d.en) not in (select k from skip)
  -- Verified entries first, then the ones people actually look up, so the
  -- first screen a learner sees is the best of what the dictionary holds.
  order by d.verified desc, d.hits desc, d.id
  limit greatest(1, least(coalesce(p_limit, 12), 50))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- How many are left to find at this level — the screen can say "тағы 180
-- сөз бар" instead of implying the well has run dry.
create or replace function public.dict_discover_count(
  p_cefr text default null, p_topic text default null)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $$
  select count(*)::int
  from public.dictionary d
  where coalesce(d.en, '') <> ''
    and coalesce(d.kk, '') <> ''
    and (p_cefr is null or p_cefr = '' or d.cefr = p_cefr)
    and (p_topic is null or p_topic = '' or p_topic = 'general' or d.topic = p_topic)
    and public.norm_term(d.en) not in (
      select public.norm_term(w.en) from public.words w where w.user_id = auth.uid()
    );
$$;

grant execute on function
  public.dict_discover(text, text, text[], integer, integer) to authenticated;
grant execute on function
  public.dict_discover_count(text, text) to authenticated;

notify pgrst, 'reload schema';
