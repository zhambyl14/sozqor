// lib/features/play/pronounce_screen.dart
//
// Pronunciation drill.
//
// Vocabulary apps teach recognition and quietly skip production, so learners
// end up with words they can pick out of four options but cannot say. This
// screen is the missing half: hear the model, see the word broken into
// syllables, hold the button and repeat it, then judge yourself.
//
// The self-judgement used to be the whole of it, and the header used to
// explain why: automatic scoring would need a speech-recognition engine, and
// an honest three-way self-check was better than a number nobody measured.
//
// It is measured now. The model already answering translations will listen to
// a couple of seconds of audio over an ordinary HTTPS request and say what it
// heard — probed on "beacon" and "library" it returned both, in about a
// second. So holding the button records, and letting go marks it.
//
// The self-check has not been deleted, because a microphone can be refused, a
// platform can lack one, and a request can fail. In every one of those cases
// the screen falls back to the three buttons rather than to an error: the
// drill is worth doing without a network, and it always was.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/listen.dart';
import '../../services/sozqor_ai.dart';
import '../../services/speech.dart';

const _vowels = 'aeiouy';

/// Two vowels that are pronounced as one sound, so they must not be split.
const _digraphs = {
  'ai', 'au', 'aw', 'ay', 'ea', 'ee', 'ei', 'eu', 'ew', 'ey', 'ie',
  'oa', 'oe', 'oi', 'oo', 'ou', 'ow', 'oy', 'ue', 'ui', 'uy',
};

bool _isVowel(String c) => c.isNotEmpty && _vowels.contains(c);

/// Splits an English word into rough syllables.
///
/// Not a phonetic engine — three classic rules applied in order: a single
/// consonant between two vowels opens the next syllable (com·pu·ter), two
/// consonants between vowels split down the middle (or·ga·ni·sa·tion), and a
/// word-final consonant + "le" stays whole (a·pple → ap·ple, relia·ble).
/// It gets the common cases right, which is all a learner needs in order to
/// know where to slow down.
List<String> syllablesOf(String raw) {
  final w = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (w.isEmpty) return ['—'];
  if (w.length <= 3) return [w];

  final out = <String>[];
  var buf = '';
  var hasVowel = false;

  void flush() {
    if (buf.isEmpty) return;
    out.add(buf);
    buf = '';
    hasVowel = false;
  }

  for (var i = 0; i < w.length; i++) {
    final c = w[i];
    final next = i + 1 < w.length ? w[i + 1] : '';
    final after = i + 2 < w.length ? w[i + 2] : '';

    if (_isVowel(c)) {
      // Two vowels that are not a digraph belong to different syllables:
      // re·li·a·ble, not re·liable.
      final prev = buf.isEmpty ? '' : buf[buf.length - 1];
      if (_isVowel(prev) && !_digraphs.contains('$prev$c')) flush();
      buf += c;
      hasVowel = true;
      continue;
    }

    if (!hasVowel) { buf += c; continue; }

    // A final "-Cle" is one syllable: ap·ple, ta·ble, relia·ble.
    if (i + 3 == w.length && next == 'l' && after == 'e') {
      flush();
      buf += c;
      continue;
    }
    if (_isVowel(next)) {
      // Single consonant between vowels opens the next syllable.
      flush();
      buf += c;
      continue;
    }
    if (next.isNotEmpty && !_isVowel(next) && _isVowel(after)) {
      // Two consonants between vowels split between them.
      buf += c;
      flush();
      continue;
    }
    buf += c;
  }
  flush();

  // Never hand back one-letter crumbs, and never show more than five chips.
  final merged = <String>[];
  for (final s in out) {
    if (s.length == 1 && merged.isNotEmpty) {
      merged[merged.length - 1] = merged.last + s;
    } else {
      merged.add(s);
    }
  }
  if (merged.length > 1 && merged.first.length == 1) {
    merged[1] = merged.first + merged[1];
    merged.removeAt(0);
  }
  while (merged.length > 5) {
    merged[4] = merged[4] + merged[5];
    merged.removeAt(5);
  }
  return merged.isEmpty ? [w] : merged;
}

