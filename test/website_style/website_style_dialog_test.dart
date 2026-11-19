import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/website_style/website_style_proposal.dart';
import 'package:ocideck/widgets/dialogs/website_style_dialog.dart';

void main() {
  testWidgets(
    'website analyseren, dia bekijken en aangepast profiel overnemen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      WebsiteStyleSelection? chosen;
      Uri? address;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebsiteStyleDialog(
              lookup: (url) async {
                address = url;
                return const WebsiteStyleProposal(
                  profile: ThemeProfile(
                    name: 'example.org',
                    accentColor: '#4472C4',
                  ),
                  accentRoles: {'buttons'},
                  accentToken: '--brand-primary',
                  images: {},
                );
              },
              save: (selection) async {
                chosen = selection;
                return selection.profile;
              },
            ),
          ),
        ),
      );
      expect(find.text('Website-URL'), findsOneWidget);
      await tester.tap(find.text('Website analyseren'));
      await tester.pumpAndSettle();
      expect(find.text('Vul een geldig HTTPS-webadres in.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'example.org');
      await tester.tap(find.text('Website analyseren'));
      await tester.pumpAndSettle();
      expect(address, Uri.parse('https://example.org'));
      expect(find.textContaining('--brand-primary'), findsOneWidget);
      await tester.tap(find.text('Inhoudsdia'));
      await tester.pumpAndSettle();
      expect(find.text('Voorbeelddia'), findsWidgets);
      await tester.tap(find.text('Accentkleur · #4472C4'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Hexkleur'),
        '#116655',
      );
      await tester.pump();
      await tester.tap(find.text('Toepassen'));
      await tester.pumpAndSettle();
      expect(find.text('Accentkleur · #116655'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), 'Mijn huisstijl');
      await tester.tap(find.text('Profiel overnemen'));
      await tester.pumpAndSettle();
      expect(chosen?.profile.name, 'Mijn huisstijl');
      expect(chosen?.profile.accentColor, '#116655');
    },
  );
}
