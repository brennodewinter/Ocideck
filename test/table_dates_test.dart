import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/table_dates.dart';

void main() {
  group('parseIsoDateCell', () {
    test('reads a strict ISO date, with surrounding whitespace', () {
      expect(parseIsoDateCell('2026-08-15'), DateTime(2026, 8, 15));
      expect(parseIsoDateCell('  2026-08-15 '), DateTime(2026, 8, 15));
    });

    test('refuses anything that is not yyyy-mm-dd', () {
      // 05-08-2026 is twee verschillende dagen afhankelijk van wie het typte;
      // een deadline is een slechte plek om te gokken.
      expect(parseIsoDateCell('05-08-2026'), isNull);
      expect(parseIsoDateCell('2026/08/15'), isNull);
      expect(parseIsoDateCell('15 augustus 2026'), isNull);
      expect(parseIsoDateCell('open'), isNull);
      expect(parseIsoDateCell(''), isNull);
      // Geen datum midden in een zin: alleen een cel die niets anders draagt.
      expect(parseIsoDateCell('af op 2026-08-15'), isNull);
    });

    test('refuses a date that does not exist', () {
      // DateTime rolt 31 februari stilzwijgend door naar maart; die stilte is
      // precies wat hier niet mag.
      expect(parseIsoDateCell('2026-02-31'), isNull);
      expect(parseIsoDateCell('2026-13-01'), isNull);
      expect(parseIsoDateCell('2026-00-10'), isNull);
      // Een schrikkeldag die wél bestaat, blijft geldig.
      expect(parseIsoDateCell('2024-02-29'), DateTime(2024, 2, 29));
      expect(parseIsoDateCell('2026-02-29'), isNull);
    });
  });

  group('isPastDateCell', () {
    final asOf = DateTime(2026, 7, 20);

    test('a date before today is past', () {
      expect(isPastDateCell('2026-07-19', asOf), isTrue);
      expect(isPastDateCell('2020-01-01', asOf), isTrue);
    });

    test('today itself is not past — it is still today', () {
      expect(isPastDateCell('2026-07-20', asOf), isFalse);
    });

    test('the time within the day does not matter', () {
      expect(
        isPastDateCell('2026-07-20', DateTime(2026, 7, 20, 23, 59)),
        isFalse,
      );
    });

    test('a future date and a non-date are never past', () {
      expect(isPastDateCell('2026-07-21', asOf), isFalse);
      expect(isPastDateCell('open', asOf), isFalse);
      expect(isPastDateCell('', asOf), isFalse);
    });
  });
}
