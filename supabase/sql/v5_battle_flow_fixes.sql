-- v5_battle_flow_fixes.sql
--
-- The code-sharing flow sends exactly {p_questions, p_cefr}, which matched
-- BOTH create_friend_battle overloads — the old two-argument one and the
-- three-argument one whose p_target defaults to null. PostgREST cannot choose
-- between two equally good candidates, so "Досқа код жіберу" was one
-- deployment away from PGRST203 at all times, and when it did resolve it
-- could land on the older body: no guest check, no p1_lang, a different code
-- generator and a two-day expiry.
--
-- The three-argument version does everything the old one did and delegates to
-- invite_friend_battle when it is aimed at somebody, so the old one goes.
drop function if exists public.create_friend_battle(jsonb, text);

-- A rematch replayed the previous game's questions in their previous order,
-- which turns the decider of a best-of-three into a memory test. Same words,
-- fresh order: both players saw them, so shuffling stays fair, and the
-- question set still comes from whoever built the first game.
create or replace function public.offer_rematch(p_battle uuid)
returns public.battles
language plpgsql security definer set search_path to 'public' as $$
declare
  uid  uuid := auth.uid();
  b    public.battles;
  nxt  public.battles;
  sid  uuid;
  played integer;
  wins_p1 integer;
  wins_p2 integer;
  qs jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into b from public.battles where id = p_battle for update;
  if b.id is null then raise exception 'REMATCH_ERR:gone'; end if;
  if b.status <> 'finished' then raise exception 'REMATCH_ERR:unfinished'; end if;
  if b.p2 is null then raise exception 'REMATCH_ERR:no_opponent'; end if;
  if uid <> b.p1 and uid <> b.p2 then raise exception 'REMATCH_ERR:not_yours'; end if;

  sid := coalesce(b.series_id, b.id);

  select count(*) into played
    from public.battles x
   where coalesce(x.series_id, x.id) = sid and x.status = 'finished';
  if played >= 3 then raise exception 'REMATCH_ERR:series_over'; end if;

  select * into nxt from public.battles x
   where x.rematch_of = p_battle and x.status in ('invited', 'waiting', 'active')
   limit 1;
  if nxt.id is not null then return nxt; end if;

  if uid = b.p1 then
    update public.battles set p1_rematch = true where id = p_battle returning * into b;
  else
    update public.battles set p2_rematch = true where id = p_battle returning * into b;
  end if;

  -- Still one-sided. NOTE for anybody reading the client: this null does NOT
  -- arrive there as null — a function returning `battles` answers with an
  -- object whose every column is null, so the caller has to check the id.
  if not (b.p1_rematch and b.p2_rematch) then
    return null;
  end if;

  select count(*) filter (where x.winner = b.p1),
         count(*) filter (where x.winner = b.p2)
    into wins_p1, wins_p2
    from public.battles x
   where coalesce(x.series_id, x.id) = sid and x.status = 'finished';

  if greatest(wins_p1, wins_p2) >= 2 then
    raise exception 'REMATCH_ERR:series_over';
  end if;

  select coalesce(jsonb_agg(e order by random()), b.questions)
    into qs
    from jsonb_array_elements(coalesce(b.questions, '[]'::jsonb)) e;

  insert into public.battles
    (mode, status, p1, p2, questions, cefr, started_at,
     rematch_of, series_id, series_game, p1_lang, p2_lang,
     p1_seen_at, p2_seen_at)
  values
    (b.mode, 'active', b.p1, b.p2, qs, b.cefr, now(),
     p_battle, sid, played + 1, b.p1_lang, b.p2_lang, now(), now())
  returning * into nxt;

  return nxt;
end;
$$;

grant execute on function public.offer_rematch(uuid) to authenticated;
