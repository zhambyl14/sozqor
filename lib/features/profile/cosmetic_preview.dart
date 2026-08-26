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

  /// Freezes the effect at one frame of its cycle.
  ///
  /// A moving ring is worth a ticker on a profile, where there is one of
  /// them. In a list it is a repaint every frame under a RepaintBoundary,
  /// which is the boundary doing work instead of saving it — and the gradient
  /// reads as metal standing still just as well as turning.
  final bool still;

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
    this.still = false,
  });

  @override
  State<CosmeticAvatar> createState() => _CosmeticAvatarState();
}

class _CosmeticAvatarState extends State<CosmeticAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _animates =>
      !widget.still && widget.fx != FrameFx.none && widget.frame != null;

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
            ? _ringed(stack, ring, second, 0.18, s)
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
        // The glow is the expensive part — a blur is its own draw pass — and
        // a still frame in a list does not need one.
        boxShadow: widget.fx == FrameFx.pulse && !widget.still
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

// ═══════════════════════════════════════════════════════════
// Who is wearing it
// ═══════════════════════════════════════════════════════════

/// Everything one person is wearing, resolved to colours.
///
/// [WornCosmetics] carries what the server reports — colours, an emoji, a
/// title — but not the `data` payload that says how a frame *moves*: the RPC
/// that reads other people only returns rendered fields. The catalogue is on
/// the device anyway, so the motion is looked up by frame id here rather than
/// widening the request.
class WearerLook {
  final String name;
  final String? emoji;
  final Color? frame, frameSecond, aura, banner;
  final FrameFx fx;
  final String? badge, title;

  const WearerLook({
    required this.name,
    this.emoji,
    this.frame,
    this.frameSecond,
    this.aura,
    this.banner,
    this.fx = FrameFx.none,
    this.badge,
    this.title,
  });

  factory WearerLook.from({
    required String name,
    String? emoji,
    WornCosmetics? worn,
    Map<String, dynamic>? frameData,
  }) => WearerLook(
    name: name,
    emoji: emoji,
    frame: sqHexColor(worn?.frameColor),
    frameSecond: frameData == null ? null : frameSecondOf(frameData),
    fx: frameData == null ? FrameFx.none : frameFxOf(frameData),
    aura: sqHexColor(worn?.auraColor),
    banner: sqHexColor(worn?.bannerColor),
    badge: worn?.badge,
    title: worn?.title,
  );

  /// The colour this person is written in — their title, the band behind
  /// their head. The frame leads because it is the piece seen first.
  Color get tint => frame ?? aura ?? banner ?? AppColors.primary;

  bool get wearsSomething =>
      frame != null || aura != null || banner != null ||
      badge != null || title != null;
}

/// The `data` payload of the frame somebody is wearing, found in the
/// catalogue by id. Null when they wear none or the catalogue has not arrived
/// yet — both of which simply mean "a still ring".
Map<String, dynamic>? frameDataOf(String? frameId, List<Cosmetic> catalogue) {
  if (frameId == null || frameId.isEmpty) return null;
  for (final c in catalogue) {
    if (c.id == frameId) return c.data;
  }
  return null;
}

/// One catalogue item, drawn the way it will actually look on the person
/// looking at it.
///
/// The shop used to draw its own flat swatch — a 3-pt ring, a stripe, a disc —
/// while the profile drew the rich version, so the thing you bought never
/// looked like the thing you tapped. Everything here goes through the same
/// widgets the profile uses, on top of what the learner is already wearing:
/// a frame arrives around *their* avatar, an aura lights *their* face, a
/// title is written in *their* frame's colour. Trying it on is the whole
/// argument for buying it.
class CosmeticShowcase extends StatelessWidget {
  final Cosmetic item;
  final WearerLook wearer;
  final double size;

  const CosmeticShowcase({
    super.key,
    required this.item,
    required this.wearer,
    this.size = 76,
  });

  /// The learner's own avatar with one piece swapped for the item on sale.
  /// Their frame is drawn still even when it animates: on a shelf of sixty
  /// cards the one thing moving should be the thing being sold.
  Widget _worn({
    required double size,
    Color? aura,
    String? badge,
    String? emoji,
  }) => CosmeticAvatar(
    name: wearer.name,
    emoji: emoji ?? wearer.emoji,
    size: size,
    frame: wearer.frame,
    frameSecond: wearer.frameSecond,
    fx: FrameFx.none,
    aura: aura ?? wearer.aura,
    badge: badge ?? wearer.badge);

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final colour = sqHexColor(item.color);

