// lib/features/arena/battle_screen.dart
//
// Head-to-head play.
//
// Ranked matches broadcast their running score over a Supabase Realtime
// channel so both players watch the gap move; bot matches simulate an opponent
// locally; friend matches compare final scores whenever the other side gets
// around to playing.
//
// 4.0 turns the whole screen dark and strips it to one job. The complaint
// about 3.0 was never the rules — it was not knowing what the other person was
// doing. Now there are two rails: yours on top, theirs below, one bead per
// round, plus a live "жауап беруде…" marker. You always know whether you are
// ahead, behind, or waiting.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../core/widgets/spelling_pad.dart';
import '../../data/models/battle.dart';
import '../../data/models/invite.dart';
import '../../data/models/profile.dart';
import '../../data/models/question.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/achievements.dart';
import '../../data/repos/cosmetics_repo.dart';
import '../../services/speech.dart';
import '../profile/cosmetic_preview.dart';

/// One finished round, for the post-match table.
class _Round {
  final int n;
  final String word;
  final bool meOk;
  final int meMs;
  final bool? oppOk;
  const _Round(this.n, this.word, this.meOk, this.meMs, this.oppOk);
}

class BattleScreen extends ConsumerStatefulWidget {
  final Battle battle;
  const BattleScreen({super.key, required this.battle});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  /// Picking one of four options is quick; assembling a word letter by letter
  /// is not, so a spelling question gets its own, longer clock.
  static const _perQuestionSeconds = 12;
  static const _spellingSeconds    = 25;

  final _rng = Random();

  late Battle _battle = widget.battle;
  RealtimeChannel? _channel;
  StreamSubscription<Battle?>? _watch;
  Timer? _tick;
  Timer? _botTimer;
  /// Realtime is the fast path for "the opponent finished", but it is not a
  /// guarantee: the socket can drop while the result screen is open and
  /// nothing ever arrives, leaving the learner on "Қарсыласты күтудеміз"
  /// forever with no way forward. This re-reads the row on a timer until the
  /// match is settled, so the wait always ends.
  Timer? _awaitOpp;

  int _index = 0;
  int _score = 0;
  int _correct = 0;
  int _combo = 0;
  int _oppScore = 0;
  int _oppIndex = 0;
  int _secondsLeft = _perQuestionSeconds;
  int _maxSeconds  = _perQuestionSeconds;

  final List<int> _chosenLetters = [];
  final List<AnswerLog> _log = [];
  final List<_Round> _rounds = [];
  /// Per-round outcome for the bot, so the result table can compare turn by
  /// turn instead of only totals.
  final List<bool> _botRounds = [];

  String? _picked;
  bool _revealed = false;
  bool _finished = false;
  bool _submitting = false;
  bool _oppFinished = false;

  /// A rematch has been asked for and the other player has not answered yet.
  bool _rematchWaiting = false;
  Timer? _rematchPoll;

  /// The opponent left and the server awarded this match on their forfeit.
  bool _oppForfeited = false;

  /// Waiting ran out without the match settling at all — the opponent never
  /// submitted and the server would not yet call it. The result screen says
  /// so instead of showing a spinner for ever.
  bool _oppGaveUp = false;

  DateTime _qStart = DateTime.now();
  List<Achievement> _unlocked = const [];

  String get _uid => currentUid ?? '';
  bool get _isBot => _battle.mode == 'bot';

  /// A question nobody can answer (no options and no letters) would just burn
  /// the clock, so it never makes it into the round. The filter is
  /// deterministic, so both players still play the very same set.
  late final List<Question> _questions = widget.battle.questions
      .where((q) => q.options.isNotEmpty || q.letters.isNotEmpty)
      .toList();
  Question? get _current =>
      _index < _questions.length ? _questions[_index] : null;

  String get _oppName => _isBot
      ? (_battle.botName ?? tr('Бот'))
      : (_oppProfileName ?? tr('Қарсылас'));

  String? _oppProfileName;
  String? _oppEmoji;
  int? _oppElo;
  /// What the opponent is wearing. Fetched once with their profile — a second
  /// request per battle for six equip slots that never change mid-match would
  /// be a request per battle for nothing.
  WornCosmetics? _oppWorn;

  @override
  void initState() {
    super.initState();
    // EN-12: nothing may pop over a live question. The invite overlay reads
    // this and holds anything that arrives until the round is over.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(busyProvider.notifier).state = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
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
    _tick?.cancel();
    _botTimer?.cancel();
    _awaitOpp?.cancel();
    _rematchPoll?.cancel();
    _watch?.cancel();
    if (_channel != null) supa.removeChannel(_channel!);
    Speech.instance.stop();
    super.dispose();
  }

  Future<void> _begin() async {
    await _loadOpponent();
    if (!mounted) return;

    if (_isBot) {
      _startBotSimulation();
    } else {
      _joinChannel();
      _watchRow();
    }
    _startQuestionTimer();
    _maybeSpeak();
  }

