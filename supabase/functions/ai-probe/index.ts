// Diagnostic probe for the sozqor-ai provider chain.
//
// POST {"terms":[...]}            ask every configured provider the same words
// POST {"list":true}              Google's catalogue of model ids for this key
// POST {"models":[...]}           probe exactly those REST model ids
// POST {"live":[...]}             probe those model ids over the Live API
//
// The last one exists because the free tier prices the Live API differently:
// the REST Flash models are capped at 20 requests a DAY, while the Live
// models are capped at no request count at all — only tokens per minute. If
// one of them can answer a lexicographer's question in JSON, the app stops
// having a daily budget. Whether it can is a question for a measurement, not
// for an opinion, which is what this is.
//
// Key VALUES are never returned — only model names, answers and timings.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENROUTER_KEY = Deno.env.get("OPENROUTER_API_KEY") ?? "";
const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const FREEROUTER_KEY = Deno.env.get("FREEROUTER_API_KEY") ?? "";
const FREEROUTER_URL = "https://freerouter.eu.cc/v1/chat/completions";

const TIMEOUT = 25_000;

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

const prompt = (term: string) =>
  `The Kazakh word "${term}" — give its real English meaning.\n` +
  `A romanisation of the Kazakh (writing it in Latin letters) is WRONG.\n` +
  `Return ONLY raw JSON: {"en":"...","ru":"...","gloss":"short English explanation"}`;

async function chatCompletions(
  url: string, key: string, model: string, text: string,
) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: text }],
      temperature: 0.1,
      max_tokens: 300,
    }),
    signal: AbortSignal.timeout(TIMEOUT),
  });
  const body = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${body.slice(0, 200)}`);
  const j = JSON.parse(body);
  const t = j?.choices?.[0]?.message?.content ?? "";
  if (!t.trim()) throw new Error("empty");
  return t as string;
}

async function gemini(model: string, text: string) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: { temperature: 0.1, maxOutputTokens: 4096 },
      }),
      signal: AbortSignal.timeout(TIMEOUT),
    },
  );
  const body = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${body.slice(0, 200)}`);
  const j = JSON.parse(body);
  const t = j?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!t.trim()) {
    throw new Error(`empty finish=${j?.candidates?.[0]?.finishReason ?? "?"}`);
  }
  return t as string;
}

/// One turn over the Live API: connect, set up, ask, read until the turn is
/// complete, close. A session per question is the wrong shape for a chat and
/// exactly the right shape for a dictionary lookup.
function geminiLive(model: string, text: string): Promise<string> {
  const url =
    "wss://generativelanguage.googleapis.com/ws/" +
    "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent" +
    `?key=${GEMINI_KEY}`;

  return new Promise((resolve, reject) => {
    let ws: WebSocket;
    try {
      ws = new WebSocket(url);
    } catch (e) {
      reject(new Error(`ws open: ${String(e).slice(0, 120)}`));
      return;
    }
    let out = "";
    let done = false;
    const finish = (err?: string) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { ws.close(); } catch { /* already closing */ }
      if (err) reject(new Error(err));
      else if (!out.trim()) reject(new Error("empty"));
      else resolve(out);
    };
    const timer = setTimeout(() => finish(`timeout ${TIMEOUT}ms`), TIMEOUT);

    ws.onopen = () => {
      ws.send(JSON.stringify({
        setup: {
          model: `models/${model}`,
          generationConfig: { responseModalities: ["TEXT"], temperature: 0.1 },
        },
      }));
    };

    ws.onerror = () => finish("ws error");
    ws.onclose = (ev) => {
      if (!done && !out.trim()) {
        finish(`closed ${ev.code} ${String(ev.reason ?? "").slice(0, 160)}`);
      } else finish();
    };

    ws.onmessage = async (ev) => {
      let raw = "";
      try {
        raw = typeof ev.data === "string" ? ev.data : await (ev.data as Blob).text();
      } catch {
        return;
      }
      let msg: Record<string, unknown>;
      try { msg = JSON.parse(raw); } catch { return; }

      if (msg.setupComplete !== undefined) {
        ws.send(JSON.stringify({
          clientContent: {
            turns: [{ role: "user", parts: [{ text }] }],
            turnComplete: true,
          },
        }));
        return;
      }
      const sc = msg.serverContent as Record<string, unknown> | undefined;
      if (sc) {
        const turn = sc.modelTurn as { parts?: Array<{ text?: string }> } | undefined;
        for (const p of turn?.parts ?? []) out += p.text ?? "";
        if (sc.turnComplete === true || sc.generationComplete === true) finish();
      }
    };
  });
}

type Provider = { id: string; run: (text: string) => Promise<string> };

