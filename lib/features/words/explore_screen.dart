// lib/features/words/explore_screen.dart
//
// The shared dictionary, browsable.
//
// Only levels appropriate to the learner are highlighted by default — an A0
// starter pack never clutters a B2 catalogue — but every level stays reachable
// and dimmed rather than hidden, with a line explaining why it is dimmed.
// Picking is multi-select: the bar at the bottom counts what you have chosen
// and adds the lot in one call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/repos/words_repo.dart' show kWordPageSize;
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/sozqor_ai.dart';
import '../auth/guest_gate.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _search = TextEditingController();

  /// This screen is pushed as its own route, so unlike the word bank — which
  /// borrows the tab's PrimaryScrollController — it owns the controller it
  /// watches for the bottom of the list.
  final _scroll = ScrollController();

  List<DictEntry> _entries = const [];

  /// Keyed by the English word, so a pick survives changing the level or
  /// topic filter — the entry itself is kept, not just its key.
  final Map<String, DictEntry> _picked = {};
  String? _topic;
  late String _level;
  bool _levelFromFallback = true;
  bool _loading = true;
  bool _adding = false;
  bool _growing = false;

  /// English keys the learner already has, read from the server rather than
  /// from the bank's loaded pages — the bank is paged now, so its in-memory
  /// list is not a complete answer to "do I own this?".
  Set<String> _owned = const {};

  /// Whether [_owned] is an answer or a shrug. An empty set used to stand for
  /// both, so a failed fetch read as "owns nothing", every row drew as new,
  /// and the learner was offered words already in their bank with no badge to
  /// warn them. Unknown is retried on the next page instead.
  bool _ownedKnown = false;

  /// `dict_discover_count`: how many words at this level the learner has never
  /// added. Null means the server did not answer — which is never the same as
  /// zero, and is the difference between "you have taken them all" and a lie.
  int? _remaining;

  /// Rows pulled from the server so far, counting the ones filtered out for
  /// being already owned. This is the search offset; `_entries.length` is not,
  /// or every page would re-fetch the words it just hid.
  int _fetched = 0;
  bool _exhausted = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(myProfileProvider).valueOrNull;
    _level = profile?.cefrLevel ?? 'A1';
    _levelFromFallback = profile == null;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  static String _norm(String s) => s.toLowerCase().trim();

  /// EN-37 / KK-9: the catalogue pages twenty at a time and the only way to
  /// reach page two was a button below the last row, so most learners never
  /// saw one. This asks for the next page while the bottom is still 600px
  /// away, which is far enough that the list never visibly stalls.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels < p.maxScrollExtent - 600) return;
    if (_loading || _loadingMore || _exhausted) return;
    _loadMore();
  }

  /// Starts the list over for the current level / topic / query.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _entries = const [];
      _fetched = 0;
      _exhausted = false;
      _remaining = null;
    });
    await _refreshOwned();
    await _fetchPage();
    // The count is only worth a round trip when the screen is about to make a
    // claim that depends on it: an empty list, or a list that ended.
    if (_entries.isEmpty || _exhausted) await _countRemaining();
    if (mounted) setState(() => _loading = false);
  }

  /// The learner's own words, so a row can say 'Бар' instead of posing as new.
  Future<void> _refreshOwned() async {
    try {
      _owned = await ref.read(wordsRepoProvider).ownedEnglish();
      _ownedKnown = true;
    } catch (_) {
      _owned = const {};
      _ownedKnown = false;
    }
  }

  /// Asks how many words at this level the learner has never added, before
  /// the screen says there are none. A null answer stays null: "the server
  /// did not tell me" must never be rendered as "there is nothing left".
  Future<void> _countRemaining() async {
    final left = await ref
        .read(dictRepoProvider)
        .discoverCount(cefr: _level, topic: _topic);
    if (mounted) setState(() => _remaining = left);
  }

  /// Pulls one page and appends whatever survives the owned filter (EN-39).
  ///
  /// A page can be entirely words the learner already has, which would look
  /// like the catalogue ending early, so it keeps asking — up to a small
  /// bound — until something lands or the server runs out.
  Future<void> _fetchPage() async {
    if (_exhausted) return;
    // A failed owned fetch poisons every row it touches, so it is retried
    // here rather than left wrong for the rest of the session.
    if (!_ownedKnown) await _refreshOwned();

    final query = _search.text.trim();
    final repo = ref.read(dictRepoProvider);
    var attempts = 0;
    try {
      while (attempts < 5 && !_exhausted) {
        attempts++;
        // With no query, dict_discover answers the question this screen is
        // actually asking — words at this level the learner has never added —
        // and it subtracts the whole `words` table, not the screenful the
        // client can see. dict_search stays for a typed query, which discover
        // has no parameter for.
        final page = query.isEmpty
            ? await repo.discover(
                cefr: _level,
                topic: _topic,
                limit: kWordPageSize,
                offset: _fetched)
            : await repo.search(
                query: query,
                cefr: [_level],
                topic: _topic,
                limit: kWordPageSize,
                offset: _fetched);
        _fetched += page.length;
        if (page.length < kWordPageSize) _exhausted = true;

        final known = _entries.map((e) => _norm(e.en)).toSet();
        final fresh = page
            // dict_discover reads p_topic 'general' as "any topic at all", so
            // the Жалпы chip has to be honoured here or picking it lists the
            // whole level.
            .where((e) => _topic == null || e.topic == _topic)
            .where((e) => !_owned.contains(_norm(e.en)))
            .where((e) => known.add(_norm(e.en)))
            .toList();

        if (fresh.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _entries = [..._entries, ...fresh];
            _error = null;
          });
          return;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _exhausted || _loading) return;
    setState(() => _loadingMore = true);
    await _fetchPage();
    if (mounted) setState(() => _loadingMore = false);
    if (_exhausted && mounted) await _countRemaining();
  }

  /// Fetches more words for this level+topic and APPENDS them under what is
  /// already on screen.
  ///
  /// It used to call `growBrain` and then re-run the whole search, which
  /// replaced the list with the same first 120 rows — from the learner's side
  /// the button simply reloaded the page and appeared to do nothing. Asking
  /// the AI directly, with everything already listed passed as `exclude`,
  /// is what actually produces words they have not seen; the results are
  /// written into the shared dictionary on the server, so the next person
  /// gets them from cache for free.
  Future<void> _grow() async {
    setState(() => _growing = true);
    try {
      final seen = <String>{
        for (final e in _entries) ...[
          e.en.toLowerCase().trim(),
          e.kk.toLowerCase().trim(),
        ],
      }..removeWhere((s) => s.isEmpty);

      final fresh = await SozQorAI.instance.suggest(
        cefr: _level,
        topic: _topic ?? 'general',
        count: 12,
        exclude: seen,
      );

      // The server can still answer with something already on screen, or
      // with a word the learner saved long ago; the list must never grow a
      // duplicate and must never re-offer something already owned (EN-39).
      final known = _entries.map((e) => e.en.toLowerCase().trim()).toSet();
      final added = fresh
          .where((e) => !_owned.contains(e.en.toLowerCase().trim()))
          .where((e) => known.add(e.en.toLowerCase().trim()))
          .toList();

      if (!mounted) return;
      setState(() => _entries = [..._entries, ...added]);
      sqSnack(context, added.isNotEmpty
          ? trp('Тағы {p1} сөз қосылды', {'p1': '${added.length}'})
          : tr('Жаңа сөз табылмады, кейінірек көр'));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _growing = false);
    }
  }

  Future<void> _addPicked() async {
    if (_picked.isEmpty) return;
    if (!await requireAccount(context, ref, GuestFeature.saveWord)) return;
    if (!mounted) return;
    setState(() => _adding = true);
    try {
      final chosen = _picked.values.toList();
      final n = await ref.read(wordsRepoProvider).addManyFromDict(chosen);
      final profiles = ref.read(profileRepoProvider);
      for (var i = 0; i < n; i++) {
        await profiles.bumpWordsAdded();
      }
      await ref.read(eventsRepoProvider).bumpByMetric(_level, 'words', by: n);
      refreshAll(ref);
      ref.invalidate(eventProgressProvider);
      if (!mounted) return;
      sqSnack(context, n == 0
          ? tr('Барлығы сөздігіңде бар екен')
          : trp('{p1} сөз қосылды · +{p2} XP', {'p1': '$n', 'p2': '${n * 10}'}));
      setState(_picked.clear);
      // What was just saved is no longer a word to discover, so the list is
      // rebuilt without it rather than left showing stale rows.
      await _load();
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    // The profile can still be loading when this screen opens, in which case
    // _level locks to the 'A1' fallback — once the real level arrives, adopt
    // it, but only if the learner has not since picked a level chip herself.
    ref.listen(myProfileProvider, (prev, next) {
      final lvl = next.valueOrNull?.cefrLevel;
      if (_levelFromFallback && lvl != null && lvl != _level) {
        setState(() { _level = lvl; _levelFromFallback = false; });
        _load();
      }
    });
    final d = isDark(context);
    final myLevel = ref.watch(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
    final allowed = visibleCefrFor(myLevel);
    final lang = ref.watch(nativeLangProvider);

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: SqAction(trp('{p1} сөзді қосу', {'p1': '${_picked.length}'}),
                icon: PhosphorIconsBold.plus,
                busy: _adding,
                onTap: _addPicked),
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                children: [
                  SqHeader(
                    title: tr('Сөз базасы'),
                    eyebrow: tr('Ортақ сөздік'),
                    onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 14),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.card(d),
                      borderRadius: BorderRadius.circular(17),
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
                              filled: false,
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              hintStyle: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600,
                                color: AppColors.text4(d)),
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
                  const SizedBox(height: 11),

                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final c in kCefrCodes) ...[
                          Opacity(
                            opacity: allowed.contains(c) ? 1 : 0.45,
                            child: SqChip(c,
                              tint: AppColors.tiers[cefrIndex(c).clamp(0, 4)],
                              selected: c == _level,
                              outlined: true,
                              radius: 999,
                              onTap: () {
                                setState(() {
                                  _level = c;
                                  _levelFromFallback = false;
                                });
                                _load();
                              }),
                          ),
                          const SizedBox(width: 7),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SqChip(tr('Барлығы'),
                          selected: _topic == null,
                          outlined: true,
                          radius: 999,
                          onTap: () {
                            setState(() => _topic = null);
                            _load();
                          }),
                        const SizedBox(width: 7),
                        for (final t in kTopics) ...[
                          SqChip(t.label,
                            tint: AppColors.topic(t.key),
                            selected: _topic == t.key,
                            outlined: true,
                            radius: 999,
                            onTap: () {
                              setState(() => _topic = t.key);
                              _load();
                            }),
                          const SizedBox(width: 7),
                        ],
                      ],
                    ),
                  ),

                  if (!allowed.contains(_level))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsFill.info,
                            size: 15, color: AppColors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cefrIndex(_level) < cefrIndex(myLevel)
                                  ? tr('Бұл сенің деңгейіңнен төмен — қайталауға ғана')
                                  : tr('Бұл сенің деңгейіңнен жоғары — қиын болуы мүмкін'),
                              style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w600,
                                color: AppColors.text3(d))),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                      children: const [
                        SqShimmer(), SqShimmer(), SqShimmer(),
                        SqShimmer(), SqShimmer(),
                      ])
                  : _error != null && _entries.isEmpty
                      ? SqEmpty(
                          icon: PhosphorIconsFill.warningCircle,
                          title: tr('Сөз базасы жүктелмеді'),
                          subtitle: _error,
                          action: SizedBox(
                            width: 220,
                            child: SqAction(tr('Қайталау'),
                              icon: PhosphorIconsBold.arrowClockwise,
                              onTap: _load),
                          ),
                        )
                      : _entries.isEmpty
                      ? SqEmpty(
                          icon: PhosphorIconsFill.magnifyingGlass,
                          title: _owned.isEmpty
                              ? tr('Бұл бөлімде сөз аз')
                              : tr('Мұндағы сөздер сөздігіңде бар'),
                          subtitle:
                              tr('Осы деңгей мен тақырып бойынша жаңа сөздер '
                                 'тауып беруге болады'),
                          action: SizedBox(
                            width: 250,
                            child: SqAction(tr('Жаңа сөздер тап'),
                              icon: PhosphorIconsFill.sparkle,
                              tone: SqTone.green,
                              busy: _growing,
                              onTap: _growing ? null : _grow),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
                          children: [
                            SqGroup(children: [
                              for (final e in _entries)
                                _EntryRow(
                                  entry: e,
                                  lang: lang,
                                  // Owned words are filtered out before they
                                  // reach this list (EN-39), so nothing here
                                  // is already saved.
                                  owned: false,
                                  picked: _picked
                                      .containsKey(e.en.toLowerCase()),
                                  onToggle: () => setState(() {
                                    final key = e.en.toLowerCase();
                                    if (_picked.containsKey(key)) {
                                      _picked.remove(key);
                                    } else {
                                      _picked[key] = e;
                                    }
                                  }),
                                ),
                            ]),
                            const SizedBox(height: 16),

                            // EN-37: the catalogue is walked twenty at a time,
                            // and only once it is genuinely used up does the
                            // AI get asked for words nobody has stored yet.
                            if (!_exhausted)
                              SqAction(
                                _loadingMore
                                    ? tr('Жүктелуде…')
                                    : tr('Тағы жүктеу'),
                                icon: PhosphorIconsBold.arrowDown,
                                tone: SqTone.ghost,
                                height: 50,
                                busy: _loadingMore,
                                onTap: _loadingMore ? null : _loadMore)
                            else ...[
                              Text(
                                tr('Базадағы сөздер таусылды'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                  color: AppColors.text3(d))),
                              const SizedBox(height: 10),
                              SqAction(
                                _growing ? tr('Ізделуде…') : tr('Тағы сөз тап'),
                                icon: PhosphorIconsFill.sparkle,
                                tone: SqTone.ghost,
                                height: 50,
                                busy: _growing,
                                onTap: _growing ? null : _grow),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final DictEntry entry;
  final String lang;
  final bool owned, picked;
  final VoidCallback onToggle;

  const _EntryRow({
    required this.entry, required this.lang, required this.owned,
    required this.picked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = AppColors.topic(entry.topic);

    return SqTile(
      fill: picked ? AppColors.soft(AppColors.primary, d) : null,
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppColors.muted(d),
          borderRadius: BorderRadius.circular(13)),
        alignment: Alignment.center,
        child: SqNum(
          entry.en.isNotEmpty ? entry.en[0].toUpperCase() : '?',
          size: 16, color: tint),
      ),
      title: entry.en,
      subtitle: entry.native(lang),
      trailing: owned
          ? SqBadge(tr('Бар'), tint: AppColors.green)
          : AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: picked ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: picked ? AppColors.primary : AppColors.border(d),
                  width: 2),
              ),
              child: picked
                  ? const Icon(PhosphorIconsBold.check,
                      size: 15, color: Colors.white)
                  : null,
            ),
      onTap: owned ? null : onToggle,
    );
  }
}
