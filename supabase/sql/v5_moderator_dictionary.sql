-- supabase/sql/v5_moderator_dictionary.sql
--
-- v5.0 — EN-33 / EN-38 / EN-50 / KK-7: moderators can edit the dictionary.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Run it AFTER v5_translation_review.sql, which creates the report table this
-- file's queue reads from.
--
-- Today `lib/data/repos/dictionary_repo.dart` is read-only — dict_lookup,
-- dict_search, dict_distractors — and `moderator_repo.dart` manages events,
-- tournaments and shop items but never touches the dictionary at all. So the
-- only writer is dict_upsert, called by the AI edge function, and there is no
-- way for any human to correct a wrong translation, add a word at a level, or
-- remove a bad entry. Every mistake the AI makes is permanent.
--
-- That is also why EN-49's gate needed a review queue: refusing a bad
-- translation is only half an answer if nobody can then supply a good one.

-- ── Browsing ───────────────────────────────────────────────
-- Paged, filterable, and with the two filters that matter for cleaning up:
-- `verified` (has a human checked it) and `source` (did a model write it).
create or replace function public.dict_admin_list(
  p_query    text default '',
  p_cefr     text default null,
  p_topic    text default null,
  p_verified boolean default null,
  p_source   text default null,
  p_limit    integer default 20,
  p_offset   integer default 0)
