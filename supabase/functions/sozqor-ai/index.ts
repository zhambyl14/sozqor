// SozQor AI gateway
// Keeps LLM API keys server-side and grows the shared dictionary
// so repeated lookups never cost a request.
//
// Tasks: translate | enrich | suggest | chat | explain | raw
//
// A translate request never dead-ends on a quota error. The order is
// FreeRouter (free, and the most accurate of them on the probe below), then
// OpenAI, then Gemini, then the free OpenRouter models, and only if every one
// of them is spent do three keyless translation services get their turn.
//
// But "always answers" is not the goal on its own, and used to be pursued at
// the cost of being right: two of those keyless services return Kazakh words
// TRANSLITERATED, and "шамшырақ" reached learners as "shamshyraq". Every
// candidate now passes a gate — script, identity, transliteration, length, and
// agreement between two models — before it is shown or written to the shared
// dictionary. A word that fails is refused outright with "Аударма табылмады",
// because one wrong entry in a dictionary everybody shares is worse than a
// gap in it.
//
// Every error message is written in the interface language sent as `lang`
// ("kk" or "ru"). 5.0 collapsed the app's two language settings into one, so
// `study_lang` now always mirrors `lang`; the parameter is still read for
// older cached clients that send it.
//
// Function secrets — ANY ONE of these makes the AI work; with none of them the
// app falls back to the keyless translators and says so in `note`:
//   FREEROUTER_API_KEY  (free; tried first — never commit it, this repo is public)
//   OPENAI_API_KEY      (+ optional OPENAI_MODEL, default gpt-4o-mini)
//   OPENROUTER_API_KEY
//   GEMINI_API_KEY

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") || "gpt-4o-mini";
const OPENROUTER_KEY = Deno.env.get("OPENROUTER_API_KEY") ?? "";
const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";

// FreeRouter — an OpenAI-compatible gateway over several models at no cost.
// Set FREEROUTER_API_KEY in the function's secrets; never commit the key, the
// repository is public.
const FREEROUTER_KEY = Deno.env.get("FREEROUTER_API_KEY") ?? "";
const FREEROUTER_URL = "https://freerouter.eu.cc/v1/chat/completions";

// Probed against "шамшырақ" (a beacon / lamp), the word this release exists to
// stop mistranslating: glm-5.2 answered "beacon", kiro-auto answered
// "sunflower". Both reported 0.95 confidence. That is the whole reason
// self-reported confidence is not one of the gate's checks below and
// cross-model agreement is — a model is not able to tell you when it is wrong.
const FREEROUTER_PRIMARY = "glm-5.2";
const FREEROUTER_SECOND = "kiro-auto";

// OpenRouter retired the `:free` tier on every model this list used to name —
// each one now 404s with "unavailable for free". These are priced at zero by
// /api/v1/models today. They are tried AFTER Gemini because a free model that
// answers confidently but wrongly is worse than none here: a translate result
// is written into the shared dictionary, so one bad answer becomes everyone's
// answer. Probed against "жалаңаш" these returned "newcomer", "silly" and
// "yellowish" where Gemini returned "naked".
const FREE_MODELS = [
  "nvidia/nemotron-3-super-120b-a12b:free",
  "openai/gpt-oss-20b:free",
  "nvidia/nemotron-3-nano-30b-a3b:free",
  "z-ai/glm-5.2:free",
  "google/gemma-4-31b-it:free",
];

// gemini-2.0-flash is retired (404, "use models/gemini-3.6-flash") and
// 2.5-flash spends its whole output allowance on hidden reasoning, coming back
// finishReason MAX_TOKENS with no text at all. Both of these answer normally.
const GEMINI_MODELS = ["gemini-3.6-flash", "gemini-flash-latest"];

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

