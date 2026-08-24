-- supabase/sql/v5_cosmetics_content.sql
--
-- v5.0 — EN-41 / KK-6: cosmetics worth wanting.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Run it AFTER v5_coins_currency.sql — the prices below are already on the
-- coin scale, and that file divides every existing price by ten.
--
-- The complaint is that the shop items look cheap, and they did: a frame was
-- one hex colour drawn as a 2px ring, an aura was the same colour drawn as a
-- box shadow, and a badge was an emoji floating on the layout. Three thousand
-- XP bought a slightly different border.
--
-- There is no artist and no asset pipeline on this project, so nothing here
-- ships a file. What changed is that the client now reads a richer `data`
-- payload and draws from it (lib/features/profile/cosmetic_preview.dart):
--
--   color   the ring's first colour, as before
--   color2  a second colour, so a frame can be a gradient rather than a line
--   fx      how it moves — 'sweep', 'shimmer', 'pulse', or absent for still
--
-- A gradient sweep, a travelling highlight and a slow pulse are three things
-- you can tell apart across a room, and every one of them is a database row.
-- Adding a fourth needs no app release.
--
-- Safe to re-run: everything is `on conflict (id) do update`.

insert into public.cosmetics
  (id, kind, name_kk, name_ru, price, rarity, sort, requires, data, is_active)
values
  -- ── Frames ───────────────────────────────────────────────
  ('frame_dawn', 'frame', 'Таң шапағы', 'Заря', 45, 'rare', 10, null,
   '{"color":"#F59E0B","color2":"#F0455E","fx":"sweep"}'::jsonb, true),
  ('frame_steppe', 'frame', 'Дала желі', 'Степной ветер', 45, 'rare', 11, null,
   '{"color":"#12B981","color2":"#38BDF8","fx":"sweep"}'::jsonb, true),
  ('frame_night', 'frame', 'Түнгі аспан', 'Ночное небо', 80, 'epic', 12, null,
   '{"color":"#7C5CFF","color2":"#3B82F6","fx":"shimmer"}'::jsonb, true),
  ('frame_ember', 'frame', 'Шоқ', 'Тлеющий уголь', 80, 'epic', 13, null,
   '{"color":"#F0455E","color2":"#F59E0B","fx":"pulse"}'::jsonb, true),
  -- Earned, not sold. `requires` is metric:threshold, the same shape the
  -- existing reward items already use.
  ('frame_qyran', 'frame', 'Қыран қанаты', 'Крыло беркута', 0, 'legend', 14,
   'streak:30', '{"color":"#F5D142","color2":"#B87333","fx":"shimmer"}'::jsonb, true),
  ('frame_tugyr', 'frame', 'Тұғыр', 'Вершина', 0, 'legend', 15,
   'elo:2500', '{"color":"#F0455E","color2":"#7C5CFF","fx":"shimmer"}'::jsonb, true),

  -- ── Auras ────────────────────────────────────────────────
  ('aura_warm', 'aura', 'Жылу', 'Тепло', 30, 'common', 20, null,
   '{"color":"#F59E0B"}'::jsonb, true),
  ('aura_frost', 'aura', 'Аяз', 'Мороз', 30, 'common', 21, null,
   '{"color":"#38BDF8"}'::jsonb, true),
  ('aura_violet', 'aura', 'Кешкі шапақ', 'Сумерки', 55, 'rare', 22, null,
   '{"color":"#7C5CFF"}'::jsonb, true),
  ('aura_gold', 'aura', 'Алтын шуақ', 'Золотое сияние', 0, 'legend', 23,
   'xp:20000', '{"color":"#F5D142"}'::jsonb, true),

  -- ── Titles ───────────────────────────────────────────────
  -- Drawn in the frame's colour now rather than as plain text, which is why
  -- a title bought for coins used to look the same as no title at all.
  ('title_okushy', 'title', 'Ізденуші', 'Искатель', 20, 'common', 30, null,
   '{}'::jsonb, true),
  ('title_sozshy', 'title', 'Сөзші', 'Словесник', 40, 'rare', 31, null,
   '{}'::jsonb, true),
  ('title_kurash', 'title', 'Күрескер', 'Боец', 0, 'rare', 32,
   'battles_won:50', '{}'::jsonb, true),
  ('title_ustaz', 'title', 'Ұстаз', 'Наставник', 0, 'epic', 33,
   'words:500', '{}'::jsonb, true),
  ('title_tugyr', 'title', 'Тұғырдағы', 'На вершине', 0, 'legend', 34,
   'elo:3000', '{}'::jsonb, true),

  -- ── Banners ──────────────────────────────────────────────
  ('banner_steppe', 'banner', 'Дала', 'Степь', 35, 'common', 40, null,
   '{"color":"#12B981"}'::jsonb, true),
  ('banner_dusk', 'banner', 'Ымырт', 'Сумерки', 35, 'common', 41, null,
   '{"color":"#7C5CFF"}'::jsonb, true),
  ('banner_flame', 'banner', 'Жалын', 'Пламя', 60, 'rare', 42, null,
   '{"color":"#F0455E"}'::jsonb, true),

  -- ── Badges ───────────────────────────────────────────────
  ('badge_flame', 'badge', 'Жалын', 'Пламя', 25, 'common', 50, null,
   '{"emoji":"🔥"}'::jsonb, true),
  ('badge_eagle', 'badge', 'Қыран', 'Беркут', 50, 'rare', 51, null,
   '{"emoji":"🦅"}'::jsonb, true),
  ('badge_crown', 'badge', 'Тәж', 'Корона', 0, 'legend', 52,
   'elo:2800', '{"emoji":"👑"}'::jsonb, true)
on conflict (id) do update
  set name_kk = excluded.name_kk,
      name_ru = excluded.name_ru,
      price   = excluded.price,
      rarity  = excluded.rarity,
      sort    = excluded.sort,
      requires = excluded.requires,
      data    = excluded.data,
      is_active = excluded.is_active;

-- The frames that already existed carry only a `color`, so they render as a
-- flat ring next to the new ones. Giving them a second colour costs nothing
-- and stops the shop looking like two different shops.
update public.cosmetics
   set data = data || jsonb_build_object(
         'color2', coalesce(data->>'color', '#7C5CFF'))
 where kind = 'frame'
   and data ? 'color'
   and not (data ? 'color2');
