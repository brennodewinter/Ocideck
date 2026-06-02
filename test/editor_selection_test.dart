import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/editor_provider.dart';

void main() {
  group('EditorNotifier multi-selection', () {
    test('select is single and clears any multi-selection', () {
      final n = EditorNotifier();
      n.selectAll(5);
      n.select(2);
      expect(n.currentState.selectedIndex, 2);
      expect(n.currentState.selection, {2});
      expect(n.currentState.hasMultiSelection, isFalse);
    });

    test('toggleSelect adds and removes, keeping a non-empty set', () {
      final n = EditorNotifier()..select(1);
      n.toggleSelect(3);
      expect(n.currentState.selection, {1, 3});
      expect(n.currentState.selectedIndex, 3); // clicked becomes active

      n.toggleSelect(3); // remove again
      expect(n.currentState.selection, {1});
      expect(n.currentState.selectedIndex, 1);
    });

    test('toggleSelect never empties the selection', () {
      final n = EditorNotifier()..select(2);
      n.toggleSelect(2); // would remove the only one
      expect(n.currentState.selection, {2});
    });

    test('selectRange selects an inclusive range from the anchor', () {
      final n = EditorNotifier()..select(2);
      n.selectRange(5);
      expect(n.currentState.selection, {2, 3, 4, 5});
      expect(n.currentState.selectedIndex, 5);
    });

    test('selectRange works backwards too', () {
      final n = EditorNotifier()..select(5);
      n.selectRange(2);
      expect(n.currentState.selection, {2, 3, 4, 5});
      expect(n.currentState.selectedIndex, 2);
    });

    test('selectAll selects every slide', () {
      final n = EditorNotifier()..select(1);
      n.selectAll(4);
      expect(n.currentState.selection, {0, 1, 2, 3});
    });

    test('clampIndex prunes selection beyond the new max', () {
      final n = EditorNotifier()..selectAll(6); // {0..5}
      n.clampIndex(3);
      expect(n.currentState.selection, {0, 1, 2, 3});
      expect(n.currentState.selectedIndex, lessThanOrEqualTo(3));
    });
  });
}