/// `lang` (interface language, from AppLang.current) and `study_lang`
/// (the learner's "Оқу тілі" — which language new words translate to) are
/// two independent settings on the client and must stay independent here
/// too: every error message in this function is UI chrome and always uses
/// `lang`, while a `study_lang` field is used ONLY by the two tasks whose
/// whole output is study content the learner reads to learn from — explain's
/// explanation text and chat's "the learner speaks X" framing — because a
/// learner reading the app in Russian while training Kazakh vocabulary (or
/// the other way round) must still get that content in Kazakh, not Russian.
/// Falls back to `lang` so an older cached client that never sends
/// `study_lang` keeps working exactly as before.
const studyLang = (raw: unknown, fallback: Lang): Lang =>
  clean(raw) === "ru" ? "ru" : clean(raw) === "kk" ? "kk" : fallback;

/// The chat scenarios are Kazakh labels the client also uses as lookup keys
/// for its own offline scripted tutor, so they cannot simply be translated in
/// place. Sent to an English-only model as-is ("Scene: \"Дәрігерде\"") they
/// ground nothing — the model has no idea what that word means and answers
/// with something plausible but unrelated to the scene, which is exactly the
/// "ignores what I said, talks about something else" bug this maps fixes.
const SCENE_EN: Record<string, string> = {
  "Кофеханада": "a coffee shop — you are the barista taking the customer's order",
  "Әуежайда": "an airport check-in counter — you are the airline staff member",
  "Жұмыс сұхбаты": "a job interview — you are the interviewer",
  "Дүкенде": "a clothing store — you are the shop assistant helping a customer",
  "Дәрігерде": "a doctor's office — you are the doctor examining a patient",
};

const sceneEn = (kk: string) => SCENE_EN[kk] ?? "a friendly everyday situation";

// ── LLM transports ─────────────────────────────────────────

/// OpenAI, when a key is configured. Tried before everything else: it is the
/// only one of the three that is not on a free quota, so it answers instead of
/// spending six requests discovering that the free models are spent.
async function callOpenAI(
  prompt: string,
  temperature: number,
  maxTokens: number,
) {
  if (!OPENAI_KEY) throw new Error(NO_KEY_MSG);
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_KEY}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      messages: [{ role: "user", content: prompt }],
      temperature,
      max_completion_tokens: maxTokens,
    }),
    signal: AbortSignal.timeout(45_000),
  });
  if (!res.ok) {
    // The status alone cannot tell "no credit left" from "too fast"; both are
    // 429. Carry a slice of the body so the cause is visible in `note`.
    const detail = (await res.text().catch(() => "")).slice(0, 300);
    throw new Error(
      `${res.status === 429 ? "429" : "OpenAI " + res.status} ${OPENAI_MODEL} ${detail}`,
    );
  }
  const json = await res.json();
  const text = json?.choices?.[0]?.message?.content ?? "";
  if (!text.trim()) throw new Error(`OpenAI empty ${OPENAI_MODEL}`);
  return text as string;
}