function providers(only?: string[], live?: string[]): Provider[] {
  const out: Provider[] = [];
  if (GEMINI_KEY && live && live.length) {
    for (const m of live) out.push({ id: `live/${m}`, run: (t) => geminiLive(m, t) });
    return out;
  }
  if (GEMINI_KEY && only && only.length) {
    for (const m of only) out.push({ id: `gemini/${m}`, run: (t) => gemini(m, t) });
    return out;
  }
  if (OPENAI_KEY) {
    for (const m of ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-5-mini"]) {
      out.push({
        id: `openai/${m}`,
        run: (t) => chatCompletions("https://api.openai.com/v1/chat/completions", OPENAI_KEY, m, t),
      });
    }
  }
  if (GEMINI_KEY) {
    for (const m of ["gemini-3.6-flash", "gemini-flash-latest", "gemini-2.5-flash"]) {
      out.push({ id: `gemini/${m}`, run: (t) => gemini(m, t) });
    }
  }
  if (FREEROUTER_KEY) {
    for (const m of ["glm-5.2", "kiro-auto"]) {
      out.push({
        id: `freerouter/${m}`,
        run: (t) => chatCompletions(FREEROUTER_URL, FREEROUTER_KEY, m, t),
      });
    }
  }
  if (OPENROUTER_KEY) {
    for (
      const m of [
        "nvidia/nemotron-3-super-120b-a12b:free",
        "openai/gpt-oss-20b:free",
        "z-ai/glm-5.2:free",
        "google/gemma-4-31b-it:free",
        "deepseek/deepseek-chat-v3.1:free",
        "qwen/qwen3-235b-a22b:free",
      ]
    ) {
      out.push({
        id: `openrouter/${m}`,
        run: (t) => chatCompletions("https://openrouter.ai/api/v1/chat/completions", OPENROUTER_KEY, m, t),
      });
    }
  }
  return out;
}

/// Google's own list of what this key may call, paged.
async function listGemini() {
  const out: unknown[] = [];
  let pageToken = "";
  for (let page = 0; page < 5; page++) {
    const url = new URL("https://generativelanguage.googleapis.com/v1beta/models");
    url.searchParams.set("key", GEMINI_KEY);
    url.searchParams.set("pageSize", "200");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT) });
    const body = await res.text();
    if (!res.ok) throw new Error(`${res.status} ${body.slice(0, 300)}`);
    const j = JSON.parse(body);
    for (const m of j?.models ?? []) {
      out.push({
        id: String(m.name ?? "").replace(/^models\//, ""),
        label: m.displayName ?? "",
        methods: m.supportedGenerationMethods ?? [],
      });
    }
    pageToken = j?.nextPageToken ?? "";
    if (!pageToken) break;
  }
  return out;
}

async function one(p: Provider, term: string) {
  const t0 = Date.now();
  try {
    const raw = await p.run(prompt(term));
    let en = "", ru = "", gloss = "";
    try {
      const j = JSON.parse(extractJson(raw));
      en = String(j?.en ?? "");
      ru = String(j?.ru ?? "");
      gloss = String(j?.gloss ?? "").slice(0, 90);
    } catch {
      gloss = raw.slice(0, 90);
    }
    return { model: p.id, term, en, ru, gloss, ms: Date.now() - t0 };
  } catch (e) {
    return { model: p.id, term, error: String(e).slice(0, 200), ms: Date.now() - t0 };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const json = (b: unknown, s = 200) =>
    new Response(JSON.stringify(b, null, 2), {
      status: s,
      headers: { ...CORS, "Content-Type": "application/json" },
    });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "auth required" }, 401);

  const body = await req.json().catch(() => ({}));

  if (body.list === true) {
    try {
      return json({ models: await listGemini() });
    } catch (e) {
      return json({ error: String(e).slice(0, 300) }, 200);
    }
  }

  const terms: string[] = Array.isArray(body.terms) && body.terms.length
    ? body.terms.filter((x: unknown) => typeof x === "string").slice(0, 8)
    : ["шаңырақ"];
  const only: string[] = Array.isArray(body.models)
    ? body.models.filter((x: unknown) => typeof x === "string").slice(0, 8)
    : [];
  const live: string[] = Array.isArray(body.live)
    ? body.live.filter((x: unknown) => typeof x === "string").slice(0, 8)
    : [];

  const ps = providers(only, live);
  const jobs: Promise<unknown>[] = [];
  for (const term of terms) for (const p of ps) jobs.push(one(p, term));

  return json({
    keys: {
      openai: !!OPENAI_KEY,
      gemini: !!GEMINI_KEY,
      openrouter: !!OPENROUTER_KEY,
      freerouter: !!FREEROUTER_KEY,
    },
    results: await Promise.all(jobs),
  });
});
