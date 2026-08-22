// lib/core/theme/app_colors.dart
//
// SozQor 4.0 palette.
//
// The 3.0 look was built out of gradient cards: every block competed for
// attention and nothing read as "the thing to press". 4.0 inverts that —
// the page is a quiet off-white, content sits on plain white cards with a
// hairline border, and exactly one block per screen is allowed to go dark
// (`ink`). That dark block is the focus moment: today's plan, the question,
// the result.
//
// Colour is used only to carry meaning: violet = the app / progress,
// green = correct & mastered, red = wrong & danger, amber = reward & streak,
// sky = information. Every accent ships as a quartet — solid / deep (the
// pressed "lip" under a button) / soft (tinted background) / line (its
// border) — so a tinted row is always assembled the same way.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand ────────────────────────────────────────────────
  static const Color primary     = Color(0xFF7C5CFF);
  static const Color primaryDeep = Color(0xFF5B3FD9);
  static const Color primarySoft = Color(0xFFF0EBFF);
  static const Color primaryLine = Color(0xFFDCD1FF);
  static const Color primaryEdge = Color(0xFFC9B8FF);
  static const Color primaryInk  = Color(0xFF5B3FD9);

  // ── Accents ──────────────────────────────────────────────
  static const Color green     = Color(0xFF00C48F);
  static const Color greenDeep = Color(0xFF00A97B);
  static const Color greenSoft = Color(0xFFE4FBF4);
  static const Color greenLine = Color(0xFFBFF2E4);
  static const Color greenInk  = Color(0xFF00795C);

  static const Color red     = Color(0xFFFF5B5B);
  static const Color redDeep = Color(0xFFD94141);
  static const Color redSoft = Color(0xFFFFE9E9);
  static const Color redLine = Color(0xFFFFD1D1);
  static const Color redInk  = Color(0xFFC0392B);

  static const Color amber     = Color(0xFFFFAA00);
  static const Color amberDeep = Color(0xFFD98A00);
  static const Color amberSoft = Color(0xFFFFF3DC);
  static const Color amberLine = Color(0xFFFFE3AE);
  static const Color amberInk  = Color(0xFFB26B00);

  static const Color sky     = Color(0xFF2E9BFF);
  static const Color skyDeep = Color(0xFF1B78D0);
  static const Color skySoft = Color(0xFFE6F2FF);
  static const Color skyLine = Color(0xFFC8E2FF);
  static const Color skyInk  = Color(0xFF1B78D0);

  /// Legacy aliases kept so screens that were written against the 3.0 names
  /// keep compiling — they all resolve to the 4.0 quartet above.
  static const Color mint    = green;
  static const Color coral   = red;
  static const Color magenta = primary;
  static const Color indigo  = primaryDeep;
  static const Color rose    = red;
  static const Color lime    = green;
  static const Color teal    = sky;
  static const Color success = green;
  static const Color error   = red;
  static const Color warning = amber;
  static const Color info    = sky;

  // ── The dark focus block ─────────────────────────────────
  /// Used for the one block per screen that has to win the eye.
  static const Color ink       = Color(0xFF15132A);
  static const Color inkLip    = Color(0xFF000000);
  static const Color inkTrack  = Color(0xFF2A2547);
  static const Color onInk     = Color(0xFFFFFFFF);
  static const Color onInk2    = Color(0xFFA79FD6);
  static const Color onInk3    = Color(0xFF8F88BE);
  static const Color onInkSoft = Color(0xFFCFCBEA);

  // ── Surfaces ─────────────────────────────────────────────
  static const Color bgL      = Color(0xFFF7F6FB);
  static const Color bgD      = Color(0xFF0E0D1A);
  static const Color surfaceL = Color(0xFFFFFFFF);
  static const Color surfaceD = Color(0xFF16142B);
  static const Color cardL    = Color(0xFFFFFFFF);
  static const Color cardD    = Color(0xFF1B1934);
  // Light mode ships as the default theme, so these two are what almost every
  // learner actually sees. They used to be 0xFFECEAF4 and 0xFFF4F2FA, which
  // against a white card come out at contrast 1.19 and 1.07 — below the point
  // a boundary is visible at all. Everything the design draws as "a white
  // card with a hairline" therefore had no hairline and no card: a plain
  // white button on a 0xFFF7F6FB page, which is exactly the "the buttons have
  // no colour" the light theme was reported for. Dark mode never showed it —
  // borderD against cardD is a clear step either way.
  static const Color borderL  = Color(0xFFDCD6EC);
  static const Color borderD  = Color(0xFF2C2950);
  static const Color dividerL = Color(0xFFE9E5F3);
  static const Color dividerD = Color(0xFF242143);
  // A recessed surface, one step below a card. This used to be
  // 0xFFF7F6FB — the exact value of bgL — so any muted panel sitting
  // directly on the page (the daily chest, the pack rows, the spelling
  // keys) rendered at contrast ratio 1.00 against it and simply was not
  // there. Dark mode never showed the bug because mutedD and bgD differ.
  static const Color mutedL   = Color(0xFFE9E6F3);
  static const Color mutedD   = Color(0xFF201D3C);

  // ── Text ─────────────────────────────────────────────────
  static const Color textL  = Color(0xFF15132A);
  static const Color textD  = Color(0xFFF3F1FF);
  static const Color text2L = Color(0xFF565272);
  static const Color text2D = Color(0xFFA8A3C8);
  static const Color text3L = Color(0xFF8B87A3);
  static const Color text3D = Color(0xFF7C7797);
  static const Color text4L = Color(0xFFB4B0C6);
  static const Color text4D = Color(0xFF5C5880);
  /// The Space-Grotesk micro caption above a title.
  static const Color eyebrowL = Color(0xFF9591AE);
  static const Color eyebrowD = Color(0xFF7B769C);

  // ── Helpers ──────────────────────────────────────────────
  static Color bg(bool d)      => d ? bgD : bgL;
  static Color surface(bool d) => d ? surfaceD : surfaceL;
  static Color card(bool d)    => d ? cardD : cardL;
  static Color border(bool d)  => d ? borderD : borderL;
  static Color divider(bool d) => d ? dividerD : dividerL;
  static Color muted(bool d)   => d ? mutedD : mutedL;
  static Color text(bool d)    => d ? textD : textL;
  static Color text2(bool d)   => d ? text2D : text2L;
  static Color text3(bool d)   => d ? text3D : text3L;
  static Color text4(bool d)   => d ? text4D : text4L;
  static Color eyebrow(bool d) => d ? eyebrowD : eyebrowL;

  /// The dark focus block reads as "even darker than the page" in light mode
  /// and as "a lifted panel" in dark mode.
  static Color inkBlock(bool d) => d ? const Color(0xFF232045) : ink;
  static Color inkBlockLip(bool d) => d ? const Color(0xFF11101F) : inkLip;
  static Color inkBlockTrack(bool d) => d ? const Color(0xFF383363) : inkTrack;

  /// A tinted background for an accent — the `soft` step, dimmed for dark.
  static Color soft(Color accent, bool d) =>
      d ? Color.alphaBlend(accent.withValues(alpha: 0.18), cardD) : _softOf(accent);

  /// The hairline that goes with [soft].
  static Color line(Color accent, bool d) =>
      d ? accent.withValues(alpha: 0.34) : _lineOf(accent);

  /// Readable text on top of [soft].
  static Color onSoft(Color accent, bool d) => d ? accent : _inkOf(accent);

  static Color _softOf(Color a) {
    if (a == green) return greenSoft;
    if (a == red) return redSoft;
    if (a == amber) return amberSoft;
    if (a == sky) return skySoft;
    if (a == primary) return primarySoft;
    return a.withValues(alpha: 0.10);
  }

  static Color _lineOf(Color a) {
    if (a == green) return greenLine;
    if (a == red) return redLine;
    if (a == amber) return amberLine;
    if (a == sky) return skyLine;
    if (a == primary) return primaryLine;
    return a.withValues(alpha: 0.28);
  }

  static Color _inkOf(Color a) {
    if (a == green) return greenInk;
    if (a == red) return redInk;
    if (a == amber) return amberInk;
    if (a == sky) return skyInk;
    if (a == primary) return primaryInk;
    return a;
  }

  /// The solid colour that sits under a raised element as its 4-pixel "lip".
  static Color lipOf(Color a) {
    if (a == green) return greenDeep;
    if (a == red) return redDeep;
    if (a == amber) return amberDeep;
    if (a == sky) return skyDeep;
    if (a == primary) return primaryDeep;
    if (a == ink) return inkLip;
    return Color.lerp(a, Colors.black, 0.24) ?? a;
  }

  /// The solid edge under a *surface* button — a header square, a ghost
  /// action, a lifted panel. [lipOf] is for accents; this is the neutral one
  /// that has to read against white without turning grey.
  static Color surfaceLip(bool d) =>
      d ? const Color(0xFF0A0918) : const Color(0xFFCEC7E4);

  static Color glass(bool d) => d
      ? const Color(0xFF16142B).withValues(alpha: 0.90)
      : Colors.white.withValues(alpha: 0.94);

  static Color shadow(bool d, {double alpha = 0.08}) => d
      ? Colors.black.withValues(alpha: alpha * 3.2)
      : const Color(0xFF15132A).withValues(alpha: alpha);

  static Color highlight(bool d) => d
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.9);

  // ── Gradients ────────────────────────────────────────────
  // 4.0 does not paint gradient cards any more. These stay so screens that
  // were not part of the redesign still compile, but each is now a single hue
  // with a barely-there shift — a flat brand surface rather than a rainbow.
  // They stay `const` because several call sites use them as const defaults.
  static const LinearGradient brandGrad = LinearGradient(
    colors: [primary, Color(0xFF7053E6)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient mintGrad = LinearGradient(
    colors: [green, Color(0xFF00B081)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient coralGrad = LinearGradient(
    colors: [red, Color(0xFFE65252)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient goldGrad = LinearGradient(
    colors: [amber, Color(0xFFE69900)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient skyGrad = LinearGradient(
    colors: [sky, Color(0xFF298CE6)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient nightGrad = LinearGradient(
    colors: [ink, Color(0xFF131126)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient indigoGrad = LinearGradient(
    colors: [primaryDeep, Color(0xFF5239C3)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);

  static const LinearGradient magentaGrad = brandGrad;
  static const LinearGradient sunsetGrad  = coralGrad;
  static const LinearGradient oceanGrad   = skyGrad;
  static const LinearGradient limeGrad    = mintGrad;
  static const LinearGradient roseGrad    = coralGrad;

  /// League tier colours: Bronze → Diamond.
  static const List<Color> tiers = [
    Color(0xFFCD7F32), // қола
    Color(0xFF9FB0C4), // күміс
    Color(0xFFFFAA00), // алтын
    Color(0xFF4FD1C5), // платина
    Color(0xFF7C5CFF), // алмас
  ];

  /// Stable accent for a topic/category chip — restricted to the 4.0 accents
  /// plus a few neutrals so a long word list never turns into a rainbow.
  static Color topic(String key) {
    const map = <String, Color>{
      'general': primary, 'food': green,    'travel': sky,
      'family': primary,  'body': red,      'home': Color(0xFF8D6E63),
      'school': primaryDeep, 'work': Color(0xFF00897B),
      'nature': green,    'animals': amber,
      'tech': sky,        'emotions': red,
      'sport': green,     'time': amber,
      'city': Color(0xFF546E7A), 'money': amber,
      'health': green,    'communication': primary,
    };
    return map[key] ?? primary;
  }
}