  Future<void> _loadOpponent() async {
    if (_isBot) return;
    final oppId = _battle.oppId(_uid);
    if (oppId == null) return;
    try {
      final p = await ref.read(profileRepoProvider).byId(oppId);
      if (mounted && p != null) {
        setState(() {
          _oppProfileName = p.name;
          _oppEmoji = p.avatarEmoji;
          _oppElo = p.elo;
        });
      }
      final worn = await ref.read(cosmeticsRepoProvider)
          .worn([oppId])
          .catchError((_) => const <String, WornCosmetics>{});
      if (mounted && worn[oppId] != null) {
        setState(() => _oppWorn = worn[oppId]);
      }
    } catch (_) {/* opponent card just stays generic */}
  }

  // ── realtime ─────────────────────────────────────────────

  void _joinChannel() {
    _channel = supa.channel('battle-${_battle.id}',
        opts: const RealtimeChannelConfig(self: false));
    _channel!
        .onBroadcast(
          event: 'progress',
          callback: (payload) {
            if (!mounted) return;
            final from = payload['from']?.toString();
            if (from == _uid) return;
            setState(() {
              _oppScore = (payload['score'] as num?)?.toInt() ?? _oppScore;
              _oppIndex = (payload['index'] as num?)?.toInt() ?? _oppIndex;
              _oppFinished = payload['done'] == true || _oppFinished;
            });
          },
        )
        .subscribe();
  }

  void _broadcast({bool done = false}) {
    _channel?.sendBroadcastMessage(event: 'progress', payload: {
      'from': _uid, 'score': _score, 'index': _index, 'done': done,
    });
  }

  void _watchRow() {
    _watch = ref.read(battleRepoProvider).watch(_battle.id).listen((b) {
      if (b == null || !mounted) return;

      // The other side turned the invitation down — either deliberately, or
      // because they were mid-round and the overlay held it, or because they
      // muted the sender. Whichever it was, waiting out a match nobody is
      // going to play is worse than being told (EN-12).
      if (b.status == 'cancelled' && !_finished) {
        _tick?.cancel();
        sqSnack(context, tr('Досың бос емес — кейінірек шақыр'));
        Navigator.of(context).maybePop();
        return;
      }

      setState(() {
        _battle = b;
        final opp = b.oppScore(_uid);
        if (opp > _oppScore) _oppScore = opp;
        if (b.oppIsDone(_uid)) _oppFinished = true;
      });
    });
  }

  // ── bot ──────────────────────────────────────────────────

  void _startBotSimulation() {
    final accuracy = _battle.botAccuracy ?? 0.7;
    final speed = _battle.botSpeedMs ?? 3500;

    void scheduleNext() {
      final jitter = (speed * (0.65 + _rng.nextDouble() * 0.7)).round();
      _botTimer = Timer(Duration(milliseconds: jitter), () {
        if (!mounted || _oppIndex >= _questions.length) return;
        setState(() {
          final ok = _rng.nextDouble() < accuracy;
          if (ok) _oppScore += 10 + _rng.nextInt(8);
          _botRounds.add(ok);
          _oppIndex++;
          if (_oppIndex >= _questions.length) _oppFinished = true;
        });
        if (_oppIndex < _questions.length) scheduleNext();
      });
    }

    scheduleNext();
  }

  // ── question flow ────────────────────────────────────────

