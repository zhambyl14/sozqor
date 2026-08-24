// lib/features/words/word_detail_screen.dart
//
// The word card.
//
// Everything the learner needs about one word without a second tap:
// pronunciation, the translation, an example in context, synonyms and
// antonyms, and — the part 3.0 never showed — exactly where the word sits in
// its review schedule and when it comes back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/question_factory.dart';
import '../../services/sozqor_ai.dart';
import '../../services/speech.dart';
import '../play/play_session_screen.dart';
import '../play/pronounce_screen.dart';
import 'add_word_screen.dart';

class WordDetailScreen extends ConsumerStatefulWidget {
  final Word word;
  const WordDetailScreen({super.key, required this.word});

  @override
  ConsumerState<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends ConsumerState<WordDetailScreen> {
  late Word _word = widget.word;
  String? _explanation;
  bool _explaining = false;
  bool _enriching = false;

  String get _speakable => _word.en.toLowerCase().startsWith('to ')
      ? _word.en.substring(3) : _word.en;

  Future<void> _toggleFavorite() async {
    final next = !_word.isFavorite;
    setState(() => _word = _word.copyWith(isFavorite: next));
    try {
      await ref.read(wordsRepoProvider).toggleFavorite(_word.id, next);
      ref.invalidate(myWordsProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _word = _word.copyWith(isFavorite: !next));
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  /// Pulls in definition / synonyms / antonyms when the word was added by
  /// hand and has none.
  Future<void> _enrich() async {
    setState(() => _enriching = true);
    try {
      final e = await SozQorAI.instance.enrich(en: _word.en, kk: _word.kk);
      await ref.read(wordsRepoProvider).update(_word.id, {
        'definition_en': e.definitionEn,
        'synonyms': e.synonyms,
        'antonyms': e.antonyms,
        'example_en': e.exampleEn ?? _word.exampleEn,
        'transcription': e.ipa ?? _word.transcription,
      });
      if (!mounted) return;
      setState(() => _word = _word.copyWith(
        definitionEn: e.definitionEn,
        synonyms: e.synonyms,
        antonyms: e.antonyms,
        exampleEn: e.exampleEn ?? _word.exampleEn,
        transcription: e.ipa ?? _word.transcription,
      ));
      ref.invalidate(myWordsProvider);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _explain() async {
    setState(() => _explaining = true);
    try {
      final text = await SozQorAI.instance
          .explain(_word.en, studyLang: ref.read(nativeLangProvider));
      if (mounted) setState(() => _explanation = text);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _explaining = false);
    }
  }

  Future<void> _delete() async {
    final ok = await sqConfirm(context,
      title: tr('Сөзді жою'),
      message: trp('«{p1}» сөзін сөздіктен жоясың ба?', {'p1': _word.en}),
      confirm: tr('Жою'));
    if (!ok || !mounted) return;
    try {
      await ref.read(wordsRepoProvider).remove(_word.id);
      refreshAll(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  /// A short round built only from this word plus decoys from the level pool.
  Future<void> _drill() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final pool = ref.read(levelPoolProvider).valueOrNull ?? const [];
    final questions = QuestionFactory.build(
      items: [PlayItem.fromWord(_word)],
      pool: pool,
      kinds: kindsFor(profile?.cefrLevel ?? 'A1'),
      count: 4,
      nativeLang: ref.read(nativeLangProvider),
    );
    if (questions.isEmpty) {
      sqSnack(context, tr('Бұл сөзге сұрақ құрастыру мүмкін болмады'), error: true);
      return;
    }
    await Navigator.of(context).push<PlayOutcome>(MaterialPageRoute(
      builder: (_) => PlaySessionScreen(
        mode: PlayMode.review, preset: questions, title: _word.en)));
    if (mounted) refreshAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final t = topicOf(_word.topic);
    final lang = ref.watch(nativeLangProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        Row(
          children: [
            SqSquareButton(PhosphorIconsBold.arrowLeft,
              onTap: () => Navigator.of(context).pop()),
            const Spacer(),
            SqSquareButton(
              _word.isFavorite
                  ? PhosphorIconsFill.heart : PhosphorIconsBold.heart,
              fill: _word.isFavorite
                  ? AppColors.soft(AppColors.red, d) : AppColors.card(d),
              border: _word.isFavorite
                  ? Colors.transparent : AppColors.border(d),
              iconColor: _word.isFavorite
                  ? AppColors.red : AppColors.text2(d),
              onTap: _toggleFavorite),
            const SizedBox(width: 9),
            SqSquareButton(PhosphorIconsBold.pencilSimple,
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AddWordScreen(editing: _word)));
                if (changed == true && mounted) {
                  ref.invalidate(myWordsProvider);
                  final list = await ref.read(myWordsProvider.future);
                  final updated = list.firstWhere(
                    (w) => w.id == _word.id, orElse: () => _word);
                  if (mounted) setState(() => _word = updated);
                }
              }),
            const SizedBox(width: 9),
            SqSquareButton(PhosphorIconsBold.trash,
              iconColor: AppColors.red,
              onTap: _delete),
          ],
        ),
        const SizedBox(height: 16),

        SqInkCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_word.en,
                          style: TextStyle(
                            fontSize: _word.en.length > 14 ? 24 : 32,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9, color: Colors.white)),
                        const SizedBox(height: 4),
                        SqNum(
                          [
                            if ((_word.transcription ?? '').isNotEmpty)
                              _word.transcription!,
                            if ((_word.pos ?? '').isNotEmpty) _word.pos!,
                          ].join(' · '),
                          size: 13, weight: FontWeight.w500,
                          color: AppColors.onInk2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      SqSquareButton(PhosphorIconsFill.speakerHigh,
                        size: 46,
                        fill: AppColors.primary,
                        lip: AppColors.primaryDeep,
                        iconColor: Colors.white,
                        onTap: () => Speech.instance.say(_speakable)),
                      const SizedBox(height: 7),
                      GestureDetector(
                        onTap: () => Speech.instance.slow(_speakable),
                        child: Text(tr('баяу'),
                          style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700,
                            color: AppColors.onInk2)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SqEyebrow(lang == 'ru' ? tr('Орысша') : tr('Қазақша'),
                      color: AppColors.onInk3, size: 9.5),
                    const SizedBox(height: 3),
                    Text(_word.native(lang),
                      style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 7, runSpacing: 7, children: [
                _InkTag(_word.cefr, AppColors.sky),
                _InkTag(t.label, null),
                _InkTag(trp('{p1}/5 меңгерілді', {'p1': '${_word.mastery}'}), AppColors.green),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 15),

        if ((_word.exampleEn ?? '').isNotEmpty) ...[
          SqPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SqEyebrow(tr('Мысал сөйлем'), size: 9.5),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Speech.instance.say(_word.exampleEn!),
                      child: Icon(PhosphorIconsFill.speakerHigh,
                        size: 17, color: AppColors.text3(d)),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                _Highlighted(
                  sentence: _word.exampleEn!,
                  target: _word.en,
                  base: AppColors.text(d)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if ((_word.definitionEn ?? '').isNotEmpty) ...[
          SqPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SqEyebrow(tr('Ағылшынша мағынасы'), size: 9.5),
                const SizedBox(height: 10),
                Text(_word.definitionEn!,
                  style: TextStyle(
                    fontSize: 13.5, height: 1.55, fontWeight: FontWeight.w600,
                    color: AppColors.text2(d))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (_word.synonyms.isNotEmpty || _word.antonyms.isNotEmpty) ...[
          SqEqualRow(
            children: [
              Expanded(
                child: _TagPanel(
                  label: tr('Синоним'),
                  items: _word.synonyms,
                  tint: AppColors.green),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: _TagPanel(
                  label: tr('Антоним'),
                  items: _word.antonyms,
                  tint: AppColors.red),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        SqPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(PhosphorIconsFill.calendarCheck,
                    size: 18, color: AppColors.primary),
                  const SizedBox(width: 9),
                  Text(tr('Қайталау кестесі'),
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                      color: AppColors.text(d))),
                  const Spacer(),
                  SqBadge(
                    _word.isDue ? tr('қазір дайын') : _relative(_word.nextReview),
                    tint: _word.isDue ? AppColors.green : AppColors.primary),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    Expanded(
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: i < _word.mastery
                              ? AppColors.green
                              : AppColors.border(d),
                          borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                    if (i != 4) const SizedBox(width: 5),
                  ],
                ],
              ),
              const SizedBox(height: 11),
              Text(_masteryLine(),
                style: TextStyle(
                  fontSize: 11.5, height: 1.45, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Metric(tr('Дұрыс'), '${_word.correct}', d),
                  _Metric(tr('Барлығы'), '${_word.attempts}', d),
                  _Metric(tr('Дәлдік'),
                    '${(_word.accuracy * 100).round()}%', d),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if ((_word.definitionEn ?? '').isEmpty || _word.synonyms.isEmpty) ...[
          SqAction(tr('Мағынасын, синонимін толықтыр'),
            icon: PhosphorIconsFill.sparkle,
            tone: SqTone.softPrimary,
            height: 50,
            busy: _enriching,
            onTap: _enrich),
          const SizedBox(height: 12),
        ],

        if (_explanation != null)
          SqPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SqEyebrow(tr('SozQor түсіндіреді'), size: 9.5),
                const SizedBox(height: 10),
                Text(_explanation!,
                  style: TextStyle(
                    fontSize: 13.5, height: 1.6, fontWeight: FontWeight.w600,
                    color: AppColors.text2(d))),
              ],
            ),
          )
        else
          SqAction(_explaining ? tr('Жүктелуде…') : tr('Қазақша түсіндір'),
            icon: PhosphorIconsFill.brain,
            tone: SqTone.ghost,
            height: 50,
            busy: _explaining,
            onTap: _explaining ? null : _explain),

        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SqAction(tr('Осы сөзді жаттығу'),
                icon: PhosphorIconsFill.target,
                height: 52,
                onTap: _drill),
            ),
            const SizedBox(width: 10),
            SqSquareButton(PhosphorIconsFill.microphone,
              size: 52,
              fill: AppColors.card(d),
              border: AppColors.border(d),
              lip: AppColors.surfaceLip(d),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PronounceScreen(
                  only: _word.en, onlyWordId: _word.id)))),
          ],
        ),
      ],
    );
  }

  String _masteryLine() => switch (_word.mastery) {
    0 => tr('Бұл сөз әлі жаңа. Алғашқы қайталаудан кейін кесте басталады.'),
    5 => tr('Толық меңгерілді. Ұзақ үзілістен кейін бір рет тексеріледі.'),
    _ => trp('Меңгеру деңгейі: 5-тен {done}. Толық меңгеруге дейін {left} қадам.', {
          'done': '${_word.mastery}',
          'left': '${5 - _word.mastery}',
        }),
  };

  static String _relative(DateTime? at) {
    if (at == null) return tr('жоспарланбаған');
    final diff = at.difference(DateTime.now());
    if (diff.isNegative) return tr('қазір');
    if (diff.inDays > 0) return trp('{p1} күннен кейін', {'p1': '${diff.inDays}'});
    if (diff.inHours > 0) return trp('{p1} сағаттан кейін', {'p1': '${diff.inHours}'});
    return trp('{p1} минуттан кейін', {'p1': '${diff.inMinutes}'});
  }
}

class _InkTag extends StatelessWidget {
  final String label;
  final Color? tint;
  const _InkTag(this.label, this.tint);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (tint ?? Colors.white).withValues(alpha: tint == null ? 0.12 : 0.18),
      borderRadius: BorderRadius.circular(8)),
    child: Text(label,
      style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800,
        color: tint ?? Colors.white)),
  );
}

