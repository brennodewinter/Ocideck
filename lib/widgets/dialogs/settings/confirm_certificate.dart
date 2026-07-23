/// Vraagt de gebruiker het certificaat van [origin] te bekijken en geeft de
/// vingerafdruk terug als hij het besluit te vertrouwen, of `null`.
///
/// Staat los van de panelen die hem gebruiken, en los van de dialoog die hem
/// invult: het ophalen van een certificaat leunt op `dart:io`, en dat mag een
/// paneel niet meeslepen naar de webbundel. Het paneel kent alleen deze vorm.
typedef ConfirmCertificate =
    Future<String?> Function({
      required Uri origin,
      required String host,
      required bool allowPrivate,
    });
