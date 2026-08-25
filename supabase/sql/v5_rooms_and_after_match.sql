-- supabase/sql/v5_rooms_and_after_match.sql
--
-- v5.0 — the group lobby stops erroring, gets real invitations, and a
-- finished match stops being a dead end.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run. Run it AFTER v5_rooms.sql and v5_match_consent.sql.
--
-- ── 1. The reported crash ──────────────────────────────────
--
--   ERROR: column reference "code" is ambiguous
--
-- create_room declares a local variable called `code` and then writes
-- `where rooms.code = code`. To PL/pgSQL the right-hand `code` is both the
-- column and the variable, so it refuses to guess — and creating a group
-- room failed every single time. Renaming the variable is the whole fix; it
-- is kept as a separate file rather than an edit to v5_rooms.sql so the
-- history says what happened.

create or replace function public.create_room(
  p_cefr text default 'A1',
  p_questions jsonb default '[]'::jsonb,
  p_max integer default 4)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid    uuid := auth.uid();
  rid    uuid;
  v_code text;
  tries  integer := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Топтық баттл үшін тіркелу керек';
  end if;

  -- One open room per host. Otherwise a host who taps twice leaves a lobby
  -- their friends are sitting in while they wait in a different one.
  delete from public.rooms where host = uid and status = 'waiting';

  loop
    tries := tries + 1;
    v_code := public._room_code();
    exit when not exists (
      select 1 from public.rooms r
       where r.code = v_code and r.status = 'waiting');
    if tries > 12 then raise exception 'could not allocate a code'; end if;
  end loop;

  insert into public.rooms (host, code, cefr, questions, max_players)
  values (uid, v_code, coalesce(p_cefr, 'A1'), coalesce(p_questions, '[]'::jsonb),
          greatest(2, least(coalesce(p_max, 4), 6)))
  returning id into rid;

  -- The host is ready by definition: they are the one who opened it.
  insert into public.room_members (room_id, user_id, ready)
  values (rid, uid, true);

  return public.room_state(rid);
end;
$$;

-- ── 2. Inviting friends into the room ──────────────────────
--
-- A five-letter code you read aloud is fine between two people in the same
-- kitchen and useless otherwise. "Бірі бірін шақырып алып сосын барып
-- бастайтындай" needs an invitation that arrives on the friend's screen,
-- the same way a battle invitation does.

create table if not exists public.room_invites (
  room_id    uuid not null references public.rooms(id) on delete cascade,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  -- Longer than a battle invite on purpose: a lobby is a place you drift
  -- into, not a bell that rings for fifteen seconds.
  expires_at timestamptz not null default now() + interval '3 minutes',
  primary key (room_id, to_user)
);
alter table public.room_invites enable row level security;
drop policy if exists room_invites_mine on public.room_invites;
create policy room_invites_mine on public.room_invites
  for select to authenticated
  using (to_user = auth.uid() or from_user = auth.uid());

create index if not exists room_invites_to_idx
  on public.room_invites (to_user, expires_at);

create or replace function public.invite_to_room(p_room uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  r   public.rooms;
  n   integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into r from public.rooms where id = p_room;
  if r.id is null or r.status <> 'waiting' then
    raise exception 'ROOM_ERR:closed';
  end if;
  if not exists (select 1 from public.room_members m
                  where m.room_id = p_room and m.user_id = uid) then
    raise exception 'ROOM_ERR:not_member';
  end if;
  if p_user = uid then raise exception 'ROOM_ERR:self'; end if;

  if not exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = uid and f.addressee = p_user)
        or (f.requester = p_user and f.addressee = uid))
  ) then
    raise exception 'ROOM_ERR:not_friend';
  end if;

  select count(*) into n from public.room_members where room_id = p_room;
  if n >= r.max_players then raise exception 'ROOM_ERR:full'; end if;

  -- Already in the lobby: nothing to invite them to.
  if exists (select 1 from public.room_members m
              where m.room_id = p_room and m.user_id = p_user) then
    return;
  end if;

  insert into public.room_invites (room_id, from_user, to_user, expires_at)
  values (p_room, uid, p_user, now() + interval '3 minutes')
  on conflict (room_id, to_user) do update
    set from_user = excluded.from_user,
        created_at = now(),
        expires_at = excluded.expires_at;
end;
$$;

