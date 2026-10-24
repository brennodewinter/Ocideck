// Stoppen vóór het venster dicht moet de sessie met appQuit afsluiten,
// ook als er op dat moment niets loopt.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/widgets/shell/recording_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stop voor quit raakt de sessie, ook als die leeg is', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => stopRecordingBeforeQuit(ref),
              child: const Text('stop'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
