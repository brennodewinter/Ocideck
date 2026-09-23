import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/editors/markdown_smart_input_formatter.dart';

/// Simuleert één getypte Enter na [line]: de cursor stond aan het einde van
/// die regel en `\n` kwam erachter.
TextEditingValue pressEnterAfter(String line) {
  final before = TextEditingValue(
    text: line,
    selection: TextSelection.collapsed(offset: line.length),
  );
  final after = TextEditingValue(
    text: '$line\n',
    selection: TextSelection.collapsed(offset: line.length + 1),
  );
  return const MarkdownSmartInputFormatter().formatEditUpdate(before, after);
}

void main() {
  group('MarkdownSmartInputFormatter regelvervolg', () {
    test('Enter na een taak zet een nieuwe taak voort', () {
      final result = pressEnterAfter('- [ ] eerste');
      expect(result.text, '- [ ] eerste\n- [ ] ');
      expect(result.selection.baseOffset, '- [ ] eerste\n- [ ] '.length);
    });

    test('Enter na een afgevinkte taak zet een open taak voort', () {
      final result = pressEnterAfter('- [x] klaar');
      expect(result.text, '- [x] klaar\n- [ ] ');
    });

    test('Enter op een lege taakruimte ruimt de markering op', () {
      final result = pressEnterAfter('- [ ] ');
      expect(result.text.trim(), isEmpty);
    });

    test('Enter na een gewone bullet blijft een bullet voortzetten', () {
      final result = pressEnterAfter('- item');
      expect(result.text, '- item\n- ');
    });

    test('Enter na een nummering verhoogt het nummer', () {
      final result = pressEnterAfter('2. stap');
      expect(result.text, '2. stap\n3. ');
    });
  });
}