class PronounceScreen extends ConsumerStatefulWidget {
  /// Practise one specific word instead of a mixed session.
  final String? only;
  /// The word's id in the learner's dictionary, so practising it here still
  /// records against spaced repetition like every other single-word entry
  /// point. Null when [only] is a dictionary word the learner hasn't added.
  final String? onlyWordId;
  const PronounceScreen({super.key, this.only, this.onlyWordId});

  @override
  ConsumerState<PronounceScreen> createState() => _PronounceScreenState();
}

class _PronounceScreenState extends ConsumerState<PronounceScreen>
    with SingleTickerProviderStateMixin {
  static const _sessionSize = 8;

  late final AnimationController _wave = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  List<_Item> _items = const [];
  int _index = 0;
  bool _holding = false;
  bool _rated = false;
  bool _finished = false;
  int _score = 0;
  int _rateCount = 0;

  /// Whether this device will let us listen at all. Set false the first time
  /// the recorder refuses — no permission, no microphone, an unsupported
  /// platform — and from then on the screen is the self-marked drill it was.
  bool _micOk = true;

  /// A recording is on its way to the model.
  bool _checking = false;

  /// The verdict on this word, once there is one.
  Heard? _heard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _build());
  }

  @override
  void dispose() {
    _wave.dispose();
    Speech.instance.stop();
    // The recorder holds the microphone until it is told otherwise, and a
    // screen that has been popped must not keep it.
    Listen.instance.cancel();
    super.dispose();
  }

  /// Press: start recording. A refusal here is not an error to show — it is
  /// the answer to "can this device do it", and the screen quietly becomes
  /// the self-marked one.
  Future<void> _holdStart() async {
    if (_checking) return;
    HapticFeedback.selectionClick();
    setState(() { _holding = true; _heard = null; });
    if (!_micOk) return;
    final started = await Listen.instance.start();
    if (!started && mounted) setState(() => _micOk = false);
  }

  /// Release: send what was recorded and let the model mark it.
  Future<void> _holdEnd({bool cancelled = false}) async {
    if (!_holding) return;
    setState(() => _holding = false);
    if (!_micOk) return;
    if (cancelled) {
      await Listen.instance.cancel();
      return;
    }

    final audio = await Listen.instance.stop();
    // Too short to be a word. Saying so is friendlier than marking it wrong.
    if (audio == null) {
      if (mounted) sqSnack(context, tr('Тым қысқа — түймені ұстап тұрып айт'));
      return;
    }

    final item = _current;
    if (item == null) return;
    setState(() => _checking = true);
    try {
      final heard = await SozQorAI.instance
          .pronounce(audio: audio, target: _speakable(item.en));
      if (!mounted) return;
      setState(() { _checking = false; _heard = heard; });
      HapticFeedback.mediumImpact();
      await _rate(heard.score, auto: true);
    } catch (e) {
      if (!mounted) return;
      // The drill survives a failed request: mark it yourself this once.
      setState(() { _checking = false; _heard = null; });
      sqSnack(context, humanError(e), error: true);
    }
  }

  void _build() {
    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];
    final pool = ref.read(levelPoolProvider).valueOrNull ?? const <DictEntry>[];

    final items = <_Item>[];
    if (widget.only != null) {
      items.add(_Item(widget.only!, null, widget.onlyWordId));
    } else {
      for (final w in words.take(_sessionSize)) {
        items.add(_Item(w.en, w.transcription, w.id));
      }
      for (final e in pool) {
        if (items.length >= _sessionSize) break;
        if (items.any((i) => i.en.toLowerCase() == e.en.toLowerCase())) continue;
        items.add(_Item(e.en, e.ipa, null));
      }
    }
    setState(() => _items = items);
    if (items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Speech.instance.say(_speakable(items.first.en)));
    }
  }

  static String _speakable(String en) =>
      en.toLowerCase().startsWith('to ') ? en.substring(3) : en;

  _Item? get _current => _index < _items.length ? _items[_index] : null;

  Future<void> _rate(int stars, {bool auto = false}) async {
    final item = _current;
    if (item == null) return;
    if (!auto) HapticFeedback.mediumImpact();
    setState(() {
      _rated = true;
      _score += stars;
      _rateCount++;
    });
    // A confident repetition counts as a correct review, so the word moves
    // along the same spaced-repetition schedule as everything else.
    if (item.wordId != null && stars >= 2) {
      try {
        await ref.read(wordsRepoProvider).update(item.wordId!, {
          'last_reviewed': DateTime.now().toUtc().toIso8601String(),
        });
        ref.invalidate(myWordsProvider);
      } catch (_) {/* practice still counted locally */}
    }
  }

  void _next() {
    if (_index + 1 >= _items.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() { _index++; _rated = false; _heard = null; });
    Speech.instance.say(_speakable(_items[_index].en));
  }

  void _replay() {
    setState(() {
      _index = 0;
      _rated = false;
      _finished = false;
      _score = 0;
      _rateCount = 0;
      _heard = null;
    });
    _build();
  }

  int get _percent =>
      _rateCount == 0 ? 0 : ((_score / (_rateCount * 3)) * 100).round();

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final item = _current;

    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg(d),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: SqHeader(
                  title: tr('Айтылым'),
                  onBack: () => Navigator.of(context).pop(),
                  backIcon: PhosphorIconsBold.x),
              ),
              const Spacer(),
              SqEmpty(
                icon: PhosphorIconsFill.microphone,
                title: tr('Жаттығатын сөз жоқ'),
                subtitle: tr('Алдымен сөздікке бірнеше сөз қос'),
                tint: AppColors.sky),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    if (_finished) {
      return Scaffold(
        backgroundColor: AppColors.bg(d),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    SqSquareButton(PhosphorIconsBold.x,
                      onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(tr('Айтылым жаттығуы'),
                        style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: AppColors.text(d))),
                    ),
                  ],
                ),
                const Spacer(),
                SqPanel(
                  radius: 24,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      SqRing(
                        value: _rateCount == 0 ? 0 : _percent / 100,
                        size: 96,
                        stroke: 10,
                        color: _percent >= 70
                            ? AppColors.green
                            : _percent >= 40 ? AppColors.amber : AppColors.red,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SqNum(_rateCount == 0 ? '—' : '$_percent',
                              size: 26, color: AppColors.text(d)),
                            Text(tr('БАЛЛ'),
                              style: TextStyle(
                                fontSize: 9.5, fontWeight: FontWeight.w700,
                                color: AppColors.text3(d))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(tr('Жаттығу бітті'),
                        style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800,
                          color: AppColors.text(d))),
                      const SizedBox(height: 6),
                      Text(trp('{n} сөз айттың', {'n': '$_rateCount'}),
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppColors.text3(d))),
                    ],
                  ),
                ),
                const Spacer(),
                SqAction(tr('Қайтадан'),
                  icon: PhosphorIconsBold.arrowCounterClockwise,
                  onTap: _replay),
                const SizedBox(height: 10),
                SqAction(tr('Дайын'),
                  tone: SqTone.ghost,
                  onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      );
    }

    final syllables = syllablesOf(item!.en);

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        child: SqFill(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
              Row(
                children: [
                  SqSquareButton(PhosphorIconsBold.x,
                    onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(tr('Айтылым жаттығуы'),
                      style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                  ),
                  SqNum('${_index + 1} / ${_items.length}',
                    size: 11.5, color: AppColors.text3(d)),
                ],
              ),
              const SizedBox(height: 16),

              SqPanel(
                radius: 24,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 22),
                child: Column(
                  children: [
                    Text(item.en,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: item.en.length > 12 ? 26 : 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1, color: AppColors.text(d))),
                    if ((item.ipa ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SqNum(item.ipa!,
                        size: 14, weight: FontWeight.w500,
                        color: AppColors.primary),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: AnimatedBuilder(
                        animation: _wave,
                        builder: (_, __) => _Wave(
                          t: _wave.value, live: _holding),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SqLip(
                          fill: AppColors.inkBlock(d),
                          lip: AppColors.inkBlockLip(d),
                          depth: 3,
                          radius: 14,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                          onTap: () => Speech.instance.say(_speakable(item.en)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsFill.speakerHigh,
                                size: 16, color: Colors.white),
                              const SizedBox(width: 7),
                              Text(tr('Үлгіні тыңда'),
                                style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        SqLip(
                          fill: AppColors.muted(d),
                          border: AppColors.border(d),
                          radius: 14,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                          onTap: () => Speech.instance.slow(_speakable(item.en)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsFill.playCircle,
                                size: 16, color: AppColors.text2(d)),
                              const SizedBox(width: 7),
                              Text(tr('Баяу'),
                                style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w800,
                                  color: AppColors.text2(d))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              SqPanel(
                radius: 24,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    SqRing(
                      value: _rateCount == 0 ? 0 : _percent / 100,
                      size: 88,
                      stroke: 9,
                      color: _percent >= 70
                          ? AppColors.green
                          : _percent >= 40 ? AppColors.amber : AppColors.red,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SqNum(_rateCount == 0 ? '—' : '$_percent',
                            size: 23, color: AppColors.text(d)),
                          Text(tr('БАЛЛ'),
                            style: TextStyle(
                              fontSize: 9.5, fontWeight: FontWeight.w700,
                              color: AppColors.text3(d))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr('Буынға бөліп айт'),
                            style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800,
                              color: AppColors.text(d))),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              for (var i = 0; i < syllables.length; i++) ...[
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.soft(
                                        i == syllables.length - 1
                                            ? AppColors.amber
                                            : AppColors.green, d),
                                      borderRadius: BorderRadius.circular(12)),
                                    child: Text(syllables[i],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.onSoft(
                                          i == syllables.length - 1
                                              ? AppColors.amber
                                              : AppColors.green, d))),
                                  ),
                                ),
                                if (i != syllables.length - 1)
                                  const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              if (_rated) ...[
                SqRise(
                  child: Column(
                    children: [
                      Text(tr('Жақсы. Келесі сөзге көшейік.'),
                        style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          color: AppColors.text2(d))),
                      const SizedBox(height: 12),
                      SqAction(
                        _index + 1 >= _items.length
                            ? tr('Жаттығуды бітіру') : tr('Келесі сөз'),
                        trailingIcon: PhosphorIconsBold.arrowRight,
                        onTap: _next),
                    ],
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTapDown: (_) => _holdStart(),
                  onTapUp: (_) => _holdEnd(),
                  onTapCancel: () => _holdEnd(cancelled: true),
                  child: SizedBox(
                    width: 96, height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_holding)
                          SqPulse(
                            child: Container(
                              width: 96, height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary, width: 2)),
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: _holding ? 86 : 80,
                          height: _holding ? 86 : 80,
                          decoration: BoxDecoration(
                            color: _holding
                                ? AppColors.primaryDeep : AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              const BoxShadow(
                                color: AppColors.primaryDeep,
                                offset: Offset(0, 5), blurRadius: 0),
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.55),
                                blurRadius: 26, offset: const Offset(0, 12)),
                            ],
                          ),
                          child: _checking
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.6, color: Colors.white))
                              : const Icon(PhosphorIconsFill.microphone,
                                  size: 34, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _checking
                      ? tr('Тыңдап жатыр…')
                      : _holding
                          ? tr('Айта бер…')
                          : tr('Басып тұрып қайтала'),
                  style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700,
                    color: AppColors.text3(d))),
                const SizedBox(height: 14),

                // The verdict, when there is one.
                if (_heard != null) _Verdict(heard: _heard!),

                // The three buttons stay for the devices that cannot listen,
                // and for the attempt whose request failed. When the model
                // marked it, marking it again would only overwrite a measured
                // score with a guess.
                if (_heard == null && !_checking) ...[
                  Row(
                    children: [
                      Expanded(child: _RateButton(
                        label: tr('Қиын'), tint: AppColors.red,
                        icon: PhosphorIconsFill.smileySad,
                        onTap: () => _rate(1))),
                      const SizedBox(width: 9),
                      Expanded(child: _RateButton(
                        label: tr('Шамалы'), tint: AppColors.amber,
                        icon: PhosphorIconsFill.smileyMeh,
                        onTap: () => _rate(2))),
                      const SizedBox(width: 9),
                      Expanded(child: _RateButton(
                        label: tr('Оңай'), tint: AppColors.green,
                        icon: PhosphorIconsFill.smiley,
                        onTap: () => _rate(3))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _micOk
                        ? tr('Түймені ұстап тұрып айтсаң — өзі тексереді.')
                        : tr('Микрофон қолжетімсіз — өзіңді бағала.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11, height: 1.4, fontWeight: FontWeight.w600,
                      color: AppColors.text4(d))),
                ],
              ],
          ],
        ),
      ),
    );
  }
}

