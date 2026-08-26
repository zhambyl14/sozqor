// lib/features/words/add_word_screen.dart
//
// Adding a word is one field and one button. SozQor AI detects the language,
// translates, and fills in part of speech, definition, synonyms, antonyms,
// example, level and topic — the learner never has to classify anything.
//
// The manual form is always one tap away and is opened automatically when a
// lookup fails, with whatever was typed already dropped into the right side.
// A failed translation must never be a dead end.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/sozqor_ai.dart';
import '../../services/speech.dart';
import '../auth/guest_gate.dart';

class AddWordScreen extends ConsumerStatefulWidget {
  /// Pass a word to edit it instead of creating a new one.
  final Word? editing;
  /// Pre-fill the input, used by the catalog "add" flow.
  final String? initialTerm;

  const AddWordScreen({super.key, this.editing, this.initialTerm});

  @override
  ConsumerState<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends ConsumerState<AddWordScreen> {
  final _input = TextEditingController();
  final _kk    = TextEditingController();
  final _en    = TextEditingController();
  final _ru    = TextEditingController();
  final _ex    = TextEditingController();
  final _def   = TextEditingController();

  DictEntry? _found;
  AiSource? _source;
  String _cefr = 'A2';
  String _topic = 'general';
  List<String> _syn = const [];
  List<String> _ant = const [];
  String? _pos, _ipa, _emoji;

  bool _looking = false;
  bool _saving = false;
  bool _manual = false;
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final w = widget.editing;
    if (w != null) {
      _kk.text = w.kk; _en.text = w.en;
      _ru.text = w.ru ?? '';
      _ex.text = w.exampleEn ?? '';
      _def.text = w.definitionEn ?? '';
      _cefr = w.cefr; _topic = w.topic;
      _syn = w.synonyms; _ant = w.antonyms;
      _pos = w.pos; _ipa = w.transcription; _emoji = w.emoji;
      _manual = true;
    } else if ((widget.initialTerm ?? '').isNotEmpty) {
      _input.text = widget.initialTerm!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _input.dispose(); _kk.dispose(); _en.dispose(); _ru.dispose();
    _ex.dispose(); _def.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final term = _input.text.trim();
    if (term.isEmpty) {
      setState(() => _error = tr('Алдымен сөз жаз'));
      return;
    }
    setState(() { _looking = true; _error = null; });

    try {
      final res = await SozQorAI.instance.translate(term);
      if (!mounted) return;
      final e = res.entry;
      setState(() {
        _found  = e;
        _source = res.source;
        _kk.text  = e.kk;
        _en.text  = e.en;
        _ru.text  = e.ru ?? '';
        _ex.text  = e.exampleEn ?? '';
        _def.text = e.definitionEn ?? '';
        _cefr  = kCefrCodes.contains(e.cefr) ? e.cefr : 'A2';
        _topic = kTopics.any((t) => t.key == e.topic) ? e.topic : 'general';
        _syn = e.synonyms; _ant = e.antonyms;
        _pos = e.pos; _ipa = e.ipa; _emoji = e.emoji;
        // A bare word pair deserves a nudge to fill in the rest.
        if (res.isBasic) _manual = true;
      });
    } catch (e) {
      if (!mounted) return;
      _prefillManually(term);
      setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  /// Kazakh has 9 letters Russian does not (әғқңөұүһі) — only those tell the
  /// two apart, since every plain Russian letter is also valid Cyrillic.
  /// Cyrillic without one of those nine goes to the Russian field, and
  /// anything in the Latin alphabet is treated as the English side.
  void _prefillManually(String term) {
    final kazakhOnly =
        RegExp(r'[әғқңөұүһі]', caseSensitive: false).hasMatch(term);
    final cyrillic = RegExp(r'[Ѐ-ӿ]').hasMatch(term);
    setState(() {
      _manual = true;
      if (kazakhOnly) {
        if (_kk.text.trim().isEmpty) _kk.text = term;
      } else if (cyrillic) {
        if (_ru.text.trim().isEmpty) _ru.text = term;
      } else {
        if (_en.text.trim().isEmpty) _en.text = term.toLowerCase();
      }
    });
  }

  Future<void> _save() async {
    final kk = _kk.text.trim();
    final en = _en.text.trim();
    if (kk.isEmpty || en.isEmpty) {
      setState(() => _error = tr('Қазақша және ағылшынша сөз керек'));
      return;
    }

    // Guests can look words up all they like; keeping one needs an account.
    if (!_isEdit &&
        !await requireAccount(context, ref, GuestFeature.saveWord)) {
      return;
    }
    if (!mounted) return;

    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(wordsRepoProvider);

      if (_isEdit) {
        await repo.update(widget.editing!.id, {
          'kk': kk, 'en': en,
          'ru': _ru.text.trim().isEmpty ? null : _ru.text.trim(),
          'definition_en': _def.text.trim().isEmpty ? null : _def.text.trim(),
          'example_en': _ex.text.trim().isEmpty ? null : _ex.text.trim(),
          'synonyms': _syn, 'antonyms': _ant,
          'cefr': _cefr, 'topic': _topic,
          'pos': _pos, 'transcription': _ipa, 'emoji': _emoji,
        });
      } else {
        if (await repo.exists(kk, en)) {
          setState(() {
            _saving = false; _error = tr('Бұл сөз сөздігіңде бар');
          });
          return;
        }
        await repo.add(
          kk: kk, en: en, ru: _ru.text, pos: _pos,
          definitionEn: _def.text.trim().isEmpty ? null : _def.text.trim(),
          exampleEn: _ex.text.trim().isEmpty ? null : _ex.text.trim(),
          transcription: _ipa, emoji: _emoji,
          synonyms: _syn, antonyms: _ant,
          cefr: _cefr, topic: _topic,
          source: _found == null ? 'manual' : 'ai',
          dictionaryId: _found?.id,
        );
        await ref.read(profileRepoProvider).bumpWordsAdded();
        final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
        await ref.read(eventsRepoProvider).bumpByMetric(cefr, 'words');
      }

      refreshAll(ref);
      ref.invalidate(eventProgressProvider);
      if (mounted) {
        sqSnack(context,
          _isEdit ? tr('Жаңартылды') : tr('Сөз сақталды · +10 тәжірибе'));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final filled = _kk.text.trim().isNotEmpty && _en.text.trim().isNotEmpty;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: _isEdit ? tr('Сөзді өңдеу') : tr('Сөз қосу'),
          eyebrow: _isEdit ? null : tr('Бір өріс жеткілікті'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (!_isEdit) ...[
          SqInkCard(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14)),
                      child: const Icon(PhosphorIconsFill.magicWand,
                        color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr('Автоматты толтыру'),
                            style: const TextStyle(
                              color: Colors.white, fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3)),
                          const SizedBox(height: 2),
                          Text(
                            tr('Қай тілде жазсаң да өзі табады'),
                            style: const TextStyle(
                              color: AppColors.onInk2, fontSize: 11.5,
                              height: 1.35, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: TextField(
                    controller: _input,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _lookup(),
                    style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800,
                      color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: tr('алма · apple · яблоко'),
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 16),
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SqAction(tr('Тап'),
                  icon: PhosphorIconsFill.lightning,
                  tone: SqTone.primary,
                  busy: _looking,
                  onTap: _lookup),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (_error != null) ...[
          SqPanel(
            radius: 18,
            padding: const EdgeInsets.all(14),
            fill: AppColors.soft(AppColors.amber, d),
            border: AppColors.line(AppColors.amber, d),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(PhosphorIconsFill.info,
                  size: 19, color: AppColors.amber),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                        style: TextStyle(
                          fontSize: 12.5, height: 1.4,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSoft(AppColors.amber, d))),
                      const SizedBox(height: 3),
                      Text(tr('Өрістерді өзің толтыра бересің.'),
                        style: TextStyle(
                          fontSize: 11.5, height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSoft(AppColors.amber, d)
                              .withValues(alpha: 0.85))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (filled) ...[
          _Preview(
            kk: _kk.text, en: _en.text, ru: _ru.text,
            ipa: _ipa, pos: _pos,
            definition: _def.text,
            example: _ex.text,
            synonyms: _syn, antonyms: _ant,
            cefr: _cefr, topic: _topic,
            source: _source),
          const SizedBox(height: 14),
        ],

        if (filled || _manual || _isEdit)
          SqPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _manual = !_manual),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsBold.slidersHorizontal,
                        size: 17, color: AppColors.text2(d)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(tr('Қолмен түзету'),
                          style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800,
                            color: AppColors.text(d))),
                      ),
                      Icon(_manual
                          ? PhosphorIconsBold.caretUp
                          : PhosphorIconsBold.caretDown,
                        size: 15, color: AppColors.text3(d)),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: !_manual
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            _Field(label: tr('Қазақша'), controller: _kk,
                              onChanged: () => setState(() {})),
                            const SizedBox(height: 12),
                            _Field(label: tr('Ағылшынша'), controller: _en,
                              onChanged: () => setState(() {})),
                            const SizedBox(height: 12),
                            _Field(label: tr('Орысша'), controller: _ru),
                            const SizedBox(height: 12),
                            _Field(label: tr('Ағылшынша мағынасы'),
                              controller: _def, lines: 2),
                            const SizedBox(height: 12),
                            _Field(label: tr('Мысал сөйлем'),
                              controller: _ex, lines: 2),
                            const SizedBox(height: 16),
                            SqEyebrow(tr('Деңгей')),
                            const SizedBox(height: 8),
                            Wrap(spacing: 7, runSpacing: 7, children: [
                              for (final c in kCefrCodes)
                                SqChip(c,
                                  tint: AppColors.tiers[
                                    cefrIndex(c).clamp(0, 4)],
                                  selected: c == _cefr,
                                  outlined: true,
                                  onTap: () => setState(() => _cefr = c)),
                            ]),
                            const SizedBox(height: 16),
                            SqEyebrow(tr('Тақырып')),
                            const SizedBox(height: 8),
                            Wrap(spacing: 7, runSpacing: 7, children: [
                              for (final t in kTopics)
                                SqChip(t.label,
                                  tint: AppColors.topic(t.key),
                                  selected: t.key == _topic,
                                  outlined: true,
                                  onTap: () =>
                                      setState(() => _topic = t.key)),
                            ]),
                          ],
                        ),
                ),
              ],
            ),
          ),

        if (!filled && !_manual && !_isEdit) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _manual = true),
              child: Text(tr('Қолмен түзету'))),
          ),
        ],

        const SizedBox(height: 20),
        SqAction(tr('Сақтау'),
          icon: PhosphorIconsBold.check,
          busy: _saving,
          onTap: filled ? _save : null),
      ],
    );
  }
}

