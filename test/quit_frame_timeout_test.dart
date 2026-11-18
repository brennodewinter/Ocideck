import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/app_shell.dart';

void main() {
  testWidgets('afsluiten blijft niet hangen als de engine geen frame levert', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (current) {
            context = current;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    var completed = false;
    // Bewust geen frames pompen: precies wat een achtergrondvenster mist.
    await tester.runAsync(() async {
      await settleUiBeforeNativeQuit(
        context,
        frameTimeout: const Duration(milliseconds: 30),
      ).timeout(const Duration(seconds: 2));
      completed = true;
    });
    expect(tester.takeException(), isNull);
    expect(completed, isTrue);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
