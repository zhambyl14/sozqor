-- supabase/sql/v5_friend_battle_consent_guard.sql
--
-- v5.0 — a targeted friend battle can only ever be an INVITATION.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run. Run it AFTER v5_match_consent.sql.
--
-- `create_friend_battle(p_target)` made the row 'active', and both clients
-- then treated it as a game already under way: the sender played it, finished
-- it, and the friend's screen said a battle was waiting for them that had in
-- fact already ended. The handshake was built and two screens still called
-- this path afterwards, so the old behaviour survived exactly where nobody
-- was looking.
--
-- Rather than trust every call site, the server refuses. With a target it
-- delegates to `invite_friend_battle`, which rings for fifteen seconds and
-- plays for nobody until it is accepted. Without a target it is the
-- share-a-code flow, which is unchanged and still legitimate — typing
-- somebody's code IS consent, and `join_battle_by_code` is the moment both
-- sides start together.

create or replace function public.create_friend_battle(
  p_questions jsonb default '[]'::jsonb,
  p_cefr      text default 'A1',
  p_target    uuid default null)
returns public.battles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid  uuid := auth.uid();
  b    public.battles;
  code text;
  tries integer := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_guest() then
    raise exception 'GUEST_LOCKED: Дос баттлы үшін тіркелу керек';
  end if;

  -- Aimed at somebody: that is an invitation, whatever the caller thought.
  if p_target is not null then
    return public.invite_friend_battle(
      p_target, p_questions, p_cefr,
      coalesce((select ui_lang from public.profiles where id = uid), 'kk'));
  end if;

  loop
    tries := tries + 1;
    code := public._room_code();
    exit when not exists (
      select 1 from public.battles x
       where x.invite_code = code and x.status in ('waiting', 'invited'));
    if tries > 12 then raise exception 'could not allocate a code'; end if;
  end loop;

  insert into public.battles
    (mode, status, p1, questions, cefr, invite_code, p1_lang)
  values
    ('friend', 'waiting', uid, coalesce(p_questions, '[]'::jsonb),
     coalesce(p_cefr, 'A1'), code,
     coalesce((select ui_lang from public.profiles where id = uid), 'kk'))
  returning * into b;

  return b;
end;
$$;

-- The other half of the code flow: whoever types the code becomes p2 and the
-- battle starts for both at the same moment.
create or replace function public.join_battle_by_code(p_code text)
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

  select * into b from public.battles
   where invite_code = upper(btrim(coalesce(p_code, '')))
     and status = 'waiting'
     and expires_at > now()
   limit 1
   for update;
  if b.id is null then raise exception 'INVITE_ERR:gone'; end if;
  if b.p1 = uid then raise exception 'INVITE_ERR:self'; end if;

  update public.battles
     set p2 = uid,
         status = 'active',
         started_at = now(),
         accepted_at = now(),
         p1_seen_at = now(),
         p2_seen_at = now(),
         p2_lang = coalesce((select ui_lang from public.profiles where id = uid), 'kk')
   where id = b.id
  returning * into b;

  return b;
end;
$$;

grant execute on function public.create_friend_battle(jsonb, text, uuid) to authenticated;
grant execute on function public.join_battle_by_code(text) to authenticated;

notify pgrst, 'reload schema';