// ── Result preview ─────────────────────────────────────────

class _Preview extends StatelessWidget {
  final String kk, en, definition, example, cefr, topic;
  final String? ipa, pos, ru;
  final List<String> synonyms, antonyms;
  final AiSource? source;

  const _Preview({
    required this.kk, required this.en,
    required this.definition, required this.example,
    required this.cefr, required this.topic,
    required this.synonyms, required this.antonyms,
    this.ipa, this.pos, this.ru, this.source,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final t = topicOf(topic);

    return SqPanel(
      border: AppColors.primaryEdge,
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
                    Text(en,
                      style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        letterSpacing: -0.5, color: AppColors.text(d))),
                    if ((ipa ?? '').isNotEmpty)
                      SqNum(ipa!,
                        size: 12.5, weight: FontWeight.w500,
                        color: AppColors.text3(d)),
                    const SizedBox(height: 3),
                    Text(kk,
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                    if ((ru ?? '').trim().isNotEmpty)
                      Text(ru!,
                        style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          color: AppColors.text3(d))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqBadge(cefr, tint: AppColors.sky),
                  const SizedBox(height: 7),
                  SqSquareButton(PhosphorIconsFill.speakerHigh,
                    size: 38,
                    fill: AppColors.muted(d),
                    border: AppColors.border(d),
                    onTap: () => Speech.instance.say(en)),
                ],
              ),
            ],
          ),

          if (definition.trim().isNotEmpty) ...[
            const SizedBox(height: 13),
            _Block(tr('Ағылшынша мағынасы'), definition, d),
          ],
          if (example.trim().isNotEmpty) ...[
            const SizedBox(height: 11),
            _Block(tr('Мысал сөйлем'), '«$example»', d, italic: true),
          ],

          if (synonyms.isNotEmpty) ...[
            const SizedBox(height: 12),
            SqEyebrow(tr('Синоним'), size: 9.5),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in synonyms)
                SqBadge(s, tint: AppColors.green, size: 11.5),
            ]),
          ],
          if (antonyms.isNotEmpty) ...[
            const SizedBox(height: 10),
            SqEyebrow(tr('Антоним'), size: 9.5),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in antonyms)
                SqBadge(a, tint: AppColors.red, size: 11.5),
            ]),
          ],

          const SizedBox(height: 14),
          Row(
            children: [
              SqBadge(t.label, tint: AppColors.topic(topic)),
              if ((pos ?? '').isNotEmpty) ...[
                const SizedBox(width: 7),
                SqBadge(pos!, tint: AppColors.text3(d)),
              ],
              const Spacer(),
              if (source != null)
                Flexible(
                  child: Text(_sourceText(source!),
                    style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w600,
                      color: AppColors.text4(d))),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _sourceText(AiSource s) => switch (s) {
    AiSource.memory  => tr('жадтан'),
    AiSource.bundled => tr('офлайн сөздіктен'),
    AiSource.shared  => tr('сөздік базадан'),
    AiSource.llm     => tr('AI тапты'),
    AiSource.basic   => tr('жылдам аударма · толықтыр'),
  };
}

class _Block extends StatelessWidget {
  final String label, value;
  final bool d, italic;
  const _Block(this.label, this.value, this.d, {this.italic = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SqEyebrow(label, size: 9.5),
      const SizedBox(height: 4),
      Text(value,
        style: TextStyle(
          fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
          color: AppColors.text2(d),
          fontStyle: italic ? FontStyle.italic : null)),
    ],
  );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int lines;
  final VoidCallback? onChanged;

  const _Field({
    required this.label, required this.controller,
    this.lines = 1, this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SqEyebrow(label),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        maxLines: lines,
        style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700,
          color: AppColors.text(isDark(context))),
        onChanged: (_) => onChanged?.call(),
      ),
    ],
  );
}
