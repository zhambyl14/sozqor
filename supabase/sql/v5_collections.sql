-- supabase/sql/v5_collections.sql
--
-- v5.0 — EN-32 / EN-34 / EN-38 / KK-5 / KK-7: word collections become rows.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- THE NAMED BUG. "IELTS 6.5+" says 120 words and produces about fourteen
-- questions. Both numbers are true and neither is a mistake in the counting:
-- the 120 is a literal typed into `kWordPacks` in lib/services/meta_store.dart
-- and compiled into the app, while the words themselves are whatever the
-- shared dictionary happens to hold at topic='school' and cefr in (B2, C1) —
-- which is fourteen. The pack was never a set of words. It was a filter with a
-- number written next to it, and the number was a wish.
--
-- Nothing can fix that on the client, because the client cannot know how many
-- rows the dictionary has, and no moderator can add any: expanding a pack
-- means editing a Dart constant and shipping an app-store release.
--
-- So a pack becomes what it always claimed to be — a list of specific words —
-- and the count on screen becomes `count(*)`, which cannot lie.
--
-- EN-34 falls out of the same tables: a learner's own collection is a pack
-- with an owner.

-- ── Tables ─────────────────────────────────────────────────
create table if not exists public.word_packs (
  id            bigserial primary key,
  slug          text unique,
  title_kk      text not null,
  title_ru      text not null default '',
  subtitle_kk   text not null default '',
  subtitle_ru   text not null default '',
  emoji         text not null default '📚',
  colour        text not null default '#7C5CFF',
  topic         text,
  levels        text[] not null default '{}',
  sort          integer not null default 0,
  -- An official pack is curated and visible to everyone; a personal one
  -- belongs to exactly one learner. Same table because they are the same
  -- thing, and a second table would mean two of every function below.
  is_official   boolean not null default true,
  owner         uuid references public.profiles(id) on delete cascade,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles(id) on delete set null,
  constraint word_packs_owner_check
    check ((is_official and owner is null) or (not is_official and owner is not null))
);

create table if not exists public.word_pack_entries (
  pack_id       bigint not null references public.word_packs(id) on delete cascade,
  dictionary_id bigint not null references public.dictionary(id) on delete cascade,
  sort          integer not null default 0,
  added_at      timestamptz not null default now(),
  primary key (pack_id, dictionary_id)
);

create index if not exists word_packs_mine on public.word_packs (owner)
  where owner is not null;
create index if not exists word_pack_entries_by_pack
  on public.word_pack_entries (pack_id, sort);

alter table public.word_packs        enable row level security;
alter table public.word_pack_entries enable row level security;

drop policy if exists word_packs_read on public.word_packs;
create policy word_packs_read on public.word_packs
  for select using (is_official or owner = auth.uid());

drop policy if exists word_pack_entries_read on public.word_pack_entries;
create policy word_pack_entries_read on public.word_pack_entries
  for select using (
    exists (select 1 from public.word_packs p
             where p.id = pack_id and (p.is_official or p.owner = auth.uid())));

-- Writes go through the functions below, never straight from the client:
-- otherwise anybody could add themselves to an official pack, or edit one.

