// lib/features/profile/worn_avatar.dart
//
// One person, wearing what they bought.
//
// The shop sells six kinds of cosmetic and the server has always reported all
// six through `worn_cosmetics`. Only two of them — the frame ring and the
// title text — were ever drawn, and only on the leaderboard. So a learner
// could spend three thousand XP on a badge, an aura or a banner and then find
// there was no screen anywhere, their own profile included, that showed it.
// A cosmetic nobody can see is not a reward.
//
// This is the one place that turns a [WornCosmetics] into pixels, so a person
// looks the same on the leaderboard, in the friends list and on their own
// profile:
//
//   aura   → the light around the avatar
//   frame  → the ring on it
//   badge  → the small disc on its corner
//   banner → the tint of the row they sit in
//   title  → the line under their name
//
// Everything is optional and independent: a learner wearing nothing renders
// exactly as they always did.

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/cosmetics_repo.dart';

class WornAvatar extends StatelessWidget {
  final String name;

  /// Null while the cosmetics request is still in flight, which is why every
  /// piece below degrades to "not worn" rather than to a placeholder.
  final WornCosmetics? worn;

  final double size;

  /// The learner themselves — filled in the brand colour, as before.
  final bool isMe;

  /// An emoji avatar, when the person has one. Falls back to the initial.
  final String? emoji;

  const WornAvatar({
    super.key,
    required this.name,
    this.worn,
    this.size = 38,
    this.isMe = false,
    this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final frame = sqHexColor(worn?.frameColor);
    final aura = sqHexColor(worn?.auraColor);
    final badge = worn?.badge;

    // The ring eats 2 pt a side, so the face shrinks to keep the whole
    // assembly at [size] and rows stay the height they were.
    final face = frame == null ? size : size - 4;

    Widget avatar = (emoji ?? '').isEmpty
        ? SqAvatar(name, size: face, tint: isMe ? AppColors.primary : null,
            solid: isMe)
        : Container(
            width: face, height: face,
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.primary
                  : AppColors.muted(d),
              borderRadius: BorderRadius.circular(face * 0.34)),
            alignment: Alignment.center,
            child: Text(emoji!, style: TextStyle(fontSize: face * 0.52)),
          );

    if (frame != null) {
      avatar = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: frame, shape: BoxShape.circle),
        child: avatar,
      );
    }

    if (aura != null) {
      avatar = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: aura.withValues(alpha: 0.55),
              blurRadius: size * 0.32,
              spreadRadius: size * 0.05),
          ],
        ),
        child: avatar,
      );
    }

    if (badge == null) return SizedBox(width: size, height: size, child: avatar);

    // The badge sits half off the corner, so it never covers the face.
    final chip = size * 0.46;
    return SizedBox(
      width: size, height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -chip * 0.22,
            bottom: -chip * 0.14,
            child: Container(
              width: chip, height: chip,
              decoration: BoxDecoration(
                color: AppColors.card(d),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border(d))),
              alignment: Alignment.center,
              child: Text(badge,
                style: TextStyle(fontSize: chip * 0.58, height: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tint a worn banner gives the row its owner sits in.
///
/// Kept faint on purpose: a banner has to be recognisable without making the
/// name on top of it unreadable, and a list where several people wear one
/// must still read as a list rather than as a colour chart.
Color? wornRowFill(WornCosmetics? worn, bool dark) {
  final banner = sqHexColor(worn?.bannerColor);
  if (banner == null) return null;
  return banner.withValues(alpha: dark ? 0.16 : 0.10);
}
