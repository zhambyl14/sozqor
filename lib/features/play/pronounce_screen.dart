// lib/features/play/pronounce_screen.dart
//
// Pronunciation drill.
//
// Vocabulary apps teach recognition and quietly skip production, so learners
// end up with words they can pick out of four options but cannot say. This
// screen is the missing half: hear the model, see the word broken into
// syllables, hold the button and repeat it, then judge yourself.
//
// The self-judgement is deliberate and stated on screen. Automatic scoring
// would need a speech-recognition engine and a microphone permission on every
// platform; an honest three-way self-check ships today, feeds the same spaced
// repetition as every other answer, and never lies to the learner about a
// score it did not measure.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/word.dart';
import '../../providers.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _build());
  }

  @override
  void dispose() {
    _wave.dispose();
    Speech.instance.stop();
    super.dispose();
  }

  void _build() {
    final words = ref.read(myWordsProvider).value ?? const <Word>[];
    final pool = ref.read(levelPoolProvider).value ?? const <DictEntry>[];

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

  Future<void> _rate(int stars) async {
    final item = _current;
    if (item == null) return;
    HapticFeedback.mediumImpact();
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
    setState(() { _index++; _rated = false; });
    Speech.instance.say(_speakable(_items[_index].en));
  }

  void _replay() {
    setState(() {
      _index = 0;
      _rated = false;
      _finished = false;
      _score = 0;
      _rateCount = 0;
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
                  onTapDown: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _holding = true);
                  },
                  onTapUp: (_) => setState(() => _holding = false),
                  onTapCancel: () => setState(() => _holding = false),
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
                          child: const Icon(PhosphorIconsFill.microphone,
                            size: 34, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_holding ? tr('Айта бер…') : tr('Басып тұрып қайтала'),
                  style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700,
                    color: AppColors.text3(d))),
                const SizedBox(height: 14),
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
                  tr('Автотексеру келесі нұсқада. Қазір өзіңді бағалайсың.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11, height: 1.4, fontWeight: FontWeight.w600,
                    color: AppColors.text4(d))),
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
                      : (d ? AppColors.borderD : const Color(0xFFE7E4F3)),
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