  void _startQuestionTimer() {
    _tick?.cancel();
    _maxSeconds = _current?.kind == QKind.spelling
        ? _spellingSeconds
        : _perQuestionSeconds;
    _secondsLeft = _maxSeconds;
    _qStart = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_revealed) _answer(null);
      }
    });
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

  void _maybeSpeak() {
    final q = _current;
    if (q == null) return;
    if (q.kind == QKind.listening && (q.speakText ?? '').isNotEmpty) {
      Speech.instance.say(q.speakText!);
    }
  }

  void _answer(String? choice) {
    if (_revealed) return;
    final q = _current;
    if (q == null) return;
    _tick?.cancel();

    final ok = choice != null && q.isCorrect(choice);
    final ms = DateTime.now().difference(_qStart).inMilliseconds;
    HapticFeedback.mediumImpact();

    setState(() {
      _picked = choice;
      _revealed = true;
      _log.add(AnswerLog(
        correct: ok, ms: ms, kind: q.kind, wordId: q.wordId));
      _rounds.add(_Round(_index + 1, q.answer, ok, ms,
          _isBot && _botRounds.length > _index ? _botRounds[_index] : null));
      if (ok) {
        _correct++;
        _combo++;
        // faster answers are worth more, so speed decides close matches
        final speedBonus = ((_maxSeconds * 1000 - ms) / 1000)
            .clamp(0, _maxSeconds).round();
        _score += 10 + speedBonus + min<int>(_combo * 2, 10);
      } else {
        _combo = 0;
      }
    });

    _broadcast();

    Future.delayed(Duration(milliseconds: ok ? 620 : 1150), () {
      if (!mounted) return;
      if (_index + 1 >= _questions.length) {
        _finish();
      } else {
        setState(() {
          _index++;
          _picked = null;
          _revealed = false;
          _chosenLetters.clear();
        });
        _startQuestionTimer();
        _maybeSpeak();
      }
    });
  }

  /// The player may finish before the bot has worked through every question.
  /// Roll the remainder forward so both sides are scored over the same set.
  void _completeBotRun() {
    _botTimer?.cancel();
    final accuracy = _battle.botAccuracy ?? 0.7;
    while (_oppIndex < _questions.length) {
      final ok = _rng.nextDouble() < accuracy;
      if (ok) _oppScore += 10 + _rng.nextInt(8);
      _botRounds.add(ok);
      _oppIndex++;
    }
    _oppFinished = true;
  }

  Future<void> _finish() async {
    if (_finished) return;
    _tick?.cancel();
    if (_isBot) _completeBotRun();
    setState(() { _finished = true; _submitting = true; });
    _broadcast(done: true);

    try {
      final updated = await ref.read(battleRepoProvider).submit(
        battleId: _battle.id,
        score: _score,
        correct: _correct,
        oppScore: _isBot ? _oppScore : null);
      if (mounted) setState(() => _battle = updated);

      // Battle answers train real words too when the learner owns them.
      final logs = _log.where((a) => a.wordId != null).toList();
      if (logs.isNotEmpty) {
        await ref.read(wordsRepoProvider)
            .recordQuiz(logs, game: 'battle', xp: 0)
            .catchError((_) => (0, 0, 0));
      }

      final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
      await ref.read(eventsRepoProvider).bumpByMetric(cefr, 'battles');

      refreshAll(ref);
      ref.invalidate(battleHistoryProvider);
      ref.invalidate(pendingInvitesProvider);

      final fresh = ref.read(myProfileProvider).valueOrNull;
      if (fresh != null) {
        _unlocked = await AchievementService.instance.check(fresh);
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }

    _pollForOpponent();
  }

  /// Keeps re-reading the battle row until the opponent's result lands.
  ///
  /// Everything else here depends on a live socket: the broadcast channel for
  /// their progress, the postgres stream for their submitted row. Neither is
  /// guaranteed to arrive — a backgrounded app, a dropped websocket, or a
  /// reconnect that misses the one UPDATE it needed all end the same way, with
  /// the result screen frozen on "waiting" while the opponent has long since
  /// finished. Polling is the floor under that: slow, but it always resolves.
  ///
  /// Stops as soon as the match is settled, and gives up after two minutes so
  /// an abandoned opponent does not leave a timer running for the session.
  void _pollForOpponent() {
    if (_isBot || _oppFinished || _battle.oppIsDone(_uid)) return;
    _awaitOpp?.cancel();

    var tries = 0;
    _awaitOpp = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted || ++tries > 40) {
        t.cancel();
        // Two minutes of waiting used to end in silence: the timer stopped,
        // no state changed, and the result screen sat on "waiting" for ever
        // while neither rating moved. Claiming the forfeit is what settles
        // it (EN-20) — the server still checks the grace period itself, so
        // an opponent who was merely slow is not robbed of their match.
        if (mounted) setState(() => _oppGaveUp = true);
        return;
      }
      final fresh = await ref.read(battleRepoProvider).byId(_battle.id)
          .catchError((_) => null);
      if (!mounted || fresh == null) return;

      // Past the grace period the win is claimable. The server is the judge:
      // it returns the battle untouched until the opponent has genuinely run
      // out of time, so calling this early costs nothing.
      if (!fresh.oppIsDone(_uid) && tries >= 8) {
        final settled = await ref.read(battleRepoProvider)
            .claimForfeit(_battle.id)
            .catchError((_) => fresh);
        if (!mounted) return;
        if (settled.isFinished) {
          t.cancel();
          setState(() {
            _battle = settled;
            _oppFinished = true;
            _oppForfeited = true;
            _oppScore = settled.oppScore(_uid);
          });
          refreshAll(ref);
          ref.invalidate(battleHistoryProvider);
        }
        return;
      }
      if (!fresh.oppIsDone(_uid)) return;

      t.cancel();
      setState(() {
        _battle = fresh;
        _oppFinished = true;
        _oppScore = max(_oppScore, fresh.oppScore(_uid));
      });
      // The opponent finishing is what decides the match, so the numbers the
      // rest of the app shows are only correct once that has landed.
      refreshAll(ref);
      ref.invalidate(battleHistoryProvider);
    });
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final me = ref.watch(myProfileProvider).valueOrNull;

    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final quit = await sqConfirm(context,
          title: tr('Баттлдан шығу'),
          message: tr('Шықсаң, жеңіліс болып саналады. Шығасың ба?'),
          confirm: tr('Шығу'));
        if (quit && mounted) {
          await _finish();
          if (mounted) nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _finished ? AppColors.bg(isDark(context)) : AppColors.ink,
        body: SafeArea(
          child: _questions.isEmpty
              ? Center(
                  child: SqEmpty(
                    icon: PhosphorIconsFill.warningCircle,
                    title: tr('Бұл баттлдың сұрақтары бос'),
                    subtitle: tr('Аренаға оралып, жаңа баттл баста'),
                    tint: AppColors.red,
                    action: SizedBox(
                      width: 220,
                      child: SqAction(tr('Артқа'),
                        tone: SqTone.ghost,
                        onTap: () => Navigator.of(context).pop()),
                    ),
                  ),
                )
              : _finished
                  ? _BattleResult(
                      battle: _battle,
                      uid: _uid,
                      myScore: _score,
                      oppScore: _isBot
                          ? _oppScore
                          : max(_battle.oppScore(_uid), _oppScore),
                      oppName: _oppName,
                      // Either signal settles this. The row is authoritative
                      // but slow, the broadcast is fast but not persisted;
                      // reading only the row is what left this screen stuck
                      // on "waiting" after the opponent had visibly finished.
                      oppFinished:
                          _isBot || _oppFinished || _battle.oppIsDone(_uid),
                      oppForfeited: _oppForfeited,
                      oppGaveUp: _oppGaveUp,
                      correct: _correct,
                      total: _questions.length,
                      rounds: _rounds,
                      isBot: _isBot,
                      unlocked: _unlocked,
                      submitting: _submitting,
                      onRematch: _offerRematch,
                      rematchWaiting: _rematchWaiting,
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : _playing(me),
        ),
      ),
    );
  }

  /// Asks for a rematch, and keeps asking until the other side answers.
  ///
  /// `offer_rematch` is idempotent: it sets this player's flag and returns
  /// the next battle the moment BOTH flags are set — whichever side calls it
  /// second is the one that creates the row, and the other side picks it up
  /// on its next poll. So polling the same call is the whole handshake.
  Future<void> _offerRematch() async {
    if (_rematchWaiting) return;
    final repo = ref.read(battleRepoProvider);

    if (_isBot) {
      // Nothing to agree with. Straight back into another one.
      if (mounted) Navigator.of(context).pop(_battle);
      return;
    }

    setState(() => _rematchWaiting = true);
    try {
      final next = await repo.offerRematch(_battle.id);
      if (!mounted) return;
      if (next != null) {
        _goToRematch(next);
        return;
      }
      // Still one-sided. Wait for them, and give up after half a minute
      // rather than leaving somebody staring at a spinner for ever.
      var waited = 0;
      _rematchPoll?.cancel();
      _rematchPoll = Timer.periodic(const Duration(seconds: 2), (t) async {
        waited += 2;
        if (!mounted) { t.cancel(); return; }
        try {
          final b = await repo.offerRematch(_battle.id);
          if (b != null && mounted) { t.cancel(); _goToRematch(b); return; }
        } catch (e) {
          t.cancel();
          if (mounted) {
            setState(() => _rematchWaiting = false);
            sqSnack(context, humanError(e), error: true);
          }
          return;
        }
        if (waited >= 30 && mounted) {
          t.cancel();
          setState(() => _rematchWaiting = false);
          sqSnack(context, tr('Қарсылас реваншқа келіспеді'));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _rematchWaiting = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  void _goToRematch(Battle next) {
    _rematchPoll?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => BattleScreen(battle: next)));
  }

  Widget _playing(Profile? me) {
    final q = _current!;
    final total = _questions.length;
    final myRail = List<Color>.generate(total, (i) {
      if (i < _rounds.length) {
        return _rounds[i].meOk ? AppColors.green : AppColors.red;
      }
      if (i == _index) return AppColors.primary;
      return Colors.white.withValues(alpha: 0.12);
    });
    final oppRail = List<Color>.generate(total, (i) {
      if (_isBot && i < _botRounds.length) {
        return _botRounds[i] ? AppColors.green : AppColors.red;
      }
      if (i < _oppIndex) return AppColors.onInk3;
      return Colors.white.withValues(alpha: 0.12);
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Column(
        children: [
          Row(
            children: [
              SqSquareButton(PhosphorIconsBold.x,
                size: 36, onInk: true,
                onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 11),
              Expanded(
                child: SqEyebrow(
                  trp('{mode} · раунд {n}/{total}', {
                    'mode': tr(switch (_battle.mode) {
                      'ranked' => 'Рейтингті баттл',
                      'bot' => 'Ботпен',
                      _ => 'Дос баттлы',
                    }),
                    'n': '${_index + 1}',
                    'total': '$total',
                  }),
                  color: AppColors.onInk2, size: 10.5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(
                    alpha: _secondsLeft <= 4 ? 0.32 : 0.18),
                  borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsFill.timer,
                      size: 13, color: Color(0xFFFF8080)),
                    const SizedBox(width: 5),
                    SqNum(_secondsLeft.toString().padLeft(2, '0'),
                      size: 12, color: const Color(0xFFFF8080)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _PlayerCard(
                  name: me?.name ?? tr('Сен'),
                  rating: '${me?.elo ?? 1000}',
                  score: _score,
                  worn: ref.watch(myWornProvider),
                  emoji: me?.avatarEmoji,
                  mine: true),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SqNum('VS', size: 12, color: Color(0xFF6B6499)),
              ),
              Expanded(
                child: _PlayerCard(
                  name: _oppName,
                  rating: _isBot ? tr('бот') : '${_oppElo ?? '—'}',
                  score: _oppScore,
                  worn: _oppWorn,
                  emoji: _oppEmoji,
                  mine: false),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SqBeads(total: total, colors: myRail, height: 6),
          const SizedBox(height: 7),
          Row(
            children: [
              SqEyebrow(tr('Сенің жолың'),
                color: AppColors.onInk3, size: 9.5),
              const Spacer(),
              if (!_oppFinished && _oppIndex <= _index) ...[
                SqPulse(
                  child: Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.amber, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    trp('{name} жауап беруде…', {'name': _oppName}),
                    style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700,
                      color: AppColors.amber)),
                ),
              ] else if (_oppFinished)
                Text(tr('Қарсылас аяқтады'),
                  style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700,
                    color: AppColors.green)),
            ],
          ),
          const SizedBox(height: 7),
          SqBeads(total: total, colors: oppRail, height: 6),
          const SizedBox(height: 16),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    child: Column(
                      children: [
                        Text(tr(q.kind.prompt),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: AppColors.onInk2)),
                        const SizedBox(height: 10),
                        if (q.kind == QKind.listening)
                          GestureDetector(
                            onTap: () => Speech.instance.say(q.speakText ?? ''),
                            child: Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(24)),
                              child: const Icon(PhosphorIconsFill.speakerHigh,
                                size: 32, color: Colors.white),
                            ),
                          )
                        else
                          Text(q.prompt,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: q.prompt.length > 30 ? 24 : 34,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1, color: Colors.white)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsFill.lightning,
                                size: 13, color: AppColors.amber),
                              const SizedBox(width: 6),
                              Text(tr('Жылдам жауап көбірек ұпай береді'),
                                style: const TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (q.kind == QKind.spelling && q.letters.isNotEmpty)
                    SpellingPad(
                      question: q,
                      chosen: _chosenLetters,
                      revealed: _revealed,
                      dense: true,
                      onInk: true,
                      onPick: (i) => setState(() => _chosenLetters.add(i)),
                      onUndo: () => setState(() {
                        if (_chosenLetters.isNotEmpty) {
                          _chosenLetters.removeLast();
                        }
                      }),
                      onSubmit: _submitSpelling,
                    )
                  else
                    for (var i = 0; i < q.options.length; i++) ...[
                      _BattleAnswer(
                        text: q.options[i],
                        badge: String.fromCharCode(65 + i),
                        revealed: _revealed,
                        isCorrect: q.isCorrect(q.options[i]),
                        isPicked: q.options[i] == _picked,
                        onTap: () => _answer(q.options[i]),
                      ),
                      const SizedBox(height: 10),
                    ],

                  if (_revealed && _picked == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tr('Уақыт бітті!'),
                        style: const TextStyle(
                          color: AppColors.red, fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Playing pieces ─────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  final String name, rating;
  final int score;
  final bool mine;
  /// EN-43 / KK-6: what this player is wearing. Cosmetics are bought to be
  /// seen and the battle is the one place two people look at each other — so
  /// before this, an opponent could not tell somebody who had spent a
  /// thousand coins from somebody who had spent nothing.
  final WornCosmetics? worn;
  final String? emoji;

  const _PlayerCard({
    required this.name, required this.rating,
    required this.score, required this.mine,
    this.worn, this.emoji});

  @override
  Widget build(BuildContext context) {
    final frame = sqHexColor(worn?.frameColor);
    final title = worn?.title;

    final avatar = CosmeticAvatar(
      name: name,
      emoji: emoji,
      size: 40,
      frame: frame ?? (mine ? AppColors.primary : null),
      // Still, deliberately. The battle screen is dark and busy; two
      // shimmering rings would compete with the question the round is about.
      fx: FrameFx.none,
      aura: sqHexColor(worn?.auraColor),
      badge: worn?.badge);

    final label = Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: CosmeticTitle(
              title: title,
              tint: frame ?? AppColors.amber,
              size: 9.5),
          )
        else
          Text(rating,
            style: const TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600,
              color: AppColors.onInk2)),
      ],
    );

    final scoreText = SqNum('$score', size: 22, color: Colors.white);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mine
            ? AppColors.primary.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: mine
              ? AppColors.primary.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: mine
            ? [avatar, const SizedBox(width: 10),
               Expanded(child: label), scoreText]
            : [scoreText, Expanded(child: label),
               const SizedBox(width: 10), avatar],
      ),
    );
  }
}

/// A white answer button on the dark battle field.
class _BattleAnswer extends StatelessWidget {
  final String text, badge;
  final bool revealed, isCorrect, isPicked;
  final VoidCallback onTap;

  const _BattleAnswer({
    required this.text, required this.badge, required this.revealed,
    required this.isCorrect, required this.isPicked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color fill = Colors.white;
    Color ink = AppColors.ink;
    Color badgeBg = AppColors.mutedL;
    Color badgeInk = AppColors.text3L;

    if (revealed && isCorrect) {
      fill = AppColors.greenSoft; ink = AppColors.greenInk;
      badgeBg = AppColors.green; badgeInk = Colors.white;
    } else if (revealed && isPicked) {
      fill = AppColors.redSoft; ink = AppColors.redInk;
      badgeBg = AppColors.red; badgeInk = Colors.white;
    } else if (revealed) {
      fill = Colors.white.withValues(alpha: 0.55);
      ink = AppColors.text3L;
    }

    return SqLip(
      fill: fill,
      lip: Colors.black.withValues(alpha: 0.35),
      radius: 18,
      padding: const EdgeInsets.all(15),
      onTap: revealed ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: badgeBg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: SqNum(badge, size: 13, color: badgeInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
              style: TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w800,
                letterSpacing: -0.2, color: ink)),
          ),
        ],
      ),
    );
  }
}

