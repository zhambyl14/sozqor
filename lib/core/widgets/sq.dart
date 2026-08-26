// lib/core/widgets/sq.dart
//
// The SozQor 4.0 component kit.
//
// Everything on a 4.0 screen is assembled from the pieces in this file, which
// is what keeps twenty-seven screens looking like one product. The rules the
// kit encodes:
//
//   • A page is quiet. One dark [SqInkCard] per screen carries the focus
//     moment; everything else is a white [SqPanel] or [SqGroup].
//   • Anything you can press is physical: it sits on a solid 4-pixel lip and
//     the lip collapses under the finger ([SqLip]).
//   • Numbers are never prose. Scores, timers, ranks and the little uppercase
//     captions all go through [SqNum] / [SqEyebrow] in Space Grotesk.
//   • Icons are Phosphor at one weight per role — fill inside tinted boxes,
//     bold for outlines and chevrons. No emoji in chrome.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../i18n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// True when the app is showing its dark palette.
bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// The single letter shown inside an avatar circle.
///
/// A profile row can legitimately carry an empty name — a guest session before
/// onboarding has written one — and `''.characters.first` throws, which used to
/// take the whole screen down with it. Never returns an empty string.
String sqInitial(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return 'S';
  return trimmed.characters.first.toUpperCase();
}

/// Parses a `#RRGGBB` colour out of shop data.
///
/// Cosmetic colours are stored in the database rather than in the app, so a
/// new frame can be added without a release — which also means the value
/// arrives as untrusted text and must never throw on a typo.
Color? sqHexColor(String? hex) {
  final raw = (hex ?? '').trim().replaceFirst('#', '');
  if (raw.length != 6) return null;
  final value = int.tryParse(raw, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

// ═══════════════════════════════════════════════════════════
// Type
// ═══════════════════════════════════════════════════════════

/// The small uppercase caption that sits above a screen or section title.
class SqEyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  final double size;
  const SqEyebrow(this.text, {super.key, this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: AppTheme.mono(
      size: size,
      weight: FontWeight.w700,
      letterSpacing: size * 0.012 + 0.1,
      color: color ?? AppColors.eyebrow(isDark(context)),
    ),
  );
}

/// Space Grotesk numerals — scores, timers, XP, ranks.
class SqNum extends StatelessWidget {
  final String value;
  final double size;
  final Color? color;
  final FontWeight weight;
  final double? letterSpacing, height;

  const SqNum(
    this.value, {
    super.key,
    this.size = 14,
    this.color,
    this.weight = FontWeight.w700,
    this.letterSpacing,
    this.height,
  });

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: AppTheme.mono(
      size: size,
      weight: weight,
      color: color ?? AppColors.text(isDark(context)),
      letterSpacing: letterSpacing,
      height: height,
    ),
  );
}

/// A section title with an optional trailing action.
class SqSection extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;
  final Widget? trailingWidget;

  const SqSection(
    this.title, {
    super.key,
    this.trailing,
    this.onTrailing,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 11),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800,
                letterSpacing: -0.2, color: AppColors.text(d))),
          ),
          if (trailingWidget != null) trailingWidget!,
          if (trailing != null)
            GestureDetector(
              onTap: onTrailing,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(trailing!,
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep)),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Press physics
// ═══════════════════════════════════════════════════════════

/// A surface that sits on a solid lip and tucks into it when pressed.
///
/// This is the single interaction primitive of 4.0 — buttons, answer tiles,
/// nav pills and reward cards are all an [SqLip] with different fills.
class SqLip extends StatefulWidget {
  final Widget child;
  final Color fill;
  final Color? lip;
  final Color? border;
  final double borderWidth;
  final double radius;
  final double depth;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool haptic;
  final List<BoxShadow>? glow;

  const SqLip({
    super.key,
    required this.child,
    required this.fill,
    this.lip,
    this.border,
    this.borderWidth = 1,
    this.radius = 16,
    this.depth = 4,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.haptic = true,
    this.glow,
  });

  @override
  State<SqLip> createState() => _SqLipState();
}

