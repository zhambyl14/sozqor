# SozQor — дүкенге шығару нұсқаулығы

Google Play мен App Store-ға шығарудың толық реті. Қадамдар **реті бойынша**
жазылған: алдыңғысын аттап кетсең, келесісі жұмыс істемейді.

`SETUP.md` — қосымшаның өзін іске қосу туралы. Бұл құжат — дүкен туралы.

---

## 0. Қазіргі жағдай

| Не | Күйі |
|---|---|
| Release қол қоюы (signing) | ✅ Дайын — `android/key.properties` болса, өз кілтіңмен қол қояды |
| Құпиялық саясаты | ✅ Жазылды — `PRIVACY.md`. Байланыс мекенжайын толтырып, интернетке шығару керек (§7) |
| Дүкен қадамдарының тізімі | ✅ Осы құжат |
| `applicationId` = `com.example.sozqor_app` | ❌ **Блокер.** Екі дүкен де `com.example`-ды қабылдамайды. §1 |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` = `com.example.sozqorApp` | ❌ **Блокер.** §1 |
| Қосымша иконкасы | ❌ **Блокер.** Әлі Flutter-дің әдепкі көк иконкасы. §5.1 |
| Upload keystore (`.jks`) | ⬜ Жасау керек — §2 |
| Play Console / App Store Connect аккаунты | ⬜ Тек сен аша аласың |

**§1 мен §2 — тек сен істей аласың.** Firebase консоліне кіру мен кілт
генерациясы басқа ешкімге тапсырылмайды.

---

## 1. Пакет атын ауыстыру (applicationId + bundle id)

> Бұл — ең қауіпті қадам. `applicationId` жаңа `google-services.json`-сыз
> ауысса, Gradle «No matching client found for package name» деп құлайды, ал
> ауысып кетсе push хабарламалары үнсіз өліп қалады. Сондықтан **алдымен
> Firebase, сосын код**.

### 1.1 Атын таңда

Ұсыныс: **`kz.sozqor.app`**

Ережелер:
- кіші әріп, кемінде екі бөлік, нүктемен бөлінеді;
- ішінде `example`, `test` болмауы керек;
- **дүкенге бір рет жүктелген соң ЕШҚАШАН өзгермейді** — жаңа ат = жаңа
  қосымша, ескі қолданушылар онда жоқ. Сондықтан қазір ойланып таңда.

Android мен iOS-та бірдей ат қойған ыңғайлы.

### 1.2 Firebase — бір команда (ұсынылатын жол)

Бұл команда Firebase-те жаңа Android және iOS қосымшаларын **өзі тіркеп**,
`google-services.json`, `GoogleService-Info.plist` файлдарын жүктеп,
`lib/firebase_options.dart` файлын қайта жазады:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=sozqor --platforms=android,ios,web \
  --android-package-name=kz.sozqor.app \
  --ios-bundle-id=kz.sozqor.app
```

> `firebase login` сұраса — Firebase жобасы тіркелген Google аккаунтыңмен кір.

### 1.3 Firebase — қолмен (балама жол)

1. https://console.firebase.google.com → **sozqor** → ⚙️ **Project settings**
   → **General** → **Your apps** → **Add app** → **Android**
2. `Android package name`: `kz.sozqor.app`
3. `google-services.json` жүктеп ал → `android/app/google-services.json`
   орнына қой (ескісін ауыстыр)
4. Сол жерде **Add app → iOS**, bundle id: `kz.sozqor.app` →
   `GoogleService-Info.plist` → Xcode-та `Runner` қалтасына сүйреп апар
5. `lib/firebase_options.dart` ішіндегі `appId` мен `iosBundleId` мәндерін
   жаңа қосымшалардікіне ауыстыр (Project settings → Your apps → App ID)

### 1.4 Кодта ауыстырылатын жерлер

