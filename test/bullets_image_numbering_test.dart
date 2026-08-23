import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/bullets_image_editor.dart';

/// A "bullets + image" slide is `SlideType.bulletsImage`, so it uses
/// [BulletsImageEditor] — including a split continuation page. This guards that
/// the "continue numbering" toggle (previously only in the plain bullets editor)
/// is reachable there, so a numbered split-with-image slide can carry on the
/// count.
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1400, height: 2000, child: child)),
  ),
);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Slide numberedBulletsImage() => Slide.create(
    SlideType.bulletsImage,
  ).copyWith(bullets: ['Zesde', 'Zevende'], listStyle: ListStyle.numbered);

  testWidgets(
    'continue-numbering toggle appears on a numbered bullets+image slide when '
    'the previous slide is numbered, and enabling it sets continueNumbering',
    (tester) async {
      var updated = numberedBulletsImage();
      await tester.pumpWidget(
        _host(
          BulletsImageEditor(
            slide: updated,
            onUpdate: (s) => updated = s,
            imageService: ImageService(),
            previousSlideIsNumbered: true,
          ),
        ),
      );

      expect(find.text('Doornummeren vanaf vorige slide'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(updated.continueNumbering, isTrue);
    },
  );

  testWidgets('the toggle is hidden when the previous slide is not numbered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: numberedBulletsImage(),
          onUpdate: (_) {},
          imageService: ImageService(),
          previousSlideIsNumbered: false,
        ),
      ),
    );

    expect(find.text('Doornummeren vanaf vorige slide'), findsNothing);
  });
}
