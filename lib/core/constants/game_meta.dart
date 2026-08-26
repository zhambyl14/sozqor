// lib/core/constants/game_meta.dart
//
// Static game metadata: CEFR ladder, topics, question kinds, session modes,
// avatars, bot roster and the achievement catalogue.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ── CEFR ladder ────────────────────────────────────────────────────────────

class CefrLevel {
  final String code, title, subtitle, emoji;
  const CefrLevel(this.code, this.title, this.subtitle, this.emoji);
}

const List<CefrLevel> kCefrLevels = [
  CefrLevel('A0', 'Нөлден бастаушы', 'Ағылшынды мүлде білмеймін', '🌱'),
  CefrLevel('A1', 'Бастауыш',        'Бірен-саран сөз білемін',   '🐣'),
  CefrLevel('A2', 'Негізгі',         'Қарапайым сөйлей аламын',   '📗'),
  CefrLevel('B1', 'Орта',            'Күнделікті тақырыпта еркінмін', '⚡'),
  CefrLevel('B2', 'Ортадан жоғары',  'Күрделі мәтінді түсінемін', '🔥'),
  CefrLevel('C1', 'Жетік',           'Еркін сөйлеп, жаза аламын', '👑'),
];

const List<String> kCefrCodes = ['A0', 'A1', 'A2', 'B1', 'B2', 'C1'];

CefrLevel cefrOf(String code) =>
    kCefrLevels.firstWhere((l) => l.code == code, orElse: () => kCefrLevels[1]);

int cefrIndex(String code) {
  final i = kCefrCodes.indexOf(code);
  return i < 0 ? 1 : i;
}

/// Levels a learner should actually be shown: their own level, the one below
/// (for consolidation) and the one above (for stretch). This is what keeps
/// A0 starter content out of a B2 learner's feed.
List<String> visibleCefrFor(String code) {
  final i = cefrIndex(code);
  final lo = (i - 1).clamp(0, kCefrCodes.length - 1);
  final hi = (i + 1).clamp(0, kCefrCodes.length - 1);
  return kCefrCodes.sublist(lo, hi + 1);
}

// ── Topics ─────────────────────────────────────────────────────────────────

class Topic {
  final String key, label, emoji;
  const Topic(this.key, this.label, this.emoji);
  Color get color => AppColors.topic(key);
}

const List<Topic> kTopics = [
  Topic('general',       'Жалпы',          '📚'),
  Topic('food',          'Тамақ',          '🍎'),
  Topic('travel',        'Саяхат',         '✈️'),
  Topic('family',        'Отбасы',         '👨‍👩‍👧'),
  Topic('body',          'Дене',           '💪'),
  Topic('home',          'Үй',             '🏠'),
  Topic('school',        'Оқу',            '🎓'),
  Topic('work',          'Жұмыс',          '💼'),
  Topic('nature',        'Табиғат',        '🌿'),
  Topic('animals',       'Жануарлар',      '🐾'),
  Topic('tech',          'Технология',     '💻'),
  Topic('emotions',      'Сезім',          '❤️'),
  Topic('sport',         'Спорт',          '⚽'),
  Topic('time',          'Уақыт',          '⏰'),
  Topic('city',          'Қала',           '🏙️'),
  Topic('money',         'Ақша',           '💰'),
  Topic('health',        'Денсаулық',      '🩺'),
  Topic('communication', 'Қарым-қатынас',  '💬'),
];

Topic topicOf(String key) =>
    kTopics.firstWhere((t) => t.key == key, orElse: () => kTopics.first);

// ── Question kinds ─────────────────────────────────────────────────────────

enum QKind {
  kkEn,        // қазақша сөз → ағылшын аудармасы
  enKk,        // ағылшын сөз → қазақша аудармасы
  definition,  // ағылшын сөз → ағылшынша мағынасы
  synonym,     // ағылшын сөз → синонимі
  antonym,     // ағылшын сөз → антонимі
  listening,   // тыңдап тап
  spelling,    // әріптерден жина
  sentence,    // сөйлемдегі бос орын
}

extension QKindMeta on QKind {
  String get id => name;

  String get label => switch (this) {
    QKind.kkEn       => 'Қазақша → Ағылшынша',
    QKind.enKk       => 'Ағылшынша → Қазақша',
    QKind.definition => 'Сөздің мағынасы',
    QKind.synonym    => 'Синонимін тап',
    QKind.antonym    => 'Антонимін тап',
    QKind.listening  => 'Тыңдап тап',
    QKind.spelling   => 'Әріптерден жина',
    QKind.sentence   => 'Сөйлемді толықтыр',
  };