-- ── Reading ────────────────────────────────────────────────
-- The catalogue, with the REAL word count and this learner's progress in one
-- round trip. The count is count(*) — the whole point of the migration.
create or replace function public.pack_catalogue()
returns table (
  id           bigint,
  slug         text,
  title_kk     text,
  title_ru     text,
  subtitle_kk  text,
  subtitle_ru  text,
  emoji        text,
  colour       text,
  topic        text,
  levels       text[],
  is_official  boolean,
  is_mine      boolean,
  word_count   integer,
  owned_count  integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select p.id, p.slug, p.title_kk, p.title_ru, p.subtitle_kk, p.subtitle_ru,
         p.emoji, p.colour, p.topic, p.levels, p.is_official,
         (p.owner = auth.uid()),
         (select count(*) from public.word_pack_entries e
           where e.pack_id = p.id)::int,
         -- How many of the pack's words the learner already has, which is the
         -- only honest way to draw a progress bar for one.
         (select count(*) from public.word_pack_entries e
           join public.words w
             on w.dictionary_id = e.dictionary_id and w.user_id = auth.uid()
          where e.pack_id = p.id)::int
  from public.word_packs p
  where p.is_active and (p.is_official or p.owner = auth.uid())
  order by p.is_official desc, p.sort, p.created_at;
$$;

-- One page of a pack. Paged because a pack is exactly the kind of list that
-- grows without limit once moderators can add to it (EN-54).
create or replace function public.pack_words(
  p_pack bigint, p_limit integer default 20, p_offset integer default 0)
returns setof public.dictionary
language sql
stable
security definer
set search_path to 'public'
as $$
  select d.*
  from public.word_pack_entries e
  join public.dictionary d on d.id = e.dictionary_id
  join public.word_packs p on p.id = e.pack_id
  where e.pack_id = p_pack
    and (p.is_official or p.owner = auth.uid())
  order by e.sort, d.id
  limit greatest(1, least(coalesce(p_limit, 20), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- ── A learner's own collections (EN-34) ────────────────────
create or replace function public.create_my_pack(
  p_title text, p_emoji text default '📚', p_colour text default '#7C5CFF')
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  n   integer;
  id  bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if btrim(coalesce(p_title, '')) = '' then
    raise exception 'GUEST_LOCKED: Топтама атауын жаз';
  end if;

  -- A cap, because nothing else limits this and a thousand empty collections
  -- would make the learner's own catalogue unusable to them.
  select count(*) into n from public.word_packs where owner = uid;
  if n >= 30 then
    raise exception 'GUEST_LOCKED: Топтама саны шегіне жетті';
  end if;

  insert into public.word_packs
    (title_kk, title_ru, emoji, colour, is_official, owner, created_by)
  values (btrim(p_title), btrim(p_title), p_emoji, p_colour, false, uid, uid)
  returning word_packs.id into id;
  return id;
end;
$$;

create or replace function public.rename_my_pack(p_pack bigint, p_title text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if btrim(coalesce(p_title, '')) = '' then
    raise exception 'GUEST_LOCKED: Топтама атауын жаз';
  end if;
  update public.word_packs
     set title_kk = btrim(p_title), title_ru = btrim(p_title)
   where id = p_pack and owner = auth.uid();
end;
$$;

create or replace function public.delete_my_pack(p_pack bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- Entries go with it through the cascade. Only a pack the caller owns can
  -- be deleted, so an official one is untouchable here whatever is passed.
  delete from public.word_packs where id = p_pack and owner = auth.uid();
end;
$$;

-- EN-34's actual point: adding a word the learner already has, with one tap,
-- rather than retyping something the dictionary already holds.
create or replace function public.add_word_to_pack(
  p_pack bigint, p_dictionary_id bigint)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
begin
  if not exists (select 1 from public.word_packs
                  where id = p_pack and owner = uid) then
    raise exception 'not your pack';
  end if;

  insert into public.word_pack_entries (pack_id, dictionary_id)
  values (p_pack, p_dictionary_id)
  on conflict (pack_id, dictionary_id) do nothing;

  return (select count(*)::int from public.word_pack_entries
           where pack_id = p_pack);
end;
$$;

create or replace function public.remove_word_from_pack(
  p_pack bigint, p_dictionary_id bigint)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not exists (select 1 from public.word_packs
                  where id = p_pack and owner = auth.uid()) then
    raise exception 'not your pack';
  end if;

  delete from public.word_pack_entries
   where pack_id = p_pack and dictionary_id = p_dictionary_id;

  return (select count(*)::int from public.word_pack_entries
           where pack_id = p_pack);
end;
$$;

-- ── Moderator side (EN-38 / KK-7) ──────────────────────────
create or replace function public.admin_upsert_pack(
  p_id          bigint,
  p_slug        text,
  p_title_kk    text,
  p_title_ru    text,
  p_subtitle_kk text,
  p_subtitle_ru text,
  p_emoji       text,
  p_colour      text,
  p_topic       text,
  p_levels      text[],
  p_sort        integer,
  p_is_active   boolean)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  id bigint;
begin
  if not public.is_moderator(uid) then raise exception 'not a moderator'; end if;

  if p_id is null then
    insert into public.word_packs
      (slug, title_kk, title_ru, subtitle_kk, subtitle_ru, emoji, colour,
       topic, levels, sort, is_active, is_official, created_by)
    values (p_slug, p_title_kk, coalesce(p_title_ru, ''),
            coalesce(p_subtitle_kk, ''), coalesce(p_subtitle_ru, ''),
            coalesce(p_emoji, '📚'), coalesce(p_colour, '#7C5CFF'),
            p_topic, coalesce(p_levels, '{}'), coalesce(p_sort, 0),
            coalesce(p_is_active, true), true, uid)
    returning word_packs.id into id;
  else
    update public.word_packs
       set slug = p_slug, title_kk = p_title_kk,
           title_ru = coalesce(p_title_ru, ''),
           subtitle_kk = coalesce(p_subtitle_kk, ''),
           subtitle_ru = coalesce(p_subtitle_ru, ''),
           emoji = coalesce(p_emoji, '📚'),
           colour = coalesce(p_colour, '#7C5CFF'),
           topic = p_topic, levels = coalesce(p_levels, '{}'),
           sort = coalesce(p_sort, 0),
           is_active = coalesce(p_is_active, true)
     where word_packs.id = p_id
    returning word_packs.id into id;
  end if;
  return id;
end;
$$;

-- Bulk-fill a pack from the dictionary. This is what makes "expand the
-- collection" possible at all — before, it meant an app release.
create or replace function public.admin_fill_pack(
  p_pack bigint, p_topic text, p_levels text[], p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;

  insert into public.word_pack_entries (pack_id, dictionary_id)
  select p_pack, d.id
  from public.dictionary d
  where (p_topic is null or d.topic = p_topic)
    and (p_levels is null or array_length(p_levels, 1) is null
         or d.cefr = any(p_levels))
  order by d.hits desc, d.id
  limit greatest(1, least(coalesce(p_limit, 200), 1000))
  on conflict (pack_id, dictionary_id) do nothing;

  return (select count(*)::int from public.word_pack_entries
           where pack_id = p_pack);
end;
$$;

create or replace function public.admin_pack_add_words(
  p_pack bigint, p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  insert into public.word_pack_entries (pack_id, dictionary_id)
  select p_pack, unnest(coalesce(p_ids, '{}'::bigint[]))
  on conflict (pack_id, dictionary_id) do nothing;
  return (select count(*)::int from public.word_pack_entries
           where pack_id = p_pack);
end;
$$;

create or replace function public.admin_pack_remove_word(
  p_pack bigint, p_dictionary_id bigint)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  delete from public.word_pack_entries
   where pack_id = p_pack and dictionary_id = p_dictionary_id;
  return (select count(*)::int from public.word_pack_entries
           where pack_id = p_pack);
end;
$$;

-- ── Seeding the six packs the app already ships ────────────
-- Same ids, titles, topics and levels as kWordPacks in meta_store.dart. The
-- `size` numbers from that list are deliberately NOT carried over: they are
-- the fiction this whole file exists to end. Each pack is filled with the
-- words that actually exist, and its count is whatever that turns out to be.
insert into public.word_packs
  (slug, title_kk, title_ru, subtitle_kk, subtitle_ru, emoji, colour, topic, levels, sort)
values
  ('movies', 'Фильм сөздері', 'Слова из фильмов',
   'Диалогтан алынған лексика', 'Лексика из диалогов',
   '🎬', '#7C5CFF', 'communication', array['B1','B2'], 1),
  ('ielts', 'IELTS 6.5+', 'IELTS 6.5+',
   'Академиялық лексика', 'Академическая лексика',
   '🎓', '#3B82F6', 'school', array['B2','C1'], 2),
  ('songs', 'Ән мәтіндері', 'Тексты песен',
   'Поп-музыка тілі', 'Язык поп-музыки',
   '🎵', '#EC4899', 'emotions', array['A2','B1'], 3),
  ('tech', 'Tech & IT', 'Tech & IT',
   'Мамандық сөздері', 'Профессиональные слова',
   '💻', '#12B981', 'tech', array['B1','B2'], 4),
  ('travel', 'Саяхат', 'Путешествия',
   'Әуежай, қонақүй, жол', 'Аэропорт, отель, дорога',
   '✈️', '#F59E0B', 'travel', array['A2','B1'], 5),
  ('food', 'Ас мәзірі', 'Меню',
   'Кафе мен базар тілі', 'Язык кафе и рынка',
   '🍜', '#F0455E', 'food', array['A1','A2'], 6)
on conflict (slug) do update
  set title_ru = excluded.title_ru,
      subtitle_ru = excluded.subtitle_ru,
      emoji = excluded.emoji,
      colour = excluded.colour;

-- Fill each from the dictionary as it stands today. Re-running is harmless:
-- the insert conflicts on the pair and adds only what is new, so this doubles
-- as the way to top a pack up after the dictionary grows.
insert into public.word_pack_entries (pack_id, dictionary_id)
select p.id, d.id
from public.word_packs p
join public.dictionary d
  on (p.topic is null or d.topic = p.topic)
 and (array_length(p.levels, 1) is null or d.cefr = any(p.levels))
where p.is_official
on conflict (pack_id, dictionary_id) do nothing;

grant execute on function public.pack_catalogue()                    to authenticated;
grant execute on function public.pack_words(bigint, integer, integer) to authenticated;
grant execute on function public.create_my_pack(text, text, text)    to authenticated;
grant execute on function public.rename_my_pack(bigint, text)        to authenticated;
grant execute on function public.delete_my_pack(bigint)              to authenticated;
grant execute on function public.add_word_to_pack(bigint, bigint)    to authenticated;
grant execute on function public.remove_word_from_pack(bigint, bigint) to authenticated;
grant execute on function public.admin_upsert_pack(
  bigint, text, text, text, text, text, text, text, text, text[], integer, boolean)
  to authenticated;
grant execute on function public.admin_fill_pack(bigint, text, text[], integer)
  to authenticated;
grant execute on function public.admin_pack_add_words(bigint, bigint[]) to authenticated;
grant execute on function public.admin_pack_remove_word(bigint, bigint)  to authenticated;

notify pgrst, 'reload schema';
