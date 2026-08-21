/// Maak van vrije tekst een veilige bestandsnaam-stam: strip alles buiten
/// Unicode-letters, -cijfers, whitespace en `-`, alle whitespace naar `_`,
/// en val terug op [fallback] wanneer de naam leeg wordt.
///
/// Eén gedeelde sanitizer: voorheen stond dit recept identiek in
/// `file_service_package.dart` (`_safeName`), `shell_actions.dart`
/// (`_safeRemoteName`) en `file_service_style_profile.dart`
/// (`_safeProfileFileName`), met alleen de fallback verschillend. Een
/// aanroeper die een ander fallback-woord wil geeft die mee.
String sanitizeFilename(String input, {required String fallback}) {
  final cleaned = input
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return cleaned.isEmpty ? fallback : cleaned;
}
