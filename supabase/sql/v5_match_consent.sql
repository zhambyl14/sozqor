-- supabase/sql/v5_match_consent.sql
--
-- v5.0 — nobody is dragged into a match they did not agree to.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run. Run it AFTER v5_battle_settlement.sql and v5_league_elo.sql.
--
-- Four things were true before this file, and all four are the same bug:
--
--   * A friend battle STARTED for whoever pressed the button. The other side
--     got a pending invite they might open an hour later, by which time the
--     inviter had played all ten questions alone. One player's decision,
--     two players' match.
--   * A ranked "Кек қайтару" re-queued into ordinary matchmaking, so the
--     rematch was against a stranger — the one thing a rematch is not.
--   * Nothing stopped a friend sending the same invite twenty times.
--   * Nothing knew whether the person being invited was in the middle of a
--     rated match, so the invite landed on top of one.
--
-- Consent is therefore a row, not a screen: the battle exists in an `invited`
-- state that plays for nobody until the other side says yes.

-- ── Schema ─────────────────────────────────────────────────

alter table public.battles drop constraint if exists battles_status_check;
alter table public.battles add constraint battles_status_check
  check (status in ('invited', 'waiting', 'active', 'finished', 'cancelled', 'declined'));

alter table public.battles
  add column if not exists accepted_at timestamptz,
  add column if not exists responded_at timestamptz,
  -- 15 seconds. Long enough to notice, short enough that the inviter is not
  -- left staring at a spinner while a friend decides whether to look at their
  -- phone at all.
  add column if not exists invite_expires_at timestamptz,
  add column if not exists rematch_of uuid references public.battles(id) on delete set null,
  -- A best-of-three is one series with three rows, so both clients can read
  -- the same score instead of each keeping a private tally.
  add column if not exists series_id uuid,
  add column if not exists series_game integer not null default 1,
  -- Whoever presses "Кек қайтару" sets their side. The next game exists only
  -- once BOTH are set.
  add column if not exists p1_rematch boolean not null default false,
  add column if not exists p2_rematch boolean not null default false,
  -- The heartbeat behind the pause. A client that is on the battle screen
  -- touches this every few seconds; silence is a disconnection.
  add column if not exists p1_seen_at timestamptz,
  add column if not exists p2_seen_at timestamptz,
  -- Each side answers in the language THEY chose. One shared question list
  -- with one shared language is why a learner reading the app in Russian was
  -- being asked Kazakh→English.
  add column if not exists p1_lang text not null default 'kk',
  add column if not exists p2_lang text not null default 'kk';

create index if not exists battles_invited_idx
  on public.battles (p2, status) where status = 'invited';
create index if not exists battles_series_idx
  on public.battles (series_id) where series_id is not null;

-- Anti-spam. One row per (from, to) pair; an invite that is declined, ignored
-- or expired starts a two-minute silence.
create table if not exists public.invite_blocks (
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user   uuid not null references auth.users(id) on delete cascade,
  until     timestamptz not null,
  reason    text,
  primary key (from_user, to_user)
);
alter table public.invite_blocks enable row level security;
drop policy if exists invite_blocks_read on public.invite_blocks;
create policy invite_blocks_read on public.invite_blocks
  for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid());

-- ── Is this person free to be invited? ─────────────────────
--
-- Derived, not stored. A `busy` flag on the profile is a flag somebody has to
-- remember to clear, and the one time it is not cleared the player can never
-- be invited again. An unfinished battle row expires on its own.
create or replace function public.user_busy(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.battles b
    where (b.p1 = p_user or b.p2 = p_user)
      and b.status = 'active'
      and coalesce(b.started_at, b.created_at) > now() - interval '20 minutes'
      and not (b.p1 = p_user and b.p1_done)
      and not (b.p2 = p_user and b.p2_done)
  ) or exists (
    select 1 from public.mm_queue q
    where q.user_id = p_user and q.joined_at > now() - interval '2 minutes'
  );
$$;

-- ── Sending an invite ──────────────────────────────────────
create or replace function public.invite_friend_battle(
  p_target    uuid,
  p_questions jsonb default '[]'::jsonb,
  p_cefr      text default 'A1',
  p_lang      text default 'kk')
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b   public.battles;
  blocked timestamptz;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_target is null or p_target = uid then
    raise exception 'INVITE_ERR:self';
  end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Досыңды баттлға шақыру үшін тіркел';
  end if;

  -- Friends only. Anyone can be searched for; only a friend can be summoned.
  if not exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = uid and f.addressee = p_target)
        or (f.requester = p_target and f.addressee = uid))
  ) then
    raise exception 'INVITE_ERR:not_friend';
  end if;

  select until into blocked from public.invite_blocks
   where from_user = uid and to_user = p_target and until > now();
  if blocked is not null then
    raise exception 'INVITE_ERR:blocked:%', ceil(extract(epoch from (blocked - now())))::int;
  end if;

  if public.user_busy(p_target) then
    raise exception 'INVITE_ERR:busy';
  end if;

  -- One live invite per pair. Sending a second while the first is still
  -- ringing replaces it rather than stacking.
  update public.battles
     set status = 'cancelled', responded_at = now()
   where status = 'invited' and p1 = uid and p2 = p_target;

  insert into public.battles
    (mode, status, p1, p2, questions, cefr, invite_expires_at, p1_lang, p2_lang)
  values
    ('friend', 'invited', uid, p_target, p_questions, p_cefr,
     now() + interval '15 seconds',
     coalesce(nullif(p_lang, ''), 'kk'),
     coalesce((select ui_lang from public.profiles where id = p_target), 'kk'))
  returning * into b;

  return b;
