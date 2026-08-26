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
import '../auth/guest_gate.dart';
import 'achievements_screen.dart';
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

/// The band the person is standing in, their code, and whether this user is
/// allowed to add them.
///
/// A separate request from the profile row because it is computed — the band
/// comes from the same league_bands() table the league screen reads, so the
/// two can never drift into disagreeing about what "Алтын" means.
final _publicMetaProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) =>
        ref.watch(boardRepoProvider).publicProfile(userId));

final _publicAchievementsProvider =
    FutureProvider.family<Set<String>, String>((ref, userId) =>
        ref.watch(profileRepoProvider).unlockedAchievements(userId));

class PublicProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  /// Shown while the real row is in flight, so the screen opens with a name
  /// on it rather than a spinner — the caller always already knows this much.
  final String? fallbackName;

  const PublicProfileScreen({
    super.key, required this.userId, this.fallbackName});

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _adding = false;
  bool _asked = false;

  /// Sends the request and says so. Reachable from anywhere a profile can be
  /// opened — the league standings, a search result, the end of a match —
  /// because "I just played somebody good" is exactly when you want to add
  /// them and there was no way to.
  Future<void> _addFriend() async {
    if (_adding || _asked) return;
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted) return;
    setState(() => _adding = true);
    try {
      await ref.read(boardRepoProvider).sendFriendRequest(widget.userId);
      if (mounted) {
        setState(() => _asked = true);
        sqSnack(context, tr('Достық сұранысы жіберілді'));
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
    final userId = widget.userId;
    final fallbackName = widget.fallbackName;
    final d = isDark(context);
    final async = ref.watch(_publicProfileProvider(userId));
    final worn = ref.watch(_publicWornProvider(userId)).valueOrNull;
    final meta = ref.watch(_publicMetaProvider(userId)).valueOrNull;
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
                // The level, beside the title, because a level nobody else
                // can see is a number the app keeps to itself. Computed from
                // xp with the same curve the owner's own profile uses, so the
                // two can never disagree.
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (p != null)
                      SqChip(trp('{n}-деңгей', {'n': '${p.levelNumber}'}),
                        tint: AppColors.sky,
                        radius: 999,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6)),
                    // A title is a cosmetic somebody chose to wear, so it is
                    // shown the way they meant it to be — under the name.
                    if (worn?.title != null)
                      SqChip(worn!.title!,
                        tint: sqHexColor(worn.auraColor) ?? AppColors.amber,
                        radius: 999,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Which league they are standing in. A ladder nobody can see you on
          // is not a ladder, and this is the only place another person could
          // ever be seen on it.
          if (meta != null) ...[
            SqPanel(
              radius: 18,
              padding: const EdgeInsets.all(14),
              fill: AppColors.soft(
                sqHexColor(meta['tier_colour']?.toString()) ?? AppColors.amber, d),
              border: AppColors.line(
                sqHexColor(meta['tier_colour']?.toString()) ?? AppColors.amber, d),
              child: Row(
                children: [
                  SqTintBox(PhosphorIconsFill.shieldChevron,
                    tint: sqHexColor(meta['tier_colour']?.toString())
                        ?? AppColors.amber,
                    size: 38, solid: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trp('{tier} лигасы', {
                            'tier': (AppLang.isRu
                                ? meta['tier_ru'] : meta['tier_kk'])
                                ?.toString() ?? '—'
                          }),
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: AppColors.text(d))),
                        Text(
                          trp('Дос коды: {p1}',
                            {'p1': sqFriendCode(meta['friend_code']?.toString())}),
                          style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: AppColors.text3(d))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (meta['can_add'] == true && !_asked)
              SqAction(tr('Дос қосу'),
                icon: PhosphorIconsFill.userPlus,
                busy: _adding,
                onTap: _addFriend)
            else if (_asked || meta['friendship'] == 'pending')
              SqPanel(
                radius: 14,
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(tr('Достық сұранысы жіберілді'),
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.text3(d))),
                ),
              )
            else if (meta['friendship'] == 'accepted')
              SqPanel(
                radius: 14,
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(tr('Сендер доссыңдар'),
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppColors.text3(d))),
                ),
              ),
            const SizedBox(height: 14),
          ],

          SqEqualRow(
            children: [
              Expanded(child: SqStat(
                icon: PhosphorIconsFill.lightning,
                tint: AppColors.amber,
                value: '${p?.xp ?? 0}',
                label: tr('Тәжірибе'))),
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
                  // Tappable, because a badge you cannot ask about is just
                  // an emoji. A tooltip needed a long press and only ever
                  // gave back the title.
                  for (final a in kAchievements)
                    if (unlocked.contains(a.code))
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => showAchievementSheet(
                            context, a, unlocked: true),
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
