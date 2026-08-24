-- supabase/sql/v5_rooms.sql
--
-- v5.0 — EN-44 / KK-2: a private battle for three or four friends.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- `battles` has p1 and p2 and nothing else, so every head-to-head mode in this
-- app is structurally two people. A room is the missing shape: a host, a code,
-- a roster with a ready flag on each member, and one question set everybody
-- plays.
--
-- EN-44 is explicit that "the Battle starts only after the required players
-- are ready", so start_room refuses while anybody is not — enforced here and
-- not only in the UI, because the host's phone is not a referee.
--
-- Realtime matters more here than anywhere else in the app: a lobby where you
-- cannot see somebody join is not a lobby. `battles` is already in the
-- publication; these two are added at the bottom.

create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  host        uuid not null references auth.users(id) on delete cascade,
  code        text unique,
  mode        text not null default 'friend',
  cefr        text not null default 'A1',
  status      text not null default 'waiting'
                check (status in ('waiting', 'running', 'finished')),
  questions   jsonb not null default '[]'::jsonb,
  max_players integer not null default 4 check (max_players between 2 and 6),
  created_at  timestamptz not null default now(),
  started_at  timestamptz,
  -- A lobby nobody ever started is rubbish after an hour, and without this
  -- the join-by-code space fills up with them.
  expires_at  timestamptz not null default (now() + interval '1 hour')
);

create table if not exists public.room_members (
  room_id   uuid not null references public.rooms(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  ready     boolean not null default false,
  score     integer not null default 0,
  correct   integer not null default 0,
  done      boolean not null default false,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (room_id, user_id)
);

create index if not exists room_members_by_user on public.room_members (user_id);
create index if not exists rooms_open on public.rooms (code) where status = 'waiting';

alter table public.rooms        enable row level security;
alter table public.room_members enable row level security;

-- Anybody in the room may read it, and a waiting room with a code is readable
-- by anyone holding that code — which is how joining works at all.
drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms
  for select using (
    host = auth.uid()
    or exists (select 1 from public.room_members m
                where m.room_id = id and m.user_id = auth.uid())
    or (status = 'waiting' and code is not null));

drop policy if exists room_members_read on public.room_members;
create policy room_members_read on public.room_members
  for select using (
    exists (select 1 from public.room_members m
             where m.room_id = room_members.room_id and m.user_id = auth.uid())
    or exists (select 1 from public.rooms r
                where r.id = room_members.room_id and r.host = auth.uid()));

-- Every write goes through a function. A client that can UPDATE room_members
-- directly can set its own score, and the whole point of the ready flag is
-- that one person cannot start the game for everybody.

-- ── Helpers ────────────────────────────────────────────────
create or replace function public._room_code()
returns text
language plpgsql
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  out   text := '';
  i     integer;
begin
  -- No I, O, 0 or 1: this code is read aloud and typed in by hand.
  for i in 1..5 loop
    out := out || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return out;
end;
$$;

create or replace function public.room_state(p_room uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'id',          r.id,
    'code',        r.code,
    'host',        r.host,
    'i_am_host',   r.host = auth.uid(),
    'status',      r.status,
    'cefr',        r.cefr,
    'max_players', r.max_players,
    'questions',   case when r.status = 'running' then r.questions
                        else '[]'::jsonb end,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id',      p.id,
               'name',         coalesce(nullif(btrim(p.display_name), ''),
                                        p.username, ''),
               'avatar_emoji', p.avatar_emoji,
               'ready',        m.ready,
               'score',        m.score,
               'correct',      m.correct,
               'done',         m.done,
               'is_host',      p.id = r.host,
               'is_me',        p.id = auth.uid())
             order by m.joined_at)
      from public.room_members m
      join public.profiles p on p.id = m.user_id
      where m.room_id = r.id), '[]'::jsonb),
    -- What start_room checks, surfaced so the host's button can say why it is
    -- disabled instead of simply being disabled.
    'all_ready', not exists (
      select 1 from public.room_members m
       where m.room_id = r.id and not m.ready),
    'player_count', (select count(*) from public.room_members m
                      where m.room_id = r.id)
  )
  from public.rooms r
  where r.id = p_room;
$$;

-- ── Lifecycle ──────────────────────────────────────────────
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
  uid uuid := auth.uid();
  rid uuid;
  code text;
  tries integer := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Топтық баттл үшін тіркелу керек';
  end if;

  -- One open room per host. Otherwise a host who taps twice leaves a lobby
  -- their friends are sitting in while they wait in a different one.
  delete from public.rooms
   where host = uid and status = 'waiting';

  loop
    tries := tries + 1;
    code := public._room_code();
    exit when not exists (
      select 1 from public.rooms
       where rooms.code = code and status = 'waiting');
    if tries > 12 then raise exception 'could not allocate a code'; end if;
  end loop;

  insert into public.rooms (host, code, cefr, questions, max_players)
  values (uid, code, coalesce(p_cefr, 'A1'), coalesce(p_questions, '[]'::jsonb),
          greatest(2, least(coalesce(p_max, 4), 6)))
  returning id into rid;

  -- The host is ready by definition: they are the one who opened it.
  insert into public.room_members (room_id, user_id, ready)
  values (rid, uid, true);

  return public.room_state(rid);
