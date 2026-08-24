// lib/features/home/story_content.dart
//
// The Word Path's story (EN-11 / KK-1).
//
// 4.0's "Сөз жолы" was a zig-zag of forty nodes and every single one of them
// launched the same classic quiz filtered by topic. The PRD's loudest complaint
// about the whole app is that everything is question → answer → score, and this
// mode was the clearest example: a map drawn over a test.
//
// So this is a story a learner plays through, and the vocabulary is how they
// play it. Picking the right English word IS what the character says next;
// getting it wrong is not a red cross, it is Aida saying the wrong thing and
// the scene going on anyway. Two branches per chapter change what comes after,
// so a chapter played twice is not identical.
//
// ── Why the prose is byLang and not tr() ──
// tr() takes the Kazakh string as its key, and a paragraph-length key is both
// unreadable in source and invisible to the i18n coverage test, which only
// sees string literals passed directly to tr(). A half-translated story would
// ship silently. A record carrying both languages cannot be half-translated:
// the compiler asks for both.
//
// ── Level ──
// Every answer word is A1–A2. A story a beginner cannot read is a story that
// only works for people who did not need it.

import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/widgets.dart' show IconData;

/// What the learner does in a scene. Varied deliberately — three word-choices
/// in a row and the story is a quiz wearing a costume again.
enum SceneKind {
  /// Choose the English word the character should say.
  word,
  /// Hear it, then choose it. The listening beat.
  listen,
  /// Spell it out on the keypad.
  spell,
  /// A story decision with no right answer, which changes later scenes.
  branch,
}

/// One option in a branch, and the flag it sets.
class StoryChoice {
  final String kk, ru;
  /// Remembered for the rest of the chapter so later narration can react.
  final String flag;
  const StoryChoice({required this.kk, required this.ru, required this.flag});
}

class StoryScene {
  /// Who is talking. Names are the same in both languages on purpose — they
  /// are people, not vocabulary.
  final String speaker;
  /// What is happening. Two or three sentences at most: the standing rule for
  /// this app is to cut the words, and a wall of text in a language you are
  /// learning is a wall you stop climbing.
  final String narrationKk, narrationRu;
  /// The line the scene turns on — a question asked of the learner, or the
  /// character's own words.
  final String lineKk, lineRu;

  final SceneKind kind;

  /// The English word this scene is about. Empty for a branch.
  final String answer;
  /// Wrong answers offered alongside it. Real words, plausibly confusable —
  /// three obviously silly options is not a choice either.
  final List<String> distractors;

  /// Only for [SceneKind.branch].
  final List<StoryChoice> choices;

  /// Shown after the scene resolves, and reacts to a flag when one is set.
  final String afterKk, afterRu;
  /// When set, this scene's [afterKk]/[afterRu] are only used if the flag was
  /// chosen earlier in the chapter.
  final String? ifFlag;

  const StoryScene({
    required this.speaker,
    required this.narrationKk,
    required this.narrationRu,
    required this.lineKk,
    required this.lineRu,
    this.kind = SceneKind.word,
    this.answer = '',
    this.distractors = const [],
    this.choices = const [],
    this.afterKk = '',
    this.afterRu = '',
    this.ifFlag,
  });
}

class StoryChapter {
  final String titleKk, titleRu;
  final String placeKk, placeRu;
  final IconData icon;
  final List<StoryScene> scenes;
  const StoryChapter({
    required this.titleKk,
    required this.titleRu,
    required this.placeKk,
    required this.placeRu,
    required this.icon,
    required this.scenes,
  });
}

/// The cast. Three people, carried through every chapter, so the story has
/// somebody in it rather than a series of unrelated counters.
///
///   Айя  — the learner's travelling companion, cheerful, asks questions
///   Бек  — her older brother, already in the city, practical
///   Мира — a barista in chapter two who turns up again at the end
const _aiya = 'Айя';
const _bek = 'Бек';
const _mira = 'Мира';