class _SqLipState extends State<SqLip> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.onTap != null;
    final lip = widget.lip;
    final depth = lip == null ? 0.0 : widget.depth;
    final sunk = live && _down;
    final drop = sunk ? depth * 0.75 : 0.0;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.fill,
        borderRadius: BorderRadius.circular(widget.radius),
        border: widget.border == null
            ? null
            : Border.all(color: widget.border!, width: widget.borderWidth),
        boxShadow: [
          if (lip != null)
            BoxShadow(
              color: lip,
              offset: Offset(0, depth - drop),
              blurRadius: 0),
          if (widget.glow != null && !sunk) ...widget.glow!,
        ],
      ),
      child: widget.child,
    );

    if (!live) {
      return Padding(
        padding: EdgeInsets.only(bottom: depth),
        child: body,
      );
    }

    // The lip stays put while the face slides down into it, so the element's
    // outer bounds never move and nothing around it reflows on a press.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: depth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, drop, 0),
          child: body,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Buttons
// ═══════════════════════════════════════════════════════════

enum SqTone { primary, ink, danger, amber, sky, green, ghost, softPrimary }

/// The full-width action button. One per screen should be [SqTone.primary]
/// or [SqTone.ink]; everything else is [SqTone.ghost].
class SqAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final SqTone tone;
  final double height;
  final bool busy;
  final bool expand;

  const SqAction(
    this.label, {
    super.key,
    this.icon,
    this.trailingIcon,
    this.onTap,
    this.tone = SqTone.primary,
    this.height = 54,
    this.busy = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final live = onTap != null && !busy;

    late final Color fill, ink;
    Color? lip, border;

    switch (tone) {
      case SqTone.primary:
        fill = AppColors.primary; lip = AppColors.primaryDeep; ink = Colors.white;
      case SqTone.ink:
        fill = AppColors.inkBlock(d);
        lip = AppColors.inkBlockLip(d);
        ink = Colors.white;
      case SqTone.danger:
        fill = AppColors.red; lip = AppColors.redDeep; ink = Colors.white;
      case SqTone.amber:
        fill = AppColors.amber; lip = AppColors.amberDeep;
        ink = d ? Colors.white : AppColors.ink;
      case SqTone.sky:
        fill = AppColors.sky; lip = AppColors.skyDeep; ink = Colors.white;
      case SqTone.green:
        fill = AppColors.green; lip = AppColors.greenDeep; ink = Colors.white;
      case SqTone.softPrimary:
        fill = AppColors.soft(AppColors.primary, d);
        lip = null; border = AppColors.line(AppColors.primary, d);
        ink = AppColors.onSoft(AppColors.primary, d);
      case SqTone.ghost:
        // The lip and the border used to be 0xFFEDEAF6 / 0xFFE7E4F3, both a
        // hair off white — so in light mode the whole button was a white
        // rectangle on a 0xFFF7F6FB page and read as a line of text rather
        // than as something to press.
        fill = AppColors.card(d);
        lip = AppColors.surfaceLip(d);
        border = AppColors.border(d);
        ink = AppColors.text2(d);
    }

    // A hard SizedBox(height:) with maxLines: 1 meant a label that did not fit
    // was cut and given an ellipsis — read as "the button only shows half its
    // text". Kazakh and Russian labels run considerably longer than the
    // English ones the 54pt default was chosen against, and the system text
    // scale can push any of them over.
    //
    // A minimum height instead of a fixed one keeps every short label exactly
    // where it was, and lets a long one take a second line and grow the button
    // rather than lose its words.
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: busy
            ? [
                SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(ink))),
              ]
            : [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: ink),
                  const SizedBox(width: 9),
                ],
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        letterSpacing: -0.2, height: 1.2, color: ink)),
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 9),
                  Icon(trailingIcon, size: 16, color: ink),
                ],
              ],
      ),
    );

    return Opacity(
      opacity: live || busy ? 1 : 0.45,
      child: SqLip(
        fill: fill,
        lip: lip,
        border: border,
        borderWidth: tone == SqTone.ghost ? 1.5 : 1,
        radius: 17,
        depth: tone == SqTone.ghost ? 3 : 4,
        onTap: live ? onTap : null,
        haptic: true,
        child: content,
      ),
    );
  }
}

