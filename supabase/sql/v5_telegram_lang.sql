-- supabase/sql/v5_telegram_lang.sql
--
-- v5.0 — EN-4 / KK-9: the Telegram bot answers in the app's language.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- The bot is a separate process with no session and no profile to read: all it
-- ever sees is a /start payload carrying a verification code. So the language
-- has to travel on the row that code names, or the bot has nothing to go on
-- and every learner gets Kazakh — which is what happens today, including for
-- somebody who set the app to Russian before they ever reached the bot.

alter table public.phone_verifications
  add column if not exists lang text not null default 'kk'
    check (lang in ('kk', 'ru'));

-- A contact can arrive minutes after /start, and with no code attached to it —
-- the button stays on screen and a learner may tap it whenever they get round
-- to it. tg-webhook finds the row by chat id in that case, so that lookup
-- needs to be cheap and needs to find the newest pending one.
create index if not exists phone_verifications_by_chat
  on public.phone_verifications (telegram_id, status, created_at desc);

-- Expired rows are worthless and they hold phone numbers, so they should not
-- accumulate. purge_phone_verifications() already exists; this is the index
-- that keeps it from scanning the table.
create index if not exists phone_verifications_expiry
  on public.phone_verifications (expires_at)
  where status = 'pending';

notify pgrst, 'reload schema';
