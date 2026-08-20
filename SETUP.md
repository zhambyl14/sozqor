# SozQor — баптау нұсқаулығы

Код толық дайын. Мына қадамдарды реті бойынша орындасаң, бәрі жұмыс істейді.

Барлық құпия кілттер бір жерге қойылады:
**https://supabase.com/dashboard/project/xwscugxrkbjiwcbmswrg/settings/functions**
→ `Edge Function Secrets` → `Add new secret`

---

## 1. Telegram боты (МІНДЕТТІ — онсыз тіркелу жұмыс істемейді)

Тіркелу SMS арқылы емес, Telegram боты арқылы өтеді. Тегін.

### 1.1 Бот жасау

1. Telegram-да **@BotFather** тап
2. `/newbot` жаз
3. Боттың атын жаз — мысалы `SozQor`
4. Username жаз — міндетті түрде `bot`-пен бітуі керек, мысалы `SozQorAuthBot`
5. BotFather саған **токен** береді — осылай көрінеді:
   `7123456789:AAH...` — оны көшіріп ал

### 1.2 Supabase-ке 3 құпия қосу

| Name | Value |
|---|---|
| `TELEGRAM_BOT_TOKEN` | BotFather берген токен |
| `TELEGRAM_BOT_USERNAME` | боттың username-і, `@` белгісінсіз (мыс. `SozQorAuthBot`) |
| `TELEGRAM_WEBHOOK_SECRET` | өзің ойлап тапқан кез келген ұзын жол (мыс. `sozqor_wh_9f3k2m8x`) |

### 1.3 Вебхукты қосу

Браузердің адрес жолағына мынаны жаз (`<TOKEN>` мен `<SECRET>` орнына өз мәндеріңді қой) және Enter бас:

```
https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://xwscugxrkbjiwcbmswrg.supabase.co/functions/v1/tg-webhook&secret_token=<SECRET>
```

`{"ok":true,"result":true,...}` деп шықса — дайын.

> Тексеру: ботқа Telegram-нан `/start` жаз. «Сәлем! Мен — SozQor боты» деп жауап беруі керек.

---

## 2. AI кілттері

Ескі кілттер қосымшаның кодында ашық жатқан, сондықтан **екеуін де ауыстыр**:
- OpenRouter: https://openrouter.ai/settings/keys → ескісін өшір, жаңасын жаса
- Gemini: https://aistudio.google.com/apikey → ескісін өшір, жаңасын жаса

Содан кейін Supabase-ке қос:

| Name | Value | Міндетті ме |
|---|---|---|
| `OPENAI_API_KEY` | `sk-proj-...` (GPT кілтің болса) | Жоқ. Ең жақсы сапа, бірақ **ақылы** — шотта баланс керек |
| `OPENAI_MODEL` | `gpt-4o-mini` (әдепкі, өзгертпесең де болады) | Жоқ |
| `OPENROUTER_API_KEY` | жаңа OpenRouter кілті | Иә (біреуі болса жетеді). **Тегін** модельдері бар |
| `GEMINI_API_KEY` | жаңа Gemini кілті | Иә (біреуі болса жетеді). **Тегін** лимиті мол |

**Кезектілік:** OpenAI → OpenRouter → Gemini → кілтсіз аудармашылар.
Бірі істемесе, келесісіне өтеді. Үшеуінің бірі болса жеткілікті.

### Қай кілт қосулы екенін тексеру

Қосымшадан сөз аударып көр де, жауап `source: "basic"` болса — бірде-бір AI
кілті істемей тұр деген сөз. Дәл себебін көру үшін:

```
Supabase → Edge Functions → sozqor-ai → Logs
```

> **Жиі кездесетін екі қате:**
> - `insufficient_quota` — кілт дұрыс, бірақ шотта ақша жоқ (OpenAI тегін
>   триалы біткен). Жаңа кілт жасаудың пайдасы жоқ — не төлеу керек, не
>   OpenRouter/Gemini-ге ауысу керек.
> - Кілт **Supabase-ке қосылмаған**. OpenRouter сайтында кілттің тұрғаны
>   жеткіліксіз — оны `Edge Functions → Secrets`-ке де қою керек. Тексеру:
>   OpenRouter → API Keys → `Last Used` бағаны `Never` болса, қосылмаған.

> **OpenRouter деген не:** бір API арқылы ондаған AI модельдеріне (GPT, Llama,
> Qwen, Gemma) қосылатын делдал. Тегін модельдері бар — ақша төлемей істеу үшін
> қосқанмын. OpenAI кілтің болса, оның қажеті шамалы, бірақ резерв ретінде
> қалдырған дұрыс.

