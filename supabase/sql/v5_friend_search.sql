-- supabase/sql/v5_friend_search.sql
--
-- v5.0 — you find a friend by their handle, not by browsing everybody.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run. Run it AFTER v5_friend_requests.sql, which is where the
-- version this replaces comes from.
--
-- The directory of "people you could add" was removed from the screen, but
-- not from the server: `search_users` matched `username ilike '%q%' or
-- display_name ilike '%q%'` on two characters and ordered the result by XP.
-- Type "an" and you get twenty strangers, ranked by how much they have
-- played. That is a directory with extra steps, and it is exactly what the
-- report asked to stop: "әр қолданушының аидиә болады, сол сандар бойынша
-- достар бір бірін табады".
--
-- So: the whole handle, or the account id, or nothing. `board_row` is kept as
-- the return type because the friends screen already draws it, but the XP
-- column it carries is no longer used to rank anything.

create or replace function public.search_users(p_query text, p_limit integer default 20)
returns setof public.board_row
language sql
stable
security definer
set search_path to 'public', 'extensions'
as $$
  with q as (select btrim(coalesce(p_query, '')) as raw)
  select p.id, p.username, p.display_name, p.avatar_emoji, p.cefr_level, p.xp, 0
  from public.profiles p, q
  where p.id <> auth.uid()
    and not p.is_guest
    and length(q.raw) >= 3
    and (
      -- the handle, whole, however they typed the @ and the case
      lower(p.username) = lower(ltrim(q.raw, '@'))
      -- or the account id, pasted from a share link
      or (q.raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          and p.id = q.raw::uuid)
    )
  limit greatest(1, least(coalesce(p_limit, 20), 5));
$$;

grant execute on function public.search_users(text, integer) to authenticated;

notify pgrst, 'reload schema';