| Файл | Не | Қалай |
|---|---|---|
| `android/app/build.gradle.kts` | `applicationId = "com.example.sozqor_app"` | Қолмен жаз: `applicationId = "kz.sozqor.app"` |
| `lib/firebase_options.dart` | `appId` (android), `iosBundleId` | §1.2 командасы өзі жазады |
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` (6 жер) | Xcode → `Runner` → `Signing & Capabilities` → `Bundle Identifier`. Қолмен түзетуден гөрі Xcode арқылы өзгерткен қауіпсіз |

`namespace = "com.example.sozqor_app"` мен `MainActivity.kt` ішіндегі пакетті
**өзгертпесең де болады** — ол тек Kotlin коды үшін ішкі ат, дүкен оны
көрмейді. Өзгерткің келсе, `android/app/src/main/kotlin/...` қалтасының
құрылымын да сол атпен қайта жасау керек.

### 1.5 Тексеру

```bash
flutter clean
flutter run --release
```

- Қосымша ашылса — `google-services.json` дұрыс.
- Push тірі ме: телефонда Баптаулар → Хабарлама → рұқсат бер. Сосын Supabase →
  Table Editor → `device_tokens` кестесінен жаңа токенді көшіріп ал → Firebase
  Console → **Messaging** → `Send test message` → токенді қой → жіберу.
  Хабарлама келсе, қадам аяқталды.

> Баптаулардағы «Тексеріп көру» түймесі **жергілікті** хабарламаны шығарады —
> ол Firebase-ті тексермейді. Push-ты жоғарыдағы жолмен тексер.

---

## 2. Upload keystore жасау

Release нұсқасы бұрын debug кілтпен қол қойылатын. Енді
`android/app/build.gradle.kts` `android/key.properties` файлын өзі іздейді:
бар болса — сенің кілтіңмен, жоқ болса — debug кілтпен қол қояды. Яғни
**gradle-ды енді өңдеудің қажеті жоқ**, тек екі файл жасайсың.

### 2.1 Кілт генерациясы (PowerShell)

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore "$env:USERPROFILE\sozqor-upload.jks" `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Сұрақтарға (аты-жөні, ұйым, қала, ел коды `KZ`) нақты жауап жаз. Парольді
**екі рет** сұрайды — біреуін ойлап тап та, жазып қой.

### 2.2 `android/key.properties`

```properties
storePassword=СЕНІҢ_ПАРОЛІҢ
keyPassword=СЕНІҢ_ПАРОЛІҢ
keyAlias=upload
storeFile=C:/Users/taraz/sozqor-upload.jks
```

> **Слэш алға қарай** (`/`). `.properties` файлында `\` — қашу белгісі,
> `C:\Users\...` деп жазсаң жол табылмайды.

`key.properties` пен `*.jks` — `.gitignore`-да, git-ке ешқашан түспейді.

### 2.3 Кілтті сақтау

- `.jks` файлын және екі парольді **екі бөлек жерге** көшіріп қой (мысалы,
  сыртқы диск + парольдер менеджері).
- Жоғалтсаң: Play App Signing қосулы болса, Google-дан upload key ауыстыруды
  сұрауға болады (бірнеше күн). Play App Signing қосылмаған болса — қосымшаны
  жаңарту мүмкіндігі біржола жоғалады.

### 2.4 SHA-1 (Google кірісі қажет болса)

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v `
  -keystore "$env:USERPROFILE\sozqor-upload.jks" -alias upload
```

Шыққан SHA-1-ді Firebase → Project settings → Your apps → Android →
`Add fingerprint` дегенге қос.

> Play App Signing қосылған соң Google **өз** SHA-1-ін жасайды (Play Console →
> Release → Setup → App signing). Оны да Firebase-ке қосу керек, әйтпесе
> дүкеннен орнатылған нұсқада Google кірісі істемейді.

---

## 3. AAB жинау (Android)

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Нәтиже: `build/app/outputs/bundle/release/app-release.aab`

Google кірісін қосқың келсе, сол командаға қос:

```
--dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
```

### 3.1 Нұсқа нөмірі

`pubspec.yaml` → `version: 4.0.1+2`. `+2` — бұл `versionCode`. **Play-ге
жүктелген әр жаңа файлдың `versionCode`-ы алдыңғысынан үлкен болуы керек**,
әйтпесе жүктелмейді. Әр жүктеу алдында `+3`, `+4` деп өсір.

### 3.2 Қол қойылғанын тексеру

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -printcert `
  -jarfile "build\app\outputs\bundle\release\app-release.aab"