---

## 3. Supabase Auth баптау

https://supabase.com/dashboard/project/xwscugxrkbjiwcbmswrg/auth/providers

- **Email** провайдері **қосулы** тұруы керек. Қолданушы email көрмейді —
  ішкі жағынан аккаунт `77001234567@sozqor.kz` түрінде сақталады, ал экранда
  тек телефон нөмірі болады.
- **Anonymous Sign-Ins** → **қос**. Бұл «Қонақ ретінде кіру» түймесі үшін.
  Қоспасаң, қонақ түймесі «Қонақ режимі әлі қосылмаған» деп хабарлайды.
- `Confirm email` — **өшірулі** болғаны дұрыс. Нөмірді Telegram растайды,
  сондықтан email растаудың қажеті жоқ.

---

## 4. Хабарламалар (push)

Қосымшада хабарламаның **екі түрі** бар:

| Түрі | Қайдан келеді | Не керек |
|---|---|---|
| **Күнделікті еске салу** | телефонның өзінен (жергілікті) | ештеңе — бірден жұмыс істейді |
| **Push (лига, баттл, серия)** | Firebase арқылы серверден | төмендегі баптау |

Күнделікті еске салу — Баптаулар → Хабарлама бөлімінде қосылады, уақыты да
сонда таңдалады. Ол интернетсіз де, серверсіз де жұмыс істейді.

### 4.1 Дерекқор кестесі (МІНДЕТТІ)

Supabase → **SQL Editor** → `supabase/sql/device_tokens.sql` файлының ішіндегі
кодты көшіріп қой да, `Run` бас. Онсыз құрылғы токендері сақталмайды.

### 4.2 Android
Дайын, `android/app/google-services.json` орнында.

> `applicationId` = `com.example.sozqor_app`. Оны өзгертсең, Firebase-те жаңа
> Android app тіркеп, жаңа `google-services.json` жүктеу керек.

### 4.3 Web (sozqor.tarazblt12005.workers.dev)

1. https://console.firebase.google.com → **sozqor** → ⚙️ **Project settings**
   → **Cloud Messaging** → `Web configuration` → **Generate key pair**
2. Шыққан ұзын кілтті көшір
3. Cloudflare → **sozqor** → **Settings** → **Variables** → `FCM_VAPID_KEY`
   деген айнымалы қосып, кілтті соған қой
4. `git push` — Cloudflare өзі жинап, өзі шығарады
   (`tool/cf_build.sh` → `npx wrangler deploy`)

Қолмен жинау керек болса:

```bash
flutter build web --release --pwa-strategy=none --dart-define=FCM_VAPID_KEY=<КІЛТ>
```

`web/firebase-messaging-sw.js` файлы дайын тұр — оны өзгертудің қажеті жоқ.

> **`--pwa-strategy=none` міндетті.** Онсыз Flutter өзінің service worker-ін
> қосады, ол қосымшаны телефонның кэшіне жазып қояды — сосын Cloudflare-ге жаңа
> нұсқа шықса да, телефон ескісін көрсете береді. Web push бұдан зардап
> шекпейді: ол бөлек `firebase-messaging-sw.js` арқылы жұмыс істейді.

> Кілт бермесең, веб-push жай ғана өшік қалады — қосымшаның қалғаны бұзылмайды.

> **iPhone-дағы Safari:** веб-push тек қосымшаны «Home Screen»-ге қосқанда
> ғана жұмыс істейді (iOS 16.4+). Бөлісу ⤴ → `Экранға қосу`.

### 4.4 iOS
1. https://console.firebase.google.com → **sozqor** жобасы → ⚙️ → `Add app` → **iOS**
2. Bundle ID: Xcode-тағы `Runner → Signing & Capabilities` мәнімен бірдей болсын
3. `GoogleService-Info.plist` жүктеп ал
4. Xcode-та `Runner` қалтасына сүйреп апар (`Copy items if needed` ✓)
5. `Signing & Capabilities → + Capability`:
   - **Push Notifications**
   - **Background Modes** → `Remote notifications` ✓
6. APNs кілті: https://developer.apple.com/account/resources/authkeys/list →
   `.p8` жасап, Firebase → `Project settings → Cloud Messaging → APNs Authentication Key`-ге жүкте

> `ios/Runner/Runner.entitlements` файлы дайын тұр. Xcode-та `Push Notifications`
> capability-ін қосқанда сол файл автоматты байланады. App Store-ға шығарда
> ішіндегі `development` дегенді `production` деп ауыстыр.

---

## 5. Шығару (release)

### Android

Қазір release нұсқасы debug кілтпен қол қойылған — дүкенге жарамайды.

