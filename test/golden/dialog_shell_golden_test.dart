@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/dialog_shell.dart';

const _surfaceKey = ValueKey('dialog-shell-golden-surface');

Future<void> _match(
  WidgetTester tester, {
  required String name,
  required bool dark,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  const size = Size(960, 760);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => AppTheme.isDark = false);
  AppTheme.isDark = dark;

  final baseTheme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
      ),
      home: MediaQuery(
        data: const MediaQueryData(
          size: size,
          disableAnimations: true,
        ).copyWith(textScaler: textScaler),
        child: Scaffold(
          body: RepaintBoundary(
            key: _surfaceKey,
            child: ColoredBox(
              color: baseTheme.colorScheme.surfaceContainerLow,
              child: Center(
                child: OciDialogShell(
                  width: 620,
                  height: 560,
                  child: OciDialogScaffold(
                    title: 'Presentatie openen',
                    leading: const Icon(Icons.folder_open_outlined),
                    subtitle: const Text('WebDAV · Rapportages'),
                    body: ListView(
                      children: const [
                        ListTile(
                          leading: Icon(Icons.folder_outlined),
                          title: Text('2026'),
                          trailing: Icon(Icons.chevron_right),
                        ),
                        ListTile(
                          leading: Icon(Icons.slideshow_outlined),
                          title: Text('Managementrapportage'),
                        ),
                        ListTile(
                          leading: Icon(Icons.slideshow_outlined),
                          title: Text('Technisch overzicht'),
                        ),
                      ],
                    ),
                    footerLeading: const Icon(Icons.drag_indicator),
                    actions: const [
                      TextButton(onPressed: null, child: Text('Annuleren')),
                      FilledButton(onPressed: null, child: Text('Openen')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await expectLater(
    find.byKey(_surfaceKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  testWidgets('gedeelde dialoogschil volgt licht en donker profiel', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await _match(
        tester,
        name: 'dialog_shell_${dark ? 'dark' : 'light'}',
        dark: dark,
      );
    }
  });

  testWidgets('gedeelde dialoogschil blijft bruikbaar bij grote tekst', (
    tester,
  ) async {
    await _match(
      tester,
      name: 'dialog_shell_large_text',
      dark: false,
      textScaler: const TextScaler.linear(2),
    );
  });
}
