/// Geeft een opgeschoond linkdoel terug dat interactief mag worden in een
/// audience-export, of `null` wanneer het platte tekst moet blijven.
///
/// De viewer van de export handelt URL-schema's zelf af. Houd die vertrouwens-
/// grens bewust klein: weblinks, e-maillinks en ankers binnen het document.
String? safeExportLink(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty || value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    return null;
  }
  if (value.startsWith('#')) {
    return value.length > 1 ? value : null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  switch (uri.scheme.toLowerCase()) {
    case 'http':
    case 'https':
      return uri.host.isEmpty ? null : value;
    case 'mailto':
      return uri.path.isEmpty ? null : value;
    default:
      return null;
  }
}
