-- supabase/sql/profiles_guard.sql
--
-- Column-level protection for `public.profiles`.
--
-- A profile row is writable by the person it belongs to, expressed as
-- `profiles_update_own`: USING (auth.uid() = id) WITH CHECK (auth.uid() = id).
-- Postgres row level security is row level only, so that policy decides
-- *which row* may be written and says nothing about *which columns* — and
-- there was no trigger making up the difference. Any signed-in player could
-- therefore PATCH their own row with role = 'moderator' and walk into the
-- console (which writes events, tournaments and the shop for everybody), or
-- with xp = 999999 and take the top of the league. Neither needed anything
-- more than the publishable key that ships inside the app.
--
-- The line between "the learner changed a setting" and "the game awarded
-- something" is the role the statement runs under. PostgREST writes run as
-- `authenticated`; every function that legitimately moves XP, a rank or an
-- equipped item — add_xp, record_quiz, submit_battle_result, submit_daily_result,
-- buy_cosmetic, equip_cosmetic, touch_streak, claim_guest_account and the
-- rest — is SECURITY DEFINER and owned by `postgres`, so it runs as
-- `postgres` instead. Adding a new one of those needs no change here; adding
-- a new *client-editable* settings column does, or it will be silently
-- reverted.
--
-- Applied 2026-08-22 as migration `profiles_guard_privileged_columns`.

-- SECURITY INVOKER on purpose: as DEFINER, current_user would always be the
-- owner and this would never fire.
create or replace function public.profiles_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Everything the client is allowed to set stays as written: username,
  -- display_name, avatar_emoji, cefr_level, ui_lang, native_lang, dark_mode,
  -- notif_enabled, daily_goal, onboarded. Every other column is put back.
  new.role            := old.role;
  new.xp              := old.xp;
  new.xp_spent        := old.xp_spent;
  new.coins           := old.coins;
  new.elo             := old.elo;
  new.battles_played  := old.battles_played;
  new.battles_won     := old.battles_won;
  new.words_total     := old.words_total;
  new.words_learned   := old.words_learned;
  new.quizzes_done    := old.quizzes_done;
  new.streak          := old.streak;
  new.best_streak     := old.best_streak;
  new.last_active     := old.last_active;
  new.is_guest        := old.is_guest;
  new.phone           := old.phone;
  new.telegram_id     := old.telegram_id;
  new.created_at      := old.created_at;
  new.equipped_frame  := old.equipped_frame;
  new.equipped_title  := old.equipped_title;
  new.equipped_avatar := old.equipped_avatar;
  new.equipped_banner := old.equipped_banner;
  new.equipped_badge  := old.equipped_badge;
  new.equipped_aura   := old.equipped_aura;
  -- The friend code is an identifier, so it is assigned once by
  -- my_friend_code() (SECURITY DEFINER, which this guard does not fire for)
  -- and never writable by the account it belongs to. Without this line a
  -- learner could PATCH their own row and take somebody else's code.
  new.friend_code     := old.friend_code;

  return new;
end;
$$;

drop trigger if exists profiles_guard on public.profiles;

-- Fires before profiles_touch, which is alphabetically later and only stamps
-- updated_at.
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.profiles_guard();
