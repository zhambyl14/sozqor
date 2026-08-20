// lib/features/arena/clan_screen.dart
//
// The team race.
//
// A league ranks you against strangers; this ranks you *with* people you know.
// Your team is simply you plus everyone you have added as a friend, and the
// week's XP is pooled against a shared goal. There is no clan table on the
// server — the standing is assembled from the same friends RPC the rest of the
// app uses, which is why a team can exist the moment you add one person.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../profile/friends_screen.dart';

class ClanScreen extends ConsumerWidget {
  const ClanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(teamProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(teamProvider);
        ref.invalidate(friendsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Менің командам'),
          eyebrow: tr('Жаңа · команда'),
          onBack: () => Navigator.of(context).pop(),
          actions: const [
            SqTintBox(PhosphorIconsFill.flagBanner,
              tint: AppColors.sky, size: 40, solid: true),
          ],
        ),
        const SizedBox(height: 16),

        async.when(
          loading: () => const Column(children: [
            SqShimmer(height: 150), SqShimmer(), SqShimmer()]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Команда жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (team) {
            if (team.size <= 1) {
              return SqEmpty(
                icon: PhosphorIconsFill.usersThree,
                title: tr('Командаң әлі бос'),
                subtitle: tr('Дос қосқан бойда команда құрылады.'),
                tint: AppColors.sky,
                action: SizedBox(
                  width: 240,
                  child: SqAction(tr('Дос қосу'),
                    icon: PhosphorIconsBold.userPlus,
                    tone: SqTone.sky,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const FriendsScreen()))),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SqPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('Апталық команда жарысы'),
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: AppColors.text(d))),
                          const Spacer(),
                          SqBadge(_untilSunday(),
                            tint: AppColors.red, numeric: true),
                        ],
                      ),
                      const SizedBox(height: 15),
                      _Bar(
                        label: tr('Біздің команда'),
                        value: team.total,
                        ratio: team.progress,
                        tint: AppColors.sky,
                        icon: PhosphorIconsFill.flagBanner,
                        strong: true),
                      const SizedBox(height: 12),
                      _Bar(
                        label: tr('Апталық мақсат'),
                        value: team.goal,
                        ratio: 1,
                        tint: AppColors.text4(d),
                        icon: PhosphorIconsFill.target,
                        strong: false),
                      const SizedBox(height: 13),
                      Text(
                        team.progress >= 1
                            ? trp('Мақсат орындалды! Келесі белес — {n} XP.',
                                {'n': '${team.goal + 1000}'})
                            : trp('Мақсатқа {n} XP қалды.',
                                {'n': '${team.goal - team.total}'}),
                        style: TextStyle(
                          fontSize: 11.5, height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text3(d))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                SqSection(tr('Мүшелер үлесі'),
                  trailingWidget: SqNum('${team.size}',
                    size: 11, color: AppColors.text3(d))),
                SqGroup(children: [
                  for (final m in team.members.take(12))
                    SqTile(
                      leading: SqAvatar(m.name,
                        size: 34,
                        tint: m.isMe ? AppColors.primary : AppColors.sky,
                        solid: m.isMe),
                      title: m.isMe
                          ? trp('{name} (сен)', {'name': m.name}) : m.name,
                      titleColor: m.isMe
                          ? AppColors.primaryDeep : AppColors.text(d),
                      below: SqTrack(team.shareOf(m),
                        color: m.isMe ? AppColors.primary : AppColors.sky,
                        height: 5),
                      trailing: SqNum('${m.xp}',
                        size: 12, color: AppColors.text2(d)),
                    ),
                ]),
                const SizedBox(height: 18),

                SqAction(tr('Достарды көру'),
                  icon: PhosphorIconsFill.usersThree,
                  tone: SqTone.sky,
                  height: 52,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FriendsScreen()))),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The weekly race resets on Monday, same as the league.
  static String _untilSunday() {
    final now = DateTime.now();
    final days = 8 - now.weekday;
    final hours = 24 - now.hour;
    return days >= 7
        ? trp('{h} сағ', {'h': '$hours'})
        : trp('{d} күн {h} сағ', {'d': '$days', 'h': '$hours'});
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final int value;
  final double ratio;
  final Color tint;
  final IconData icon;
  final bool strong;

  const _Bar({
    required this.label, required this.value, required this.ratio,
    required this.tint, required this.icon, required this.strong});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Row(
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: strong ? tint : AppColors.muted(d),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon,
            size: 15, color: strong ? Colors.white : AppColors.text3(d)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(label,
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: strong
                          ? AppColors.text(d) : AppColors.text2(d))),
                  const Spacer(),
                  SqNum('$value',
                    size: 12,
                    color: strong ? tint : AppColors.text3(d)),
                ],
              ),
              const SizedBox(height: 5),
              SqTrack(ratio, color: tint, height: 9),
            ],
          ),
        ),
      ],
    );
  }
}
