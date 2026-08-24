-- supabase/sql/v5_coins_currency.sql
--
-- v5.0 — EN-42 / KK-6: the shop stops spending XP and spends coins.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
--
-- XP is the number leagues and leaderboards rank on. Spending it in a shop
-- means a cosmetic costs you standing, so the two things the app most wants
-- — competing and customising — are in direct opposition. The current code
-- works around that with `xp_spent`, a second column subtracted from `xp` at
-- the till so the ranking number stays intact. That is a currency already,
-- just one wearing XP's clothes and called XP in the UI.
--
-- `profiles.coins` already exists, and add_xp has been granting
-- `coins += amount / 10` on every award since before this release — so every
-- account is already carrying a balance nobody has ever been able to spend.
-- This makes that balance real.
--
-- MIGRATION OF EXISTING VALUE. Coins accrue at a tenth of XP, so prices are
-- divided by ten to keep everything costing what it used to. Nobody loses
-- purchasing power: each account is topped up to at least what its unspent XP
-- could have bought, and xp_spent is zeroed since it no longer gates anything.
-- Run this once and only once — the top-up is not idempotent.

begin;

-- 1. Prices move to the coin scale. A 500 XP frame becomes a 50 coin frame,
--    which is the same number of battles won.
update public.cosmetics
   set price = greatest(0, round(price / 10.0)::int)
 where price > 0;

-- 2. Nobody is poorer than they were a minute ago. A learner who had 3000
--    unspent XP could buy 3000 XP worth of items; they get the 300 coins that
--    now buys the same set, unless they already hold more than that.
update public.profiles
   set coins = greatest(
         coins,
         greatest(0, round((xp - xp_spent) / 10.0)::int)
       ),
       xp_spent = 0;

-- 3. The till.
create or replace function public.buy_cosmetic(p_item text)
returns public.profiles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uid uuid := auth.uid();
  item public.cosmetics;
  p public.profiles;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into item from public.cosmetics where id = p_item;
  if item.id is null then raise exception 'no such item'; end if;
  if not item.is_active then raise exception 'no such item'; end if;

  if exists (select 1 from public.user_cosmetics
             where user_id = uid and item_id = p_item) then
    select * into p from public.profiles where id = uid;
    return p;                       -- already owned; buying again is a no-op
  end if;

  if not public.cosmetic_unlocked(uid, item.requires) then
    raise exception 'locked';
  end if;

  -- The row lock is what stops two taps from buying one item twice on a
  -- balance that only covers one.
  select * into p from public.profiles where id = uid for update;
  if item.price > p.coins then
    raise exception 'GUEST_LOCKED: Тиын жетпей тұр';
  end if;

  insert into public.user_cosmetics (user_id, item_id) values (uid, p_item);
  update public.profiles set coins = coins - item.price
   where id = uid returning * into p;
  return p;
end;
$$;

commit;
