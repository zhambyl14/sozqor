// lib/features/play/play_session_screen.dart
//
// One engine drives every solo mode: classic, review, marathon, time attack,
// the global daily challenge, tournament rounds and word-path levels. Rounds
// are built locally from the learner's words plus the shared dictionary, so
// play starts instantly and keeps working offline.
//
// The 4.0 rewrite fixes the loudest complaint about 3.0: the round used to
// auto-advance the moment you tapped, which meant a wrong answer flashed past
// before you could read why. Now answering *stops*. A verdict panel rises
// from the bottom with the correct word and the reason, and "Келесі" always
// sits in exactly the same place — the round only moves when you say so.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../core/widgets/spelling_pad.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/question.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../services/ads.dart';
import '../../providers.dart';
import '../../services/achievements.dart';
import '../../services/question_factory.dart';
import '../../services/speech.dart';

/// What a finished round reports back to whoever pushed it. The word path
/// uses [passed] to decide whether the next node unlocks.
class PlayOutcome {
  final int score, correct, total, bestCombo;
  const PlayOutcome({
    required this.score,
    required this.correct,
    required this.total,
    required this.bestCombo,
  });

  double get accuracy => total == 0 ? 0 : correct / total;
  bool get passed => total > 0 && accuracy >= 0.6;
}

class PlaySessionScreen extends ConsumerStatefulWidget {
  final PlayMode mode;
  final List<QKind>? kinds;
  final int? tournamentId;
  final List<Question>? preset;
  final String? topic;
  /// Shown in place of the mode name — used by word packs and the word path.
  final String? title;
  /// How many questions a classic round asks (EN-31). Null keeps each mode's
  /// own default; marathon and time attack ignore it, since they end on
  /// lives and on the clock rather than on a count.
  final int? count;

  const PlaySessionScreen({
    super.key,
    required this.mode,
    this.kinds,
    this.tournamentId,
    this.preset,
    this.topic,
    this.title,
    this.count,
  });

  @override
  ConsumerState<PlaySessionScreen> createState() => _PlaySessionScreenState();
}

class _PlaySessionScreenState extends ConsumerState<PlaySessionScreen> {
  static const _timeAttackSeconds = 60;
  static const _marathonLives = 3;

  List<Question> _questions = const [];
  List<PlayItem> _items = const [];
  List<DictEntry> _pool = const [];
  final List<AnswerLog> _log = [];

  int _index = 0;
  int _score = 0;
  int _correct = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _lives = _marathonLives;
  /// Set once a rewarded ad has bought this run an extra life. The run
  /// carries on for the practice, but its score never reaches the arcade
  /// board — a record anyone can extend by watching videos is not a
  /// record, and every board in this app ranks on numbers people earned.
  bool _revived = false;
  int _secondsLeft = _timeAttackSeconds;
  int _elapsedMs = 0;

  String? _picked;
  bool _revealed = false;
  bool _skipped = false;
  bool _loading = true;
  bool _finished = false;
  bool _submitting = false;
  String? _error;

  /// Options knocked out by the 50:50 lifeline on the current question.
  Set<String> _hidden = {};
  bool _fiftyUsed = false;
  bool _hintUsed = false;

  final List<int> _chosenLetters = [];

  /// Questions answered wrongly, so the result screen can offer a short drill
  /// on exactly those instead of a fresh random round.
  final List<Question> _wrong = [];

  Timer? _ticker;
  DateTime _questionStart = DateTime.now();

  bool get _isMarathon   => widget.mode == PlayMode.marathon;
  bool get _isTimeAttack => widget.mode == PlayMode.timeAttack;
  bool get _isDaily      => widget.mode == PlayMode.daily;

  @override
  void initState() {
    super.initState();
    // EN-12: nothing may pop over a live question. The invite overlay reads
    // this and holds anything that arrives until the round is over.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(busyProvider.notifier).state = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Cleared in deactivate() rather than dispose(): Riverpod invalidates `ref`
  /// once the element is unmounted, so reading a notifier in dispose() throws
  /// "Cannot use ref after the widget was disposed". deactivate() runs first,
  /// while the element is still attached, and is the documented place for
  /// this.
  @override
  void deactivate() {
    ref.read(busyProvider.notifier).state = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    Speech.instance.stop();
    super.dispose();
  }

  // ── setup ────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.preset != null && widget.preset!.isNotEmpty) {
        _questions = widget.preset!;
      } else {
        await _buildRound();
      }

      // A question with neither options nor letters cannot be answered —
      // it would just show an empty screen, so it never gets asked.
      _questions = _questions
          .where((q) => q.options.isNotEmpty || q.letters.isNotEmpty)
          .toList();

