// lib/features/arena/tournament_run_screen.dart
//
// A survival run (EN-23 / KK-4).
//
// A tournament round used to be PlayMode.tournament, which is
// PlayMode.classic with a different label and a different place to post the
// score. "Tournament must not feel like another Classic Test" is the PRD's
// wording, and it was right: nothing about it was different.
//
// Survival is the one shape nothing else in this app has — a run you can LOSE,
// and a decision about whether to risk what you have already earned. Between
// waves the learner is asked to bank or push on, and that choice is the mode.
// Everything else here exists to make it a real one: the clock shortens every
// wave so pushing genuinely gets harder, and lives are counted per day rather
// than per run so a lost life costs something.
//
// Lives are spent server-side. Held on the device they would reset with a
// reinstall, and a survival mode with unlimited retries is not one.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/question.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/question_factory.dart';

/// Six questions to a wave. Short enough that "one more wave" is a small ask,
/// long enough that surviving one means something.
const _waveSize = 6;
const _maxWave = 10;

/// Wave 1 gives twelve seconds a question, wave 8 and beyond give five. Mirrors
/// wave_seconds() in v5_tournament_survival.sql — the two must agree or the
/// difficulty the learner feels is not the one the board is ranking.
int waveSeconds(int wave) => max(5, 13 - max(1, wave));

class TournamentRunScreen extends ConsumerStatefulWidget {
  final int tournamentId;
  final String title;
  const TournamentRunScreen({
    super.key, required this.tournamentId, required this.title});

  @override
  ConsumerState<TournamentRunScreen> createState() =>
      _TournamentRunScreenState();
}

enum _Phase { loading, playing, betweenWaves, lost, banked, noLives, error }

class _TournamentRunScreenState extends ConsumerState<TournamentRunScreen> {
  _Phase _phase = _Phase.loading;
  String? _error;

  int _wave = 1;
  int _inWave = 0;
  int _score = 0;
  int _livesLeft = 3;

  List<Question> _questions = const [];
  int _index = 0;
  String? _picked;
  bool _revealed = false;

  int _secondsLeft = 12;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(busyProvider.notifier).state = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  /// See the note on the same override in play_session_screen: `ref` is dead
  /// by the time dispose() runs.
  @override
  void deactivate() {
    ref.read(busyProvider.notifier).state = false;
    super.deactivate();
  }

  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  Future<void> _begin() async {
    try {
      final state = await ref.read(boardRepoProvider)
          .tournamentState(widget.tournamentId);
      if (!mounted) return;
      _livesLeft = state.livesLeft;
      if (_livesLeft <= 0) {
        setState(() => _phase = _Phase.noLives);
        return;
      }
      await _buildWave();
    } catch (e) {
      if (mounted) {
        setState(() { _phase = _Phase.error; _error = humanError(e); });
      }
    }
  }

  Future<void> _buildWave() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';

