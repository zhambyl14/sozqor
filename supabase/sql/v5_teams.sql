-- supabase/sql/v5_teams.sql
--
-- v5.0 — EN-24 / EN-25 / EN-26 / KK-4: real teams, a weekly team challenge,
-- and a one-day team-versus-team boss war.
--
-- Paste this whole file into the Supabase SQL editor and run it once. Every
-- object is created with `if not exists` or `create or replace`, so running it
-- a second time changes nothing.
--
-- Until this runs there is no team system on the server at all. providers.dart
-- calls a "clan" whatever set of people you happen to have added as friends,
-- and clan_screen.dart renders a weekly race between them that nobody agreed
-- to join, nobody can leave, and no two people see the same version of. This
-- file replaces that fiction with rows.
--
-- THE TWO RULES THE PRD IS EXPLICIT ABOUT LIVE HERE, IN SQL, NOT IN THE UI:
--
--   EN-25, fair contribution. One strong player must not be able to carry the
--   whole weekly goal. Every member's counted contribution is capped at 40% of
--   the team goal, and the reward additionally needs at least 3 DISTINCT
--   members to have put something in. A team of one therefore cannot finish a
--   week, which is the point — the weekly challenge is a *team* challenge, and
--   a rule the client enforces is a rule anybody with a REST client ignores.
--
--   EN-26, the war. One day long, at most 3 counted matches per player, and a
--   team scores nothing at all until 3 distinct members have played. Both
--   halves matter: the per-player cap stops one person playing the whole war,
--   the participation floor stops one person BEING the whole war.
--
-- KK-4 asks that the war not be another test. It is a hunt: both teams face
-- the same boss and every match score is damage. The first team to fell it
-- wins outright; if it is still standing at midnight UTC the team that did
-- more damage wins. The frame is entirely client-side text — the server only
-- has to know that damage accumulates and that a threshold ends the day.
--
-- Nothing here trusts a number the client sent. contribute_team_xp treats its
-- argument as an upper bound and counts what `xp_log` actually recorded, so a
-- forged call cannot inflate a goal; submit_war_match clamps one match's
-- damage to a value a real round can produce. Every function below is
-- SECURITY DEFINER and, because the SQL editor runs as `postgres`, owned by
-- postgres — which is what lets them write past profiles_guard the same way
-- add_xp does.

-- ═══════════════════════════════════════════════════════════
-- Tables
-- ═══════════════════════════════════════════════════════════

create table if not exists public.teams (
  id           bigserial primary key,
  name         text not null,
  tag          text unique,
  emblem       text not null default '🛡️',
  colour       text not null default '#7C5CFF',
  owner        uuid references public.profiles(id) on delete set null,
  description  text,
  is_open      boolean not null default true,
  member_limit integer not null default 20,
  created_at   timestamptz not null default now(),
  -- Lifetime XP the roster has contributed, and the badge level it buys. Both
  -- are moved only by contribute_team_xp.
  xp           integer not null default 0,
  level        integer not null default 1
);

create table if not exists public.team_members (
  team_id        bigint not null references public.teams(id) on delete cascade,
  user_id        uuid   not null references public.profiles(id) on delete cascade,
  role           text   not null default 'member'
                 check (role in ('owner', 'officer', 'member')),
  joined_at      timestamptz not null default now(),
  contributed_xp integer not null default 0,
  primary key (team_id, user_id)
);

-- One team per person. Without this a player could stand in three teams and
-- have the same weekly XP counted three times, and `my_team()` would have no
-- honest answer to give.
create unique index if not exists team_members_one_team_per_user
  on public.team_members (user_id);

create table if not exists public.team_invites (
  id         bigserial primary key,
  team_id    bigint not null references public.teams(id) on delete cascade,
  user_id    uuid   not null references public.profiles(id) on delete cascade,
  invited_by uuid   references public.profiles(id) on delete set null,
  status     text   not null default 'pending'
             check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now()
);

-- A team may ask a given person once at a time. Answered invitations are kept
-- as history, so the uniqueness is partial rather than a plain constraint.
create unique index if not exists team_invites_one_pending
  on public.team_invites (team_id, user_id) where status = 'pending';

create index if not exists team_invites_for_user
  on public.team_invites (user_id) where status = 'pending';

create table if not exists public.team_weekly (
  team_id    bigint  not null references public.teams(id) on delete cascade,
  week_start date    not null,
  goal       integer not null default 1500,
  progress   integer not null default 0,
  claimed    boolean not null default false,
  primary key (team_id, week_start)
);

create table if not exists public.team_weekly_contrib (
  team_id    bigint  not null,
  week_start date    not null,
  user_id    uuid    not null references public.profiles(id) on delete cascade,
  xp         integer not null default 0,
  primary key (team_id, week_start, user_id),
  foreign key (team_id, week_start)
    references public.team_weekly (team_id, week_start) on delete cascade
);