    switch (item.kind) {
      case CosmeticKind.frame:
        return CosmeticAvatar(
          name: wearer.name,
          emoji: wearer.emoji,
          size: size,
          frame: colour ?? AppColors.muted(d),
          frameSecond: frameSecondOf(item.data),
          fx: frameFxOf(item.data),
          aura: wearer.aura);

      case CosmeticKind.aura:
        return _worn(size: size * 0.88, aura: colour);

      case CosmeticKind.badge:
        return _worn(size: size * 0.88, badge: item.emoji ?? '•');

      case CosmeticKind.avatar:
        return _worn(size: size * 0.9, emoji: item.emoji ?? '🙂');

      case CosmeticKind.title:
        // A title is text, and text is what it will be. Left to wrap: a card
        // grows before a name is ever cut in half.
        return CosmeticTitle(title: item.name, tint: wearer.tint);

      case CosmeticKind.banner:
        // The same shape the profile hero has — a strip with a head on it —
        // so the preview and the profile are recognisably one thing.
        final face = size * 0.46;
        final strip = size * 0.62;
        return SizedBox(
          width: double.infinity,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0, left: 0, right: 0,
                child: CosmeticBanner(
                  colour: colour ?? AppColors.muted(d),
                  height: strip,
                  radius: BorderRadius.circular(14))),
              Positioned(
                top: strip - face / 2, left: 0, right: 0,
                child: Center(child: _worn(size: face))),
            ],
          ),
        );
    }
  }
}

/// A person wearing everything they own — the block both profiles open with.
///
/// This is what the shop is for. A cosmetic bought with coins has to be the
/// first thing anybody sees, on your own page and on the one a stranger opens
/// from a leaderboard, so both screens draw this same hero: the banner as the
/// band behind the head, the avatar inside its frame with the frame's real
/// motion, the aura burning behind it, the badge on its corner and the title
/// under the name in the frame's colour.
///
/// Dark on purpose. Gold, ember and violet rings read as light against ink
/// and as stickers against white, and this block is the one moment on the
/// page allowed to win the eye.
class CosmeticHero extends StatelessWidget {
  final WearerLook look;

  /// `@username`, or whatever line belongs under the name.
  final String? handle;

  /// Level, rank, CEFR — whatever the screen wants beside the title.
  final List<Widget> chips;

  /// Anything the screen adds below the identity, e.g. the level track.
  final Widget? child;

  final double avatarSize;

  const CosmeticHero({
    super.key,
    required this.look,
    this.handle,
    this.chips = const [],
    this.child,
    this.avatarSize = 96,
  });

  static const double _band = 84;

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inkBlock(d),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(
          color: AppColors.ink.withValues(alpha: d ? 0.55 : 0.30),
          blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          children: [
            SizedBox(
              // The band, plus the half of the head that hangs off it. Fixed
              // rather than stacked with negative offsets so the aura's glow
              // has room to bleed instead of being sliced off.
              height: _band + avatarSize / 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(top: 0, left: 0, right: 0, child: _bandFill()),
                  Positioned(
                    top: _band - avatarSize / 2, left: 0, right: 0,
                    child: Center(
                      child: CosmeticAvatar(
                        name: look.name,
                        emoji: look.emoji,
                        size: avatarSize,
                        frame: look.frame,
                        frameSecond: look.frameSecond,
                        fx: look.fx,
                        aura: look.aura,
                        badge: look.badge),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(look.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21, height: 1.25, fontWeight: FontWeight.w800,
                      letterSpacing: -0.4, color: Colors.white)),
                  if (handle != null) ...[
                    const SizedBox(height: 3),
                    Text(handle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5, height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onInk3)),
                  ],
                  if (look.title != null) ...[
                    const SizedBox(height: 9),
                    // In the frame's colour: the two pieces were bought to be
                    // worn together, and a title in the app's violet looked
                    // like something the app handed out.
                    CosmeticTitle(title: look.title!, tint: look.tint, size: 13),
                  ],
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 7, runSpacing: 7,
                      alignment: WrapAlignment.center,
                      children: chips),
                  ],
                  if (child != null) ...[
                    const SizedBox(height: 16),
                    child!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The banner is exactly what a banner is for: the strip a name sits on.
  /// Without one the band takes the frame's colour, so even a hero with one
  /// cosmetic belongs to its owner rather than to the app's violet.
  Widget _bandFill() => look.banner != null
      ? CosmeticBanner(
          colour: look.banner!, height: _band, radius: BorderRadius.zero)
      : Container(
          height: _band,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                look.tint.withValues(alpha: 0.50),
                look.tint.withValues(alpha: 0.05),
              ]),
          ),
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