// ── Result ─────────────────────────────────────────────────

class _BattleResult extends ConsumerWidget {
  final Battle battle;
  final String uid, oppName;
  final int myScore, oppScore, correct, total;
  final List<_Round> rounds;
  final bool oppFinished, submitting, isBot;
  /// The opponent left and the server settled the match on their forfeit.
  final bool oppForfeited;
  /// The wait ran out with nothing settled — see [_oppGaveUp].
  final bool oppGaveUp;
  final List<Achievement> unlocked;
  final Future<void> Function() onRematch;
  final VoidCallback onClose;

  /// This player has asked for a rematch and the other one has not answered
  /// yet. The button becomes a wait rather than a second request.
  final bool rematchWaiting;

  const _BattleResult({
    required this.battle, required this.uid,
    required this.myScore, required this.oppScore, required this.oppName,
    required this.oppFinished, required this.correct, required this.total,
    required this.rounds, required this.isBot,
    required this.unlocked, required this.submitting,
    required this.onRematch, required this.onClose,
    this.rematchWaiting = false,
    this.oppForfeited = false, this.oppGaveUp = false});

  bool get _won  => oppFinished && myScore > oppScore;
  bool get _lost => oppFinished && myScore < oppScore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final delta = battle.myEloDelta(uid);
    // The profile has already been refreshed by the time the result shows, so
    // its Elo is the "after" number and the "before" is that minus the delta.
    final eloAfter = ref.watch(myProfileProvider).valueOrNull?.elo ?? 1000;
    final eloBefore = eloAfter - delta;
    final tint = !oppFinished
        ? AppColors.amber
        : _won ? AppColors.green : _lost ? AppColors.red : AppColors.amber;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
      children: [
        SqRise(
          child: SqInkCard(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            glow: tint,
            glowAt: Alignment.topRight,
            child: Column(
              children: [
                SqFloat(
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(22)),
                    child: Icon(
                      !oppFinished
                          ? PhosphorIconsFill.hourglass
                          : _won ? PhosphorIconsFill.trophy
                                 : _lost ? PhosphorIconsFill.shieldWarning
                                         : PhosphorIconsFill.handshake,
                      size: 32, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  !oppFinished
                      ? (oppGaveUp
                          ? tr('Қарсылас оралмады')
                          : tr('Қарсыласты күтудеміз'))
                      : _won ? tr('Жеңдің!')
                             : _lost ? tr('Ұтылдың') : tr('Тең түсті'),
                  style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800,
                    letterSpacing: -0.5, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  !oppFinished
                      ? (oppGaveUp
                          ? tr('Ойын есептелмеді. Кейінірек қайта көр.')
                          : tr('Ол ойнап болған соң нәтиже шығады'))
                      : oppForfeited
                          ? trp('{name} ойыннан кетті — жеңіс сенікі',
                              {'name': oppName})
                          : trp('{name}-мен {my} : {opp} есебі', {
                          'name': oppName,
                          'my': '$myScore',
                          'opp': '$oppScore',
                        }),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: AppColors.onInk2)),
                if (battle.mode == 'ranked' && delta != 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 13),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tint.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SqNum('$eloBefore',
                          size: 13, color: AppColors.onInk2),
                        const SizedBox(width: 10),
                        Icon(PhosphorIconsBold.arrowRight,
                          size: 14, color: tint),
                        const SizedBox(width: 10),
                        SqNum('$eloAfter',
                          size: 24, color: Colors.white),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8)),
                          child: SqNum('${delta > 0 ? '+' : ''}$delta',
                            size: 12.5, color: tint),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: SqInkStat('$correct/$total', tr('дұрыс'))),
                    const SizedBox(width: 9),
                    Expanded(child: SqInkStat('$myScore', tr('ұпай'))),
                    const SizedBox(width: 9),
                    Expanded(child: SqInkStat(
                      oppFinished ? '$oppScore' : '—', oppName,
                      valueColor: AppColors.onInk2)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (rounds.isNotEmpty) ...[
          SqSection(tr('Раунд бойынша')),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card(d),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border(d)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15, vertical: 11),
                  color: AppColors.muted(d),
                  child: Row(
                    children: [
                      SizedBox(width: 20,
                        child: SqEyebrow(tr('Р'), size: 9.5)),
                      const SizedBox(width: 10),
                      Expanded(child: SqEyebrow(tr('Сөз'), size: 9.5)),
                      SizedBox(width: 58,
                        child: Center(child: SqEyebrow(tr('Мен'),
                          size: 9.5, color: AppColors.primaryDeep))),
                      SizedBox(width: 58,
                        child: Center(child: SqEyebrow(
                          oppName.length > 7
                              ? '${oppName.substring(0, 6)}…' : oppName,
                          size: 9.5))),
                    ],
                  ),
                ),
                for (final r in rounds)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.divider(d)))),
                    child: Row(
                      children: [
                        SizedBox(width: 20,
                          child: SqNum('${r.n}',
                            size: 11.5, color: AppColors.text4(d))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r.word,
                            style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800,
                              color: AppColors.text(d))),
                        ),
                        SizedBox(
                          width: 58,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                r.meOk
                                    ? PhosphorIconsFill.checkCircle
                                    : PhosphorIconsFill.xCircle,
                                size: 15,
                                color: r.meOk ? AppColors.green : AppColors.red),
                              const SizedBox(width: 5),
                              SqNum(
                                trp('{s}с', {
                                  's': (r.meMs / 1000).toStringAsFixed(1)}),
                                size: 10.5, color: AppColors.text3(d)),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 58,
                          child: Center(
                            child: r.oppOk == null
                                ? Text('—',
                                    style: TextStyle(
                                      color: AppColors.text4(d),
                                      fontWeight: FontWeight.w700))
                                : Icon(
                                    r.oppOk!
                                        ? PhosphorIconsFill.checkCircle
                                        : PhosphorIconsFill.xCircle,
                                    size: 15,
                                    color: r.oppOk!
                                        ? AppColors.green : AppColors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (!isBot) ...[
            const SizedBox(height: 8),
            Text(
              tr('Қарсыласыңның раунд бойынша нәтижесі сақталмайды — '
                 'тек жалпы ұпай салыстырылады.'),
              style: TextStyle(
                fontSize: 11, height: 1.45, fontWeight: FontWeight.w600,
                color: AppColors.text4(d))),
          ],
          const SizedBox(height: 16),
        ],

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
          const SizedBox(height: 16),
        ],

        if (submitting)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator()))
        else ...[
          // A rematch is an AGREEMENT. Pressing this asks; the next game
          // exists only once the other player has asked too, and it is
          // against them — not against whoever the queue turns up next,
          // which is what "Кек қайтару" used to do.
          if (!isBot) ...[
            _RematchButton(
              battle: battle,
              waiting: rematchWaiting,
              onTap: onRematch),
            const SizedBox(height: 10),
            // Two people who have just played each other are exactly the two
            // people most likely to want to play again — and, right now, the
            // only place in the app where they can say anything to each other.
            _AfterMatch(battleId: battle.id),
            const SizedBox(height: 10),
          ] else ...[
            SqAction(tr('Тағы ойнау'),
              icon: PhosphorIconsFill.sword,
              tone: SqTone.danger,
              onTap: () => onRematch()),
            const SizedBox(height: 10),
          ],
          SqAction(tr('Аренаға қайту'),
            tone: SqTone.ghost, height: 48, onTap: onClose),
        ],
      ],
    );
  }

}

