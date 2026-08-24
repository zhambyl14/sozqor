// lib/features/profile/legal_screen.dart
//
// The two documents an app store requires and a learner is entitled to read
// at any moment: the user agreement and the privacy policy (EN-46 / KK-10).
//
// The text lives here rather than behind a link on purpose. A learner on a
// prepaid connection in the middle of a lesson should not need the network to
// read what they agreed to, and a store reviewer should not meet a spinner.
// PRIVACY.md at the repo root stays the long-form source for the store
// listing; this is the same substance, said plainly, in both languages.
//
// Both languages are written out side by side instead of going through tr().
// tr() takes the Kazakh string as its key, and a key that comes out of a
// const table rather than a literal is invisible to the i18n coverage test —
// so a missing Russian side here would silently show Kazakh to a Russian
// reader, which is the one failure the release is most concerned with. A
// record carrying both halves cannot be half-translated: the compiler asks
// for both.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';

enum LegalDoc { terms, privacy }

/// One section, in both languages.
typedef LegalSection = ({String hKk, String hRu, String bKk, String bRu});

class LegalScreen extends ConsumerWidget {
  final LegalDoc doc;
  const LegalScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final sections = doc == LegalDoc.terms ? _terms : _privacy;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: doc == LegalDoc.terms
              ? tr('Пайдаланушы келісімі')
              : tr('Құпиялық саясаты'),
          eyebrow: tr('Құқықтық құжаттар'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),
        for (final s in sections) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(byLang(kk: s.hKk, ru: s.hRu),
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  letterSpacing: -0.3, color: AppColors.text(d))),
              const SizedBox(height: 6),
              Text(byLang(kk: s.bKk, ru: s.bRu),
                style: TextStyle(
                  fontSize: 13, height: 1.55, fontWeight: FontWeight.w500,
                  color: AppColors.text2(d))),
            ],
          ),
          const SizedBox(height: 18),
        ],
        Text('sozqor.help@gmail.com',
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: AppColors.text3(d))),
      ],
    );
  }
}

const _terms = <LegalSection>[
  (
    hKk: 'SozQor туралы',
    hRu: 'О SozQor',
    bKk: 'SozQor — ағылшын сөздерін ойнап үйренуге арналған қосымша. Оны '
        'пайдалану тегін. Қосымшаны ашқаныңда осы келісімді қабылдаған '
        'болып саналасың.',
    bRu: 'SozQor — это приложение для изучения английских слов через игру. '
        'Пользоваться им бесплатно. Открывая приложение, ты принимаешь это '
        'соглашение.',
  ),
  (
    hKk: 'Аккаунт',
    hRu: 'Аккаунт',
    bKk: 'Қосымшаны тіркелмей-ақ, қонақ ретінде пайдалана бересің. Тіркелсең, '
        'прогресің сақталады және оны басқа құрылғыдан да көре аласың. '
        'Аккаунтыңның құпия сөзін басқа адамға берме — аккаунтта не '
        'болғанына сен жауаптысың.',
    bRu: 'Приложением можно пользоваться и без регистрации, как гость. Если '
        'зарегистрируешься, прогресс сохранится и будет доступен с другого '
        'устройства. Не передавай пароль другим — за то, что происходит в '
        'аккаунте, отвечаешь ты.',
  ),
  (
    hKk: 'Тәртіп ережелері',
    hRu: 'Правила поведения',
    bKk: 'Басқа пайдаланушыларды ренжітпе, дөрекі есім немесе лақап ат қойма. '
        'Ойын нәтижесін, рейтингті немесе сыйлықтарды жасанды жолмен '
        'көтеруге тырыспа. Бұл ережелер бұзылса, аккаунт шектелуі мүмкін.',
    bRu: 'Не обижай других пользователей, не ставь грубое имя или никнейм. Не '
        'пытайся искусственно поднять результат игры, рейтинг или награды. '
        'При нарушении этих правил аккаунт может быть ограничен.',
  ),
  (
    hKk: 'Сөздік мазмұны',
    hRu: 'Содержимое словаря',
    bKk: 'Сөздердің аудармасы мен мысалдары жасанды интеллекттің көмегімен де '
        'жиналады, сондықтан сирек жағдайда қате кездесуі мүмкін. Қате '
        'аударманы көрсең, бізге хабарла — модераторлар түзетеді.',
    bRu: 'Переводы слов и примеры отчасти собираются с помощью искусственного '
        'интеллекта, поэтому изредка возможны ошибки. Если увидишь неверный '
        'перевод, сообщи нам — модераторы исправят.',
  ),
  (
    hKk: 'Жауапкершілік',
    hRu: 'Ответственность',
    bKk: 'Қосымша «қалай бар, солай» ұсынылады. Біз оны үнемі жақсартып '
        'отырамыз, бірақ қызмет үзіліссіз жұмыс істейді деп кепілдік бере '
        'алмаймыз.',
    bRu: 'Приложение предоставляется «как есть». Мы постоянно его улучшаем, '
        'но не можем гарантировать работу сервиса без перерывов.',
  ),
  (
    hKk: 'Өзгерістер',
    hRu: 'Изменения',
    bKk: 'Келісім өзгерсе, жаңа нұсқасы осы бетте тұрады. Қосымшаны әрі қарай '
        'пайдалану — жаңа нұсқаны қабылдағаның.',
    bRu: 'Если соглашение изменится, новая версия появится на этой странице. '
        'Дальнейшее использование приложения означает согласие с ней.',
  ),
];