```

`Owner:` жолында өзің жазған аты-жөнің тұруы керек. Егер `CN=Android Debug`
десе — `key.properties` табылмаған, дүкен ондай файлды қабылдамайды.

---

## 4. iOS

macOS + Xcode міндетті — Windows-та iOS нұсқасын жинау мүмкін емес.

1. **Apple Developer Program** — жылына $99.
2. Xcode → `Runner` → **Signing & Capabilities**:
   - `Team` — өз аккаунтың
   - `Bundle Identifier` — `kz.sozqor.app`
   - `+ Capability` → **Push Notifications**
   - `+ Capability` → **Background Modes** → `Remote notifications` ✓
3. `ios/Runner/Runner.entitlements` ішіндегі `development` дегенді
   `production` деп ауыстыр.
4. `ios/Runner/Info.plist`-ке қос — әйтпесе әр жүктеуде экспорт туралы сұрақ
   қойылады:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
5. **iPad туралы шешім.** Қазір `Info.plist` iPad бағдарларын қолдайды →
   App Store 13" iPad скриншоттарын да талап етеді. Тек iPhone шығарғың
   келсе: Xcode → `Runner` → **General** → `Supported Destinations` ішінен
   iPad-ты алып таста.
6. Жинау:
   ```bash
   flutter build ipa --release
   ```
   Сосын Xcode **Organizer** → `Distribute App` → `App Store Connect`, немесе
   `Transporter` қосымшасы арқылы `.ipa` файлын жүкте.

---

## 5. Дүкен активтері

### 5.1 Иконка — қазір блокер

Қазіргі күйі: `android/app/src/main/res/mipmap-*/ic_launcher.png` — Flutter-дің
әдепкі көк иконкасы, ал `assets/images/icon.png` небәрі **323×325 px**. Дүкенге
де, телефонға да жетпейді.

Керек: **1024×1024 PNG** мастер-файл. Сосын:

```bash
flutter pub add dev:flutter_launcher_icons
```

`pubspec.yaml`-ге қос:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: assets/images/icon_1024.png
  remove_alpha_ios: true
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: assets/images/icon_fg.png
```

```bash
dart run flutter_launcher_icons
```

Дүкен талаптары:

| Дүкен | Өлшемі | Ерекшелігі |
|---|---|---|
| Google Play | 512×512 PNG | 32-bit, alpha болуы мүмкін |
| App Store | 1024×1024 PNG/JPG | **мөлдірлік жоқ**, бұрышын өзің дөңгелетпе |
| Play Feature graphic | 1024×500 PNG/JPG | Дүкен бетінің басындағы баннер, міндетті |

### 5.2 Скриншоттар

| Дүкен | Талап |
|---|---|
| Google Play | Кемінде **2**, ең көбі 8. Телефон: 1080×1920 (9:16) жеткілікті. Ең кіші қабырға ≥ 320 px, ең үлкені ≤ 3840 px |
| Google Play (планшет) | Міндетті емес, бірақ болмаса дүкенде «планшетке бейімделмеген» деген белгі тұрады. 7" және 10" |
| App Store | **6.9" (1290×2796)** — міндетті. 6.5" (1284×2778) қосымша. iPad қолдасаң — 13" (2064×2752) |

Скриншотты эмуляторда емес, нақты телефонда ал: Басты бет, Ойын сессиясы,
Баттл, Лига/Үздіктер, Профиль — бесеуі жетеді.

### 5.3 Мәтіндер

| Өріс | Play шегі | App Store шегі |
|---|---|---|
| Аты | 30 | 30 |
| Қысқа сипаттама / Subtitle | 80 | 30 |
| Толық сипаттама | 4000 | 4000 |
| Кілт сөздер | — | 100 |
| Promotional text | — | 170 |

**Тіл.** Play-де қазақ тілі (kk) бар — қазақша + орысша жаса.
App Store-да қазақ тілі жоқ — орысша + ағылшынша жаса.

Дайын үлгі (қысқартып, өзгертіп қолдана бер):

```
Аты (kk):     SozQor — ағылшын сөздері
Қысқаша (kk): Ағылшын сөздерін ойнап үйрен: баттл, лига, күнделікті мақсат.

Аты (ru):     SozQor — английские слова
Кратко (ru):  Учи английские слова играя: батлы, лига, ежедневная цель.

Name (en):    SozQor — Learn English Words
Subtitle:     Learn English by playing
```

