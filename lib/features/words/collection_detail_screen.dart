// lib/features/words/collection_detail_screen.dart
//
// One collection: its words, and — for a collection the learner owns — the "+"
// that EN-34 is really about.
//
// "Users can add existing Dictionary words to their collection using a '+'
// action. Do not make them manually enter words that already exist." So adding
// is a picker over the bank with a search box, and nothing here has a field
// for typing a word into.
//
// Paged twenty at a time (EN-36 / EN-54). A pack a moderator can top up is
// exactly the kind of list that grows without a ceiling, and the old screens
// in this app were built on the assumption that a list is always short.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/collection.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/word.dart';
import '../../data/repos/collections_repo.dart';
import '../../data/repos/words_repo.dart' show kWordPageSize;
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/question_factory.dart';
import '../play/play_session_screen.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  final WordCollection collection;
  const CollectionDetailScreen({super.key, required this.collection});

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  List<DictEntry> _words = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _busy = false;
  String? _error;
  late int _count = widget.collection.wordCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _words = const [];
      _exhausted = false;
    });
    await _fetch();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetch() async {
    try {
      final page = await ref.read(collectionsRepoProvider)
          .words(widget.collection.id,
              limit: kWordPageSize, offset: _words.length);
      if (!mounted) return;
      setState(() {
        _words = [..._words, ...page];
        _exhausted = page.length < kWordPageSize;
      });
    } on CollectionsUnavailable {
      if (mounted) {
        setState(() => _error = tr('Топтама жүйесі әлі қосылмаған'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _exhausted) return;
    setState(() => _loadingMore = true);
    await _fetch();
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _addWords() async {
    final picked = await showModalBottomSheet<List<Word>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PickFromBankSheet(),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() => _busy = true);
    var added = 0;
    try {
      for (final w in picked) {
        // Only a word that came from the shared dictionary can be added: a
        // pack entry points at a dictionary row, and a hand-typed word has no
        // such row to point at.
        if (w.dictionaryId == null) continue;
        _count = await ref.read(collectionsRepoProvider)
            .addWord(widget.collection.id, w.dictionaryId!);
        added++;
      }
      if (!mounted) return;
      sqSnack(context, added == 0
          ? tr('Бұл сөздер ортақ базадан емес — қосу мүмкін болмады')
          : trp('{n} сөз қосылды', {'n': '$added'}));
      await _load();
      ref.invalidate(collectionsProvider);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeWord(DictEntry e) async {
    setState(() => _busy = true);
    try {
      // Every entry came out of a pack, so it has a dictionary id by
      // construction; the model's nullable id is for entries built locally.
      _count = await ref.read(collectionsRepoProvider)
          .removeWord(widget.collection.id, e.id ?? 0);
      if (!mounted) return;
      setState(() => _words = _words.where((x) => x.id != e.id).toList());
      ref.invalidate(collectionsProvider);
    } catch (err) {
      if (mounted) sqSnack(context, humanError(err), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Plays the collection. Built from the words actually in it, so a round can
  /// never claim more questions than the pack holds — which is the learner-
  /// facing half of the "120 words, 14 questions" bug.
  Future<void> _play() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';

    // Everything, not just the loaded page: a round over the first twenty
    // would quietly ignore the rest of the collection.
    var all = _words;
    if (!_exhausted) {
      try {
        all = await ref.read(collectionsRepoProvider)
            .words(widget.collection.id, limit: 100, offset: 0);
      } catch (_) {
        // Fall back to what is on screen rather than refusing to play.
      }
    }

    final questions = QuestionFactory.build(
      items: all.map(PlayItem.fromDict).toList(),
      pool: all,
      kinds: kindsFor(cefr),
      count: all.length < 10 ? all.length : 10,
      nativeLang: ref.read(nativeLangProvider),
    );
    if (!mounted) return;
    if (questions.isEmpty) {
      sqSnack(context, tr('Сұрақ құрастыру мүмкін болмады'), error: true);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaySessionScreen(
        mode: PlayMode.classic,
        preset: questions,
        title: widget.collection.title)));
    if (mounted) refreshAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final c = widget.collection;
    final lang = ref.watch(nativeLangProvider);
    final tint = sqHexColor(c.colour) ?? AppColors.primary;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: _load,
      children: [
        SqHeader(
          title: c.title,
          eyebrow: c.isMine ? tr('Менің топтамам') : tr('Ресми топтама'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        SqInkCard(
          padding: const EdgeInsets.all(18),
          glow: tint,
          glowAt: Alignment.topRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The number is count(*) from the server, not a
                        // literal compiled into the app.
                        SqCountUp(_count, size: 26, color: Colors.white),
                        Text(tr('сөз'),
                          style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: AppColors.onInk3)),
                      ],
                    ),
                  ),
                  if (c.subtitle.isNotEmpty)
                    Flexible(
                      child: Text(c.subtitle,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5, height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onInk2)),
                    ),
                ],
              ),
              const SizedBox(height: 15),
              SqAction(tr('Жаттығуды бастау'),
                icon: PhosphorIconsFill.play,
                onTap: _count == 0 || _busy ? null : _play),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (c.isMine)
          SqAction(tr('Сөздігімнен сөз қосу'),
            icon: PhosphorIconsBold.plus,
            tone: SqTone.ghost,
            height: 50,
            busy: _busy,
            onTap: _busy ? null : _addWords),
        if (c.isMine) const SizedBox(height: 16),

        if (_loading)
          const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()])
        else if (_error != null && _words.isEmpty)
          SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Топтама жүктелмеді'),
            subtitle: _error,
            action: SizedBox(
              width: 200,
              child: SqAction(tr('Қайталау'),
                icon: PhosphorIconsBold.arrowClockwise, onTap: _load),
            ))
        else if (_words.isEmpty)
          SqEmpty(
            icon: PhosphorIconsFill.folderOpen,
            title: tr('Топтама бос'),
            subtitle: c.isMine
                ? tr('Сөздігіңнен сөз қосып баста')
                : tr('Бұл топтамаға әлі сөз қосылмаған'),
            tint: AppColors.sky)
        else ...[
          SqGroup(children: [
            for (final e in _words)
              SqTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.muted(d),
                    borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: SqNum(
                    e.en.isNotEmpty ? e.en[0].toUpperCase() : '?',
                    size: 15, color: tint),
                ),
                title: e.en,
                subtitle: e.native(lang),
                trailing: c.isMine
                    ? SqSquareButton(PhosphorIconsBold.minus,
                        size: 30,
                        fill: AppColors.soft(AppColors.red, d),
                        border: Colors.transparent,
                        iconColor: AppColors.red,
                        onTap: _busy ? null : () => _removeWord(e))
                    : null,
              ),
          ]),
          if (!_exhausted) ...[
            const SizedBox(height: 14),
            SqAction(_loadingMore ? tr('Жүктелуде…') : tr('Тағы жүктеу'),
              icon: PhosphorIconsBold.arrowDown,
              tone: SqTone.ghost,
              height: 48,
              busy: _loadingMore,
              onTap: _loadingMore ? null : _more),
          ],
        ],
      ],
    );
  }
}

