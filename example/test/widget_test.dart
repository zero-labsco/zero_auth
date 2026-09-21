import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_auth_example/main.dart';

void main() {
  testWidgets('demo app shows the unauthenticated state', (tester) async {
    await tester.pumpWidget(const DemoApp());

    expect(find.text('state: Unauthenticated'), findsOneWidget);
    expect(find.text('signed out'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.text('Demo account: user / user'), findsOneWidget);
  });

  testWidgets('renders without overflow from phone to desktop', (tester) async {
    // A phone, a tablet and a desktop window, all at 1x so logical size equals
    // the physical size we set.
    const sizes = <Size>[Size(360, 780), Size(768, 1024), Size(1440, 900)];

    for (final size in sizes) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const DemoApp());
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'layout must not overflow at $size',
      );
      expect(find.text('state: Unauthenticated'), findsOneWidget);
    }
  });
}