Толық сипаттама (kk) үлгісі:

```
SozQor — қазақ тілінде сөйлейтіндерге арналған ағылшын сөздерін үйрену
қосымшасы. Барлық түсіндірме — қазақша.

• Сөз қосасың — аудармасы, мысалы, айтылуы автоматты табылады
• Аралық қайталау: ұмытар алдында сол сөз қайта шығады
• Ойын режимдері: классикалық тест, марафон, тайм-атака, айтылым
• Баттл: ботпен немесе нақты қарсыласпен 1v1
• Лига, турнир, күнделікті мақсат, серия
• Интернетсіз де жұмыс істейтін офлайн сөздік

Тегін. Жарнама жоқ. Дүкендегі бәрі ойында жинаған XP-ге алынады.
```

---

## 6. Google Play Console

### 6.1 Аккаунт

- Тіркеу: https://play.google.com/console — бір рет **$25**.
- **Маңызды:** жаңа **жеке** (individual) аккаунттарға Google қосымшаны
  Production-ға шығармас бұрын **12 тестермен 14 күн жабық тест** өткізуді
  міндеттейді. Бұл — күнтізбеге әсер ететін нәрсе, алдын ала 12 адам жинап
  қой. Ұйым (organization) аккаунтына бұл талап қолданылмайды.

### 6.2 App content бөлімі

| Өріс | Жауап |
|---|---|
| Privacy policy URL | §7-де жасалатын сілтеме |
| Ads | Жоқ, жарнама жоқ |
| App access | Қосымша қонақ режимінде толық ашық. Бірақ тіркелген бөлікті тексеру үшін **демо аккаунт** бер: нөмір + құпия сөз. Telegram арқылы растауды модератор жасай алмайды, сондықтан аккаунтты алдын ала өзің жасап қой |
| Content rating | Анкетаны толтыр: зорлық жоқ, ересектерге арналған контент жоқ, қолданушылар арасында хат алмасу жоқ |
| Target audience | **13+**. 13-ке дейінгі жас тобын таңдама — әйтпесе Play Families саясаты қосылып, қосымша сол талаптарға сай болуы керек |
| Data safety | §8 кестесі |
| Government / Financial / Health apps | Үшеуіне де жоқ |

### 6.3 Шығару реті

1. **Internal testing** — AAB жүкте, өз телефоныңа орнатып тексер
2. **Closed testing** — 12 тестер, 14 күн (§6.1)
3. **Production** — елдерді таңда (Қазақстан + қалағаның)

Бірінші тексеру әдетте бірнеше күнге созылады.

---

## 7. Құпиялық саясатын интернетке шығару

Екі дүкен де **ашық URL** сұрайды — репозиторийдегі файл жарамайды.

1. `PRIVACY.md` ішіндегі толтырылмаған орындарды жаз:
   `<ӘЗІРЛЕУШІ_АТЫ>`, `<БАЙЛАНЫС_ПОШТАСЫ>`, `<@БОТ_USERNAME>`
   (орысша бөлімінде: `<ИМЯ_РАЗРАБОТЧИКА>`, `<КОНТАКТНАЯ_ПОЧТА>`).
   Пошта нақты жұмыс істейтін болсын — өшіру сұраныстары сонда келеді.
2. Ең оңай жол: веб-нұсқа Cloudflare-де тұр. `web/privacy.html` файлын жаса
   (мазмұны — `PRIVACY.md`-дің HTML-і), `git push` — Cloudflare өзі шығарады.
   URL: `https://sozqor.tarazblt12005.workers.dev/privacy.html`
3. Балама: GitHub репозиторийі ашық болса, `PRIVACY.md`-дің GitHub-тағы
   сілтемесі де жарайды.

> **App Store қосымша талап қояды:** аккаунт жасай алатын қосымшада аккаунтты
> **қосымшаның ішінен** өшіру жолы болуы керек (Guideline 5.1.1(v)). Қазір
> қосымшада ондай түйме жоқ — оны Баптаулар экранына қосу керек. Ол
> қосылғанша App Store-ға жіберу қайтарылып қалуы мүмкін. Play үшін жоғарыдағы
> сұраныс жолы жеткілікті.