create or replace function public.my_room_invites()
returns table (
  room_id      uuid,
  code         text,
  from_user    uuid,
  username     text,
  display_name text,
  avatar_emoji text,
  players      integer,
  max_players  integer,
  seconds_left integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select r.id, r.code, p.id, p.username, p.display_name, p.avatar_emoji,
         (select count(*)::int from public.room_members m where m.room_id = r.id),
         r.max_players,
         greatest(0, ceil(extract(epoch from (i.expires_at - now()))))::int
  from public.room_invites i
  join public.rooms r on r.id = i.room_id
  join public.profiles p on p.id = i.from_user
  where i.to_user = auth.uid()
    and i.expires_at > now()
    and r.status = 'waiting'
  order by i.created_at desc;
$$;

create or replace function public.decline_room_invite(p_room uuid)
returns void
language sql
security definer
set search_path to 'public'
as $$
  delete from public.room_invites
   where room_id = p_room and to_user = auth.uid();
$$;

-- ── 3. A finished match is a place two people just met ─────
--
-- "матч біткенде қарсыластар бір біріне достық жібере алады, хат жібере
-- алады, быстрый сообщение деген секілді". The friend request already has an
-- RPC; the message does not, and it is deliberately NOT free text. A canned
-- phrase cannot be abuse, needs no moderation queue, and is faster to tap
-- than to type — which is the whole point of a quick message.

create table if not exists public.battle_messages (
  id         bigserial primary key,
  battle_id  uuid not null references public.battles(id) on delete cascade,
  from_user  uuid not null references auth.users(id) on delete cascade,
  phrase     text not null,
  created_at timestamptz not null default now()
);
alter table public.battle_messages enable row level security;
drop policy if exists battle_messages_read on public.battle_messages;
create policy battle_messages_read on public.battle_messages
  for select to authenticated
  using (exists (
    select 1 from public.battles b
    where b.id = battle_id and (b.p1 = auth.uid() or b.p2 = auth.uid())
  ));

create index if not exists battle_messages_battle_idx
  on public.battle_messages (battle_id, created_at);

-- The whole vocabulary. The client shows these as buttons; the server keeps
-- the list so a new phrase does not need an app release, and so nothing else
-- can ever be sent.
create or replace function public.quick_phrases()
returns table (code text, kk text, ru text)
language sql
immutable
as $$
  values
    ('gg',      'Жақсы ойын!',        'Хорошая игра!'),
    ('respect', 'Мықтысың!',          'Ты силён!'),
    ('close',   'Тығыз болды',        'Было напряжённо'),
    ('again',   'Тағы ойнайық',       'Сыграем ещё'),
    ('luck',    'Сәттілік!',          'Удачи!'),
    ('thanks',  'Рахмет',             'Спасибо');
$$;

create or replace function public.send_battle_message(p_battle uuid, p_phrase text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b   public.battles;
  n   integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.quick_phrases() q where q.code = p_phrase) then
    raise exception 'MSG_ERR:unknown_phrase';
  end if;

  select * into b from public.battles where id = p_battle;
  if b.id is null then raise exception 'MSG_ERR:gone'; end if;
  if uid <> b.p1 and uid <> b.p2 then raise exception 'MSG_ERR:not_yours'; end if;
  if b.p2 is null then raise exception 'MSG_ERR:no_opponent'; end if;

  -- Three per match, per person. A canned phrase is still spam if it can be
  -- sent forty times.
  select count(*) into n from public.battle_messages
   where battle_id = p_battle and from_user = uid;
  if n >= 3 then raise exception 'MSG_ERR:enough'; end if;

  insert into public.battle_messages (battle_id, from_user, phrase)
  values (p_battle, uid, p_phrase);
end;
$$;

create or replace function public.battle_messages_for(p_battle uuid)
returns table (
  from_user uuid,
  is_mine   boolean,
  phrase    text,
  kk        text,
  ru        text,
  created_at timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select m.from_user, m.from_user = auth.uid(), m.phrase, q.kk, q.ru, m.created_at
  from public.battle_messages m
  join public.quick_phrases() q on q.code = m.phrase
  join public.battles b on b.id = m.battle_id
  where m.battle_id = p_battle
    and (b.p1 = auth.uid() or b.p2 = auth.uid())
  order by m.created_at;
$$;

-- Who did I just play, and can I add them? One call so the end-of-match card
-- can draw both actions without guessing.
create or replace function public.opponent_card(p_battle uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  b   public.battles;
  opp uuid;
  p   public.profiles;
  rel text;
begin
  select * into b from public.battles where id = p_battle;
  if b.id is null then return null; end if;
  if uid <> b.p1 and uid <> b.p2 then return null; end if;
  opp := case when b.p1 = uid then b.p2 else b.p1 end;
  if opp is null then return null; end if;

  select * into p from public.profiles where id = opp;

  select f.status into rel from public.friendships f
   where (f.requester = uid and f.addressee = opp)
      or (f.requester = opp and f.addressee = uid)
   limit 1;

  return jsonb_build_object(
    'user_id',      p.id,
    'username',     p.username,
    'display_name', p.display_name,
    'avatar_emoji', p.avatar_emoji,
    'elo',          p.elo,
    'cefr',         p.cefr_level,
    'friendship',   coalesce(rel, 'none'),
    'can_add',      coalesce(rel, 'none') = 'none' and not p.is_guest
  );
end;
$$;

grant execute on function public.create_room(text, jsonb, integer) to authenticated;
grant execute on function public.invite_to_room(uuid, uuid)        to authenticated;
grant execute on function public.my_room_invites()                 to authenticated;
grant execute on function public.decline_room_invite(uuid)         to authenticated;
grant execute on function public.quick_phrases()                   to authenticated, anon;
grant execute on function public.send_battle_message(uuid, text)   to authenticated;
grant execute on function public.battle_messages_for(uuid)         to authenticated;
grant execute on function public.opponent_card(uuid)               to authenticated;

notify pgrst, 'reload schema';
