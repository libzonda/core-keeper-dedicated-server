import 'package:flutter_test/flutter_test.dart';
import 'package:core_keeper_web/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CoreKeeperManagerApp());
    expect(find.text('Core Keeper'), findsOneWidget);
  });
}