/// The rounded-square icon button used in headers: back, close, bell, gear.
class SqSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? fill, iconColor, lip, border;
  final bool onInk;
  final Widget? badge;

  const SqSquareButton(
    this.icon, {
    super.key,
    this.onTap,
    this.size = 38,
    this.fill,
    this.iconColor,
    this.lip,
    this.border,
    this.onInk = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    // A default-filled square is a surface button — back, gear, bell — and
    // gets the surface lip so it is visibly pressable. One built with its own
    // [fill] is already carrying a tint of its own and is left alone: a
    // neutral violet edge under a red or green square would fight it.
    final edge = lip ?? (onInk || fill != null ? null : AppColors.surfaceLip(d));
    final body = SqLip(
      fill: fill ??
          (onInk ? Colors.white.withValues(alpha: 0.08) : AppColors.card(d)),
      border: border ?? (onInk ? null : AppColors.border(d)),
      lip: edge,
      depth: edge == null ? 0 : 3,
      radius: size * 0.34,
      onTap: onTap,
      child: SizedBox(
        width: size, height: size,
        child: Icon(icon,
          size: size * 0.44,
          color: iconColor ?? (onInk ? Colors.white : AppColors.text2(d))),
      ),
    );
    if (badge == null) return body;
    return Stack(
      clipBehavior: Clip.none,
      children: [body, Positioned(top: 7, right: 8, child: badge!)],
    );
  }
}

/// A tiny red dot used to mark "there is something new here".
class SqDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool ringed;
  const SqDot({super.key, this.color = AppColors.red, this.size = 7, this.ringed = true});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: ringed
          ? Border.all(color: AppColors.card(isDark(context)), width: 1.5)
          : null,
    ),
  );
}

// ═══════════════════════════════════════════════════════════
// Surfaces
// ═══════════════════════════════════════════════════════════

/// A plain white card with a hairline border. The default container of 4.0.
class SqPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? fill, border;
  final bool lifted;

  const SqPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(17),
    this.radius = 22,
    this.onTap,
    this.fill,
    this.border,
    this.lifted = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqLip(
      fill: fill ?? AppColors.card(d),
      border: border ?? AppColors.border(d),
      lip: lifted ? AppColors.surfaceLip(d) : null,
      depth: 3,
      radius: radius,
      padding: padding,
      onTap: onTap,
      child: child,
    );
  }
}

