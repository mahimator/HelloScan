import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/main.dart';

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
  testWidgets('pasting messy card text auto-fills, reviews and clears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HelloScanApp());
    expect(find.text('Your batch is empty'), findsOneWidget);

    await tester.tap(find.text('Paste text'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('paste-text-input')),
      _messyCard,
    );
    await tester.tap(find.byKey(const Key('paste-extract-button')));
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields, hasLength(8));
    expect(fields[0].initialValue, 'Ravi Kumar');
    expect(fields[1].initialValue, 'Sr. Manager');
    expect(fields[2].initialValue, isNotEmpty);
    expect(fields[3].initialValue, 'ravi.kumar@acrne-tech.com');
    expect(fields[4].initialValue, '+919812345678');
    expect(fields[5].initialValue, contains('acrne-tech.com'));
    expect(fields[6].initialValue, contains('Bengaluru'));
    expect(find.textContaining('Auto-filled 7 fields'), findsOneWidget);

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
