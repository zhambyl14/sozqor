// lib/features/words/word_bank_screen.dart
//
// The learner's own vocabulary.
//
// Search and filters collapse into one band at the top so the list itself
// starts high on the screen, and every row carries the one number that
// matters: how well the word is known, as five dots. The "add" button sits
// bottom-right, inside thumb reach, because adding a word is the action people
// come here to repeat.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../play/play_session_screen.dart';
import 'add_word_screen.dart';
import 'explore_screen.dart';
import 'word_detail_screen.dart';

enum _Filter { all, learning, learned, favorite, due }

extension on _Filter {
  String get label => switch (this) {
    _Filter.all      => tr('Барлығы'),
    _Filter.learning => tr('Үйренуде'),
    _Filter.learned  => tr('Меңгерілді'),
    _Filter.favorite => tr('Таңдаулы'),
    _Filter.due      => tr('Қайталау'),
  };
  IconData get icon => switch (this) {
    _Filter.all      => PhosphorIconsFill.books,
    _Filter.learning => PhosphorIconsFill.bookOpen,
    _Filter.learned  => PhosphorIconsFill.checkCircle,
    _Filter.favorite => PhosphorIconsFill.heart,
    _Filter.due      => PhosphorIconsFill.arrowsClockwise,
  };
}

class WordBankScreen extends ConsumerStatefulWidget {
  const WordBankScreen({super.key});

  @override
  ConsumerState<WordBankScreen> createState() => _WordBankScreenState();
}

class _WordBankScreenState extends ConsumerState<WordBankScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String? _topic;

  /// Words swiped away locally, hidden from the list before the network
  /// delete confirms so a dismissed `Dismissible` is never rebuilt with the
  /// same key while `myWordsProvider` is still serving the stale cache.
  final Set<String> _removedIds = {};

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _deleteWord(Word word) async {
    setState(() => _removedIds.add(word.id));
    try {
      await ref.read(wordsRepoProvider).remove(word.id);
      if (mounted) refreshAll(ref);
    } catch (e) {
      if (mounted) {
        setState(() => _removedIds.remove(word.id));
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  List<Word> _apply(List<Word> words) {
    final q = _search.text.trim().toLowerCase();
    return words.where((w) {
      if (_removedIds.contains(w.id)) return false;
      if (q.isNotEmpty &&
          !w.en.toLowerCase().contains(q) &&
          !w.kk.toLowerCase().contains(q)) {
        return false;
      }
      if (_topic != null && w.topic != _topic) return false;
      return switch (_filter) {
        _Filter.all      => true,
        _Filter.learning => !w.isLearned,
        _Filter.learned  => w.isLearned,
        _Filter.favorite => w.isFavorite,
        _Filter.due      => w.isDue,
      };
    }).toList();
  }

  Future<void> _add() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AddWordScreen()));
    if (mounted) refreshAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(myWordsProvider);
    final all = async.value ?? const <Word>[];
    final shown = _apply(all);
    final learned = all.where((w) => w.isLearned).length;
    final due = ref.watch(dueCountProvider).value ?? 0;
    final topics = {for (final w in all) w.topic}.toList()..sort();
    final lang = ref.watch(nativeLangProvider);

    // The word bank is the one list in the app with no natural ceiling, so it
    // is built lazily: the header is one sliver and every word row is another,
    // rather than a single Column that materialises all of them at once.
    return Scaffold(
      backgroundColor: AppColors.bg(d),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: SqLip(
          fill: AppColors.primary,
          lip: AppColors.primaryDeep,
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          onTap: _add,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsBold.plus, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(tr('Сөз қосу'),
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: Colors.white)),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.card(d),
          onRefresh: () async {
            ref.invalidate(myWordsProvider);
            ref.invalidate(dueCountProvider);
            await Future<void>.delayed(const Duration(milliseconds: 350));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                sliver: SliverList.list(children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqEyebrow(trp('{n} сөз · {m} меңгерілді',
                    {'n': '${all.length}', 'm': '$learned'})),
                  const SizedBox(height: 1),
                  Text(tr('Сөздік'),
                    style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800,
                      letterSpacing: -0.6, color: AppColors.text(d))),
                ],
              ),
            ),
            SqSquareButton(PhosphorIconsBold.compass,
              size: 42,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExploreScreen()))),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
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
                  onChanged: (_) => setState(() {}),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintStyle: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600,
                      color: AppColors.text4(d)),
                  ),
                ),
              ),
              if (_search.text.isNotEmpty)
                GestureDetector(
                  onTap: () { _search.clear(); setState(() {}); },
                  child: Icon(PhosphorIconsBold.x,
                    size: 16, color: AppColors.text3(d)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in _Filter.values) ...[
                _DarkChip(
                  label: f.label,
                  icon: f.icon,
                  selected: f == _filter,
                  onTap: () => setState(() => _filter = f)),
                const SizedBox(width: 7),
              ],
            ],
          ),
        ),

        if (topics.length > 1) ...[
          const SizedBox(height: 9),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SqChip(tr('Барлық тақырып'),
                  selected: _topic == null,
                  outlined: true,
                  onTap: () => setState(() => _topic = null)),
                const SizedBox(width: 7),
                for (final t in topics) ...[
                  SqChip(tr(topicOf(t).label),
                    tint: AppColors.topic(t),
                    selected: _topic == t,
                    outlined: true,
                    onTap: () => setState(() => _topic = t)),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        ],
        if (_topic != null) ...[
          const SizedBox(height: 9),
          SqAction(tr('Осы тақырыпты жаттығу'),
            icon: PhosphorIconsFill.target,
            tone: SqTone.ghost,
            height: 46,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    PlaySessionScreen(mode: PlayMode.classic, topic: _topic)));
              if (mounted) refreshAll(ref);
            }),
        ],
        const SizedBox(height: 14),

        if (due > 0) ...[
          SqPanel(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            fill: AppColors.soft(AppColors.green, d),
            border: AppColors.line(AppColors.green, d),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const PlaySessionScreen(mode: PlayMode.review)));
              if (mounted) refreshAll(ref);
            },
            child: Row(
              children: [
                const Icon(PhosphorIconsFill.arrowsClockwise,
                  size: 19, color: AppColors.greenDeep),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(trp('{p1} сөз қайталауды күтіп тұр', {'p1': '$due'}),
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: AppColors.greenInk)),
                      Text(tr('Дәл уақытында қайтала'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: AppColors.greenDeep)),
                    ],
                  ),
                ),
                const Icon(PhosphorIconsBold.caretRight,
                  size: 15, color: AppColors.greenDeep),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (async.isLoading && all.isEmpty)
          const Column(children: [
            SqShimmer(), SqShimmer(), SqShimmer(), SqShimmer()])
        else if (shown.isEmpty)
          SqEmpty(
            icon: all.isEmpty
                ? PhosphorIconsFill.books
                : PhosphorIconsFill.magnifyingGlass,
            title: all.isEmpty ? tr('Әзірге сөз жоқ') : tr('Ештеңе табылмады'),
            subtitle: all.isEmpty
                ? tr('Алғашқы сөзіңді қос — бір түймемен!')
                : tr('Сүзгіні өзгертіп көр'),
            action: all.isEmpty
                ? SizedBox(
                    width: 250,
                    child: SqAction(tr('Сөз базасынан таңдау'),
                      icon: PhosphorIconsBold.magnifyingGlass,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ExploreScreen()))),
                  )
                : null,
          ),
                ]),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 130),
                sliver: SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => SqGroupRow(
                    first: i == 0,
                    last: i == shown.length - 1,
                    child: _WordRow(
                      word: shown[i], lang: lang, onDelete: _deleteWord),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DarkChip({
    required this.label, required this.icon,
    required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.inkBlock(d) : AppColors.card(d),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.inkBlock(d) : AppColors.border(d)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              size: 13,
              color: selected ? Colors.white : AppColors.text2(d)),
            const SizedBox(width: 6),
            Text(label,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.text2(d))),
          ],
        ),
      ),
    );
  }
}