end;
$$;

create or replace function public.join_room(p_code text)
returns jsonb
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

  select * into r from public.rooms
   where code = upper(btrim(coalesce(p_code, '')))
     and status = 'waiting'
     and expires_at > now()
   limit 1;
  if r.id is null then
    raise exception 'GUEST_LOCKED: Код табылмады немесе ескірген';
  end if;

  select count(*) into n from public.room_members where room_id = r.id;
  if n >= r.max_players
     and not exists (select 1 from public.room_members
                      where room_id = r.id and user_id = uid) then
    raise exception 'GUEST_LOCKED: Бөлме толы';
  end if;

  insert into public.room_members (room_id, user_id)
  values (r.id, uid)
  on conflict (room_id, user_id) do update set last_seen = now();

  return public.room_state(r.id);
end;
$$;

create or replace function public.set_ready(p_room uuid, p_ready boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.room_members
     set ready = coalesce(p_ready, false), last_seen = now()
   where room_id = p_room and user_id = auth.uid();
  return public.room_state(p_room);
end;
$$;

create or replace function public.leave_room(p_room uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  r   public.rooms;
begin
  select * into r from public.rooms where id = p_room;
  if r.id is null then return; end if;

  delete from public.room_members where room_id = p_room and user_id = uid;

  -- The host leaving ends the lobby rather than stranding everybody in a room
  -- nobody can start.
  if r.host = uid and r.status = 'waiting' then
    delete from public.rooms where id = p_room;
  end if;
end;
$$;

-- EN-44: "The Battle starts only after the required players are ready."
-- Checked here because the host's phone is not a referee.
create or replace function public.start_room(p_room uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  r   public.rooms;
  n   integer;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null then raise exception 'no such room'; end if;
  if r.host <> uid then raise exception 'GUEST_LOCKED: Тек құрушы бастай алады'; end if;
  if r.status <> 'waiting' then return public.room_state(p_room); end if;

  select count(*) into n from public.room_members where room_id = p_room;
  if n < 2 then
    raise exception 'GUEST_LOCKED: Кемінде 2 ойыншы керек';
  end if;
  if exists (select 1 from public.room_members
              where room_id = p_room and not ready) then
    raise exception 'GUEST_LOCKED: Барлығы дайын болуы керек';
  end if;

  update public.rooms
     set status = 'running', started_at = now()
   where id = p_room;

  return public.room_state(p_room);
end;
$$;

create or replace function public.submit_room_score(
  p_room uuid, p_score integer, p_correct integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  r   public.rooms;
  qn  integer;
  cap integer;
begin
  select * into r from public.rooms where id = p_room;
  if r.id is null then raise exception 'no such room'; end if;

  -- Same clamp as a battle: ten points a question plus a speed and a combo
  -- bonus never puts one past forty.
  qn  := greatest(1, coalesce(jsonb_array_length(r.questions), 10));
  cap := qn * 40;

  update public.room_members
     set score   = greatest(0, least(coalesce(p_score, 0), cap)),
         correct = greatest(0, least(coalesce(p_correct, 0), qn)),
         done    = true,
         last_seen = now()
   where room_id = p_room and user_id = uid;

  -- Everybody finished: the room is over and XP is paid by placing.
  if not exists (select 1 from public.room_members
                  where room_id = p_room and not done) then
    update public.rooms set status = 'finished' where id = p_room;
    perform public._award_room(p_room);
  end if;

  return public.room_state(p_room);
end;
$$;

-- Pays everybody who played. Written as its own function because it awards
-- people who are not the caller, which add_xp cannot do.
create or replace function public._award_room(p_room uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  m record;
  place integer := 0;
  amount integer;
begin
  for m in
    select user_id, score from public.room_members
     where room_id = p_room order by score desc, joined_at
  loop
    place := place + 1;
    amount := case place when 1 then 70 when 2 then 40 else 25 end;
    update public.profiles
       set xp = greatest(0, xp + amount),
           coins = greatest(0, coins + greatest(0, amount / 10))
     where id = m.user_id;
    insert into public.xp_log (user_id, amount, source)
    values (m.user_id, amount, 'room_battle');
  end loop;
end;
$$;

-- ── Realtime ───────────────────────────────────────────────
-- A lobby where you cannot see somebody join is not a lobby.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'rooms') then
    alter publication supabase_realtime add table public.rooms;
  end if;
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'room_members') then
    alter publication supabase_realtime add table public.room_members;
  end if;
end;
$$;

revoke execute on function public._award_room(uuid) from authenticated, anon;
grant execute on function public.room_state(uuid)                     to authenticated;
grant execute on function public.create_room(text, jsonb, integer)    to authenticated;
grant execute on function public.join_room(text)                      to authenticated;
grant execute on function public.set_ready(uuid, boolean)             to authenticated;
grant execute on function public.leave_room(uuid)                     to authenticated;
grant execute on function public.start_room(uuid)                     to authenticated;
grant execute on function public.submit_room_score(uuid, integer, integer)
  to authenticated;

notify pgrst, 'reload schema';