  String get short => switch (this) {
    QKind.kkEn       => 'ҚАЗ→АҒЫЛ',
    QKind.enKk       => 'АҒЫЛ→ҚАЗ',
    QKind.definition => 'Мағына',
    QKind.synonym    => 'Синоним',
    QKind.antonym    => 'Антоним',
    QKind.listening  => 'Тыңдау',
    QKind.spelling   => 'Емле',
    QKind.sentence   => 'Сөйлем',
  };

  String get emoji => switch (this) {
    QKind.kkEn       => '🇰🇿',
    QKind.enKk       => '🇬🇧',
    QKind.definition => '📖',
    QKind.synonym    => '🔗',
    QKind.antonym    => '↔️',
    QKind.listening  => '🎧',
    QKind.spelling   => '🔤',
    QKind.sentence   => '📝',
  };

  String get prompt => switch (this) {
    QKind.kkEn       => 'Ағылшынша аудармасын таңда',
    QKind.enKk       => 'Қазақша аудармасын таңда',
    QKind.definition => 'Бұл сөз нені білдіреді?',
    QKind.synonym    => 'Осы сөздің синонимін таңда',
    QKind.antonym    => 'Осы сөздің антонимін таңда',
    QKind.listening  => 'Естіген сөзіңді таңда',
    QKind.spelling   => 'Сөзді әріптерден жина',
    QKind.sentence   => 'Бос орынға дұрыс сөзді таңда',
  };

  LinearGradient get grad => switch (this) {
    QKind.kkEn       => AppColors.brandGrad,
    QKind.enKk       => AppColors.skyGrad,
    QKind.definition => AppColors.mintGrad,
    QKind.synonym    => AppColors.magentaGrad,
    QKind.antonym    => AppColors.coralGrad,
    QKind.listening  => AppColors.skyGrad,
    QKind.spelling   => AppColors.goldGrad,
    QKind.sentence   => AppColors.brandGrad,
  };

  /// Minimum CEFR index at which this kind is worth showing.
  int get minLevel => switch (this) {
    QKind.kkEn || QKind.enKk || QKind.listening => 0,
    QKind.spelling  => 1,
    QKind.definition => 2,
    QKind.sentence  => 2,
    QKind.synonym   => 2,
    QKind.antonym   => 3,
  };

  static QKind fromId(String id) =>
      QKind.values.firstWhere((k) => k.name == id, orElse: () => QKind.kkEn);
}

/// Question kinds unlocked for a learner at [cefr].
List<QKind> kindsFor(String cefr) {
  final i = cefrIndex(cefr);
  return QKind.values.where((k) => k.minLevel <= i).toList();
}

// ── Session modes ──────────────────────────────────────────────────────────

enum PlayMode { classic, review, marathon, timeAttack, daily, battle, tournament }

extension PlayModeMeta on PlayMode {
  String get id => name;

  String get title => switch (this) {
    PlayMode.classic    => 'Классикалық тест',
    PlayMode.review     => 'Қайталау',
    PlayMode.marathon   => 'Марафон',
    PlayMode.timeAttack => 'Тайм-атака',
    PlayMode.daily      => 'Күнделікті сынақ',
    PlayMode.battle     => 'Баттл',
    PlayMode.tournament => 'Турнир раунды',
  };

  String get subtitle => switch (this) {
    PlayMode.classic    => '10 сұрақ • өз сөздерің',
    PlayMode.review     => 'Ұмытуға жақын сөздер',
    PlayMode.marathon   => '3 жан • шексіз • рекорд қой',
    PlayMode.timeAttack => '60 секунд • қанша үлгерсең',
    PlayMode.daily      => 'Бүкіл әлем бір жиынтықты ойнайды',
    PlayMode.battle     => 'Жекпе-жек',
    PlayMode.tournament => 'Жиынтық ұпайға қосылады',
  };

  String get emoji => switch (this) {
    PlayMode.classic    => '🎯',
    PlayMode.review     => '🔁',
    PlayMode.marathon   => '🏃',
    PlayMode.timeAttack => '⏱️',
    PlayMode.daily      => '🌍',
    PlayMode.battle     => '⚔️',
    PlayMode.tournament => '🏆',
  };

  LinearGradient get grad => switch (this) {
    PlayMode.classic    => AppColors.brandGrad,
    PlayMode.review     => AppColors.mintGrad,
    PlayMode.marathon   => AppColors.coralGrad,
    PlayMode.timeAttack => AppColors.goldGrad,
    PlayMode.daily      => AppColors.skyGrad,
    PlayMode.battle     => AppColors.magentaGrad,
    PlayMode.tournament => AppColors.goldGrad,
  };
}

// ── Avatars ────────────────────────────────────────────────────────────────

const List<String> kAvatars = [
  '🦊','🐺','🦅','🐎','🦁','🐯','🐻','🐼','🦉','🐨',
  '🦄','🐲','🦈','🐬','🦋','🌟','⚡','🔥','💎','👑',
];

