// lib/features/home/missions_screen.dart
//
// The mission path — a season track that turns XP the learner is already
// earning into a visible ladder of rewards.
//
// Level is derived from lifetime XP (400 per step), so nothing here is a
// second currency to farm: playing normally advances it. Free rewards unlock
// as you pass them; the premium ones stay visible but locked, which is what
// makes the free track feel like progress rather than a teaser.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import '../../services/meta_store.dart';

class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final xp = ref.watch(myProfileProvider).value?.xp ?? 0;
    final meta = ref.watch(metaProvider);
    final level = passLevelFor(xp);
    final claimed = meta.passClaimed;

    final unclaimed = kPassRewards
        .where((r) => r.level <= level && !claimed.contains(r.level))
        .where((r) => !r.premium || meta.passPremium)
        .toList();
    final lockedPremium = kPassRewards
        .where((r) => r.premium && !meta.passPremium)
        .length;

    // No stored season-start date exists (checked meta_store.dart), so the
    // countdown is simply days remaining until the end of this month.
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Миссия жолы'),
          eyebrow: tr('1-маусым'),
          onBack: () => Navigator.of(context).pop(),
          actions: [SqBadge(trp('{n} күн', {'n': '$daysLeft'}),
            tint: AppColors.red)],
        ),
        const SizedBox(height: 16),

        SqInkCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: SqNum('$level', size: 19, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(trp('{n}-деңгей · {rank}',
                            {'n': '$level', 'rank': _rankName(level)}),
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(trp('Келесі деңгейге {xp} XP',
                            {'xp': '${passXpToNext(xp)}'}),
                          style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: AppColors.onInk2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SqTrack(passProgressFor(xp),
                height: 9, background: AppColors.inkTrack),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: SqInkStat('${claimed.length}',
                    tr('алынған сыйлық'))),
                  const SizedBox(width: 8),
                  Expanded(child: SqInkStat('$lockedPremium',
                    tr('премиум құлыпта'), valueColor: AppColors.amber)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (unclaimed.isNotEmpty) ...[
          SqPanel(
            fill: AppColors.soft(AppColors.green, d),
            border: AppColors.line(AppColors.green, d),
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.gift,
                  tint: AppColors.green, size: 38, solid: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    trp('{n} сыйлық алуға дайын',
                      {'n': '${unclaimed.length}'}),
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                      color: AppColors.onSoft(AppColors.green, d))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        for (final r in kPassRewards) ...[
          _RewardRow(
            reward: r,
            level: level,
            claimed: claimed.contains(r.level),
            premiumUnlocked: meta.passPremium,
          ),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 6),
        if (!meta.passPremium)
          SqAction(tr('Премиум жолды ашу'),
            tone: SqTone.amber,
            icon: PhosphorIconsFill.crownSimple,
            onTap: () async {
              final ok = await sqConfirm(context,
                title: tr('Премиум жол'),
                message: tr('Премиум жол осы құрылғыда тегін ашылады.'),
                confirm: tr('Ашу'),
                cancel: tr('Кейін'),
                danger: false);
              if (!ok) return;
              await ref.read(metaProvider.notifier).unlockPremium();
            })
        else
          SqPanel(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.crownSimple,
                  tint: AppColors.amber, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('Премиум жол ашық'),
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                      color: AppColors.text(d))),
                ),
                const Icon(PhosphorIconsFill.checkCircle,
                  size: 20, color: AppColors.green),
              ],
            ),
          ),
      ],
    );
  }

  static String _rankName(int level) {
    if (level >= 11) return tr('Аңыз');
    if (level >= 9) return tr('Шебер');
    if (level >= 7) return tr('Жауынгер');
    if (level >= 4) return tr('Ізденуші');
    if (level >= 2) return tr('Жаңашыл');
    return tr('Бастауыш');
  }
}

class _RewardRow extends ConsumerWidget {
  final PassReward reward;
  final int level;
  final bool claimed, premiumUnlocked;

  const _RewardRow({
    required this.reward,
    required this.level,
    required this.claimed,
    required this.premiumUnlocked,
  });

  IconData get _icon {
    if (reward.grant == null) return PhosphorIconsFill.star;
    if (reward.grant!.startsWith('freeze')) return PhosphorIconsFill.snowflake;
    if (reward.grant == 'life') return PhosphorIconsFill.heart;
    if (reward.grant == 'theme_night') return PhosphorIconsFill.moonStars;
    if (reward.grant == 'frame_eagle') return PhosphorIconsFill.bird;
    return PhosphorIconsFill.circleHalf;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final reached = reward.level <= level;
    final locked = reward.premium && !premiumUnlocked;
    final canClaim = reached && !claimed && !locked;
    final tint = reward.premium ? AppColors.amber : AppColors.primary;
    final isCurrent = reward.level == level + 1;

    return SqPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      fill: isCurrent ? AppColors.soft(AppColors.primary, d) : null,
      border: isCurrent ? AppColors.primaryEdge : null,
      onTap: canClaim
          ? () async {
              await ref.read(metaProvider.notifier).claimPass(reward);
              if (reward.xp > 0) {
                await ref.read(profileRepoProvider)
                    .addXp(reward.xp, 'mission_path')
                    .catchError((_) => 0);
                ref.invalidate(myProfileProvider);
              }
              if (context.mounted) {
                sqSnack(context, trp('«{name}» алынды',
                  {'name': tr(reward.title)}));
              }
            }
          : null,
      child: Opacity(
        opacity: reached || isCurrent ? 1 : 0.55,
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: reached ? AppColors.inkBlock(d) : AppColors.muted(d),
                borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: SqNum('${reward.level}',
                size: 13,
                color: reached ? Colors.white : AppColors.text3(d)),
            ),
            const SizedBox(width: 11),
            SqTintBox(_icon, tint: tint, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(reward.title),
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                      color: AppColors.text(d))),
                  const SizedBox(height: 1),
                  Text(reward.premium ? tr('Премиум') : tr('Тегін'),
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.onSoft(tint, d))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (claimed)
              const Icon(PhosphorIconsFill.checkCircle,
                size: 20, color: AppColors.green)
            else if (canClaim)
              SqBadge(tr('Алу'), tint: AppColors.green, solid: true)
            else if (locked)
              Icon(PhosphorIconsFill.lockSimple,
                size: 17, color: AppColors.text4(d))
            else
              Icon(PhosphorIconsBold.minus,
                size: 15, color: AppColors.text4(d)),
          ],
        ),
      ),
    );
  }
}
