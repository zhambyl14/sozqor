// lib/features/profile/cosmetic_preview.dart
//
// How a cosmetic actually looks (EN-41 / EN-43 / KK-6).
//
// A frame was a hex colour drawn as a 2px ring and an aura was the same colour
// drawn as a box shadow. That is why the shop felt cheap: three thousand XP
// bought a slightly different border, and — worse — the only person who ever
// saw it was the person who bought it.
//
// There is no artist and no asset pipeline on this project, so everything here
// is drawn in Flutter from the item's own `data` payload. A gradient sweep, a
// rotating shimmer and a pulse are three genuinely different things you can
// see across a room, and none of them needs a file shipping with the app or a
// client release to add a new item.
//
// PERFORMANCE. These appear in lists. Every animated piece sits inside a
// RepaintBoundary, the controllers only run for items that actually animate,
// and a row that is not animating costs exactly what it did before — a
// shimmering frame on sixty shop rows at once is how you make a phone hot.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/cosmetics_repo.dart';

/// How a frame moves. Read from `data['fx']`, so a new item is a database row
/// rather than a client release.
enum FrameFx { none, sweep, shimmer, pulse }

FrameFx frameFxOf(Map<String, dynamic> data) =>
    switch ((data['fx'] ?? '').toString()) {
      'sweep'   => FrameFx.sweep,
      'shimmer' => FrameFx.shimmer,
      'pulse'   => FrameFx.pulse,
      _         => FrameFx.none,
    };

/// The second colour of a gradient frame, when the item names one.
Color? frameSecondOf(Map<String, dynamic> data) =>
    sqHexColor((data['color2'] ?? '').toString());

/// An avatar with everything the wearer owns on it: the frame and its motion,
/// the aura behind it, and the badge pinned to its corner.
///
/// One widget so the profile, the shop and the battle screen cannot drift into
/// three different ideas of what an item looks like — which is exactly how a
/// learner ends up buying something that looks different from its preview.
class CosmeticAvatar extends StatefulWidget {
  final String name;
  final String? emoji;
  final double size;

  /// Frame colour, its optional second colour, and its motion.
  final Color? frame;
  final Color? frameSecond;
  final FrameFx fx;

  /// Glow behind the avatar.
  final Color? aura;

  /// Pinned to the bottom-right.
  final String? badge;

  const CosmeticAvatar({
    super.key,
    required this.name,
    this.emoji,
    this.size = 78,
    this.frame,
    this.frameSecond,
    this.fx = FrameFx.none,
    this.aura,
    this.badge,
  });

  @override
  State<CosmeticAvatar> createState() => _CosmeticAvatarState();
}

class _CosmeticAvatarState extends State<CosmeticAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _animates => widget.fx != FrameFx.none && widget.frame != null;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CosmeticAvatar old) {
    super.didUpdateWidget(old);
    if (old.fx != widget.fx || old.frame != widget.frame) _sync();
  }

  /// A controller exists only while something is actually moving. Sixty shop
  /// rows each ticking a controller for a frame that does not animate is a
  /// warm phone and a flat battery for no visible gain.
  void _sync() {
    if (_animates && _c == null) {
      _c = AnimationController(
        vsync: this,
        duration: switch (widget.fx) {
          FrameFx.pulse => const Duration(milliseconds: 1800),
          _             => const Duration(milliseconds: 2600),
        },
      )..repeat();
    } else if (!_animates && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() { _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final s = widget.size;
    final ring = widget.frame;
    final inner = s - 10;

    Widget face = Container(
      width: inner, height: inner,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.card(d), width: 3)),
      alignment: Alignment.center,
      child: (widget.emoji ?? '').isEmpty
          ? SqNum(sqInitial(widget.name),
              size: s * 0.34, color: Colors.white)
          : Text(widget.emoji!, style: TextStyle(fontSize: s * 0.42)),
    );

    Widget stack = Container(
      width: s, height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring == null ? AppColors.muted(d) : null,
        boxShadow: widget.aura == null
            ? null
            : [BoxShadow(
                color: widget.aura!.withValues(alpha: 0.55),
                blurRadius: s * 0.34, spreadRadius: s * 0.05)],
      ),
      alignment: Alignment.center,
      child: face,
    );

    if (ring != null) {
      final second = widget.frameSecond ?? ring;
      final c = _c;
      stack = RepaintBoundary(
        child: c == null
            ? _ringed(stack, ring, second, 0, s)
            : AnimatedBuilder(
                animation: c,
                builder: (_, __) => _ringed(stack, ring, second, c.value, s),
              ),
      );
    }

    if (widget.badge == null) return stack;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        stack,
        Positioned(
          right: -2, bottom: 0,
          child: Container(
            width: s * 0.34, height: s * 0.34,
            decoration: BoxDecoration(
              color: AppColors.card(d),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border(d), width: 1.5)),
            alignment: Alignment.center,
            child: Text(widget.badge!,
              style: TextStyle(fontSize: s * 0.18, height: 1)),
          ),
        ),
      ],
    );
  }

  /// The ring itself. A sweep gradient rotated by `t` is what turns a flat
  /// border into something that reads as metal or light.
  Widget _ringed(Widget child, Color a, Color b, double t, double s) {
    final turn = t * 2 * math.pi;
    final width = widget.fx == FrameFx.none ? 3.0 : 4.0;

    return Container(
      width: s, height: s,
      padding: EdgeInsets.all(width),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: switch (widget.fx) {
          // A single bright arc travelling round a darker ring.
          FrameFx.shimmer => SweepGradient(
              startAngle: turn,
              endAngle: turn + 2 * math.pi,
              colors: [a, b, Colors.white, b, a],
              stops: const [0, 0.35, 0.5, 0.65, 1]),
          // Two colours turning into each other.
          FrameFx.sweep => SweepGradient(
              startAngle: turn,
              endAngle: turn + 2 * math.pi,
              colors: [a, b, a]),
          // Still, but breathing.
          FrameFx.pulse => SweepGradient(
              colors: [a, b, a],
              transform: GradientRotation(turn * 0.25)),
          FrameFx.none => LinearGradient(colors: [a, b]),
        },
        boxShadow: widget.fx == FrameFx.pulse
            ? [BoxShadow(
                color: a.withValues(
                  alpha: 0.25 + 0.3 * (0.5 + 0.5 * math.sin(turn))),
                blurRadius: 18, spreadRadius: 2)]
            : null,
      ),
      child: child,
    );
  }
}