/// The one dark block per screen — the focus moment.
///
/// A soft coloured light bleeds in from a corner so the block has depth
/// without becoming a gradient card.
class SqInkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color glow;
  final Alignment glowAt;
  final VoidCallback? onTap;
  final bool shadow;

  const SqInkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.glow = AppColors.primary,
    this.glowAt = Alignment.topRight,
    this.onTap,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final body = Container(
      decoration: BoxDecoration(
        color: AppColors.inkBlock(d),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [BoxShadow(
                color: AppColors.ink.withValues(alpha: d ? 0.55 : 0.30),
                blurRadius: 28, offset: const Offset(0, 12))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned(
              top: glowAt.y < 0 ? -55 : null,
              bottom: glowAt.y > 0 ? -55 : null,
              left: glowAt.x < 0 ? -45 : null,
              right: glowAt.x > 0 ? -45 : null,
              child: IgnorePointer(
                child: Container(
                  width: 175, height: 175,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: glow.withValues(alpha: 0.26),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: body,
    );
  }
}

/// A white rounded container that hosts a stack of [SqTile]s separated by
/// hairlines — the list idiom of 4.0.
class SqGroup extends StatelessWidget {
  final List<Widget> children;
  final double radius;
  final Color? fill, border;

  const SqGroup({
    super.key,
    required this.children,
    this.radius = 22,
    this.fill,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
          height: 1, thickness: 1, indent: 0, endIndent: 0,
          color: AppColors.divider(d)));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: fill ?? AppColors.card(d),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? AppColors.border(d)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// One row of a *lazily built* group.
///
/// [SqGroup] takes its children up front, which is wrong for a word bank that
/// may hold hundreds of rows. This paints the same card — side borders, a
/// hairline between rows, rounded top and bottom — one row at a time, so it
/// can live inside a `SliverList.builder`.
class SqGroupRow extends StatelessWidget {
  final Widget child;
  final bool first, last;
  final double radius;

  const SqGroupRow({
    super.key,
    required this.child,
    required this.first,
    required this.last,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final edge = AppColors.border(d);
    final corner = Radius.circular(radius);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(d),
        border: Border(
          left: BorderSide(color: edge),
          right: BorderSide(color: edge),
          top: BorderSide(color: first ? edge : AppColors.divider(d)),
          bottom: last ? BorderSide(color: edge) : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: first ? corner : Radius.zero,
          topRight: first ? corner : Radius.zero,
          bottomLeft: last ? corner : Radius.zero,
          bottomRight: last ? corner : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// One row inside an [SqGroup].
class SqTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? titleColor, fill;
  final bool strike;
  final EdgeInsets padding;
  final Widget? below;

  const SqTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.titleColor,
    this.fill,
    this.strike = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final body = Container(
      color: fill,
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                  style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: titleColor ?? AppColors.text(d),
                    decoration:
                        strike ? TextDecoration.lineThrough : TextDecoration.none)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!,
                    style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600,
                      color: AppColors.text3(d))),
                ],
                if (below != null) ...[const SizedBox(height: 6), below!],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (chevron) ...[
            const SizedBox(width: 8),
            Icon(PhosphorIconsBold.caretRight,
              size: 15, color: AppColors.text4(d)),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: body,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Small pieces
// ═══════════════════════════════════════════════════════════

/// The rounded-square tinted icon box that leads most rows.
class SqTintBox extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final double size;
  final bool solid;
  final Color? fill;

  const SqTintBox(
    this.icon, {
    super.key,
    this.tint = AppColors.primary,
    this.size = 38,
    this.solid = false,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: fill ?? (solid ? tint : AppColors.soft(tint, d)),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      alignment: Alignment.center,
      child: Icon(icon,
        size: size * 0.5,
        color: solid ? Colors.white : AppColors.onSoft(tint, d)),
    );
  }
}

/// A rounded-square avatar built from the first letter of a name.
class SqAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? tint;
  final bool solid;
  final Color? ring;

  const SqAvatar(
    this.name, {
    super.key,
    this.size = 38,
    this.tint,
    this.solid = false,
    this.ring,
  });

  String get _initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final first = t.characters.first;
    return first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final c = tint ?? AppColors.primary;
    final box = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: solid ? c : AppColors.muted(d),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      alignment: Alignment.center,
      child: SqNum(_initial,
        size: size * 0.40,
        color: solid ? Colors.white : AppColors.text2(d)),
    );
    if (ring == null) return box;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ring,
        borderRadius: BorderRadius.circular(size * 0.34 + 4)),
      child: box,
    );
  }
}

