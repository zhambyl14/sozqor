// lib/features/play/ai_chat_screen.dart
//
// Conversation practice.
//
// Recognising a word in a multiple-choice list is not the same as producing
// it, so 4.0 adds a role-play: pick a situation, type replies, and get a
// partner that always answers with another question. Words the learner has in
// their bank are underlined when the partner uses them, and can be added on
// the spot when they are new.
//
// The reply comes from the `sozqor-ai` edge function when it is reachable, and
// from a short scripted tutor when it is not — the drill has to work on a bad
// connection, which is when people actually practise.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/sozqor_ai.dart';
import '../../services/speech.dart';

/// Scenario names double as the key the scripted tutor and the server look up,
/// so they stay Kazakh here and are translated where they are shown.
const _scenarios = [
  'Кофеханада', 'Әуежайда', 'Жұмыс сұхбаты', 'Дүкенде', 'Дәрігерде',
];

class _Msg {
  final String text;
  final bool mine;
  /// A word in this message that is worth saving.
  final String? newWord;
  const _Msg(this.text, this.mine, {this.newWord});
}

class AiChatScreen extends ConsumerStatefulWidget {
  /// Optional word to steer the opening line — used by "Күннің сөзі".
  final String? seedWord;
  const AiChatScreen({super.key, this.seedWord});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  final Set<String> _saved = {};

  String _scenario = _scenarios.first;
  bool _busy = false;
  int _earned = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    Speech.instance.stop();
    super.dispose();
  }

  void _greet() {
    final seed = widget.seedWord;
    setState(() {
      _messages
        ..clear()
        ..add(_Msg(
          seed == null
              ? tr('Сәлем! Жағдайды таңда да, ағылшынша жауап бере бер. '
                   'Қателессең — түзетіп отырамын.')
              : trp('Сәлем! Бүгін «{w}» сөзін қолданып көрейік. '
                    'Дайын болсаң, жаза бер.', {'w': seed}),
          false))
        // Scripted, not AI-generated: the scene's opener never needs a
        // network round trip, and never risks a weak model producing a line
        // that ignores the scene entirely.
        ..add(_Msg(SozQorAI.instance.openingLine(_scenario), false));
    });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  Future<void> _ask({required String mine}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cefr = ref.read(myProfileProvider).value?.cefrLevel ?? 'A1';

      // Who said which line matters as much as the lines themselves. The edge
      // function pastes these into the prompt under "Conversation so far", and
      // an unlabelled wall of sentences gives the model no way to tell the
      // learner's words from its own — which is exactly how a reply ends up
      // answering something nobody asked.
      //
      // The final entry is dropped because it is the turn being sent as
      // `message`; including it as well had the model reading the same
      // sentence twice and echoing it back.
      final past = _messages.isEmpty
          ? const <_Msg>[]
          : _messages.sublist(0, _messages.length - 1);

      final reply = await SozQorAI.instance.chat(
        scenario: _scenario,
        cefr: cefr,
        message: mine,
        studyLang: ref.read(nativeLangProvider),
        history: [
          for (final m in past) '${m.mine ? 'Learner' : 'You'}: ${m.text}',
        ],
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(reply, false, newWord: _pickNewWord(reply)));
        _earned += 6;
      });
      _scrollDown();
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The longest word in the reply that the learner does not own yet — that is
  /// the one worth offering to save.
  String? _pickNewWord(String reply) {
    final owned = {
      for (final w in ref.read(myWordsProvider).value ?? const <Word>[])
        w.en.toLowerCase()
    };
    final candidates = reply
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.length >= 6 && !owned.contains(w) && !_saved.contains(w))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() => _messages.add(_Msg(text, true)));
    _scrollDown();
    await _ask(mine: text);
  }

  Future<void> _save(String word) async {
    setState(() => _saved.add(word));
    try {
      final entry = await SozQorAI.instance.translate(word);
      await ref.read(wordsRepoProvider).addFromDict(entry.entry);
      ref.invalidate(myWordsProvider);
      if (mounted) sqSnack(context, trp('«{w}» сөздікке қосылды', {'w': word}));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  void _switchScenario(String s) {
    setState(() {
      _scenario = s;
      _messages
        ..clear()
        ..add(_Msg(SozQorAI.instance.openingLine(s), false));
      _earned = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final cefr = ref.watch(myProfileProvider).value?.cefrLevel ?? 'A1';

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  SqSquareButton(PhosphorIconsBold.arrowLeft,
                    onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 11),
                  const SqTintBox(PhosphorIconsFill.robot,
                    size: 38, solid: true),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('AI әңгіме'),
                          style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: AppColors.text(d))),
                        Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.green,
                                shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                trp('{s} · {cefr} деңгей',
                                  {'s': tr(_scenario), 'cefr': cefr}),
                                style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: AppColors.text3(d))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.soft(AppColors.amber, d),
                      borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(PhosphorIconsFill.star,
                          size: 13, color: AppColors.amber),
                        const SizedBox(width: 5),
                        SqNum('+$_earned',
                          size: 11.5, color: AppColors.amberInk),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  for (final s in _scenarios) ...[
                    SqChip(tr(s),
                      selected: s == _scenario,
                      outlined: true,
                      radius: 999,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                      onTap: _busy ? null : () => _switchScenario(s)),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                itemCount: _messages.length + (_busy ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 11),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) return const _Typing();
                  final m = _messages[i];
                  return _Bubble(
                    message: m,
                    onSave: m.newWord == null ? null : () => _save(m.newWord!),
                    onSpeak: m.mine ? null : () => Speech.instance.say(m.text),
                  );
                },
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(
                18, 0, 18, MediaQuery.of(context).viewInsets.bottom > 0 ? 10 : 14),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.card(d),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border(d)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600,
                          color: AppColors.text(d)),
                        decoration: InputDecoration(
                          hintText: tr('Жауабыңды жаз…'),
                          filled: false,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppColors.text4(d)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SqSquareButton(PhosphorIconsFill.paperPlaneRight,
                      size: 42,
                      fill: AppColors.primary,
                      lip: AppColors.primaryDeep,
                      iconColor: Colors.white,
                      onTap: _busy ? null : _send),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg message;
  final VoidCallback? onSave, onSpeak;
  const _Bubble({required this.message, this.onSave, this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final mine = message.mine;

    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.card(d),
              border: mine ? null : Border.all(color: AppColors.border(d)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.text,
                  style: TextStyle(
                    fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w600,
                    color: mine ? Colors.white : AppColors.text(d))),
                if (onSave != null || onSpeak != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onSave != null)
                        SqChip(
                          trp('{w} — сөздікке қос',
                            {'w': '${message.newWord}'}),
                          icon: PhosphorIconsFill.plusCircle,
                          radius: 9,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                          onTap: onSave),
                      if (onSave != null && onSpeak != null)
                        const SizedBox(width: 7),
                      if (onSpeak != null)
                        GestureDetector(
                          onTap: onSpeak,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.muted(d),
                              borderRadius: BorderRadius.circular(9)),
                            child: Icon(PhosphorIconsFill.speakerHigh,
                              size: 14, color: AppColors.text2(d)),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card(d),
          border: Border.all(color: AppColors.border(d)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                child: SqPulse(
                  period: Duration(milliseconds: 700 + i * 160),
                  child: Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.text4(d), shape: BoxShape.circle)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
