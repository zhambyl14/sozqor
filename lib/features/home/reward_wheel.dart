// lib/features/home/reward_wheel.dart
//
// The fortune wheel and the reward table behind it (EN-8 / KK-1).
//
// The old chest offered three face-down cards, and the luck was fake: the
// payout was `base + cardIndex * 15`, so card three was strictly the best pick
// every non-golden day. Anybody who noticed had no reason to look at the other
// two again, and anybody who did not was choosing between three identical
// things while being told it was a choice.
//
// A wheel is honest about what it is. There is no decision to get wrong, the
// outcome is visibly random, and rarity gives the moment a range — most days
// are ordinary and occasionally one is not, which is the only thing that makes
// coming back for it worth anything.
//
// The reward is decided FIRST and the animation is aimed at it. Spinning and
// then reading off wherever the needle stopped would mean the prize depends on
// a frame rate, and a dropped frame would be a different reward.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../providers.dart';

enum RewardTier { common, rare, epic, legend }

extension RewardTierMeta on RewardTier {
  String get label => switch (this) {
    RewardTier.common => tr('Қарапайым'),
    RewardTier.rare   => tr('Сирек'),
    RewardTier.epic   => tr('Эпик'),
    RewardTier.legend => tr('Аңыз'),
  };

  Color get colour => switch (this) {
    RewardTier.common => AppColors.sky,
    RewardTier.rare   => AppColors.green,
    RewardTier.epic   => AppColors.primary,
    RewardTier.legend => AppColors.amber,
  };

  /// How long the reveal lingers. A legendary prize that flashes past at the
  /// same speed as fifteen coins is not a legendary prize.
  Duration get reveal => switch (this) {
    RewardTier.common => const Duration(milliseconds: 220),
    RewardTier.rare   => const Duration(milliseconds: 320),
    RewardTier.epic   => const Duration(milliseconds: 460),
    RewardTier.legend => const Duration(milliseconds: 620),
  };
}

/// One slice of the wheel, and one possible outcome.
class WheelSlice {
  final RewardTier tier;
  /// What it pays. Only one of these is ever non-zero except on the top tier.
  final int xp, coins, freezes, lives;
  /// A cosmetic id, granted server-side. Null on every tier the client can
  /// pay out by itself.
  final String? cosmeticId;
  final IconData icon;
  /// Relative chance. Not a percentage — the table is normalised at draw time
  /// so a slice can be added without rebalancing every other number.
  final int weight;

  const WheelSlice({
    required this.tier,
    required this.icon,
    required this.weight,
    this.xp = 0,
    this.coins = 0,
    this.freezes = 0,
    this.lives = 0,
    this.cosmeticId,
  });

  String get label {
    if (cosmeticId != null) return tr('Косметика');
    if (freezes > 0) return trp('{n} мұздатқыш', {'n': '$freezes'});
    if (lives > 0) return trp('{n} қосымша жан', {'n': '$lives'});
    if (coins > 0 && xp > 0) {
      return trp('{x} тәжірибе · {c} тиын', {'x': '$xp', 'c': '$coins'});
    }
    if (coins > 0) return trp('{n} тиын', {'n': '$coins'});
    return trp('{n} тәжірибе', {'n': '$xp'});
  }
}

/// The wheel, in the order the slices are drawn.
///
/// Alternating tiers on purpose: eight slices sorted by value would put every
/// good outcome on one side, and a wheel whose needle is drifting towards a
/// visibly empty half has already told you the answer.
const kWheel = <WheelSlice>[
  WheelSlice(tier: RewardTier.common, icon: PhosphorIconsFill.star,
      xp: 40, weight: 26),
  WheelSlice(tier: RewardTier.rare, icon: PhosphorIconsFill.snowflake,
      freezes: 1, weight: 12),
  WheelSlice(tier: RewardTier.common, icon: PhosphorIconsFill.coin,
      coins: 15, weight: 24),
  WheelSlice(tier: RewardTier.epic, icon: PhosphorIconsFill.sparkle,
      xp: 150, coins: 40, weight: 7),
  WheelSlice(tier: RewardTier.common, icon: PhosphorIconsFill.star,
      xp: 70, weight: 20),
  WheelSlice(tier: RewardTier.rare, icon: PhosphorIconsFill.heart,
      lives: 1, weight: 12),
  WheelSlice(tier: RewardTier.common, icon: PhosphorIconsFill.coin,
      coins: 30, weight: 18),
  WheelSlice(tier: RewardTier.legend, icon: PhosphorIconsFill.crown,
      xp: 300, coins: 120, weight: 3),
];