---

## 8. Data safety / App Privacy жауаптары

Қосымша шын жинайтын деректер (`PRIVACY.md` §2 бойынша). Осыны сол күйі
көшіріп қоюға болады.

### Google Play — Data safety

| Дерек түрі | Жиналады | Бөлісіледі | Міндетті ме | Мақсаты |
|---|---|---|---|---|
| Personal info → Phone number | Иә | Жоқ | Міндетті емес (қонақ режимі бар) | Account management |
| Personal info → Name | Иә | Жоқ | Міндетті емес | Account management, App functionality |
| Personal info → User IDs (Telegram id) | Иә | Жоқ | Міндетті емес | Account management |
| App activity → Other user-generated content (AI-ға жазылған мәтін) | Иә | Жоқ | Міндетті емес | App functionality |
| App activity → App interactions | Иә | Жоқ | Міндетті емес | App functionality, Analytics |
| Device or other IDs | Иә | Жоқ | Міндетті емес | App functionality (push), Analytics |
| App info and performance → Diagnostics | Иә | Жоқ | Міндетті емес | Analytics |
| Location, Financial info, Health, Photos, Audio, Contacts, Calendar, SMS | **Жоқ** | — | — | — |

Қосымша сұрақтар:
- *Is all data encrypted in transit?* → **Иә**
- *Do you provide a way to request data deletion?* → **Иә**, §7-дегі URL
- *Data collected for advertising or third-party sharing?* → **Жоқ**

> AI провайдерлері мен Firebase — біздің тапсырмамызды орындайтын қызметтер
> (service providers), сондықтан Play терминологиясында бұл «sharing» емес.

### App Store — App Privacy

| Санат | Жауап |
|---|---|
| **Data Used to Track You** | Ешқандай |
| **Data Linked to You** | Phone Number, Name, User ID, User Content, Product Interaction, Device ID |
| **Data Not Linked to You** | Diagnostics |
| Мақсаттар | App Functionality, Analytics. Advertising — жоқ |

---

## 9. Firebase Analytics туралы шешім

`android/app/build.gradle.kts` ішінде `firebase-analytics` кітапханасы бар. Ол
Dart кодынан шақырылмайды, бірақ қосылып тұрғандықтан қосымшаның ашылуы сияқты
жалпы оқиғаларды өзі жинайды. Екі жол бар:

- **Қалдыру** — §8-дегі `Diagnostics` пен `Device or other IDs` жауаптары сол
  күйінде дұрыс болады (`PRIVACY.md` да солай жазылған);
- **Алып тастау** — `implementation("com.google.firebase:firebase-analytics")`
  жолын өшір. Push (FCM) онсыз да жұмыс істейді. Сонда `PRIVACY.md` §4-тен
  Firebase Analytics жолын, §8-ден `Diagnostics`-ті де алып таста.

---

## 10. Соңғы тексеру тізімі

**Шығармас бұрын:**
- [ ] `applicationId` мен bundle id `com.example`-дан ауысты (§1)
- [ ] Жаңа `google-services.json` орнында, push тексерілді (§1.5)
- [ ] `android/key.properties` бар, AAB өз кілтіңмен қол қойылған (§2.2, §3.2)
- [ ] `.jks` файлы мен парольдер екі жерде сақтаулы (§2.3)
- [ ] Иконка ауыстырылды, 1024×1024 мастер бар (§5.1)
- [ ] Скриншоттар алынды (§5.2)
- [ ] `PRIVACY.md` толтырылды және ашық URL-де тұр (§7)
- [ ] Демо аккаунт жасалды, нөмірі мен паролі Play Console-ға жазылды (§6.2)
- [ ] `pubspec.yaml`-дегі `versionCode` өсірілді (§3.1)
- [ ] Data safety анкетасы §8 бойынша толтырылды

**Ескерту:** `SETUP.md` §5 «`build.gradle.kts` ішіндегі жолды өз кілтіңе
ауыстыр» дейді — ол ескірді. Енді `key.properties` жеткілікті, gradle-ды
өңдеудің қажеті жоқ.
