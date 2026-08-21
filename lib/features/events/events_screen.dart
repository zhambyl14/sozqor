// lib/features/events/events_screen.dart
//
// The learner's side of the events a moderator publishes.
//
// Events, event_progress and the active_events RPC all existed before this
// screen did, and so did the providers — but nothing in the app ever rendered
// an AppEvent. A moderator could write an event, set its rules, its entry
// conditions and its prize, and no learner would ever see any of it.
//
// The list stays deliberately thin: emoji, name, how far along you are, how
// long is left. Rules, who may enter and what is won are a tap away rather
// than stacked on the card, because five events each explaining themselves in
// a paragraph is a wall nobody reads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/app_event.dart';
import '../../data/supa.dart';
import '../../providers.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(activeEventsProvider);
    final progress = ref.watch(eventProgressProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(activeEventsProvider);
        ref.invalidate(eventProgressProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Ивенттер'),
          eyebrow: tr('Сенің деңгейің бойынша'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 14),

        events.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Ивенттер жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.rose),
          data: (list) {
            if (list.isEmpty) {
              return SqEmpty(
                icon: PhosphorIconsFill.confetti,
                title: tr('Әзірге ивент жоқ'),
                // Said plainly, because an empty list here is far more often
                // "nothing is running" than "something is broken".
                subtitle: tr('Жаңасы басталғанда осында шығады'));
            }
            return Column(
              children: [
                for (final e in list) ...[
                  _EventCard(
                    event: e,
                    progress: progress.value?[e.id],
                    onTap: () => _openDetail(context, e, progress.value?[e.id]),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  void _openDetail(BuildContext context, AppEvent e, EventProgress? p) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _EventSheet(event: e, progress: p),
      );
}

class _EventCard extends StatelessWidget {
  final AppEvent event;
  final EventProgress? progress;
  final VoidCallback onTap;
  const _EventCard({
    required this.event, required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final done = progress?.completed ?? false;
    final tint = done ? AppColors.mint : AppColors.primary;

    return SqPanel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15)),
                child: Text(event.emoji,
                    style: const TextStyle(fontSize: 21))),
              const SizedBox(width: 12),
              // Flexible, not a fixed width: event names are written by a
              // moderator at runtime and can be any length in two languages.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.text(dark))),
                    if (event.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.subtitle,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.text3(dark))),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SqBadge(event.levelLabel, tint: tint),
            ],
          ),

          if (progress != null) ...[
            const SizedBox(height: 13),
            SqTrack(progress!.ratio, color: tint),
            const SizedBox(height: 6),
            Text(
              done
                  ? tr('Аяқталды')
                  : trp('{p1} / {p2}', {
                      'p1': '${progress!.progress}',
                      'p2': '${progress!.target}',
                    }),
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: done ? AppColors.mint : AppColors.text3(dark))),
          ],

          const SizedBox(height: 11),
          Row(
            children: [
              Icon(PhosphorIconsBold.clock,
                  size: 13, color: AppColors.text3(dark)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  event.remainingLabel,
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: AppColors.text3(dark)))),
              SqNum('+${event.xpReward} XP',
                  size: 12.5, color: AppColors.amber),
            ],
          ),
        ],
      ),
    );
  }
}

/// Everything the moderator wrote, shown only when asked for.
class _EventSheet extends ConsumerWidget {
  final AppEvent event;
  final EventProgress? progress;
  const _EventSheet({required this.event, required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = isDark(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: AppColors.bg(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: SqSheetGrip()),
              const SizedBox(height: 16),

              Row(
                children: [
                  Text(event.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppColors.text(dark)))),
                ],
              ),
              if (event.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  event.subtitle,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: AppColors.text3(dark))),
              ],

              const SizedBox(height: 16),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  SqChip(event.levelLabel, icon: PhosphorIconsBold.stack),
                  SqChip(event.remainingLabel, icon: PhosphorIconsBold.clock),
                  SqChip('+${event.xpReward} XP',
                      icon: PhosphorIconsBold.star, tint: AppColors.amber),
                ],
              ),

              _section(dark, tr('Ереже'), event.rules),
              _section(dark, tr('Кім қатыса алады'), event.who),

              if (event.hasPrizeItem)
                _section(
                  dark,
                  tr('Жүлде'),
                  trp('Үздік {p1} қатысушы дүкен затын алады', {
                    'p1': '${event.prizeTopN}',
                  })),

              if (progress != null) ...[
                const SizedBox(height: 20),
                SqTrack(progress!.ratio,
                    color: progress!.completed
                        ? AppColors.mint
                        : AppColors.primary),
                const SizedBox(height: 7),
                Text(
                  progress!.completed
                      ? tr('Аяқталды')
                      : trp('{p1} / {p2}', {
                          'p1': '${progress!.progress}',
                          'p2': '${progress!.target}',
                        }),
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.text3(dark))),
              ],

              const SizedBox(height: 22),
              SqAction(
                tr('Жабу'),
                onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders nothing at all when the moderator left the field blank, rather
  /// than a heading with a gap under it.
  Widget _section(bool dark, String title, String? body) {
    if (body == null || body.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SqEyebrow(title),
          const SizedBox(height: 7),
          Text(
            body,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, height: 1.5,
              color: AppColors.text(dark))),
        ],
      ),
    );
  }
}
