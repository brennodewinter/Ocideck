import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/slide.dart';
import '../../utils/log.dart';
import '../file_service.dart';
import '../image_service.dart';
import '../package_asset_resolver.dart';
import '../web_asset_store.dart';
import 'presentation_source.dart';
import 'remote_file_client.dart';

/// Doorzoekt een remote bestandsopslag (WebDAV of S3) op presentaties.
///
/// Loopt de mappenboom recursief af en leest twee soorten vondsten:
///
/// - een los `.md`-bestand: de markdown gaat door dezelfde veiligheidspoort als
///   elk ander open ([FileService.openDeckFromContent]), en de afbeeldingen
///   waar de slides naar wijzen worden er los bij opgehaald en als in-geheugen
///   `mem:`-pad aangehaakt;
/// - een `.ocideck`-pakket: in het geheugen uitgepakt met de gedeelde,
///   zip-bom-bestendige decoder, waarna de meegeleverde afbeeldingen via
///   [attachPackageAssetsToMem] worden aangehaakt.
///
/// Alles blijft in het geheugen: een scan raakt nooit het bestandssysteem. Een
/// onleesbare map of een geweigerd deck slaat over in plaats van de hele scan
/// te laten falen — één kapot bestand hoort de rest niet mee te nemen.
class RemotePresentationSource implements PresentationSource {
  RemotePresentationSource({
    required this.client,
    required this.fileService,
    required this.label,
    required this.pathPrefix,
    this.maxFiles = 200,
    this.maxDepth = 6,
  });

  final RemoteFileClient client;
  final FileService fileService;

  @override
  final String label;

  /// Voorvoegsel voor de synthetische identiteit van een vondst, bijv.
  /// `webdav:<verbinding-id>`. Houdt treffers uit verschillende verbindingen
  /// uit elkaar bij het ontdubbelen.
  final String pathPrefix;

  /// Plafond op het aantal in te lezen presentaties, als rem op een uitschieter.
  /// Overschrijding wordt gelogd, niet stil afgekapt.
  final int maxFiles;

  /// Hoe diep de mappenboom wordt afgelopen. Een remote bibliotheek is zelden
  /// dieper; dit voorkomt dat een lus of een gigantische boom de scan gijzelt.
  final int maxDepth;

  @override
  Future<List<ScannedPresentation>> scan() async {
    final found = await _collect();
    final out = <ScannedPresentation>[];
    for (final entry in found) {
      final scanned = entry.isPackage
          ? await _readPackage(entry)
          : await _readMarkdown(entry);
      if (scanned != null) out.add(scanned);
    }
    return out;
  }

  /// Breedte-eerst door de boom, tot [maxDepth] diep en [maxFiles] vondsten.
  /// Een map die niet opgesomd kan worden wordt gemeld en overgeslagen.
  Future<List<RemoteFileEntry>> _collect() async {
    final found = <RemoteFileEntry>[];
    var level = <String>[''];
    for (var depth = 0; depth <= maxDepth && level.isNotEmpty; depth++) {
      final next = <String>[];
      for (final dir in level) {
        if (found.length >= maxFiles) break;
        final List<RemoteFileEntry> entries;
        try {
          entries = await client.list(dir);
        } catch (e) {
          logWarning(
            'RemotePresentationSource: map onleesbaar ($label: $dir)',
            e,
          );
          continue;
        }
        for (final entry in entries) {
          if (entry.isDirectory) {
            next.add(entry.path);
          } else if (entry.isMarkdown || entry.isPackage) {
            if (found.length >= maxFiles) {
              logWarning(
                'RemotePresentationSource: scan afgekapt op $maxFiles '
                'presentaties ($label)',
              );
              break;
            }
            found.add(entry);
          }
        }
      }
      if (found.length >= maxFiles) break;
      level = next;
    }
    return found;
  }