/// A pill: icon + label on a tinted or outlined background.
class SqChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color tint;
  final bool selected;
  final bool outlined;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;
  final bool onInk;

  const SqChip(
    this.label, {
    super.key,
    this.icon,
    this.tint = AppColors.primary,
    this.selected = false,
    this.outlined = false,
    this.onTap,
    this.radius = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    this.onInk = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);

    Color bg, fg, edge;
    if (onInk) {
      bg = selected ? tint : Colors.white.withValues(alpha: 0.07);
      fg = selected ? Colors.white : AppColors.onInk2;
      edge = selected ? tint : Colors.white.withValues(alpha: 0.12);
    } else if (selected) {
      bg = AppColors.soft(tint, d);
      fg = AppColors.onSoft(tint, d);
      edge = AppColors.line(tint, d);
    } else if (outlined) {
      bg = AppColors.card(d);
      fg = AppColors.text2(d);
      edge = AppColors.border(d);
    } else {
      bg = AppColors.soft(tint, d);
      fg = AppColors.onSoft(tint, d);
      edge = Colors.transparent;
    }

    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: edge, width: selected && !onInk ? 1.5 : 1),
      ),
      // A chip label has to be able to wrap. Kazakh and Russian labels run
      // long, the app allows text up to 1.2×, and a chip that cannot reflow
      // simply runs off the row it sits in — which is content nobody can see.
      //
      // Which is why this is a LayoutBuilder and not a plain Flexible: chips
      // also live in horizontal lists, and there the width arrives unbounded,
      // where a flex child is not allowed at all. Bounded means "on a page,
      // let it wrap"; unbounded means "in a strip, take your natural size".
      child: LayoutBuilder(
        builder: (context, box) {
          final text = Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: fg));
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              if (box.maxWidth.isFinite) Flexible(child: text) else text,
            ],
          );
        },
      ),
    );

    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: body,
    );
  }
}

/// A compact tag — "+40 XP", "жаңа", "18 дайын".
class SqBadge extends StatelessWidget {
  final String label;
  final Color tint;
  final bool solid;
  final bool numeric;
  final double size;