end;
$$;

-- ── Answering one ──────────────────────────────────────────
create or replace function public.respond_battle_invite(
  p_battle uuid,
  p_accept boolean,
  p_lang   text default null)
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b   public.battles;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into b from public.battles where id = p_battle for update;
  if b.id is null then raise exception 'INVITE_ERR:gone'; end if;
  if b.p2 <> uid then raise exception 'INVITE_ERR:not_yours'; end if;
  if b.status <> 'invited' then return b; end if;

  if p_accept and b.invite_expires_at > now() then
    update public.battles
       set status = 'active',
           accepted_at = now(),
           responded_at = now(),
           started_at = now(),
           p2_lang = coalesce(nullif(p_lang, ''), b.p2_lang),
           p1_seen_at = now(),
           p2_seen_at = now()
     where id = p_battle
    returning * into b;
    -- Accepting clears any standing silence: they clearly do want to play.
    delete from public.invite_blocks where from_user = b.p1 and to_user = uid;
    return b;
  end if;

  update public.battles
     set status = 'declined', responded_at = now()
   where id = p_battle
  returning * into b;

  -- A refusal is worth two minutes of quiet. Without this, "no" is an
  -- invitation to ask again immediately, which is what spam is.
  insert into public.invite_blocks (from_user, to_user, until, reason)
  values (b.p1, uid, now() + interval '2 minutes',
          case when b.invite_expires_at <= now() then 'timeout' else 'declined' end)
  on conflict (from_user, to_user) do update
    set until = excluded.until, reason = excluded.reason;

  return b;
end;
$$;

-- Housekeeping the client can call, and does: an invite nobody answered has
-- to stop ringing on the inviter's screen too.
create or replace function public.expire_battle_invites()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare n integer;
begin
  with gone as (
    update public.battles
       set status = 'declined', responded_at = now()
     where status = 'invited' and invite_expires_at <= now()
    returning p1, p2
  )
  insert into public.invite_blocks (from_user, to_user, until, reason)
  select g.p1, g.p2, now() + interval '2 minutes', 'timeout' from gone g
  on conflict (from_user, to_user) do update
    set until = excluded.until, reason = excluded.reason;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- What is ringing on my phone right now, with enough about the caller to draw
-- the banner without a second request.
create or replace function public.my_battle_invites()
returns table (
  battle_id    uuid,
  from_user    uuid,
  username     text,
  display_name text,
  avatar_emoji text,
  elo          integer,
  cefr         text,
  seconds_left integer)
language plpgsql
security definer
set search_path to 'public'
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  perform public.expire_battle_invites();
  return query
    select b.id, p.id, p.username, p.display_name, p.avatar_emoji, p.elo, b.cefr,
           greatest(0, ceil(extract(epoch from (b.invite_expires_at - now()))))::int
    from public.battles b
    join public.profiles p on p.id = b.p1
    where b.p2 = uid and b.status = 'invited' and b.invite_expires_at > now()
    order by b.created_at desc;
end;
$$;

-- ── The rematch, agreed by both ────────────────────────────
--
-- Returns the next battle when both sides have asked for it, and null while
-- it is still one side. A ranked rematch is created against exactly the same
-- opponent — it never goes near the queue, which is the whole point.
create or replace function public.offer_rematch(p_battle uuid)
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid  uuid := auth.uid();
  b    public.battles;
  nxt  public.battles;
  sid  uuid;
  played integer;
  wins_p1 integer;
  wins_p2 integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into b from public.battles where id = p_battle for update;
  if b.id is null then raise exception 'REMATCH_ERR:gone'; end if;
  if b.status <> 'finished' then raise exception 'REMATCH_ERR:unfinished'; end if;
  if b.p2 is null then raise exception 'REMATCH_ERR:no_opponent'; end if;
  if uid <> b.p1 and uid <> b.p2 then raise exception 'REMATCH_ERR:not_yours'; end if;

  sid := coalesce(b.series_id, b.id);

  -- Three games decide it. A fourth is a new series, not a longer one.
  select count(*) into played
    from public.battles x
   where coalesce(x.series_id, x.id) = sid and x.status = 'finished';
  if played >= 3 then raise exception 'REMATCH_ERR:series_over'; end if;

  -- Somebody already built the next game while we were deciding.
  select * into nxt from public.battles x
   where x.rematch_of = p_battle and x.status in ('invited', 'waiting', 'active')
   limit 1;
  if nxt.id is not null then return nxt; end if;

  if uid = b.p1 then
    update public.battles set p1_rematch = true where id = p_battle returning * into b;
  else
    update public.battles set p2_rematch = true where id = p_battle returning * into b;
  end if;

  -- One side is not an agreement.
  if not (b.p1_rematch and b.p2_rematch) then
    return null;
  end if;

  select count(*) filter (where x.winner = b.p1),
         count(*) filter (where x.winner = b.p2)
    into wins_p1, wins_p2
    from public.battles x
   where coalesce(x.series_id, x.id) = sid and x.status = 'finished';

  -- Already 2-0: there is nothing left to settle.
  if greatest(wins_p1, wins_p2) >= 2 then
    raise exception 'REMATCH_ERR:series_over';
  end if;

  insert into public.battles
    (mode, status, p1, p2, questions, cefr, started_at,
     rematch_of, series_id, series_game, p1_lang, p2_lang,
     p1_seen_at, p2_seen_at)
  values
    (b.mode, 'active', b.p1, b.p2, b.questions, b.cefr, now(),
     p_battle, sid, played + 1, b.p1_lang, b.p2_lang, now(), now())
  returning * into nxt;

  return nxt;
