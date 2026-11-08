import 'package:archive/archive.dart';

/// Gegooid door een capped output-stream zodra een uitgepakte entry voorbij
/// zijn byte-budget groeit — het teken dat het (geneste) archief een
/// decompressiebom is.
///
/// Eén gedeeld type: voorheen stond deze klasse identiek in
/// `file_service_package.dart` en `cve_bulk_ingest.dart`, met een commentaar die
/// het duplicaat al erkende. Beide plekken vangen decompressiebommen af; één
/// type houdt die grens op één plek.
class ExtractionLimitException implements Exception {
  const ExtractionLimitException();
}

/// Stops inflation before an entry can allocate beyond its output budget.
class CappedArchiveOutput extends OutputMemoryStream {
  CappedArchiveOutput(this.limit);
  final int limit;
  void _guard(int count) {
    if (count > limit - length) throw const ExtractionLimitException();
  }

  @override
  void writeByte(int value) {
    _guard(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _guard(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _guard(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _guard(count);
    super.writeBackReference(distance, count);
  }
}

/// Uses the streaming inflater on every platform, including browser builds.
///
/// Dit pad leest de ruwe stroom en slaat daarmee de controles over die
/// `ZipFile` zelf doet — de `verify`/`throwOnError` van de decoder bereiken het
/// niet. Een afgekapt of beschadigd lid leverde zo stil een stuk inhoud op.
/// Daarom toetst het hier zelf of de inflater het slotblok haalde, en of de
/// uitkomst de grootte en CRC-32 heeft die de centrale map belooft.
void writeArchiveEntryCapped(ArchiveFile file, CappedArchiveOutput output) {
  final raw = file.rawContent;
  if (raw is! ZipFile) {
    file.writeContent(output);
    return;
  }
  final compressed = raw.getStream(decompress: false);
  switch (file.compression) {
    case CompressionType.deflate:
      final inflate = Inflate.stream(
        compressed,
        output: output,
        throwOnError: true,
      );
      if (!inflate.isFinished) {
        throw const FormatException('Truncated deflate entry');
      }
    case CompressionType.bzip2:
      BZip2Decoder().decodeStream(
        compressed,
        output,
        verify: true,
        throwOnError: true,
      );
    case CompressionType.none:
      output.writeStream(compressed);
    case CompressionType.zstd ||
        CompressionType.lzma ||
        CompressionType.xz ||
        null:
      throw const FormatException('Unsupported ZIP compression');
  }
  // AES (AE-2) draagt geen CRC; daar heeft `getStream` de MAC al gecontroleerd.
  if (output.length != raw.uncompressedSize ||
      (raw.hasCrc32 && getCrc32(output.getBytes()) != raw.crc32)) {
    throw const FormatException('ZIP entry does not match its size or CRC-32');
  }
}
