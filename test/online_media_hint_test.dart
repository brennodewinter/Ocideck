import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Online media die niet speelt, met een reden die past bij wáárom — en, waar
/// dat helpt, een sprong naar de instelling (#852).
///
/// De melding was "Online media staat uit" ongeacht de oorzaak. Nu zijn er drie
/// gevallen: op web blokkeert de browser het sowieso (aanzetten helpt niet), de
/// instelling staat uit (spring naar Beveiliging), of de URL is geweigerd (het
/// ligt aan de bron). De knop verschijnt alléén waar de instelling te bereiken
/// is — de editor-preview zet daar de callback; presenter, thumbnails, export en
/// de play-only-webdemo laten hem null en tonen geen knop.
void main() {
  group('remoteBlockedReasonFor kiest de juiste reden', () {
    test('web wint, ook als de instelling aan zou staan', () {
      // Op web helpt aanzetten niet — de CSP blokkeert het. Daarom eerst.
      expect(
        remoteBlockedReasonFor(isWeb: true, allowRemoteMedia: true),
        RemoteBlockedReason.web,
      );
      expect(
        remoteBlockedReasonFor(isWeb: true, allowRemoteMedia: false),
        RemoteBlockedReason.web,
      );
    });

    test('instelling uit (niet-web) -> settingOff', () {
      expect(
        remoteBlockedReasonFor(isWeb: false, allowRemoteMedia: false),
        RemoteBlockedReason.settingOff,
      );
    });

    test('instelling aan maar toch geblokkeerd (niet-web) -> urlRejected', () {
      expect(
        remoteBlockedReasonFor(isWeb: false, allowRemoteMedia: true),
        RemoteBlockedReason.urlRejected,
      );
    });
  });

  Future<void> pumpVideo(
    WidgetTester tester, {
    required bool allowRemoteMedia,
    VoidCallback? onEnable,
  }) async {
    final slide = Slide.create(SlideType.video).copyWith(
      videoPath: 'https://eigenbureau.nl/img/video/clip.mp4',
      title: 'Online clip',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        locale: const Locale('nl'),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 200,
            child: SlidePreviewWidget(
              slide: slide,
              enableMedia: true,
              allowRemoteMedia: allowRemoteMedia,
              onEnableOnlineMedia: onEnable,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('editor-preview: melding + knop die de sprong aanroept', (
    tester,
  ) async {
    var tapped = false;
    await pumpVideo(
      tester,
      allowRemoteMedia: false,
      onEnable: () => tapped = true,
    );

    expect(find.text('Online media staat uit'), findsOneWidget);
    final knop = find.text('Aanzetten in instellingen');
    expect(knop, findsOneWidget);

    await tester.tap(knop);
    await tester.pump();
    expect(
      tapped,
      isTrue,
      reason: 'de knop moet de instelling-sprong aanroepen',
    );
  });

  testWidgets('zonder callback (presenter/thumbnail/export): geen knop', (
    tester,
  ) async {
    await pumpVideo(tester, allowRemoteMedia: false, onEnable: null);

    expect(find.text('Online media staat uit'), findsOneWidget);
    expect(
      find.text('Aanzetten in instellingen'),
      findsNothing,
      reason: 'buiten de editor is de instelling niet te openen, dus geen knop',
    );
  });
}