    var pool = ref.read(levelPoolProvider).valueOrNull ?? const <DictEntry>[];
    if (pool.length < 12) {
      pool = await ref.read(dictRepoProvider)
          .pool(cefr: visibleCefrFor(cefr), limit: 120)
          .catchError((_) => <DictEntry>[]);
    }
    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];

    final qs = QuestionFactory.build(
      items: [
        ...words.take(30).map(PlayItem.fromWord),
        ...pool.map(PlayItem.fromDict),
      ],
      pool: pool,
      kinds: kindsFor(cefr),
      count: _waveSize,
      nativeLang: ref.read(nativeLangProvider),
      // Same reason as ranked: a clock this short with audio on it is not a
      // harder question, it is an unplayable one.
      exclude: const {QKind.listening},
    );

    if (!mounted) return;
    if (qs.isEmpty) {
      setState(() {
        _phase = _Phase.error;
        _error = tr('Сұрақ құрастыру мүмкін болмады');
      });
      return;
    }

    setState(() {
      _questions = qs;
      _index = 0;
      _inWave = 0;
      _picked = null;
      _revealed = false;
      _phase = _Phase.playing;
    });
    _startClock();
  }

  void _startClock() {
    _tick?.cancel();
    setState(() => _secondsLeft = waveSeconds(_wave));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        // Running out is a wrong answer. A survival clock that merely skips
        // the question is not a clock.
        _answer(null);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _answer(String? choice) {
    if (_revealed) return;
    _tick?.cancel();
    final q = _questions[_index];
    final right = choice != null && choice == q.answer;

    HapticFeedback.mediumImpact();
    setState(() { _picked = choice; _revealed = true; });

    if (!right) {
      Future.delayed(const Duration(milliseconds: 900), _loseRun);
      return;
    }

    setState(() {
      // A deeper wave is worth more, which is what makes pushing on tempting
      // rather than merely risky.
      _score += 10 + _wave * 2 + _secondsLeft;
      _inWave++;
    });

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (_inWave >= _waveSize) {
        _tick?.cancel();
        setState(() => _phase = _Phase.betweenWaves);
        return;
      }
      setState(() {
        _index++;
        _picked = null;
        _revealed = false;
      });
      _startClock();
    });
  }

  Future<void> _loseRun() async {
    if (!mounted || _phase != _Phase.playing) return;
    _tick?.cancel();
    setState(() => _phase = _Phase.lost);
    await _submit(lost: true);
  }

  Future<void> _bank() async {
    _tick?.cancel();
    setState(() => _phase = _Phase.banked);
    await _submit(lost: false);
  }

  Future<void> _pushOn() async {
    if (_wave >= _maxWave) {
      await _bank();
      return;
    }
    setState(() => _wave++);
    await _buildWave();
  }

  Future<void> _submit({required bool lost}) async {
    try {
      final res = await ref.read(boardRepoProvider).submitTournamentRun(
        widget.tournamentId,
        // A lost run banks the waves already survived, not the one it died in.
        wave: lost ? _wave - 1 : _wave,
        score: _score,
        lost: lost);
      if (mounted) setState(() => _livesLeft = res.livesLeft);
      refreshAll(ref);
      ref.invalidate(tournamentBoardProvider(widget.tournamentId));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    return Scaffold(
      backgroundColor: _phase == _Phase.playing
          ? AppColors.ink : AppColors.bg(d),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading      => const Center(child: CircularProgressIndicator()),
          _Phase.error        => _message(d,
              icon: PhosphorIconsFill.warningCircle,
              tint: AppColors.red,
              title: tr('Раунд басталмады'),
              body: _error ?? '',
              action: tr('Жабу')),
          _Phase.noLives      => _message(d,
              icon: PhosphorIconsFill.heartBreak,
              tint: AppColors.red,
              title: tr('Бүгінгі өмірлерің бітті'),
              body: tr('Ертең үш өмірмен қайта кел'),
              action: tr('Жабу')),
          _Phase.playing      => _playing(),
          _Phase.betweenWaves => _decision(d),
          _Phase.lost         => _message(d,
              icon: PhosphorIconsFill.skull,
              tint: AppColors.red,
              title: trp('{n}-толқында құладың', {'n': '$_wave'}),
              body: trp('{n} ұпай жинадың · {l} өмір қалды',
                {'n': '$_score', 'l': '$_livesLeft'}),
              action: tr('Жабу')),
          _Phase.banked       => _message(d,
              icon: PhosphorIconsFill.trophy,
              tint: AppColors.green,
              title: trp('{n} толқыннан өттің', {'n': '$_wave'}),
              body: trp('{n} ұпай сақталды · {l} өмір қалды',
                {'n': '$_score', 'l': '$_livesLeft'}),
              action: tr('Жабу')),
        },
      ),
    );
  }

  Widget _playing() {
    final q = _questions[_index];
    final secs = waveSeconds(_wave);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: Row(
            children: [
              SqSquareButton(PhosphorIconsBold.x,
                size: 36,
                fill: AppColors.inkBlock(true),
                lip: AppColors.inkBlockLip(true),
                iconColor: Colors.white,
                onTap: _loseRun),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SqEyebrow(trp('{n}-толқын', {'n': '$_wave'}),
                      color: AppColors.onInk2),
                    const SizedBox(height: 4),
                    SqBeads(
                      total: _waveSize,
                      done: _inWave,
                      doneColor: AppColors.amber,
                      pending: AppColors.inkTrack),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // The clock is the whole tension of the mode, so it is the
              // largest number on the screen after the question.
              SqNum('$_secondsLeft',
                size: 22,
                color: _secondsLeft <= 3 ? AppColors.red : Colors.white),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SqTrack(_secondsLeft / secs,
            color: _secondsLeft <= 3 ? AppColors.red : AppColors.amber,
            background: AppColors.inkTrack,
            height: 4),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
            children: [
              Text(q.prompt,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800,
                  letterSpacing: -0.6, color: Colors.white)),
              const SizedBox(height: 28),
              for (var i = 0; i < q.options.length; i++) ...[
                SqAnswer(
                  text: q.options[i],
                  badge: String.fromCharCode(65 + i),
                  revealed: _revealed,
                  isCorrect: q.options[i] == q.answer,
                  isPicked: q.options[i] == _picked,
                  onTap: _revealed ? null : () => _answer(q.options[i])),
                const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The decision the whole mode is built around.
  Widget _decision(bool d) => SqPage(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
    children: [
      const SizedBox(height: 24),
      Center(
        child: SqFloat(
          child: Container(
            width: 78, height: 78,
            decoration: BoxDecoration(
              color: AppColors.amber,
              borderRadius: BorderRadius.circular(26)),
            child: const Icon(PhosphorIconsFill.shieldCheck,
              size: 38, color: Colors.white),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(trp('{n}-толқыннан аман өттің', {'n': '$_wave'}),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w800,
          letterSpacing: -0.5, color: AppColors.text(d))),
      const SizedBox(height: 6),
      Text(trp('Қолыңда {n} ұпай', {'n': '$_score'}),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700,
          color: AppColors.text2(d))),
      const SizedBox(height: 22),

      // What pushing on actually costs, stated as numbers. A gamble nobody
      // can price is not a decision, it is a coin toss with extra steps.
      SqPanel(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const SqTintBox(PhosphorIconsFill.timer,
              tint: AppColors.red, size: 34),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                trp('Келесі толқында әр сұраққа {n} секунд · қате жауап '
                    'раундты бітіреді',
                  {'n': '${waveSeconds(_wave + 1)}'}),
                style: TextStyle(
                  fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600,
                  color: AppColors.text2(d))),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      SqAction(tr('Әрі қарай'),
        icon: PhosphorIconsFill.fire,
        tone: SqTone.danger,
        height: 56,
        onTap: _pushOn),
      const SizedBox(height: 10),
      SqAction(trp('Тоқтап, {n} ұпайды сақтау', {'n': '$_score'}),
        icon: PhosphorIconsFill.shieldCheck,
        tone: SqTone.ghost,
        height: 52,
        onTap: _bank),
    ],
  );

  Widget _message(bool d, {
    required IconData icon,
    required Color tint,
    required String title,
    required String body,
    required String action,
  }) => SqPage(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
    children: [
      const SizedBox(height: 50),
      Center(
        child: Container(
          width: 82, height: 82,
          decoration: BoxDecoration(
            color: tint, borderRadius: BorderRadius.circular(27)),
          child: Icon(icon, size: 40, color: Colors.white),
        ),
      ),
      const SizedBox(height: 20),
      Text(title,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w800,
          letterSpacing: -0.5, color: AppColors.text(d))),
      if (body.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
      ],
      const SizedBox(height: 30),
      SqAction(action, onTap: () => Navigator.of(context).pop(true)),
    ],
  );
}
