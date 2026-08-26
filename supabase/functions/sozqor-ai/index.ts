// SozQor AI gateway
// Keeps LLM API keys server-side and grows the shared dictionary
// so repeated lookups never cost a request.
//
// Tasks: translate | enrich | suggest | chat | explain | health | raw
//
// ── Why the provider order is what it is ───────────────────
//
// It was measured, not reasoned about. `ai-probe` asks every configured model
// the same four Kazakh words and reports what each answered:
//
//   word        gemini-2.5-flash    gemini-3.6-flash   freerouter   openrouter
//   шаңырақ     yurt crown ✓        yurt crown ✓       502 / empty  "" / 404
//   шамшырақ    lighthouse ✓        lighthouse ✓       502 / empty  "..." / 404
//   жалаңаш     naked ✓             naked ✓            502 / empty  "" / 404
//   мұғалім     teacher ✓           teacher ✓          502 / empty  teacher ✓
//
// and every OpenAI model, on every word:
//   429 "You exceeded your current quota".
//
// So Gemini is not one option among several — it is the only provider on this
// project that answers Kazakh at all.
//
// OpenAI and FreeRouter used to be in this chain and are gone. Keeping a
// provider that has never once answered is not a safety net, it is latency:
// OpenAI is a PAID key with no credit on it, and FreeRouter returned a 502
// HTML page for every word probed. Both were removed rather than reordered,
// and that alone is most of the difference between a 22-second lookup and a
// two-second one.
//
// What is left is Gemini, and — for the tasks whose output is never written
// to the shared dictionary (chat, explain, raw) — the two OpenRouter models
// that actually respond. Everything the dictionary keeps comes from Gemini.
//
// ── Why two models answer every new word ───────────────────
//
// A translate result is written into the dictionary everybody shares, so a
// wrong answer is not one learner's problem. Two independent models are asked
// AT THE SAME TIME — not one after the other, which is what made the old
// second-opinion cost a whole extra round trip — and the answer is published
// only if they agree. Self-reported confidence is never consulted: on the
// probe that started this, two models answered "шамшырақ" with "beacon" and
// "sunflower" and both reported 0.95.
//
// When they DISAGREE the word is not refused — a third model breaks the tie.
// "шаңырақ" is honestly both "yurt crown" and "home", and refusing it over
// that is the "Аударма табылмады" dead end. Only the STRUCTURAL gate —
// script, identity, transliteration in both directions, length — refuses
// outright, because a romanisation really is no answer at all.
// The named defect: "шаңырақ" reached a learner as "shangri-la".
//
// ── Function secrets ───────────────────────────────────────
//   GEMINI_API_KEY      the one that matters (never commit it)
//   GEMINI_API_KEY_2 … _5   optional spares, used automatically
//   OPENROUTER_API_KEY  optional; chat and explain only
//   SUPABASE_SERVICE_ROLE_KEY   injected by Supabase; required, see below
//
// The free Gemini tier has a daily cap, and with one key a single busy
// afternoon takes the whole app's translation down. Every extra key is tried
// in turn and benched on its own when it refuses, so a second one roughly
// doubles the day and needs no code change to add.
//
// The OpenAI and FreeRouter secrets are no longer read at all. They can be
// deleted from the function's settings.
//
// `dict_upsert` is revoked from `authenticated` (v5_translation_review.sql),
// so writing to the dictionary under the caller's own token now fails. Every
// write here goes through a service-role client instead.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_KEY = Deno.env.get("OPENROUTER_API_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/// As many Gemini keys as are configured, in order.
///
/// The free tier has a daily cap, and one key means one bad afternoon takes
/// the whole app's translation down — which is exactly what happened. Each
/// key is treated as its OWN provider by the cooldown below, so a 429 on the
/// first one benches that key for ninety seconds and the second answers the
/// very next word. Adding a third is a secret, not a deploy.
const GEMINI_KEYS = [
  Deno.env.get("GEMINI_API_KEY") ?? "",
  Deno.env.get("GEMINI_API_KEY_2") ?? "",
  Deno.env.get("GEMINI_API_KEY_3") ?? "",
  Deno.env.get("GEMINI_API_KEY_4") ?? "",
  Deno.env.get("GEMINI_API_KEY_5") ?? "",
].filter((k) => k.length > 0);

const HAS_GEMINI = GEMINI_KEYS.length > 0;

// 2.5-flash first: on the probe it was both the most accurate and the fastest
// (1.3-3.3s against 3.1-10.9s for 3.6-flash). 3.6-flash is the immediate
// fallback because the free tier answers 429 under load, and flash-latest
// last because it is the one that returns 503 "high demand".
const GEMINI_MODELS = [
  "gemini-2.5-flash",
  "gemini-3.6-flash",
  "gemini-flash-latest",
];

// Gemini spends output tokens on hidden reasoning before it writes anything,
// so a budget sized for the visible answer comes back finishReason
// MAX_TOKENS with an empty candidate. These floors are what the probe needed.
const GEMINI_MIN_TOKENS = 2048;

// Deliberately NOT setting thinkingConfig.
//
// It was tried: thinkingBudget 0 cuts a lookup from about eight seconds to
// four and a half, and it was measured, and it was reverted — because with
// thinking off, 2.5-flash answers "шаңырақ" with "shanyrak". WITH thinking it
// answers "yurt crown". That is not a rounding error; "shanyrak" is the exact
// defect this whole gate exists to catch, on the exact word the report named.
//
// Translation looked like lookup rather than reasoning. On a language with
// this little training data it is neither: it is recall, and the model needs
// room to do it. Three and a half seconds is what recall costs, and a cache
// hit still returns in one.

// The only two of the free OpenRouter models that answered at all when
// probed; the rest 404 with "unavailable for free". Never used for anything
// that reaches the dictionary — see `trustedOnly`.
const FREE_MODELS = [
  "nvidia/nemotron-3-super-120b-a12b:free",
  "nvidia/nemotron-3-nano-30b-a3b:free",
];

// A learner is waiting behind every one of these. 45 seconds was long enough
// for five sequential providers to add up to three minutes.
const LLM_TIMEOUT = 7_000;
const FREE_TIMEOUT = 4_000;

// The whole of a translate, end to end. Past this the answer is whatever the
// keyless services or the stored row can give.
const TRANSLATE_DEADLINE = 9_000;
const BASIC_DEADLINE = 5_000;
const ARBITER_DEADLINE = 5_000;

// The second opinion is worth having, not worth waiting for. Past this it is
// treated as an abstention and the primary answer stands on the structural
// gate alone -- a learner staring at a spinner is a worse outcome than an
// answer with one endorsement instead of two.
const SECOND_DEADLINE = 6_000;

/// Resolves to null instead of hanging on past `ms`.
function withDeadline<T>(p: Promise<T>, ms: number): Promise<T | null> {
  return Promise.race([
    p,
    new Promise<null>((resolve) => setTimeout(() => resolve(null), ms)),
  ]);
}

