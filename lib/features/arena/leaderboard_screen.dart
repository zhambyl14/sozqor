// lib/features/arena/leaderboard_screen.dart
//
// Global standings: weekly XP, all-time XP, battle rating, the arcade high
// score boards and today's global challenge.
//
// The top three get a podium — a rank is abstract, a podium is not — and
// everybody else lives in one dense table so scrolling to find yourself is
// quick. Your own row is tinted and never blends in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/repos/board_repo.dart';
import '../../data/repos/cosmetics_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../profile/worn_avatar.dart';

enum LeaderboardTab { week, allTime, elo, marathon, timeAttack, daily }

extension on LeaderboardTab {
  String get label => switch (this) {
    LeaderboardTab.week       => tr('Апта'),
    LeaderboardTab.allTime    => tr('Барлығы'),
    LeaderboardTab.elo        => tr('Рейтинг'),
    LeaderboardTab.marathon   => tr('Марафон'),
    LeaderboardTab.timeAttack => tr('Тайм-атака'),
    LeaderboardTab.daily      => tr('Бүгінгі'),
  };
  IconData get icon => switch (this) {
    LeaderboardTab.week       => PhosphorIconsFill.calendar,
    LeaderboardTab.allTime    => PhosphorIconsFill.star,
    LeaderboardTab.elo        => PhosphorIconsFill.sword,
    LeaderboardTab.marathon   => PhosphorIconsFill.heartbeat,
    LeaderboardTab.timeAttack => PhosphorIconsFill.timer,
    LeaderboardTab.daily      => PhosphorIconsFill.globeHemisphereEast,
  };
  String get unit => switch (this) {
    LeaderboardTab.elo => '',
    LeaderboardTab.marathon || LeaderboardTab.timeAttack => tr(' ұпай'),
    _ => tr(' тәжірибе'),
  };
}

final _tabProvider = StateProvider<LeaderboardTab>((_) => LeaderboardTab.week);

/// What everyone on the current board is wearing. Derived from the board
/// itself so it is one request per list rather than one per row, and so it
/// refetches exactly when the list it describes does.
final _wornProvider =
    FutureProvider.family<Map<String, WornCosmetics>, LeaderboardTab>(
        (ref, tab) async {
  final rows = await ref.watch(_boardProvider(tab).future);
  if (rows.isEmpty) return const {};
  return ref
      .watch(cosmeticsRepoProvider)
      .worn(rows.map((r) => r.userId).toList());
});