/// Picks a slice by weight, and lifts the odds on a streak.
///
/// [streak] is the chest streak: a learner on day 12 has earned a better wheel
/// than one opening their first, and without that the streak is a number that
/// counts nothing. It shifts weight from the common slices to the rare ones
/// rather than adding a new prize, so the wheel a learner sees is always the
/// wheel they are spinning.
WheelSlice pickSlice(math.Random rng, {int streak = 1}) {
  final boost = (streak.clamp(1, 30) - 1) / 29.0; // 0 on day one, 1 by day 30
  var total = 0.0;
  final weights = <double>[];
  for (final s in kWheel) {
    final w = switch (s.tier) {
      RewardTier.common => s.weight * (1 - 0.35 * boost),
      RewardTier.rare   => s.weight * (1 + 0.45 * boost),
      RewardTier.epic   => s.weight * (1 + 0.9 * boost),
      RewardTier.legend => s.weight * (1 + 1.6 * boost),
    };
    weights.add(w);
    total += w;
  }

  var roll = rng.nextDouble() * total;
  for (var i = 0; i < kWheel.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return kWheel[i];
  }
  return kWheel.first;
}

/// The wheel itself. Told which slice to land on, and spins to it.
class RewardWheel extends StatefulWidget {
  /// Index into [kWheel]. Decided before the spin starts, never after.
  final int? target;
  /// Fires once the needle has settled, so the caller reveals at the right
  /// moment rather than on a timer that can drift out of step with the curve.
  final VoidCallback onSettled;

  const RewardWheel({super.key, required this.target, required this.onSettled});

  @override
  State<RewardWheel> createState() => _RewardWheelState();
}

class _RewardWheelState extends State<RewardWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // Long enough to read as a spin, short enough that nobody stops opening
    // it. Anything past about three seconds and the wheel becomes a wait.
    duration: const Duration(milliseconds: 2600),
  )..addStatusListener((s) {
    if (s == AnimationStatus.completed) widget.onSettled();
  });

  late final Animation<double> _turn = CurvedAnimation(
    parent: _c,
    // Fast out, long slow settle — the shape of an actual wheel losing speed.
    curve: Curves.easeOutQuart,
  );

  double _endTurns = 0;
  /// Which slice the last tick sound was for, so the ticks follow the wheel
  /// rather than a fixed interval.
  int _lastTick = -1;

  @override
  void didUpdateWidget(RewardWheel old) {
    super.didUpdateWidget(old);
    if (widget.target != null && old.target == null) _spin(widget.target!);
  }

  void _spin(int index) {
    final slice = 1 / kWheel.length;
    // Land in the middle of the slice, after five full turns so the first
    // second is a blur and nobody can follow the needle to the answer.
    _endTurns = 5 + 1 - (index * slice + slice / 2);
    _c.forward(from: 0);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _turn,
      builder: (context, _) {
        final turns = _turn.value * _endTurns;
        final at = ((turns % 1) * kWheel.length).floor();
        if (at != _lastTick && _c.isAnimating) {
          _lastTick = at;
          HapticFeedback.selectionClick();
        }
        return SizedBox(
          width: 260, height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: turns * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(240, 240),
                  painter: _WheelPainter(),
                ),
              ),
              // The needle. Fixed at the top, pointing down into the wheel.
              Positioned(
                top: 0,
                child: Container(
                  width: 26, height: 30,
                  decoration: const BoxDecoration(color: Colors.transparent),
                  child: CustomPaint(painter: _NeedlePainter()),
                ),
              ),
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2)),
                alignment: Alignment.center,
                child: const Icon(PhosphorIconsFill.gift,
                  size: 24, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centre = Offset(r, r);
    final sweep = 2 * math.pi / kWheel.length;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < kWheel.length; i++) {
      final s = kWheel[i];
      // Slice 0 starts at the top, under the needle, so the landing maths and
      // the drawing agree about where "the middle of slice i" is.
      final start = -math.pi / 2 + i * sweep;
      paint.color = i.isEven
          ? s.tier.colour
          : Color.lerp(s.tier.colour, Colors.black, 0.18)!;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r), start, sweep, true, paint);

      // The icon, upright at the slice's midpoint.
      final mid = start + sweep / 2;
      final at = centre + Offset(math.cos(mid), math.sin(mid)) * (r * 0.66);
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(s.icon.codePoint),
          style: TextStyle(
            fontSize: 22,
            fontFamily: s.icon.fontFamily,
            package: s.icon.fontPackage,
            color: Colors.white.withValues(alpha: 0.95)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.drawCircle(centre, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = AppColors.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.ink);
    canvas.drawPath(path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
