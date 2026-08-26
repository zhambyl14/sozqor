// lib/features/words/add_to_collection_sheet.dart
//
// Putting one word into a collection, from wherever that word is.
//
// The collection screen could already pull words in — open a collection, tap
// "add", tick things off a list. What there was no way to do was the other
// direction: you are looking at a word, you know exactly where it belongs,
// and there was nothing to press. Somebody reading "шаңырақ" had to remember
// it, leave, open the right collection and find it again.
//
// Official packs appear here only for a moderator, and go through the admin
// RPC — a learner sees their own collections and nothing else, because those
// are the only ones the server would let them write to anyway.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/collection.dart';
import '../../data/repos/collections_repo.dart';
import '../../data/supa.dart';
import '../../data/repos/moderator_repo.dart';
import '../../providers.dart';
import '../auth/guest_gate.dart';

/// Opens the picker. [dictionaryId] is the shared catalogue row — a word the
/// learner typed in themselves has none, and cannot be shared into a pack.
Future<void> showAddToCollectionSheet(
  BuildContext context,
  WidgetRef ref, {
  required int? dictionaryId,
  required String label,
}) async {
  if (!await requireAccount(context, ref, GuestFeature.saveWord)) return;
  if (!context.mounted) return;

  if (dictionaryId == null) {
    sqSnack(context,
        tr('Бұл сөз ортақ базада жоқ, сондықтан топтамаға қосылмайды'),
        error: true);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddToCollectionSheet(
      dictionaryId: dictionaryId, label: label),
  );
}

class _AddToCollectionSheet extends ConsumerStatefulWidget {
  final int dictionaryId;
  final String label;
  const _AddToCollectionSheet({
    required this.dictionaryId, required this.label});

  @override
  ConsumerState<_AddToCollectionSheet> createState() =>
      _AddToCollectionSheetState();
}

class _AddToCollectionSheetState
    extends ConsumerState<_AddToCollectionSheet> {
  int? _busyId;
  final _added = <int>{};
  final _newTitle = TextEditingController();
  bool _creating = false;

  @override
  void dispose() { _newTitle.dispose(); super.dispose(); }

  Future<void> _add(WordCollection c, {bool official = false}) async {
    if (_busyId != null || _added.contains(c.id)) return;
    setState(() => _busyId = c.id);
    try {
      final repo = ref.read(collectionsRepoProvider);
      if (official) {
        await repo.addWords(c.id, [widget.dictionaryId]);
      } else {
        await repo.addWord(c.id, widget.dictionaryId);
      }
      ref.invalidate(collectionsProvider);
      if (mounted) {
        setState(() => _added.add(c.id));
        sqSnack(context, trp('«{p1}» топтамасына қосылды', {'p1': c.title}));
      }
    } on CollectionsUnavailable {
      if (mounted) {
        sqSnack(context, tr('Топтама жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// A collection that does not exist yet is the commonest case the first
  /// time somebody uses this, so it is one field here rather than a trip to
  /// another screen and back.
  Future<void> _createAndAdd() async {
    final title = _newTitle.text.trim();
    if (title.isEmpty) return;
    setState(() => _creating = true);
    try {
      final repo = ref.read(collectionsRepoProvider);
      final id = await repo.create(title: title);
      await repo.addWord(id, widget.dictionaryId);
      ref.invalidate(collectionsProvider);
      if (mounted) {
        _newTitle.clear();
        setState(() => _added.add(id));
        sqSnack(context, trp('«{p1}» топтамасына қосылды', {'p1': title}));
      }
    } on CollectionsUnavailable {
      if (mounted) {
        sqSnack(context, tr('Топтама жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final all = ref.watch(collectionsProvider).valueOrNull
        ?? const <WordCollection>[];
    final isMod = ref.watch(amModeratorProvider).valueOrNull ?? false;

    final mine = all.where((c) => c.isMine).toList();
    final official = isMod
        ? all.where((c) => c.isOfficial).toList()
        : const <WordCollection>[];

    return SqSheet(
      title: tr('Топтамаға қосу'),
      children: [
        Text(widget.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.text3(d))),
        const SizedBox(height: 16),

        if (mine.isEmpty && official.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(tr('Әзірге топтама жоқ — біреуін осында құр'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
          ),

        if (mine.isNotEmpty) ...[
          SqGroup(children: [
            for (final c in mine) _row(c, d),
          ]),
          const SizedBox(height: 14),
        ],

        // Only a moderator sees these, and only a moderator's key can write
        // to them: the admin RPC checks the role again server-side.
        if (official.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: SqEyebrow(tr('Ресми топтамалар'))),
          SqGroup(children: [
            for (final c in official) _row(c, d, official: true),
          ]),
          const SizedBox(height: 14),
        ],

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newTitle,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr('Жаңа топтама аты'),
                  isDense: true)),
            ),
            const SizedBox(width: 9),
            SqSquareButton(PhosphorIconsBold.plus,
              size: 50,
              fill: _newTitle.text.trim().isEmpty
                  ? AppColors.muted(d) : AppColors.primary,
              onTap: _creating || _newTitle.text.trim().isEmpty
                  ? null : _createAndAdd),
          ],
        ),
      ],
    );
  }

  Widget _row(WordCollection c, bool d, {bool official = false}) {
    final done = _added.contains(c.id);
    return SqTile(
      leading: SqTintBox(PhosphorIconsFill.stack,
        tint: sqHexColor(c.colour) ?? AppColors.primary, size: 34),
      title: c.title,
      subtitle: trp('{n} сөз', {'n': '${c.wordCount}'}),
      trailing: _busyId == c.id
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              done ? PhosphorIconsFill.checkCircle : PhosphorIconsBold.plus,
              size: 18,
              color: done ? AppColors.green : AppColors.text3(d)),
      onTap: done ? null : () => _add(c, official: official),
    );
  }
}