```bash
keytool -genkey -v -keystore %USERPROFILE%\sozqor-upload.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`android/key.properties` жаса (git-ке қоспа):

```properties
storePassword=СЕНІҢ_ПАРОЛЬ
keyPassword=СЕНІҢ_ПАРОЛЬ
keyAlias=upload
storeFile=C:/Users/taraz/sozqor-upload.jks
```

Сосын `android/app/build.gradle.kts` ішіндегі
`signingConfig = signingConfigs.getByName("debug")` жолын өз кілтіңе ауыстыр.

```bash
flutter build appbundle --release
```

### iOS

macOS + Xcode керек:

```bash
flutter build ipa --release
```

---

## 6. Тексеру тізімі

**Тіркелу:**
- [ ] Кіру беті → «Тіркелу» → аты + құпия сөз → «Telegram арқылы тіркелу»
- [ ] Telegram ашылады → `Start` → «📱 Нөмірімді бөлісу»
- [ ] Қосымшаға оралғанда өзі кіргізеді
- [ ] Онбординг → деңгей тесті → 10 сөз автоматты қосылады

**Кіру:** нөмір + құпия сөз (Telegram қажет емес)
**Құпия сөзді ұмыту:** Telegram растау → жаңа құпия сөз

**Қонақ:**
- [ ] «Қонақ ретінде кіру» → ойнай алады
- [ ] Сөз сақтауға / лигаға тырыс → «Тіркел» терезесі шығады
- [ ] Сол жерден тіркел → XP мен серия сол күйі қалады

**Тіл:**
- [ ] Баптаулар → Тіл → Қосымша тілі → «Русский» — экран бірден орысшаға ауысады
- [ ] Қосымшаны жауып қайта аш — тіл сол күйі қалады

**Хабарлама:**
- [ ] Баптаулар → Хабарлама → «Күнделікті еске салу» қос → рұқсат сұрайды
- [ ] «Тексеріп көру» бас — хабарлама бірден шығады
- [ ] Уақытын таңда → келесі күні сол уақытта келеді

**Ойын:**
- [ ] Сөз қосу: «алма» / «apple» / «яблоко» — үшеуі де табылады
- [ ] Ойын → Классикалық тест → XP, серия өседі
- [ ] Арена → Ботпен → баттл, Elo жазылады
- [ ] Профиль → SozQor миы → сөз саны өсіп жатқаны көрінеді

---

## 7. Қонақ режимінде не ашық, не жабық

| Мүмкіндік | Қонақ | Тіркелген |
|---|:--:|:--:|
| Классикалық тест, Марафон, Тайм-атака | ✅ | ✅ |
| Ботпен баттл | ✅ | ✅ |
| Сөз базасын қарау, аударма іздеу | ✅ | ✅ |
| Онбордингтегі 10 бастапқы сөз | ✅ | ✅ |
| **Сөз сақтау / қосу** | ❌ | ✅ |
| **Лига** | ❌ | ✅ |
| **Рейтингті 1v1 (Elo)** | ❌ | ✅ |
| **Турнир** | ❌ | ✅ |
| **Күнделікті глобал сынақ** | ❌ | ✅ |
| **Достар, доспен баттл** | ❌ | ✅ |
| **Үздіктер тізімінде көріну** | ❌ | ✅ |

Шектеу тек кодта емес, **дерекқор деңгейінде** де қойылған — қонақ RPC-ге
тікелей сұраныс жіберсе де өтпейді.

---

## Барлық құпиялардың жиынтық тізімі

Supabase → Edge Function Secrets:

```
TELEGRAM_BOT_TOKEN        = BotFather берген токен          (міндетті)
TELEGRAM_BOT_USERNAME     = SozQorAuthBot                   (міндетті)
TELEGRAM_WEBHOOK_SECRET   = өзің ойлаған кездейсоқ жол      (міндетті)
OPENROUTER_API_KEY        = sk-or-v1-...                    (біреуі жеткілікті)
GEMINI_API_KEY            = AIza...                         (біреуі жеткілікті)
OPENAI_API_KEY            = sk-proj-...                     (бар болса — ең жақсысы)
OPENAI_MODEL              = gpt-4o-mini                     (қаласаң)
```

Supabase → Authentication → Providers: **Email** қосулы, **Anonymous** қосулы,
**Confirm email** өшірулі.

---

## Пайдалы сілтемелер

- Supabase жобасы: https://supabase.com/dashboard/project/xwscugxrkbjiwcbmswrg
- Edge Functions логтары: `Dashboard → Edge Functions → <функция> → Logs`
- Дерекқор: `Dashboard → Table Editor`