class _WordRow extends ConsumerWidget {
  final Word word;
  final String lang;
  final ValueChanged<Word> onDelete;
  const _WordRow({required this.word, required this.lang, required this.onDelete});

  static IconData _iconFor(String topic) => switch (topic) {
    'food'    => PhosphorIconsFill.bowlFood,
    'travel'  => PhosphorIconsFill.airplaneTilt,
    'work'    => PhosphorIconsFill.briefcase,
    'school'  => PhosphorIconsFill.graduationCap,
    'nature'  => PhosphorIconsFill.leaf,
    'animals' => PhosphorIconsFill.pawPrint,
    'tech'    => PhosphorIconsFill.cpu,
    'emotions'=> PhosphorIconsFill.heart,
    'sport'   => PhosphorIconsFill.soccerBall,
    'time'    => PhosphorIconsFill.clock,
    'city'    => PhosphorIconsFill.buildings,
    'money'   => PhosphorIconsFill.wallet,
    'health'  => PhosphorIconsFill.firstAidKit,
    'family'  => PhosphorIconsFill.users,
    'home'    => PhosphorIconsFill.house,
    'body'    => PhosphorIconsFill.person,
    'communication' => PhosphorIconsFill.chatsCircle,
    _         => PhosphorIconsFill.textAa,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final tint = AppColors.topic(word.topic);

    return Dismissible(
      key: ValueKey(word.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: AppColors.soft(AppColors.red, d),
        child: const Icon(PhosphorIconsFill.trash, color: AppColors.red),
      ),
      confirmDismiss: (_) => sqConfirm(context,
        title: tr('Сөзді жою'),
        message: trp('«{p1}» сөзін сөздіктен жоясың ба?', {'p1': word.en}),
        confirm: tr('Жою')),
      onDismissed: (_) => onDelete(word),
      child: SqTile(
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.muted(d),
            borderRadius: BorderRadius.circular(13)),
          alignment: Alignment.center,
          child: Icon(_iconFor(word.topic), size: 18, color: tint),
        ),
        title: word.en,
        subtitle: word.native(lang),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (word.isFavorite) ...[
              const Icon(PhosphorIconsFill.heart,
                size: 13, color: AppColors.red),
              const SizedBox(width: 7),
            ],
            if (word.isDue) ...[
              const SqDot(color: AppColors.amber, size: 7, ringed: false),
              const SizedBox(width: 7),
            ],
            SqMastery(word.mastery),
          ],
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => WordDetailScreen(word: word)));
          if (context.mounted) refreshAll(ref);
        },
      ),
    );
  }
}
