// lib/features/profile/profile_screen.dart
//
// The "me" tab: identity, the four numbers worth showing, and the entrance to
// everything personal — achievements, shop, weekly report, friends and team.
//
// 4.0 drops the gradient hero. The avatar frame earned in the shop is what
// makes this screen personal now, not a background colour everybody shares.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/word.dart';
import '../../providers.dart';
import '../arena/clan_screen.dart';
import '../arena/leaderboard_screen.dart';
import '../auth/guest_gate.dart';
import 'achievements_screen.dart';
import 'friends_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static String frameName(String id) => switch (id) {
    'frame_gold'  => tr('Алтын жиек'),
    'frame_eagle' => tr('Қыран жиегі'),
    _             => tr('Қарапайым жиек'),
  };

  static Color frameColor(String id) => switch (id) {
    'frame_gold'  => AppColors.amber,
    'frame_eagle' => AppColors.green,
    _             => AppColors.primary,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final profile = ref.watch(myProfileProvider).value;
    final words = ref.watch(myWordsProvider).value ?? const <Word>[];
    final unlocked =
        ref.watch(unlockedAchievementsProvider).value ?? const <String>{};
    final spendable = ref.watch(spendableXpProvider);
    final frameColor = ref.watch(myFrameColorProvider);
    final title = ref.watch(myTitleProvider);
    final learned = words.where((w) => w.isLearned).length;

    Future<void> open(Widget screen) async {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen));
      if (context.mounted) refreshAll(ref);
    }

    return SqPage(
      onRefresh: () async {
        refreshAll(ref);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr('Мен'),
                style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800,
                  letterSpacing: -0.6, color: AppColors.text(d))),
            ),
            SqSquareButton(PhosphorIconsBold.gear,
              size: 40, onTap: () => open(const SettingsScreen())),
          ],
        ),
        const SizedBox(height: 16),

        const GuestBanner(feature: GuestFeature.friends),

        SqPanel(
          radius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  // The ring colour comes from the shop catalogue rather than
                  // a switch over known ids: the catalogue lives server-side
                  // so new frames ship without an app release, and a hardcoded
                  // list could never know about them.
                  color: frameColor ?? AppColors.muted(d),
                  shape: BoxShape.circle),
                child: Container(
                  width: 78, height: 78,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card(d), width: 3)),
                  alignment: Alignment.center,
                  child: (profile?.avatarEmoji ?? '').isEmpty
                      ? SqNum(sqInitial(profile?.name),
                          size: 30, color: Colors.white)
                      : Text(profile!.avatarEmoji,
                          style: const TextStyle(fontSize: 36)),
                ),
              ),
              const SizedBox(height: 14),
              Text(profile?.name ?? '…',
                style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800,
                  letterSpacing: -0.4, color: AppColors.text(d))),
              const SizedBox(height: 3),
              Text(
                profile?.isGuest ?? false
                    ? tr('Қонақ аккаунт')
                    : '@${profile?.username ?? ''}',
                style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7,
                alignment: WrapAlignment.center,
                children: [
                  // An earned title sits first: it is the one badge here the
                  // learner chose rather than was assigned.
                  if (title != null)
                    SqBadge(title, tint: AppColors.primary, solid: true),
                  SqBadge(profile?.cefrLevel ?? 'A1', tint: AppColors.sky),
                  SqBadge(tr(profile?.rankTitle ?? '—'), tint: AppColors.amber),
                ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  SqNum('LVL ${profile?.levelNumber ?? 1}',
                    size: 12, color: AppColors.text(d)),
                  const Spacer(),
                  Text(trp('келесі деңгейге {xp} XP',
                      {'xp': '${profile?.xpToNextLevel ?? 100}'}),
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.text3(d))),
                ],
              ),
              const SizedBox(height: 7),
              SqTrack(profile?.levelProgress ?? 0, height: 9),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SqStat(
              icon: PhosphorIconsFill.books, tint: AppColors.primary,
              value: '${profile?.wordsTotal ?? words.length}',
              label: tr('сөз'),
              onTap: () => goTab(ref, SqTab.words))),
            const SizedBox(width: 9),
            Expanded(child: SqStat(
              icon: PhosphorIconsFill.checkCircle, tint: AppColors.green,
              value: '$learned', label: tr('меңгерілді'))),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SqStat(
              icon: PhosphorIconsFill.fire, tint: AppColors.amber,
              value: '${profile?.streak ?? 0}', label: tr('күндік серия'))),
            const SizedBox(width: 9),
            Expanded(child: SqStat(
              icon: PhosphorIconsFill.sword, tint: AppColors.red,
              value: '${profile?.battlesWon ?? 0}', label: tr('жеңіс'),
              onTap: () => goTab(ref, SqTab.arena))),
          ],
        ),
        const SizedBox(height: 20),

        SqGroup(children: [
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.sealCheck,
              tint: AppColors.amber, size: 38),
            title: tr('Жетістіктер'),
            subtitle: trp('{n} / {total} ашылды', {
              'n': '${unlocked.length}',
              'total': '${kAchievements.length}',
            }),
            chevron: true,
            onTap: () => open(const AchievementsScreen())),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.storefront, size: 38),
            title: tr('Дүкен'),
            subtitle: tr('Жиек, тақырып, мұздатқыш'),
            trailing: SqBadge('$spendable XP',
              tint: AppColors.amber, numeric: true),
            onTap: () => open(const ShopScreen())),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.chartLineUp,
              tint: AppColors.green, size: 38),
            title: tr('Апталық есеп'),
            subtitle: tr('Күндер, тақырыптар, серпін'),
            onTap: () => open(const ReportScreen())),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.usersThree,
              tint: AppColors.sky, size: 38),
            title: tr('Достар'),
            subtitle: tr('Дос қос, баттлға шақыр'),
            chevron: true,
            onTap: () async {
              if (!await requireAccount(context, ref, GuestFeature.friends)) {
                return;
              }
              if (!context.mounted) return;
              await open(const FriendsScreen());
            }),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.flagBanner,
              tint: AppColors.sky, size: 38),
            title: tr('Менің командам'),
            subtitle: tr('Апталық команда жарысы'),
            chevron: true,
            onTap: () => open(const ClanScreen())),
          SqTile(
            leading: const SqTintBox(PhosphorIconsFill.ranking,
              tint: AppColors.amber, size: 38),
            title: tr('Әлемдік рейтинг'),
            subtitle: tr('Апта, барлық уақыт, Elo'),
            chevron: true,
            onTap: () => open(const LeaderboardScreen())),
          SqTile(
            leading: SqTintBox(PhosphorIconsFill.shareNetwork,
              tint: AppColors.text3(d), size: 38),
            title: tr('Достарыңа ұсын'),
            subtitle: tr('SozQor туралы айт'),
            onTap: () => Share.share(
              trp('Мен SozQor-да ағылшын сөздерін ойнап үйреніп жүрмін — '
                  '{n} сөз, {day} күндік серия. Сен де қосыл!', {
                'n': '${profile?.wordsTotal ?? 0}',
                'day': '${profile?.streak ?? 0}',
              }))),
        ]),
      ],
    );
  }
}