// ── Bot roster ─────────────────────────────────────────────────────────────

class BotProfile {
  final String name, avatar;
  final double accuracy;   // chance of answering correctly
  final int    speedMs;    // average time per answer
  final int    minLevel;   // cefr index this bot starts appearing at
  const BotProfile(this.name, this.avatar, this.accuracy, this.speedMs, this.minLevel);
}

const List<BotProfile> kBots = [
  BotProfile('Айдана',  '🐣', 0.55, 5200, 0),
  BotProfile('Ерасыл',  '🦊', 0.62, 4600, 0),
  BotProfile('Мөлдір',  '🐨', 0.68, 4100, 1),
  BotProfile('Дамир',   '🐺', 0.73, 3600, 1),
  BotProfile('Аружан',  '🦉', 0.78, 3100, 2),
  BotProfile('Санжар',  '🦅', 0.83, 2700, 3),
  BotProfile('Тоқтар',  '🐯', 0.88, 2300, 4),
  BotProfile('Ұстаз AI','👑', 0.93, 1900, 5),
];

BotProfile botFor(String cefr, {int nudge = 0}) {
  final i = (cefrIndex(cefr) + nudge).clamp(0, kCefrCodes.length - 1);
  final pool = kBots.where((b) => b.minLevel <= i).toList();
  return pool.isEmpty ? kBots.first : pool.last;
}

// ── Achievements ───────────────────────────────────────────────────────────

class Achievement {
  final String code, title, description, emoji;
  final int    target;
  final String metric; // words | learned | streak | quizzes | battles_won | xp | elo | marathon
  final int    xp;
  const Achievement(this.code, this.title, this.description, this.emoji,
      this.target, this.metric, this.xp);
}

const List<Achievement> kAchievements = [
  Achievement('first_word',   'Алғашқы қадам',   'Бірінші сөзіңді қос',              '🌱',   1, 'words',       20),
  Achievement('words_10',     'Жинақтаушы',      '10 сөз жина',                      '📗',  10, 'words',       40),
  Achievement('words_50',     'Сөз қоржыны',     '50 сөз жина',                      '📚',  50, 'words',      100),
  Achievement('words_200',    'Кітапхана',       '200 сөз жина',                     '🏛️', 200, 'words',     300),
  Achievement('words_500',    'Сөз патшасы',     '500 сөз жина',                     '👑', 500, 'words',      800),
  Achievement('learned_10',   'Меңгердім',       '10 сөзді толық меңгер',            '✅',  10, 'learned',     60),
  Achievement('learned_100',  'Шебер',           '100 сөзді толық меңгер',           '🎓', 100, 'learned',    400),
  Achievement('streak_3',     'Үш күн қатар',    '3 күндік серия жаса',              '🔥',   3, 'streak',      30),
  Achievement('streak_7',     'Апталық от',      '7 күндік серия жаса',              '🔥',   7, 'streak',      80),
  Achievement('streak_30',    'Айлық темір',     '30 күндік серия жаса',             '🛡️',  30, 'streak',    500),
  Achievement('streak_100',   'Жүз күндік жол',  '100 күндік серия жаса',            '💎', 100, 'streak',    1500),
  Achievement('quiz_10',      'Ойыншы',          '10 тест тапсыр',                   '🎮',  10, 'quizzes',     40),
  Achievement('quiz_100',     'Марафоншы',       '100 тест тапсыр',                  '🏃', 100, 'quizzes',    300),
  Achievement('battle_1',     'Алғашқы жекпе-жек','Бірінші баттлыңды жең',           '⚔️',   1, 'battles_won', 50),
  Achievement('battle_10',    'Жауынгер',        '10 баттл жең',                     '🗡️',  10, 'battles_won',150),
  Achievement('battle_50',    'Арена аңызы',     '50 баттл жең',                     '🏅',  50, 'battles_won',600),
  Achievement('elo_1200',     'Рейтингті ойыншы','Elo рейтингті 1200-ге жеткіз',     '📈',1200, 'elo',        200),
  Achievement('elo_1500',     'Мықтылар лигасы', 'Elo рейтингті 1500-ге жеткіз',     '🚀',1500, 'elo',        600),
  Achievement('xp_1000',      'Мың ұпай',        '1000 тәжірибе жина',                     '⭐',1000, 'xp',         100),
  Achievement('xp_10000',     'Он мың ұпай',     '10000 тәжірибе жина',                    '🌟',10000,'xp',         700),
  Achievement('marathon_20',  'Тынымсыз',        'Марафонда 20 ұпай жина',           '💪',  20, 'marathon',   120),
  Achievement('marathon_50',  'Шыдамдылық',      'Марафонда 50 ұпай жина',           '🧗',  50, 'marathon',   400),
];