  const SqBadge(
    this.label, {
    super.key,
    this.tint = AppColors.primary,
    this.solid = false,
    this.numeric = false,
    this.size = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final fg = solid ? Colors.white : AppColors.onSoft(tint, d);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? tint : AppColors.soft(tint, d),
        borderRadius: BorderRadius.circular(8),
      ),
      child: numeric
          ? SqNum(label, size: size + 1, color: fg)
          : Text(label,
              style: TextStyle(
                fontSize: size, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// A rounded progress track.
class SqTrack extends StatelessWidget {
  final double value;
  final Color color;
  final Color? background;
  final double height;
  final bool animate;

  const SqTrack(
    this.value, {
    super.key,
    this.color = AppColors.primary,
    this.background,
    this.height = 6,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final track = background ?? (d ? AppColors.borderD : AppColors.mutedL);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: track,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: animate
                ? TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, __) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(height)),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(height)),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The segmented progress rail: one bead per question, the live one widened.
class SqBeads extends StatelessWidget {
  final int total, done;
  final int? current;
  final Color doneColor, currentColor;
  final Color? pending;
  final double height;
  final List<Color>? colors;

  const SqBeads({
    super.key,
    required this.total,
    this.done = 0,
    this.current,
    this.doneColor = AppColors.green,
    this.currentColor = AppColors.primary,
    this.pending,
    this.height = 6,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final idle = pending ?? AppColors.border(d);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            flex: current == i ? 16 : 10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: height,
              decoration: BoxDecoration(
                color: colors != null
                    ? colors![i.clamp(0, colors!.length - 1)]
                    : i < done
                        ? doneColor
                        : i == current
                            ? currentColor
                            : idle,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
          if (i != total - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// A donut progress ring with a value in the middle.
class SqRing extends StatelessWidget {
  final double value;
  final double size, stroke;
  final Color color;
  final Color? track;
  final Widget? child;

  const SqRing({
    super.key,
    required this.value,
    this.size = 58,
    this.stroke = 7,
    this.color = AppColors.primary,
    this.track,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SizedBox(
      width: size, height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(
            value: v,
            color: color,
            track: track ?? AppColors.muted(d),
            stroke: stroke,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value, stroke;
  final Color color, track;
  const _RingPainter({
    required this.value, required this.color,
    required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Five dots showing how well a word is known.
class SqMastery extends StatelessWidget {
  final int mastery;
  final double dot;
  const SqMastery(this.mastery, {super.key, this.dot = 6});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => Container(
        width: dot, height: dot,
        margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i < mastery
              ? AppColors.green
              : AppColors.border(d),
        ),
      )),
    );
  }
}

/// A three-up statistic cell, used inside dark result blocks.
class SqInkStat extends StatelessWidget {
  final String value, label;
  final Color? valueColor;
  const SqInkStat(this.value, this.label, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SqNum(value, size: 21, color: valueColor ?? Colors.white),
        const SizedBox(height: 2),
        Text(label,
          style: const TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w700,
            color: AppColors.onInk2)),
      ],
    ),
  );
}

/// A white stat tile: icon, number, caption.
class SqStat extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String value, label;
  final VoidCallback? onTap;

  const SqStat({
    super.key,
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(height: 6),
          SqNum(value, size: 20, color: AppColors.text(d)),
          const SizedBox(height: 2),
          Text(label,
            style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700,
              color: AppColors.text3(d))),
        ],
      ),
    );
  }
}

/// A segmented control — "Апта / Бүгін / Достар".
class SqSegmented extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;

  const SqSegmented({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        // A recessed track, not a card: the selected pill has to look like it
        // sits *in* something, and on a white box in light mode it looked
        // like a lone dark chip floating on the page.
        color: AppColors.muted(d),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border(d)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index
                        ? AppColors.inkBlock(d) : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(items[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: i == index ? Colors.white : AppColors.text2(d)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The answer button of a question screen: letter badge, text, verdict mark.
class SqAnswer extends StatelessWidget {
  final String text, badge;
  final VoidCallback? onTap;
  final bool revealed, isCorrect, isPicked;

  const SqAnswer({
    super.key,
    required this.text,
    required this.badge,
    this.onTap,
    this.revealed = false,
    this.isCorrect = false,
    this.isPicked = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);

    Color fill = AppColors.card(d);
    Color border = AppColors.border(d);
    Color ink = AppColors.text(d);
    Color badgeBg = AppColors.muted(d);
    Color badgeInk = AppColors.text3(d);
    Color? lip = AppColors.surfaceLip(d);
    IconData? mark;

    if (revealed && isCorrect) {
      fill = AppColors.soft(AppColors.green, d);
      border = AppColors.green;
      ink = AppColors.onSoft(AppColors.green, d);
      badgeBg = AppColors.green;
      badgeInk = Colors.white;
      lip = AppColors.line(AppColors.green, d);
      mark = PhosphorIconsFill.checkCircle;
    } else if (revealed && isPicked) {
      fill = AppColors.soft(AppColors.red, d);
      border = AppColors.red;
      ink = AppColors.onSoft(AppColors.red, d);
      badgeBg = AppColors.red;
      badgeInk = Colors.white;
      lip = AppColors.line(AppColors.red, d);
      mark = PhosphorIconsFill.xCircle;
    } else if (revealed) {
      fill = AppColors.muted(d);
      border = AppColors.divider(d);
      ink = AppColors.text4(d);
      lip = null;
    }

    return SqLip(
      fill: fill,
      border: border,
      borderWidth: 1.5,
      lip: lip,
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      onTap: revealed ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: badgeBg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: SqNum(badge, size: 13, color: badgeInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
              style: TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w800,
                letterSpacing: -0.2, height: 1.25, color: ink)),
          ),
          if (mark != null) ...[
            const SizedBox(width: 8),
            Icon(mark, size: 21, color: ink),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Page furniture
// ═══════════════════════════════════════════════════════════

/// The standard screen header: optional back button, eyebrow + title, actions.
class SqHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final VoidCallback? onBack;
  final IconData backIcon;
  final List<Widget> actions;
  final double titleSize;
  final bool onInk;

  const SqHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.onBack,
    this.backIcon = PhosphorIconsBold.arrowLeft,
    this.actions = const [],
    this.titleSize = 22,
    this.onInk = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Row(
      children: [
        if (onBack != null) ...[
          SqSquareButton(backIcon, onTap: onBack, onInk: onInk),
          const SizedBox(width: 11),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                SqEyebrow(eyebrow!,
                  color: onInk ? AppColors.onInk2 : null),
                const SizedBox(height: 1),
              ],
              Text(title,
                style: TextStyle(
                  fontSize: titleSize, fontWeight: FontWeight.w800,
                  letterSpacing: -0.55,
                  color: onInk ? Colors.white : AppColors.text(d))),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 9), a],
      ],
    );
  }
}

/// A scrollable 4.0 page: flat background, 18-pt gutters, room for the nav bar.
class SqPage extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;
  final Widget? floating;
  final Color? background;
  final ScrollPhysics? physics;

  const SqPage({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 118),
    this.onRefresh,
    this.floating,
    this.background,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      padding: padding,
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      children: children,
    );

    if (onRefresh != null) {
      list = RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.card(isDark(context)),
        onRefresh: onRefresh!,
        child: list,
      );
    }

    return Scaffold(
      backgroundColor: background ?? AppColors.bg(isDark(context)),
      floatingActionButton: floating,
      // Every screen here is laid out for a phone. Left unbounded in a desktop
      // browser the same content stretches across 1900pt: stat cards land at
      // opposite edges, rows read as unrelated fragments, and a page that is
      // full on a phone looks half empty. Capping the column keeps the design
      // it was drawn at and centres it, which is what a wide window should do
      // with a narrow layout.
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
            child: list,
          ),
        ),
      ),
    );
  }
}

/// Wide enough for a large phone held in landscape, narrow enough that a
/// desktop window does not spread a phone layout across the whole screen.
const double _pageMaxWidth = 560;

/// A row of cards that all take the height of the tallest one.
///
/// This is `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` with the one
/// thing that makes it legal inside a scroll view. A stretching Row hands its
/// children a *tight* cross-axis constraint taken from its own — and a direct
/// child of a ListView is given an unbounded height, so the children were
/// being laid out at infinity.
///
/// In a debug build that trips an assert. In a release build asserts are
/// stripped, so it silently produced an infinitely tall row: the page's scroll
/// extent went to infinity, and scrolling carried the content up and away with
/// no end and nothing to come back to. Four of the five tabs were built this
/// way — every one that pairs two stat cards side by side — and the fifth,
/// the word bank, was the only one that never did.
///
/// [IntrinsicHeight] bounds the row at the tallest child's natural height,
/// which is what "two cards, same height" meant in the first place.
class SqEqualRow extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;

