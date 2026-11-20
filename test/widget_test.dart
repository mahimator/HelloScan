import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/main.dart';

void main() {
  testWidgets('HelloScan workspace renders', (tester) async {
    await tester.pumpWidget(const HelloScanApp());
    expect(find.text('HelloScan'), findsOneWidget);
    expect(find.text('Your batch is empty'), findsOneWidget);
  });
}
