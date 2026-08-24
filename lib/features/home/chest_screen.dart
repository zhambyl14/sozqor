// lib/features/home/chest_screen.dart
//
// The daily chest, as a fortune wheel (EN-8 / KK-1).
//
// 4.0 offered three face-down cards and called the pick "luck". It was not:
// the payout was `base + cardIndex * 15`, so the third card was strictly the
// best choice every non-golden day. Anybody who noticed stopped looking at the
// other two, and anybody who did not was picking between three identical
// things while being told it was a decision.
//
// The wheel removes the false choice and puts a real range in its place. Most
// days pay something ordinary; occasionally one does not. The streak lifts the
// odds rather than the flat amount, so the run is worth keeping for a reason
// the learner can feel rather than one they have to be told.
//
// The reward table and the spin live in reward_wheel.dart; this screen is the
// ceremony around them.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'reward_wheel.dart';

class ChestScreen extends ConsumerStatefulWidget {
  const ChestScreen({super.key});

  @override
  ConsumerState<ChestScreen> createState() => _ChestScreenState();
}

class _ChestScreenState extends ConsumerState<ChestScreen> {
  /// Chosen before the wheel starts turning, never read off where it stopped —
  /// otherwise the prize would depend on the frame rate and a dropped frame
  /// would be a different reward.
  int? _target;
  WheelSlice? _won;
  bool _busy = false;
  bool _settled = false;

  Future<void> _spin() async {
    if (_busy || _target != null) return;
    final meta = ref.read(metaProvider);
    if (!meta.chestReady) return;

    setState(() => _busy = true);
    HapticFeedback.mediumImpact();

    final slice = pickSlice(math.Random(), streak: meta.nextChestStreak);
    setState(() {
      _won = slice;
      _target = kWheel.indexOf(slice);
    });
  }

  /// Runs once the needle has stopped. Everything is banked here rather than
  /// at spin time so the numbers on the profile move at the same moment the
  /// learner sees what they won.
  Future<void> _settle() async {
    final slice = _won;
    if (slice == null || _settled) return;
    _settled = true;

    try {
      final banked = await ref.read(metaProvider.notifier).bankChest(
        freezes: slice.freezes, lives: slice.lives);
      // Already opened today — another device got there first. Nothing is
      // awarded twice.
      if (!banked) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      // XP and coins are server-side: add_xp already grants a tenth of the XP
      // in coins, so a slice that pays both asks for the XP that produces the
      // coins it promises rather than trying to write coins from the device,
      // which profiles_guard would revert anyway.
      final xp = slice.xp + slice.coins * 10;
      if (xp > 0) {
        await ref.read(profileRepoProvider)
            .addXp(xp, 'daily_chest')
            .catchError((_) => 0);
        ref.invalidate(myProfileProvider);
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final meta = ref.watch(metaProvider);
    final ready = meta.chestReady;
    final streak = meta.chestStreak;
    final won = _won;
    final revealed = won != null && _settled;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Сыйлық сандығы'),
          eyebrow: tr('Күнделікті'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 10),

        if (streak > 0)
          Center(
            child: SqChip(
              trp('{n} күндік сандық сериясы', {'n': '$streak'}),
              icon: PhosphorIconsFill.fire,
              tint: AppColors.amber,
              radius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          ),
        const SizedBox(height: 14),

        Center(
          child: RewardWheel(target: _target, onSettled: _settle),
        ),
        const SizedBox(height: 18),

        if (revealed)
          _Prize(slice: won)
        else if (!ready)
          SqPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Icon(PhosphorIconsFill.clock,
                  size: 26, color: AppColors.text3(d)),
                const SizedBox(height: 10),
                Text(tr('Бүгінгі сандық ашылған'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
                const SizedBox(height: 4),
                Text(tr('Ертең тағы бір айналдырасың'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: AppColors.text3(d))),
              ],
            ),
          )
        else
          SqAction(tr('Айналдыру'),
            icon: PhosphorIconsFill.gift,
            height: 56,
            busy: _busy && !revealed,
            onTap: _busy ? null : _spin),

        const SizedBox(height: 18),

        // What is actually on the wheel. A prize table nobody can read is a
        // prize table nobody trusts, and "what could I have won" is the first
        // question a wheel provokes.
        SqSection(tr('Сандықта не бар')),
        SqGroup(children: [
          for (final tier in RewardTier.values)
            SqTile(
              leading: SqTintBox(
                switch (tier) {
                  RewardTier.common => PhosphorIconsFill.star,
                  RewardTier.rare   => PhosphorIconsFill.snowflake,
                  RewardTier.epic   => PhosphorIconsFill.sparkle,
                  RewardTier.legend => PhosphorIconsFill.crown,
                },
                tint: tier.colour, size: 34),
              title: tier.label,
              subtitle: kWheel
                  .where((s) => s.tier == tier)
                  .map((s) => s.label)
                  .join(' · '),
            ),
        ]),
      ],
    );
  }
}

/// The reveal. Sized and coloured by rarity, because a legendary prize shown
/// exactly like fifteen coins is not a legendary prize.
class _Prize extends StatelessWidget {
  final WheelSlice slice;
  const _Prize({required this.slice});

  @override
  Widget build(BuildContext context) {
    final tint = slice.tier.colour;
    final big = slice.tier == RewardTier.epic ||
        slice.tier == RewardTier.legend;

    return SqRise(
      child: SqInkCard(
        radius: 24,
        padding: EdgeInsets.symmetric(vertical: big ? 26 : 20, horizontal: 20),
        glow: tint,
        glowAt: Alignment.topRight,
        child: Column(
          children: [
            SqFloat(
              child: Container(
                width: big ? 72 : 60, height: big ? 72 : 60,
                decoration: BoxDecoration(
                  color: tint, borderRadius: BorderRadius.circular(22)),
                child: Icon(slice.icon,
                  size: big ? 36 : 30, color: Colors.white),
              ),
            ),
            const SizedBox(height: 14),
            SqChip(slice.tier.label,
              tint: tint,
              radius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5)),
            const SizedBox(height: 10),
            Text(slice.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: big ? 24 : 20, fontWeight: FontWeight.w800,
                letterSpacing: -0.4, color: Colors.white)),
            const SizedBox(height: 4),
            Text(tr('Есепшотыңа қосылды'),
              style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.onInk2)),
          ],
        ),
      ),
    );
  }
}