class _Item {
  final String en;
  final String? ipa, wordId;
  const _Item(this.en, this.ipa, this.wordId);
}

class _RateButton extends StatelessWidget {
  final String label;
  final Color tint;
  final IconData icon;
  final VoidCallback onTap;

  const _RateButton({
    required this.label, required this.tint,
    required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqLip(
      fill: AppColors.soft(tint, d),
      border: AppColors.line(tint, d),
      borderWidth: 1.5,
      lip: AppColors.line(tint, d),
      depth: 3,
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.onSoft(tint, d)),
          const SizedBox(height: 5),
          Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800,
              color: AppColors.onSoft(tint, d))),
        ],
      ),
    );
  }
}

/// The bar strip under the word. It idles flat and comes alive while the
/// learner is holding the button, so the screen reacts to them speaking even
/// though nothing is being measured.
class _Wave extends StatelessWidget {
  final double t;
  final bool live;
  const _Wave({required this.t, required this.live});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    // Each bar is 5pt wide with a 3pt gap, so the strip fills whatever width
    // it is given instead of overflowing on a narrow phone.
    return LayoutBuilder(
      builder: (_, box) {
        final bars = ((box.maxWidth + 3) ~/ 8).clamp(8, 34);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < bars; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 5,
                height: live
                    ? 10 + (math.sin((i * 0.7) + t * math.pi * 2).abs() * 38)
                    : 8 + (math.sin(i * 0.8).abs() * 22),
                decoration: BoxDecoration(
                  color: live
                      ? AppColors.primary
                      : AppColors.border(d),
                  borderRadius: BorderRadius.circular(999)),
              ),
              if (i != bars - 1) const SizedBox(width: 3),
            ],
          ],
        );
      },
    );
  }
}

