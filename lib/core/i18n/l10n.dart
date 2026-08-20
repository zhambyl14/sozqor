// lib/core/i18n/l10n.dart
//
// Interface language. Kazakh is the source language: every user-facing string
// in the app is written in Kazakh and doubles as its own key, so a missing
// translation degrades to readable Kazakh instead of a raw identifier.
//
//   tr('Сақтау')                            → 'Сохранить'
//   trp('{n} сөз қалды', {'n': '$left'})    → 'осталось 7 слов'
//
// `tr` is a plain top-level function so constants, models and repositories —
// none of which have a BuildContext — can translate too. Widgets additionally
// watch `langProvider`, which is what makes a language change repaint the
// screen the user is standing on, without a restart.

import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ru.dart';

class AppLang {
  AppLang._();

  static const kk = 'kk';
  static const ru = 'ru';
  static const supported = <String>[kk, ru];

  /// Name of each language in its own language — a picker is only readable
  /// when every row is written in the language it selects.
  static const names = <String, String>{kk: 'Қазақша', ru: 'Русский'};

  static const _prefsKey = 'sq_ui_lang';

  /// Read by [tr] on every call, including from code that has no context.
  /// Kept in step with [langProvider] by [LangCtrl].
  static String current = kk;

  static bool get isRu => current == ru;

  /// Loaded once before the first frame so the very first screen is already
  /// in the right language.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && supported.contains(saved)) {
        current = saved;
        return;
      }
      // No stored choice yet: follow the device, falling back to Kazakh.
      final device = PlatformDispatcher.instance.locale.languageCode;
      current = supported.contains(device) ? device : kk;
    } catch (_) {
      current = kk;
    }
  }

  static Future<void> persist(String v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, v);
    } catch (_) {/* a lost preference is not worth an error */}
  }

  /// True once the user has picked a language by hand; until then the profile
  /// row on the server may still overrule the device guess.
  static Future<bool> hasExplicitChoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey) != null;
    } catch (_) {
      return false;
    }
  }
}

/// Translates one user-facing string. The Kazakh original is the key.
String tr(String kk) {
  if (AppLang.current == AppLang.kk) return kk;
  return kRu[kk] ?? kk;
}

/// Translates a string with placeholders written as `{name}`. Placeholders
/// let Russian reorder the sentence instead of being stitched together in
/// Kazakh word order.
String trp(String kk, Map<String, String> args) {
  var s = tr(kk);
  for (final e in args.entries) {
    s = s.replaceAll('{${e.key}}', e.value);
  }
  return s;
}

/// Picks one of two already-translated strings by language. For the rare case
/// where a whole sentence differs structurally rather than word for word.
String byLang({required String kk, required String ru}) =>
    AppLang.current == AppLang.ru ? ru : kk;

class LangCtrl extends StateNotifier<String> {
  LangCtrl() : super(AppLang.current);

  /// Switching is immediate: [AppLang.current] moves first so anything read
  /// during the rebuild is already translated, then the state change repaints
  /// every widget watching [langProvider].
  Future<void> set(String v) async {
    if (!AppLang.supported.contains(v) || v == state) return;
    AppLang.current = v;
    state = v;
    await AppLang.persist(v);
  }

  /// Adopts the language stored on the profile, but never overrides a choice
  /// the user made on this device.
  Future<void> adoptFromProfile(String v) async {
    if (!AppLang.supported.contains(v) || v == state) return;
    if (await AppLang.hasExplicitChoice()) return;
    AppLang.current = v;
    state = v;
  }
}

final langProvider = StateNotifierProvider<LangCtrl, String>((_) => LangCtrl());
