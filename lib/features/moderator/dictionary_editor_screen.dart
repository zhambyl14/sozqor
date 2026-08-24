// lib/features/moderator/dictionary_editor_screen.dart
//
// The dictionary, editable (EN-33 / EN-38 / KK-7).
//
// Until 5.0 nothing in this app could change a dictionary row. The only writer
// was `dict_upsert` from the AI edge function, so a wrong translation was
// permanent, a missing word could only be added by a learner looking it up,
// and "assign levels" — which EN-38 asks for outright — was impossible.
//
// The filters are the tool, not decoration. "Тексерілмеген" and "AI жазған"
// are how a moderator finds the rows that need a human, which is the entire
// reason to open this screen; sorting by id would bury them under everything
// already fine.
//
// Paged twenty at a time. The dictionary is the one table in this project
// designed to grow without a ceiling.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/repos/words_repo.dart' show kWordPageSize;
import '../../data/supa.dart';
import '../../providers.dart';
import 'word_editor_screen.dart';

class DictionaryEditorScreen extends ConsumerStatefulWidget {
  const DictionaryEditorScreen({super.key});

  @override
  ConsumerState<DictionaryEditorScreen> createState() =>
      _DictionaryEditorScreenState();
}

class _DictionaryEditorScreenState
    extends ConsumerState<DictionaryEditorScreen> {
  final _search = TextEditingController();

  List<DictEntry> _rows = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _busy = false;
  String? _error;

  String? _cefr;
  String? _topic;
  /// null = everything, false = only what no human has checked.
  bool? _verified;
  String? _source;

  /// Ids ticked for a bulk action. Bulk is the difference between a tool and
  /// a form: setting a level one row at a time over three hundred words is
  /// not something anybody does twice.
  final Set<int> _selected = {};

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
      _selected.clear();
    });
    final repo = ref.read(moderatorRepoProvider);
    try {
      _total = await repo.dictionaryCount(
        query: _search.text, cefr: _cefr, topic: _topic,
        verified: _verified, source: _source);
    } catch (_) {
      _total = 0;
    }
    await _fetch();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetch() async {
    try {
      final page = await ref.read(moderatorRepoProvider).dictionary(
        query: _search.text,
        cefr: _cefr, topic: _topic, verified: _verified, source: _source,
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

  Future<void> _edit([DictEntry? entry]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WordEditorScreen(entry: entry)));
    if (saved == true) await _load();
  }

  Future<void> _bulkLevel() async {
    final level = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SqSheetGrip(),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(tr('Деңгей тағайындау'),
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final c in kCefrCodes)
              ListTile(
                title: Text(c),
                onTap: () => Navigator.of(ctx).pop(c)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (level == null || !mounted) return;
    await _run(() async {
      final n = await ref.read(moderatorRepoProvider)
          .setLevel(_selected.toList(), level);
      if (mounted) {
        sqSnack(context, trp('{n} сөзге {c} деңгейі қойылды',
          {'n': '$n', 'c': level}));
      }
    });
  }

  Future<void> _bulkVerify() => _run(() async {
    final n = await ref.read(moderatorRepoProvider)
        .setVerified(_selected.toList(), true);
    if (mounted) {
      sqSnack(context, trp('{n} сөз тексерілді деп белгіленді', {'n': '$n'}));
    }
  });

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      await _load();
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final lang = ref.watch(nativeLangProvider);

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      floatingActionButton: _selected.isNotEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SqLip(
                fill: AppColors.primary,
                lip: AppColors.primaryDeep,
                radius: 18,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                onTap: () => _edit(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsBold.plus,
                      size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(tr('Сөз қосу'),
                      style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                  ],
                ),
              ),
            ),
      // The bulk bar only exists while something is ticked, so the screen is
      // not permanently carrying a row of disabled buttons.
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SqPanel(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SqNum('${_selected.length}',
                      size: 16, color: AppColors.primaryDeep),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SqAction(tr('Деңгей'),
                        height: 42,
                        tone: SqTone.ghost,
                        onTap: _busy ? null : _bulkLevel),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SqAction(tr('Тексерілді'),
                        height: 42,
                        tone: SqTone.green,
                        onTap: _busy ? null : _bulkVerify),
                    ),
                    const SizedBox(width: 8),
                    SqSquareButton(PhosphorIconsBold.x,
                      size: 42,
                      onTap: () => setState(_selected.clear)),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.card(d),
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
            children: [
              SqHeader(
                title: tr('Сөз базасы'),
                eyebrow: trp('{n} сөз', {'n': '$_total'}),
                onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
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
                    GestureDetector(
                      onTap: _load,
                      child: const Icon(PhosphorIconsBold.arrowRight,
                        size: 17, color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // The two filters this screen exists for.
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    SqChip(tr('Тексерілмеген'),
                      icon: PhosphorIconsFill.warningCircle,
                      tint: AppColors.amber,
                      selected: _verified == false,
                      outlined: true,
                      radius: 999,
                      onTap: () {
                        setState(() =>
                            _verified = _verified == false ? null : false);
                        _load();
                      }),
                    const SizedBox(width: 7),
                    SqChip(tr('AI жазған'),
                      icon: PhosphorIconsFill.sparkle,
                      tint: AppColors.primary,
                      selected: _source == 'ai',
                      outlined: true,
                      radius: 999,
                      onTap: () {
                        setState(() => _source = _source == 'ai' ? null : 'ai');
                        _load();
                      }),
                    const SizedBox(width: 7),
                    for (final c in kCefrCodes) ...[
                      SqChip(c,
                        selected: _cefr == c,
                        outlined: true,
                        radius: 999,
                        onTap: () {
                          setState(() => _cefr = _cefr == c ? null : c);
                          _load();
                        }),
                      const SizedBox(width: 7),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (_loading)
                const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()])
              else if (_error != null && _rows.isEmpty)
                SqEmpty(
                  icon: PhosphorIconsFill.warningCircle,
                  title: tr('Сөз базасы жүктелмеді'),
                  subtitle: _error,
                  action: SizedBox(
                    width: 200,
                    child: SqAction(tr('Қайталау'),
                      icon: PhosphorIconsBold.arrowClockwise, onTap: _load),
                  ))
              else if (_rows.isEmpty)
                SqEmpty(
                  icon: PhosphorIconsFill.magnifyingGlass,
                  title: tr('Ештеңе табылмады'),
                  subtitle: tr('Сүзгіні өзгертіп көр'),
                  tint: AppColors.sky)
              else ...[
                SqGroup(children: [
                  for (final e in _rows)
                    _DictRow(
                      entry: e,
                      lang: lang,
                      selected: _selected.contains(e.id),
                      onTap: () => _edit(e),
                      onSelect: () => setState(() {
                        final id = e.id;
                        if (id == null) return;
                        _selected.contains(id)
                            ? _selected.remove(id)
                            : _selected.add(id);
                      }),
                    ),
                ]),
                if (!_exhausted) ...[
                  const SizedBox(height: 14),
                  SqAction(
                    _loadingMore ? tr('Жүктелуде…') : tr('Тағы жүктеу'),
                    icon: PhosphorIconsBold.arrowDown,
                    tone: SqTone.ghost,
                    height: 48,
                    busy: _loadingMore,
                    onTap: _loadingMore ? null : _more),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DictRow extends StatelessWidget {
  final DictEntry entry;
  final String lang;
  final bool selected;
  final VoidCallback onTap, onSelect;

  const _DictRow({
    required this.entry,
    required this.lang,
    required this.selected,
    required this.onTap,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqTile(
      fill: selected ? AppColors.soft(AppColors.primary, d) : null,
      leading: GestureDetector(
        onTap: onSelect,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.muted(d),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border(d)),
          ),
          alignment: Alignment.center,
          child: selected
              ? const Icon(PhosphorIconsBold.check,
                  size: 16, color: Colors.white)
              // Not a checkbox until something is ticked: a column of empty
              // boxes makes an ordinary browse look like a bulk operation.
              : SqNum(entry.cefr, size: 10.5, color: AppColors.text3(d)),
        ),
      ),
      title: entry.en,
      subtitle: entry.native(lang),
      trailing: entry.verified
          ? const Icon(PhosphorIconsFill.sealCheck,
              size: 17, color: AppColors.green)
          : const Icon(PhosphorIconsFill.warningCircle,
              size: 17, color: AppColors.amber),
      onTap: onTap,
    );
  }
}