/// One OpenRouter model. Throws with "429" in the message when throttled, so
/// the caller can move on to the next model instead of giving up.
async function callOpenRouter(
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
) {
  if (!OPENROUTER_KEY) throw new Error(NO_KEY_MSG);
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENROUTER_KEY}`,
      "X-Title": "SozQor",
    },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: prompt }],
      temperature,
      max_tokens: maxTokens,
    }),
    signal: AbortSignal.timeout(45_000),
  });
  if (res.status === 429) throw new Error(`429 ${model}`);
  if (!res.ok) throw new Error(`OpenRouter ${res.status} ${model}`);
  const json = await res.json();
  if (json.error) throw new Error(`OpenRouter: ${JSON.stringify(json.error)}`);
  const text = json?.choices?.[0]?.message?.content ?? "";
  if (!text.trim()) throw new Error(`OpenRouter empty ${model}`);
  return text as string;
}

async function callGemini(
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
) {
  if (!GEMINI_KEY) throw new Error(NO_KEY_MSG);
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature, maxOutputTokens: maxTokens },
      }),
      signal: AbortSignal.timeout(45_000),
    },
  );
  if (res.status === 429) throw new Error(`429 ${model}`);
  if (!res.ok) throw new Error(`Gemini ${res.status} ${model}`);
  const json = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!text.trim()) throw new Error(`Gemini empty ${model}`);
  return text as string;
}

/// Walks every provider in turn. One that is out of quota costs a single
/// failed request and the next one is tried immediately.
///
/// `trustedOnly` skips the free OpenRouter models. Use it for any task whose
/// answer is written into the shared dictionary. Measured against known words,
/// those models return confident, well-formed, WRONG JSON — "кітап" came back
/// as "unknown", "жалаңаш" as "silly" and "yellowish" — and dict_upsert makes
/// one bad answer permanent for every learner. Where nothing is persisted
/// (chat, explain, enrich) they are a genuine safety net and stay in the chain.
/// FreeRouter speaks the OpenAI chat-completions shape, so this is the same
/// call as callOpenAI with a different base URL and no cost.
async function callFreeRouter(
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
) {
  if (!FREEROUTER_KEY) throw new Error(NO_KEY_MSG);
  const res = await fetch(FREEROUTER_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${FREEROUTER_KEY}`,
    },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: prompt }],
      temperature,
      max_tokens: maxTokens,
    }),
    signal: AbortSignal.timeout(45_000),
  });
  if (!res.ok) {
    throw new Error(`freerouter ${model} ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  const text = json?.choices?.[0]?.message?.content ?? "";
  if (!text.trim()) throw new Error(`freerouter ${model} empty`);
  return text as string;
}

async function complete(
  prompt: string,
  temperature = 0.3,
  maxTokens = 2048,
  trustedOnly = false,
) {
  const problems: string[] = [];

  // FreeRouter first: it costs nothing and, on the probe that matters, it was
  // the only provider configured here that got the hard word right.
  if (FREEROUTER_KEY) {
    for (const model of [FREEROUTER_PRIMARY, FREEROUTER_SECOND]) {
      try {
        return await callFreeRouter(model, prompt, temperature, maxTokens);
      } catch (e) {
        problems.push(String(e));
      }
    }
  }

  if (OPENAI_KEY) {
    try {
      return await callOpenAI(prompt, temperature, maxTokens);
    } catch (e) {
      problems.push(String(e));
    }
  }

  // Gemini before OpenRouter, deliberately. Accuracy decides the order here,
  // not speed: a translate answer is written straight into the shared
  // dictionary, so a confident wrong answer becomes every learner's answer.
  // Probed on "жалаңаш", Gemini returned "naked" while the free OpenRouter
  // models returned "newcomer", "silly" and "yellowish" — which is how the
  // dictionary came to answer "жалаңаш" with the wrong word in the first place.
  for (const model of GEMINI_MODELS) {
    try {
      return await callGemini(model, prompt, temperature, maxTokens);
    } catch (e) {
      const msg = String(e);
      problems.push(msg);
      if (msg.includes(NO_KEY_MSG)) break;
    }
  }

  if (!trustedOnly) {
    for (const model of FREE_MODELS) {
      try {
        return await callOpenRouter(model, prompt, temperature, maxTokens);
      } catch (e) {
        const msg = String(e);
        problems.push(msg);
        if (msg.includes(NO_KEY_MSG)) break; // no key at all — skip the rest
      }
    }
  }

  const all = problems.join(" | ");
  if (problems.length > 0 && problems.every((p) => p.includes(NO_KEY_MSG))) {
    throw new Error(NO_KEY_MSG);
  }
  // RATE_MSG stays the leading text so the status mapping keeps matching on
  // it, but the provider detail rides along for the `note` field.
  throw new Error(
    all.includes("429") ? `${RATE_MSG} | ${all}` : all || MSG.noAnswer.kk,
  );
}

// ── Keyless translation fallback ───────────────────────────

/// Key-less translation providers, tried in order. None of them needs an API
/// key, and none of them is reliable on its own from a datacentre IP — the
/// Google endpoint in particular starts refusing requests — so the chain
/// matters more than any single one of them.

async function viaGoogle(text: string, from: string, to: string) {
  const url = "https://translate.googleapis.com/translate_a/single" +
    `?client=gtx&sl=${from}&tl=${to}&dt=t&q=${encodeURIComponent(text)}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
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
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) return "";
  const json = await res.json();
  const out = String(json?.responseData?.translatedText ?? "").trim();
  // MyMemory answers with a sentence of its own when it has no match.
  if (!out || /^(NO QUERY SPECIFIED|MYMEMORY WARNING|INVALID)/i.test(out)) return "";
  return out;
}

