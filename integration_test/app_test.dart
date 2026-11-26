import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/main.dart';
import 'package:integration_test/integration_test.dart';

const String _messyCard = '''
  RAVI  KUMAR
 Sr.  Manager
Acrne Technologies Pvt.Ltd
 ravi.kumar @ acrne-tech.con
M: +91 98l23 45678
www.acrne-tech.com
Plot 12, Sector 5 , HSR Layout
Bengaluru - 560102''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('end-to-end: paste, extract, review and clear', (tester) async {
    await tester.pumpWidget(const HelloScanApp());
    await tester.pumpAndSettle();

    expect(find.text('Your batch is empty'), findsOneWidget);

    await tester.tap(find.text('Paste text'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('paste-text-input')),
      _messyCard,
    );
    await tester.tap(find.byKey(const Key('paste-extract-button')));
    await tester.pumpAndSettle();

    // Extraction populated the card and surfaced the review banner.
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.textContaining('Auto-filled'), findsOneWidget);

    // Scroll the editor to reach the review action.
    await tester.dragUntilVisible(
      find.text('Mark reviewed'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.tap(find.text('Mark reviewed'));
    await tester.pumpAndSettle();
    expect(find.text('Reviewed ✓'), findsOneWidget);

    await tester.tap(find.text('Clear batch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(find.text('Your batch is empty'), findsOneWidget);
  });
}
