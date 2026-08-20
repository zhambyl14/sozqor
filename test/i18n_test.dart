// test/i18n_test.dart
//
// Guards the two ways the interface language can silently break:
//
//   • a Russian line that loses one of its {placeholders}, so the learner
//     reads a literal "{n}" on screen;
//   • text that has been through a wrong-encoding round trip and comes back as
//     mojibake ("Қайырлы" -> "ÒšÐ°Ð¹Ñ‹Ñ€Ð»Ñ‹"), which is what the whole 4.0
//     Russian pass started from.

import 'package:flutter_test/flutter_test.dart';
import 'package:sozqor/core/i18n/l10n.dart';
import 'package:sozqor/core/i18n/ru.dart';

/// Cyrillic read as single-byte text always lands on one of these Latin
/// letters, none of which can appear in Kazakh or Russian copy. Typographic
/// punctuation the app really does use (em dash, middot, ellipsis, guillemets)
/// is deliberately not in the set.
final _mojibake = RegExp('[ÃÐÑÒÓÔ]');

final _placeholder = RegExp(r'\{[a-zA-Z0-9_]+\}');

void main() {
  setUp(() => AppLang.current = AppLang.kk);
  tearDown(() => AppLang.current = AppLang.kk);

  group('tr', () {
    test('Kazakh is returned unchanged, and is its own key', () {
      expect(tr('Сақтау'), 'Сақтау');
      expect(tr('бұл жол ешқашан аударылмайды'), 'бұл жол ешқашан аударылмайды');
    });

    test('Russian is used once the language switches', () {
      AppLang.current = AppLang.ru;
      expect(tr('Сақтау'), isNot('Сақтау'));
      expect(tr('Сақтау'), kRu['Сақтау']);
    });

    test('a missing translation falls back to readable Kazakh', () {
      AppLang.current = AppLang.ru;
      expect(tr('мүлдем жоқ кілт'), 'мүлдем жоқ кілт');
    });
  });

  group('trp', () {
    test('fills every placeholder in Kazakh', () {
      expect(trp('{n} сөз қайталау', {'n': '12'}), '12 сөз қайталау');
    });

    test('fills every placeholder in Russian', () {
      AppLang.current = AppLang.ru;
      final out = trp('{n} сөз қайталау', {'n': '12'});
      expect(out.contains('12'), isTrue);
      expect(_placeholder.hasMatch(out), isFalse,
          reason: 'a placeholder survived into the visible text: $out');
    });
  });

  group('ru.dart', () {
    test('is not empty', () {
      expect(kRu.length, greaterThan(500));
    });

    test('every translation keeps the placeholders of its key', () {
      final broken = <String>[];
      kRu.forEach((kk, ru) {
        final want = _placeholder.allMatches(kk).map((m) => m[0]).toList()..sort();
        final got = _placeholder.allMatches(ru).map((m) => m[0]).toList()..sort();
        if (want.join(',') != got.join(',')) broken.add('$kk -> $ru');
      });
      expect(broken, isEmpty,
          reason: 'these lines would show a raw {placeholder}:\n'
              '${broken.join('\n')}');
    });

    test('no key contains a Dart interpolation, which could never match', () {
      final bad = kRu.keys.where((k) => k.contains(r'$')).toList();
      expect(bad, isEmpty,
          reason: 'a key built by interpolation can never be looked up: $bad');
    });

    test('neither side is mojibake', () {
      final bad = <String>[];
      kRu.forEach((kk, ru) {
        if (_mojibake.hasMatch(kk) || _mojibake.hasMatch(ru)) bad.add(kk);
      });
      expect(bad, isEmpty, reason: 'wrong-encoding round trip in: $bad');
    });

    test('no translation is left identical to the Kazakh by accident', () {
      final same = kRu.entries.where((e) => e.key == e.value).toList();
      // Short labels, units and brand-ish lines legitimately match; a jump
      // well past that means an entry was filled in with the wrong side.
      expect(same.length, lessThan(60), reason: '${same.map((e) => e.key)}');
    });
  });

  group('AppLang', () {
    test('knows exactly the two languages the app ships', () {
      expect(AppLang.supported, ['kk', 'ru']);
      for (final code in AppLang.supported) {
        expect(AppLang.names[code], isNotNull,
            reason: '$code has no name to show in the picker');
      }
    });
  });
}