/// "Кек қайтару", as an offer rather than a command.
///
/// The scoreline is read from the server so both phones show the same one,
/// and the button says out loud that the other player has to agree — which
/// is the part people were surprised by when a rematch simply started.
class _RematchButton extends ConsumerStatefulWidget {
  final Battle battle;
  final bool waiting;
  final Future<void> Function() onTap;
  const _RematchButton({
    required this.battle, required this.waiting, required this.onTap});

  @override
  ConsumerState<_RematchButton> createState() => _RematchButtonState();
}

class _RematchButtonState extends ConsumerState<_RematchButton> {
  SeriesState? _series;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = await ref.read(battleRepoProvider).seriesState(widget.battle.id);
    if (mounted) setState(() => _series = st);
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final st = _series;

    // Three games and it is settled. A fourth would be a new series, and
    // saying so is kinder than a button that errors when it is pressed.
    if (st != null && st.decided) {
      final won = st.iWonSeries;
      return SqPanel(
        radius: 16,
        padding: const EdgeInsets.all(14),
        fill: AppColors.soft(AppColors.amber, d),
        border: AppColors.line(AppColors.amber, d),
        child: Text(
          won == null
              ? trp('Серия {s} — тең', {'s': st.scoreline})
              : won
                  ? trp('Серияны {s} есебімен жеңдің!', {'s': st.scoreline})
                  : trp('Серияда {s} есебімен ұтылдың', {'s': st.scoreline}),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w800,
            color: AppColors.text(d)),
        ),
      );
    }

    if (widget.waiting) {
      return SqPanel(
        radius: 16,
        padding: const EdgeInsets.all(14),
        fill: AppColors.soft(AppColors.red, d),
        border: AppColors.line(AppColors.red, d),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(tr('Қарсыластың келісуін күтудеміз'),
                style: TextStyle(
                  fontSize: 13, height: 1.35, fontWeight: FontWeight.w800,
                  color: AppColors.text(d))),
            ),
          ],
        ),
      );
    }

    final played = st?.played ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SqAction(
          played > 0
              ? trp('Тағы бір ойын · {s}', {'s': st!.scoreline})
              : tr('Кек қайтару'),
          icon: PhosphorIconsFill.sword,
          tone: SqTone.danger,
          onTap: () => widget.onTap()),
        const SizedBox(height: 6),
        Text(tr('Екі ойыншы да келіскенде ғана басталады'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w600,
            color: AppColors.text4(d))),
      ],
    );
  }
}