class _TagPanel extends StatelessWidget {
  final String label;
  final List<String> items;
  final Color tint;
  const _TagPanel({
    required this.label, required this.items, required this.tint});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqPanel(
      radius: 20,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SqEyebrow(label, size: 9.5),
          const SizedBox(height: 9),
          if (items.isEmpty)
            Text('—',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.text4(d)))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in items) SqBadge(s, tint: tint, size: 11.5),
            ]),
        ],
      ),
    );
  }
}

/// Renders the example sentence with the target word picked out in violet.
class _Highlighted extends StatelessWidget {
  final String sentence, target;
  final Color base;
  const _Highlighted({
    required this.sentence, required this.target, required this.base});

  @override
  Widget build(BuildContext context) {
    final needle = target.toLowerCase().startsWith('to ')
        ? target.substring(3) : target;
    final lower = sentence.toLowerCase();
    final at = lower.indexOf(needle.toLowerCase());

    const style = TextStyle(
      fontSize: 14, height: 1.55, fontWeight: FontWeight.w600);

    if (at < 0 || needle.isEmpty) {
      return Text(sentence, style: style.copyWith(color: base));
    }
    return RichText(
      text: TextSpan(
        style: style.copyWith(color: base),
        children: [
          TextSpan(text: sentence.substring(0, at)),
          TextSpan(
            text: sentence.substring(at, at + needle.length),
            style: const TextStyle(
              color: AppColors.primary, fontWeight: FontWeight.w800)),
          TextSpan(text: sentence.substring(at + needle.length)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value;
  final bool d;
  const _Metric(this.label, this.value, this.d);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        SqNum(value, size: 15, color: AppColors.text(d)),
        const SizedBox(height: 2),
        Text(label,
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
      ],
    ),
  );
}
