import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/cockpit_editor.dart';

/// Meter-editing coverage for the [CockpitEditor]: adding/removing meters,
/// switching a meter's type, and editing its value / unit / range all flow
/// through `onUpdate` and round-trip via [CockpitSpec.parse]. The editor is a
/// plain [StatefulWidget]; only a localised [MaterialApp] host is needed.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget host(Slide slide, void Function(Slide) onUpdate) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: CockpitEditor(
        slide: slide,
        onUpdate: onUpdate,
        themeAnimationDurationMs: kThemeDefaultAnimationDurationMs,
      ),
    ),
  );

  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // A slide with exactly [meters] cockpit meters, so field targeting is
  // unambiguous.
  Slide cockpitSlide(List<CockpitMeterSpec> meters) => Slide.create(
    SlideType.cockpit,
  ).copyWith(customMarkdown: CockpitSpec(meters: meters).toBlock());

  CockpitSpec parseUpdate(Slide slide) =>
      CockpitSpec.parse(slide.customMarkdown);

  testWidgets('editing the slide title emits an updated title', (tester) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Risico')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Cockpit-titel');
    await tester.pump();

    expect(updated, isNotNull);
    expect(updated!.title, 'Cockpit-titel');
  });

  testWidgets('adding a meter appends one and emits it', (tester) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Risico')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    // One meter card to start with.
    expect(
      find.byType(DropdownButtonFormField<CockpitMeterType>),
      findsOneWidget,
    );

    await tester.tap(find.text('Meter toevoegen'));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(parseUpdate(updated!).meters.length, 2);
    expect(
      find.byType(DropdownButtonFormField<CockpitMeterType>),
      findsNWidgets(2),
    );
  });

  testWidgets('removing a meter drops it', (tester) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [
          CockpitMeterSpec(label: 'Een'),
          CockpitMeterSpec(label: 'Twee'),
        ]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    // Two cards -> two delete buttons; remove the first.
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    final meters = parseUpdate(updated!).meters;
    expect(meters.length, 1);
    expect(meters.single.label, 'Twee');
  });

  testWidgets('changing a meter type re-emits with the new type', (
    tester,
  ) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Risico')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<CockpitMeterType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltmeter').last);
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(
      parseUpdate(updated!).meters.single.type,
      CockpitMeterType.voltmeter,
    );
  });

  testWidgets('editing value and unit re-emits them', (tester) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Risico', value: 50)]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Waarde'), '72');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Eenheid'), 'pt');
    await tester.pump();

    expect(updated, isNotNull);
    final meter = parseUpdate(updated!).meters.single;
    expect(meter.value, 72);
    expect(meter.unit, 'pt');
  });

  testWidgets('editing the range bounds re-emits min and max', (tester) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Risico')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    // The range fields sit inside a collapsed "advanced" section.
    await tester.tap(find.text('Bereik en kleurzones'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Min'), '10');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Max'), '200');
    await tester.pump();

    expect(updated, isNotNull);
    final meter = parseUpdate(updated!).meters.single;
    expect(meter.min, 10);
    expect(meter.max, 200);
  });

  testWidgets('toggling "animate on enter" flips the flag and shows the '
      'duration control', (tester) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Risico')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    // Default is animateOnEnter == true; turn it off.
    await tester.tap(
      find.widgetWithText(FilterChip, 'Animeren bij binnenkomst'),
    );
    await tester.pumpAndSettle();
    expect(updated, isNotNull);
    expect(parseUpdate(updated!).animateOnEnter, isFalse);

    // Turning it back on reveals the animation-duration slider.
    await tester.tap(
      find.widgetWithText(FilterChip, 'Animeren bij binnenkomst'),
    );
    await tester.pumpAndSettle();
    expect(parseUpdate(updated!).animateOnEnter, isTrue);
    expect(find.byType(Slider), findsWidgets);
  });

  testWidgets('the horizon type swaps in pitch and bank fields', (
    tester,
  ) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Stand')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<CockpitMeterType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kunstmatige horizon').last);
    await tester.pumpAndSettle();

    expect(parseUpdate(updated!).meters.single.type, CockpitMeterType.horizon);
    // Pitch/bank fields are now present; editing pitch re-emits it.
    await tester.enterText(find.widgetWithText(TextFormField, 'Pitch'), '15');
    await tester.pump();
    expect(parseUpdate(updated!).meters.single.pitch, 15);
    expect(find.widgetWithText(TextFormField, 'Bank'), findsOneWidget);
  });

  testWidgets('the heading type swaps in target and marker fields', (
    tester,
  ) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(
        cockpitSlide(const [CockpitMeterSpec(label: 'Richting')]),
        (s) => updated = s,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<CockpitMeterType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koers').last);
    await tester.pumpAndSettle();

    expect(parseUpdate(updated!).meters.single.type, CockpitMeterType.heading);
    await tester.enterText(find.widgetWithText(TextFormField, 'Doel'), '90');
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Markeringslabel'),
      'Noord',
    );
    await tester.pump();
    final meter = parseUpdate(updated!).meters.single;
    expect(meter.heading, 90);
    expect(meter.markerLabel, 'Noord');
    expect(tester.takeException(), isNull);
  });
}