const RATE_MSG = "AI лимиті бітті — қазір қарапайым аудармамен жұмыс істейміз.";
const NO_KEY_MSG = "AI кілттері бапталмаған";

// Every message the learner can actually read. The client sends `lang`, so an
// error lands in the same language as the rest of the interface.
const MSG: Record<string, { kk: string; ru: string }> = {
  rate: {
    kk: RATE_MSG,
    ru: "Лимит AI исчерпан — сейчас работаем с простым переводом.",
  },
  noKey: { kk: NO_KEY_MSG, ru: "Ключи AI не настроены" },
  auth: { kk: "Авторизация қажет", ru: "Нужна авторизация" },
  empty: { kk: "Бос сұраныс", ru: "Пустой запрос" },
  noAnswer: { kk: "AI жауап бермеді", ru: "AI не ответил" },
  unreadable: {
    kk: "AI жауабын оқу мүмкін болмады",
    ru: "Не удалось прочитать ответ AI",
  },
  noTranslation: { kk: "Аударма табылмады", ru: "Перевод не найден" },
  noList: { kk: "AI тізім қайтармады", ru: "AI не вернул список" },
  unknownTask: { kk: "Белгісіз тапсырма", ru: "Неизвестная задача" },
};

type Lang = "kk" | "ru";

const say = (key: keyof typeof MSG, lang: Lang) => MSG[key][lang];

/// Full language name, for prompts that must answer in the learner's language.
const LANG_NAME: Record<Lang, string> = { kk: "Kazakh", ru: "Russian" };

/// `lang` (interface language) and `study_lang` (which language new words
/// translate to) are two independent client settings and stay independent
/// here: every error message in this function is UI chrome and always uses
/// `lang`, while `study_lang` is used ONLY by the two tasks whose whole
/// output is study content — explain's text and chat's framing.
const studyLang = (raw: unknown, fallback: Lang): Lang =>
  clean(raw) === "ru" ? "ru" : clean(raw) === "kk" ? "kk" : fallback;

/// The chat scenarios are Kazakh labels the client also uses as lookup keys
/// for its own offline scripted tutor, so they cannot simply be translated in
/// place. Sent to an English-only model as-is they ground nothing.
const SCENE_EN: Record<string, string> = {
  "Кофеханада": "a coffee shop — you are the barista taking the customer's order",
  "Әуежайда": "an airport check-in counter — you are the airline staff member",
  "Жұмыс сұхбаты": "a job interview — you are the interviewer",
  "Дүкенде": "a clothing store — you are the shop assistant helping a customer",
  "Дәрігерде": "a doctor's office — you are the doctor examining a patient",
};

const sceneEn = (kk: string) => SCENE_EN[kk] ?? "a friendly everyday situation";

// ── LLM transports ─────────────────────────────────────────

/// OpenRouter speaks the OpenAI chat-completions shape.
async function chatCompletions(
  url: string,
  key: string,
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
  label: string,
) {
  if (!key) throw new Error(NO_KEY_MSG);
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
      "X-Title": "SozQor",
    },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: prompt }],
      temperature,
      max_tokens: maxTokens,
    }),
    signal: AbortSignal.timeout(LLM_TIMEOUT),
  });
  if (!res.ok) {
    // The status alone cannot tell "no credit left" from "too fast"; both are
    // 429. Carry a slice of the body so the cause is visible in `note`.
    const detail = (await res.text().catch(() => "")).slice(0, 200);
    throw new Error(`${res.status === 429 ? "429" : res.status} ${label}/${model} ${detail}`);
  }
  const json = await res.json();
  const text = json?.choices?.[0]?.message?.content ?? "";
  if (!text.trim()) throw new Error(`empty ${label}/${model}`);
  return text as string;
}

const callOpenRouter = (model: string, p: string, t: number, m: number) =>
  chatCompletions(
    "https://openrouter.ai/api/v1/chat/completions",
    OPENROUTER_KEY, model, p, t, m, "openrouter",
  );

async function callGemini(
  key: string,
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
) {
  if (!key) throw new Error(NO_KEY_MSG);
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature,
          maxOutputTokens: Math.max(maxTokens, GEMINI_MIN_TOKENS),
        },
      }),
      signal: AbortSignal.timeout(LLM_TIMEOUT),
    },
  );
  if (res.status === 429) throw new Error(`429 gemini/${model}`);
  if (!res.ok) {
    throw new Error(`${res.status} gemini/${model} ${(await res.text().catch(() => "")).slice(0, 160)}`);
  }
  const json = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!text.trim()) {
    throw new Error(
      `empty gemini/${model} finish=${json?.candidates?.[0]?.finishReason ?? "?"}`,
    );
  }
  return text as string;
}

/// One attempt at one model, named so a caller can pick a SECOND opinion from
/// a different model rather than the same one twice.
type Attempt = { id: string; run: () => Promise<string> };

/// Every provider this project can reach, best first. `trustedOnly` drops the
/// free OpenRouter models, which return confident well-formed wrong JSON —
/// "кітап" as "unknown", "жалаңаш" as "silly" — and are therefore unfit for
/// anything that lands in the shared dictionary.
function chain(
  prompt: string,
  temperature: number,
  maxTokens: number,
  trustedOnly: boolean,
): Attempt[] {
  const out: Attempt[] = [];
  // Best model on EVERY key before falling back to a weaker model on any of
  // them: a key that is out of quota should cost the learner one 150ms
  // refusal, not a slower answer.
  for (const m of GEMINI_MODELS) {
    GEMINI_KEYS.forEach((key, i) => {
      out.push({
        id: `gemini${i + 1}/${m}`,
        run: () => callGemini(key, m, prompt, temperature, maxTokens),
      });
    });
  }
  if (OPENROUTER_KEY && !trustedOnly) {
    for (const m of FREE_MODELS) {
      out.push({ id: `openrouter/${m}`, run: () => callOpenRouter(m, prompt, temperature, maxTokens) });
    }
  }
  return out;
}

/// Walks the chain until one provider answers. Returns the text and which
/// model produced it, so a wrong word can be traced to its source instead of
/// being blamed on "the AI".
/// When each vendor may be tried again. A spent quota is not a fact about one
/// request -- it stays true for minutes -- and this function is called several
/// times per translate, so remembering it across calls (and across requests,
/// while the instance lives) is what stops a dead key being re-probed six
/// times a word. This is the difference between a 28-second wait and a
/// 5-second one when Gemini's free tier runs out.
const cooldownUntil = new Map<string, number>();
const QUOTA_COOLDOWN = 90_000;
const FLAKY_COOLDOWN = 60_000;

/// A free model that answers 404 or empty will answer the same way in a
/// second. Gemini is not treated that way -- only an explicit quota refusal
/// puts it on the bench, because a one-off 503 there is genuinely transient.
const FLAKY = new Set(["openrouter"]);

