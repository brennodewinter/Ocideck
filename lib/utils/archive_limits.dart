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
void writeArchiveEntryCapped(ArchiveFile file, CappedArchiveOutput output) {
  final raw = file.rawContent;
  if (raw is! ZipFile) {
    file.writeContent(output);
    return;
  }
  final compressed = raw.getStream(decompress: false);
  switch (file.compression) {
    case CompressionType.deflate:
      Inflate.stream(compressed, output: output);
    case CompressionType.bzip2:
      if (!BZip2Decoder().decodeStream(compressed, output)) {
        throw const FormatException('Invalid BZip2 entry');
      }
    case CompressionType.none:
      output.writeStream(compressed);
    case null:
      throw const FormatException('Unknown ZIP compression');
  }
}
