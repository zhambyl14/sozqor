// lib/features/words/collections_screen.dart
//
// The learner's own word collections (EN-34 / KK-5).
//
// "Users can add existing Dictionary words to their collection using a '+'
// action. Do not make them manually enter words that already exist." That
// second sentence is the whole feature: the words are already in the bank, so
// building "Менің IELTS сөздерім" should be picking from a list, never typing
// anything twice.
//
// Official packs and personal ones are the same rows on the server, so they
// share a screen here too — with the learner's own kept first, since those are
// the ones they came to manage.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/collection.dart';
import '../../data/repos/collections_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../auth/guest_gate.dart';
import 'collection_detail_screen.dart';

/// Enough to feel like a choice, few enough to stay one tap.
const _kEmojis = ['📚', '🎯', '⭐', '🔥', '🌱', '🧠', '✈️', '🍜', '💼', '🎬'];
const _kColours = [
  '#7C5CFF', '#F0455E', '#12B981', '#F59E0B', '#3B82F6', '#EC4899',
];

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      ref.invalidate(collectionsProvider);
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

  Future<void> _create() async {
    if (!await requireAccount(context, ref, GuestFeature.saveWord)) return;
    if (!mounted) return;
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewCollectionSheet(),
    );
    if (made == true) ref.invalidate(collectionsProvider);
  }

  Future<void> _delete(WordCollection c) async {
    final ok = await sqConfirm(context,
      title: tr('Топтаманы жою'),
      message: trp('«{p1}» жойылсын ба? Сөздерің сөздігіңде қалады.',
        {'p1': c.title}),
      confirm: tr('Жою'));
    if (!ok) return;
    await _run(() async {
      await ref.read(collectionsRepoProvider).remove(c.id);
      if (mounted) sqSnack(context, tr('Топтама жойылды'));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(collectionsProvider);
    final unavailable =
        async.hasError && async.error is CollectionsUnavailable;
    final all = async.valueOrNull ?? const <WordCollection>[];
    final mine = all.where((c) => c.isMine).toList();
    final official = all.where((c) => c.isOfficial).toList();

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(collectionsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Топтамалар'),
          eyebrow: tr('Сөз жинақтары'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (unavailable)
          SqEmpty(
            icon: PhosphorIconsFill.folders,
            title: tr('Топтама жүйесі әлі қосылмаған'),
            subtitle: tr('Сервер жаңартылған соң қолжетімді болады'),
            tint: AppColors.sky)
        else if (async.isLoading && all.isEmpty)
          const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()])
        else if (async.hasError && all.isEmpty)
          SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Топтамалар жүктелмеді'),
            subtitle: humanError(async.error!),
            action: SizedBox(
              width: 200,
              child: SqAction(tr('Қайталау'),
                icon: PhosphorIconsBold.arrowClockwise,
                onTap: () => ref.invalidate(collectionsProvider)),
            ))
        else ...[
          SqLip(
            fill: AppColors.primary,
            lip: AppColors.primaryDeep,
            radius: 20,
            padding: const EdgeInsets.all(16),
            onTap: _busy ? null : _create,
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.plus,
                  size: 22, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Өз топтамаңды жаса'),
                        style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                      Text(tr('Сөздігіңдегі сөздерден жина'),
                        style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (mine.isNotEmpty) ...[
            SqSection(tr('Менің топтамаларым'),
              trailingWidget: SqNum('${mine.length}',
                size: 11, color: AppColors.text3(d))),
            SqGroup(children: [
              for (final c in mine)
                _CollectionRow(
                  collection: c,
                  onOpen: () => _open(c),
                  onDelete: () => _delete(c)),
            ]),
            const SizedBox(height: 18),
          ],

          SqSection(tr('Ресми топтамалар')),
          if (official.isEmpty)
            SqPanel(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Әзірге ресми топтама жоқ'),
                style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
            )
          else
            SqGroup(children: [
              for (final c in official)
                _CollectionRow(collection: c, onOpen: () => _open(c)),
            ]),
        ],
      ],
    );
  }

  Future<void> _open(WordCollection c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CollectionDetailScreen(collection: c)));
    if (mounted) ref.invalidate(collectionsProvider);
  }
}

class _CollectionRow extends StatelessWidget {
  final WordCollection collection;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const _CollectionRow({
    required this.collection, required this.onOpen, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final c = collection;
    final tint = sqHexColor(c.colour) ?? AppColors.primary;

    return SqTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Text(c.emoji, style: const TextStyle(fontSize: 19)),
      ),
      title: c.title,
      // The real count, from the server. This row is where the old "120 words"
      // lie was told.
      subtitle: c.isEmpty
          ? tr('Сөз жоқ')
          : trp('{n} сөз · {have} сөздігіңде',
              {'n': '${c.wordCount}', 'have': '${c.ownedCount}'}),
      below: c.isEmpty
          ? null
          : SqTrack(c.progress, color: tint, height: 5),
      trailing: onDelete == null
          ? Icon(PhosphorIconsBold.caretRight,
              size: 15, color: AppColors.text3(d))
          : SqSquareButton(PhosphorIconsBold.trash,
              size: 32,
              fill: AppColors.soft(AppColors.red, d),
              border: Colors.transparent,
              iconColor: AppColors.red,
              onTap: onDelete),
      onTap: onOpen,
    );
  }
}

class _NewCollectionSheet extends ConsumerStatefulWidget {
  const _NewCollectionSheet();

  @override
  ConsumerState<_NewCollectionSheet> createState() =>
      _NewCollectionSheetState();
}

class _NewCollectionSheetState extends ConsumerState<_NewCollectionSheet> {
  final _title = TextEditingController();
  String _emoji = _kEmojis.first;
  String _colour = _kColours.first;
  bool _busy = false;

  @override
  void dispose() { _title.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      sqSnack(context, tr('Топтама атауын жаз'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(collectionsRepoProvider)
          .create(title: title, emoji: _emoji, colour: _colour);
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
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SqSheetGrip(),
            Text(tr('Жаңа топтама'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Атауы'),
                hintText: tr('Мысалы: Менің IELTS сөздерім'),
              ),
            ),
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
            const SizedBox(height: 20),
            SqAction(tr('Жасау'),
              icon: PhosphorIconsBold.check,
              busy: _busy,
              onTap: _busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}
