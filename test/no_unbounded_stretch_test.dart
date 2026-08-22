// test/no_unbounded_stretch_test.dart
//
// `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` is banned in this app.
//
// A stretching Row hands its children a *tight* cross-axis constraint taken
// from its own. A direct child of a ListView is given an unbounded height, so
// the children were laid out at infinity. In a debug build that trips an
// assert; in a release build asserts are stripped and it silently produces an
// infinitely tall row, which takes the page's scroll extent to infinity with
// it. The symptom is that scrolling carries the content up and away with no
// end and nothing to scroll back to — and it shipped on four of the five
// tabs, every one that pairs two stat cards side by side.
//
// Nothing catches this: `flutter analyze` is happy, the widget renders, and a
// debug run only complains if that exact row is on screen. So it is caught
// here instead, by reading the source. [SqEqualRow] is the sanctioned
// version — the same row with an IntrinsicHeight above it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no Row stretches its children against an unbounded height', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'Row\(\s*\n\s*crossAxisAlignment:\s*CrossAxisAlignment\.stretch',
      multiLine: true,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      // sq.dart holds the one sanctioned use, inside SqEqualRow, where an
      // IntrinsicHeight has already bounded the cross axis.
      if (entity.path.endsWith('sq.dart')) continue;
      for (final m in pattern.allMatches(source)) {
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(offenders, isEmpty,
        reason: 'use SqEqualRow instead — a bare stretching Row inside a '
                'scroll view lays its children out at infinite height:\n'
                '${offenders.join('\n')}');
  });
}
