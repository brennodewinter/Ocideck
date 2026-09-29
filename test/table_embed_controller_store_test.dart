import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart' show TableAlign;
import 'package:ocideck/widgets/markdown_editor/table_embed_binding.dart';

/// De bewaarplaats van tabelcontrollers achter de visuele embeds.
///
/// De testcase die er toe deed: een embed die op dezelfde documentpositie van
/// widgettype wisselt (tabel ↔ tijdlijn). De nieuwe widget obtaint de entry
/// vóórdat de oude zijn `dispose` — en dus zijn `release` — draait: een
/// uitgeschakelde widget wordt pas aan het einde van de frame ontmanteld.
/// Beide delen dan dezelfde controller. De late vrijgave mocht die gedeelde
/// controller niet opruimen, maar deed dat wél — de net gemonteerde cellen
/// bleven achter met gedode focusnodes ("FocusNode was used after being
/// disposed").
void main() {
  const gfm = '| A | B |\n|---|---|\n| 1 | 2 |';

  void onChanged(List<List<String>> rows, List<TableAlign> aligns) {}

  /// Draait de uitgestelde vrijgave: `tester.pump()` laat post-frame
  /// callbacks in deze testbinding liggen; begin+draw voert ze wel uit.
  void pumpFrame(WidgetTester tester) {
    tester.binding.handleBeginFrame(Duration.zero);
    tester.binding.handleDrawFrame();
  }

  testWidgets(
    'release van de oude eigenaar laat een her-adopteerde controller leven',
    (tester) async {
      final store = TableEmbedControllerStore();
      addTearDown(store.dispose);

      final first = store.obtain(
        10,
        gfm,
        onChanged: onChanged,
        onCellFocused: null,
      );
      // De opvolger obtaint dezelfde plek vóór de ontmanteling van de
      // voorganger — en erft daarmee dezelfde controller.
      final second = store.obtain(
        10,
        gfm,
        onChanged: onChanged,
        onCellFocused: null,
      );
      expect(identical(second.controller, first.controller), isTrue);

      // Pas nu ruimt de oude widget op: ná de adoptie.
      store.release(10, first.controller, first.token);
      pumpFrame(tester);

      // De gedeelde controller moet heel blijven — anders hangen de cellen
      // van de nieuwe widget aan gedode focusnodes.
      expect(
        () => first.controller.focusNode(0, 0).addListener(() {}),
        returnsNormally,
      );
      expect(() => first.controller.addListener(() {}), returnsNormally);
    },
  );

  testWidgets('release ruimt op wanneer niemand de entry adopteerde', (
    tester,
  ) async {
    final store = TableEmbedControllerStore();
    addTearDown(store.dispose);

    final acquired = store.obtain(
      10,
      gfm,
      onChanged: onChanged,
      onCellFocused: null,
    );
    store.release(10, acquired.controller, acquired.token);
    pumpFrame(tester);

    expect(() => acquired.controller.addListener(() {}), throwsAssertionError);
  });
}
