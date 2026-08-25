// lib/features/moderator/pack_editor_screen.dart
//
// Filling the official collections (EN-38 / KK-7).
//
// "аилтс 6,5+ деп тұр и еще 120 сөз деп тұр, ішіне кірсең 14 қана сұрақ
// көрсетіп тұр." Since 5.0 the number on the card is count(*), so the card
// stopped lying — but nothing made it true. The six packs held 14, 12, 7, 6,
// 4 and 0 rows against a dictionary of three hundred, and the only way to add
// one was `admin_pack_add_words` typed into the Supabase SQL editor.
//
// This screen is the missing half: pick a pack, search the dictionary, tick
// rows, add. Every write returns the new count(*) and it is painted at the
// top straight away — watching that number climb is the whole job, and a
// moderator who cannot see the effect stops trusting the tool.
//
// Two ways in, because they answer different questions. "Сөздіктен қосу" is
// for choosing exactly which words belong in "IELTS 6.5+"; `admin_fill_pack`
// is for getting a pack from four words to two hundred in one tap, which is
// what the six seeded packs actually need first.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/collection.dart';
import '../../data/models/dict_entry.dart';
import '../../data/repos/collections_repo.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/repos/words_repo.dart' show kWordPageSize;
import '../../data/supa.dart';
import '../../providers.dart';
import 'moderator_screen.dart' show ModField;

/// How long the longest classic round is. A pack under this cannot answer the
/// round a learner is allowed to ask for, so the editor says so out loud
/// instead of leaving the moderator to guess what "enough" means.
const int _kFullRound = 30;

/// How far "бәрін таңдау" will walk the dictionary. High enough to sweep a
/// whole topic in one go, low enough that a mis-aimed tap does not drag the
/// entire table into one pack.
const int _kPickAllCeiling = 500;

/// Same short list the learner's own collections offer, so an official pack
/// and a personal one cannot end up looking like different kinds of object.
const _kEmojis = ['📚', '🎯', '⭐', '🔥', '🌱', '🧠', '✈️', '🍜', '💼', '🎬'];
const _kColours = [
  '#7C5CFF', '#F0455E', '#12B981', '#F59E0B', '#3B82F6', '#EC4899',
];

// ═══════════════════════════════════════════════════════════
// The pack list
// ═══════════════════════════════════════════════════════════

class PackEditorScreen extends ConsumerStatefulWidget {
  const PackEditorScreen({super.key});

  @override
  ConsumerState<PackEditorScreen> createState() => _PackEditorScreenState();
}

class _PackEditorScreenState extends ConsumerState<PackEditorScreen> {
  Future<void> _openForm([WordCollection? pack]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PackFormSheet(editing: pack),
    );
    if (saved == true) ref.invalidate(collectionsProvider);
  }

  Future<void> _openWords(WordCollection pack) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _PackWordsScreen(pack: pack)));
    if (mounted) ref.invalidate(collectionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(collectionsProvider);
    final unavailable =
        async.hasError && async.error is CollectionsUnavailable;
    final packs = (async.valueOrNull ?? const <WordCollection>[])
        .where((c) => c.isOfficial)
        .toList();

    return SqPage(
      onRefresh: () async {
        ref.invalidate(collectionsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Топтама сөздері'),
          eyebrow: tr('Модератор'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (unavailable)
          SqEmpty(
            icon: PhosphorIconsFill.folders,
            title: tr('Топтама жүйесі әлі қосылмаған'),
            subtitle: tr('Сервер жаңартылған соң қолжетімді болады'),
            tint: AppColors.sky)
        else ...[
          SqAction(tr('Жаңа топтама'),
            icon: PhosphorIconsBold.plus,
            onTap: () => _openForm()),
          const SizedBox(height: 14),

          if (async.isLoading && packs.isEmpty)
            const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()])
          else if (async.hasError && packs.isEmpty)
            SqEmpty(
              icon: PhosphorIconsFill.warningCircle,
              tint: AppColors.red,
              title: tr('Топтамалар жүктелмеді'),
              subtitle: humanError(async.error!),
              action: SizedBox(
                width: 200,
                child: SqAction(tr('Қайталау'),
                  icon: PhosphorIconsBold.arrowClockwise,
                  onTap: () => ref.invalidate(collectionsProvider)),
              ))
          else if (packs.isEmpty)
            SqEmpty(
              icon: PhosphorIconsFill.stack,
              title: tr('Әзірге ресми топтама жоқ'))
          else
            SqGroup(children: [
              for (final c in packs)
                SqTile(
                  leading: _PackGlyph(c),
                  title: c.titleKk.isEmpty ? tr('Атаусыз') : c.titleKk,
                  subtitle: _describe(c),
                  // The gap to a full round, said on the row itself: a list
                  // of six packs is exactly where you decide which one to
                  // work on next.
                  below: c.wordCount >= _kFullRound
                      ? null
                      : SqTrack(c.wordCount / _kFullRound,
                          color: AppColors.amber, height: 5),
                  trailing: SqSquareButton(PhosphorIconsBold.pencilSimple,
                    size: 32,
                    fill: AppColors.soft(AppColors.primary, d),
                    border: Colors.transparent,
                    iconColor: AppColors.primaryDeep,
                    onTap: () => _openForm(c)),
                  onTap: () => _openWords(c)),
            ]),
        ],
      ],
    );
  }

  /// Count first, then what the pack claims to be about — the two things a
  /// moderator compares when deciding whether it is honest.
  String _describe(WordCollection c) {
    final bits = <String>[
      c.wordCount == 0
          ? tr('Сөз жоқ')
          : trp('{n} сөз', {'n': '${c.wordCount}'}),
    ];
    if ((c.topic ?? '').isNotEmpty) bits.add(tr(topicOf(c.topic!).label));
    if (c.levels.isNotEmpty) bits.add(c.levels.join('·'));
    return bits.join(' · ');
  }
}

