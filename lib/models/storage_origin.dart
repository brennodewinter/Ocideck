/// Waar een geopend deck vandaan komt.
///
/// Elke opslagsoort draagt zijn eigen gegevens — een ETag bij WebDAV en S3, een
/// `baseSha` en werkbranch bij git — dus dit is bewust een smal contract en geen
/// gemeenschappelijke basisklasse: het zegt alleen wat élke herkomst heeft.
///
/// Het bestaan van dit type is de reden dat een tabblad één herkomstveld heeft
/// in plaats van drie. Met drie losse velden kon een deck dat van WebDAV kwam en
/// naar S3 werd weggeschreven er twee tegelijk dragen, en dan is "waar kwam dit
/// vandaan" niet meer te beantwoorden. Nu dwingt het type het antwoord af.
///
/// Geen `sealed`: de drie implementaties wonen bij hun eigen instellingen
/// ([WebdavOrigin], [S3Origin], [GitOrigin]) en dat mag niet één bibliotheek
/// worden alleen om de verzegeling te krijgen.
abstract interface class StorageOrigin {
  /// De verbinding waar dit deck vandaan kwam, als `StorageConnection.id`.
  ///
  /// Leeg voor herkomst uit een versie van vóór de verbindingenlijst; de
  /// backends vallen dan terug op het vergelijken van de serverinstellingen
  /// zelf (`matchesServer`, `matchesBucket`, `matchesRepo`).
  String get connectionId;

  /// Waar het deck binnen die opslag staat: een pad bij WebDAV en S3, de
  /// deckmap bij git. Voor labels en meldingen — nooit om op te sturen.
  String get remoteLocation;
}
