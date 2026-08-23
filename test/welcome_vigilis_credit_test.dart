import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressietest voor de Vigilis-sponsorcredit rechtsonder op het welkomscherm.
/// De credit verdween "bij reload" — deze test rendert het welkomscherm echt en
/// controleert in beide thema's dat de tekst én het merk zichtbaar en binnen
/// beeld staan, en dat de gekozen asset bij het thema past (een licht-inkt-merk
/// op een lichte band, of andersom, zou onzichtbaar zijn).
Finder _vigilisImage() => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.contains('vigilis'),
);

Future<void> _pumpWelcome(
  WidgetTester tester, {
  required String profile,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'app_consent_accepted': true,
    'selectedAppAppearanceProfileName': profile,
  });
  await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
  await tester.pumpAndSettle();
}

void _expectVisibleWithinViewport(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThan(0), reason: 'Vigilis-logo heeft nul breedte');
  expect(size.height, greaterThan(0));
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-0.5));
  expect(rect.top, greaterThanOrEqualTo(-0.5));
  expect(rect.right, lessThanOrEqualTo(1200.5));
  expect(rect.bottom, lessThanOrEqualTo(800.5));
}

void main() {
  for (final (profile, dark) in const [('Europa', false), ('Donker', true)]) {
    testWidgets('welkomscherm toont de Vigilis-credit in profiel $profile', (
      tester,
    ) async {
      await _pumpWelcome(tester, profile: profile);

      // De tekst van de credit staat er.
      expect(find.text('Mogelijk gemaakt door'), findsOneWidget);

      // Het merk: precies één Image met de Vigilis-asset.
      final vigilis = _vigilisImage();
      expect(vigilis, findsOneWidget);

      // Laad de asset echt, zodat de intrinsieke breedte beschikbaar is.
      await tester.runAsync(() async {
        final element = tester.element(vigilis);
        final image = tester.widget<Image>(vigilis);
        await precacheImage(image.image, element);
      });
      await tester.pumpAndSettle();

      _expectVisibleWithinViewport(tester, vigilis);

      // De gekozen asset moet bij het thema passen: de donkere (licht-inkt)
      // variant op een donkere band, de lichte (donker-inkt) variant op een
      // lichte band. Het omgekeerde is precies het onzichtbare geval.
      final assetName =
          ((tester.widget<Image>(vigilis)).image as AssetImage).assetName;
      expect(
        assetName.contains('dark'),
        dark,
        reason: 'asset-inkt past niet bij het $profile-thema → onzichtbaar',
      );
    });
  }
}