const kStory = <StoryChapter>[
  // ── 1 ─────────────────────────────────────────────────────
  StoryChapter(
    titleKk: 'Әуежай',
    titleRu: 'Аэропорт',
    placeKk: 'Бірінші тарау',
    placeRu: 'Первая глава',
    icon: PhosphorIconsFill.airplaneTilt,
    scenes: [
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Ұшақ қонды. Айя терезеден жаңа қаланы көріп тұр.',
        narrationRu: 'Самолёт приземлился. Айя смотрит в окно на новый город.',
        lineKk: 'Кірер алдында бізден бір нәрсе сұрайды. Ол ағылшынша не?',
        lineRu: 'Перед входом у нас кое-что спросят. Как это по-английски?',
        answer: 'passport',
        distractors: ['ticket', 'window', 'letter'],
        afterKk: 'Қызметкер басын изеді. Бірінші кедергі — өтті.',
        afterRu: 'Сотрудник кивает. Первое препятствие пройдено.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Заттар шығатын таспаның қасында тұрмыз.',
        narrationRu: 'Стоим у ленты, откуда выезжают вещи.',
        lineKk: 'Менің қара сөмкем қайда? «Сөмке» ағылшынша қалай?',
        lineRu: 'Где моя чёрная сумка? Как будет «сумка» по-английски?',
        kind: SceneKind.listen,
        answer: 'bag',
        distractors: ['box', 'book', 'bed'],
        afterKk: 'Сөмке келді. Айя жеңілдеп күлді.',
        afterRu: 'Сумка приехала. Айя облегчённо смеётся.',
      ),
      StoryScene(
        speaker: _bek,
        narrationKk: 'Бек шығыс есіктің жанында күтіп тұр.',
        narrationRu: 'Бек ждёт у восточного выхода.',
        lineKk: 'Қалаға қалай барамыз? Шешім сенікі.',
        lineRu: 'Как поедем в город? Решай ты.',
        kind: SceneKind.branch,
        choices: [
          StoryChoice(kk: 'Таксимен', ru: 'На такси', flag: 'taxi'),
          StoryChoice(kk: 'Пойызбен', ru: 'На поезде', flag: 'train'),
        ],
      ),
      StoryScene(
        speaker: _bek,
        narrationKk: 'Жолда Бек терезеге қарап отыр.',
        narrationRu: 'По дороге Бек смотрит в окно.',
        lineKk: 'Мына жердің атын жаз — біз тұратын жер осы.',
        lineRu: 'Напиши название этого места — здесь мы и живём.',
        kind: SceneKind.spell,
        answer: 'city',
        afterKk: 'Бек: «Ертең саған бір жерді көрсетемін».',
        afterRu: 'Бек: «Завтра покажу тебе одно место».',
        ifFlag: 'taxi',
      ),
    ],
  ),

  // ── 2 ─────────────────────────────────────────────────────
  StoryChapter(
    titleKk: 'Кофехана',
    titleRu: 'Кофейня',
    placeKk: 'Екінші тарау',
    placeRu: 'Вторая глава',
    icon: PhosphorIconsFill.coffee,
    scenes: [
      StoryScene(
        speaker: _mira,
        narrationKk: 'Бұрыштағы кішкене кофехана. Бариста күлімсіреп қарайды.',
        narrationRu: 'Маленькая кофейня на углу. Бариста улыбается.',
        lineKk: 'Не ішесің? Айя ыстық сүтті сусын алғысы келеді.',
        lineRu: 'Что будешь пить? Айя хочет горячий напиток с молоком.',
        answer: 'coffee',
        distractors: ['water', 'juice', 'soup'],
        afterKk: 'Мира: «Жақсы таңдау».',
        afterRu: 'Мира: «Хороший выбор».',
      ),
      StoryScene(
        speaker: _mira,
        narrationKk: 'Мира кассаға қарап тұр.',
        narrationRu: 'Мира смотрит на кассу.',
        lineKk: 'Төлеу керек. Бұл сөзді естіп көр.',
        lineRu: 'Нужно заплатить. Послушай это слово.',
        kind: SceneKind.listen,
        answer: 'money',
        distractors: ['music', 'monday', 'mother'],
        afterKk: 'Айя ақшасын береді.',
        afterRu: 'Айя отдаёт деньги.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Терезенің жанындағы орынға отырдық.',
        narrationRu: 'Сели за столик у окна.',
        lineKk: 'Мира менен бірдеңе сұрады. Оның есімін жаз.',
        lineRu: 'Мира кое-что спросила. Напиши её имя по-английски.',
        kind: SceneKind.spell,
        answer: 'name',
        afterKk: 'Мира: «Айя. Есімде сақтаймын».',
        afterRu: 'Мира: «Айя. Запомню».',
      ),
      StoryScene(
        speaker: _mira,
        narrationKk: 'Кетер алдында Мира бір нәрсе ұсынды.',
        narrationRu: 'Перед уходом Мира кое-что предложила.',
        lineKk: 'Ертең де келесің бе?',
        lineRu: 'Придёшь завтра?',
        kind: SceneKind.branch,
        choices: [
          StoryChoice(kk: 'Иә, келемін', ru: 'Да, приду', flag: 'friend'),
          StoryChoice(kk: 'Білмеймін', ru: 'Не знаю', flag: 'shy'),
        ],
      ),
    ],
  ),

  // ── 3 ─────────────────────────────────────────────────────
  StoryChapter(
    titleKk: 'Базар',
    titleRu: 'Рынок',
    placeKk: 'Үшінші тарау',
    placeRu: 'Третья глава',
    icon: PhosphorIconsFill.storefront,
    scenes: [
      StoryScene(
        speaker: _bek,
        narrationKk: 'Базар шулы. Жеміс сатушы Айяға қарап тұр.',
        narrationRu: 'Рынок шумный. Продавец фруктов смотрит на Айю.',
        lineKk: 'Қызыл, дөңгелек, тәтті. Ол не?',
        lineRu: 'Красное, круглое, сладкое. Что это?',
        answer: 'apple',
        distractors: ['onion', 'bread', 'cheese'],
        afterKk: 'Сатушы екеуін пакетке салды.',
        afterRu: 'Продавец кладёт два в пакет.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Келесі сөреде нан иісі шығып тұр.',
        narrationRu: 'На следующем прилавке пахнет хлебом.',
        lineKk: 'Мынаны да алайық. Естіп көр.',
        lineRu: 'Давай возьмём и это. Послушай.',
        kind: SceneKind.listen,
        answer: 'bread',
        distractors: ['break', 'brown', 'board'],
        afterKk: 'Бек: «Бүгін кешкі ас дайын».',
        afterRu: 'Бек: «Ужин на сегодня готов».',
      ),
      StoryScene(
        speaker: _bek,
        narrationKk: 'Сатушы бағаны айтты, бірақ Айя естімей қалды.',
        narrationRu: 'Продавец назвал цену, но Айя не расслышала.',
        lineKk: 'Сұрау керек. Бұл сөзді жаз.',
        lineRu: 'Нужно спросить. Напиши это слово.',
        kind: SceneKind.spell,
        answer: 'price',
        afterKk: 'Сатушы саусағымен санды көрсетті.',
        afterRu: 'Продавец показывает число на пальцах.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Қолымыз толы. Үйге қайтуымыз керек.',
        narrationRu: 'Руки полные. Пора домой.',
        lineKk: 'Мынау бізді үйге апарады. Ол не?',
        lineRu: 'Это отвезёт нас домой. Что это?',
        answer: 'bus',
        distractors: ['boat', 'bike', 'door'],
        afterKk: 'Автобус тоқтады. Есік ашылды.',
        afterRu: 'Автобус останавливается. Дверь открывается.',
      ),
    ],
  ),

  // ── 4 ─────────────────────────────────────────────────────
  StoryChapter(
    titleKk: 'Сұхбат',
    titleRu: 'Собеседование',
    placeKk: 'Төртінші тарау',
    placeRu: 'Четвёртая глава',
    icon: PhosphorIconsFill.briefcase,
    scenes: [
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Кеңсе. Айяның қолы сәл дірілдеп тұр.',
        narrationRu: 'Офис. У Айи слегка дрожат руки.',
        lineKk: 'Олар менен нені сұрайды? Ең бірінші — осы.',
        lineRu: 'О чём меня спросят? Первое — это.',
        answer: 'work',
        distractors: ['walk', 'word', 'world'],
        afterKk: 'Есік ашылды. Ішке шақырды.',
        afterRu: 'Дверь открылась. Её пригласили внутрь.',
      ),
      StoryScene(
        speaker: _bek,
        narrationKk: 'Бек есіктің сыртында күтіп қалды.',
        narrationRu: 'Бек остался ждать за дверью.',
        lineKk: 'Сен не істей аласың? Оларға осыны айт.',
        lineRu: 'Что ты умеешь? Скажи им именно это.',
        kind: SceneKind.spell,
        answer: 'help',
        afterKk: 'Сұхбат алушы басын изеді де, жазып алды.',
        afterRu: 'Интервьюер кивает и что-то записывает.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Соңғы сұрақ ауыр естілді.',
        narrationRu: 'Последний вопрос прозвучал тяжело.',
        lineKk: 'Қашан бастай аласың? Естіп көр.',
        lineRu: 'Когда сможешь начать? Послушай.',
        kind: SceneKind.listen,
        answer: 'tomorrow',
        distractors: ['today', 'together', 'morning'],
        afterKk: 'Бөлмеде бір сәт тыныштық орнады.',
        afterRu: 'В комнате на мгновение стало тихо.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Сыртқа шыққанда Бек орнынан тұрды.',
        narrationRu: 'Когда она вышла, Бек встал.',
        lineKk: 'Оған не дейміз?',
        lineRu: 'Что ему скажем?',
        kind: SceneKind.branch,
        choices: [
          StoryChoice(kk: 'Алдым!', ru: 'Меня взяли!', flag: 'hired'),
          StoryChoice(kk: 'Күте тұрайық', ru: 'Подождём', flag: 'waiting'),
        ],
      ),
    ],
  ),

  // ── 5 ─────────────────────────────────────────────────────
  StoryChapter(
    titleKk: 'Қайту',
    titleRu: 'Возвращение',
    placeKk: 'Бесінші тарау',
    placeRu: 'Пятая глава',
    icon: PhosphorIconsFill.house,
    scenes: [
      StoryScene(
        speaker: _mira,
        narrationKk: 'Кофеханада Мира Айяны танып қалды.',
        narrationRu: 'В кофейне Мира узнала Айю.',
        lineKk: 'Қалайсың? Бір ай өтті.',
        lineRu: 'Как ты? Прошёл месяц.',
        answer: 'happy',
        distractors: ['hungry', 'heavy', 'hard'],
        afterKk: 'Мира: «Көзіңнен көрініп тұр».',
        afterRu: 'Мира: «По глазам вижу».',
        ifFlag: 'friend',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Айя қалтасынан бір қағаз шығарды.',
        narrationRu: 'Айя достала из кармана бумагу.',
        lineKk: 'Мынау менің жаңа... Жаз.',
        lineRu: 'Это моя новая... Напиши.',
        kind: SceneKind.spell,
        answer: 'job',
        afterKk: 'Мира қағазды оқыды да, күлді.',
        afterRu: 'Мира прочитала бумагу и засмеялась.',
      ),
      StoryScene(
        speaker: _bek,
        narrationKk: 'Бек кешке бәрін шақырды.',
        narrationRu: 'Бек вечером всех позвал.',
        lineKk: 'Бүгін не істейміз? Естіп көр.',
        lineRu: 'Что сегодня будем делать? Послушай.',
        kind: SceneKind.listen,
        answer: 'dinner',
        distractors: ['winter', 'dinosaur', 'finger'],
        afterKk: 'Үстел толды. Дауыстар араласты.',
        afterRu: 'Стол накрыт. Голоса смешались.',
      ),
      StoryScene(
        speaker: _aiya,
        narrationKk: 'Терезеден сол қала көрініп тұр. Енді ол бөтен емес.',
        narrationRu: 'В окне тот же город. Теперь он не чужой.',
        lineKk: 'Мұнда мен өзімді қалай сезінемін?',
        lineRu: 'Как я себя здесь чувствую?',
        answer: 'home',
        distractors: ['hotel', 'hour', 'hope'],
        afterKk: 'Айя күлді. Бірінші тарау осылай бітті.',
        afterRu: 'Айя улыбнулась. Так закончилась первая часть.',
      ),
    ],
  ),
];

/// Total scenes, which is what `MetaState.storyNode` counts.
int get kStoryLength =>
    kStory.fold(0, (n, c) => n + c.scenes.length);

/// The index of the first scene of [chapter].
int chapterStart(int chapter) {
  var n = 0;
  for (var i = 0; i < chapter && i < kStory.length; i++) {
    n += kStory[i].scenes.length;
  }
  return n;
}

/// Which chapter a flat scene index falls in.
int chapterOf(int scene) {
  var n = 0;
  for (var i = 0; i < kStory.length; i++) {
    n += kStory[i].scenes.length;
    if (scene < n) return i;
  }
  return kStory.length - 1;
}
