-- supabase/sql/v5_delete_account.sql
--
-- v5.0 — EN-45 / KK-10: "Delete account" in Settings → Account data.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- Removing the auth user needs the service role, which the client does not
-- have and must not have. A SECURITY DEFINER function owned by postgres does,
-- so the whole deletion runs server-side against the caller's own id — there
-- is no parameter naming a user, and therefore no way to aim it at somebody
-- else.
--
-- Rows that reference auth.users without ON DELETE CASCADE are cleared first,
-- so the final delete cannot fail on a foreign key and leave an account
-- half-erased.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- Content the learner owns outright.
  delete from public.review_log        where user_id = uid;
  delete from public.words             where user_id = uid;
  delete from public.xp_log            where user_id = uid;
  delete from public.daily_progress    where user_id = uid;
  delete from public.daily_results     where user_id = uid;
  delete from public.game_scores       where user_id = uid;
  delete from public.user_achievements where user_id = uid;
  delete from public.user_cosmetics    where user_id = uid;
  delete from public.event_progress    where user_id = uid;
  delete from public.device_tokens     where user_id = uid;
  delete from public.league_members    where user_id = uid;
  delete from public.tournament_entries where user_id = uid;
  delete from public.mm_queue          where user_id = uid;
  delete from public.friendships       where requester = uid or addressee = uid;

  -- Battles are shared with an opponent, so they are detached rather than
  -- destroyed: deleting them would rewrite somebody else's match history and
  -- their rating would no longer add up. An unfinished one is cancelled so
  -- the opponent is not left waiting on a player who no longer exists.
  update public.battles set status = 'cancelled'
   where status in ('waiting', 'active') and (p1 = uid or p2 = uid);

  -- Content authored as a moderator outlives the account.
  update public.events    set created_by = null where created_by = uid;
  update public.cosmetics set created_by = null where created_by = uid;

  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke execute on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;