create table if not exists public.team_wars (
  id         bigserial primary key,
  team_a     bigint not null references public.teams(id) on delete cascade,
  -- Null while the war sits in the queue waiting for a second team.
  team_b     bigint references public.teams(id) on delete cascade,
  day        date not null default (now() at time zone 'utc')::date,
  status     text not null default 'open'
             check (status in ('open', 'running', 'finished')),
  a_score    integer not null default 0,
  b_score    integer not null default 0,
  -- Carried on the row rather than read from team_rules() at display time, so
  -- a war that is already under way is never re-balanced beneath the players.
  boss_hp    integer not null default 3000,
  winner     bigint references public.teams(id) on delete set null,
  created_at timestamptz not null default now()
);

-- A team fights one war a day. Two partial indexes rather than one, because a
-- team can be on either side of the pairing.
create unique index if not exists team_wars_one_open_a
  on public.team_wars (team_a, day) where status <> 'finished';
create unique index if not exists team_wars_one_open_b
  on public.team_wars (team_b, day) where status <> 'finished' and team_b is not null;

create table if not exists public.team_war_matches (
  id        bigserial primary key,
  war_id    bigint not null references public.team_wars(id) on delete cascade,
  user_id   uuid   not null references public.profiles(id) on delete cascade,
  team_id   bigint not null references public.teams(id) on delete cascade,
  score     integer not null default 0,
  played_at timestamptz not null default now()
);

create index if not exists team_war_matches_by_war
  on public.team_war_matches (war_id, user_id);

-- ═══════════════════════════════════════════════════════════
-- Row level security
-- ═══════════════════════════════════════════════════════════
--
-- Teams are public: anybody signed in may read a roster or a war, which is
-- what makes team_detail_screen and the team board possible. Nothing here
-- grants INSERT, UPDATE or DELETE to a client — every write goes through one
-- of the SECURITY DEFINER functions below, so the caps and the participation
-- floors cannot be walked around by writing the table directly.

alter table public.teams               enable row level security;
alter table public.team_members        enable row level security;
alter table public.team_invites        enable row level security;
alter table public.team_weekly         enable row level security;
alter table public.team_weekly_contrib enable row level security;
alter table public.team_wars           enable row level security;
alter table public.team_war_matches    enable row level security;

drop policy if exists teams_read on public.teams;
create policy teams_read on public.teams
  for select to authenticated using (true);

drop policy if exists team_members_read on public.team_members;
create policy team_members_read on public.team_members
  for select to authenticated using (true);

-- An invitation is between one team and one person; nobody else needs to see
-- who a team is courting.
drop policy if exists team_invites_read on public.team_invites;
create policy team_invites_read on public.team_invites
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.team_members m
                where m.team_id = team_invites.team_id and m.user_id = auth.uid())
  );

drop policy if exists team_weekly_read on public.team_weekly;
create policy team_weekly_read on public.team_weekly
  for select to authenticated using (true);

drop policy if exists team_weekly_contrib_read on public.team_weekly_contrib;
create policy team_weekly_contrib_read on public.team_weekly_contrib
  for select to authenticated using (true);

drop policy if exists team_wars_read on public.team_wars;
create policy team_wars_read on public.team_wars
  for select to authenticated using (true);

drop policy if exists team_war_matches_read on public.team_war_matches;
create policy team_war_matches_read on public.team_war_matches
  for select to authenticated using (true);

grant select on public.teams               to authenticated;
grant select on public.team_members        to authenticated;
grant select on public.team_invites        to authenticated;
grant select on public.team_weekly         to authenticated;
grant select on public.team_weekly_contrib to authenticated;
grant select on public.team_wars           to authenticated;
grant select on public.team_war_matches    to authenticated;

-- ═══════════════════════════════════════════════════════════
-- The rules, in one place
-- ═══════════════════════════════════════════════════════════

-- Every balance number the system has. The functions below read it instead of
-- carrying their own copies, and the state RPCs hand it to the client so the
-- screens can *show* the rule rather than restate a constant that has since
-- moved. Changing a number here changes the game everywhere at once.
create or replace function public.team_rules()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'member_limit',         20,
    -- EN-25: no member's counted contribution may exceed this share of the
    -- weekly goal, and no fewer than this many members may finish it.
    'cap_share',            0.40,
    'min_contributors',     3,
    -- EN-26: 3v3 minimum, three counted matches each, and a floor of three
    -- distinct players before a side scores at all.
    'min_team_for_war',     3,
    'war_match_limit',      3,
    'war_min_players',      3,
    'war_boss_hp',          3000,
    -- A perfect ten-question round is worth roughly 350 in play_session_screen;
    -- anything above this did not come out of a round.
    'war_match_max_damage', 400
  );
$$;

-- ═══════════════════════════════════════════════════════════
-- Internal helpers
-- ═══════════════════════════════════════════════════════════

