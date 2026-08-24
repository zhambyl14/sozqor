// lib/features/profile/public_profile_screen.dart
//
// Somebody else's profile (EN-17 / KK-2).
//
// The friends list and every leaderboard showed a name, an avatar and one
// number, and there was no way to look further. Cosmetics in particular were
// bought to be seen, and the only person who could see them was their owner —
// which is most of why the shop felt pointless.
//
// What this deliberately does NOT show is as much the point as what it does.
// The profile row carries a phone number, a Telegram id, a role and a guest
// flag; none of them appear here, and none of them are fetched in a shape
// this screen could leak. Everything below is the public face: who they are,
// how far they have come, and what they are wearing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/profile.dart';
import '../../data/repos/cosmetics_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'worn_avatar.dart';

/// Everything the screen needs, in one request each.
final _publicProfileProvider =
    FutureProvider.family<Profile?, String>((ref, userId) =>
        ref.watch(profileRepoProvider).byId(userId));

final _publicWornProvider =
    FutureProvider.family<WornCosmetics?, String>((ref, userId) async {
  final all = await ref.watch(cosmeticsRepoProvider).worn([userId]);
  return all[userId];
});

final _publicAchievementsProvider =
    FutureProvider.family<Set<String>, String>((ref, userId) =>
        ref.watch(profileRepoProvider).unlockedAchievements(userId));

class PublicProfileScreen extends ConsumerWidget {
  final String userId;
  /// Shown while the real row is in flight, so the screen opens with a name
  /// on it rather than a spinner — the caller always already knows this much.
  final String? fallbackName;

  const PublicProfileScreen({
    super.key, required this.userId, this.fallbackName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(_publicProfileProvider(userId));
    final worn = ref.watch(_publicWornProvider(userId)).valueOrNull;
    final unlocked =
        ref.watch(_publicAchievementsProvider(userId)).valueOrNull
            ?? const <String>{};
    final p = async.valueOrNull;
    final name = p?.name ?? fallbackName ?? '…';

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Профиль'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (async.hasError)
          SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Профиль ашылмады'),
            subtitle: humanError(async.error!),
            action: SizedBox(
              width: 200,
              child: SqAction(tr('Қайталау'),
                icon: PhosphorIconsBold.arrowClockwise,
                onTap: () => ref.invalidate(_publicProfileProvider(userId))),
            ),
          )
        else ...[
          SqInkCard(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            glow: sqHexColor(worn?.bannerColor) ?? AppColors.primary,
            glowAt: Alignment.topRight,
            child: Column(
              children: [
                WornAvatar(
                  name: name,
                  worn: worn,
                  size: 84,
                  emoji: p?.avatarEmoji),
                const SizedBox(height: 12),
                Text(name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800,
                    letterSpacing: -0.5, color: Colors.white)),
                if ((p?.username ?? '').isNotEmpty)
                  Text('@${p!.username}',
                    style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: AppColors.onInk3)),
                // A title is a cosmetic somebody chose to wear, so it is
                // shown the way they meant it to be — under the name.
                if (worn?.title != null) ...[
                  const SizedBox(height: 8),
                  SqChip(worn!.title!,
                    tint: sqHexColor(worn.auraColor) ?? AppColors.amber,
                    radius: 999,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          SqEqualRow(
            children: [
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.lightning,
                tint: AppColors.amber,
                value: '${p?.xp ?? 0}',
                label: tr('XP'))),
              const SizedBox(width: 9),
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.sword,
                tint: AppColors.red,
                value: '${p?.elo ?? 1000}',
                label: tr('Рейтинг'))),
              const SizedBox(width: 9),
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.fire,
                tint: AppColors.primary,
                value: '${p?.streak ?? 0}',
                label: tr('Серия'))),
            ],
          ),
          const SizedBox(height: 10),
          SqEqualRow(
            children: [
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.chartBar,
                tint: AppColors.sky,
                value: p?.cefrLevel ?? 'A1',
                label: tr('Деңгей'))),
              const SizedBox(width: 9),
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.trophy,
                tint: AppColors.green,
                value: '${p?.battlesWon ?? 0}',
                label: tr('Жеңіс'))),
              const SizedBox(width: 9),
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.books,
                tint: AppColors.primary,
                value: '${p?.wordsTotal ?? 0}',
                label: tr('Сөз'))),
            ],
          ),
          const SizedBox(height: 18),

          SqSection(tr('Жетістіктер'),
            trailingWidget: SqNum('${unlocked.length} / ${kAchievements.length}',
              size: 11, color: AppColors.text3(d))),
          if (unlocked.isEmpty)
            SqPanel(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Әзірге жетістік жоқ'),
                style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
            )
          else
            SqPanel(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in kAchievements)
                    if (unlocked.contains(a.code))
                      Tooltip(
                        message: tr(a.title),
                        child: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.muted(d),
                            borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.center,
                          child: Text(a.emoji,
                            style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
