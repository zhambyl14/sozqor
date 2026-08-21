import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LayoutBuilder inside IntrinsicHeight', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IntrinsicHeight(
            child: Column(children: [
              Row(children: [
                Flexible(
                  child: LayoutBuilder(
                    builder: (_, box) => Text('hello ${box.maxWidth}')),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
