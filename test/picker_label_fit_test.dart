import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';

/// The room a type card leaves its label: 100px wide, 8px padding either side.
const _cardLabelWidth = 84.0;

double _fitted(String label) => _fittedAt(label, _cardLabelWidth);

double _fittedAt(String label, double width) =>
    FittedTypeLabel.fittedFontSize(label, width, TextDirection.ltr);

/// The narrowest width at which [label] still renders at full size — i.e. how
/// much room its longest word needs. Found by bisection so the test never
/// depends on the metrics of whatever font it happens to run in.
double _widthNeeded(String label) {
  var lo = 0.0;
  var hi = 5000.0;
  while (hi - lo > 0.5) {
    final mid = (lo + hi) / 2;
    if (_fittedAt(label, mid) == FittedTypeLabel.baseFontSize) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

void main() {
  // NB: widget tests render in Ahem, where every glyph is a full em square —
  // far wider than any real font. So these assert the *mechanism* against
  // widths derived from the measurement itself, not against hard-coded pixel
  // sizes that would only hold for one font.
  group('FittedTypeLabel.fittedFontSize', () {
    test('nothing shrinks when there is room', () {
      // The common case on a real screen: the step-down is the exception.
      for (final label in [
        'Quote',
        'Aanvalsoppervlak',
        'Acties en besluiten',
      ]) {
        expect(_fittedAt(label, 10000), FittedTypeLabel.baseFontSize);
      }
    });

    test('only the longest word decides, so spaces are free', () {
      // "Acties en besluiten" is far wider than "Aanvalsoppervlak" as one line,
      // yet needs *less* room, because it may break at its spaces. That is what
      // keeps a two-word label at full size while a compound steps down.
      expect(
        _widthNeeded('Acties en besluiten'),
        lessThan(_widthNeeded('Aanvalsoppervlak')),
      );
    });

    test('a word wider than the card steps the label down', () {
      // The bug this guards: "Aanvalsoppervlak" rendered as
      // "Aanvalsopperv / lak", which reads as a typo rather than a line break.
      final tight = _widthNeeded('Aanvalsoppervlak') - 1;
      expect(
        _fittedAt('Aanvalsoppervlak', tight),
        lessThan(FittedTypeLabel.baseFontSize),
      );
    });

    test('the step-down stops at the readable floor', () {
      expect(
        _fittedAt('Buitengewoonlangesamenstelling', 1),
        FittedTypeLabel.minFontSize,
      );
    });

    test('every registered type label fits its card', () {
      // Guards the whole set at once, so a future type with a long name is
      // caught here rather than on someone's screen.
      for (final entry in slideTypeMeta.entries) {
        expect(
          _fitted(entry.value.label),
          greaterThanOrEqualTo(FittedTypeLabel.minFontSize),
          reason: 'label of ${entry.key.name} cannot be fitted',
        );
      }
    });
  });

  testWidgets('the card renders the label at the fitted size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _cardLabelWidth,
              child: FittedTypeLabel(label: 'Aanvalsoppervlak'),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Aanvalsoppervlak'));
    expect(text.style?.fontSize, lessThan(FittedTypeLabel.baseFontSize));
    expect(text.maxLines, 2);
    // A label that still will not fit is cut, never spilled over the card.
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
