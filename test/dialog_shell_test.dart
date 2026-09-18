import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/dialog_shell.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    Size surface = const Size(1200, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: OciDialogShell(
              width: 560,
              height: 560,
              child: OciDialogScaffold(
                title: 'Een lange venstertitel die mee moet kunnen schalen',
                leading: const Icon(Icons.folder_open_outlined),
                subtitle: const Text('Contextregel'),
                headerTrailing: const Text('Extra status'),
                body: const ColoredBox(color: Colors.transparent),
                footerLeading: const Text('Hulpactie', key: Key('leading')),
                actions: const [
                  TextButton(onPressed: null, child: Text('Annuleren')),
                  FilledButton(onPressed: null, child: Text('Doorgaan')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('gebruikt de voorkeursmaat en centrale venstervorm', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(
      tester.getSize(find.byKey(const Key('oci-dialog-surface'))),
      const Size(560, 560),
    );
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.shape, isA<RoundedRectangleBorder>());
    expect(
      (dialog.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(18),
    );
  });

  testWidgets('blijft binnen een kleine viewport', (tester) async {
    await pumpShell(tester, surface: const Size(400, 500));

    final size = tester.getSize(find.byKey(const Key('oci-dialog-surface')));
    expect(size.width, lessThanOrEqualTo(376));
    expect(size.height, lessThanOrEqualTo(476));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stapelt kop en voet bij tweehonderd procent tekst', (
    tester,
  ) async {
    await pumpShell(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    final statusTop = tester.getTopLeft(find.text('Extra status')).dy;
    final titleBottom = tester
        .getBottomLeft(
          find.text('Een lange venstertitel die mee moet kunnen schalen'),
        )
        .dy;
    expect(statusTop, greaterThanOrEqualTo(titleBottom));
    expect(find.text('Annuleren'), findsOneWidget);
    expect(find.text('Doorgaan'), findsOneWidget);
  });
}
