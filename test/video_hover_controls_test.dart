import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De afspeel-/pauzeknop van een video blijft verborgen tot je erover hovert.
/// Decoratieve overlays (footer, TLP-badge, banner, logo) liggen bovenop de
/// videolaag; als zij muis-events afvangen, krijgt de video een onterechte
/// onExit en verdwijnt de knop juist als je 'm nadert. Deze test borgt dat de
/// overlays de hover doorlaten, zodat de knop in de footer-zone verschijnt.
void main() {
  testWidgets('video play button reveals on hover, even over the footer band', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.video,
    ).copyWith(videoPath: '/tmp/does_not_exist.mp4', tlp: TlpLevel.amber);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: SlidePreviewWidget(
                slide: slide,
                enableMedia: true,
                autoplayMedia: false,
                // Footer met paginanummers + TLP-badge: overlays die over de
                // knop linksonder vallen.
                themeProfile: const ThemeProfile(footerShowPageNumbers: true),
                slideNumber: 2,
                slideCount: 5,
                tlp: TlpLevel.amber,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    AnimatedOpacity fade() => tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byIcon(Icons.play_circle),
        matching: find.byType(AnimatedOpacity),
      ),
    );

    // Verborgen zolang de muis er niet boven hangt.
    expect(fade().opacity, 0);

    final box = tester.getRect(find.byType(SlidePreviewWidget));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: box.topLeft - const Offset(20, 20));
    addTearDown(gesture.removePointer);
    await tester.pump();

    // Elke decoratieve overlay ligt onder dezelfde gedeelde IgnorePointer; we
    // controleren ze alle drie op hun eigen plek. Telkens van buiten de dia
    // terug naar binnen bewegen, zodat elke positie een echte enter is.
    Future<void> expectRevealAt(Offset target) async {
      await gesture.moveTo(box.topLeft - const Offset(20, 20)); // eerst eraf
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fade().opacity, 0);
      await gesture.moveTo(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fade().opacity, 1);
    }

    // Footer-strook (onder), classificatiebanner (boven) en TLP-badge
    // (rechtsonder) mogen geen van alle de hover blokkeren.
    await expectRevealAt(Offset(box.left + 30, box.bottom - 12));
    await expectRevealAt(Offset(box.center.dx, box.top + 6));
    await expectRevealAt(Offset(box.right - 24, box.bottom - 14));

    // En weer verbergen zodra de muis de dia verlaat.
    await gesture.moveTo(box.topLeft - const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fade().opacity, 0);
  });
}
