import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:test/test.dart';

void main() {
  group('FormIssueCode', () {
    test('wire names are unique, kebab-case and round-trip', () {
      final seen = <String>{};
      for (final code in FormIssueCode.values) {
        expect(code.wireName, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')));
        expect(seen.add(code.wireName), isTrue, reason: code.wireName);
        expect(FormIssueCode.fromWire(code.wireName), same(code));
      }
    });

    test('an unknown wire name is null, not an exception', () {
      expect(FormIssueCode.fromWire('no-such-code'), isNull);
      expect(FormIssueCode.fromWire(''), isNull);
      expect(FormIssueCode.fromWire('Rule-Malformed'), isNull);
    });

    test('default severities follow FORM_INTAKE.md', () {
      // Warnings and info are the exceptions; everything else blocks.
      const notErrors = {
        'image-too-small': FormSeverity.warning,
        'image-heic-unverified': FormSeverity.warning,
        'image-unexpected-faces': FormSeverity.info,
        'form-version-mismatch': FormSeverity.warning,
        'notice-missing': FormSeverity.warning,
        'form-attribute-missing': FormSeverity.warning,
        'unknown-marker': FormSeverity.warning,
        'unknown-rule': FormSeverity.info,
      };
      for (final code in FormIssueCode.values) {
        expect(
          code.severity,
          notErrors[code.wireName] ?? FormSeverity.error,
          reason: code.wireName,
        );
      }
    });
  });

  group('FormProblem', () {
    test('takes its severity from the code unless told otherwise', () {
      expect(FormProblem(FormIssueCode.ruleMalformed).isError, isTrue);
      expect(FormProblem(FormIssueCode.unknownRule).isError, isFalse);
      expect(
        FormProblem(
          FormIssueCode.ruleMalformed,
          severity: FormSeverity.warning,
        ).isError,
        isFalse,
      );
    });

    test('toString names the code, the line, the field and the facts', () {
      final text = FormProblem(
        FormIssueCode.ruleMalformed,
        line: 7,
        fieldId: 'verhaal',
        facts: {'rule': 'words'},
      ).toString();
      expect(text, contains('rule-malformed'));
      expect(text, contains('line 7'));
      expect(text, contains('verhaal'));
      expect(text, contains('words'));
    });

    test('a bare problem prints just its code', () {
      expect(
        FormProblem(FormIssueCode.noticeMissing).toString(),
        'notice-missing',
      );
    });
  });
}