/// Picking words out of the bank. The whole of EN-34's "do not make them
/// manually enter words that already exist" is this sheet existing.
class _PickFromBankSheet extends ConsumerStatefulWidget {
  const _PickFromBankSheet();

  @override
  ConsumerState<_PickFromBankSheet> createState() => _PickFromBankSheetState();
}

class _PickFromBankSheetState extends ConsumerState<_PickFromBankSheet> {
  final _search = TextEditingController();
  final Set<String> _picked = {};

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final lang = ref.watch(nativeLangProvider);
    final all = ref.watch(wordBankProvider).words;
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : all.where((w) =>
            w.en.toLowerCase().contains(q) ||
            w.kk.toLowerCase().contains(q)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SqSheetGrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  children: [
                    Text(tr('Сөз таңдау'),
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.card(d),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border(d)),
                      ),
                      child: Row(
                        children: [
                          Icon(PhosphorIconsBold.magnifyingGlass,
                            size: 17, color: AppColors.text4(d)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600,
                                color: AppColors.text(d)),
                              decoration: InputDecoration(
                                hintText: tr('Сөз іздеу…'),
                                filled: false, isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: shown.isEmpty
                    ? SqEmpty(
                        icon: PhosphorIconsFill.books,
                        title: tr('Сөз табылмады'),
                        subtitle: tr('Алдымен сөздігіңе сөз қос'),
                        tint: AppColors.sky)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final w = shown[i];
                          final on = _picked.contains(w.id);
                          // A word typed by hand has no dictionary row, so it
                          // cannot be a pack entry. Saying so on the row is
                          // better than letting it be picked and then
                          // silently skipped.
                          final addable = w.dictionaryId != null;
                          return SqGroupRow(
                            first: i == 0,
                            last: i == shown.length - 1,
                            child: SqTile(
                              fill: on
                                  ? AppColors.soft(AppColors.primary, d)
                                  : null,
                              title: w.en,
                              subtitle: addable
                                  ? w.native(lang)
                                  : tr('Ортақ базада жоқ'),
                              titleColor: addable
                                  ? AppColors.text(d) : AppColors.text3(d),
                              trailing: !addable
                                  ? null
                                  : AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      width: 26, height: 26,
                                      decoration: BoxDecoration(
                                        color: on
                                            ? AppColors.primary
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: on
                                              ? AppColors.primary
                                              : AppColors.border(d),
                                          width: 2),
                                      ),
                                      child: on
                                          ? const Icon(PhosphorIconsBold.check,
                                              size: 14, color: Colors.white)
                                          : null,
                                    ),
                              onTap: !addable
                                  ? null
                                  : () => setState(() {
                                      on
                                          ? _picked.remove(w.id)
                                          : _picked.add(w.id);
                                    }),
                            ),
                          );
                        },
                      ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                child: SqAction(
                  _picked.isEmpty
                      ? tr('Сөз таңда')
                      : trp('{n} сөзді қосу', {'n': '${_picked.length}'}),
                  icon: PhosphorIconsBold.plus,
                  onTap: _picked.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                          all.where((w) => _picked.contains(w.id)).toList())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
