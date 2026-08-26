// lib/features/home/story_chapter_screen.dart
//
// Playing one chapter of the story (EN-11 / KK-1).
//
// The thing this screen exists to avoid is the shape every other mode in the
// app has: a question, four options, a score. So the vocabulary here is not
// tested, it is USED — the English word you choose is what Айя says next, and
// the scene continues either way. A wrong answer is the character saying the
// wrong thing and being corrected, not a red cross and a number going down.
//
// There is no score on screen. Finishing the chapter is the reward, plus the
// XP at the end; adding a running total would put the quiz back.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import '../../services/speech.dart';
import 'story_content.dart';

class StoryChapterScreen extends ConsumerStatefulWidget {
  final int chapter;
  const StoryChapterScreen({super.key, required this.chapter});

  @override
  ConsumerState<StoryChapterScreen> createState() =>
      _StoryChapterScreenState();
}

class _StoryChapterScreenState extends ConsumerState<StoryChapterScreen> {
  int _scene = 0;
  String? _picked;
  bool _revealed = false;
  bool _finished = false;

  /// Every branch this learner has ever taken, not just the ones in this
  /// chapter.
  ///
  /// It used to be a plain in-memory set thrown away when the chapter closed,
  /// which made one consequence unreachable by construction: chapter five
  /// gates a scene on `friend`, and `friend` is only chosen in chapter two —
  /// a different screen, a different instance, a set that no longer existed.
  /// Seeded from MetaState here and written back the moment a choice is made.
  Set<String> _flags = {};

  StoryChapter get _ch => kStory[widget.chapter];
  StoryScene get _s => _ch.scenes[_scene];

  @override
  void initState() {
    super.initState();
    // EN-12: a battle invitation must not land on top of a scene the learner
    // is reading.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(busyProvider.notifier).state = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakIfNeeded());
    _flags = ref.read(metaProvider).storyFlags;
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
    Speech.instance.stop();
    super.dispose();
  }

  void _speakIfNeeded() {
    if (_s.kind == SceneKind.listen && _s.answer.isNotEmpty) {
      Speech.instance.say(_s.answer);
    }
  }

  /// The options for a choice scene, shuffled once per scene so the answer is
  /// not always in the same place.
  List<String> get _options {
    final all = [_s.answer, ..._s.distractors];
    // Seeded by the scene so a rebuild — a keyboard opening, a theme change —
    // does not reshuffle the buttons under the learner's finger.
    all.shuffle(Random(widget.chapter * 100 + _scene));
    return all;
  }

  void _answer(String choice) {
    if (_revealed) return;
    HapticFeedback.selectionClick();
    setState(() { _picked = choice; _revealed = true; });
  }

  Future<void> _choose(StoryChoice c) async {
    HapticFeedback.selectionClick();
    setState(() {
      _flags = {..._flags, c.flag};
      _revealed = true;
    });
    // Written now rather than when the chapter ends: a learner who closes the
    // app after choosing still chose.
    final saved = await ref.read(metaProvider.notifier).rememberStoryFlag(c.flag);
    if (mounted) setState(() => _flags = saved);
  }

  Future<void> _next() async {
    if (_scene + 1 < _ch.scenes.length) {
      setState(() {
        _scene++;
        _picked = null;
        _revealed = false;
      });
      _speakIfNeeded();
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_finished) return;
    setState(() => _finished = true);

    // The chapter is cleared as a whole. Marking each scene would let a
    // learner half-finish a chapter and come back to a story that has no
    // beginning, which is worse than replaying four scenes.
    final upTo = chapterStart(widget.chapter) + _ch.scenes.length;
    await ref.read(metaProvider.notifier).clearStoryTo(upTo);

    try {
      await ref.read(profileRepoProvider)
          .addXp(120, 'story_${widget.chapter + 1}')
          .catchError((_) => 0);
      ref.invalidate(myProfileProvider);
    } catch (_) {/* the chapter still counts as read */}
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    if (_finished) return _done(d);

    final s = _s;
    final isBranch = s.kind == SceneKind.branch;
    final correct = _picked == s.answer;

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  SqSquareButton(PhosphorIconsBold.x,
                    size: 38, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SqBeads(
                      total: _ch.scenes.length,
                      done: _scene + (_revealed ? 1 : 0),
                      doneColor: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                children: [
                  // The scene. One dark block — it is what the learner is
                  // here for, and everything else on screen is a control.
                  SqRise(
                    child: SqInkCard(
                      padding: const EdgeInsets.all(20),
                      glow: AppColors.primary,
                      glowAt: Alignment.topRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_ch.icon, size: 16,
                                color: AppColors.onInk2),
                              const SizedBox(width: 7),
                              SqEyebrow(s.speaker, color: AppColors.onInk2),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(byLang(kk: s.narrationKk, ru: s.narrationRu),
                            style: const TextStyle(
                              fontSize: 13.5, height: 1.55,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onInk2)),
                          const SizedBox(height: 12),
                          Text(byLang(kk: s.lineKk, ru: s.lineRu),
                            style: const TextStyle(
                              fontSize: 17, height: 1.4,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3, color: Colors.white)),

                          if (s.kind == SceneKind.listen) ...[
                            const SizedBox(height: 14),
                            SqLip(
                              fill: Colors.white.withValues(alpha: 0.12),
                              border: Colors.white.withValues(alpha: 0.18),
                              radius: 14,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                              onTap: () => Speech.instance.say(s.answer),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(PhosphorIconsFill.speakerHigh,
                                    size: 17, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(tr('Қайта тыңдау'),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (isBranch)
                    for (final c in s.choices) ...[
                      SqAction(byLang(kk: c.kk, ru: c.ru),
                        tone: SqTone.ghost,
                        height: 52,
                        onTap: _revealed ? null : () => _choose(c)),
                      const SizedBox(height: 9),
                    ]
                  else if (s.kind == SceneKind.spell)
                    // Typed rather than assembled from a letter keypad. The
                    // pad wants a Question, and building one here would couple
                    // the story to the quiz engine it exists to be different
                    // from — writing the word out is also closer to what the
                    // scene is asking for.
                    _SpellField(
                      answer: s.answer,
                      revealed: _revealed,
                      onSubmit: _answer)
                  else
                    for (var i = 0; i < _options.length; i++) ...[
                      SqAnswer(
                        text: _options[i],
                        badge: String.fromCharCode(65 + i),
                        revealed: _revealed,
                        isCorrect: _options[i] == s.answer,
                        isPicked: _options[i] == _picked,
                        onTap: _revealed ? null : () => _answer(_options[i])),
                      const SizedBox(height: 9),
                    ],

                  if (_revealed) ...[
                    const SizedBox(height: 8),
                    _Outcome(
                      scene: s,
                      correct: isBranch || correct,
                      flags: _flags),
                  ],
                ],
              ),
            ),

            if (_revealed)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: SqAction(
                  _scene + 1 < _ch.scenes.length
                      ? tr('Жалғастыру')
                      : tr('Тарауды аяқтау'),
                  icon: PhosphorIconsBold.arrowRight,
                  height: 54,
                  onTap: _next),
              ),
          ],
        ),
      ),
    );
  }

