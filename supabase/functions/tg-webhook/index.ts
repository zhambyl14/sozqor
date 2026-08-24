// SozQor Telegram bot — phone verification (EN-4 / EN-5 / KK-9)
//
// The bot proves a phone number without an SMS provider, which is what makes
// sign-up free. The whole security model is one line, further down: Telegram
// stamps every shared contact with the id of the account that shared it, so
// `contact.user_id === message.from.id` is proof the number belongs to the
// person sending it. A contact forwarded from somebody else fails that test.
//
// This function was live but had never been in the repository, so nobody could
// read it, review it or redeploy it. Two things the PRD asks for are fixed
// here as it is written down:
//
//   EN-4. The bot answers in the language the learner chose in the app. The
//   `lang` travels on the phone_verifications row (see v5_telegram_lang.sql)
//   and is looked up from the /start payload, so a learner who set the app to
//   Russian is not met by a Kazakh bot. Every string below exists in both.
//
//   EN-5. "Share your phone number" is not an instruction — it describes a
//   result, not an action, and the button it means is not on screen until the
//   keyboard is sent. So the contact-request keyboard is opened WITH the
//   message, and the text names the button by the exact label printed on it:
//   «Нөмірмен бөлісу» in Kazakh, «Поделиться контактом» in Russian. The label
//   on the button and the label in the sentence are generated from the same
//   constant so they cannot drift apart.
//
// Environment (Supabase dashboard -> Edge Functions -> tg-webhook -> Secrets):
//   TELEGRAM_BOT_TOKEN         from @BotFather
//   TELEGRAM_WEBHOOK_SECRET    any long random string; optional but advised
//   SUPABASE_URL               provided automatically
//   SUPABASE_SERVICE_ROLE_KEY  provided automatically
//
// Register the webhook once after deploying:
//
//   curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
//     -H "Content-Type: application/json" \
//     -d '{"url":"https://<project>.supabase.co/functions/v1/tg-webhook",
//          "secret_token":"<TELEGRAM_WEBHOOK_SECRET>",
//          "allowed_updates":["message"]}'
//
// Deploy with --no-verify-jwt: Telegram cannot send a Supabase JWT.
//
//   supabase functions deploy tg-webhook --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const API = `https://api.telegram.org/bot${TOKEN}`;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type Lang = "kk" | "ru";

/// The label printed on Telegram's own contact button.
///
/// Used for BOTH the button and the sentence that tells the learner to press
/// it. EN-5 is really a complaint about those two drifting apart: an
/// instruction naming a button that says something else is worse than no
/// instruction, because the learner starts looking for a button that is not
/// there.
const SHARE_LABEL: Record<Lang, string> = {
  kk: "📱 Нөмірмен бөлісу",
  ru: "📱 Поделиться контактом",
};