async function completeFrom(
  attempts: Attempt[],
  skip = new Set<string>(),
): Promise<{ text: string; model: string }> {
  const problems: string[] = [];
  const now = Date.now();
  // Every model behind one vendor shares one key and one quota, so a 429 from
  // gemini/2.5-flash tells you exactly as much about gemini/3.6-flash. Trying
  // the rest anyway is what turned a spent quota into a 28-second wait.
  const spent = new Set<string>();
  for (const a of attempts) {
    if (skip.has(a.id)) continue;
    const vendor = a.id.split("/")[0];
    if (spent.has(vendor)) continue;
    if ((cooldownUntil.get(vendor) ?? 0) > now) {
      problems.push(`cooling ${vendor}`);
      continue;
    }
    try {
      return { text: await a.run(), model: a.id };
    } catch (e) {
      const msg = String(e);
      problems.push(msg);
      if (msg.includes("429") || msg.includes("quota") || msg.includes(NO_KEY_MSG)) {
        spent.add(vendor);
        cooldownUntil.set(vendor, Date.now() + QUOTA_COOLDOWN);
      } else if (FLAKY.has(vendor)) {
        spent.add(vendor);
        cooldownUntil.set(vendor, Date.now() + FLAKY_COOLDOWN);
      }
    }
  }
  const all = problems.join(" | ");
  if (problems.length > 0 && problems.every((p) => p.includes(NO_KEY_MSG))) {
    throw new Error(NO_KEY_MSG);
  }
  throw new Error(
    all.includes("429") || all.includes("cooling")
      ? `${RATE_MSG} | ${all}`
      : all || MSG.noAnswer.kk,
  );
}

async function complete(
  prompt: string,
  temperature = 0.3,
  maxTokens = 2048,
  trustedOnly = false,
) {
  return (await completeFrom(chain(prompt, temperature, maxTokens, trustedOnly))).text;
}

// ── Keyless translation fallback ───────────────────────────
//
// None of these needs an API key and none is reliable on its own from a
// datacentre IP, so the chain matters more than any single one. They are
// raced rather than walked: three 4-second attempts in sequence is twelve
// seconds a learner spends watching a spinner.

async function viaGoogle(text: string, from: string, to: string) {
  const url = "https://translate.googleapis.com/translate_a/single" +
    `?client=gtx&sl=${from}&tl=${to}&dt=t&q=${encodeURIComponent(text)}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(FREE_TIMEOUT) });
  if (!res.ok) return "";
  const json = await res.json();
  return (json?.[0] ?? [])
    .map((part: unknown[]) => (Array.isArray(part) ? part[0] ?? "" : ""))
    .join("")
    .trim();
}

async function viaMyMemory(text: string, from: string, to: string) {
  const url = "https://api.mymemory.translated.net/get" +
    `?q=${encodeURIComponent(text)}&langpair=${from}|${to}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(FREE_TIMEOUT) });
  if (!res.ok) return "";
  const json = await res.json();
  const out = String(json?.responseData?.translatedText ?? "").trim();
  // MyMemory answers with a sentence of its own when it has no match.
  if (!out || /^(NO QUERY SPECIFIED|MYMEMORY WARNING|INVALID)/i.test(out)) return "";
  return out;
}