  Future<ScannedPresentation?> _readMarkdown(RemoteFileEntry entry) async {
    try {
      final bytes = await client.download(entry.path);
      if (bytes.length > FileService.maxDeckMarkdownBytes) return null;
      final String raw;
      try {
        raw = utf8.decode(bytes);
      } on FormatException catch (e) {
        logWarning(
          'RemotePresentationSource: geen geldige UTF-8 (${entry.path})',
          e,
        );
        return null;
      }
      final parsed = fileService.openDeckFromContent(
        raw,
        sourceName: '$label · ${entry.name}',
      );
      final deck = parsed.deck;
      if (deck == null) return null;
      final withImages = await _attachRemoteImages(deck, entry.path);
      return _scanned(entry, withImages, raw);
    } catch (e) {
      logWarning('RemotePresentationSource: onleesbaar (${entry.path})', e);
      return null;
    }
  }

  Future<ScannedPresentation?> _readPackage(RemoteFileEntry entry) async {
    try {
      final bytes = await client.download(entry.path);
      // Een versleuteld pakket vraagt om een wachtwoord; daar is een scan de
      // plek niet voor. Overslaan is eerlijker dan de gebruiker midden in een
      // zoekactie om wachtwoorden vragen.
      if (FileService.isEncryptedPackage(bytes)) return null;
      final entries = fileService.decodePackageEntries(bytes);
      if (entries == null) return null;
      final mdEntry = FileService.mainMarkdownEntry(entries);
      if (mdEntry == null) return null;
      final String raw;
      try {
        raw = utf8.decode(mdEntry.bytes);
      } on FormatException catch (e) {
        logWarning(
          'RemotePresentationSource: pakket-md niet UTF-8 (${entry.path})',
          e,
        );
        return null;
      }
      final parsed = fileService.openDeckFromContent(
        raw,
        sourceName: '$label · ${entry.name} → ${mdEntry.name}',
      );
      final deck = parsed.deck;
      if (deck == null) return null;
      return _scanned(
        entry,
        attachPackageAssetsToMem(deck, entries, mdEntry.name),
        raw,
      );
    } catch (e) {
      logWarning(
        'RemotePresentationSource: pakket onleesbaar (${entry.path})',
        e,
      );
      return null;
    }
  }

  ScannedPresentation _scanned(RemoteFileEntry entry, Deck deck, String raw) =>
      ScannedPresentation(
        path: '$pathPrefix/${entry.path}',
        fileName: entry.name,
        deck: deck,
        content: raw,
      );

  /// Haal de afbeeldingen op waar een los `.md` naar verwijst en hang ze als
  /// `mem:`-pad aan het deck. Verwijzingen zijn relatief aan de map van het
  /// markdown-bestand; een pad dat met `../` buiten de wortel wijst, een
  /// absoluut pad en een URL worden niet gevolgd.
  ///
  /// Een afbeelding die niet op te halen is of geen afbeelding blijkt wordt
  /// overgeslagen: het deck komt dan met een placeholder binnen, net als een
  /// pakket met een kapotte verwijzing.
  Future<Deck> _attachRemoteImages(Deck deck, String mdPath) async {
    final baseDir = p.posix.dirname(mdPath);
    final memFor = <String, String>{};
    Future<String?> memPath(String ref) async {
      final trimmed = ref.trim();
      if (trimmed.isEmpty ||
          WebAssetStore.isMemPath(trimmed) ||
          p.isAbsolute(trimmed) ||
          trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('data:')) {
        return null;
      }
      final resolved = p.posix.normalize(
        baseDir == '.' ? trimmed : p.posix.join(baseDir, trimmed),
      );
      if (resolved.startsWith('..')) return null; // buiten de wortel
      final cached = memFor[resolved];
      if (cached != null) return cached;
      try {
        final bytes = await client.download(resolved);
        if (bytes.isEmpty ||
            bytes.length > ImageService.maxImageBytes ||
            !ImageService.looksLikeImage(bytes)) {
          return null;
        }
        final mem = WebAssetStore.put(bytes, name: p.posix.basename(resolved));
        memFor[resolved] = mem;
        return mem;
      } catch (e) {
        logWarning(
          'RemotePresentationSource: afbeelding onbereikbaar ($resolved)',
          e,
        );
        return null;
      }
    }

    final slides = <Slide>[];
    for (final slide in deck.slides) {
      slides.add(
        slide.copyWith(
          imagePath: await memPath(slide.imagePath) ?? slide.imagePath,
          imagePath2: await memPath(slide.imagePath2) ?? slide.imagePath2,
        ),
      );
    }
    return memFor.isEmpty ? deck : deck.copyWith(slides: slides);
  }
}