const T: Record<string, Record<Lang, string>> = {
  welcome: {
    kk: "Сәлем! Мен SozQor ботымын.\n\n" +
      "Нөміріңді растау үшін төмендегі «{btn}» түймесін бас. " +
      "Түйме экранның ең астында, пернетақтаның орнында тұр.\n\n" +
      "Нөмірің тек аккаунтқа кіру үшін керек. Біз жарнама жібермейміз.",
    ru: "Привет! Я бот SozQor.\n\n" +
      "Чтобы подтвердить номер, нажми кнопку «{btn}» ниже. " +
      "Она находится в самом низу экрана, на месте клавиатуры.\n\n" +
      "Номер нужен только для входа в аккаунт. Рекламу мы не присылаем.",
  },
  noCode: {
    kk: "Сәлем! Растау сілтемесі жоқ.\n\n" +
      "SozQor қосымшасын аш, «Тіркелу» бөліміне өт те, сол жердегі " +
      "Telegram түймесін бас — сол сені осында дұрыс сілтемемен әкеледі.",
    ru: "Привет! Ссылки для подтверждения нет.\n\n" +
      "Открой приложение SozQor, перейди в «Регистрацию» и нажми там кнопку " +
      "Telegram — она приведёт тебя сюда с нужной ссылкой.",
  },
  expired: {
    kk: "Бұл сілтеменің уақыты өтіп кеткен.\n\n" +
      "Қосымшаға қайта кіріп, Telegram түймесін қайтадан бас.",
    ru: "Срок действия этой ссылки истёк.\n\n" +
      "Вернись в приложение и нажми кнопку Telegram ещё раз.",
  },
  alreadyDone: {
    kk: "Бұл нөмір расталып қойған. Қосымшаға қайта оралуыңа болады.",
    ru: "Этот номер уже подтверждён. Можешь вернуться в приложение.",
  },
  notYours: {
    kk: "Бұл нөмір сенікі емес сияқты.\n\n" +
      "Басқа біреудің контактісін жіберудің орнына, «{btn}» түймесін бас — " +
      "ол сенің өз нөміріңді жібереді.",
    ru: "Похоже, это не твой номер.\n\n" +
      "Вместо пересылки чужого контакта нажми кнопку «{btn}» — она отправит " +
      "именно твой номер.",
  },
  ok: {
    kk: "✅ Нөмірің расталды!\n\n" +
      "Енді SozQor қосымшасына оралып, тіркелуді аяқта.",
    ru: "✅ Номер подтверждён!\n\n" +
      "Теперь вернись в приложение SozQor и заверши регистрацию.",
  },
  nudge: {
    kk: "Нөміріңді растау үшін «{btn}» түймесін бас.\n\n" +
      "Түймені көрмесең, қосымшадағы Telegram түймесін қайта бас.",
    ru: "Чтобы подтвердить номер, нажми кнопку «{btn}».\n\n" +
      "Если кнопки не видно, нажми кнопку Telegram в приложении ещё раз.",
  },
  help: {
    kk: "SozQor — ағылшын сөздерін ойнап үйрететін қосымша.\n\n" +
      "Бұл бот тек бір нәрсе істейді: нөміріңді растайды, сонда SMS қажет " +
      "болмайды.\n\nҚосымшадағы Telegram түймесін бассаң, бәрі өзі басталады.",
    ru: "SozQor — приложение, где английские слова учат через игру.\n\n" +
      "Этот бот делает только одно: подтверждает твой номер, чтобы не " +
      "понадобилась SMS.\n\nНажми кнопку Telegram в приложении — и всё " +
      "начнётся само.",
  },
  error: {
    kk: "Бірдеңе дұрыс болмады. Сәл кейінірек қайталап көр.",
    ru: "Что-то пошло не так. Попробуй чуть позже.",
  },
};

const say = (key: keyof typeof T, lang: Lang, btn?: string) =>
  T[key][lang].replaceAll("{btn}", btn ?? SHARE_LABEL[lang]);

// ── Telegram API ───────────────────────────────────────────