end;
$$;

-- Where a series stands, for the panel both players see.
create or replace function public.series_state(p_battle uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b   public.battles;
  sid uuid;
  mine integer;
  theirs integer;
  drawn integer;
  played integer;
begin
  select * into b from public.battles where id = p_battle;
  if b.id is null then return null; end if;
  sid := coalesce(b.series_id, b.id);

  select count(*) filter (where x.winner = uid),
         count(*) filter (where x.winner is not null and x.winner <> uid),
         count(*) filter (where x.is_draw),
         count(*)
    into mine, theirs, drawn, played
    from public.battles x
   where coalesce(x.series_id, x.id) = sid and x.status = 'finished';

  return jsonb_build_object(
    'series_id', sid,
    'played',    played,
    'mine',      mine,
    'theirs',    theirs,
    'drawn',     drawn,
    'decided',   played >= 3 or greatest(mine, theirs) >= 2,
    'i_offered', case when uid = b.p1 then b.p1_rematch else b.p2_rematch end,
    'they_offered', case when uid = b.p1 then b.p2_rematch else b.p1_rematch end
  );
end;
$$;

-- ── Presence: pause instead of running the clock alone ─────
create or replace function public.touch_battle(p_battle uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b   public.battles;
  opp_seen timestamptz;
  opp_done boolean;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  update public.battles
     set p1_seen_at = case when p1 = uid then now() else p1_seen_at end,
         p2_seen_at = case when p2 = uid then now() else p2_seen_at end
   where id = p_battle and (p1 = uid or p2 = uid)
  returning * into b;
  if b.id is null then raise exception 'not your battle'; end if;

  if b.p1 = uid then
    opp_seen := b.p2_seen_at; opp_done := b.p2_done;
  else
    opp_seen := b.p1_seen_at; opp_done := b.p1_done;
  end if;

  return jsonb_build_object(
    'status',        b.status,
    'opponent_done', opp_done,
    -- null when there is no human on the other side (a bot never leaves).
    'opponent_gap',  case when b.p2 is null then null
                     else coalesce(extract(epoch from (now() - opp_seen))::int, 0) end,
    -- Eight seconds of silence is a lost connection, not a slow reader: the
    -- client touches every three.
    'paused',        b.p2 is not null and not opp_done
                     and coalesce(extract(epoch from (now() - opp_seen)), 0) > 8,
    -- And after ninety, they are not coming back.
    'can_claim',     b.p2 is not null and not opp_done
                     and coalesce(extract(epoch from (now() - opp_seen)), 0) > 90
  );
end;
$$;

-- What to drop the learner back into when they reopen the app.
create or replace function public.my_open_battle()
returns public.battles
language sql
stable
security definer
set search_path to 'public'
as $$
  select b.* from public.battles b
  where (b.p1 = auth.uid() or b.p2 = auth.uid())
    and b.status = 'active'
    and coalesce(b.started_at, b.created_at) > now() - interval '30 minutes'
    and not (b.p1 = auth.uid() and b.p1_done)
    and not (b.p2 = auth.uid() and b.p2_done)
  order by b.created_at desc
  limit 1;
$$;

-- ── Grants ─────────────────────────────────────────────────
grant execute on function public.user_busy(uuid)                         to authenticated;
grant execute on function public.invite_friend_battle(uuid, jsonb, text, text) to authenticated;
grant execute on function public.respond_battle_invite(uuid, boolean, text)    to authenticated;
grant execute on function public.expire_battle_invites()                 to authenticated;
grant execute on function public.my_battle_invites()                     to authenticated;
grant execute on function public.offer_rematch(uuid)                     to authenticated;
grant execute on function public.series_state(uuid)                      to authenticated;
grant execute on function public.touch_battle(uuid)                      to authenticated;
grant execute on function public.my_open_battle()                        to authenticated;

notify pgrst, 'reload schema';