  Widget _done(bool d) => SqPage(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
    children: [
      const SizedBox(height: 40),
      Center(
        child: SqFloat(
          child: Container(
            width: 86, height: 86,
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(28)),
            child: Icon(_ch.icon, size: 42, color: Colors.white),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(byLang(kk: _ch.titleKk, ru: _ch.titleRu),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800,
          letterSpacing: -0.5, color: AppColors.text(d))),
      const SizedBox(height: 6),
      Text(tr('Тарау аяқталды'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w600,
          color: AppColors.text3(d))),
      const SizedBox(height: 22),
      Center(
        child: SqChip(trp('+{n} тәжірибе', {'n': '120'}),
          icon: PhosphorIconsFill.lightning,
          tint: AppColors.amber,
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
      ),
      const SizedBox(height: 30),
      SqAction(tr('Жолға оралу'),
        icon: PhosphorIconsBold.arrowLeft,
        onTap: () => Navigator.of(context).pop(true)),
    ],
  );
}

/// Typing the word out. Deliberately forgiving about case and stray spaces:
/// the scene is about knowing the word, not about the shift key.
class _SpellField extends StatefulWidget {
  final String answer;
  final bool revealed;
  final void Function(String) onSubmit;
  const _SpellField({
    required this.answer, required this.revealed, required this.onSubmit});

  @override
  State<_SpellField> createState() => _SpellFieldState();
}

class _SpellFieldState extends State<_SpellField> {
  final _c = TextEditingController();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  void _send() {
    final typed = _c.text.trim().toLowerCase();
    if (typed.isEmpty) return;
    widget.onSubmit(typed == widget.answer.toLowerCase() ? widget.answer : typed);
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          enabled: !widget.revealed,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _send(),
          style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800,
            color: AppColors.text(d)),
          decoration: InputDecoration(
            hintText: tr('Ағылшынша жаз…'),
            filled: true,
            fillColor: AppColors.card(d),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border(d))),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border(d))),
          ),
        ),
        const SizedBox(height: 10),
        SqAction(tr('Айту'),
          icon: PhosphorIconsBold.check,
          height: 50,
          onTap: widget.revealed ? null : _send),
      ],
    );
  }
}

/// What happened, and what it meant. Never a score — the point of this mode is
/// that the vocabulary carries the story rather than being marked out of ten.
class _Outcome extends StatelessWidget {
  final StoryScene scene;
  final bool correct;
  final Set<String> flags;

  const _Outcome({
    required this.scene, required this.correct, required this.flags});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    // A scene's aftermath only applies when its branch was actually taken;
    // otherwise the story would react to something that did not happen.
    final gated = scene.ifFlag != null && !flags.contains(scene.ifFlag);
    final after = gated
        ? ''
        : byLang(kk: scene.afterKk, ru: scene.afterRu);

    final tint = correct ? AppColors.green : AppColors.amber;

    return SqPanel(
      padding: const EdgeInsets.all(15),
      fill: AppColors.soft(tint, d),
      border: AppColors.line(tint, d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!correct && scene.answer.isNotEmpty) ...[
            Row(
              children: [
                Icon(PhosphorIconsFill.arrowBendUpRight,
                  size: 15, color: AppColors.onSoft(tint, d)),
                const SizedBox(width: 8),
                Expanded(
                  // Corrected, not marked. The learner is told the word Айя
                  // should have said, and the scene carries on.
                  child: Text(
                    trp('Айя «{w}» деуі керек еді', {'w': scene.answer}),
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.onSoft(tint, d))),
                ),
              ],
            ),
            if (after.isNotEmpty) const SizedBox(height: 8),
          ],
          if (after.isNotEmpty)
            Text(after,
              style: TextStyle(
                fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600,
                color: AppColors.onSoft(tint, d))),
        ],
      ),
    );
  }
}
