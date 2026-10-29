/// Web-/testvariant van `AtomicFilePreferencesStore`: alleen de
/// meldingshaak, zodat aanroepers platform-onafhankelijk blijven. Op web is
/// `localStorage` de prefs-opslag en bestaat het bestandsprobleem van
/// #2628 niet.
class AtomicFilePreferencesStore {
  /// Wordt op desktop-platforms met een bestands-prefs één keer per corrupt
  /// bestand aangeroepen; hier nooit.
  static void Function(String? quarantinedPath)? onCorruption;
}

/// Op web is er niets te registreren — `localStorage` is de prefs-opslag.
void registerAtomicFilePreferences() {}