async function viaLingva(text: string, from: string, to: string) {
  const url = `https://lingva.ml/api/v1/${from}/${to}/${encodeURIComponent(text)}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(FREE_TIMEOUT) });
  if (!res.ok) return "";
  const json = await res.json();
  return String(json?.translation ?? "").trim();
}

/// Trims the debris these services attach to a match. MyMemory in particular
/// answers a one-word lookup with the whole translation-memory segment it
/// found — "kitchen" came back as "ас үйconstellation name (optional)".
///
/// The strongest signal is script: a Kazakh or Russian answer has no business
/// containing Latin letters, and an English one has no business containing
/// Cyrillic, so the answer is cut at the point where the script flips.
function tidy(out: string, src: string, to: string): string {
  let s = out.split("\n")[0].trim();

  const cut = to === "en" ? /[Ѐ-ӿ]/ : /[A-Za-z]/;
  const at = s.search(cut);
  if (at > 0) s = s.slice(0, at).trim();

  s = s.replace(/\s*\([^)]*\)?\s*$/, "").trim();   // trailing "(optional)"
  s = s.replace(/[.,;:]+$/, "").trim();

  if (!s) return "";
  // A single word must not come back as a sentence.
  const srcWords = src.trim().split(/\s+/).length;
  if (srcWords === 1 && s.split(/\s+/).length > 4) return "";
  if (s.length > Math.max(48, src.length * 5)) return "";
  return s;
}

/// Asks all three at once and returns an answer only if TWO OF THEM AGREE.
///
/// Taking the first one that survived the gate is what put "butterfly" in
/// front of a learner who typed "бауырсақ": one of these services answered
/// with a word that has nothing to do with the term, and nothing structural
/// about "butterfly" says it is wrong. These are machine-translation
/// endpoints being asked about Kazakh, which is the language they are worst
/// at — a single one of them is not evidence.
///
/// Two independent services landing on the same word is. When they do not,
/// the honest answer is that there is no answer: a gap in the dictionary is
/// recoverable, a confident wrong word is not.
///
/// `from` must be a real language code — auto-detection is done here rather
/// than by the provider, because the two that support it disagree about
/// Kazakh.
async function freeTranslate(
  text: string,
  from: string,
  to: string,
): Promise<string> {
  const one = async (p: (t: string, f: string, x: string) => Promise<string>) => {
    const out = tidy(await p(text, from, to), text, to);
    if (!out) return "";
    if (gate(text, out, to as "en" | "kk" | "ru") !== null) return "";
    return out;
  };

  const answers = (await Promise.all(
    [viaGoogle, viaMyMemory, viaLingva].map((p) => one(p).catch(() => "")),
  )).filter(Boolean);
  if (answers.length < 2) return "";

  const flat = (x: string) => x.toLowerCase().replace(/[^\p{L}]/gu, "");
  for (let i = 0; i < answers.length; i++) {
    for (let j = i + 1; j < answers.length; j++) {
      // 0.85, not equality: these services differ on articles and plurals
      // ("a book" / "book", "кітаптар" / "кітап") without disagreeing.
      if (similarity(flat(answers[i]), flat(answers[j])) >= 0.85) {
        // The shorter of the two is the headword rather than the phrase.
        return answers[i].length <= answers[j].length ? answers[i] : answers[j];
      }
    }
  }
  return "";
}

const hasCyrillic = (s: string) => /[Ѐ-ӿ]/.test(s);
const hasLatin = (s: string) => /[A-Za-z]/.test(s);
const isKazakhOnly = (s: string) => /[әғқңөұүһі]/i.test(s);

// ── The translation gate (EN-49 / KK-8) ────────────────────
//
// The named bug: "шамшырақ" was answered with "shamshyraq", and "шаңырақ"
// with "shangri-la". Both are the word written in Latin letters rather than
// translated, and both reached learners as if they were real answers.
//
// A script check cannot catch this — a transliteration is Latin, one word,
// about the right length. So the gate asks the question the script test
// cannot: is this answer simply the source word respelled? Everything here is
// structural. Nothing asks a model how sure it is.

/// Kazakh Cyrillic to Latin. TWO tables, because the providers disagree about
/// how to respell the same letter and a single table misses half of them:
/// `tight` is the compact convention (ң→n, қ→q) and `loose` the expanded one
/// (ң→ng, қ→k). "шаңырақ" is "shanyraq" under one and "shangyrak" under the
/// other — and it is only the second that puts it close enough to
/// "shangri-la" to be caught.
const TRANSLIT_COMMON: Array<[RegExp, string]> = [
  [/щ/g, "sh"], [/ш/g, "sh"], [/ч/g, "ch"], [/ц/g, "ts"],
  [/ю/g, "yu"], [/я/g, "ya"], [/ё/g, "yo"], [/ж/g, "zh"],
  [/ә/g, "a"], [/ғ/g, "g"], [/ө/g, "o"], [/ұ/g, "u"], [/ү/g, "u"],
  [/һ/g, "h"], [/і/g, "i"],
  [/а/g, "a"], [/б/g, "b"], [/в/g, "v"], [/г/g, "g"], [/д/g, "d"],
  [/е/g, "e"], [/з/g, "z"], [/и/g, "i"], [/й/g, "y"], [/к/g, "k"],
  [/л/g, "l"], [/м/g, "m"], [/н/g, "n"], [/о/g, "o"], [/п/g, "p"],
  [/р/g, "r"], [/с/g, "s"], [/т/g, "t"], [/у/g, "u"], [/ф/g, "f"],
  [/х/g, "h"], [/ы/g, "y"], [/э/g, "e"], [/ъ/g, ""], [/ь/g, ""],
];

const TRANSLIT_TIGHT: Array<[RegExp, string]> = [
  [/қ/g, "q"], [/ң/g, "n"], ...TRANSLIT_COMMON,
];
const TRANSLIT_LOOSE: Array<[RegExp, string]> = [
  [/қ/g, "k"], [/ң/g, "ng"], ...TRANSLIT_COMMON,
];

function romaniseWith(s: string, table: Array<[RegExp, string]>): string {
  let out = s.toLowerCase();
  for (const [re, to] of table) out = out.replace(re, to);
  return out.replace(/[^a-z]/g, "");
}

/// How much a Latin string looks like a respelling of a Cyrillic one, under
/// either convention. Taking the max is the point: a provider only has to
/// match one of them for this to be a transliteration.
function translitScore(cyrillic: string, latin: string): number {
  const flat = latin.toLowerCase().replace(/[^a-z]/g, "");
  if (flat.length < 3) return 0;
  return Math.max(
    similarity(romaniseWith(cyrillic, TRANSLIT_TIGHT), flat),
    similarity(romaniseWith(cyrillic, TRANSLIT_LOOSE), flat),
  );
}

/// 0.55, down from 0.72. Measured against the two words this exists for:
/// "шаңырақ"/"shangri-la" scores 0.61 under the loose table (0.56 tight), and
/// "шамшырақ"/"shamshyraq" scores 1.00 — while real translations sit far
/// below: "мұғалім"/"teacher" 0.14, "жалаңаш"/"naked" 0.22,
/// "шамшырақ"/"beacon" 0.20, "шаңырақ"/"yurt crown" 0.20.
const TRANSLIT_LIMIT = 0.55;

/// Levenshtein distance, normalised to 0..1 against the longer string.
function similarity(a: string, b: string): number {
  if (!a && !b) return 1;
  if (!a || !b) return 0;
  const m = a.length, n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i, ...Array(n).fill(0)];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    prev = cur;
  }
  return 1 - prev[n] / Math.max(m, n);
}

/// Why a candidate was refused. Also the `failed_check` column of
/// `translation_reports`, so a moderator can see what the machine objected to.
type GateFail =
  | "script"
  | "identity"
  | "translit"
  | "length"
  | "disagree"
  | null;

/// Judges one candidate translation of `src` into `to`.
/// Returns null when the candidate is acceptable, or the reason it is not.
function gate(src: string, candidate: string, to: "en" | "kk" | "ru"): GateFail {
  const s = src.trim().toLowerCase();
  const c = candidate.trim().toLowerCase();
  if (!c) return "length";

  // SCRIPT. An English answer written in Cyrillic, or a Kazakh/Russian answer
  // written in Latin, is by definition not a translation into that language.
  if (to === "en" && hasCyrillic(c)) return "script";
  if (to !== "en" && !hasCyrillic(c)) return "script";

  // IDENTITY. Answering with the question is not an answer. Compared after
  // stripping everything but letters so spacing and punctuation cannot hide it.
  const bare = (x: string) => x.replace(/[^\p{L}]/gu, "");
  if (bare(s) === bare(c)) return "identity";

  // TRANSLITERATION, forwards: a Cyrillic term answered with its own Latin
  // respelling. This is "шаңырақ" → "shangri-la".
  if (to === "en" && hasCyrillic(s) && translitScore(s, c) >= TRANSLIT_LIMIT) {
    return "translit";
  }

  // TRANSLITERATION, backwards: a Latin term answered with its own Cyrillic
  // respelling — "shangri-la" → "шангри-ла", which the forward test cannot
  // see because neither string is where it expects it.
  if (to !== "en" && hasLatin(s) && translitScore(c, s) >= TRANSLIT_LIMIT) {
    return "translit";
  }

  // Deliberately NOT refused: a Kazakh word answered in Russian with the same
  // word respelled. Russian really does borrow "домбыра" as "домбра" and
  // "тұсаукесер" as "тусаукесер", so that shape is a correct translation as
  // often as it is a lazy one. The English side is where the dictionary is
  // actually protected, and it is checked above.

  // LENGTH. A one-word term does not translate into a sentence, and nothing
  // here should be five times the length of what was asked.
  const words = s.split(/\s+/).length;
  if (words === 1 && c.split(/\s+/).length > 4) return "length";
  if (c.length > Math.max(48, s.length * 5)) return "length";

  return null;
}

/// Records what the gate refused, so the review queue has something to review
/// and a repeatedly-failing word is visible rather than merely absent.
///
/// Uses the SERVICE client, not the caller's: the RLS policy on
/// `translation_reports` is moderator-only, so under a learner's own token
/// every insert was silently refused and the table stayed empty.
/// Never allowed to break a request.
async function reportRejection(
  admin: SupabaseClient | null,
  term: string,
  candidate: string,
  failed: GateFail,
  to: string,
  provider: string,
) {
  if (!admin) return;
  try {
    await admin.from("translation_reports").insert({
      term,
      source_lang: detectLang(term),
      target_lang: to,
      candidate,
      failed_check: failed,
      provider,
    });
  } catch {
    // the table may not exist yet; the rejection still stands
  }
}

/// The source language of a typed term. Kazakh-only letters settle it at
/// once; otherwise Cyrillic is assumed Russian and corrected later if the
/// translation comes back unchanged.
function detectLang(t: string): "en" | "kk" | "ru" {
  if (!hasCyrillic(t)) return "en";
  return isKazakhOnly(t) ? "kk" : "ru";
}

/// Builds a plain en/kk/ru triple without any LLM. The two directions that do
/// not depend on each other run together — sequentially this was three
/// round trips where two would do.
async function basicEntry(term: string) {
  const t = term.trim();
  if (!t) return null;

  let en = "";
  let src = detectLang(t);

  if (src === "en") {
    en = t;
  } else {
    en = await freeTranslate(t, src, "en");
    // A Kazakh word with no Kazakh-only letters looks Russian. If Russian did
    // not move it, try again as Kazakh (and the other way round).
    if (!en) {
      const other = src === "kk" ? "ru" : "kk";
      en = await freeTranslate(t, other, "en");
      if (en) src = other;
    }
    if (!en) return null;
  }

  const [kk, ru] = await Promise.all([
    src === "kk" ? Promise.resolve(t) : freeTranslate(en, "en", "kk"),
    src === "ru" ? Promise.resolve(t) : freeTranslate(en, "en", "ru"),
  ]);

  if (!en || !kk) return null;
  return {
    en: en.toLowerCase(),
    kk: kk.toLowerCase(),
    ru: ru ? ru.toLowerCase() : null,
    pos: null,
    definition_en: null,
    synonyms: [] as string[],
    antonyms: [] as string[],
    example_en: null,
    example_kk: null,
    ipa: null,
    emoji: null,
    cefr: "A2",
    topic: "general",
    source: "basic",
  };
}

// ── helpers ────────────────────────────────────────────────

function extractJson(raw: string): string {
  const s = raw.trim().replace(/```json/gi, "").replace(/```/g, "").trim();
  const o = s.indexOf("{");
  const a = s.indexOf("[");
  if (o === -1 && a === -1) return s;
  const useObj = a === -1 || (o !== -1 && o < a);
  const start = useObj ? o : a;
  const end = s.lastIndexOf(useObj ? "}" : "]");
  return end > start ? s.slice(start, end + 1) : s;
}

function parseJson(raw: string) {
  try {
    return JSON.parse(extractJson(raw));
  } catch {
    throw new Error(MSG.unreadable.kk);
  }
}

const CEFR = ["A0", "A1", "A2", "B1", "B2", "C1"];
const clean = (v: unknown) => (typeof v === "string" ? v.trim() : "");
const arr = (v: unknown) =>
  Array.isArray(v) ? v.filter((x) => typeof x === "string" && x.trim()).slice(0, 6) : [];

const norm = (v: unknown) =>
  clean(v).toLowerCase().replace(/\s+/g, " ").replace(/^to /, "");

type Entry = Record<string, unknown>;

/// Whether a dictionary row can be handed to a learner as it stands.
///
/// The requirement is explicit: use the stored row only when the English, the
/// Kazakh, the Russian, the English meaning, the synonyms AND the example
/// sentence are all there. Anything less and the AI fills the gaps — an
/// entry with a blank meaning is what made people type it in by hand.
function isComplete(e: Entry | null | undefined): boolean {
  if (!e) return false;
  return clean(e.en) !== "" &&
    clean(e.kk) !== "" &&
    clean(e.ru) !== "" &&
    clean(e.definition_en) !== "" &&
    clean(e.example_en) !== "" &&
    arr(e.synonyms).length >= 2;
}

/// `dict_lookup` has an exact branch and a fuzzy one (similarity >= 0.45) and
/// does not say which answered, so a merely SIMILAR row used to be served as
/// though it were the word. This is that missing distinction.
function isExactMatch(e: Entry, term: string): boolean {
  const t = norm(term);
  return norm(e.en) === t || norm(e.kk) === t || norm(e.ru) === t;
}

const TRANSLATE_FIELDS =
  `  en            - the English form (for verbs use the "to X" infinitive)\n` +
  `  kk            - the Kazakh form\n` +
  `  ru            - the Russian form\n` +
  `  pos           - one of: noun, verb, adjective, adverb, phrase, other\n` +
  `  definition_en - a short English definition (max 15 words)\n` +
  `  synonyms      - array of 2-4 English synonyms\n` +
  `  antonyms      - array of 0-2 English antonyms\n` +
  `  example_en    - one natural English example sentence\n` +
  `  example_kk    - the Kazakh translation of that sentence\n` +
  `  ipa           - IPA transcription of the English form\n` +
  `  emoji         - one relevant emoji\n` +
  `  cefr          - one of A0, A1, A2, B1, B2, C1\n` +
  `  topic         - one of: general, food, travel, family, body, home, school, ` +
  `work, nature, animals, tech, emotions, sport, time, city, money, health, communication`;

/// The prompt says out loud what the gate enforces. Models that respell a
/// word usually do it because nothing told them not to.
const translatePrompt = (term: string) =>
  `You are a Kazakh<->English lexicographer for a vocabulary app.\n` +
  `Input term: "${term}"\n` +
  `Detect the language and produce BOTH sides.\n` +
  `IMPORTANT: writing the term in Latin letters (a romanisation such as\n` +
  `"shanyraq" for "шаңырақ") is NOT a translation and is never acceptable.\n` +
  `Give the real meaning. If you genuinely do not know the word, set en to "".\n` +
  `Return ONLY a raw JSON object, no markdown, with exactly these fields:\n` +
  TRANSLATE_FIELDS;

/// The second opinion, asked as a narrow question so its answer is cheap and
/// hard to misread.
const secondPrompt = (term: string) =>
  `What does the word "${term}" mean in English?\n` +
  `Answer with the meaning, never with the word rewritten in Latin letters.\n` +
  `Return ONLY {"en":"..."}. If you do not know it, return {"en":""}.`;

/// The tie-breaker. Two models disagreeing is not evidence that either is
/// wrong -- "шаңырақ" is honestly both "yurt crown" and "home", and the old
/// code refused the word outright for it, which is the "Аударма табылмады"
/// dead end. A third model decides instead.
const arbiterPrompt = (term: string, a: string, b: string) =>
  `Two translators disagree about the word "${term}".
` +
  `One says it means "${a}". The other says "${b}".
` +
  `Which is right? If neither is, give the correct English meaning yourself.
` +
  `A romanisation of the term in Latin letters is never a valid answer.
` +
  `Return ONLY {"en":"..."}.`;

/// The one question the transliteration test cannot answer for itself.
///
/// "shamshyraq" for "шамшырақ" is a respelling and must be refused. "dombra"
/// for "домбыра" is ALSO a respelling -- and it is the correct English word,
/// because English borrowed the instrument along with its name. Structurally
/// the two are identical: same script, same length, same near-perfect
/// romanisation score. Nothing about the strings tells them apart.
///
/// What does tell them apart is whether English actually has the word, so
/// that is what gets asked, and only on the candidates the gate stopped.
/// A "no" has to come with the real meaning, so a refusal still teaches the
/// learner something instead of being a dead end.
const loanwordPrompt = (term: string, candidate: string) =>
  `Is "${candidate}" a real English word that appears in English dictionaries,
` +
  `or is it merely the Kazakh word "${term}" rewritten in Latin letters?
` +
  `Words like "dombra", "yurt" and "kumis" ARE real English borrowings.
` +
  `A spelling invented on the spot is not.
` +
  `Think about what "${term}" actually MEANS before you answer.
` +
  `Return ONLY {"real": true or false, "en": "the correct English meaning if it is not real"}.`;

const enrichPrompt = (en: string, kk: string) =>
  `For the English word "${en}" (Kazakh: "${kk}") return ONLY raw JSON with fields:\n` +
  `  definition_en - short English definition (max 15 words)\n` +
  `  synonyms      - array of 3-4 English synonyms\n` +
  `  antonyms      - array of 0-2 English antonyms\n` +
  `  example_en    - one natural example sentence using the word\n` +
  `  example_kk    - the Kazakh translation of that sentence\n` +
  `  ipa           - IPA transcription\n` +
  `  emoji         - one relevant emoji\n` +
  `  cefr          - one of A0, A1, A2, B1, B2, C1`;

/// Fills whatever a row is still missing, in one request, and never fails the
/// caller: a partial entry is better than an error.
async function fillGaps(entry: Entry): Promise<Entry> {
  if (isComplete(entry)) return entry;
  // Nothing to fill the gaps WITH. Walking the chain again to rediscover that
  // is six seconds spent on a foregone conclusion.
  if (chain("", 0, 0, false).every(
        (a) => (cooldownUntil.get(a.id.split("/")[0]) ?? 0) > Date.now())) {
    return entry;
  }
  const en = clean(entry.en), kk = clean(entry.kk);
  if (!en) return entry;
  try {
    const extra = parseJson(await complete(enrichPrompt(en, kk), 0.25, 700)) as Entry;
    const keep = (k: string, v: unknown) =>
      clean(entry[k]) !== "" ? entry[k] : (clean(v) !== "" ? clean(v) : entry[k]);
    return {
      ...entry,
      definition_en: keep("definition_en", extra.definition_en),
      example_en: keep("example_en", extra.example_en),
      example_kk: keep("example_kk", extra.example_kk),
      ipa: keep("ipa", extra.ipa),
      emoji: keep("emoji", extra.emoji),
      cefr: CEFR.includes(clean(entry.cefr))
        ? entry.cefr
        : (CEFR.includes(clean(extra.cefr)) ? clean(extra.cefr) : "A2"),
      synonyms: arr(entry.synonyms).length >= 2 ? arr(entry.synonyms) : arr(extra.synonyms),
      antonyms: arr(entry.antonyms).length > 0 ? arr(entry.antonyms) : arr(extra.antonyms),
    };
  } catch {
    return entry;
  }
}

/// One place that writes a dictionary row, always under the service key.
async function saveEntry(admin: SupabaseClient | null, e: Entry, source: string) {
  if (!admin) return null;
  const { data, error } = await admin.rpc("dict_upsert", {
    p_en: clean(e.en),
    p_kk: clean(e.kk),
    p_ru: clean(e.ru) || null,
    p_pos: clean(e.pos) || null,
    p_definition_en: clean(e.definition_en) || null,
    p_synonyms: arr(e.synonyms),
    p_antonyms: arr(e.antonyms),
    p_example_en: clean(e.example_en) || null,
    p_example_kk: clean(e.example_kk) || null,
    p_ipa: clean(e.ipa) || null,
    p_emoji: clean(e.emoji) || null,
    p_cefr: CEFR.includes(clean(e.cefr)) ? clean(e.cefr) : "A2",
    p_topic: clean(e.topic) || "general",
    p_source: source,
  });
  return error ? null : data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const ok = (body: unknown) =>
    new Response(JSON.stringify(body), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  const fail = (msg: string, status = 400) =>
    new Response(JSON.stringify({ error: msg }), {
      status,
      headers: { ...CORS, "Content-Type": "application/json" },
    });

  let lang: Lang = "kk";

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    // Writes go through this one. dict_upsert is revoked from `authenticated`
    // and translation_reports is moderator-only under RLS, so without it the
    // dictionary silently stops growing and the review queue stays empty.
    const admin: SupabaseClient | null = SERVICE_KEY
      ? createClient(Deno.env.get("SUPABASE_URL")!, SERVICE_KEY)
      : null;

    const body = await req.json().catch(() => ({}));
    lang = clean(body.lang) === "ru" ? "ru" : "kk";

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return fail(say("auth", lang), 401);

    const task = clean(body.task) || "translate";

    // health: which keys are configured (never their values). Live provider
    // probing lives in the separate `ai-probe` function.
    if (task === "health") {
      return ok({
        gemini: HAS_GEMINI,
        gemini_keys: GEMINI_KEYS.length,
        gemini_models: HAS_GEMINI ? GEMINI_MODELS : null,
        openrouter: OPENROUTER_KEY.length > 0,
        service_key: SERVICE_KEY.length > 0,
        order: chain("", 0, 0, true).map((a) => a.id),
        cooling: Object.fromEntries(
          [...cooldownUntil.entries()]
            .filter(([, t]) => t > Date.now())
            .map(([v, t]) => [v, Math.round((t - Date.now()) / 1000)]),
        ),
      });
    }

    // ── translate ────────────────────────────────────────────
    //
    //   1. the shared dictionary, but only an EXACT row that is COMPLETE
    //   2. two models at once — one full entry, one second opinion
    //   3. the gate, then agreement, then a third model to break a tie
    //   4. whatever is still blank gets filled
    //   5. the keyless services, if every model is spent
    if (task === "translate") {
      const term = clean(body.text);
      if (!term) return fail(say("empty", lang));

      const srcLang = detectLang(term);
      const target: "en" | "kk" | "ru" = srcLang === "en" ? "kk" : "en";

      // 1. Cache. Only an exact hit counts — dict_lookup also returns rows
      // that merely resemble the term — and only a complete one is returned
      // as-is. An incomplete row is kept and filled in rather than discarded,
      // so a half-written entry improves instead of staying half-written.
      let partial: Entry | null = null;
      const { data: cached } = await supabase.rpc("dict_lookup", { p_term: term });
      if (Array.isArray(cached)) {
        const exact = (cached as Entry[]).find((r) => isExactMatch(r, term));
        if (exact) {
          // A row the ungated version already poisoned must not be served for
          // ever just because it is stored.
          //
          // A VERIFIED row is different: somebody wrote it on purpose. The
          // gate cannot tell "baursak" for "бауырсақ" from an invented
          // respelling — that is the whole reason the loanword check exists —
          // so applying it to a hand-written row threw away the one source
          // that is allowed to just know the answer, and sent the word back
          // to the model that gets it wrong.
          const stored = target === "en" ? clean(exact.en) : clean(exact.kk);
          const rot = (srcLang === "en" || exact.verified === true)
            ? null
            : gate(term, stored, target);
          if (rot !== null) {
            await reportRejection(admin, term, stored, rot, target, "cache");
          } else if (isComplete(exact)) {
            return ok({ source: "cache", entry: exact });
          } else {
            partial = exact;
          }
        }
      }

      // 2. Two models, at the same time. The second opinion used to be a
      // whole extra round trip AFTER the first answer; asked in parallel it
      // is free in wall-clock terms.
      const primaryChain = chain(translatePrompt(term), 0.2, 1024, true);
      const first = withDeadline(completeFrom(primaryChain), TRANSLATE_DEADLINE);
      // A different MODEL, not merely the next attempt in the list — with
      // several keys configured the next attempt is the same model behind a
      // different key, and asking one model twice is not a second opinion.
      const secondChain = chain(secondPrompt(term), 0.1, 400, true);
      const firstModel = secondChain[0]?.id.split("/")[1] ?? "";
      const otherModels = secondChain.filter(
        (a) => a.id.split("/")[1] !== firstModel);
      const second = otherModels.length > 0
        ? withDeadline(completeFrom(otherModels).catch(() => null), SECOND_DEADLINE)
        : Promise.resolve(null);

      let parsed: Entry | null = null;
      let usedModel = "";
      let llmError = "";
      try {
        const r = await first;
        if (r === null) throw new Error(`timeout ${TRANSLATE_DEADLINE}ms`);
        usedModel = r.model;
        parsed = parseJson(r.text) as Entry;
      } catch (e) {
        llmError = e instanceof Error ? e.message : String(e);
      }
      const secondRes = await second;

      const en = clean(parsed?.en);
      const kk = clean(parsed?.kk);

      // Every model is out of quota (or the answer was unusable) — fall back
      // to a plain dictionary-grade translation so the learner is never stuck,
      // and fill it in rather than handing over an empty form.
      if (!en || !kk) {
        if (partial) {
          const filled = await fillGaps(partial);
          await saveEntry(admin, filled, clean(partial.source) || "ai");
          return ok({ source: "cache", entry: filled, note: llmError });
        }
        const basic = await withDeadline(basicEntry(term), BASIC_DEADLINE);
        if (basic) {
          const filled = await fillGaps(basic as Entry);
          const saved = isComplete(filled) ? await saveEntry(admin, filled, "basic") : null;
          return ok({
            source: isComplete(filled) ? "ai" : "basic",
            entry: saved ?? filled,
            note: llmError,
          });
        }
        if (llmError.includes(NO_KEY_MSG)) return fail(say("noKey", lang), 503);
        if (llmError.includes(RATE_MSG)) return fail(say("rate", lang), 429);
        return fail(llmError || say("noTranslation", lang), llmError ? 429 : 400);
      }

      // 3. The gate, before anything is written. This answer is about to
      // become the shared dictionary's answer for everybody.
      const candidate = target === "en" ? en : kk;
      let failed = gate(term, candidate, target);

      // A "translit" verdict is the one the gate can get wrong in the
      // learner's favour as well as against them, so it is the one verdict
      // worth a second look. Everything else stands.
      if (failed === "translit" && target === "en") {
        try {
          const check = await withDeadline(
            completeFrom(chain(loanwordPrompt(term, candidate), 0.1, 300, true)),
            ARBITER_DEADLINE,
          );
          if (check !== null) {
            const j = parseJson(check.text) as Entry;
            const better = clean(j?.en);
            // The real meaning outranks the verdict: if it named one, take it
            // even when it also claimed the romanisation was a real word.
            if (better && gate(term, better, "en") === null) {
              parsed = { ...parsed, en: better };
              failed = null;
            } else if (j?.real === true) {
              failed = null;                    // a genuine borrowing
            }
          }
        } catch {
          // No answer means the gate's verdict stands, which is the safe way
          // round: a refused word is a gap, a wrong word is a lie.
        }
      }

      if (failed !== null) {
        await reportRejection(admin, term, candidate, failed, target, usedModel);
        return ok({
          source: "rejected",
          reason: failed,
          entry: null,
          message: say("noTranslation", lang),
        });
      }
      const finalEn = clean(parsed?.en) || en;
      // The Russian side was never gated at all, which is how "шангри-ла"
      // was going to be stored next to "shangri-la".
      const ru = clean(parsed?.ru);
      const ruBad = ru && srcLang !== "ru" ? gate(term, ru, "ru") : null;

      // Agreement. An empty or missing second answer is an abstention, not a
      // contradiction — one model not knowing a word is not evidence the
      // other is wrong.
      let agreed = true;
      let otherEn = "";
      if (secondRes) {
        try {
          otherEn = clean((parseJson(secondRes.text) as Entry).en).toLowerCase();
        } catch { /* unusable second opinion is an abstention too */ }
      }
      if (otherEn && target === "en") {
        const a = otherEn.replace(/[^a-z]/g, "");
        const b = finalEn.toLowerCase().replace(/[^a-z]/g, "");
        // Either the same word, or one contains the other — models answer
        // "lighthouse" and "lighthouse, beacon" for the same term.
        agreed = similarity(a, b) >= 0.6 || a.includes(b) || b.includes(a);
      }

      // A disagreement is a question, not a verdict. Ask a third model which
      // of the two is right; whichever it backs is the one that gets
      // published. Only a candidate that fails the STRUCTURAL gate is ever
      // refused outright -- that is the transliteration case, and it is the
      // only one where the honest answer is that there is no answer.
      let publishable = true;
      if (!agreed) {
        await reportRejection(admin, term, `${finalEn} / ${otherEn}`, "disagree", target, usedModel);
        publishable = false;
        try {
          const verdict = await withDeadline(
            completeFrom(
              chain(arbiterPrompt(term, finalEn, otherEn), 0.1, 300, true),
              new Set([usedModel]),
            ),
            ARBITER_DEADLINE,
          );
          if (verdict === null) throw new Error("arbiter timeout");
          const pick = clean((parseJson(verdict.text) as Entry).en);
          if (pick && gate(term, pick, "en") === null) {
            const flat = (x: string) => x.toLowerCase().replace(/[^a-z]/g, "");
            const backsPrimary = similarity(flat(pick), flat(finalEn)) >= 0.6 ||
              flat(pick).includes(flat(finalEn)) || flat(finalEn).includes(flat(pick));
            if (!backsPrimary) {
              // The arbiter named a different word; that word is the answer.
              parsed = { ...parsed, en: pick };
            }
            publishable = true;
          }
        } catch {
          // No arbiter available. The answer still passed the structural
          // gate, so the learner gets it -- it simply does not go into the
          // dictionary everybody shares on one model's word alone.
        }
      }

      // 4. Fill whatever is blank, merging anything the stored row already
      // had — a moderator's correction outranks a fresh model answer.
      let entry: Entry = {
        ...parsed,
        en: clean(parsed?.en) || finalEn,
        kk,
        ru: ruBad === null ? ru : "",
      };
      if (partial) {
        for (const k of Object.keys(partial)) {
          const v = partial[k];
          if (k === "synonyms" || k === "antonyms") {
            if (arr(v).length >= 2) entry[k] = arr(v);
          } else if (clean(v) !== "" && partial.verified === true) {
            entry[k] = v;
          }
        }
      }
      entry = await fillGaps(entry);

      // Unendorsed answers are shown but not stored. The learner is not left
      // empty-handed, and one model's guess does not become everybody's
      // dictionary entry.
      const saved = publishable ? await saveEntry(admin, entry, "ai") : null;
      return ok({
        source: publishable ? "ai" : "unverified",
        model: usedModel,
        entry: saved && typeof saved === "object"
          ? { ...(saved as Entry), ru: clean(entry.ru) || (saved as Entry).ru }
          : entry,
      });
    }

    // ── enrich: fill definition/synonyms for a word already owned ──
    if (task === "enrich") {
      const en = clean(body.en);
      const kk = clean(body.kk);
      if (!en) return fail(say("empty", lang));
      return ok({ entry: parseJson(await complete(enrichPrompt(en, kk), 0.25, 700)) });
    }

    // ── suggest: new words at the learner's level ──
    //
    // This one must never come back empty. "Жаңа сөз табылмады, кейінірек
    // көр" was what a learner saw whenever every model was busy — with a
    // dictionary of hundreds of rows sitting right there, unread.
    if (task === "suggest") {
      const cefr = CEFR.includes(clean(body.cefr)) ? clean(body.cefr) : "A2";
      const topic = clean(body.topic) || "general";
      const count = Math.min(Math.max(Number(body.count) || 8, 1), 20);
      const excludeList = (Array.isArray(body.exclude) ? body.exclude : [])
        .filter((x: unknown) => typeof x === "string")
        .map((x: string) => x.trim().toLowerCase())
        .filter(Boolean);
      const known = excludeList.slice(0, 60).join(", ");

      const prompt =
        `Suggest exactly ${count} English words at CEFR level ${cefr}, topic "${topic}",\n` +
        `useful for a Kazakh speaker learning English.\n` +
        `Avoid these words: ${known || "none"}.\n` +
        `Return ONLY a raw JSON array; each item has:\n` +
        `  en, kk, pos, definition_en, synonyms (array of 2-3), example_en, emoji, cefr, topic`;

      // trustedOnly, like translate, and for the same reason: every item here
      // goes through dict_upsert into the dictionary everyone shares. The
      // free models answered "hotel" with "гостиница" and "airport" with the
      // misspelled "ауэжай".
      let list: unknown = null;
      let note = "";
      try {
        list = parseJson(await complete(prompt, 0.75, 2048, true));
      } catch (e) {
        note = e instanceof Error ? e.message : String(e);
      }

      const saved: unknown[] = [];
      const takenEn = new Set(excludeList);
      if (Array.isArray(list)) {
        for (const it of (list as Entry[]).slice(0, count)) {
          const en = clean(it?.en), kk = clean(it?.kk);
          if (!en || !kk) continue;
          if (takenEn.has(en.toLowerCase())) continue;
          // The same gate as translate: a suggestion is written to the shared
          // dictionary too, so it gets the same scrutiny.
          if (gate(kk, en, "en") !== null) continue;
          takenEn.add(en.toLowerCase());
          const row = await saveEntry(admin, it, "ai");
          if (row) saved.push(row);
          else saved.push({ ...it, synonyms: arr(it.synonyms), source: "ai" });
        }
      }

      // The floor. Whatever the models did, the dictionary already holds
      // words at this level that this learner has never seen, and reading
      // them costs one query and no quota.
      if (saved.length < count) {
        try {
          const { data: pool } = await supabase.rpc("dict_discover", {
            p_cefr: cefr,
            p_topic: topic,
            p_exclude: Array.from(takenEn),
            p_limit: count - saved.length,
          });
          if (Array.isArray(pool)) {
            for (const row of pool as Entry[]) {
              if (takenEn.has(clean(row.en).toLowerCase())) continue;
              takenEn.add(clean(row.en).toLowerCase());
              saved.push(row);
            }
          }
        } catch (e) {
          note = note || String(e);
        }
      }

      if (saved.length === 0 && note) {
        if (note.includes(NO_KEY_MSG)) return fail(say("noKey", lang), 503);
        if (note.includes(RATE_MSG)) return fail(say("rate", lang), 429);
        return fail(note, 429);
      }
      return ok({ entries: saved, note: note || undefined });
    }

    // ── chat: one turn of a role-play conversation ──
    if (task === "chat") {
      const message = clean(body.message);
      if (!message) return fail(say("empty", lang));

      const scenario = clean(body.scenario) || "Кофеханада";
      const cefr = CEFR.includes(clean(body.cefr)) ? clean(body.cefr) : "A2";
      const learnerLang = studyLang(body.study_lang, lang);
      const history = (Array.isArray(body.history) ? body.history : [])
        .filter((x: unknown) => typeof x === "string")
        .slice(-8);

      const prompt =
        `You are a friendly English conversation partner in a role-play.\n` +
        `Scene: ${sceneEn(scenario)}.\n` +
        `The learner is a ${LANG_NAME[learnerLang]} speaker at CEFR level ${cefr}.\n` +
        (history.length ? `Conversation so far:\n${history.join("\n")}\n` : "") +
        `The learner just said: "${message}"\n\n` +
        `Reply in English only, staying in character. Rules:\n` +
        `  - 1 to 2 short sentences, vocabulary at ${cefr} level\n` +
        `  - answer what they actually said, do not change the subject\n` +
        `  - always end with a simple question so they can keep talking\n` +
        `  - no markdown, no quotes, no translation, no explanation`;

      return ok({ text: (await complete(prompt, 0.7, 700)).trim() });
    }

    // ── explain: teach a word in the learner's language ──
    if (task === "explain") {
      const en = clean(body.en);
      if (!en) return fail(say("empty", lang));
      const learnerLang = studyLang(body.study_lang, lang);
      const prompt =
        `Explain the English word "${en}" to a ${LANG_NAME[learnerLang]}-speaking learner.\n` +
        `Write in ${LANG_NAME[learnerLang]}, warm and simple, 3-5 short sentences.\n` +
        `Cover: what it means, when to use it, one common mistake, and one memory hook.\n` +
        `Plain text only, no markdown.`;
      return ok({ text: await complete(prompt, 0.5, 1400) });
    }

    if (task === "raw") {
      const prompt = clean(body.prompt);
      if (!prompt) return fail(say("empty", lang));
      return ok({ text: await complete(prompt, Number(body.temperature) || 0.4, 2048) });
    }

    return fail(`${say("unknownTask", lang)}: ${task}`);
  } catch (e) {
    const raw = e instanceof Error ? e.message : String(e);
    const rate = raw.includes(RATE_MSG);
    const noKey = raw.includes(NO_KEY_MSG);
    // Only the two messages a learner is meant to read get translated; the
    // rest is a transport error kept verbatim for debugging.
    const msg = rate ? say("rate", lang) : noKey ? say("noKey", lang) : raw;
    return new Response(JSON.stringify({ error: msg }), {
      status: rate ? 429 : noKey ? 503 : 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
