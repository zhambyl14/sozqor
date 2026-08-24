-- supabase/sql/v5_friend_requests.sql
--
-- v5.0 — EN-15 / EN-16 / KK-2: friendship becomes request → accept.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- Today BoardRepo.addFriend writes {requester, addressee, status:'accepted'}
-- straight into `friendships` under the friendships_insert policy, so anyone
-- can make themselves anybody's friend with no consent — and that roster is
-- what feeds the invite surface and the team standing. The status column
-- already defaults to 'pending' and already permits it; nothing ever used it.
--
-- search_users is the other half: called with an empty query it builds
-- '%' || '' || '%', which matches every registered profile, so the "add a
-- friend" screen is really a directory of the whole user base. EN-15 forbids
-- exactly that.

-- ── Finding people ─────────────────────────────────────────
-- Two characters minimum, and the handle is what you search. A display name
-- is still matched so somebody who typed their real name can be found, but
-- never the whole table.
create or replace function public.search_users(p_query text, p_limit integer default 20)
returns setof public.board_row
language sql
stable
security definer
set search_path to 'public', 'extensions'
as $$
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level, p.xp, 0
  from public.profiles p
  where p.id <> auth.uid()
    and not p.is_guest
    and length(btrim(coalesce(p_query, ''))) >= 2
    and (p.username     ilike '%' || btrim(p_query) || '%'
      or p.display_name ilike '%' || btrim(p_query) || '%')
  order by
    -- an exact handle is what the searcher almost always meant
    (lower(p.username) = lower(btrim(p_query))) desc,
    (p.username ilike btrim(p_query) || '%') desc,
    p.xp desc
  limit greatest(1, least(p_limit, 50));
$$;

-- ── Requesting ─────────────────────────────────────────────
create or replace function public.send_friend_request(p_user uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  existing public.friendships;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_user is null or p_user = uid then
    raise exception 'GUEST_LOCKED: Өзіңді дос қыла алмайсың';
  end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Дос қосу үшін тіркелу керек';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and not is_guest) then
    raise exception 'GUEST_LOCKED: Пайдаланушы табылмады';
  end if;

  select * into existing from public.friendships
   where (requester = uid and addressee = p_user)
      or (requester = p_user and addressee = uid)
   limit 1;

  if existing.id is not null then
    if existing.status = 'blocked' then return 'blocked'; end if;
    if existing.status = 'accepted' then return 'friends'; end if;
    -- They asked first: saying yes back is the same as accepting.
    if existing.requester = p_user then
      update public.friendships set status = 'accepted' where id = existing.id;
      return 'friends';
    end if;
    return 'pending';
  end if;

  insert into public.friendships (requester, addressee, status)
  values (uid, p_user, 'pending');
  return 'pending';
end;
$$;

create or replace function public.respond_friend_request(p_id bigint, p_accept boolean)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  f public.friendships;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into f from public.friendships where id = p_id for update;
  if f.id is null then return 'gone'; end if;
  -- Only the person who was asked may answer.
  if f.addressee <> uid then raise exception 'not addressed to you'; end if;
  if f.status <> 'pending' then return f.status; end if;

  if p_accept then
    update public.friendships set status = 'accepted' where id = p_id;
    return 'accepted';
  end if;

  delete from public.friendships where id = p_id;
  return 'declined';
end;
$$;

-- Incoming requests still waiting on an answer. `value` carries the row id so
-- the client can answer without a second lookup, and `rank` is 0 to keep the
-- board_row shape the rest of the app already parses.
create or replace function public.my_friend_requests()
returns setof public.board_row
language sql
stable
security definer
set search_path to 'public'
as $$
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level,
         f.id::int, 0
  from public.friendships f
  join public.profiles p on p.id = f.requester
  where f.addressee = auth.uid() and f.status = 'pending'
  order by f.created_at desc;
$$;

-- Requests this user has sent that are still unanswered, so the button can
-- read "sent" instead of offering to send again.
create or replace function public.my_sent_requests()
returns setof public.board_row
language sql
stable
security definer
set search_path to 'public'
as $$
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level,
         f.id::int, 0
  from public.friendships f
  join public.profiles p on p.id = f.addressee
  where f.requester = auth.uid() and f.status = 'pending'
  order by f.created_at desc;
$$;

-- ── Locking the table down ─────────────────────────────────
-- With the RPCs in place the client has no reason to write friendships
-- directly, and leaving it able to is what made consent optional.
drop policy if exists friendships_insert on public.friendships;
drop policy if exists friendships_update on public.friendships;

grant execute on function public.send_friend_request(uuid)            to authenticated;
grant execute on function public.respond_friend_request(bigint, boolean) to authenticated;
grant execute on function public.my_friend_requests()                 to authenticated;
grant execute on function public.my_sent_requests()                   to authenticated;
