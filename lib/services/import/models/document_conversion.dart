/// Wat een document-importeur (DOCX/ODT) oplevert, naast de Markdown zelf.
///
/// De importeurs blijven headless: ze leveren de afbeeldings-*bytes* mee,
/// niet een pad. Pas de servicelaag beslist waar die bytes landen — de
/// `mem:`-store op web en tussentijds op desktop, de projectmap bij opslag.
/// Dat is hetzelfde contract als [SourceImage] bij de presentatie-import.
library;

import 'dart:typed_data';

/// Eén afbeelding uit het bronpakket: de bytes, een veilige bestandsnaam, en
/// de verwijzing zoals die in de opgeleverde Markdown staat.
class ImportedDocumentImage {
  const ImportedDocumentImage({
    required this.ref,
    required this.name,
    required this.bytes,
    this.alt = '',
  });

  /// De verwijzing die in de Markdown staat — het archiefpad zoals
  /// `word/media/image1.png` of `Pictures/foto.jpg`. Hij is alleen een
  /// sleutel: de servicelaag herschrijft hem naar een echt pad en hij
  /// bereikt nooit het bestand van de gebruiker.
  final String ref;

  /// Veilige bestandsnaam voor de assetlaag (`normalizeImageFileName`, met
  /// de extensie die de bytes zelf verklappen).
  final String name;

  /// De afbeeldingsbytes, al aan de magic-bytecontrole voorbij.
  final Uint8List bytes;

  /// Alt-tekst uit de bron (bijschrift, objectnaam), gesaneerd voor
  /// Markdown — geen blokhaken, geen regeleinden.
  final String alt;

  /// Het letterlijke `![alt](ref)`-token zoals de importeur het in de
  /// Markdown zette. De servicelaag vervangt deze string, dus wat er ook
  /// verandert aan het pad — de Markdown blijft geldig.
  String get emitted => '![$alt]($ref)';
}

/// De uitkomst van `convertDocxDetailed`/`convertOdtDetailed`: de Markdown,
/// de mee te nemen afbeeldingen en wat er níet meekwam.
class DocumentConversion {
  const DocumentConversion({
    required this.markdown,
    this.images = const [],
    this.notImported = const [],
  });

  /// De omgezette documenttekst, met `![alt](ref)`-verwijzingen naar
  /// [images] op de plek waar de afbeelding stond.
  final String markdown;

  /// De afbeeldingen waar [markdown] naar verwijst.
  final List<ImportedDocumentImage> images;

  /// Soorten inhoud die niet meekwamen, één sleutel per weggevallen element:
  /// `'afbeelding'` (onleesbaar, ontbrekend of niet weergeefbaar formaat),
  /// `'tekstkader'`, `'groep'` en `'object'`. De UI telt en vertaalt ze;
  /// de importeur zelf kent geen vertaling.
  final List<String> notImported;
}
