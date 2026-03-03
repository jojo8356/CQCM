import 'package:flutter_test/flutter_test.dart';
import 'package:cqcm/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const CQCMApp());
    expect(find.text('CQCM'), findsOneWidget);
  });
}