async function tg(method: string, payload: unknown) {
  try {
    await fetch(`${API}/${method}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    // A webhook that throws is a webhook Telegram retries, which would send
    // the learner the same message several times. Failing to reply is the
    // lesser problem.
  }
}

/// Sends a message with the contact-request keyboard already open (EN-5).
///
/// `one_time_keyboard` deliberately off: it collapses the keyboard after the
/// first tap, and a learner who taps somewhere else first then cannot find the
/// button again — which is the exact confusion this is meant to end.
function askForContact(chatId: number, text: string, lang: Lang) {
  return tg("sendMessage", {
    chat_id: chatId,
    text,
    reply_markup: {
      keyboard: [[{ text: SHARE_LABEL[lang], request_contact: true }]],
      resize_keyboard: true,
      one_time_keyboard: false,
      input_field_placeholder: lang === "ru"
        ? "Нажми кнопку ниже"
        : "Төмендегі түймені бас",
    },
  });
}

function plain(chatId: number, text: string) {
  return tg("sendMessage", {
    chat_id: chatId,
    text,
    // Take the contact keyboard away once it has done its job, so the chat
    // does not keep offering to share a number that is already verified.
    reply_markup: { remove_keyboard: true },
  });
}

// ── Verification rows ──────────────────────────────────────

interface Verification {
  id: string;
  code: string;
  status: string;
  lang: string | null;
  expires_at: string;
}

async function findCode(code: string): Promise<Verification | null> {
  const { data } = await supabase
    .from("phone_verifications")
    .select("id, code, status, lang, expires_at")
    .eq("code", code)
    .maybeSingle();
  return (data as Verification | null) ?? null;
}

/// The most recent code this Telegram account was sent to, used when a contact
/// arrives without a /start in the same breath — a learner can tap the button
/// minutes later, or reopen the chat and tap it then.
async function latestForChat(chatId: number): Promise<Verification | null> {
  const { data } = await supabase
    .from("phone_verifications")
    .select("id, code, status, lang, expires_at")
    .eq("telegram_id", chatId)
    .eq("status", "pending")
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data as Verification | null) ?? null;
}

const langOf = (v: Verification | null): Lang =>
  v?.lang === "ru" ? "ru" : "kk";

const isExpired = (v: Verification) =>
  new Date(v.expires_at).getTime() < Date.now();

// ── Handlers ───────────────────────────────────────────────

async function onStart(chatId: number, payload: string) {
  const code = payload.trim();

  if (!code) {
    // No payload: they found the bot by searching rather than through the app,
    // so there is no row and no language to read. Kazakh is the app's default.
    await plain(chatId, say("noCode", "kk"));
    return;
  }

  const row = await findCode(code);
  if (!row) {
    await plain(chatId, say("expired", "kk"));
    return;
  }

  const lang = langOf(row);
  if (row.status === "verified" || row.status === "consumed") {
    await plain(chatId, say("alreadyDone", lang));
    return;
  }
  if (isExpired(row)) {
    await plain(chatId, say("expired", lang));
    return;
  }

  // Remember which chat this code belongs to, so a contact shared later —
  // without a fresh /start — can still be matched back to it.
  await supabase
    .from("phone_verifications")
    .update({ telegram_id: chatId })
    .eq("id", row.id);

  await askForContact(chatId, say("welcome", lang), lang);
}

async function onContact(
  chatId: number,
  fromId: number,
  contact: { phone_number?: string; user_id?: number },
) {
  const row = await latestForChat(chatId);
  const lang = langOf(row);

  // THE security check. Telegram stamps a shared contact with the id of the
  // account that shared it; a contact forwarded from somebody else carries
  // their id, or none at all. Without this the bot would happily verify a
  // number the sender does not own, which is the whole thing it exists to
  // prevent.
  if (!contact.user_id || contact.user_id !== fromId) {
    await askForContact(chatId, say("notYours", lang), lang);
    return;
  }

  if (!row) {
    await plain(chatId, say("expired", lang));
    return;
  }
  if (isExpired(row)) {
    await plain(chatId, say("expired", lang));
    return;
  }

  const phone = (contact.phone_number ?? "").replace(/\D/g, "");
  if (!phone) {
    await askForContact(chatId, say("nudge", lang), lang);
    return;
  }

  const { error } = await supabase
    .from("phone_verifications")
    .update({
      phone,
      telegram_id: fromId,
      status: "verified",
      verified_at: new Date().toISOString(),
    })
    .eq("id", row.id)
    .eq("status", "pending");

  // Never logged: the phone number is the one piece of genuinely personal data
  // this function touches.
  if (error) {
    await plain(chatId, say("error", lang));
    return;
  }

  await plain(chatId, say("ok", lang));
}

// ── Entry point ────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");

  // Telegram echoes the secret back on every call, which is what stops
  // anybody who guesses the URL from driving the bot.
  if (WEBHOOK_SECRET) {
    const got = req.headers.get("x-telegram-bot-api-secret-token");
    if (got !== WEBHOOK_SECRET) return new Response("forbidden", { status: 403 });
  }

  try {
    const update = await req.json();
    const msg = update?.message;
    if (!msg) return new Response("ok");

    const chatId = msg.chat?.id as number | undefined;
    const fromId = msg.from?.id as number | undefined;
    if (!chatId || !fromId) return new Response("ok");

    if (msg.contact) {
      await onContact(chatId, fromId, msg.contact);
      return new Response("ok");
    }

    const text = (msg.text ?? "").trim();
    if (text.startsWith("/start")) {
      await onStart(chatId, text.slice("/start".length));
      return new Response("ok");
    }
    if (text.startsWith("/help")) {
      const row = await latestForChat(chatId);
      await plain(chatId, say("help", langOf(row)));
      return new Response("ok");
    }

    // Anything else: a learner who typed their number as text instead of
    // pressing the button, which is exactly the confusion EN-5 describes. Put
    // the button back in front of them rather than saying "unknown command".
    const row = await latestForChat(chatId);
    const lang = langOf(row);
    if (row) {
      await askForContact(chatId, say("nudge", lang), lang);
    } else {
      await plain(chatId, say("noCode", lang));
    }
    return new Response("ok");
  } catch {
    // Always 200. A non-200 makes Telegram retry the same update, and a bug
    // that sends one confusing message should not send it five times.
    return new Response("ok");
  }
});
