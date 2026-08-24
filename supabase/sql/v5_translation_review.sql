-- supabase/sql/v5_translation_review.sql
--
-- v5.0 — EN-49 / EN-50 / KK-8: the review queue behind the translation gate.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- The gate itself lives in supabase/functions/sozqor-ai/index.ts. When it
-- refuses a candidate the learner is told "Аударма табылмады" and nothing is
-- written to the shared dictionary — which is the right outcome, but it is
-- also a silent one. A word that keeps failing is a word the app cannot teach,
-- and nobody would ever know. This table is where those refusals land so a
-- moderator can see them and fix the entry by hand.
--
-- The checks, and what each one caught:
--   script    the answer was in the wrong alphabet entirely
--   identity  the answer was the question
--   translit  the answer was the source word respelled in Latin — the named
--             bug, "шамшырақ" -> "shamshyraq"
--   length    a one-word term came back as a sentence, or an empty string
--   disagree  two independent models gave different answers, so neither is
--             trustworthy enough to become everybody's answer
--
-- There is no `confidence` check on purpose. Probed on "шамшырақ", one model
-- answered "beacon" and another "sunflower", and BOTH reported 0.95. A model
-- cannot tell you when it is wrong, so the gate is structural and comparative
-- instead.

create table if not exists public.translation_reports (
  id           bigserial primary key,
  term         text not null,
  source_lang  text,
  target_lang  text,
  candidate    text,
  failed_check text check (failed_check in
                 ('script', 'identity', 'translit', 'length',
                  'confidence', 'disagree')),
  provider     text,
  created_at   timestamptz not null default now(),
  status       text not null default 'open'
                 check (status in ('open', 'fixed', 'rejected')),
  reviewed_by  uuid references public.profiles(id) on delete set null,
  reviewed_at  timestamptz
);

-- The queue is read newest-first and filtered by status, and the same word
-- failing repeatedly is the strongest signal in it.
create index if not exists translation_reports_open
  on public.translation_reports (status, created_at desc);
create index if not exists translation_reports_term
  on public.translation_reports (lower(term));

alter table public.translation_reports enable row level security;

-- Only moderators ever see this. It is a list of things the app got wrong,
-- which is useful to the people who can fix them and to nobody else.
drop policy if exists translation_reports_mod on public.translation_reports;
create policy translation_reports_mod on public.translation_reports
  for all
  using (public.is_moderator(auth.uid()))
  with check (public.is_moderator(auth.uid()));

-- The edge function writes with the service-role key, which bypasses RLS, so
-- it needs no policy of its own.

-- ── The review queue ───────────────────────────────────────
create or replace function public.translation_queue(
  p_status text default 'open',
  p_limit  integer default 40,
  p_offset integer default 0)
returns table (
  id           bigint,
  term         text,
  source_lang  text,
  target_lang  text,
  candidate    text,
  failed_check text,
  provider     text,
  created_at   timestamptz,
  status       text,
  -- How many times this word has failed. A term that has been refused nine
  -- times is a different problem from one refused once.
  fail_count   integer,
  -- What the dictionary currently holds for it, if anything, so the moderator
  -- can tell "never learned it" from "learned it wrong".
  current_en   text,
  current_kk   text,
  current_ru   text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select r.id, r.term, r.source_lang, r.target_lang, r.candidate,
         r.failed_check, r.provider, r.created_at, r.status,
         (select count(*) from public.translation_reports x
           where lower(x.term) = lower(r.term))::int,
         d.en, d.kk, d.ru
  from public.translation_reports r
  left join lateral (
    select en, kk, ru from public.dictionary
     where lower(en) = lower(r.term)
        or lower(kk) = lower(r.term)
        or lower(coalesce(ru, '')) = lower(r.term)
     limit 1
  ) d on true
  where public.is_moderator(auth.uid())
    and (p_status is null or p_status = 'all' or r.status = p_status)
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 40), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- ── Fixing one ─────────────────────────────────────────────
-- Writes the correction into the shared dictionary and closes every open
-- report for that word at once, because a word that failed nine times should
-- not need closing nine times.
create or replace function public.translation_fix(
  p_id text,
  p_en text,
  p_kk text,
  p_ru text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  r public.translation_reports;
  saved public.dictionary;
begin
  if not public.is_moderator(uid) then raise exception 'not a moderator'; end if;

  select * into r from public.translation_reports where id = p_id::bigint;
  if r.id is null then raise exception 'no such report'; end if;

  if btrim(coalesce(p_en, '')) = '' or btrim(coalesce(p_kk, '')) = '' then
    raise exception 'GUEST_LOCKED: Ағылшын және қазақша нұсқасы міндетті';
  end if;

  insert into public.dictionary (en_key, kk_key, en, kk, ru, source, verified)
  values (public.norm_term(p_en), public.norm_term(p_kk),
          btrim(p_en), btrim(p_kk), nullif(btrim(coalesce(p_ru, '')), ''),
          'user', true)
  on conflict (en_key) do update
    set kk = excluded.kk,
        ru = coalesce(excluded.ru, public.dictionary.ru),
        kk_key = excluded.kk_key,
        -- A moderator typed this, so it outranks whatever the model produced.
        verified = true
  returning * into saved;

  update public.translation_reports
     set status = 'fixed', reviewed_by = uid, reviewed_at = now()
   where lower(term) = lower(r.term) and status = 'open';

  return to_jsonb(saved);
end;
$$;

-- Closing one without a correction: the refusal was right and the word simply
-- has no entry worth making.
create or replace function public.translation_dismiss(p_id text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
begin
  if not public.is_moderator(uid) then raise exception 'not a moderator'; end if;
  update public.translation_reports
     set status = 'rejected', reviewed_by = uid, reviewed_at = now()
   where id = p_id::bigint;
end;
$$;

-- ── Closing the hole the edge function proved was open ─────
--
-- index.ts builds its Supabase client with the CALLER's Authorization header
-- and successfully calls dict_upsert. That is proof EXECUTE on dict_upsert is
-- granted to `authenticated` — so any client holding the publishable key can
-- call it directly, skip the gate entirely, and write anything it likes into
-- the dictionary every learner shares.
--
-- After this, the edge function must use the SERVICE-ROLE key for its
-- dict_upsert call (SUPABASE_SERVICE_ROLE_KEY is already available to it).
revoke execute on function public.dict_upsert(
  text, text, text, text, text, text[], text[], text, text, text, text,
  text, text, text) from authenticated, anon;

grant execute on function public.translation_queue(text, integer, integer)
  to authenticated;
grant execute on function public.translation_fix(text, text, text, text)
  to authenticated;
grant execute on function public.translation_dismiss(text) to authenticated;

notify pgrst, 'reload schema';
