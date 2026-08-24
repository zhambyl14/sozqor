# SQL to apply — v5.0

The schema lives in the Supabase project, not in this repo, so these are
applied by hand: open the Supabase dashboard → **SQL Editor** → paste one file
→ Run. There is no CLI and no service key on the dev machine, which is why
they are files rather than migrations.

**The app ships without them and keeps working.** Every screen that calls a
new RPC handles the error, so a missing function shows a message rather than a
blank page. But the features below stay broken until the matching file is run.

Run them in this order. Each is safe to run once; only `v5_coins_currency.sql`
must **not** be run twice.

| # | File | Fixes | Until it runs |
|---|---|---|---|
| 1 | `v5_battle_settlement.sql` | EN-18 / KK-3 — the rating bug | Whoever finishes a match first still gets no XP and no win recorded; a decisive win against a far weaker opponent still moves nobody; an abandoned match never settles |
| 2 | `v5_friend_requests.sql` | EN-15 / EN-16 / KK-2 | The friends screen shows "функция табылмады" on add; anybody can still be added without consent |
| 3 | `v5_delete_account.sql` | EN-45 / KK-10 | "Аккаунтты жою" errors instead of deleting |
| 4 | `v5_coins_currency.sql` | EN-42 / KK-6 | The shop still spends XP while the UI says coins — **the one real mismatch**, so run this in the same sitting as deploying the app |
| 5 | `v5_teams.sql` | EN-24 / EN-25 / EN-26 / KK-4 — teams, the weekly team challenge and the clan war | The team screens show "команда жүйесі әлі қосылмаған" and nothing else |
| 6 | `v5_translation_review.sql` | EN-49 / EN-50 / KK-8 — the moderator queue behind the translation gate | The gate still works and still refuses transliterations; the refusals are simply not recorded anywhere |
| 7 | `v5_league_elo.sql` | EN-19 / KK-3 — the league becomes a rating ladder | The league still ranks on weekly XP and the band never changes with your rating; matchmaking ignores bands. **Run after #1** — it replaces a function that file introduces |
| 8 | `v5_telegram_lang.sql` | EN-4 / KK-9 — the bot speaks the app's language | The bot answers every learner in Kazakh, including one who set the app to Russian |
| 9 | `v5_tournament_survival.sql` | EN-23 / KK-4 — the tournament becomes survival | The run screen opens and plays, but lives never decrease, the board still ranks on score alone, and a tournament still cannot be retired |
| 10 | `v5_collections.sql` | EN-32 / EN-34 / EN-38 / KK-5 — word collections become rows | The collections screen shows "топтама жүйесі әлі қосылмаған" and nobody can make their own. **Seeds the six existing packs and fills them from the dictionary**, so the count on each becomes true the moment it runs |

`profiles_guard.sql` and `device_tokens.sql` are already applied; they are kept
for reference.

## What each one actually changes

**`v5_battle_settlement.sql`** rewrites `submit_battle_result` and adds
`claim_battle_forfeit`. Three separate defects lived in the old function: the
reward block ran only for whoever submitted *second*, so the first finisher got
nothing; `round(k * (1 - exp1))` is 0 once the Elo gap is wide enough, so a
lopsided win moved neither rating; and nothing settled a match whose second
player never submitted, which left the row `active` for ever. Also clamps the
client-supplied score to what the question count can possibly produce.

**`v5_friend_requests.sql`** adds `send_friend_request`,
`respond_friend_request`, `my_friend_requests`, `my_sent_requests`, tightens
`search_users` to need two characters, and **drops the client INSERT/UPDATE
policies on `friendships`** so consent cannot be skipped.

**`v5_delete_account.sql`** adds `delete_my_account()`. It takes no argument
and works on `auth.uid()`, so it cannot be aimed at another account. Finished
battles are kept with the id detached rather than deleted — they are the
opponent's history and their rating too.

**`v5_coins_currency.sql`** moves the shop off XP. Divides every price by ten
to match the rate `coins` accrues at, tops each account up to at least what its
unspent XP could have bought, zeroes `xp_spent`, and rewrites `buy_cosmetic`.
**Not idempotent** — running it twice divides prices twice.

## Edge function secrets

`supabase/functions/sozqor-ai` needs `FREEROUTER_API_KEY` set in the function's
secrets (Supabase dashboard → Edge Functions → sozqor-ai → Secrets). It is a
free OpenAI-compatible gateway and it is now the first provider tried, because
on the probe that motivated the translation gate it was the only one configured
here that answered the hard word correctly.

**Never put that key in this repository — it is public.** Nothing in the tree
contains it and nothing should.

`v5_translation_review.sql` revokes `dict_upsert` from `authenticated`, which
the edge function currently calls under the caller's own token. After running
it, that one call has to use `SUPABASE_SERVICE_ROLE_KEY` (already available to
the function) or writing a new dictionary entry will start failing.

## The Telegram bot

`supabase/functions/tg-webhook/` was live but had never been in this
repository, so nobody could read it, review it or redeploy it. It is written
down now. Its own header carries the secrets it needs and the exact curl call
that registers the webhook. Deploy it with `--no-verify-jwt` — Telegram cannot
send a Supabase JWT.

`phone-auth` is the other half of that flow and is still not in the repo. It
now receives a `lang` field on its `start` action; it has to store that on the
`phone_verifications` row (the column is added by #8) or the bot has nothing to
read and EN-4 stays broken.

## Adding a client-editable column later

`profiles` has a column guard (`profiles_guard.sql`). Anything not on its
pass-through list is silently reverted on write, so a new settings column has
to be added there too or it will look like it saves and then does not.