  const SqEqualRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    // The one place in the app that is allowed to stretch a Row: here the
    // IntrinsicHeight above it has already bounded the cross axis.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: mainAxisAlignment,
      children: children,
    ),
  );
}

/// Caps and centres whatever a [Scaffold] puts in its `bottomNavigationBar`,
/// to the same width [SqPage] caps its content at.
///
/// The `heightFactor: 1` is the whole reason this is a widget rather than a
/// `Center` written inline. An [Align] only shrink-wraps an axis when it is
/// given a factor for it, or when the constraint on that axis is unbounded —
/// and the bottom-bar slot is measured with a bounded height, so a bare
/// [Center] there reports the full screen height. Scaffold uses that height
/// to decide where the body ends, so the bar floats its contents halfway up
/// the screen and collapses the page behind it. It looks exactly like every
/// tab losing its content, and it is one missing argument.
class SqBottomBarSlot extends StatelessWidget {
  final Widget child;
  const SqBottomBarSlot({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
      child: child,
    ),
  );
}

/// A column that fills the viewport when it fits and scrolls when it does not.
///
/// Several 4.0 screens pin an action to the bottom with a [Spacer]. That only
/// works while the content is shorter than the screen — on a small phone, or
/// with the text scaled up, the same layout overflows. This keeps the spacer
/// behaviour and adds a scroll as the escape hatch.
class SqFill extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final CrossAxisAlignment crossAxisAlignment;

  const SqFill({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: box.maxHeight - padding.vertical),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          ),
        ),
      ),
    ),
  );
}

/// Empty state: a tinted icon, a line of explanation, one way forward.
class SqEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color tint;

  const SqEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.tint = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SqTintBox(icon, tint: tint, size: 60),
          const SizedBox(height: 15),
          Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: AppColors.text(d))),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, height: 1.5, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// A shimmering placeholder used while a list loads.
