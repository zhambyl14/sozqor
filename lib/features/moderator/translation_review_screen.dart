// lib/features/moderator/translation_review_screen.dart
//
// What the translation gate refused (EN-49 / EN-50 / KK-8).
//
// The gate in supabase/functions/sozqor-ai/index.ts stops a bad answer
// reaching a learner: a transliteration, the word echoed back, two models that
// disagreed. That is the right outcome and it is also a silent one — a word
// that keeps failing is a word the app cannot teach, and nobody would ever
// know. Refusing a bad translation is only half an answer if nobody can then
// supply a good one.
//
// So the queue shows the word, what the machine offered, why it was refused,
// and how many times it has failed. A term refused nine times is a different
// problem from one refused once, and the count is the fastest way to see it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/moderator_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';

/// The queue, newest first. `autoDispose` for the same reason the other
/// console lists are: leaving the screen should drop the data, so coming back
/// shows what is actually open now.
final translationQueueProvider =
    FutureProvider.autoDispose.family<List<TranslationReport>, String>(
        (ref, status) =>
            ref.watch(moderatorRepoProvider).translationQueue(status: status));

class TranslationReviewScreen extends ConsumerStatefulWidget {
  const TranslationReviewScreen({super.key});

  @override
  ConsumerState<TranslationReviewScreen> createState() =>
      _TranslationReviewScreenState();
}

class _TranslationReviewScreenState
    extends ConsumerState<TranslationReviewScreen> {
  String _status = 'open';
  bool _busy = false;

  Future<void> _fix(TranslationReport r) async {
    final result = await showModalBottomSheet<_Fix>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FixSheet(report: r),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(moderatorRepoProvider).fixTranslation(
        r.id, en: result.en, kk: result.kk, ru: result.ru);
      ref.invalidate(translationQueueProvider(_status));
      if (mounted) sqSnack(context, tr('Аударма түзетілді'));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss(TranslationReport r) async {
    setState(() => _busy = true);
    try {
      await ref.read(moderatorRepoProvider).dismissTranslation(r.id);
      ref.invalidate(translationQueueProvider(_status));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final async = ref.watch(translationQueueProvider(_status));

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(translationQueueProvider(_status));
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Аударма тексеру'),
          eyebrow: tr('Модератор'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 14),

        SqSegmented(
          items: [tr('Ашық'), tr('Түзетілген'), tr('Қабылданбаған')],
          index: switch (_status) {
            'open'  => 0,
            'fixed' => 1,
            _       => 2,
          },
          onChanged: (i) => setState(() => _status = switch (i) {
            0 => 'open',
            1 => 'fixed',
            _ => 'rejected',
          }),
        ),
        const SizedBox(height: 16),

        async.when(
          loading: () =>
              const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Кезек жүктелмеді'),
            subtitle: humanError(e),
            action: SizedBox(
              width: 200,
              child: SqAction(tr('Қайталау'),
                icon: PhosphorIconsBold.arrowClockwise,
                onTap: () =>
                    ref.invalidate(translationQueueProvider(_status))),
            )),
          data: (rows) {
            if (rows.isEmpty) {
              return SqEmpty(
                icon: PhosphorIconsFill.checkCircle,
                title: _status == 'open'
                    ? tr('Кезек бос')
                    : tr('Мұнда ештеңе жоқ'),
                subtitle: _status == 'open'
                    ? tr('Аударма қақпасы ештеңе қайтармаған')
                    : '',
                tint: AppColors.green);
            }
            return Column(
              children: [
                for (final r in rows) ...[
                  _ReportCard(
                    report: r,
                    busy: _busy,
                    onFix: () => _fix(r),
                    onDismiss: () => _dismiss(r)),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final TranslationReport report;
  final bool busy;
  final VoidCallback onFix, onDismiss;

  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onFix,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final r = report;

    return SqPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.term,
                  style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800,
                    letterSpacing: -0.4, color: AppColors.text(d))),
              ),
              // A word that failed nine times is a different problem from one
              // that failed once, and this is the fastest way to see which.
              if (r.failCount > 1)
                SqBadge(trp('{n}×', {'n': '${r.failCount}'}),
                  tint: AppColors.red, numeric: true),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(PhosphorIconsFill.xCircle,
                size: 15, color: AppColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.candidate.isEmpty
                      ? tr('Жауап болмады')
                      : trp('Ұсынған: «{w}»', {'w': r.candidate}),
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppColors.text2(d))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(PhosphorIconsFill.info,
                size: 15, color: AppColors.text3(d)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.reason,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.text3(d))),
              ),
            ],
          ),

          // What the dictionary currently holds, which is how a moderator
          // tells "never learned it" from "learned it wrong".
          if ((r.currentEn ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            SqPanel(
              padding: const EdgeInsets.all(11),
              fill: AppColors.soft(AppColors.amber, d),
              border: AppColors.line(AppColors.amber, d),
              child: Text(
                trp('Базада қазір: {en} · {kk}',
                  {'en': r.currentEn!, 'kk': r.currentKk ?? '—'}),
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppColors.onSoft(AppColors.amber, d))),
            ),
          ],

          if (r.status == 'open') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SqAction(tr('Түзету'),
                    icon: PhosphorIconsBold.pencilSimple,
                    height: 44,
                    onTap: busy ? null : onFix),
                ),
                const SizedBox(width: 9),
                SqAction(tr('Керегі жоқ'),
                  tone: SqTone.ghost,
                  height: 44,
                  onTap: busy ? null : onDismiss),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Fix {
  final String en, kk, ru;
  const _Fix(this.en, this.kk, this.ru);
}

class _FixSheet extends StatefulWidget {
  final TranslationReport report;
  const _FixSheet({required this.report});

  @override
  State<_FixSheet> createState() => _FixSheetState();
}

class _FixSheetState extends State<_FixSheet> {
  late final _en = TextEditingController(text: widget.report.currentEn ?? '');
  late final _kk = TextEditingController(
    text: widget.report.currentKk ?? widget.report.term);
  late final _ru = TextEditingController(text: widget.report.currentRu ?? '');

  @override
  void dispose() {
    _en.dispose(); _kk.dispose(); _ru.dispose();
    super.dispose();
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
            Text(trp('«{w}» аудармасы', {'w': widget.report.term}),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            const SizedBox(height: 18),
            TextField(
              controller: _en,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Ағылшынша'))),
            const SizedBox(height: 10),
            TextField(
              controller: _kk,
              decoration: InputDecoration(labelText: tr('Қазақша'))),
            const SizedBox(height: 10),
            TextField(
              controller: _ru,
              decoration: InputDecoration(labelText: tr('Орысша'))),
            const SizedBox(height: 20),
            SqAction(tr('Сақтау'),
              icon: PhosphorIconsBold.check,
              onTap: () {
                if (_en.text.trim().isEmpty || _kk.text.trim().isEmpty) return;
                Navigator.of(context).pop(
                  _Fix(_en.text.trim(), _kk.text.trim(), _ru.text.trim()));
              }),
          ],
        ),
      ),
    );
  }
}
