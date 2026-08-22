// test/contrast_test.dart
//
// A floor under every light-mode boundary in the palette.
//
// Light is the theme the app starts in, so it is the one almost every learner
// sees, and it is the one that kept losing its edges. Twice now a surface
// colour has been picked a hair off the thing behind it and shipped: `mutedL`
// once matched `bgL` exactly, so a recessed panel rendered at contrast 1.00
// and simply was not there; then `borderL` and the button lips sat at 1.07 to
// 1.19 against white, so a card had no outline and a ghost button read as a
// line of text rather than as something to press.
//
// Neither was catchable by eye in a dark-mode screenshot, and neither throws.
// The numbers here are deliberately below the values the palette currently
// holds — this is a floor, not a mirror of today's hexes, so a designer can
// still tune a colour without the test objecting. What it will not allow is
// another boundary quietly falling back to invisible.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sozqor/core/theme/app_colors.dart';

/// WCAG relative luminance.
double _lum(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
         0.7152 * channel(c.g) +
         0.0722 * channel(c.b);
}

/// WCAG contrast ratio, 1.0 (identical) to 21.0 (black on white).
double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void _atLeast(Color a, Color b, double min, String what) {
  final got = _contrast(a, b);
  expect(got, greaterThanOrEqualTo(min),
      reason: '$what is at contrast ${got.toStringAsFixed(2)}, '
              'below the $min floor — it will not be visible');
}

void main() {
  group('light surfaces are distinguishable', () {
    test('a card is separable from the page behind it', () {
      // Not through the fill — white on off-white is deliberate — but through
      // the hairline, which therefore has to carry the whole boundary.
      _atLeast(AppColors.cardL, AppColors.borderL, 1.35, 'card border on card');
      _atLeast(AppColors.bgL, AppColors.borderL, 1.25, 'card border on page');
    });

    test('a row separator inside a card is visible', () {
      _atLeast(AppColors.cardL, AppColors.dividerL, 1.15, 'divider on card');
    });

    test('a recessed panel is visible on the page', () {
      // The bug this one is named for: mutedL was once bgL exactly.
      _atLeast(AppColors.bgL, AppColors.mutedL, 1.08, 'muted panel on page');
    });

    test('a surface button reads as pressable', () {
      // The 3-pixel lip under a ghost action or a header square is the only
      // thing that says "button" on a white-on-white surface.
      _atLeast(AppColors.cardL, AppColors.surfaceLip(false), 1.45,
          'button lip under a white face');
      _atLeast(AppColors.bgL, AppColors.surfaceLip(false), 1.35,
          'button lip against the page');
    });

    test('body text clears AA on every light surface', () {
      for (final surface in [AppColors.bgL, AppColors.cardL, AppColors.mutedL]) {
        _atLeast(surface, AppColors.textL, 4.5, 'primary text');
        _atLeast(surface, AppColors.text2L, 4.5, 'secondary text');
      }
    });
  });

  group('dark surfaces are distinguishable', () {
    test('a card is separable from the page behind it', () {
      _atLeast(AppColors.bgD, AppColors.cardD, 1.08, 'card on page');
      _atLeast(AppColors.cardD, AppColors.borderD, 1.15, 'card border on card');
    });

    test('body text clears AA on every dark surface', () {
      for (final surface in [AppColors.bgD, AppColors.cardD, AppColors.mutedD]) {
        _atLeast(surface, AppColors.textD, 4.5, 'primary text');
        _atLeast(surface, AppColors.text2D, 4.5, 'secondary text');
      }
    });
  });

  group('accents stay readable on their own tint', () {
    // Every tinted row in the app is assembled the same way: soft() behind,
    // onSoft() on top. If one accent's pair fails, every badge, chip and
    // banner built from it fails with it.
    const accents = <String, Color>{
      'primary': AppColors.primary,
      'green':   AppColors.green,
      'red':     AppColors.red,
      'amber':   AppColors.amber,
      'sky':     AppColors.sky,
    };

    for (final e in accents.entries) {
      test('${e.key} ink on ${e.key} soft', () {
        for (final dark in [false, true]) {
          _atLeast(
            AppColors.soft(e.value, dark),
            AppColors.onSoft(e.value, dark),
            3.0,
            '${e.key} label on its tint (${dark ? 'dark' : 'light'})');
        }
      });
    }
  });
}
