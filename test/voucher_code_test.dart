import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/voucher_code.dart';

void main() {
  // Vaste code, op dezelfde manier als de server gegenereerd: tien bytes
  // entropie (0x01..0x0a), Crockford-payload plus SHA-256-checksum.
  const valid = 'OCVO-0410-6105-0R3G-G28A-S0';
  const other = 'OCVO-0W3G-E1R7-0W3G-E1R7-QW';

  test('accepteert de canonieke vorm en is hoofdletterongevoelig', () {
    expect(hasValidVoucherChecksum(valid), isTrue);
    expect(hasValidVoucherChecksum(other), isTrue);
    expect(hasValidVoucherChecksum(valid.toLowerCase()), isTrue);
    expect(hasValidVoucherChecksum('  $valid  '), isTrue);
    // Spaties mogen tussen tekens staan, net als streepjes ontbreken.
    expect(hasValidVoucherChecksum('OCVO 0410 6105 0R3G G28A S0'), isTrue);
    expect(hasValidVoucherChecksum('OCVO041061050R3GG28AS0'), isTrue);
  });

  test('Crockford-transcriptiefixes gelden alleen voor de payload', () {
    // O→0, I/L→1 in de payload; het voorvoegsel blijft letterlijk OCVO.
    expect(hasValidVoucherChecksum('OCVO-O4IO-6IO5-OR3G-G28A-S0'), isTrue);
    expect(hasValidVoucherChecksum('OCVO-O4LO-6LO5-OR3G-G28A-S0'), isTrue);
    // Een verkeerde lezing (bijv. G→9 of O die géén 0 is) faalt.
    expect(hasValidVoucherChecksum('OCVO-O41O-61O5-ORG9-G28A-S0'), isFalse);
  });

  test('een typefout in de checksum of payload faalt lokaal', () {
    expect(hasValidVoucherChecksum('OCVO-0410-6105-0R3G-G28A-S1'), isFalse);
    expect(hasValidVoucherChecksum('OCVO-0410-6105-0R3G-G28B-S0'), isFalse);
    expect(hasValidVoucherChecksum('OCVO-0410-6105-0R3G-G28A'), isFalse);
    expect(hasValidVoucherChecksum('OCVO-0410-6105-0R3G-G28A-S'), isFalse);
    expect(hasValidVoucherChecksum('OCVO-0410'), isFalse);
  });

  test('zonder OCVO-voorvoegsel is het geen vouchercode', () {
    expect(hasValidVoucherChecksum('0410-6105-0R3G-G28A-S0'), isFalse);
    expect(hasValidVoucherChecksum('OCSC-0410-6105-0R3G-G28A-S0'), isFalse);
    expect(hasValidVoucherChecksum(''), isFalse);
  });

  test('verboden Crockford-tekens falen', () {
    // 'U' zit niet in het alfabet.
    expect(hasValidVoucherChecksum('OCVO-0410-6105-0R3G-G28A-SU'), isFalse);
  });

  test('formatVoucherCode geeft de canonieke gegroepeerde vorm', () {
    expect(formatVoucherCode(valid), valid);
    expect(formatVoucherCode(valid.toLowerCase()), valid);
    expect(formatVoucherCode('OCVO041061050R3GG28AS0'), valid);
    expect(formatVoucherCode('nope'), isNull);
  });

  test('normalizeVoucherCode levert payload+check zonder voorvoegsel', () {
    expect(normalizeVoucherCode(valid), '041061050R3GG28AS0');
    expect(normalizeVoucherCode('geen-code'), isNull);
  });
}