returns setof public.dictionary
language sql
stable
security definer
set search_path to 'public', 'extensions'
as $$
  select d.*
  from public.dictionary d
  where public.is_moderator(auth.uid())
    and (coalesce(btrim(p_query), '') = ''
         or d.en ilike '%' || btrim(p_query) || '%'
         or d.kk ilike '%' || btrim(p_query) || '%'
         or coalesce(d.ru, '') ilike '%' || btrim(p_query) || '%')
    and (p_cefr     is null or d.cefr = p_cefr)
    and (p_topic    is null or d.topic = p_topic)
    and (p_verified is null or d.verified = p_verified)
    and (p_source   is null or d.source = p_source)
  -- Unverified first: the point of the screen is finding what needs checking,
  -- and sorting by id would bury it under everything already fine.
  order by d.verified asc, d.hits desc, d.id desc
  limit greatest(1, least(coalesce(p_limit, 20), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- An honest total for the header. The old totalWords() selected 1000 ids and
-- returned their length, which both moved a thousand rows to produce a number
-- and silently capped at 1000 — the one number whose whole point is that it
-- keeps growing.
create or replace function public.dict_count(
  p_query    text default '',
  p_cefr     text default null,
  p_topic    text default null,
  p_verified boolean default null,
  p_source   text default null)
returns integer
language sql
stable
security definer
set search_path to 'public', 'extensions'
as $$
  select count(*)::int
  from public.dictionary d
  where public.is_moderator(auth.uid())
    and (coalesce(btrim(p_query), '') = ''
         or d.en ilike '%' || btrim(p_query) || '%'
         or d.kk ilike '%' || btrim(p_query) || '%'
         or coalesce(d.ru, '') ilike '%' || btrim(p_query) || '%')
    and (p_cefr     is null or d.cefr = p_cefr)
    and (p_topic    is null or d.topic = p_topic)
    and (p_verified is null or d.verified = p_verified)
    and (p_source   is null or d.source = p_source);
$$;

-- ── Editing ────────────────────────────────────────────────
create or replace function public.dict_admin_upsert(
  p_id            bigint,
  p_en            text,
  p_kk            text,
  p_ru            text default null,
  p_pos           text default null,
  p_definition_en text default null,
  p_example_en    text default null,
  p_ipa           text default null,
  p_emoji         text default null,
  p_cefr          text default 'A2',
  p_topic         text default 'general',
  p_synonyms      text[] default '{}',
  p_antonyms      text[] default '{}',
  p_verified      boolean default true)
returns public.dictionary
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  row public.dictionary;
begin
  if not public.is_moderator(uid) then raise exception 'not a moderator'; end if;
  if btrim(coalesce(p_en, '')) = '' or btrim(coalesce(p_kk, '')) = '' then
    raise exception 'GUEST_LOCKED: Ағылшын және қазақша нұсқасы міндетті';
  end if;

  if p_id is null then
    insert into public.dictionary
      (en_key, kk_key, ru_key, en, kk, ru, pos, definition_en, example_en,
       ipa, emoji, cefr, topic, synonyms, antonyms, source, verified)
    values (public.norm_term(p_en), public.norm_term(p_kk),
            case when btrim(coalesce(p_ru, '')) = '' then null
                 else public.norm_term(p_ru) end,
            btrim(p_en), btrim(p_kk), nullif(btrim(coalesce(p_ru, '')), ''),
            p_pos, p_definition_en, p_example_en, p_ipa, p_emoji,
            coalesce(p_cefr, 'A2'), coalesce(p_topic, 'general'),
            coalesce(p_synonyms, '{}'), coalesce(p_antonyms, '{}'),
            'user', coalesce(p_verified, true))
    on conflict (en_key) do update
      set kk = excluded.kk, ru = excluded.ru, kk_key = excluded.kk_key,
          ru_key = excluded.ru_key, pos = excluded.pos,
          definition_en = excluded.definition_en,
          example_en = excluded.example_en, ipa = excluded.ipa,
          emoji = excluded.emoji, cefr = excluded.cefr, topic = excluded.topic,
          synonyms = excluded.synonyms, antonyms = excluded.antonyms,
          verified = excluded.verified
    returning * into row;
  else
    update public.dictionary
       set en = btrim(p_en), kk = btrim(p_kk),
           ru = nullif(btrim(coalesce(p_ru, '')), ''),
           en_key = public.norm_term(p_en),
           kk_key = public.norm_term(p_kk),
           ru_key = case when btrim(coalesce(p_ru, '')) = '' then null
                         else public.norm_term(p_ru) end,
           pos = p_pos, definition_en = p_definition_en,
           example_en = p_example_en, ipa = p_ipa, emoji = p_emoji,
           cefr = coalesce(p_cefr, cefr), topic = coalesce(p_topic, topic),
           synonyms = coalesce(p_synonyms, synonyms),
           antonyms = coalesce(p_antonyms, antonyms),
           -- A moderator touched it, so it outranks whatever the model wrote.
           verified = coalesce(p_verified, true)
     where dictionary.id = p_id
    returning * into row;
  end if;

  return row;
end;
$$;

-- Deleting has to detach the learners' words first, or the foreign key
-- refuses and the moderator just sees an error they cannot act on. The words
-- themselves survive — somebody has been studying them, and a bad shared entry
-- is not a reason to empty their bank.
create or replace function public.dict_admin_delete(p_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  update public.words set dictionary_id = null where dictionary_id = p_id;
  delete from public.word_pack_entries where dictionary_id = p_id;
  delete from public.dictionary where id = p_id;
end;
$$;

-- Bulk level assignment. EN-38 asks for moderators to "assign levels", and
-- doing it one row at a time over a few hundred words is not a tool.
create or replace function public.dict_admin_set_cefr(
  p_ids bigint[], p_cefr text)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  n integer;
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  if p_cefr not in ('A0','A1','A2','B1','B2','C1') then
    raise exception 'bad cefr';
  end if;
  update public.dictionary
     set cefr = p_cefr
   where id = any(coalesce(p_ids, '{}'::bigint[]));
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.dict_admin_set_verified(
  p_ids bigint[], p_verified boolean)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  n integer;
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  update public.dictionary
     set verified = coalesce(p_verified, true)
   where id = any(coalesce(p_ids, '{}'::bigint[]));
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ── The audit trail EN-50 asks for ─────────────────────────
-- There is no record anywhere of who changed what, and `created_by` on events
-- and cosmetics is set by the CLIENT, so it is not one either.
create table if not exists public.moderator_audit (
  id         bigserial primary key,
  actor      uuid references public.profiles(id) on delete set null,
  action     text not null,
  table_name text not null,
  row_id     text,
  before     jsonb,
  after      jsonb,
  at         timestamptz not null default now()
);

create index if not exists moderator_audit_recent
  on public.moderator_audit (at desc);

alter table public.moderator_audit enable row level security;

drop policy if exists moderator_audit_read on public.moderator_audit;
create policy moderator_audit_read on public.moderator_audit
  for select using (public.is_moderator(auth.uid()));

create or replace function public.dict_audit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  insert into public.moderator_audit
    (actor, action, table_name, row_id, before, after)
  values (
    auth.uid(),
    lower(tg_op),
    'dictionary',
    coalesce(new.id, old.id)::text,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

drop trigger if exists dictionary_audit on public.dictionary;
create trigger dictionary_audit
  after insert or update or delete on public.dictionary
  for each row execute function public.dict_audit();

grant execute on function public.dict_admin_list(
  text, text, text, boolean, text, integer, integer) to authenticated;
grant execute on function public.dict_count(text, text, text, boolean, text)
  to authenticated;
grant execute on function public.dict_admin_upsert(
  bigint, text, text, text, text, text, text, text, text, text, text,
  text[], text[], boolean) to authenticated;
grant execute on function public.dict_admin_delete(bigint)              to authenticated;
grant execute on function public.dict_admin_set_cefr(bigint[], text)    to authenticated;
grant execute on function public.dict_admin_set_verified(bigint[], boolean)
  to authenticated;

notify pgrst, 'reload schema';
