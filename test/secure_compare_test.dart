import 'package:ocideck/utils/secure_compare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('constantTimeEqualsBytes', () {
    test('gelijke bytes retourneren true', () {
      expect(constantTimeEqualsBytes([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('ongelijke bytes retourneren false', () {
      expect(constantTimeEqualsBytes([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('verschillende lengte retourneert false', () {
      expect(constantTimeEqualsBytes([1, 2], [1, 2, 3]), isFalse);
    });

    test('lege lijsten retourneren true', () {
      expect(constantTimeEqualsBytes([], []), isTrue);
    });

    test('enkele byte verschil retourneert false', () {
      expect(constantTimeEqualsBytes([0], [1]), isFalse);
    });
  });

  group('constantTimeEqualsString', () {
    test('gelijke strings retourneren true', () {
      expect(
        constantTimeEqualsString(
          'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b27721bf48c5e',
          'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b27721bf48c5e',
        ),
        isTrue,
      );
    });

    test('ongelijke strings retourneren false', () {
      expect(
        constantTimeEqualsString(
          'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b27721bf48c5e',
          'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b27721bf48c5f',
        ),
        isFalse,
      );
    });

    test('verschillende lengte retourneert false', () {
      expect(constantTimeEqualsString('abc', 'abcd'), isFalse);
    });

    test('lege strings retourneren true', () {
      expect(constantTimeEqualsString('', ''), isTrue);
    });

    test('hoofdletterverschil retourneert false', () {
      expect(constantTimeEqualsString('ABC', 'abc'), isFalse);
    });
  });
}