create or replace function public._team_of(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path to 'public'
as $$
  select team_id from public.team_members where user_id = p_user;
$$;

create or replace function public.team_info(p_team bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'id',           t.id,
    'name',         t.name,
    'tag',          t.tag,
    'emblem',       t.emblem,
    'colour',       t.colour,
    'owner',        t.owner,
    'description',  t.description,
    'is_open',      t.is_open,
    'member_limit', t.member_limit,
    'xp',           t.xp,
    'level',        t.level,
    'member_count', (select count(*) from public.team_members m where m.team_id = t.id),
    'my_role',      (select m.role from public.team_members m
                      where m.team_id = t.id and m.user_id = auth.uid()),
    'created_at',   t.created_at
  )
  from public.teams t
  where t.id = p_team;
$$;

-- Grants a player XP and the coins that go with it, the same tenth-of-XP rate
-- add_xp has always used, and leaves the audit row `xp_log` expects. Written
-- here rather than calling add_xp because add_xp awards *the caller*, and both
-- the weekly claim and the end of a war pay out to people who are not the one
-- making the request.
create or replace function public._team_award(p_user uuid, p_amount integer, p_source text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_user is null or p_amount is null or p_amount <= 0 then return; end if;
  update public.profiles
     set xp = xp + p_amount,
         coins = coins + (p_amount / 10)
   where id = p_user;
  insert into public.xp_log (user_id, amount, source) values (p_user, p_amount, p_source);
end;
$$;

-- Opens (or refreshes) this week's row for a team.
--
-- The goal follows the roster rather than being fixed at creation: a team that
-- recruits mid-week must clear a higher bar, or a stalled week could be
-- finished simply by adding people to it after the fact. A week already
-- claimed is left alone so the number the team saw when it won stays true.
create or replace function public._ensure_team_week(p_team bigint)
returns public.team_weekly
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  ws date := public.week_start(current_date);
  n  integer;
  g  integer;
  w  public.team_weekly;
begin
  select count(*) into n from public.team_members where team_id = p_team;
  g := greatest(1500, least(12000, 500 * greatest(n, 1)));

  insert into public.team_weekly (team_id, week_start, goal)
  values (p_team, ws, g)
  on conflict (team_id, week_start) do nothing;

  update public.team_weekly
     set goal = g
   where team_id = p_team and week_start = ws and not claimed and goal <> g;

  select * into w from public.team_weekly where team_id = p_team and week_start = ws;
  return w;
end;
$$;

-- Ends a war and pays it out.
--
-- [p_force] is the deadline: false means "somebody may just have felled the
-- boss, finish only if they did", true means "the day is over, count what is
-- on the board". Either way a side whose damage does not clear the
-- participation floor counts as zero, which is the EN-26 rule that a team
-- cannot win on one person's back.
create or replace function public._settle_war(p_war bigint, p_force boolean default false)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  w        public.team_wars;
  r        jsonb := public.team_rules();
  floor_n  integer := (r->>'war_min_players')::int;
  a_players integer; b_players integer;
  a_eff integer; b_eff integer;
  win bigint := null;
  m record;
begin
  select * into w from public.team_wars where id = p_war for update;
  if w.id is null or w.status = 'finished' then return; end if;

  select count(distinct user_id) into a_players
    from public.team_war_matches where war_id = w.id and team_id = w.team_a;
  select count(distinct user_id) into b_players
    from public.team_war_matches where war_id = w.id and team_id = w.team_b;

  a_eff := case when a_players >= floor_n then w.a_score else 0 end;
  b_eff := case when b_players >= floor_n then w.b_score else 0 end;

  if a_eff >= w.boss_hp and a_eff >= b_eff then
    win := w.team_a;
  elsif b_eff >= w.boss_hp and b_eff > a_eff then
    win := w.team_b;
  elsif p_force then
    if a_eff > b_eff then win := w.team_a;
    elsif b_eff > a_eff then win := w.team_b;
    end if;
  else
    -- The boss is still standing and the day is not over.
    return;
  end if;

  update public.team_wars
     set status = 'finished', winner = win, team_b = w.team_b
   where id = w.id;

  -- Only people who actually swung get paid, on either side. A war nobody on
  -- your team entered pays nothing, which is the same rule the score uses.
  for m in
    select distinct user_id, team_id from public.team_war_matches where war_id = w.id
  loop
    if win is null then
      perform public._team_award(m.user_id, 80, 'team_war_draw');
    elsif m.team_id = win then
      perform public._team_award(m.user_id, 150, 'team_war_win');
    else
      perform public._team_award(m.user_id, 40, 'team_war_loss');
    end if;
  end loop;
end;
$$;

revoke execute on function public._team_of(uuid) from public;
revoke execute on function public._team_award(uuid, integer, text) from public;
revoke execute on function public._ensure_team_week(bigint) from public;
revoke execute on function public._settle_war(bigint, boolean) from public;

-- ═══════════════════════════════════════════════════════════
-- Membership
-- ═══════════════════════════════════════════════════════════
--
-- Every user-facing failure below is raised as `TEAM_ERR:<code>`. The client
-- maps the code to a translated sentence; a bare Kazakh message from the
-- server would reach a Russian reader untranslated, which is the exact failure
-- this release exists to end.

create or replace function public.create_team(
  p_name   text,
  p_tag    text,
  p_emblem text default '🛡️',
  p_colour text default '#7C5CFF')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  nm  text := btrim(coalesce(p_name, ''));
  tg  text := upper(btrim(coalesce(p_tag, '')));
  tid bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then raise exception 'TEAM_ERR:guest'; end if;
  if public._team_of(uid) is not null then raise exception 'TEAM_ERR:already_in_team'; end if;
  if char_length(nm) < 2 or char_length(nm) > 24 then raise exception 'TEAM_ERR:bad_name'; end if;
  if tg !~ '^[A-Z0-9]{2,6}$' then raise exception 'TEAM_ERR:bad_tag'; end if;
  if exists (select 1 from public.teams where upper(tag) = tg) then
    raise exception 'TEAM_ERR:tag_taken';
  end if;

  insert into public.teams (name, tag, emblem, colour, owner, member_limit)
  values (nm, tg,
          coalesce(nullif(btrim(coalesce(p_emblem, '')), ''), '🛡️'),
          coalesce(nullif(btrim(coalesce(p_colour, '')), ''), '#7C5CFF'),
          uid,
          (public.team_rules()->>'member_limit')::int)
  returning id into tid;

  insert into public.team_members (team_id, user_id, role) values (tid, uid, 'owner');

  -- Whatever they have already earned this week counts from the moment there
  -- is a team to earn it for, otherwise founding a team on Friday costs a week.
  perform public.contribute_team_xp(0);
  return public.team_info(tid);
end;
$$;

create or replace function public.my_team()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select public.team_info(m.team_id)
  from public.team_members m
  where m.user_id = auth.uid();
$$;

-- The roster, with both the lifetime contribution and this week's, since the
-- weekly bar is what the team is actually racing.
create or replace function public.team_roster(p_team bigint)
returns table (
  user_id        uuid,
  username       text,
  display_name   text,
  avatar_emoji   text,
  cefr_level     text,
  role           text,
  contributed_xp integer,
  week_xp        integer,
  joined_at      timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level,
         m.role, m.contributed_xp,
         coalesce(c.xp, 0)::int,
         m.joined_at
  from public.team_members m
  join public.profiles p on p.id = m.user_id
  left join public.team_weekly_contrib c
         on c.team_id = m.team_id
        and c.user_id = m.user_id
        and c.week_start = public.week_start(current_date)
  where m.team_id = p_team
  order by coalesce(c.xp, 0) desc, m.joined_at asc
  limit 60;
$$;

-- Browsing teams is not the same risk as browsing people: a team is a public
-- banner somebody chose to fly, so an empty query legitimately means "show me
-- what is open". Only teams with room are offered when no query is given.
create or replace function public.search_teams(p_query text default '', p_limit integer default 20)
returns table (
  id           bigint,
  name         text,
  tag          text,
  emblem       text,
  colour       text,
  member_count integer,
  member_limit integer,
  is_open      boolean,
  xp           integer,
  level        integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  with q as (select btrim(coalesce(p_query, '')) as s)
  select t.id, t.name, t.tag, t.emblem, t.colour,
         (select count(*) from public.team_members m where m.team_id = t.id)::int,
         t.member_limit, t.is_open, t.xp, t.level
  from public.teams t, q
  where (q.s = '' and t.is_open)
     or (q.s <> '' and (t.name ilike '%' || q.s || '%' or t.tag ilike '%' || q.s || '%'))
  order by (t.tag ilike (select s from q)) desc, t.xp desc, t.created_at asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

create or replace function public.join_team(p_team bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  t   public.teams;
  n   integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then raise exception 'TEAM_ERR:guest'; end if;
  if public._team_of(uid) is not null then raise exception 'TEAM_ERR:already_in_team'; end if;

  select * into t from public.teams where id = p_team;
  if t.id is null then raise exception 'TEAM_ERR:not_found'; end if;
  if not t.is_open then raise exception 'TEAM_ERR:closed'; end if;

  select count(*) into n from public.team_members where team_id = t.id;
  if n >= t.member_limit then raise exception 'TEAM_ERR:full'; end if;

  insert into public.team_members (team_id, user_id, role) values (t.id, uid, 'member');
  update public.team_invites set status = 'accepted'
   where team_id = t.id and user_id = uid and status = 'pending';
  perform public.contribute_team_xp(0);
  return public.team_info(t.id);
end;
$$;

create or replace function public.invite_to_team(p_user uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  tid bigint := public._team_of(uid);
  me  text;
  t   public.teams;
  n   integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if tid is null then raise exception 'TEAM_ERR:no_team'; end if;
  if p_user is null or p_user = uid then raise exception 'TEAM_ERR:self'; end if;

  select role into me from public.team_members where team_id = tid and user_id = uid;
  if me not in ('owner', 'officer') then raise exception 'TEAM_ERR:forbidden'; end if;

  select * into t from public.teams where id = tid;
  select count(*) into n from public.team_members where team_id = tid;
  if n >= t.member_limit then raise exception 'TEAM_ERR:full'; end if;

  if not exists (select 1 from public.profiles where id = p_user and not is_guest) then
    raise exception 'TEAM_ERR:not_found';
  end if;
  if public._team_of(p_user) is not null then raise exception 'TEAM_ERR:target_in_team'; end if;
  if exists (select 1 from public.team_invites
              where team_id = tid and user_id = p_user and status = 'pending') then
    return 'already';
  end if;

  insert into public.team_invites (team_id, user_id, invited_by) values (tid, p_user, uid);
  return 'invited';
end;
$$;

create or replace function public.my_team_invites()
returns table (
  id              bigint,
  team_id         bigint,
  name            text,
  tag             text,
  emblem          text,
  colour          text,
  member_count    integer,
  invited_by_name text,
  created_at      timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select i.id, t.id, t.name, t.tag, t.emblem, t.colour,
         (select count(*) from public.team_members m where m.team_id = t.id)::int,
         coalesce(nullif(btrim(p.display_name), ''), p.username, ''),
         i.created_at
  from public.team_invites i
  join public.teams t on t.id = i.team_id
  left join public.profiles p on p.id = i.invited_by
  where i.user_id = auth.uid() and i.status = 'pending'
  order by i.created_at desc
  limit 30;
$$;

create or replace function public.respond_team_invite(p_id bigint, p_accept boolean)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  i   public.team_invites;
  t   public.teams;
  n   integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into i from public.team_invites where id = p_id for update;
  if i.id is null or i.status <> 'pending' then raise exception 'TEAM_ERR:invite_gone'; end if;
  if i.user_id <> uid then raise exception 'TEAM_ERR:forbidden'; end if;

  if not p_accept then
    update public.team_invites set status = 'declined' where id = p_id;
    return 'declined';
  end if;

  if public._team_of(uid) is not null then raise exception 'TEAM_ERR:already_in_team'; end if;

  select * into t from public.teams where id = i.team_id;
  if t.id is null then raise exception 'TEAM_ERR:not_found'; end if;
  select count(*) into n from public.team_members where team_id = t.id;
  if n >= t.member_limit then raise exception 'TEAM_ERR:full'; end if;

  insert into public.team_members (team_id, user_id, role) values (t.id, uid, 'member');
  update public.team_invites set status = 'accepted' where id = p_id;
  perform public.contribute_team_xp(0);
  return 'accepted';
end;
$$;

-- Leaving.
--
-- The owner walking out must not strand the team: ownership passes to the
-- longest-serving officer, or failing that the longest-serving member. A team
-- whose last person leaves is deleted outright rather than left as an empty
-- banner nobody can join or clean up.
create or replace function public.leave_team()
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid  uuid := auth.uid();
  tid  bigint := public._team_of(uid);
  me   text;
  heir uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if tid is null then raise exception 'TEAM_ERR:no_team'; end if;

  select role into me from public.team_members where team_id = tid and user_id = uid;
  delete from public.team_members where team_id = tid and user_id = uid;

  if not exists (select 1 from public.team_members where team_id = tid) then
    delete from public.teams where id = tid;
    return 'disbanded';
  end if;

  if me = 'owner' then
    select user_id into heir from public.team_members
     where team_id = tid
     order by case role when 'officer' then 0 else 1 end, joined_at asc
     limit 1;
    update public.team_members set role = 'owner' where team_id = tid and user_id = heir;
    update public.teams set owner = heir where id = tid;
  end if;

  return 'left';
end;
$$;

create or replace function public.kick_member(p_user uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid    uuid := auth.uid();
  tid    bigint := public._team_of(uid);
  me     text;
  target text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if tid is null then raise exception 'TEAM_ERR:no_team'; end if;
  if p_user = uid then raise exception 'TEAM_ERR:self'; end if;

  select role into me from public.team_members where team_id = tid and user_id = uid;
  select role into target from public.team_members where team_id = tid and user_id = p_user;
  if target is null then raise exception 'TEAM_ERR:not_member'; end if;
  if me not in ('owner', 'officer') then raise exception 'TEAM_ERR:forbidden'; end if;
  -- An officer may clear out members; only the owner outranks an officer, and
  -- nobody outranks the owner.
  if target = 'owner' or (me = 'officer' and target = 'officer') then
    raise exception 'TEAM_ERR:cannot_kick';
  end if;

  delete from public.team_members where team_id = tid and user_id = p_user;
  return 'kicked';
end;
$$;

-- ═══════════════════════════════════════════════════════════
-- EN-25 · the weekly team challenge
-- ═══════════════════════════════════════════════════════════

-- Counts XP the caller has earned this week toward their team's goal, and
-- returns how much was actually counted.
--
-- [p_amount] is an upper bound, never a source of truth. The real figure is
-- read back out of `xp_log`, so however this is called the team can never be
-- credited with XP nobody earned — the difference between a rule and a
-- suggestion. Passing 0 means "count everything I have outstanding", which is
-- what makes this safe to fire after any round without threading an amount
-- through the app.
--
-- On top of that sits the EN-25 cap: at most 40% of the goal from any one
-- member. A player who has already given their share adds nothing further, and
-- the UI shows them sitting at their ceiling rather than silently dropping it.
create or replace function public.contribute_team_xp(p_amount integer default 0)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid     uuid := auth.uid();
  tid     bigint := public._team_of(uid);
  w       public.team_weekly;
  r       jsonb := public.team_rules();
  ws      date;
  cap     integer;
  earned  integer;
  already integer;
  add     integer;
begin
  if uid is null or tid is null then return 0; end if;

  w := public._ensure_team_week(tid);
  ws := w.week_start;
  cap := greatest(1, floor(w.goal * (r->>'cap_share')::numeric)::int);

  select coalesce(sum(amount), 0)::int into earned
    from public.xp_log
   where user_id = uid and created_at >= ws::timestamptz;

  select coalesce(xp, 0) into already
    from public.team_weekly_contrib
   where team_id = tid and week_start = ws and user_id = uid;
  already := coalesce(already, 0);

  add := least(cap, earned) - already;
  if p_amount is not null and p_amount > 0 then add := least(add, p_amount); end if;
  if add <= 0 then return 0; end if;

  insert into public.team_weekly_contrib as c (team_id, week_start, user_id, xp)
  values (tid, ws, uid, add)
  on conflict (team_id, week_start, user_id) do update set xp = c.xp + excluded.xp;

  update public.team_weekly set progress = progress + add
   where team_id = tid and week_start = ws;
  update public.team_members set contributed_xp = contributed_xp + add
   where team_id = tid and user_id = uid;
  update public.teams
     set xp = xp + add,
         level = 1 + ((xp + add) / 5000)
   where id = tid;

  return add;
end;
$$;

-- Everything the weekly screen draws, including the rule numbers themselves so
-- the cap can be shown on the bar instead of described in a paragraph.
create or replace function public.team_weekly_state()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid   uuid := auth.uid();
  tid   bigint := public._team_of(uid);
  w     public.team_weekly;
  r     jsonb := public.team_rules();
  cap   integer;
  contributors integer;
  reward integer;
  members jsonb;
begin
  if uid is null or tid is null then return null; end if;

  -- Sync first: a player who earned XP elsewhere in the app should not have to
  -- play again before the bar they are looking at catches up.
  perform public.contribute_team_xp(0);
  w := public._ensure_team_week(tid);
  cap := greatest(1, floor(w.goal * (r->>'cap_share')::numeric)::int);

  select count(*) into contributors
    from public.team_weekly_contrib
   where team_id = tid and week_start = w.week_start and xp > 0;

  reward := greatest(150, (w.goal / 10));

  select coalesce(jsonb_agg(row order by xp desc), '[]'::jsonb) into members
  from (
    select jsonb_build_object(
             'user_id',      p.id,
             'name',         coalesce(nullif(btrim(p.display_name), ''), p.username, ''),
             'avatar_emoji', p.avatar_emoji,
             'role',         m.role,
             'xp',           coalesce(c.xp, 0),
             'capped',       coalesce(c.xp, 0) >= cap
           ) as row,
           coalesce(c.xp, 0) as xp
    from public.team_members m
    join public.profiles p on p.id = m.user_id
    left join public.team_weekly_contrib c
           on c.team_id = m.team_id and c.user_id = m.user_id and c.week_start = w.week_start
    where m.team_id = tid
    limit 60
  ) s;

  return jsonb_build_object(
    'rules',            r,
    'team_id',          tid,
    'week_start',       w.week_start,
    'goal',             w.goal,
    'progress',         w.progress,
    'claimed',          w.claimed,
    'cap_per_member',   cap,
    'contributors',     contributors,
    'min_contributors', (r->>'min_contributors')::int,
    'my_xp',            (select coalesce(xp, 0) from public.team_weekly_contrib
                          where team_id = tid and week_start = w.week_start and user_id = uid),
    'reward_xp',        reward,
    'can_claim',        (not w.claimed
                         and w.progress >= w.goal
                         and contributors >= (r->>'min_contributors')::int),
    'members',          members
  );
end;
$$;

-- Pays the whole roster once the goal is met by enough people.
--
-- Any member may press it, because the reward belongs to the team rather than
-- to whoever happened to be looking. The two conditions are checked here and
-- not only in the UI: the second one — three distinct contributors — is the
-- entire point of EN-25 and would be trivially skippable otherwise.
create or replace function public.claim_team_weekly()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid    uuid := auth.uid();
  tid    bigint := public._team_of(uid);
  w      public.team_weekly;
  r      jsonb := public.team_rules();
  contributors integer;
  reward integer;
  paid   integer := 0;
  m      record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if tid is null then raise exception 'TEAM_ERR:no_team'; end if;

  perform public.contribute_team_xp(0);

  select * into w from public.team_weekly
   where team_id = tid and week_start = public.week_start(current_date) for update;
  if w.team_id is null then raise exception 'TEAM_ERR:not_ready'; end if;
  if w.claimed then raise exception 'TEAM_ERR:already_claimed'; end if;
  if w.progress < w.goal then raise exception 'TEAM_ERR:not_ready'; end if;

  select count(*) into contributors
    from public.team_weekly_contrib
   where team_id = tid and week_start = w.week_start and xp > 0;
  if contributors < (r->>'min_contributors')::int then
    raise exception 'TEAM_ERR:need_contributors';
  end if;

  update public.team_weekly set claimed = true
   where team_id = tid and week_start = w.week_start;

  reward := greatest(150, (w.goal / 10));
  for m in select user_id from public.team_members where team_id = tid loop
    perform public._team_award(m.user_id, reward, 'team_weekly');
    paid := paid + 1;
  end loop;

  return jsonb_build_object('reward_xp', reward, 'members', paid);
end;
$$;

-- ═══════════════════════════════════════════════════════════
-- EN-26 / KK-4 · the one-day boss war
-- ═══════════════════════════════════════════════════════════

create or replace function public.war_state()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid    uuid := auth.uid();
  tid    bigint := public._team_of(uid);
  today  date := (now() at time zone 'utc')::date;
  r      jsonb := public.team_rules();
  w      public.team_wars;
  stale  bigint;
  side   text;
  mine   bigint;
  opp    bigint;
  my_score integer; opp_score integer;
  my_players integer; opp_players integer;
  floor_n integer := (r->>'war_min_players')::int;
  my_matches integer;
  top    jsonb;
begin
  if uid is null or tid is null then return null; end if;

  -- There is no scheduler on this project, so the midnight deadline has to be
  -- enforced by whoever looks next. Without this a war stays "running" for
  -- ever and neither side is ever told who won.
  for stale in
    select id from public.team_wars
     where status <> 'finished' and day < today and (team_a = tid or team_b = tid)
  loop
    perform public._settle_war(stale, true);
  end loop;

  select * into w from public.team_wars
   where (team_a = tid or team_b = tid) and day >= today - 1
   order by day desc, created_at desc
   limit 1;
  if w.id is null then
    return jsonb_build_object(
      'rules', r, 'war', null, 'team', public.team_info(tid),
      'can_start', true);
  end if;

  if w.team_a = tid then
    side := 'a'; mine := w.team_a; opp := w.team_b;
    my_score := w.a_score; opp_score := w.b_score;
  else
    side := 'b'; mine := w.team_b; opp := w.team_a;
    my_score := w.b_score; opp_score := w.a_score;
  end if;

  select count(distinct user_id) into my_players
    from public.team_war_matches where war_id = w.id and team_id = mine;
  select count(distinct user_id) into opp_players
    from public.team_war_matches where war_id = w.id and team_id is not distinct from opp;

  select count(*) into my_matches
    from public.team_war_matches where war_id = w.id and user_id = uid;

  select coalesce(jsonb_agg(row order by dmg desc), '[]'::jsonb) into top
  from (
    select jsonb_build_object(
             'user_id',      p.id,
             'name',         coalesce(nullif(btrim(p.display_name), ''), p.username, ''),
             'avatar_emoji', p.avatar_emoji,
             'team_id',      x.team_id,
             'mine',         x.team_id = mine,
             'damage',       x.dmg,
             'matches',      x.n
           ) as row, x.dmg
    from (
      select user_id, team_id, sum(score)::int as dmg, count(*)::int as n
      from public.team_war_matches where war_id = w.id
      group by user_id, team_id
    ) x
    join public.profiles p on p.id = x.user_id
    order by x.dmg desc
    limit 12
  ) s;

  return jsonb_build_object(
    'rules',        r,
    'can_start',    false,
    'war', jsonb_build_object(
      'id',            w.id,
      'day',           w.day,
      'is_today',      w.day = today,
      'status',        w.status,
      'boss_hp',       w.boss_hp,
      'side',          side,
      'my_team',       public.team_info(mine),
      'opp_team',      case when opp is null then null else public.team_info(opp) end,
      'my_score',      my_score,
      'opp_score',     opp_score,
      'my_players',    my_players,
      'opp_players',   coalesce(opp_players, 0),
      -- What actually counts: a side below the participation floor scores zero
      -- however much damage one hero rolled up.
      'my_effective',  case when my_players >= floor_n then my_score else 0 end,
      'opp_effective', case when coalesce(opp_players, 0) >= floor_n then opp_score else 0 end,
      'my_matches',    my_matches,
      'matches_left',  greatest(0, (r->>'war_match_limit')::int - my_matches),
      'winner',        w.winner,
      'top',           top
    ));
end;
$$;

-- Queues the caller's team for today's war, or pairs it with a team already
-- waiting. A team below the 3-player minimum cannot enter at all — it could
-- never clear the participation floor, so entering would only guarantee it a
-- loss it did nothing to earn.
create or replace function public.find_or_queue_war()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid   uuid := auth.uid();
  tid   bigint := public._team_of(uid);
  r     jsonb := public.team_rules();
  today date := (now() at time zone 'utc')::date;
  n     integer;
  w     public.team_wars;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if tid is null then raise exception 'TEAM_ERR:no_team'; end if;

  select count(*) into n from public.team_members where team_id = tid;
  if n < (r->>'min_team_for_war')::int then raise exception 'TEAM_ERR:too_small'; end if;

  select * into w from public.team_wars
   where day = today and status <> 'finished' and (team_a = tid or team_b = tid)
   limit 1;
  if w.id is not null then return public.war_state(); end if;

  -- Somebody else is already waiting: take the oldest, so a queued team is
  -- never left sitting behind a newer one.
  select * into w from public.team_wars
   where day = today and status = 'open' and team_b is null and team_a <> tid
   order by created_at asc
   limit 1
   for update skip locked;

  if w.id is not null then
    update public.team_wars
       set team_b = tid, status = 'running'
     where id = w.id;
  else
    insert into public.team_wars (team_a, day, status, boss_hp)
    values (tid, today, 'open', (r->>'war_boss_hp')::int);
  end if;

  return public.war_state();
end;
$$;

-- Records one round as damage.
--
-- Three guards, all of them EN-26 rather than paranoia: the per-player match
-- limit, so no single player is the war; the damage clamp, so a forged score
-- cannot fell the boss in one call; and the settlement check, so the first
-- team past the boss's health ends the day there and then.
create or replace function public.submit_war_match(p_war bigint, p_score integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid   uuid := auth.uid();
  tid   bigint := public._team_of(uid);
  r     jsonb := public.team_rules();
  today date := (now() at time zone 'utc')::date;
  w     public.team_wars;
  n     integer;
  dmg   integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if tid is null then raise exception 'TEAM_ERR:no_team'; end if;

  select * into w from public.team_wars where id = p_war for update;
  if w.id is null then raise exception 'TEAM_ERR:no_war'; end if;
  if w.team_a <> tid and coalesce(w.team_b, -1) <> tid then raise exception 'TEAM_ERR:forbidden'; end if;
  if w.status <> 'running' or w.day <> today then raise exception 'TEAM_ERR:war_over'; end if;

  select count(*) into n from public.team_war_matches where war_id = w.id and user_id = uid;
  if n >= (r->>'war_match_limit')::int then raise exception 'TEAM_ERR:match_limit'; end if;

  dmg := least(greatest(coalesce(p_score, 0), 0), (r->>'war_match_max_damage')::int);

  insert into public.team_war_matches (war_id, user_id, team_id, score)
  values (w.id, uid, tid, dmg);

  if w.team_a = tid then
    update public.team_wars set a_score = a_score + dmg where id = w.id;
  else
    update public.team_wars set b_score = b_score + dmg where id = w.id;
  end if;

  perform public._settle_war(w.id, false);
  return public.war_state();
end;
$$;

-- ═══════════════════════════════════════════════════════════
-- The team board
-- ═══════════════════════════════════════════════════════════

-- Ranked on this week's shared progress rather than lifetime XP, so a team
-- founded on Monday can still top it — the same reason the league resets.
create or replace function public.team_board(p_limit integer default 30)
returns table (
  id           bigint,
  name         text,
  tag          text,
  emblem       text,
  colour       text,
  member_count integer,
  week_xp      integer,
  xp           integer,
  level        integer,
  rank         integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select t.id, t.name, t.tag, t.emblem, t.colour,
         (select count(*) from public.team_members m where m.team_id = t.id)::int,
         coalesce(w.progress, 0)::int,
         t.xp, t.level,
         rank() over (order by coalesce(w.progress, 0) desc, t.xp desc)::int
  from public.teams t
  left join public.team_weekly w
         on w.team_id = t.id and w.week_start = public.week_start(current_date)
  order by coalesce(w.progress, 0) desc, t.xp desc
  limit greatest(1, least(coalesce(p_limit, 30), 100));
$$;

-- ═══════════════════════════════════════════════════════════
-- Grants
-- ═══════════════════════════════════════════════════════════

grant execute on function public.team_rules()                            to authenticated;
grant execute on function public.team_info(bigint)                       to authenticated;
grant execute on function public.create_team(text, text, text, text)     to authenticated;
grant execute on function public.my_team()                               to authenticated;
grant execute on function public.team_roster(bigint)                     to authenticated;
grant execute on function public.search_teams(text, integer)             to authenticated;
grant execute on function public.join_team(bigint)                       to authenticated;
grant execute on function public.invite_to_team(uuid)                    to authenticated;
grant execute on function public.my_team_invites()                       to authenticated;
grant execute on function public.respond_team_invite(bigint, boolean)    to authenticated;
grant execute on function public.leave_team()                            to authenticated;
grant execute on function public.kick_member(uuid)                       to authenticated;
grant execute on function public.contribute_team_xp(integer)             to authenticated;
grant execute on function public.team_weekly_state()                     to authenticated;
grant execute on function public.claim_team_weekly()                     to authenticated;
grant execute on function public.war_state()                             to authenticated;
grant execute on function public.find_or_queue_war()                     to authenticated;
grant execute on function public.submit_war_match(bigint, integer)       to authenticated;
grant execute on function public.team_board(integer)                     to authenticated;

-- PostgREST caches the function signatures it will expose; without this the
-- app keeps getting "Could not find the function" until the next reload.
notify pgrst, 'reload schema';