/// The two things a match leaves behind: somebody worth adding, and something
/// worth saying to them.
///
/// The phrases are a fixed list the server owns. Free text between strangers
/// would need moderation this app has no room for, and a tap is faster than
/// typing anyway.
class _AfterMatch extends ConsumerStatefulWidget {
  final String battleId;
  const _AfterMatch({required this.battleId});

  @override
  ConsumerState<_AfterMatch> createState() => _AfterMatchState();
}

class _AfterMatchState extends ConsumerState<_AfterMatch> {
  Map<String, dynamic>? _opp;
  List<QuickPhrase> _phrases = const [];
  List<QuickMessage> _messages = const [];
  bool _sent = false;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(battleRepoProvider);
    final opp = await repo.opponentCard(widget.battleId);
    final ph = await repo.quickPhrases();
    final ms = await repo.messagesFor(widget.battleId);
    if (!mounted) return;
    setState(() { _opp = opp; _phrases = ph; _messages = ms; });
  }

  Future<void> _send(QuickPhrase p) async {
    setState(() => _sent = true);
    try {
      final repo = ref.read(battleRepoProvider);
      await repo.sendQuickMessage(widget.battleId, p.code);
      final ms = await repo.messagesFor(widget.battleId);
      if (mounted) setState(() => _messages = ms);
    } catch (e) {
      if (mounted) {
        setState(() => _sent = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  Future<void> _addFriend() async {
    final id = _opp?['user_id']?.toString();
    if (id == null) return;
    try {
      await ref.read(boardRepoProvider).sendFriendRequest(id);
      if (mounted) {
        setState(() => _added = true);
        sqSnack(context, tr('Достық сұранысы жіберілді'));
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opp = _opp;
    if (opp == null) return const SizedBox.shrink();
    final d = isDark(context);
    final canAdd = opp['can_add'] == true && !_added;
    final name = (opp['display_name'] ?? opp['username'] ?? '').toString();

    return SqPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text((opp['avatar_emoji'] ?? '🦊').toString(),
                style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name.isEmpty ? tr('Қарсылас') : name,
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    Text('@${opp['username'] ?? ''}',
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.text4(d))),
                  ],
                ),
              ),
              if (canAdd)
                SqLip(
                  fill: AppColors.primary,
                  lip: AppColors.primaryDeep,
                  depth: 3,
                  radius: 12,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  onTap: _addFriend,
                  child: Text(tr('Дос қосу'),
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: Colors.white)),
                ),
            ],
          ),
          if (_messages.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final m in _messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  m.isMine ? '→ ${m.text}' : '← ${m.text}',
                  style: TextStyle(
                    fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600,
                    color: AppColors.text2(d))),
              ),
          ],
          if (!_sent && _phrases.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ph in _phrases)
                  SqLip(
                    fill: AppColors.card(d),
                    lip: AppColors.line(AppColors.ink, d),
                    depth: 2,
                    radius: 11,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 8),
                    onTap: () => _send(ph),
                    child: Text(ph.text,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppColors.text(d))),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
