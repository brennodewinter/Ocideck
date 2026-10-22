// Web/stub-versie van [RecordingStaging]. Op web bestaat er geen
// bestandssysteem-staging: de duurzame opname is een `mem:`-sleutel in de
// WebAssetStore en verdwijnt vanzelf met het tabblad (TRANSCRIPTION.md
// §3.2 "Web"). Elke call is daarom een eerlijke no-op — niet "staging
// uit", maar "staging kan hier geen spoor achterlaten".

/// Het levenscyclus-contract voor opname-staging. De `_io`-versie
/// implementeert dezelfde vier calls tegen de OS-tempmap.
abstract class RecordingStaging {
  /// Maak een verse stagingmap voor één sessie; null waar er geen
  /// bestandssysteemstaging is (web).
  Future<String?> createSessionDir();

  /// Gooi één sessiemap weg — na een gefaalde start of bij de
  /// niet-bewaarkeuze. `null` is toegestaan en doet niets.
  Future<void> discardDir(String? dir);

  /// Vegen bij opstarten: sessiemappen ouder dan [maxAge] weg, jongere
  /// laten liggen voor de herstelperiode (§3.2: 7 dagen, dezelfde als de
  /// documentrecovery).
  Future<void> sweep({required Duration maxAge});

  /// Alles wissen — de expliciete wisactie, los van verloop.
  Future<void> discardAll();
}

/// Web: geen staging op schijf, dus niets om te maken, vegen of wissen.
class NoopRecordingStaging implements RecordingStaging {
  const NoopRecordingStaging();

  @override
  Future<String?> createSessionDir() async => null;

  @override
  Future<void> discardDir(String? dir) async {}

  @override
  Future<void> sweep({required Duration maxAge}) async {}

  @override
  Future<void> discardAll() async {}
}

RecordingStaging createRecordingStaging() => const NoopRecordingStaging();