class SqShimmer extends StatefulWidget {
  final double height, radius;
  final EdgeInsets margin;
  const SqShimmer({
    super.key,
    this.height = 68,
    this.radius = 20,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  State<SqShimmer> createState() => _SqShimmerState();
}

class _SqShimmerState extends State<SqShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1150))..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + _c.value * 2, 0),
            end: Alignment(1 + _c.value * 2, 0),
            colors: [
              AppColors.card(d), AppColors.muted(d), AppColors.card(d),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Motion
// ═══════════════════════════════════════════════════════════

/// The 4.0 entrance: a short rise plus fade, matching the design's `sqRise`.
class SqRise extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;
  const SqRise({
    super.key, required this.child,
    this.delay = Duration.zero, this.offset = 14});

  @override
  State<SqRise> createState() => _SqRiseState();
}

class _SqRiseState extends State<SqRise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () { if (mounted) _c.forward(); });
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (_, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// A number that counts up when it first appears.
class SqCountUp extends StatelessWidget {
  final int value;
  final double size;
  final Color? color;
  final String prefix, suffix;

  const SqCountUp(
    this.value, {
    super.key,
    this.size = 22,
    this.color,
    this.prefix = '',
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 850),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) =>
        SqNum('$prefix${v.round()}$suffix', size: size, color: color),
  );
}

/// A slow pulse used on live indicators (the opponent's "answering…" dot).
class SqPulse extends StatefulWidget {
  final Widget child;
  final Duration period;
  const SqPulse({
    super.key, required this.child,
    this.period = const Duration(milliseconds: 1200)});

  @override
  State<SqPulse> createState() => _SqPulseState();
}

class _SqPulseState extends State<SqPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)
        ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Opacity(
      opacity: 0.55 + _c.value * 0.45,
      child: Transform.scale(scale: 1 + _c.value * 0.08, child: child),
    ),
    child: widget.child,
  );
}

/// A gentle float used on reward art.
class SqFloat extends StatefulWidget {
  final Widget child;
  final double distance;
  const SqFloat({super.key, required this.child, this.distance = 5});

  @override
  State<SqFloat> createState() => _SqFloatState();
}

class _SqFloatState extends State<SqFloat> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(
      offset: Offset(0, -widget.distance * Curves.easeInOut.transform(_c.value)),
      child: child,
    ),
    child: widget.child,
  );
}

// ═══════════════════════════════════════════════════════════
// Feedback
// ═══════════════════════════════════════════════════════════

void sqSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            error ? PhosphorIconsFill.warningCircle : PhosphorIconsFill.checkCircle,
            size: 18, color: error ? AppColors.red : AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
              style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
        ],
      ),
      duration: const Duration(seconds: 3),
    ));
}

/// A yes/no sheet styled like the rest of 4.0.
Future<bool> sqConfirm(
  BuildContext context, {
  required String title,
  required String message,
  // Resolved in the body: a default value has to be a constant, and tr() is
  // not one.
  String? confirm,
  String? cancel,
  bool danger = true,
}) async {
  final d = isDark(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card(d),
      title: Text(title,
        style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text(d))),
      content: Text(message,
        style: TextStyle(
          fontSize: 13.5, height: 1.5, color: AppColors.text2(d))),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancel ?? tr('Жоқ'),
            style: TextStyle(color: AppColors.text3(d)))),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirm ?? tr('Иә'),
            style: TextStyle(
              color: danger ? AppColors.red : AppColors.primaryDeep,
              fontWeight: FontWeight.w800))),
      ],
    ),
  );
  return ok ?? false;
}

/// The grab handle at the top of a bottom sheet.
class SqSheetGrip extends StatelessWidget {
  const SqSheetGrip({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40, height: 4,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppColors.border(isDark(context)),
        borderRadius: BorderRadius.circular(2)),
    ),
  );
}

/// A nine-digit friend code, grouped the way a phone number is.
///
/// "482739154" is nine characters nobody can read back correctly;
/// "482 739 154" is three chunks anybody can. Anything that is not nine
/// digits is returned untouched rather than mangled into groups.
String sqFriendCode(String? raw) {
  final d = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 9) return raw ?? '';
  return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
}
