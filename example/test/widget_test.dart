import 'package:flutter_test/flutter_test.dart';
import 'package:zero_auth_example/main.dart';

void main() {
  testWidgets('demo app shows the unauthenticated state', (tester) async {
    await tester.pumpWidget(const DemoApp());
    expect(find.text('state: Unauthenticated'), findsOneWidget);
  });
}
