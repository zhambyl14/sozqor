// lib/features/play/packs_screen.dart
//
// Word packs.
//
// Learning from a flat alphabetical list is the slowest way to remember
// anything. A pack gives the words a reason to be together — the language of
// an airport, of a job interview, of an exam — so each one arrives with
// context already attached. Packs are assembled from the shared dictionary by
// topic and level, which means they grow as the dictionary does.

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
import '../../services/meta_store.dart';
import '../../services/question_factory.dart';
import '../../services/speech.dart';
import 'play_session_screen.dart';

const _packStyle = <String, ({Color fill, Color lip, IconData icon})>{
  'movies': (fill: AppColors.ink, lip: AppColors.inkLip,
             icon: PhosphorIconsFill.filmSlate),
  'ielts':  (fill: AppColors.primary, lip: AppColors.primaryDeep,
             icon: PhosphorIconsFill.graduationCap),
  'songs':  (fill: AppColors.red, lip: AppColors.redDeep,
             icon: PhosphorIconsFill.musicNotes),
  'tech':   (fill: AppColors.green, lip: AppColors.greenDeep,
             icon: PhosphorIconsFill.cpu),
  'travel': (fill: AppColors.sky, lip: AppColors.skyDeep,
             icon: PhosphorIconsFill.airplaneTilt),
  'food':   (fill: AppColors.amber, lip: AppColors.amberDeep,
             icon: PhosphorIconsFill.bowlFood),
};

/// Builds a practice round straight from the learner's favorited words —
/// this is what "Өз топтамаңды жаса" actually does when tapped, instead of
/// only ever showing a passive toast.
Future<void> _startOwnPack(BuildContext context, WidgetRef ref) async {
  final words = ref.read(myWordsProvider).value ?? const <Word>[];
  if (words.isEmpty) {
    sqSnack(context, tr('Алдымен сөздікке сөз қос'));
    return;
  }
  final favorites = words.where((w) => w.isFavorite).toList();
  if (favorites.length < 4) {
    sqSnack(context, tr('Кемінде 4 сөзді таңдаулыға қос'));
    return;
  }
  final entries = favorites.map((w) => w.toDictEntry()).toList();
  final profile = ref.read(myProfileProvider).value;
  final questions = QuestionFactory.build(
    items: favorites.map(PlayItem.fromWord).toList(),
    pool: entries,
    kinds: kindsFor(profile?.cefrLevel ?? 'A1'),
    count: 10,
    nativeLang: profile?.nativeLang ?? 'kk',
  );
  if (questions.isEmpty) {
    sqSnack(context, tr('Сұрақ құрастыру мүмкін болмады'), error: true);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlaySessionScreen(
      mode: PlayMode.classic, preset: questions, title: tr('Өз топтамаң'))));
  if (context.mounted) refreshAll(ref);
}

class PacksScreen extends ConsumerWidget {
  const PacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final meta = ref.watch(metaProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Сөз топтамалары'),
          eyebrow: tr('Жаңа'),
          onBack: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 16),

        for (final pack in kWordPacks) ...[
          _PackCard(
            pack: pack,
            done: meta.packs[pack.id] ?? 0,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PackDetailScreen(packId: pack.id))),
          ),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 4),
        SqPanel(
          radius: 20,
          padding: const EdgeInsets.all(16),
          border: AppColors.border(d),
          onTap: () => _startOwnPack(context, ref),
          child: Row(
            children: [
              SqTintBox(PhosphorIconsBold.plus,
                tint: AppColors.text3(d), size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Өз топтамаңды жаса'),
                      style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    Text(tr('Таңдаулы сөздерің өз топтамаңды құрайды'),
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.text3(d))),
                  ],
                ),
              ),
              Icon(PhosphorIconsBold.caretRight,
                size: 15, color: AppColors.text3(d)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PackCard extends StatelessWidget {
  final WordPack pack;
  final int done;
  final VoidCallback onTap;
  const _PackCard({required this.pack, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = _packStyle[pack.id] ??
        (fill: AppColors.primary, lip: AppColors.primaryDeep,
         icon: PhosphorIconsFill.stack);
    final ratio = (done / pack.size).clamp(0.0, 1.0);

    return SqLip(
      fill: style.fill,
      lip: style.lip,
      radius: 22,
      padding: const EdgeInsets.all(17),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16)),
            child: Icon(style.icon, size: 23, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(pack.title),
                  style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w800,
                    letterSpacing: -0.2, color: Colors.white)),
                Text(trp('{sub} · {n} сөз',
                    {'sub': tr(pack.subtitle), 'n': '${pack.size}'}),
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.72))),
                const SizedBox(height: 8),
                SqTrack(ratio,
                  color: Colors.white,
                  background: Colors.white.withValues(alpha: 0.22)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SqNum('${(ratio * 100).round()}%', size: 12, color: Colors.white),
        ],
      ),
    );
  }
}

// ── One pack ───────────────────────────────────────────────

class PackDetailScreen extends ConsumerStatefulWidget {
  final String packId;
  const PackDetailScreen({super.key, required this.packId});