      if (_questions.isEmpty) {
        setState(() { _loading = false; _error = tr(S.needMore); });
        return;
      }

      // Marathon spends the extra lives bought in the shop.
      final extra = ref.read(metaProvider).lives;
      if (_isMarathon && extra > 0) _lives = _marathonLives + extra;

      setState(() {
        _loading = false;
        _questionStart = DateTime.now();
      });
      _startTimers();
      _maybeSpeak();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = humanError(e); });
    }
  }

  Future<void> _buildRound() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';
    final lang = ref.read(nativeLangProvider);
    final kinds = widget.kinds ?? kindsFor(cefr);

    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];
    final due = widget.mode == PlayMode.review
        ? await ref.read(wordsRepoProvider).due(limit: 40)
        : const <Word>[];

    _pool = ref.read(levelPoolProvider).valueOrNull ??
        await ref.read(dictRepoProvider)
            .pool(cefr: visibleCefrFor(cefr), topic: widget.topic, limit: 150)
            .catchError((_) => <DictEntry>[]);

    final source = widget.mode == PlayMode.review
        ? due
        : (widget.topic == null
            ? words
            : words.where((w) => w.topic == widget.topic).toList());

    _items = source.map(PlayItem.fromWord).toList();

    // Not enough personal words yet? Top up from the shared dictionary so a
    // brand new learner can still play a full round.
    if (_items.length < 8) {
      final owned = {for (final w in words) w.en.toLowerCase()};
      final extra = _pool
          .where((e) => !owned.contains(e.en.toLowerCase()))
          .take(30 - _items.length)
          .map(PlayItem.fromDict);
      _items = [..._items, ...extra];
    }

    if (_isDaily) {
      // The daily challenge must give every learner at this level the same
      // round, so it always uses the level's canonical kinds — never a
      // caller-supplied or personal kind filter (widget.kinds), which would
      // silently fork the "whole world plays one set" guarantee.
      _questions = QuestionFactory.daily(
        pool: _pool,
        kinds: kindsFor(cefr),
        day: DateTime.now(),
        cefr: cefr,
        count: 12,
        nativeLang: lang,
      );
      return;
    }

    _questions = QuestionFactory.build(
      items: _items,
      pool: _pool,
      kinds: kinds,
      count: switch (widget.mode) {
        PlayMode.marathon   => 25,
        PlayMode.timeAttack => 40,
        PlayMode.tournament => 12,
        // A chosen length wins for the modes that end on a count.
        _                   => widget.count ?? 10,
      },
      nativeLang: lang,
    );
  }

  /// Marathon and time attack never run out — top the queue back up.
  void _extendIfNeeded() {
    if (!(_isMarathon || _isTimeAttack)) return;
    if (_index < _questions.length - 3) return;

    final profile = ref.read(myProfileProvider).valueOrNull;
    final more = QuestionFactory.build(
      items: _items,
      pool: _pool,
      kinds: widget.kinds ?? kindsFor(profile?.cefrLevel ?? 'A1'),
      count: 20,
      nativeLang: ref.read(nativeLangProvider),
    );
    if (more.isNotEmpty) _questions = [..._questions, ...more];
  }

  void _startTimers() {
    _ticker?.cancel();
    if (!_isTimeAttack) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _finish();
      }
    });
  }

  void _maybeSpeak() {
    final q = _current;
    if (q == null) return;
    if (q.kind == QKind.listening && (q.speakText ?? '').isNotEmpty) {
      Speech.instance.say(q.speakText!);
    }
  }

  Question? get _current =>
      _index < _questions.length ? _questions[_index] : null;

  // ── answering ────────────────────────────────────────────

  void _answer(String choice) {
    if (_revealed) return;
    final q = _current;
    if (q == null) return;

    final ok = q.isCorrect(choice);
    final ms = DateTime.now().difference(_questionStart).inMilliseconds;

    HapticFeedback.mediumImpact();

    setState(() {
      _picked = choice;
      _revealed = true;
      _skipped = false;
      _elapsedMs += ms;
      _log.add(AnswerLog(
        correct: ok, ms: ms, kind: q.kind, wordId: q.wordId));

      if (ok) {
        _correct++;
        _combo++;
        _bestCombo = max<int>(_bestCombo, _combo);
        final int speedBonus = _isTimeAttack && ms < 3000 ? 5 : 0;
        _score += 10 + min<int>(_combo * 2, 20) + speedBonus;
      } else {
        _combo = 0;
        _wrong.add(q);
        if (_isMarathon) _lives--;
      }
    });

    // Timed modes still need to keep moving, so they advance themselves —
    // every other mode waits for the learner to press "Келесі". The question
    // index is captured now so a stale timer (from a question the learner
    // already left via a manual "Келесі" tap) can tell it no longer applies
    // and bail out instead of yanking past whatever question is current now.
    if (_isTimeAttack) {
      final scheduledIndex = _index;
      Future.delayed(const Duration(milliseconds: 520), () {
        if (mounted && _revealed && _index == scheduledIndex) _next();
      });
    }
  }

  void _skip() {
    if (_revealed) return;
    final q = _current;
    if (q == null) return;
    final ms = DateTime.now().difference(_questionStart).inMilliseconds;
    setState(() {
      _picked = null;
      _revealed = true;
      _skipped = true;
      _combo = 0;
      _elapsedMs += ms;
      _wrong.add(q);
      _log.add(AnswerLog(
        correct: false, ms: ms, kind: q.kind, wordId: q.wordId));
    });
  }

  void _fiftyFifty() {
    final q = _current;
    if (q == null || _fiftyUsed || _revealed || q.options.length < 4) return;
    final wrong = q.options.where((o) => !q.isCorrect(o)).toList()..shuffle();
    setState(() {
      _fiftyUsed = true;
      _hidden = wrong.take(2).toSet();
      _score = max(0, _score - 5);
    });
    HapticFeedback.selectionClick();
  }

  void _hint() {
    final q = _current;
    if (q == null || _revealed) return;
    final answer = q.answer.trim();
    final head = answer.isEmpty
        ? '—'
        : answer.characters.take(max(1, answer.characters.length ~/ 3)).toString();
    setState(() {
      if (!_hintUsed) _score = max(0, _score - 5);
      _hintUsed = true;
    });
    sqSnack(context, trp('Кеңес: «{s}…» деп басталады', {'s': head}));
  }

  Future<void> _bookmark() async {
    final q = _current;
    if (q?.wordId == null) {
      sqSnack(context, tr('Бұл сөз әлі сөздігіңде жоқ'), error: true);
      return;
    }
    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];
    final already = words.any((w) => w.id == q!.wordId && w.isFavorite);
    if (already) {
      sqSnack(context, tr('Бұл сөз таңдаулыда бар'));
      return;
    }
    try {
      await ref.read(wordsRepoProvider).toggleFavorite(q!.wordId!, true);
      ref.invalidate(myWordsProvider);
      if (mounted) sqSnack(context, tr('Таңдаулыға қосылды'));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  void _next() {
    if (_isMarathon && _lives <= 0) { _offerRevive(); return; }
    _extendIfNeeded();
    if (_index + 1 >= _questions.length) { _finish(); return; }
    setState(() {
      _index++;
      _picked = null;
      _revealed = false;
      _skipped = false;
      _hidden = {};
      _fiftyUsed = false;
      _hintUsed = false;
      _chosenLetters.clear();
      _questionStart = DateTime.now();
    });
    _maybeSpeak();
  }

  void _submitSpelling() {
    final q = _current;
    if (q == null || _revealed) return;
    final built = _chosenLetters
        .where((i) => i >= 0 && i < q.letters.length)
        .map((i) => q.letters[i])
        .join();
    _answer(built);
  }

  /// Out of lives: offer one more in exchange for a rewarded ad.
  ///
  /// Nothing is offered when no ad can be shown — on the web build, or with no
  /// fill — so the run simply ends as it always did rather than dangling a
  /// button that cannot work.
  Future<void> _offerRevive() async {
    if (!AdsService.instance.supported) { _finish(); return; }

    final take = await sqConfirm(context,
      title: tr('Жандарың бітті'),
      message: tr('Жарнама көріп, тағы бір жан ал. '
          'XP берілмейді — рейтинг таза қалады'),
      confirm: tr('Жарнама көру'),
      cancel: tr('Аяқтау'),
      danger: false);
    if (!mounted) return;
    if (!take) { _finish(); return; }

    final outcome = await AdsService.instance.showRewardedOutcome();
    if (!mounted) return;

    if (!outcome.grantsReward) {
      final msg = outcome.message;
      if (msg != null) sqSnack(context, tr(msg));
      _finish();
      return;
    }

    setState(() { _lives = 1; _revived = true; });
    _next();
  }

  // ── finishing ────────────────────────────────────────────

  Future<void> _finish() async {
    if (_finished) return;
    _ticker?.cancel();
    setState(() { _finished = true; _submitting = true; });

    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';
    _levelBefore = profile?.levelNumber ?? 1;

    try {
      // Spaced repetition + XP for anything tied to real words.
      if (_log.isNotEmpty && widget.mode != PlayMode.daily) {
        await ref.read(wordsRepoProvider).recordQuiz(
          _log, game: widget.mode.id, xp: _score);
      }

      switch (widget.mode) {
        case PlayMode.marathon:
          // Skipped for a revived run: see [_revived].
          if (!_revived) {
            final (_, best, record) = await ref
                .read(boardRepoProvider)
                .submitGameScore('marathon', _score,
                    meta: {'correct': _correct, 'combo': _bestCombo});
            _best = best; _isRecord = record;
          }

        case PlayMode.timeAttack:
          final (_, best, record) = await ref
              .read(boardRepoProvider)
              .submitGameScore('time_attack', _score,
                  meta: {'correct': _correct, 'combo': _bestCombo});
          _best = best; _isRecord = record;

        case PlayMode.daily:
          final (rank, players) = await ref.read(boardRepoProvider).submitDaily(
            cefr: cefr, score: _score, correct: _correct,
            total: _questions.length, ms: _elapsedMs);
          _rank = rank; _players = players;
          ref.invalidate(playedDailyProvider);
          ref.invalidate(dailyBoardProvider);

        case PlayMode.tournament:
          if (widget.tournamentId != null) {
            await ref.read(boardRepoProvider)
                .submitTournamentRound(widget.tournamentId!, _score);
            ref.invalidate(tournamentBoardProvider(widget.tournamentId!));
          }

        default:
          break;
      }

      await ref.read(eventsRepoProvider).bumpByMetric(cefr, 'rounds');

      refreshAll(ref);
      final fresh = ref.read(myProfileProvider).valueOrNull;
      if (fresh != null) {
        _levelAfter = fresh.levelNumber;
        _levelProgress = fresh.levelProgress;
        _unlocked = await AchievementService.instance.check(fresh);
      }
    } catch (e) {
      _error = humanError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  int _best = 0;
  bool _isRecord = false;
  int _rank = 0;
  int _players = 0;
  int _levelBefore = 1;
  int _levelAfter = 1;
  double _levelProgress = 0;
  List<Achievement> _unlocked = const [];

  PlayOutcome get _outcome => PlayOutcome(
    score: _score,
    correct: _correct,
    total: _log.isEmpty ? _questions.length : _log.length,
    bestCombo: _bestCombo,
  );

  void _close() => Navigator.of(context).pop(_outcome);

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // repaint on a language switch
    ref.watch(langProvider);
    final d = isDark(context);

    return PopScope(
      canPop: _finished || _loading,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final quit = await sqConfirm(context,
          title: tr('Ойыннан шығу'),
          message: tr('Нәтиже сақталмайды. Шығасың ба?'),
          confirm: tr('Шығу'));
        if (quit && mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg(d),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _questions.isEmpty
                  ? _NotEnough(message: _error!)
                  : _finished
                      ? _ResultView(
                          mode: widget.mode,
                          title: widget.title,
                          score: _score,
                          correct: _correct,
                          total: _log.isEmpty ? _questions.length : _log.length,
                          bestCombo: _bestCombo,
                          elapsedMs: _elapsedMs,
                          best: _best,
                          isRecord: _isRecord,
                          rank: _rank,
                          players: _players,
                          levelBefore: _levelBefore,
                          levelAfter: _levelAfter,
                          levelProgress: _levelProgress,
                          unlocked: _unlocked,
                          submitting: _submitting,
                          wrong: _wrong,
                          onAgain: _questions.isEmpty ? null : _restart,
                          onReviewWrong: _wrong.isEmpty ? null : _drillWrong,
                          onClose: _close,
                        )
                      : _playing(d),
        ),
      ),
    );
  }

  /// Replays only the questions that were missed. It runs as a review round,
  /// so the answers still feed spaced repetition but nothing is submitted to a
  /// leaderboard a second time.
  void _drillWrong() {
    final questions = List<Question>.from(_wrong);
    if (questions.isEmpty) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PlaySessionScreen(
        mode: PlayMode.review, preset: questions,
        title: tr('Қате сөздер')),
    ));
  }

  void _restart() {
    setState(() {
      _index = 0; _score = 0; _correct = 0; _combo = 0; _bestCombo = 0;
      _lives = _marathonLives; _secondsLeft = _timeAttackSeconds;
      _elapsedMs = 0; _picked = null; _revealed = false; _skipped = false;
      _finished = false; _isRecord = false; _rank = 0; _players = 0;
      _hidden = {}; _fiftyUsed = false; _hintUsed = false;
      _unlocked = const [];
      _log.clear(); _chosenLetters.clear(); _wrong.clear();
    });
    _load();
  }

  Widget _playing(bool d) {
    final q = _current!;
    final isSpelling = q.kind == QKind.spelling && q.letters.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: _TopRail(
            index: _index,
            total: _questions.length,
            mode: widget.mode,
            title: widget.title,
            lives: _isMarathon ? _lives : null,
            secondsLeft: _isTimeAttack ? _secondsLeft : null,
            onQuit: () async {
              final quit = await sqConfirm(context,
                title: tr('Ойыннан шығу'),
                message: tr('Нәтиже сақталмайды. Шығасың ба?'),
                confirm: tr('Шығу'));
              if (quit && mounted) Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              SqChip(tr(q.kind.short),
                icon: _kindIcon(q.kind),
                tint: AppColors.primary,
                radius: 999,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11, vertical: 7)),
              const Spacer(),
              if (_combo >= 2) ...[
                SqRise(
                  key: ValueKey(_combo),
                  offset: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.inkBlock(d),
                      borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(PhosphorIconsFill.lightning,
                          size: 13, color: AppColors.amber),
                        const SizedBox(width: 5),
                        SqNum(trp('КОМБО × {n}', {'n': '$_combo'}),
                          size: 11.5, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 9),
              ],
              SqNum('${_index + 1}/${_questions.length}',
                size: 11.5, color: AppColors.text3(d)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Column(
              children: [
                _Prompt(question: q),
                const SizedBox(height: 15),
                if (isSpelling)
                  SpellingPad(
                    question: q,
                    chosen: _chosenLetters,
                    revealed: _revealed,
                    onPick: (i) => setState(() => _chosenLetters.add(i)),
                    onUndo: () => setState(() {
                      if (_chosenLetters.isNotEmpty) _chosenLetters.removeLast();
                    }),
                    onSubmit: _submitSpelling,
                  )
                else
                  for (var i = 0; i < q.options.length; i++) ...[
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _hidden.contains(q.options[i]) ? 0.25 : 1,
                      child: SqAnswer(
                        text: q.options[i],
                        badge: String.fromCharCode(65 + i),
                        revealed: _revealed || _hidden.contains(q.options[i]),
                        isCorrect: _revealed && q.isCorrect(q.options[i]),
                        isPicked: q.options[i] == _picked,
                        onTap: _hidden.contains(q.options[i])
                            ? null
                            : () => _answer(q.options[i]),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
          child: _revealed
              ? _Verdict(
                  key: ValueKey(_index),
                  correct: !_skipped && _picked != null && q.isCorrect(_picked!),
                  skipped: _skipped,
                  answer: q.answer,
                  detail: q.subPrompt,
                  combo: _combo,
                  xp: _skipped || _picked == null || !q.isCorrect(_picked!)
                      ? 0 : 10 + min(_combo * 2, 20),
                  last: _index + 1 >= _questions.length && !_isMarathon
                      && !_isTimeAttack,
                  onNext: _next,
                )
              : _Lifelines(
                  fiftyUsed: _fiftyUsed,
                  fiftyAvailable: q.options.length >= 4,
                  bookmarkable: q.wordId != null,
                  onSkip: _skip,
                  onFifty: _fiftyFifty,
                  onHint: _hint,
                  onBookmark: _bookmark,
                ),
        ),
      ],
    );
  }

  static IconData _kindIcon(QKind k) => switch (k) {
    QKind.kkEn       => PhosphorIconsFill.translate,
    QKind.enKk       => PhosphorIconsFill.arrowsLeftRight,
    QKind.definition => PhosphorIconsFill.bookOpenText,
    QKind.synonym    => PhosphorIconsFill.link,
    QKind.antonym    => PhosphorIconsFill.arrowsLeftRight,
    QKind.listening  => PhosphorIconsFill.headphones,
    QKind.spelling   => PhosphorIconsFill.keyboard,
    QKind.sentence   => PhosphorIconsFill.textAlignLeft,
  };
}

// ── Top rail ───────────────────────────────────────────────

class _TopRail extends StatelessWidget {
  final int index, total;
  final PlayMode mode;
  final String? title;
  final int? lives, secondsLeft;
  final VoidCallback onQuit;

  const _TopRail({
    required this.index, required this.total,
    required this.mode, required this.title,
    required this.onQuit, this.lives, this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final beads = total.clamp(1, 12);
    final scaled = total <= beads ? index : (index * beads ~/ total);

    return Row(
      children: [
        SqSquareButton(PhosphorIconsBold.x, onTap: onQuit),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The four modes with neither lives nor a timer are otherwise
              // pixel-identical during play — this is the only thing on
              // screen that says which one you're in.
              SqEyebrow(tr(title ?? mode.title)),
              const SizedBox(height: 6),
              SqBeads(
                total: beads,
                done: scaled.clamp(0, beads),
                current: scaled.clamp(0, beads - 1),
                height: 7,
              ),
            ],
          ),
        ),
        const SizedBox(width: 11),
        if (secondsLeft != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.soft(
                secondsLeft! <= 10 ? AppColors.red : AppColors.primary, d),
              borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsFill.timer,
                  size: 14,
                  color: secondsLeft! <= 10 ? AppColors.red : AppColors.primary),
                const SizedBox(width: 5),
                SqNum('$secondsLeft',
                  size: 12,
                  color: AppColors.onSoft(
                    secondsLeft! <= 10 ? AppColors.red : AppColors.primary, d)),
              ],
            ),
          )
        else if (lives != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.soft(AppColors.red, d),
              borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lives!.clamp(0, 5); i++)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                    child: const Icon(PhosphorIconsFill.heart,
                      size: 14, color: AppColors.red),
                  ),
                if (lives! <= 0)
                  const Icon(PhosphorIconsBold.heartBreak,
                    size: 14, color: AppColors.red),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Prompt: the dark focus block ───────────────────────────

class _Prompt extends StatelessWidget {
  final Question question;
  const _Prompt({required this.question});

  @override
  Widget build(BuildContext context) {
    final q = question;
    final isListening = q.kind == QKind.listening;
    final long = q.prompt.length > 34;

    return SqInkCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      glowAt: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(tr(q.kind.prompt),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700,
              color: AppColors.onInk2)),
          const SizedBox(height: 14),
          if (isListening)
            GestureDetector(
              onTap: () => Speech.instance.say(q.speakText ?? ''),
              child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [BoxShadow(
                    color: AppColors.primaryDeep,
                    offset: Offset(0, 5), blurRadius: 0)],
                ),
                child: const Icon(PhosphorIconsFill.speakerHigh,
                  size: 38, color: Colors.white),
              ),
            )
          else
            Text(q.prompt,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: long ? 24 : 38,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: long ? -0.6 : -1.2,
                color: Colors.white)),
          if ((q.subPrompt ?? '').isNotEmpty && !isListening) ...[
            const SizedBox(height: 8),
            Text(q.subPrompt!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600,
                color: AppColors.onInk2)),
          ],
          if (!isListening && (q.speakText ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _InkChip(
              icon: PhosphorIconsFill.speakerHigh,
              label: tr('Тыңдау'),
              onTap: () => Speech.instance.say(q.speakText!)),
          ],
        ],
      ),
    );
  }
}