/// A title, in the rarity's colour. Plain text was why a title bought for
/// coins looked the same as no title at all.
class CosmeticTitle extends StatelessWidget {
  final String title;
  final Color tint;
  final double size;
  const CosmeticTitle({
    super.key, required this.title, required this.tint, this.size = 12.5});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        tint.withValues(alpha: 0.22),
        tint.withValues(alpha: 0.06),
      ]),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tint.withValues(alpha: 0.45)),
    ),
    child: Text(title,
      style: TextStyle(
        fontSize: size, fontWeight: FontWeight.w800,
        letterSpacing: 0.1, color: tint)),
  );
}

/// The banner strip behind a profile hero.
class CosmeticBanner extends StatelessWidget {
  final Color colour;
  final double height;
  final BorderRadius radius;
  const CosmeticBanner({
    super.key,
    required this.colour,
    this.height = 46,
    this.radius = const BorderRadius.vertical(top: Radius.circular(23)),
  });

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [colour, colour.withValues(alpha: 0.25)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight),
      borderRadius: radius),
  );
}

/// One player's identity during a battle (EN-43 / KK-6).
///
/// Cosmetics are bought to be seen and the battle screen is the one place two
/// people look at each other, so everything a player is wearing goes here:
/// frame with its motion, aura, badge, title and rank. Before this the battle
/// showed a name and a number, and an opponent could not tell a learner who
/// had spent a thousand coins from one who had spent nothing.
class BattlePlayerCard extends StatelessWidget {
  final String name;
  final String? emoji;
  final WornCosmetics? worn;
  final int? elo;
  final String? rank;
  final bool isMe;
  final int score;

  const BattlePlayerCard({
    super.key,
    required this.name,
    required this.score,
    this.emoji,
    this.worn,
    this.elo,
    this.rank,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = worn;
    final frame = sqHexColor(w?.frameColor);
    final aura = sqHexColor(w?.auraColor);
    final title = w?.title;

    return Row(
      children: [
        CosmeticAvatar(
          name: name,
          emoji: emoji,
          size: 46,
          frame: frame,
          // The battle screen is dark and busy; a shimmering ring on both
          // players would compete with the question. The frame's colour and
          // its aura carry the identity here, its motion does not.
          fx: FrameFx.none,
          aura: aura,
          badge: w?.badge),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800,
                  color: isMe ? Colors.white : AppColors.onInk2)),
              if (title != null) ...[
                const SizedBox(height: 3),
                CosmeticTitle(
                  title: title,
                  tint: frame ?? AppColors.amber,
                  size: 10),
              ] else if (rank != null || elo != null) ...[
                const SizedBox(height: 2),
                Text(
                  rank ?? '$elo',
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.onInk3)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        SqNum('$score', size: 20, color: isMe ? Colors.white : AppColors.onInk2),
      ],
    );
  }
}