  @override
  ConsumerState<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends ConsumerState<PackDetailScreen> {
  bool _adding = false;

  WordPack get _pack => packOf(widget.packId)!;

  Future<void> _train(List<DictEntry> entries) async {
    if (entries.length < 4) {
      sqSnack(context, tr('Бұл топтамада сөз жеткіліксіз'), error: true);
      return;
    }
    final profile = ref.read(myProfileProvider).value;
    const roundSize = 10;
    final owned = {
      for (final w in ref.read(myWordsProvider).value ?? const <Word>[])
        w.en.toLowerCase()
    };
    // Bias the round toward pack entries the learner does not own yet, so
    // repeated rounds actually push toward finishing the pack instead of
    // re-quizzing words already added. Only fall back to owned entries when
    // there aren't enough new ones to fill a full round.
    final fresh = entries
        .where((e) => !owned.contains(e.en.toLowerCase()))
        .toList();
    final known = entries
        .where((e) => owned.contains(e.en.toLowerCase()))
        .toList();
    final source = fresh.length >= roundSize
        ? fresh
        : [...fresh, ...known.take(roundSize - fresh.length)];
    final questions = QuestionFactory.build(
      items: source.map(PlayItem.fromDict).toList(),
      pool: entries,
      kinds: kindsFor(profile?.cefrLevel ?? 'A1'),
      count: roundSize,
      nativeLang: profile?.nativeLang ?? 'kk',
    );
    if (questions.isEmpty) {
      if (mounted) {
        sqSnack(context, tr('Сұрақ құрастыру мүмкін болмады'), error: true);
      }
      return;
    }
    final outcome = await Navigator.of(context).push<PlayOutcome>(
      MaterialPageRoute(builder: (_) => PlaySessionScreen(
        mode: PlayMode.classic, preset: questions, title: tr(_pack.title))));
    if (outcome != null && outcome.correct > 0) {
      await ref.read(metaProvider.notifier)
          .bumpPack(widget.packId, outcome.correct);
    }
    if (mounted) refreshAll(ref);
  }

  Future<void> _addAll(List<DictEntry> entries) async {
    setState(() => _adding = true);
    try {
      final added = await ref.read(wordsRepoProvider)
          .addManyFromDict(entries.take(20).toList());
      ref.invalidate(myWordsProvider);
      if (mounted) {
        sqSnack(context, added == 0
            ? tr('Барлығы сөздігіңде бар екен')
            : trp('{n} сөз сөздікке қосылды', {'n': '$added'}));
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final pack = _pack;
    final style = _packStyle[pack.id] ??
        (fill: AppColors.primary, lip: AppColors.primaryDeep,
         icon: PhosphorIconsFill.stack);
    final async = ref.watch(packPoolProvider(pack.id));
    final done = ref.watch(metaProvider).packs[pack.id] ?? 0;
    final owned = {
      for (final w in ref.watch(myWordsProvider).value ?? const <Word>[])
        w.en.toLowerCase()
    };

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr(pack.title),
          eyebrow: tr(pack.subtitle),
          onBack: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 16),

        SqLip(
          fill: style.fill,
          lip: style.lip,
          radius: 24,
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16)),
                    child: Icon(style.icon, size: 23, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(trp('{n} / {total} сөз меңгерілді',
                            {'n': '$done', 'total': '${pack.size}'}),
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: Colors.white)),
                        Text(trp('Деңгей: {lv}',
                            {'lv': pack.levels.join(' · ')}),
                          style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SqTrack((done / pack.size).clamp(0.0, 1.0),
                height: 8,
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.22)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        async.when(
          loading: () => const Column(children: [
            SqShimmer(), SqShimmer(), SqShimmer()]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Топтама жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (entries) {
            if (entries.isEmpty) {
              return SqEmpty(
                icon: PhosphorIconsFill.stack,
                title: tr('Бұл топтама әлі бос'),
                subtitle:
                    tr('Сөздік базасы толыға береді — кейінірек қайта кір'));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SqAction(tr('Жаттығуды бастау'),
                        icon: PhosphorIconsFill.play,
                        onTap: () => _train(entries)),
                    ),
                    const SizedBox(width: 10),
                    SqSquareButton(PhosphorIconsBold.plus,
                      size: 54,
                      fill: AppColors.card(d),
                      border: AppColors.border(d),
                      lip: d ? AppColors.borderD : const Color(0xFFEDEAF6),
                      onTap: _adding ? null : () => _addAll(entries)),
                  ],
                ),
                const SizedBox(height: 18),
                SqSection(tr('Топтамадағы сөздер'),
                  trailingWidget: SqNum('${entries.length}',
                    size: 11, color: AppColors.text3(d))),
                SqGroup(children: [
                  for (final e in entries.take(40))
                    SqTile(
                      leading: SqTintBox(
                        owned.contains(e.en.toLowerCase())
                            ? PhosphorIconsFill.checkCircle
                            : PhosphorIconsFill.circleDashed,
                        tint: owned.contains(e.en.toLowerCase())
                            ? AppColors.green : AppColors.text3(d),
                        size: 34),
                      title: e.en,
                      subtitle: e.kk,
                      trailing: SqSquareButton(
                        PhosphorIconsFill.speakerHigh,
                        size: 32,
                        fill: AppColors.muted(d),
                        border: Colors.transparent,
                        onTap: () => Speech.instance.say(e.en)),
                    ),
                ]),
              ],
            );
          },
        ),
      ],
    );
  }
}