class _InkChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InkChip({
    required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 7),
          Text(label,
            style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    ),
  );
}

// ── Lifelines row ──────────────────────────────────────────

class _Lifelines extends StatelessWidget {
  final bool fiftyUsed, fiftyAvailable, bookmarkable;
  final VoidCallback onSkip, onFifty, onHint, onBookmark;

  const _Lifelines({
    required this.fiftyUsed, required this.fiftyAvailable,
    required this.bookmarkable,
    required this.onSkip, required this.onFifty,
    required this.onHint, required this.onBookmark});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Row(
      children: [
        Expanded(
          child: SqAction(tr('Өткізу'),
            icon: PhosphorIconsBold.skipForward,
            tone: SqTone.ghost,
            height: 50,
            onTap: onSkip),
        ),
        const SizedBox(width: 10),
        Opacity(
          opacity: fiftyUsed || !fiftyAvailable ? 0.4 : 1,
          child: SqLip(
            fill: AppColors.card(d),
            border: AppColors.border(d),
            borderWidth: 1.5,
            lip: AppColors.surfaceLip(d),
            depth: 3,
            radius: 16,
            onTap: fiftyUsed || !fiftyAvailable ? null : onFifty,
            child: SizedBox(
              width: 50, height: 50,
              child: Center(
                child: SqNum('50:50', size: 11.5, color: AppColors.text2(d))),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SqLip(
          fill: AppColors.card(d),
          border: AppColors.border(d),
          borderWidth: 1.5,
          lip: AppColors.surfaceLip(d),
          depth: 3,
          radius: 16,
          onTap: onHint,
          child: const SizedBox(
            width: 50, height: 50,
            child: Icon(PhosphorIconsFill.lightbulb,
              size: 19, color: AppColors.amber),
          ),
        ),
        const SizedBox(width: 10),
        Opacity(
          opacity: bookmarkable ? 1 : 0.4,
          child: SqLip(
            fill: AppColors.card(d),
            border: AppColors.border(d),
            borderWidth: 1.5,
            lip: AppColors.surfaceLip(d),
            depth: 3,
            radius: 16,
            onTap: bookmarkable ? onBookmark : null,
            child: SizedBox(
              width: 50, height: 50,
              child: Icon(PhosphorIconsBold.bookmarkSimple,
                size: 18, color: AppColors.text2(d)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Verdict panel ──────────────────────────────────────────

class _Verdict extends StatelessWidget {
  final bool correct, skipped, last;
  final String answer;
  final String? detail;
  final int combo, xp;
  final VoidCallback onNext;

  const _Verdict({
    super.key,
    required this.correct,
    required this.skipped,
    required this.answer,
    required this.detail,
    required this.combo,
    required this.xp,
    required this.last,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = correct ? AppColors.green : AppColors.red;

    return SqRise(
      offset: 18,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.soft(tint, d),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tint, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  correct
                      ? PhosphorIconsFill.checkCircle
                      : PhosphorIconsFill.xCircle,
                  size: 26, color: tint),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        correct
                            ? (combo >= 3
                                ? trp('Дәл тауып тұрсың! Комбо × {n}',
                                    {'n': '$combo'})
                                : tr('Дәл тауып тұрсың!'))
                            : skipped
                                ? trp('Өткізілді. Дұрысы: {w}', {'w': answer})
                                : trp('Дұрысы: {w}', {'w': answer}),
                        style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppColors.onSoft(tint, d))),
                      if ((detail ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(detail!,
                          style: TextStyle(
                            fontSize: 12, height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSoft(tint, d)
                                .withValues(alpha: 0.85))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.card(d).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8)),
                  child: SqNum('+$xp XP',
                    size: 12, color: AppColors.onSoft(tint, d)),
                ),
              ],
            ),
            const SizedBox(height: 13),
            SqAction(last ? tr('Нәтижені көру') : tr('Келесі'),
              tone: SqTone.ink,
              height: 52,
              trailingIcon: PhosphorIconsBold.arrowRight,
              onTap: onNext),
          ],
        ),
      ),
    );
  }
}

// ── Result ─────────────────────────────────────────────────

class _ResultView extends ConsumerWidget {
  final PlayMode mode;
  final String? title;
  final int score, correct, total, bestCombo, elapsedMs;
  final int best, rank, players, levelBefore, levelAfter;
  final double levelProgress;
  final bool isRecord, submitting;
  final List<Achievement> unlocked;
  final List<Question> wrong;
  final VoidCallback? onAgain, onReviewWrong;
  final VoidCallback onClose;

  const _ResultView({
    required this.mode, required this.title, required this.score,
    required this.correct, required this.total, required this.bestCombo,
    required this.elapsedMs, required this.best, required this.isRecord,
    required this.rank, required this.players,
    required this.levelBefore, required this.levelAfter,
    required this.levelProgress,
    required this.unlocked, required this.submitting, required this.wrong,
    required this.onAgain, required this.onReviewWrong, required this.onClose,
  });

  String get _headline {
    if (isRecord) return tr('Жаңа рекорд!');
    if (total == 0) return tr('Раунд аяқталды');
    final r = correct / total;
    if (r >= 0.9) return tr('Керемет!');
    if (r >= 0.7) return tr('Жақсы жұмыс!');
    if (r >= 0.5) return tr('Жаман емес');
    return tr('Тағы жаттық!');
  }

  String get _clock {
    final s = (elapsedMs / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final accuracy = total == 0 ? 0 : ((correct / total) * 100).round();
    final levelled = levelAfter > levelBefore;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
      children: [
        SqRise(
          child: SqInkCard(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            glow: correct >= total * 0.7 ? AppColors.green : AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SqFloat(
                      child: Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: isRecord
                              ? AppColors.amber
                              : correct >= total * 0.7
                                  ? AppColors.green
                                  : AppColors.primary,
                          borderRadius: BorderRadius.circular(19)),
                        child: Icon(
                          isRecord
                              ? PhosphorIconsFill.crownSimple
                              : PhosphorIconsFill.trophy,
                          size: 28, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SqEyebrow(tr(title ?? tr('Раунд бітті')),
                            color: AppColors.onInk2),
                          const SizedBox(height: 2),
                          Text(_headline,
                            style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800,
                              letterSpacing: -0.5, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: SqInkStat('$correct/$total',
                      trp('дәлдік {n}%', {'n': '$accuracy'}))),
                    const SizedBox(width: 9),
                    Expanded(child: SqInkStat('×$bestCombo',
                      tr('ең үлкен комбо'), valueColor: AppColors.amber)),
                    const SizedBox(width: 9),
                    Expanded(child: SqInkStat(_clock, tr('уақыт'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        SqPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(PhosphorIconsFill.star,
                    size: 18, color: AppColors.amber),
                  const SizedBox(width: 9),
                  Text(trp('+{n} XP жиналды', {'n': '$score'}),
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800,
                      color: AppColors.text(d))),
                  const Spacer(),
                  SqNum(
                    levelled
                        ? 'LVL $levelBefore → $levelAfter'
                        : 'LVL $levelAfter',
                    size: 11.5, color: AppColors.text3(d)),
                ],
              ),
              const SizedBox(height: 12),
              SqTrack(levelProgress, height: 9),
              const SizedBox(height: 12),
              Wrap(spacing: 7, runSpacing: 7, children: [
                SqBadge(trp('Раунд +{n}', {'n': '${10 * correct}'}),
                  tint: AppColors.primary),
                if (bestCombo > 1)
                  SqBadge(trp('Комбо +{n}', {'n': '${bestCombo * 2}'}),
                    tint: AppColors.green),
                if (isRecord) SqBadge(tr('Рекорд'), tint: AppColors.amber),
                if (best > 0)
                  SqBadge(trp('Рекордың {n}', {'n': '$best'}),
                    tint: AppColors.amber),
                if (players > 0)
                  SqBadge(
                    trp('Глобал {r} / {p}', {'r': '$rank', 'p': '$players'}),
                    tint: AppColors.sky),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (levelled)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SqPanel(
              fill: AppColors.soft(AppColors.primary, d),
              border: AppColors.line(AppColors.primary, d),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SqTintBox(PhosphorIconsFill.medal,
                    size: 40, solid: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trp('{n}-деңгейге көтерілдің', {'n': '$levelAfter'}),
                          style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800,
                            color: AppColors.text(d))),
                        Text(tr('Миссия жолында жаңа сыйлық ашылды'),
                          style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: AppColors.onSoft(AppColors.primary, d))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (unlocked.isNotEmpty) ...[
          SqSection(tr('Жаңа жетістік')),
          SqGroup(children: [
            for (final a in unlocked)
              SqTile(
                leading: const SqTintBox(PhosphorIconsFill.sealCheck,
                  tint: AppColors.amber, size: 38),
                title: tr(a.title),
                subtitle: tr(a.description),
                trailing: SqBadge('+${a.xp} XP', tint: AppColors.amber),
              ),
          ]),
          const SizedBox(height: 14),
        ],

        if (wrong.isNotEmpty) ...[
          SqSection(tr('Қате кеткен сөздер'),
            trailingWidget: SqNum(trp('{n} сөз', {'n': '${wrong.length}'}),
              size: 11, color: AppColors.text3(d))),
          SqGroup(children: [
            for (final q in wrong.take(6))
              SqTile(
                leading: const SqTintBox(
                  PhosphorIconsBold.arrowCounterClockwise,
                  tint: AppColors.red, size: 34),
                title: q.answer,
                subtitle: q.prompt,
              ),
          ]),
          const SizedBox(height: 16),
        ],

        if (submitting)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator()))
        else ...[
          if (onReviewWrong != null) ...[
            SqAction(trp('Осы {n} сөзді қайталау', {'n': '${wrong.length}'}),
              icon: PhosphorIconsFill.arrowsClockwise,
              onTap: onReviewWrong),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (onAgain != null) ...[
                Expanded(
                  child: SqAction(tr('Тағы ойнау'),
                    tone: SqTone.ghost, height: 48, onTap: onAgain)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SqAction(tr('Басты бет'),
                  tone: SqTone.ghost, height: 48, onTap: onClose)),
            ],
          ),
        ],
      ],
    );
  }
}

class _NotEnough extends StatelessWidget {
  final String message;
  const _NotEnough({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: SqEmpty(
      icon: PhosphorIconsFill.books,
      title: message,
      subtitle: tr(S.needMoreSub),
      action: SizedBox(
        width: 220,
        child: SqAction(tr(S.back),
          tone: SqTone.ghost,
          onTap: () => Navigator.of(context).pop()),
      ),
    ),
  );
}