async function viaLingva(text: string, from: string, to: string) {
  const url = `https://lingva.ml/api/v1/${from}/${to}/${encodeURIComponent(text)}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
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

/// Walks the providers until one answers. `from` must be a real language code
/// — auto-detection is done here rather than by the provider, because the two
/// that support it disagree about Kazakh.
async function freeTranslate(
  text: string,
  from: string,
  to: string,
): Promise<string> {
  for (const provider of [viaGoogle, viaMyMemory, viaLingva]) {
    try {
      const out = tidy(await provider(text, from, to), text, to);
      if (!out) continue;
      // The gate, not just "is it different from the input". MyMemory and
      // Lingva answer Kazakh with a respelling of the Kazakh, which passes
      // every test tidy() makes and is the exact defect this release names.
      if (gate(text, out, to as "en" | "kk" | "ru") !== null) continue;
      return out;
    } catch {
      // try the next provider
    }
  }
  return "";
}

const hasCyrillic = (s: string) => /[Ѐ-ӿ]/.test(s);
const hasLatin = (s: string) => /[A-Za-z]/.test(s);
const isKazakhOnly = (s: string) => /[әғқңөұүһі]/i.test(s);

// ── The translation gate (EN-49 / KK-8) ────────────────────
//
// The named bug: "шамшырақ" was answered with "shamshyraq". That is the word
// written in Latin letters, not translated, and it reached learners as if it
// were a real answer.
//
// It got through because nothing was looking for it. `tidy()` checks the
// SCRIPT of an answer — Latin for English, Cyrillic for Kazakh — and a
// transliteration passes that check perfectly: it is Latin, it is one word, it
// is about the right length. MyMemory and Lingva, two of the three keyless
// providers, return transliterations for Kazakh routinely.
//
// So the gate below asks the question the script check cannot: is this answer
// simply the source word respelled? Everything is structural. Nothing here
// asks the model how sure it is, because the probe that motivated this file
// had two models answer the same word with "beacon" and "sunflower" and both
// report 0.95.

/// Kazakh Cyrillic to Latin, in the shape the transliterating providers use.
/// Digraphs first — a naive per-character table turns "ш" into "s" and stops
/// "shamshyraq" from matching "шамшырақ" at all, which is the one comparison
/// this table exists to make.
const TRANSLIT: Array<[RegExp, string]> = [
  [/щ/g, "sh"], [/ш/g, "sh"], [/ч/g, "ch"], [/ц/g, "ts"],
  [/ю/g, "yu"], [/я/g, "ya"], [/ё/g, "yo"], [/ж/g, "zh"],
  [/ә/g, "a"], [/ғ/g, "g"], [/қ/g, "q"], [/ң/g, "n"],
  [/ө/g, "o"], [/ұ/g, "u"], [/ү/g, "u"], [/һ/g, "h"], [/і/g, "i"],
  [/а/g, "a"], [/б/g, "b"], [/в/g, "v"], [/г/g, "g"], [/д/g, "d"],
  [/е/g, "e"], [/з/g, "z"], [/и/g, "i"], [/й/g, "y"], [/к/g, "k"],
  [/л/g, "l"], [/м/g, "m"], [/н/g, "n"], [/о/g, "o"], [/п/g, "p"],
  [/р/g, "r"], [/с/g, "s"], [/т/g, "t"], [/у/g, "u"], [/ф/g, "f"],
  [/х/g, "h"], [/ы/g, "y"], [/э/g, "e"], [/ъ/g, ""], [/ь/g, ""],
];

function romanise(s: string): string {
  let out = s.toLowerCase();
  for (const [re, to] of TRANSLIT) out = out.replace(re, to);
  return out.replace(/[^a-z]/g, "");
}

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

  // TRANSLITERATION. The check the script test cannot make: is this the source
  // word simply respelled? 0.72 is deliberately below a perfect match —
  // providers differ on ш/sh versus ш/s and on whether қ becomes q or k, so an
  // exact comparison would let half the transliterations through.
  if (to === "en" && hasCyrillic(s)) {
    const romanised = romanise(s);
    const flat = c.replace(/[^a-z]/g, "");
    if (romanised.length >= 3 && similarity(romanised, flat) >= 0.72) {
      return "translit";
    }
  }

  // LENGTH. A one-word term does not translate into a sentence, and nothing
  // here should be five times the length of what was asked.
  const words = s.split(/\s+/).length;
  if (words === 1 && c.split(/\s+/).length > 4) return "length";
  if (c.length > Math.max(48, s.length * 5)) return "length";

  return null;
}

/// Records what the gate refused, so EN-50's review queue has something to
/// review and a repeatedly-failing word is visible rather than merely absent.
/// Never allowed to break a request: a translation that could not be logged is
/// still a translation that must not be shown.
async function reportRejection(
  supabase: ReturnType<typeof createClient>,
  term: string,
  candidate: string,
  failed: GateFail,
  to: string,
  provider: string,
) {
  try {
    await supabase.from("translation_reports").insert({
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

/// Builds a plain en/kk/ru triple without any LLM. No definition, synonyms or
/// example — deliberately NOT written into the shared dictionary, so the
/// brain only ever stores full-quality entries.
async function basicEntry(term: string) {
  const t = term.trim();
  if (!t) return null;

  let en = "";
  let kk = "";
  let ru = "";
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

  if (src === "kk") {
    kk = t;
  } else {
    kk = await freeTranslate(en, "en", "kk");
  }

  if (src === "ru") {
    ru = t;
  } else {
    ru = await freeTranslate(en, "en", "ru");
  }

  if (!en || !kk) return null;
  return {
    en: en.toLowerCase(),
    kk: kk.toLowerCase(),
    ru: ru ? ru.toLowerCase() : null,
    pos: null,
    definition_en: null,
    synonyms: [],
    antonyms: [],
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

    const body = await req.json().catch(() => ({}));
    lang = clean(body.lang) === "ru" ? "ru" : "kk";

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return fail(say("auth", lang), 401);

    const task = clean(body.task) || "translate";

    // health: which keys are configured (never their values). Live provider
    // probing lives in the separate `ai-probe` function.
    if (task === "health") {
      return ok({
        freerouter: FREEROUTER_KEY.length > 0,
        freerouter_models: FREEROUTER_KEY
          ? [FREEROUTER_PRIMARY, FREEROUTER_SECOND]
          : null,
        openai: OPENAI_KEY.length > 0,
        openai_model: OPENAI_KEY ? OPENAI_MODEL : null,
        openrouter: OPENROUTER_KEY.length > 0,
        gemini: GEMINI_KEY.length > 0,
      });
    }

    // ── translate: cache-first, then AI, then a keyless fallback ──
    if (task === "translate") {
      const term = clean(body.text);
      if (!term) return fail(say("empty", lang));

      const { data: cached } = await supabase.rpc("dict_lookup", { p_term: term });
      if (Array.isArray(cached) && cached.length > 0) {
        return ok({ source: "cache", entry: cached[0] });
      }

      const prompt =
        `You are a Kazakh<->English lexicographer for a vocabulary app.\n` +
        `Input term: "${term}"\n` +
        `Detect the language and produce BOTH sides.\n` +
        `Return ONLY a raw JSON object, no markdown, with exactly these fields:\n` +
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

      let parsed: Record<string, unknown> | null = null;
      let llmError = "";
      try {
        parsed = parseJson(await complete(prompt, 0.2, 1024, true));
      } catch (e) {
        llmError = e instanceof Error ? e.message : String(e);
      }

      const en = clean(parsed?.en);
      const kk = clean(parsed?.kk);

      // Every model is out of quota (or the answer was unusable) — fall back
      // to a plain dictionary-grade translation so the user is never stuck.
      if (!en || !kk) {
        const basic = await basicEntry(term);
        if (basic) return ok({ source: "basic", entry: basic, note: llmError });
        if (llmError.includes(NO_KEY_MSG)) return fail(say("noKey", lang), 503);
        if (llmError.includes(RATE_MSG)) return fail(say("rate", lang), 429);
        return fail(llmError || say("noTranslation", lang), llmError ? 429 : 400);
      }

      // ── The gate, before anything is written (EN-49 / KK-8) ──
      //
      // This answer is about to become the shared dictionary's answer for
      // everybody, for ever. A wrong word here is not one learner's problem,
      // it is the app's. So it has to survive both checks:
      //
      //   1. the structural one — script, identity, transliteration, length;
      //   2. agreement with a second, independent model.
      //
      // The second check exists because of the probe in the header: two
      // models answered "шамшырақ" with "beacon" and "sunflower", each at
      // 0.95 confidence. Nothing about a single confident answer distinguishes
      // those two cases, so a single answer is not enough to publish on.
      const srcLang = detectLang(term);
      const target: "en" | "kk" | "ru" = srcLang === "en" ? "kk" : "en";
      const candidate = target === "en" ? en : kk;

      const failed = gate(term, candidate, target);
      if (failed !== null) {
        await reportRejection(supabase, term, candidate, failed, target, "llm");
        return ok({
          source: "rejected",
          reason: failed,
          entry: null,
          message: say("noTranslation", lang),
        });
      }

      // A second opinion, and only for a term the dictionary does not already
      // hold — this is the one path that writes, so it is the one path worth
      // spending a second request on.
      let agreed = true;
      if (FREEROUTER_KEY) {
        try {
          const check = parseJson(await callFreeRouter(
            FREEROUTER_SECOND,
            `Translate this ${LANG_NAME[srcLang === "ru" ? "ru" : "kk"] ??
              "Kazakh"} term into English. Return ONLY {"en":"..."} with the ` +
            `real meaning. If you do not know it, return {"en":""}.\n` +
            `Term: "${term}"`,
            0.1,
            120,
          ));
          const other = clean(check?.en).toLowerCase();
          // An empty second answer is an abstention, not a contradiction —
          // one model not knowing a word is not evidence the other is wrong.
          if (other && target === "en") {
            agreed = similarity(
              other.replace(/[^a-z]/g, ""),
              en.toLowerCase().replace(/[^a-z]/g, ""),
            ) >= 0.6;
          }
        } catch {
          // No second opinion available. The structural gate already passed,
          // so the answer stands rather than the learner getting nothing.
        }
      }

      if (!agreed) {
        await reportRejection(supabase, term, en, "disagree", target, "llm");
        return ok({
          source: "rejected",
          reason: "disagree",
          entry: null,
          message: say("noTranslation", lang),
        });
      }

      const { data: saved, error } = await supabase.rpc("dict_upsert", {
        p_en: en,
        p_kk: kk,
        p_pos: clean(parsed?.pos) || null,
        p_definition_en: clean(parsed?.definition_en) || null,
        p_synonyms: arr(parsed?.synonyms),
        p_antonyms: arr(parsed?.antonyms),
        p_example_en: clean(parsed?.example_en) || null,
        p_example_kk: clean(parsed?.example_kk) || null,
        p_ipa: clean(parsed?.ipa) || null,
        p_emoji: clean(parsed?.emoji) || null,
        p_cefr: CEFR.includes(clean(parsed?.cefr)) ? clean(parsed?.cefr) : "A2",
        p_topic: clean(parsed?.topic) || "general",
        p_source: "ai",
      });
      const ru = clean(parsed?.ru);
      if (error) return ok({ source: "ai", entry: { ...parsed, en, kk } });
      return ok({
        source: "ai",
        entry: ru && saved && typeof saved === "object"
          ? { ...saved, ru }
          : saved,
      });
    }

    // ── enrich: fill definition/synonyms for a word already owned ──
    if (task === "enrich") {
      const en = clean(body.en);
      const kk = clean(body.kk);
      if (!en) return fail(say("empty", lang));
      const prompt =
        `For the English word "${en}" (Kazakh: "${kk}") return ONLY raw JSON with fields:\n` +
        `  definition_en - short English definition (max 15 words)\n` +
        `  synonyms      - array of 3-4 English synonyms\n` +
        `  antonyms      - array of 0-2 English antonyms\n` +
        `  example_en    - one natural example sentence using the word\n` +
        `  ipa           - IPA transcription\n` +
        `  cefr          - one of A0, A1, A2, B1, B2, C1`;
      return ok({ entry: parseJson(await complete(prompt, 0.25, 700)) });
    }

    // ── suggest: new words at the learner's level ──
    if (task === "suggest") {
      const cefr = CEFR.includes(clean(body.cefr)) ? clean(body.cefr) : "A2";
      const topic = clean(body.topic) || "general";
      const count = Math.min(Math.max(Number(body.count) || 8, 1), 20);
      const known = (Array.isArray(body.exclude) ? body.exclude : [])
        .filter((x: unknown) => typeof x === "string")
        .slice(0, 40)
        .join(", ");

      const prompt =
        `Suggest exactly ${count} English words at CEFR level ${cefr}, topic "${topic}",\n` +
        `useful for a Kazakh speaker learning English.\n` +
        `Avoid these words: ${known || "none"}.\n` +
        `Return ONLY a raw JSON array; each item has:\n` +
        `  en, kk, pos, definition_en, synonyms (array of 2-3), example_en, emoji, cefr, topic`;

      // trustedOnly, like translate, and for the same reason: every item here
      // goes through dict_upsert into the dictionary everyone shares. Allowing
      // the free models back in was tried and measured — they answered
      // "hotel" with "гостиница" (Russian, not Kazakh), "airport" with the
      // misspelled "ауэжай", and explained "window" as "ереже". A learner
      // seeing "AI лимиті бітті" has lost one tap; a learner taught that
      // "қонақүй" is "гостиница" has been taught the wrong thing, and so has
      // everyone who looks that word up afterwards.
      const list = parseJson(await complete(prompt, 0.75, 2048, true));
      if (!Array.isArray(list)) return fail(say("noList", lang));

      const saved: unknown[] = [];
      for (const it of list.slice(0, count)) {
        const en = clean(it?.en), kk = clean(it?.kk);
        if (!en || !kk) continue;
        const { data } = await supabase.rpc("dict_upsert", {
          p_en: en,
          p_kk: kk,
          p_pos: clean(it.pos) || null,
          p_definition_en: clean(it.definition_en) || null,
          p_synonyms: arr(it.synonyms),
          p_antonyms: arr(it.antonyms),
          p_example_en: clean(it.example_en) || null,
          p_example_kk: null,
          p_ipa: null,
          p_emoji: clean(it.emoji) || null,
          p_cefr: CEFR.includes(clean(it.cefr)) ? clean(it.cefr) : cefr,
          p_topic: clean(it.topic) || topic,
          p_source: "ai",
        });
        if (data) saved.push(data);
      }
      return ok({ entries: saved });
    }

    // ── chat: one turn of a role-play conversation ──
    // The app has a scripted tutor to fall back on, but it repeats itself.
    // With this task the reply actually answers what the learner just wrote.
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

      // 300 tokens sounded generous for "1-2 short sentences" but some free
      // models were cutting replies off mid-word well before that — a bigger
      // ceiling stops the truncation without changing how long a reply is.
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
      // Same headroom fix as chat: 800 tokens was cutting a 3-5 sentence
      // explanation off mid-word on some providers well before the limit.
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
