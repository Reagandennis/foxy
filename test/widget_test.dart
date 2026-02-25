import 'package:flutter_test/flutter_test.dart';

import 'package:foxy/main.dart';

void main() {
  testWidgets('Onboarding renders first slide', (WidgetTester tester) async {
    await tester.pumpWidget(const FoxyApp(supabaseReady: false));

    expect(find.text('Meet Foxy'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });
}
