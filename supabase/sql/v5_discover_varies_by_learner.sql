-- v5_discover_varies_by_learner.sql
--
-- Two learners who have never added a word saw exactly the same twelve words,
-- in exactly the same order, for ever: the ordering was verified, then hits,
-- then id, all of which are facts about the dictionary and none about the
-- person reading it. "Tagy soz tap" then felt like the same page reloading.
--
-- Quality still leads -- a verified row outranks an unverified one, and a
-- popular row outranks a rare one -- but popularity is now a coarse bucket
-- rather than an exact rank, and inside a bucket the order is a hash of the
-- row and the reader. Stable for one person (the same word does not jump
-- around between pages, so the offset still paginates) and different between
-- people.
create or replace function public.dict_discover(
  p_cefr text default null,
  p_topic text default null,
  p_exclude text[] default '{}',
  p_limit integer default 12,
  p_offset integer default 0
)
returns setof public.dictionary
language sql stable security definer set search_path to 'public' as $$
  with mine as (
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
  order by
    d.verified desc,
    least(coalesce(d.hits, 0), 100) / 25 desc,
    md5(d.id::text || coalesce(auth.uid()::text, '')),
    d.id
  limit greatest(1, least(coalesce(p_limit, 12), 50))
  offset greatest(0, coalesce(p_offset, 0));
$$;

grant execute on function public.dict_discover(text, text, text[], integer, integer)
  to authenticated, anon;