/// What the model heard, and the one thing to fix.
///
/// The heard word is shown even when it is right, because "it heard exactly
/// what you meant" is the reassurance the self-marked version could never
/// give — and when it is wrong, seeing the word it DID hear is the whole
/// lesson.
class _Verdict extends StatelessWidget {
  final Heard heard;
  const _Verdict({required this.heard});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = switch (heard.score) {
      3 => AppColors.green,
      2 => AppColors.amber,
      _ => AppColors.red,
    };

    return SqPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      fill: AppColors.soft(tint, d),
      border: AppColors.line(tint, d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                heard.score >= 2
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsFill.warningCircle,
                size: 20, color: AppColors.onSoft(tint, d)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  heard.heard.isEmpty
                      ? tr('Ештеңе естілмеді')
                      : trp('Естілгені: {p1}', {'p1': heard.heard}),
                  style: TextStyle(
                    fontSize: 14, height: 1.3, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
              ),
              const SizedBox(width: 8),
              // Three dots, filled to the score. A number out of three reads
              // as a mark; three dots read as progress.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < heard.score
                            ? AppColors.onSoft(tint, d)
                            : AppColors.onSoft(tint, d).withValues(alpha: 0.25)),
                    ),
                    if (i < 2) const SizedBox(width: 4),
                  ],
                ],
              ),
            ],
          ),
          if (heard.tip.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(heard.tip,
              style: TextStyle(
                fontSize: 12, height: 1.45, fontWeight: FontWeight.w600,
                color: AppColors.onSoft(tint, d))),
          ],
        ],
      ),
    );
  }
}
