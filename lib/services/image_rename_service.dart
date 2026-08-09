import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/log.dart';
import 'caption_service.dart';
import 'description_service.dart';
import 'image_reference_service.dart';

/// Uitkomst van een hernoemactie: het nieuwe pad bij succes, anders een
/// [RenameFailure] met de reden.
class RenameResult {
  final String? newPath;
  final RenameFailure? failure;
  final List<String> updatedDeckFiles;

  const RenameResult.success(this.newPath, {this.updatedDeckFiles = const []})
    : failure = null;
  const RenameResult.failed(this.failure)
    : newPath = null,
      updatedDeckFiles = const [];
}

enum RenameFailure { targetExists, renameFailed, sourceMissing }

/// Hernoemt een afbeeldingsbestand op schijf en houdt alles wat ernaar wijst
/// mee: Marp-verwijzingen in `.md`-bestanden op schijf, en caption- en
/// beschrijving-sidecars. De open-decks-sync (`onReplaceUsages`) blijft bij de
/// aanroeper — die heeft `WidgetRef` nodig en is geen bestandsoperatie.
///
/// Het blauwdruk is de dedup-flow (`_applyDedupePlan`): daar verplaatst een
/// kopie haar verwijzingen naar de keeper; hier verplaatst één bestand zijn
/// verwijzingen naar zijn eigen nieuwe naam. `ImageReferenceService` doet het
/// herschrijven; deze service orkestreert alleen.
class ImageRenameService {
  /// Geeft null als [stem] een geldige nieuwe bestandsnaam-stam is voor een
  /// afbeelding die nu [oldStem] heet; anders een reden waarom niet. Leeg of
  /// ongewijzigd is geen fout — de aanroeper hoort de knop uit te schakelen, en
  /// dit helpt daarbij door null terug te geven zodat "niets te doen" niet als
  /// fout wordt getoond.
  static RenameValidation validateStem(String stem, String oldStem) {
    final trimmed = stem.trim();
    if (trimmed.isEmpty) return RenameValidation.disabled;
    if (trimmed == oldStem) return RenameValidation.disabled;
    if (trimmed.contains('/') ||
        trimmed.contains('\\') ||
        trimmed.contains('\x00') ||
        trimmed == '.' ||
        trimmed == '..') {
      return RenameValidation.invalidName;
    }
    return RenameValidation.ok;
  }

  /// Het nieuwe pad: zelfde map als [oldPath], [newStem] + de extensie van
  /// [oldPath]. Publiek zodat de UI de doelnaap al vóór de actie kan tonen.
  static String destinationPath(String oldPath, String newStem) {
    final dir = p.dirname(oldPath);
    final ext = p.extension(oldPath);
    return p.normalize(p.join(dir, '$newStem$ext'));
  }

  /// Hernoemt [oldPath] naar een bestand met stam [newStem] (extensie blijft),
  /// herschrijft verwijzingen in [deckFiles] op schijf, en migreert de
  /// caption- en beschrijving-sidecar. Geeft het nieuwe pad terug bij succes.
  ///
  /// Weigert als de doelnaam al bestaat met andere inhoud — `File.rename`
  /// overschrijft op POSIX stil, en dat zou een andere afbeelding wissen.
  Future<RenameResult> rename({
    required String oldPath,
    required String newStem,
    required List<String> deckFiles,
    required CaptionService captionService,
    required DescriptionService descriptionService,
  }) async {
    final trimmedStem = newStem.trim();
    final dest = destinationPath(oldPath, trimmedStem);

    final src = File(oldPath);
    if (!src.existsSync()) {
      return const RenameResult.failed(RenameFailure.sourceMissing);
    }

    // Doel bestaat al: alleen veilig als het hetzelfde bestand is (geen
    // naamswijziging). Anders weigeren — `File.rename` overschrijft op POSIX
    // stil en dat zou een andere afbeelding wissen.
    final destFile = File(dest);
    if (destFile.existsSync() && !p.equals(oldPath, dest)) {
      return const RenameResult.failed(RenameFailure.targetExists);
    }

    try {
      await src.rename(dest);
    } catch (e, s) {
      logError('ImageRenameService.rename: file rename', e, s);
      return const RenameResult.failed(RenameFailure.renameFailed);
    }

    // Sidecar-migratie: caption en beschrijving verhuizen van de oude basename
    // naar de nieuwe. Beide sidecars staan in dezelfde map als de afbeelding,
    // dus dit is een key-wissel binnen één JSON-bestand. Lees- of
    // schrijffouten hier vallen niet terug op een al verplaatst bestand — de
    // afbeelding staat op de nieuwe naam, alleen de metadata ontbreekt dan.
    // Dat is erger dan nodig, maar nooit de verkeerde afbeelding; de
    // aanroeper kan het overnemen.
    try {
      final caption = await captionService.getCaption(oldPath);
      if (caption != null && caption.trim().isNotEmpty) {
        await captionService.saveCaption(dest, caption);
        await captionService.saveCaption(oldPath, '');
      }
    } catch (e) {
      logWarning('ImageRenameService.rename: migrate caption', e);
    }
    try {
      final desc = await descriptionService.getDescription(oldPath);
      if (desc != null && desc.trim().isNotEmpty) {
        await descriptionService.saveDescription(dest, desc);
        await descriptionService.removeDescription(oldPath);
      }
    } catch (e) {
      logWarning('ImageRenameService.rename: migrate description', e);
    }

    // Verwijzingen in .md-bestanden op schijf meewijzen — dezelfde service als
    // bij dedup, nu met één vervanging.
    final refs = ImageReferenceService();
    final updated = <String>[];
    for (final deckFile in deckFiles) {
      if (await refs.replaceReferences(deckFile, oldPath, dest)) {
        updated.add(deckFile);
      }
    }

    return RenameResult.success(dest, updatedDeckFiles: updated);
  }
}

/// De drie uitkomsten van [ImageRenameService.validateStem]: geldig, uit te
/// schakelen (leeg of ongewijzigd), of af te wijzen met een melding.
enum RenameValidation { ok, disabled, invalidName }