const _privacy = <LegalSection>[
  (
    hKk: 'Қандай дерек жиналады',
    hRu: 'Какие данные собираются',
    bKk: 'Есімің, лақап атың, деңгейің, XP-ің, рейтингің, сериялар мен ойын '
        'нәтижелерің. Тіркелсең — телефон нөмірің. Осының бәрі қосымшаның '
        'өзі жұмыс істеуі үшін керек.',
    bRu: 'Имя, никнейм, уровень, XP, рейтинг, серии и результаты игр. Если '
        'зарегистрируешься — номер телефона. Всё это нужно для работы самого '
        'приложения.',
  ),
  (
    hKk: 'Телефон нөмірі',
    hRu: 'Номер телефона',
    bKk: 'Нөмірді Telegram боты арқылы растайсың. Ол тек аккаунтқа кіру үшін '
        'қолданылады. Біз саған жарнамалық SMS жібермейміз.',
    bRu: 'Номер подтверждается через Telegram-бота. Он используется только для '
        'входа в аккаунт. Рекламные SMS мы не отправляем.',
  ),
  (
    hKk: 'Деректер қайда сақталады',
    hRu: 'Где хранятся данные',
    bKk: 'Деректер Supabase серверлерінде сақталады. Әр жол қорғалған: өз '
        'деректеріңді тек өзің көресің және өзгертесің.',
    bRu: 'Данные хранятся на серверах Supabase. Каждая строка защищена: свои '
        'данные видишь и меняешь только ты.',
  ),
  (
    hKk: 'Басқа адамдар нені көреді',
    hRu: 'Что видят другие',
    bKk: 'Басқа пайдаланушылар тек ашық профиліңді көреді: есім, лақап ат, '
        'аватар, деңгей, рейтинг, лига және белгішелерің. Телефон нөмірің '
        'ешқашан көрсетілмейді.',
    bRu: 'Другие пользователи видят только твой открытый профиль: имя, '
        'никнейм, аватар, уровень, рейтинг, лигу и значки. Номер телефона не '
        'показывается никогда.',
  ),
  (
    hKk: 'Хабарламалар',
    hRu: 'Уведомления',
    bKk: 'Күнделікті еске салуды өзің қосасың және өшіресің. Хабарлама жіберу '
        'үшін құрылғының белгісі сақталады, оны Баптаулардан өшіре аласың.',
    bRu: 'Ежедневное напоминание ты включаешь и выключаешь сам. Для отправки '
        'уведомлений хранится метка устройства — её можно удалить в '
        'Настройках.',
  ),
  (
    hKk: 'Жарнама',
    hRu: 'Реклама',
    bKk: 'Қосымшада жарнама көрсетілуі мүмкін. Жарнама желісі құрылғының '
        'жалпы деректерін пайдаланады, бірақ сенің сөздігің мен ойын '
        'нәтижелеріңе қолы жетпейді.',
    bRu: 'В приложении может показываться реклама. Рекламная сеть использует '
        'общие данные устройства, но не имеет доступа к твоему словарю и '
        'результатам игр.',
  ),
  (
    hKk: 'Деректі жою',
    hRu: 'Удаление данных',
    bKk: 'Баптаулар → Аккаунтты жою батырмасы аккаунтыңды және онымен '
        'байланысты барлық деректі біржола өшіреді. Бұны кері қайтару '
        'мүмкін емес.',
    bRu: 'Кнопка «Настройки → Удалить аккаунт» безвозвратно удаляет аккаунт и '
        'все связанные с ним данные. Отменить это невозможно.',
  ),
  (
    hKk: 'Балалар',
    hRu: 'Дети',
    bKk: 'Қосымшаны кез келген жаста пайдалануға болады. 13 жасқа толмаған '
        'бала ата-анасының рұқсатымен тіркелуі керек.',
    bRu: 'Приложением можно пользоваться в любом возрасте. Ребёнок младше 13 '
        'лет должен регистрироваться с разрешения родителей.',
  ),
];
