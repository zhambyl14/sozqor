// lib/features/arena/room_screen.dart
//
// A private battle for three or four friends (EN-44 / KK-2).
//
// The lobby is the whole feature. EN-44 asks for the host, the invited, who
// has joined, each ready state and who is still missing — and then that the
// battle starts only once the required players are ready. Everything on this
// screen is one of those, and the start button says WHY it is disabled rather
// than simply being grey, because a button that refuses without explaining is
// the thing people tap five times.
//
// The roster is live. A lobby where you cannot see somebody join is not a
// lobby, so a realtime subscription drives it rather than a poll.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/question.dart';
import '../../data/models/word.dart';
import '../../data/repos/room_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/question_factory.dart';
import '../auth/guest_gate.dart';
import '../play/play_session_screen.dart';

final roomRepoProvider = Provider((_) => RoomRepo());

class RoomScreen extends ConsumerStatefulWidget {
  /// Join straight into this code, when the learner arrived from an invite.
  final String? joinCode;
  const RoomScreen({super.key, this.joinCode});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final _code = TextEditingController();
  RoomState? _room;
  StreamSubscription<List<Map<String, dynamic>>>? _watch;
  bool _busy = false;
  bool _unavailable = false;
  bool _played = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.joinCode != null) {
      _code.text = widget.joinCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _code.dispose();
    super.dispose();
  }

  /// Re-reads the whole state whenever any member row changes. The row payload
  /// alone is not enough — `room_state` folds in the profiles and the
  /// all-ready summary that the raw rows do not carry.
  void _listen(String roomId) {
    _watch?.cancel();
    _watch = ref.read(roomRepoProvider).watchMembers(roomId).listen((_) async {
      final fresh = await ref.read(roomRepoProvider)
          .state(roomId)
          .catchError((_) => null);
      if (!mounted || fresh == null) return;
      setState(() => _room = fresh);
      if (fresh.isRunning && !_played) _play(fresh);
    });
  }

  Future<T?> _run<T>(Future<T?> Function() body) async {
    if (_busy) return null;
    setState(() { _busy = true; _error = null; });
    try {
      return await body();
    } on RoomsUnavailable {
      if (mounted) setState(() => _unavailable = true);
      return null;
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Question>> _buildQuestions() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';

    var pool = ref.read(levelPoolProvider).valueOrNull ?? const <DictEntry>[];
    if (pool.length < 12) {
      pool = await ref.read(dictRepoProvider)
          .pool(cefr: visibleCefrFor(cefr), limit: 120)
          .catchError((_) => <DictEntry>[]);
    }
    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];

    return QuestionFactory.build(
      items: [
        ...words.take(30).map(PlayItem.fromWord),
        ...pool.map(PlayItem.fromDict),
      ],
      pool: pool,
      kinds: kindsFor(cefr),
      count: 10,
      nativeLang: ref.read(nativeLangProvider),
      // Same reason as ranked: several people in one room, one of them on a
      // bus, and audio questions are unplayable for whoever that is.
      exclude: const {QKind.listening},
    );
  }

  Future<void> _create() async {
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted) return;
    final questions = await _buildQuestions();
    if (questions.length < 5) {
      if (mounted) {
        sqSnack(context, tr('Баттл үшін сөз жетпейді'), error: true);
      }
      return;
    }
    final room = await _run(() => ref.read(roomRepoProvider).create(
      cefr: ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1',
      questions: questions.map((q) => q.toJson()).toList()));
    if (room != null && mounted) {
      setState(() => _room = room);
      _listen(room.id);
    }
  }

  Future<void> _join() async {
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted) return;
    final room = await _run(
        () => ref.read(roomRepoProvider).join(_code.text));
    if (room != null && mounted) {
      setState(() => _room = room);
      _listen(room.id);
    }
  }

  Future<void> _toggleReady() async {
    final r = _room;
    if (r == null) return;
    final me = r.members.where((m) => m.isMe).firstOrNull;
    final next = !(me?.ready ?? false);
    final room = await _run(
        () => ref.read(roomRepoProvider).setReady(r.id, next));
    if (room != null && mounted) setState(() => _room = room);
  }

  Future<void> _start() async {
    final r = _room;
    if (r == null) return;
    final room = await _run(() => ref.read(roomRepoProvider).start(r.id));
    if (room != null && mounted) {
      setState(() => _room = room);
      if (room.isRunning) _play(room);
    }
  }

  Future<void> _leave() async {
    final r = _room;
    if (r != null) {
      await _run(() async {
        await ref.read(roomRepoProvider).leave(r.id);
        return null;
      });
    }
    _watch?.cancel();
    if (mounted) setState(() { _room = null; _played = false; });
  }

  /// Everybody plays the same set, then posts their score. The room settles
  /// once the last person is done.
  Future<void> _play(RoomState room) async {
    if (_played) return;
    _played = true;

    final questions = [
      for (final q in room.questions)
        Question.fromJson(Map<String, dynamic>.from(q as Map)),
    ];
    if (questions.isEmpty) return;

    final outcome = await Navigator.of(context).push<PlayOutcome>(
      MaterialPageRoute(builder: (_) => PlaySessionScreen(
        mode: PlayMode.classic,
        preset: questions,
        title: tr('Топтық баттл'))));
    if (!mounted) return;

    final fresh = await _run(() => ref.read(roomRepoProvider)
        .submit(room.id, outcome?.score ?? 0, outcome?.correct ?? 0));
    if (fresh != null && mounted) setState(() => _room = fresh);
    refreshAll(ref);
  }

  Future<void> _share() async {
    final code = _room?.code ?? '';
    if (code.isEmpty) return;
    await Share.share(
      trp('SozQor-да топтық баттлға қосыл! Код: {c}', {'c': code}));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final room = _room;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Топтық баттл'),
          eyebrow: tr('3–4 дос'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (_unavailable)
          SqEmpty(
            icon: PhosphorIconsFill.usersThree,
            title: tr('Топтық баттл әлі қосылмаған'),
            subtitle: tr('Сервер жаңартылған соң қолжетімді болады'),
            tint: AppColors.sky)
        else if (room == null)
          ..._entry(d)
        else if (room.isFinished)
          ..._results(d, room)
        else
          ..._lobby(d, room),
      ],
    );
  }

  List<Widget> _entry(bool d) => [
    SqInkCard(
      padding: const EdgeInsets.all(20),
      glow: AppColors.primary,
      glowAt: Alignment.topRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SqEyebrow(tr('Бөлме'), color: AppColors.onInk2),
          const SizedBox(height: 5),
          Text(tr('Достарыңмен бірге ойна'),
            style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800,
              letterSpacing: -0.4, color: Colors.white)),
          const SizedBox(height: 4),
          Text(tr('Бір сұрақ жиынтығы, төрт ойыншыға дейін'),
            style: const TextStyle(
              fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600,
              color: AppColors.onInk2)),
          const SizedBox(height: 16),
          SqAction(tr('Бөлме құру'),
            icon: PhosphorIconsBold.plus,
            busy: _busy,
            onTap: _busy ? null : _create),
        ],
      ),
    ),
    const SizedBox(height: 18),

    SqSection(tr('Кодпен қосылу')),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.card(d),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(d)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.hash, size: 17, color: AppColors.text4(d)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 5,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _join(),
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                letterSpacing: 3, color: AppColors.text(d)),
              decoration: const InputDecoration(
                hintText: 'ABC12',
                counterText: '',
                filled: false, isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          GestureDetector(
            onTap: _busy ? null : _join,
            child: const Icon(PhosphorIconsBold.arrowRight,
              size: 18, color: AppColors.primary)),
        ],
      ),
    ),
    if (_error != null) ...[
      const SizedBox(height: 10),
      Text(_error!,
        style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.red)),
    ],
  ];

  List<Widget> _lobby(bool d, RoomState room) {
    final me = room.members.where((m) => m.isMe).firstOrNull;
    final waiting = room.waitingOn;

    return [
      // The code, big, because somebody is reading it out loud.
      SqInkCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        glow: AppColors.primary,
        glowAt: Alignment.topRight,
        child: Column(
          children: [
            SqEyebrow(tr('Бөлме коды'), color: AppColors.onInk2),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: room.code));
                sqSnack(context, tr('Код көшірілді'));
              },
              child: Text(room.code,
                style: const TextStyle(
                  fontSize: 38, fontWeight: FontWeight.w800,
                  letterSpacing: 8, color: Colors.white)),
            ),
            const SizedBox(height: 12),
            SqAction(tr('Досқа жіберу'),
              icon: PhosphorIconsBold.shareNetwork,
              tone: SqTone.ghost,
              height: 44,
              onTap: _share),
          ],
        ),
      ),
      const SizedBox(height: 16),

      SqSection(tr('Ойыншылар'),
        trailingWidget: SqNum('${room.playerCount} / ${room.maxPlayers}',
          size: 11, color: AppColors.text3(d))),
      SqGroup(children: [
        for (final m in room.members)
          SqTile(
            leading: SqAvatar(m.name,
              size: 36,
              tint: m.ready ? AppColors.green : null,
              solid: m.ready),
            title: m.name,
            subtitle: m.isHost ? tr('Құрушы') : null,
            trailing: m.ready
                ? SqBadge(tr('Дайын'), tint: AppColors.green, solid: true)
                : SqBadge(tr('Күтуде'), tint: AppColors.amber),
          ),
        // EN-44 asks for "missing users" — the empty seats, so the room reads
        // as unfinished rather than as complete-but-small.
        for (var i = room.playerCount; i < room.maxPlayers; i++)
          SqTile(
            leading: SqTintBox(PhosphorIconsBold.userPlus,
              tint: AppColors.text4(d), size: 36),
            title: tr('Бос орын'),
            titleColor: AppColors.text3(d),
          ),
      ]),
      const SizedBox(height: 16),

      SqAction(
        (me?.ready ?? false) ? tr('Дайын емеспін') : tr('Дайынмын'),
        icon: (me?.ready ?? false)
            ? PhosphorIconsBold.x
            : PhosphorIconsBold.check,
        tone: (me?.ready ?? false) ? SqTone.ghost : SqTone.green,
        busy: _busy,
        onTap: _busy ? null : _toggleReady),

      if (room.iAmHost) ...[
        const SizedBox(height: 10),
        SqAction(tr('Бастау'),
          icon: PhosphorIconsFill.play,
          height: 54,
          busy: _busy,
          onTap: room.canStart && !_busy ? _start : null),
        const SizedBox(height: 8),
        // A button that refuses without saying why is the one people tap five
        // times. EN-44 requires the wait; this explains it.
        Center(
          child: Text(
            room.playerCount < 2
                ? tr('Кемінде 2 ойыншы керек')
                : waiting.isEmpty
                    ? tr('Барлығы дайын')
                    : trp('Күтудеміз: {who}',
                        {'who': waiting.map((m) => m.name).join(', ')}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: room.canStart ? AppColors.green : AppColors.text3(d))),
        ),
      ],

      const SizedBox(height: 14),
      Center(
        child: TextButton(
          onPressed: _busy ? null : _leave,
          child: Text(tr('Бөлмеден шығу'))),
      ),
    ];
  }

  List<Widget> _results(bool d, RoomState room) {
    final placing = room.placing;
    return [
      SqInkCard(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        glow: AppColors.amber,
        glowAt: Alignment.topRight,
        child: Column(
          children: [
            const Icon(PhosphorIconsFill.trophy,
              size: 38, color: AppColors.amber),
            const SizedBox(height: 12),
            Text(tr('Баттл аяқталды'),
              style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800,
                letterSpacing: -0.4, color: Colors.white)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SqGroup(children: [
        for (var i = 0; i < placing.length; i++)
          SqTile(
            leading: SizedBox(
              width: 34,
              child: Center(
                child: SqNum('${i + 1}',
                  size: 16,
                  color: i == 0 ? AppColors.amber : AppColors.text3(d))),
            ),
            title: placing[i].name,
            subtitle: trp('{n} дұрыс', {'n': '${placing[i].correct}'}),
            trailing: SqNum('${placing[i].score}',
              size: 14,
              color: placing[i].isMe
                  ? AppColors.primaryDeep : AppColors.text2(d)),
          ),
      ]),
      const SizedBox(height: 18),
      SqAction(tr('Жабу'), onTap: () => Navigator.of(context).pop()),
    ];
  }
}