final _boardProvider =
    FutureProvider.family<List<BoardRow>, LeaderboardTab>((ref, tab) async {
  final repo = ref.watch(boardRepoProvider);
  return switch (tab) {
    LeaderboardTab.week       => repo.leaderboard(BoardScope.week),
    LeaderboardTab.allTime    => repo.leaderboard(BoardScope.all),
    LeaderboardTab.elo        => repo.leaderboard(BoardScope.elo),
    LeaderboardTab.marathon   => repo.gameBoard('marathon'),
    LeaderboardTab.timeAttack => repo.gameBoard('time_attack'),
    LeaderboardTab.daily      => repo.dailyBoard(
        ref.watch(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1'),
  };
});

class LeaderboardScreen extends ConsumerStatefulWidget {
  final LeaderboardTab initialTab;
  const LeaderboardScreen({super.key, this.initialTab = LeaderboardTab.week});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(_tabProvider.notifier).state = widget.initialTab;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final tab = ref.watch(_tabProvider);
    final async = ref.watch(_boardProvider(tab));
    // Cosmetics arrive a moment after the board itself; an empty map simply
    // renders the plain rows until they do.
    final worn = ref.watch(_wornProvider(tab)).valueOrNull
        ?? const <String, WornCosmetics>{};
    final uid = currentUid;
    final ownRow = async.valueOrNull?.where((r) => r.userId == uid).firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: SqHeader(
                title: tr('Рейтинг'),
                onBack: () => Navigator.of(context).pop(),
                actions: [
                  SqSquareButton(PhosphorIconsBold.shareNetwork,
                    onTap: ownRow == null ? null : () => Share.share(
                      trp('Мен SozQor лидерлер тізімінде {rank}-орындамын!',
                        {'rank': '${ownRow.rank}'}))),
                ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  for (final t in LeaderboardTab.values) ...[
                    SqChip(t.label,
                      icon: t.icon,
                      selected: t == tab,
                      outlined: true,
                      radius: 999,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 9),
                      onTap: () => ref.read(_tabProvider.notifier).state = t),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.card(d),
                onRefresh: () async {
                  ref.invalidate(_boardProvider(tab));
                  await Future<void>.delayed(const Duration(milliseconds: 350));
                },
                child: async.when(
                  loading: () => ListView(
                    padding: const EdgeInsets.all(18),
                    children: const [
                      SqShimmer(height: 130), SqShimmer(), SqShimmer(),
                      SqShimmer(), SqShimmer()]),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      SqEmpty(
                        icon: PhosphorIconsFill.warningCircle,
                        title: tr('Тізім жүктелмеді'),
                        subtitle: humanError(e),
                        tint: AppColors.red),
                    ]),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          SqEmpty(
                            icon: PhosphorIconsFill.ranking,
                            title: tr('Тізім әзірге бос'),
                            subtitle: tr('Бірінші болып орын ал!')),
                        ]);
                    }
                    final podium = rows.take(3).toList();
                    final rest = rows.skip(3).toList();
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
                      children: [
                        if (podium.length == 3) ...[
                          _Podium(rows: podium, unit: tab.unit),
                          const SizedBox(height: 18),
                        ],
                        SqGroup(children: [
                          for (final r in (podium.length == 3 ? rest : rows))
                            _BoardTile(
                              row: r,
                              isMe: r.userId == uid,
                              unit: tab.unit,
                              worn: worn[r.userId]),
                        ]),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  final List<BoardRow> rows;
  final String unit;
  const _Podium({required this.rows, required this.unit});

  @override
  Widget build(BuildContext context) {
    // Second, first, third — so the winner stands in the middle.
    final order = [rows[1], rows[0], rows[2]];
    const heights = [96.0, 122.0, 78.0];
    const tints = [
      Color(0xFF9FB0C4), AppColors.amber, Color(0xFFCD7F32)];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: _Step(
              row: order[i],
              height: heights[i],
              tint: tints[i],
              unit: unit),
          ),
          if (i != 2) const SizedBox(width: 9),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final BoardRow row;
  final double height;
  final Color tint;
  final String unit;

  const _Step({
    required this.row, required this.height,
    required this.tint, required this.unit});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SqAvatar(row.name, size: 42, tint: tint, solid: true),
        const SizedBox(height: 8),
        // Names are shown in full rather than clipped, so a long one takes a
        // second line; centred, that reads as a caption instead of a ragged
        // block under a centred avatar.
        Text(row.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800,
            color: AppColors.text(d))),
        const SizedBox(height: 8),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.card(d),
            border: Border(
              top: BorderSide(color: tint, width: 3),
              left: BorderSide(color: AppColors.border(d)),
              right: BorderSide(color: AppColors.border(d)),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SqNum('${row.rank}', size: 22, color: tint),
              const SizedBox(height: 3),
              SqNum('${row.value}$unit',
                size: 10.5, color: AppColors.text3(d)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoardTile extends StatelessWidget {
  final BoardRow row;
  final bool isMe;
  final String unit;

  /// What this person is wearing, when they have bought anything. A learner
  /// with nothing equipped renders exactly as they always did.
  final WornCosmetics? worn;

  const _BoardTile({
    required this.row,
    required this.isMe,
    required this.unit,
    this.worn,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final title = worn?.title;

    return SqTile(
      // Your own row still wins: the brand tint beats anybody's banner, so
      // "where am I" never gets harder to answer as more people buy one.
      fill: isMe
          ? AppColors.soft(AppColors.primary, d)
          : wornRowFill(worn, d),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 22,
            child: SqNum('${row.rank}',
              size: 13, color: AppColors.text4(d))),
          const SizedBox(width: 8),
          WornAvatar(name: row.name, worn: worn, size: 34, isMe: isMe),
        ],
      ),
      title: isMe ? trp('{name} (сен)', {'name': row.name}) : row.name,
      titleColor: isMe ? AppColors.primaryDeep : AppColors.text(d),
      subtitle: title == null ? row.cefrLevel : '${row.cefrLevel} · $title',
      trailing: SqNum('${row.value}$unit',
        size: 12.5,
        color: isMe ? AppColors.primaryDeep : AppColors.text2(d)),
    );
  }
}
