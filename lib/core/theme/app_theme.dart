// lib/core/theme/app_theme.dart
//
// SozQor 4.0 typography and Material defaults.
//
// Two families do all the work: Manrope carries every sentence, Space Grotesk
// carries every number and every micro-caption. Splitting them that way is
// what lets a score, a rank and a timer read as data at a glance instead of
// blending into the prose around them.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(false);
  static ThemeData dark()  => _build(true);

  /// The numeric / caption face. Use it for scores, timers, ranks, XP and the
  /// small uppercase eyebrow above a title.
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static ThemeData _build(bool d) {
    final scheme = ColorScheme.fromSeed(
      seedColor:  AppColors.primary,
      brightness: d ? Brightness.dark : Brightness.light,
      surface:    AppColors.surface(d),
    );

    final base = d ? ThemeData.dark() : ThemeData.light();
    final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor:    AppColors.text(d),
      displayColor: AppColors.text(d),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg(d),
      textTheme: text,
      primaryColor: AppColors.primary,
      // 4.0 buttons answer with a lip that tucks in, not with a ripple.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800, fontSize: 20,
          letterSpacing: -0.5, color: AppColors.text(d)),
        iconTheme: IconThemeData(color: AppColors.text(d)),
      ),
      iconTheme: IconThemeData(color: AppColors.text(d), size: 20),
      cardTheme: CardThemeData(
        color: AppColors.card(d),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerTheme: DividerThemeData(color: AppColors.divider(d), thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card(d),
        hintStyle: TextStyle(
          color: AppColors.text4(d), fontWeight: FontWeight.w600, fontSize: 13.5),
        prefixIconColor: AppColors.text4(d),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: AppColors.border(d))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: AppColors.border(d))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: AppColors.red, width: 1.8)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text(d),
          side: BorderSide(color: AppColors.border(d), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: AppColors.ink,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentTextStyle: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card(d),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text(d)),
        contentTextStyle: TextStyle(
          fontSize: 13.5, height: 1.5, color: AppColors.text2(d)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface(d),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white : AppColors.card(d)),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary : AppColors.border(d)),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary : AppColors.border(d)),
      ),
    );
  }
}