class _PackGlyph extends StatelessWidget {
  final WordCollection pack;
  const _PackGlyph(this.pack);

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = sqHexColor(pack.colour) ?? AppColors.primary;
    return Container(
      width: 38, height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.soft(tint, d),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line(tint, d)),
      ),
      child: Text(pack.emoji, style: const TextStyle(fontSize: 17)),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// One pack: its words, and the two ways to add more
// ═══════════════════════════════════════════════════════════

class _PackWordsScreen extends ConsumerStatefulWidget {
  final WordCollection pack;
  const _PackWordsScreen({required this.pack});

  @override
  ConsumerState<_PackWordsScreen> createState() => _PackWordsScreenState();
}

class _PackWordsScreenState extends ConsumerState<_PackWordsScreen> {
  List<DictEntry> _words = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _busy = false;
  String? _error;

  /// count(*) as the server last reported it. Every write returns it, so this
  /// never has to be guessed at from the page on screen.
  late int _count = widget.pack.wordCount;

  // The bulk-fill form starts on whatever the pack already claims to be
  // about, because "top this pack up with more of the same" is the request
  // nine times out of ten.
  bool _showFill = false;
  late String? _fillTopic = widget.pack.topic;
  late final Set<String> _fillLevels = {...widget.pack.levels};
  int _fillLimit = 100;

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
      final page = await ref.read(collectionsRepoProvider).words(
        widget.pack.id, limit: kWordPageSize, offset: _words.length);
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

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } on CollectionsUnavailable {
      if (mounted) {
        sqSnack(context, tr('Топтама жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Search the dictionary, tick rows, add them.
  ///
  /// The pack's own ids are read in full first so the picker can mark what is
  /// already in: without it a moderator re-picks the same twenty words and
  /// the count does not move, which reads as the tool being broken.
  Future<void> _addFromDictionary() => _run(() async {
    final have = {
      for (final e in await ref.read(collectionsRepoProvider)
          .allWords(widget.pack.id))
        if (e.id != null) e.id!,
    };
    if (!mounted) return;
    final ids = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DictPickSheet(alreadyIn: have),
    );
    if (ids == null || ids.isEmpty || !mounted) return;

    final before = _count;
    _count = await ref.read(collectionsRepoProvider)
        .addWords(widget.pack.id, ids);
    if (!mounted) return;
    final added = _count - before;
    sqSnack(context, added == 0
        ? tr('Жаңа сөз жоқ — бәрі топтамада бар еді')
        : trp('{n} сөз қосылды', {'n': '$added'}));
    await _load();
  });

  /// The one tap that takes a pack from four words to two hundred.
  Future<void> _fill() => _run(() async {
    final before = _count;
    _count = await ref.read(collectionsRepoProvider).fillFromDictionary(
      widget.pack.id,
      topic: _fillTopic,
      levels: _fillLevels.isEmpty ? null : _fillLevels.toList(),
      limit: _fillLimit);
    if (!mounted) return;
    final added = _count - before;
    sqSnack(context, added == 0
        ? tr('Бұл сүзгіде жаңа сөз табылмады')
        : trp('{n} сөз қосылды', {'n': '$added'}));
    await _load();
  });

  Future<void> _remove(DictEntry e) => _run(() async {
    final id = e.id;
    if (id == null) return;
    _count = await ref.read(collectionsRepoProvider)
        .adminRemoveWord(widget.pack.id, id);
    if (!mounted) return;
    setState(() => _words = _words.where((x) => x.id != id).toList());
  });

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final lang = ref.watch(nativeLangProvider);
    final c = widget.pack;
    final tint = sqHexColor(c.colour) ?? AppColors.primary;
    final short = _kFullRound - _count;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: _load,
      children: [
        SqHeader(
          title: c.titleKk.isEmpty ? tr('Атаусыз') : c.titleKk,
          eyebrow: tr('Топтама сөздері'),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // count(*), re-read after every write on this screen.
                        SqCountUp(_count, size: 28, color: Colors.white),
                        Text(tr('сөз'),
                          style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: AppColors.onInk3)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The honest sentence: what this pack can and cannot answer.
              Text(
                short > 0
                    ? trp('{n} сұрақтық толық тестке тағы {k} сөз керек',
                        {'n': '$_kFullRound', 'k': '$short'})
                    : trp('{n} сұрақтық толық тестке жетеді',
                        {'n': '$_kFullRound'}),
                style: const TextStyle(
                  fontSize: 12, height: 1.4, fontWeight: FontWeight.w600,
                  color: AppColors.onInk2)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        SqAction(tr('Сөздіктен сөз қосу'),
          icon: PhosphorIconsBold.plus,
          busy: _busy,
          onTap: _busy ? null : _addFromDictionary),
        const SizedBox(height: 10),

        SqPanel(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          onTap: () => setState(() => _showFill = !_showFill),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsBold.magicWand,
                    size: 16, color: AppColors.text2(d)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(tr('Тақырып бойынша толтыру'),
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                  ),
                  Icon(_showFill
                      ? PhosphorIconsBold.caretUp
                      : PhosphorIconsBold.caretDown,
                    size: 14, color: AppColors.text4(d)),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: !_showFill
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          SqEyebrow(tr('Тақырып')),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7, runSpacing: 7,
                            children: [
                              SqChip(tr('Барлық тақырып'),
                                selected: _fillTopic == null,
                                outlined: _fillTopic != null,
                                onTap: () =>
                                    setState(() => _fillTopic = null)),
                              for (final t in kTopics)
                                SqChip('${t.emoji} ${tr(t.label)}',
                                  selected: _fillTopic == t.key,
                                  outlined: _fillTopic != t.key,
                                  onTap: () => setState(() =>
                                      _fillTopic =
                                          _fillTopic == t.key ? null : t.key)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SqEyebrow(tr('Деңгей')),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7, runSpacing: 7,
                            children: [
                              for (final l in kCefrCodes)
                                SqChip(l,
                                  tint: AppColors.sky,
                                  selected: _fillLevels.contains(l),
                                  outlined: !_fillLevels.contains(l),
                                  onTap: () => setState(() {
                                    if (!_fillLevels.remove(l)) {
                                      _fillLevels.add(l);
                                    }
                                  })),
                            ],
                          ),
                          if (_fillLevels.isEmpty) ...[
                            const SizedBox(height: 7),
                            Text(tr('Деңгей таңдалмаса — бәрі алынады'),
                              style: TextStyle(
                                fontSize: 11.5, height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text3(d))),
                          ],
                          const SizedBox(height: 14),
                          SqEyebrow(tr('Ең көбі')),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7, runSpacing: 7,
                            children: [
                              for (final n in const [25, 50, 100, 200, 500])
                                SqChip('$n',
                                  tint: AppColors.amber,
                                  selected: _fillLimit == n,
                                  outlined: _fillLimit != n,
                                  onTap: () => setState(() => _fillLimit = n)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SqAction(tr('Толтыру'),
                            icon: PhosphorIconsFill.lightning,
                            tone: SqTone.amber,
                            height: 48,
                            busy: _busy,
                            onTap: _busy ? null : _fill),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_loading)
          const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()])
        else if (_error != null && _words.isEmpty)
          SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            tint: AppColors.red,
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
            subtitle: tr('Сөздіктен сөз қосып баста'),
            tint: AppColors.sky)
        else ...[
          SqGroup(children: [
            for (final e in _words)
              SqTile(
                leading: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.muted(d),
                    borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: SqNum(e.cefr, size: 10.5, color: tint),
                ),
                title: e.en,
                subtitle: e.native(lang),
                trailing: SqSquareButton(PhosphorIconsBold.minus,
                  size: 30,
                  fill: AppColors.soft(AppColors.red, d),
                  border: Colors.transparent,
                  iconColor: AppColors.red,
                  onTap: _busy ? null : () => _remove(e)),
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

// ═══════════════════════════════════════════════════════════
// The dictionary picker
// ═══════════════════════════════════════════════════════════

/// Search over `dict_admin_list`, ticking rows to add. Returns dictionary ids.
///
/// Rows already in the pack stay visible and are marked rather than filtered
/// out: a moderator searching "academic" wants to see that eleven of the
/// fourteen results are already in, not a list that quietly hides them.
class _DictPickSheet extends ConsumerStatefulWidget {
  final Set<int> alreadyIn;
  const _DictPickSheet({required this.alreadyIn});

  @override
  ConsumerState<_DictPickSheet> createState() => _DictPickSheetState();
}

class _DictPickSheetState extends ConsumerState<_DictPickSheet> {
  final _search = TextEditingController();
  final Set<int> _picked = {};

  List<DictEntry> _rows = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;
  String? _cefr;
  String? _topic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = const [];
      _exhausted = false;
    });
    await _fetch();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetch() async {
    try {
      final page = await ref.read(moderatorRepoProvider).dictionary(
        query: _search.text, cefr: _cefr, topic: _topic,
        limit: kWordPageSize, offset: _rows.length);
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, ...page];
        _exhausted = page.length < kWordPageSize;
      });
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

  /// Everything the current filter found, in one go.
  ///
  /// Twenty at a time is right for reading and wrong for the job: the reason
  /// a pack has four words is that somebody would have had to tick three
  /// hundred boxes twenty at a time.
  ///
  /// `dict_admin_list` caps a page at 100 rows server-side, so asking for five
  /// hundred quietly returns one hundred — the pages have to be walked.
  Future<void> _pickAllFound() async {
    setState(() => _loadingMore = true);
    try {
      const page = 100;
      final repo = ref.read(moderatorRepoProvider);
      final found = <DictEntry>[];
      while (found.length < _kPickAllCeiling) {
        final chunk = await repo.dictionary(
          query: _search.text, cefr: _cefr, topic: _topic,
          limit: page, offset: found.length);
        found.addAll(chunk);
        if (chunk.length < page) break;
      }
      if (!mounted) return;
      setState(() {
        for (final e in found) {
          final id = e.id;
          if (id != null && !widget.alreadyIn.contains(id)) _picked.add(id);
        }
      });
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final lang = ref.watch(nativeLangProvider);

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              const SqSheetGrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Column(
                  children: [
                    Text(tr('Сөздіктен таңдау'),
                      textAlign: TextAlign.center,
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
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _load(),
                              style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600,
                                color: AppColors.text(d)),
                              decoration: InputDecoration(
                                hintText: tr('Сөз іздеу…'),
                                filled: false, isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 13),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _load,
                            child: const Icon(PhosphorIconsBold.arrowRight,
                              size: 17, color: AppColors.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      // Room for a 12-pt chip label at the 1.2 text-scale
                      // ceiling.
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final l in kCefrCodes) ...[
                            SqChip(l,
                              tint: AppColors.sky,
                              selected: _cefr == l,
                              outlined: _cefr != l,
                              radius: 999,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                              onTap: () {
                                setState(() => _cefr = _cefr == l ? null : l);
                                _load();
                              }),
                            const SizedBox(width: 7),
                          ],
                          for (final t in kTopics) ...[
                            SqChip('${t.emoji} ${tr(t.label)}',
                              selected: _topic == t.key,
                              outlined: _topic != t.key,
                              radius: 999,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                              onTap: () {
                                setState(() =>
                                    _topic = _topic == t.key ? null : t.key);
                                _load();
                              }),
                            const SizedBox(width: 7),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _loading
                    ? const Column(
                        children: [SqShimmer(), SqShimmer(), SqShimmer()])
                    : _error != null && _rows.isEmpty
                        ? SqEmpty(
                            icon: PhosphorIconsFill.warningCircle,
                            tint: AppColors.red,
                            title: tr('Сөз базасы жүктелмеді'),
                            subtitle: _error)
                        : _rows.isEmpty
                            ? SqEmpty(
                                icon: PhosphorIconsFill.magnifyingGlass,
                                title: tr('Ештеңе табылмады'),
                                subtitle: tr('Сүзгіні өзгертіп көр'),
                                tint: AppColors.sky)
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 0, 18, 12),
                                itemCount: _rows.length + (_exhausted ? 0 : 1),
                                itemBuilder: (_, i) {
                                  if (i == _rows.length) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(top: 14),
                                      child: SqAction(
                                        _loadingMore
                                            ? tr('Жүктелуде…')
                                            : tr('Тағы жүктеу'),
                                        icon: PhosphorIconsBold.arrowDown,
                                        tone: SqTone.ghost,
                                        height: 48,
                                        busy: _loadingMore,
                                        onTap: _loadingMore ? null : _more),
                                    );
                                  }
                                  final e = _rows[i];
                                  final id = e.id;
                                  final inPack = id != null &&
                                      widget.alreadyIn.contains(id);
                                  final on = id != null && _picked.contains(id);
                                  return SqGroupRow(
                                    first: i == 0,
                                    last: i == _rows.length - 1 && _exhausted,
                                    child: SqTile(
                                      fill: on
                                          ? AppColors.soft(
                                              AppColors.primary, d)
                                          : null,
                                      leading: Container(
                                        width: 34, height: 34,
                                        decoration: BoxDecoration(
                                          color: AppColors.muted(d),
                                          borderRadius:
                                              BorderRadius.circular(11)),
                                        alignment: Alignment.center,
                                        child: SqNum(e.cefr,
                                          size: 10.5,
                                          color: AppColors.text3(d)),
                                      ),
                                      title: e.en,
                                      subtitle: inPack
                                          ? tr('Топтамада бар')
                                          : e.native(lang),
                                      titleColor: inPack
                                          ? AppColors.text3(d) : null,
                                      trailing: inPack
                                          ? const Icon(
                                              PhosphorIconsFill.checkCircle,
                                              size: 22,
                                              color: AppColors.green)
                                          : _Tick(on: on),
                                      onTap: inPack || id == null
                                          ? null
                                          : () => setState(() {
                                              if (!_picked.remove(id)) {
                                                _picked.add(id);
                                              }
                                            }),
                                    ),
                                  );
                                },
                              ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                child: Row(
                  children: [
                    SqSquareButton(PhosphorIconsBold.checks,
                      size: 48,
                      onTap: _loadingMore ? null : _pickAllFound),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SqAction(
                        _picked.isEmpty
                            ? tr('Сөз таңда')
                            : trp('{n} сөзді қосу', {'n': '${_picked.length}'}),
                        icon: PhosphorIconsBold.plus,
                        onTap: _picked.isEmpty
                            ? null
                            : () => Navigator.of(context)
                                .pop(_picked.toList())),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round tick on a pickable row.
class _Tick extends StatelessWidget {
  final bool on;
  const _Tick({required this.on});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 26, height: 26,
      decoration: BoxDecoration(
        color: on ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: on ? AppColors.primary : AppColors.border(d), width: 2),
      ),
      child: on
          ? const Icon(PhosphorIconsBold.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Creating and renaming an official pack
// ═══════════════════════════════════════════════════════════

class _PackFormSheet extends ConsumerStatefulWidget {
  final WordCollection? editing;
  const _PackFormSheet({this.editing});

  @override
  ConsumerState<_PackFormSheet> createState() => _PackFormSheetState();
}

class _PackFormSheetState extends ConsumerState<_PackFormSheet> {
  late final _titleKk = TextEditingController(text: widget.editing?.titleKk);
  late final _titleRu = TextEditingController(text: widget.editing?.titleRu);
  late final _subKk = TextEditingController(text: widget.editing?.subtitleKk);
  late final _subRu = TextEditingController(text: widget.editing?.subtitleRu);

  late String _emoji = widget.editing?.emoji ?? _kEmojis.first;
  late String _colour = widget.editing?.colour ?? _kColours.first;
  late String? _topic = widget.editing?.topic;
  late final Set<String> _levels = {...?widget.editing?.levels};

  bool _busy = false;
  String? _titleError;

  @override
  void dispose() {
    _titleKk.dispose();
    _titleRu.dispose();
    _subKk.dispose();
    _subRu.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleKk.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = tr('Топтама атауын жаз'));
      return;
    }
    setState(() { _busy = true; _titleError = null; });
    try {
      await ref.read(collectionsRepoProvider).savePack(
        id: widget.editing?.id,
        titleKk: title,
        titleRu: _titleRu.text,
        subtitleKk: _subKk.text,
        subtitleRu: _subRu.text,
        emoji: _emoji,
        colour: _colour,
        topic: _topic,
        levels: _levels.toList());
      if (mounted) Navigator.of(context).pop(true);
    } on CollectionsUnavailable {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context, tr('Топтама жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SqSheetGrip(),
              Text(widget.editing == null
                  ? tr('Жаңа топтама')
                  : tr('Топтаманы өңдеу'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.text(d))),
              const SizedBox(height: 18),

              ModField(
                label: tr('Атауы (қазақша)'),
                controller: _titleKk,
                hint: tr('Мысалы: IELTS 6.5+'),
                error: _titleError),
              const SizedBox(height: 14),
              ModField(
                label: tr('Атауы (орысша)'),
                controller: _titleRu,
                hint: tr('Бос қалса — қазақшасы көрінеді')),
              const SizedBox(height: 14),
              ModField(
                label: tr('Сипаттамасы (қазақша)'),
                controller: _subKk,
                lines: 2),
              const SizedBox(height: 14),
              ModField(
                label: tr('Сипаттамасы (орысша)'),
                controller: _subRu,
                lines: 2),
              const SizedBox(height: 16),

              SqEyebrow(tr('Белгіше')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final e in _kEmojis)
                    GestureDetector(
                      onTap: () => setState(() => _emoji = e),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.muted(d),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: e == _emoji
                                ? AppColors.primary : Colors.transparent,
                            width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              SqEyebrow(tr('Түсі')),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final c in _kColours) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _colour = c),
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: sqHexColor(c),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: c == _colour
                                  ? AppColors.text(d) : Colors.transparent,
                              width: 2.5),
                          ),
                        ),
                      ),
                    ),
                    if (c != _kColours.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Topic and levels are what the bulk fill starts from, not a
              // filter the pack is served through — the words are rows now.
              SqEyebrow(tr('Тақырып')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7, runSpacing: 7,
                children: [
                  SqChip(tr('Барлық тақырып'),
                    selected: _topic == null,
                    outlined: _topic != null,
                    onTap: () => setState(() => _topic = null)),
                  for (final t in kTopics)
                    SqChip('${t.emoji} ${tr(t.label)}',
                      selected: _topic == t.key,
                      outlined: _topic != t.key,
                      onTap: () => setState(
                          () => _topic = _topic == t.key ? null : t.key)),
                ],
              ),
              const SizedBox(height: 14),

              SqEyebrow(tr('Деңгей')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7, runSpacing: 7,
                children: [
                  for (final l in kCefrCodes)
                    SqChip(l,
                      tint: AppColors.sky,
                      selected: _levels.contains(l),
                      outlined: !_levels.contains(l),
                      onTap: () => setState(() {
                        if (!_levels.remove(l)) _levels.add(l);
                      })),
                ],
              ),
              const SizedBox(height: 20),

              SqAction(tr('Сақтау'),
                icon: PhosphorIconsBold.check,
                busy: _busy,
                onTap: _busy ? null : _submit),
            ],
          ),
        ),
      ),
    );
  }
}
