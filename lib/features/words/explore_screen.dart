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
import '../../data/models/word.dart';
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

  @override
  void initState() {
    super.initState();
    final profile = ref.read(myProfileProvider).value;
    _level = profile?.cefrLevel ?? 'A1';
    _levelFromFallback = profile == null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(dictRepoProvider).search(
        query: _search.text.trim(),
        cefr: [_level],
        topic: _topic,
        limit: 120,
      );
      if (mounted) setState(() => _entries = list);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

      // The server can still answer with something already on screen; the
      // list must never grow a duplicate.
      final known = _entries.map((e) => e.en.toLowerCase().trim()).toSet();
      final added = fresh
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
      final lvl = next.value?.cefrLevel;
      if (_levelFromFallback && lvl != null && lvl != _level) {
        setState(() { _level = lvl; _levelFromFallback = false; });
        _load();
      }
    });
    final d = isDark(context);
    final owned = {
      for (final w in ref.watch(myWordsProvider).value ?? const <Word>[])
        w.en.toLowerCase()
    };
    final myLevel = ref.watch(myProfileProvider).value?.cefrLevel ?? 'A1';
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
                  : _entries.isEmpty
                      ? SqEmpty(
                          icon: PhosphorIconsFill.magnifyingGlass,
                          title: tr('Бұл бөлімде сөз аз'),
                          subtitle:
                              tr('Осы деңгей мен тақырып бойынша жаңа сөздер '
                                 'тауып беруге болады'),
                          action: SizedBox(
                            width: 250,
                            child: SqAction(tr('Жаңа сөздер тап'),
                              icon: PhosphorIconsFill.sparkle,
                              tone: SqTone.green,
                              busy: _growing,
                              onTap: _grow),
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
                                  owned: owned.contains(e.en.toLowerCase()),
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
                            SqAction(
                              _growing ? tr('Ізделуде…') : tr('Тағы сөз тап'),
                              icon: PhosphorIconsFill.sparkle,
                              tone: SqTone.ghost,
                              height: 50,
                              busy: _growing,
                              onTap: _growing ? null : _grow),
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
