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

/// Gemini's speech models hand back raw little-endian 16-bit PCM, and the
/// transcriber wants a container. Forty-four bytes of header is the whole
/// difference between "unsupported media" and a transcript.
function wavFromPcm(pcm: Uint8Array, rate = 24000): Uint8Array {
  const out = new Uint8Array(44 + pcm.length);
  const dv = new DataView(out.buffer);
  const ascii = (at: number, s: string) => {
    for (let i = 0; i < s.length; i++) out[at + i] = s.charCodeAt(i);
  };
  ascii(0, "RIFF");
  dv.setUint32(4, 36 + pcm.length, true);
  ascii(8, "WAVEfmt ");
  dv.setUint32(16, 16, true);      // PCM header size
  dv.setUint16(20, 1, true);       // format: PCM
  dv.setUint16(22, 1, true);       // mono
  dv.setUint32(24, rate, true);
  dv.setUint32(28, rate * 2, true);
  dv.setUint16(32, 2, true);
  dv.setUint16(34, 16, true);
  ascii(36, "data");
  dv.setUint32(40, pcm.length, true);
  out.set(pcm, 44);
  return out;
}

const b64 = (bytes: Uint8Array) => {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
};

const unb64 = (s: string) =>
  Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

/// Speaks a word, so the transcriber has something real to listen to. The
/// alternative is testing speech recognition against silence, which proves
/// only that the request shape parses.
async function tts(
  model: string, text: string,
): Promise<{ data: string; mime: string }> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: { prebuiltVoiceConfig: { voiceName: "Kore" } },
          },
        },
      }),
      signal: AbortSignal.timeout(TIMEOUT),
    },
  );
  const body = await res.text();
  if (!res.ok) throw new Error(`tts ${res.status} ${body.slice(0, 200)}`);
  const j = JSON.parse(body);
  const part = j?.candidates?.[0]?.content?.parts?.[0];
  const data = part?.inlineData?.data ?? part?.inline_data?.data ?? "";
  const mime = part?.inlineData?.mimeType ?? part?.inline_data?.mime_type ?? "";
  if (!data) throw new Error("tts: no audio");
  return { data: data as string, mime: String(mime) };
}

/// "audio/L16;codec=pcm;rate=24000" -> 24000. Guessing this wrong makes every
/// word play at the wrong speed, which no transcriber can recover from.
function rateOf(mime: string): number {
  const m = mime.match(/rate=(\d+)/);
  return m ? parseInt(m[1], 10) : 24000;
}

/// One transcription over plain REST. If this works, the pronunciation
/// checker does not need a WebSocket at all.
async function transcribe(
  model: string, wav: string, instruction: string,
): Promise<string> {
  const parts: unknown[] = instruction
    ? [{ text: instruction }, { inlineData: { mimeType: "audio/wav", data: wav } }]
    : [{ inlineData: { mimeType: "audio/wav", data: wav } }];
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { temperature: 0, maxOutputTokens: 2048 },
      }),
      signal: AbortSignal.timeout(TIMEOUT),
    },
  );
  const body = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${body.slice(0, 260)}`);
  const j = JSON.parse(body);
  const t = j?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!t.trim()) {
    throw new Error(`empty finish=${j?.candidates?.[0]?.finishReason ?? "?"}`);
  }
  return t as string;
}

/// Speaks a word and asks each candidate model to hear it back. This is the
/// whole feasibility question for automatic pronunciation scoring, asked in
/// one request: can any model on this key turn speech into text over REST.
async function roundTrip(word: string, models: string[]) {
  const t0 = Date.now();
  let wav = "";
  let mime = "";
  try {
    const spoken = await tts(
      "gemini-2.5-flash-preview-tts",
      `Read this single English word aloud, clearly and nothing else: ${word}`,
    );
    mime = spoken.mime;
    wav = b64(wavFromPcm(unb64(spoken.data), rateOf(spoken.mime)));
  } catch (e) {
    return [{ step: "tts", word, error: String(e).slice(0, 220), ms: Date.now() - t0 }];
  }
  const spoke = Date.now() - t0;
  // Two shapes per model: with an instruction and with the audio alone. A
  // dedicated transcriber can treat a text part as something to answer rather
  // than something to obey, and come back empty.
  const shapes: Array<[string, string]> = [
    ["asked", "Transcribe the spoken English word. Return ONLY the word."],
    ["bare", ""],
  ];
  const jobs: Array<Promise<unknown>> = [];
  for (const m of models) {
    for (const [tag, instruction] of shapes) {
      jobs.push((async () => {
        const t1 = Date.now();
        try {
          const heard = await transcribe(m, wav, instruction);
          return { step: tag, model: m, word, mime,
                   heard: heard.trim().slice(0, 60), ttsMs: spoke,
                   ms: Date.now() - t1 };
        } catch (e) {
          return { step: tag, model: m, word, mime,
                   error: String(e).slice(0, 200), ttsMs: spoke,
                   ms: Date.now() - t1 };
        }
      })());
    }
  }
  return await Promise.all(jobs);
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

  // {"hear":["model", ...], "terms":[...]} — speak each word, then ask each
  // model to hear it back.
  if (Array.isArray(body.hear) && body.hear.length) {
    const models = body.hear
      .filter((x: unknown) => typeof x === "string").slice(0, 5) as string[];
    const words: string[] = Array.isArray(body.terms) && body.terms.length
      ? body.terms.filter((x: unknown) => typeof x === "string").slice(0, 4)
      : ["beacon"];
    const rounds = await Promise.all(words.map((w) => roundTrip(w, models)));
    return json({ results: rounds.flat() });
  }

  // {"speak":"library"} — hand back a real WAV, so the gateway's own listen
  // task can be tested end to end without a microphone in the room.
  if (typeof body.speak === "string" && body.speak.trim()) {
    try {
      const spoken = await tts(
        "gemini-2.5-flash-preview-tts",
        `Read this single English word aloud, clearly and nothing else: ${body.speak.trim()}`,
      );
      return json({
        mime: "audio/wav",
        source_mime: spoken.mime,
        audio: b64(wavFromPcm(unb64(spoken.data), rateOf(spoken.mime))),
      });
    } catch (e) {
      return json({ error: String(e).slice(0, 300) }, 200);
    }
  }

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
