// test/shell_layout_test.dart
//
// The bottom bar must not eat the page.
//
// `bottomNavigationBar: Center(child: ConstrainedBox(...))` looks like it
// caps the bar's width and nothing else. It does not: an Align shrink-wraps
// an axis only when given a factor for it, and the bottom-bar slot is
// measured with a bounded height, so that Center reported the full screen
// height. Scaffold subtracts the bar's height to find where the body ends, so
// every tab lost its content area and the nav pill floated halfway up the
// screen — the app looked like it scrolled its own content away into nothing.
//
// Nothing threw, no test failed, and the difference between the broken and
// the fixed version is one argument. Hence this.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sozqor/core/widgets/sq.dart';

const _screen = Size(390, 844);
const _barHeight = 84.0;

Future<Size> _layout(WidgetTester tester, Widget bottomBar) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: const SizedBox.expand(child: Text('page')),
      bottomNavigationBar: bottomBar,
    ),
  ));
  await tester.pump();
  return tester.getSize(find.byWidget(bottomBar));
}

void main() {
  testWidgets('SqBottomBarSlot is only as tall as the bar inside it',
      (tester) async {
    const bar = SqBottomBarSlot(child: SizedBox(height: _barHeight));
    final size = await _layout(tester, bar);

    expect(size.height, _barHeight,
        reason: 'the slot took ${size.height} of a ${_screen.height}pt '
                'screen; Scaffold subtracts that from the page');
  });

  testWidgets('SqBottomBarSlot caps its width on a wide window',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: SizedBox.expand(),
        bottomNavigationBar: SqBottomBarSlot(
          child: SizedBox(height: _barHeight, child: Placeholder()),
        ),
      ),
    ));
    await tester.pump();

    // The slot spans the window; the bar inside it is capped and centred.
    final inner = tester.getRect(find.byType(Placeholder));
    expect(inner.width, lessThanOrEqualTo(560));
    expect(inner.center.dx, closeTo(700, 1),
        reason: 'the bar should sit in the middle of a 1400pt window');
  });

  testWidgets('the page keeps its height behind the bar', (tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: SizedBox.expand(child: ColoredBox(color: Color(0xFF000000))),
        bottomNavigationBar: SqBottomBarSlot(
          child: SizedBox(height: _barHeight),
        ),
      ),
    ));
    await tester.pump();

    // extendBody means the page runs the full height, under the bar.
    final body = tester.getSize(find.byType(ColoredBox).first);
    expect(body.height, _screen.height,
        reason: 'the page collapsed to ${body.height}pt');
  });
}
