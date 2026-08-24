// lib/features/moderator/word_editor_screen.dart
//
// One dictionary entry, editable (EN-33 / EN-38 / EN-50 / KK-7).
//
// The fields are the ones a round actually reads. `definition_en` feeds the
// definition question, `synonyms` and `antonyms` feed two more question kinds,
// and `cefr` decides which learners ever see the word at all — so a wrong
// level is not cosmetic, it is a word nobody will be shown.
//
// Deleting detaches every learner's copy first. The words themselves survive:
// somebody has been studying them, and a bad shared entry is not a reason to
// empty their bank.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';

class WordEditorScreen extends ConsumerStatefulWidget {
  /// Null when adding a new word.
  final DictEntry? entry;
  const WordEditorScreen({super.key, this.entry});

  @override
  ConsumerState<WordEditorScreen> createState() => _WordEditorScreenState();
}

class _WordEditorScreenState extends ConsumerState<WordEditorScreen> {
  late final _en = TextEditingController(text: widget.entry?.en ?? '');
  late final _kk = TextEditingController(text: widget.entry?.kk ?? '');
  late final _ru = TextEditingController(text: widget.entry?.ru ?? '');
  late final _pos = TextEditingController(text: widget.entry?.pos ?? '');
  late final _definition =
      TextEditingController(text: widget.entry?.definitionEn ?? '');
  late final _example =
      TextEditingController(text: widget.entry?.exampleEn ?? '');
  late final _ipa = TextEditingController(text: widget.entry?.ipa ?? '');
  late final _emoji = TextEditingController(text: widget.entry?.emoji ?? '');
  late final _synonyms =
      TextEditingController(text: widget.entry?.synonyms.join(', ') ?? '');
  late final _antonyms =
      TextEditingController(text: widget.entry?.antonyms.join(', ') ?? '');

  late String _cefr = widget.entry?.cefr ?? 'A2';
  late String _topic = widget.entry?.topic ?? 'general';
  late bool _verified = widget.entry?.verified ?? true;
  bool _busy = false;

  bool get _isNew => widget.entry?.id == null;

  @override
  void dispose() {
    for (final c in [_en, _kk, _ru, _pos, _definition, _example, _ipa,
                     _emoji, _synonyms, _antonyms]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(TextEditingController c) => c.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (_en.text.trim().isEmpty || _kk.text.trim().isEmpty) {
      sqSnack(context, tr('Ағылшын және қазақша нұсқасы міндетті'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(moderatorRepoProvider).saveWord(
        id: widget.entry?.id,
        en: _en.text, kk: _kk.text, ru: _ru.text,
        pos: _pos.text.trim().isEmpty ? null : _pos.text.trim(),
        definitionEn:
            _definition.text.trim().isEmpty ? null : _definition.text.trim(),
        exampleEn: _example.text.trim().isEmpty ? null : _example.text.trim(),
        ipa: _ipa.text.trim().isEmpty ? null : _ipa.text.trim(),
        emoji: _emoji.text.trim().isEmpty ? null : _emoji.text.trim(),
        cefr: _cefr, topic: _topic,
        synonyms: _split(_synonyms), antonyms: _split(_antonyms),
        verified: _verified);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.entry?.id;
    if (id == null) return;
    final ok = await sqConfirm(context,
      title: tr('Сөзді жою'),
      message: trp('«{p1}» ортақ базадан жойылсын ба? Оны сақтаған '
          'адамдардың сөздігінде қалады.', {'p1': widget.entry!.en}),
      confirm: tr('Жою'));
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(moderatorRepoProvider).deleteWord(id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: _isNew ? tr('Жаңа сөз') : tr('Сөзді өңдеу'),
          eyebrow: tr('Сөз базасы'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        _Field(controller: _en, label: tr('Ағылшынша'), autofocus: _isNew),
        _Field(controller: _kk, label: tr('Қазақша')),
        _Field(controller: _ru, label: tr('Орысша')),
        _Field(controller: _pos, label: tr('Сөз табы')),
        _Field(controller: _definition, label: tr('Анықтамасы'), lines: 2),
        _Field(controller: _example, label: tr('Мысал сөйлем'), lines: 2),
        _Field(controller: _ipa, label: tr('Транскрипция')),
        _Field(controller: _emoji, label: tr('Эмодзи')),
        // Comma-separated because that is how they read back, and a chip
        // editor for a field a moderator touches once is more UI than the job
        // needs.
        _Field(controller: _synonyms, label: tr('Синонимдер (үтірмен)')),
        _Field(controller: _antonyms, label: tr('Антонимдер (үтірмен)')),

        const SizedBox(height: 6),
        SqEyebrow(tr('Деңгей')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final c in kCefrCodes) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _cefr = c),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: c == _cefr
                          ? AppColors.primary : AppColors.card(d),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: c == _cefr
                            ? AppColors.primary : AppColors.border(d)),
                    ),
                    alignment: Alignment.center,
                    child: SqNum(c,
                      size: 12,
                      color: c == _cefr ? Colors.white : AppColors.text2(d)),
                  ),
                ),
              ),
              if (c != kCefrCodes.last) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 16),

        SqEyebrow(tr('Тақырып')),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in kTopics) ...[
                SqChip(tr(t.label),
                  tint: AppColors.topic(t.key),
                  selected: _topic == t.key,
                  outlined: true,
                  radius: 999,
                  onTap: () => setState(() => _topic = t.key)),
                const SizedBox(width: 7),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        SqPanel(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _verified,
            onChanged: (v) => setState(() => _verified = v),
            title: Text(tr('Тексерілді'),
              style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            subtitle: Text(tr('Адам қарап шықты — AI жазғаннан жоғары тұрады'),
              style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
          ),
        ),
        const SizedBox(height: 20),

        SqAction(_isNew ? tr('Қосу') : tr('Сақтау'),
          icon: PhosphorIconsBold.check,
          busy: _busy,
          onTap: _busy ? null : _save),

        if (!_isNew) ...[
          const SizedBox(height: 10),
          SqAction(tr('Сөзді жою'),
            icon: PhosphorIconsBold.trash,
            tone: SqTone.danger,
            height: 50,
            onTap: _busy ? null : _delete),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int lines;
  final bool autofocus;

  const _Field({
    required this.controller,
    required this.label,
    this.lines = 1,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
