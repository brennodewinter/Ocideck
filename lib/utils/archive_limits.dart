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
