// test/i18n_coverage_test.dart
//
// EN-2 / EN-55: "If a translation key is missing, it must be detected during
// development rather than silently displaying another language."
//
// tr() is deliberately forgiving at runtime — an unknown key degrades to
// readable Kazakh rather than crashing in a learner's face. That kindness is
// exactly what let untranslated strings pile up unseen: in Russian mode they
// simply render Kazakh, and nothing anywhere says so. This test is the other
// half of that bargain. It reads every tr()/trp() call site out of lib/ and
// fails the build when one has no Russian side.
//
// It parses source text rather than running the app because tr() takes a
// plain string and there is no registry to enumerate at runtime.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sozqor/core/i18n/ru.dart';

/// `tr('…')` / `trp('…'` with a single-quoted first argument, allowing Dart
/// escapes inside. Adjacent string literals — the way Dart wraps a long line —
/// are stitched back together by [_readKey] below.
final _call = RegExp(r"""\b(tr|trp)\(\s*'((?:[^'\\]|\\.)*)'""");

/// A single-quoted Dart literal, used to walk the continuation pieces of an
/// adjacent-literal concatenation.
final _literal = RegExp(r"""'((?:[^'\\]|\\.)*)'""");

/// Keys the app builds from data rather than writing out, or brand names that
/// are the same in both languages. Anything listed here is deliberate.
const _exempt = <String>{
  'SozQor',
};

/// Reads the full key beginning at [start], following Dart's adjacent string
/// literal concatenation:
///
///     tr('бірінші бөлігі '
///        'екінші бөлігі')
///
/// is one key, not two. Without this the checker reports the tail of every
/// wrapped line as a missing translation.
String _readKey(String src, RegExpMatch first) {
  final buffer = StringBuffer(first.group(2)!);
  var i = first.end;

  while (i < src.length) {
    // Skip whitespace and comments between the pieces.
    final rest = src.substring(i);
    final ws = RegExp(r'^(\s|//[^\n]*\n)*').firstMatch(rest)!;
    final j = i + ws.end;
    if (j >= src.length) break;
    if (src[j] != "'") break;

    final next = _literal.matchAsPrefix(src, j);
    if (next == null) break;
    buffer.write(next.group(1)!);
    i = next.end;
  }
  return buffer.toString();
}

/// Blanks whole-line comments so the worked examples inside a doc comment —
/// l10n.dart spells out `trp('{n} сөз қалды', …)` right above the function —
/// are not mistaken for real call sites. Lines are blanked rather than removed
/// so the adjacent-literal walk above still sees the same line structure.
String _stripComments(String src) => src
    .split('\n')
    .map((line) {
      final t = line.trimLeft();
      return t.startsWith('//') || t.startsWith('*') ? '' : line;
    })
    .join('\n');

/// Dart escapes as they appear in source, resolved to what the string
/// actually holds — ru.dart stores the resolved form.
String _unescape(String s) => s
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\\', r'\');

void main() {
  final lib = Directory('lib');

  test('every tr()/trp() key in lib/ has a Russian translation', () {
    expect(lib.existsSync(), isTrue, reason: 'run this from the package root');

    final missing = <String, String>{}; // key -> first file it appears in

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // ru.dart is the translation table itself, not a call site.
      if (entity.path.replaceAll(r'\', '/').endsWith('core/i18n/ru.dart')) {
        continue;
      }

      final src = _stripComments(entity.readAsStringSync());
      for (final m in _call.allMatches(src)) {
        final key = _unescape(_readKey(src, m));
        if (key.isEmpty || _exempt.contains(key)) continue;
        // A key assembled by interpolation can never be looked up; the
        // existing i18n_test already guards ru.dart's side of that.
        if (key.contains(r'$')) continue;
        if (kRu.containsKey(key)) continue;
        missing.putIfAbsent(key, () => entity.path);
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'These strings render Kazakh to a Russian-speaking learner.\n'
          'Add each one to lib/core/i18n/ru.dart:\n'
          '${missing.entries.map((e) => "  '${e.key}': '…',  // ${e.value}").join('\n')}',
    );
  });

  test('the checker actually finds call sites', () {
    // A guard on the guard: if the regex ever stops matching, the test above
    // would pass by finding nothing at all.
    var found = 0;
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      found += _call.allMatches(entity.readAsStringSync()).length;
    }
    expect(found, greaterThan(500),
        reason: 'the tr() scanner matched almost nothing — its regex broke');
  });
}
