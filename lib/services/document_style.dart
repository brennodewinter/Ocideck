import '../models/settings.dart';

/// Resolves the effective style [ThemeProfile] for a document, or `null` when a
/// document has no style at all.
///
/// Precedence (see `docs/design/DOCUMENT_MODE.md`):
/// 1. **Enforced house style** — when [AppSettings.documentStyleEnforced] is on
///    and a default is set, it wins and the per-document `theme:` is ignored.
/// 2. **The document's own style** ([docStyleName]) when set.
/// 3. **The settings default** document style.
/// 4. `null` — no document style; the caller keeps its own default (the app
///    theme in the editor, the active profile on export), so a plain `.md`
///    behaves exactly as it did before this feature.
///
/// A name that matches no known profile falls through to the next step rather
/// than erroring, so an unknown or since-removed profile never breaks a document.
ThemeProfile? resolveDocumentStyleProfile(
  AppSettings settings,
  String? docStyleName,
) {
  ThemeProfile? byName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final profile in settings.themeProfiles) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  if (settings.documentStyleEnforced) {
    final enforced = byName(settings.documentDefaultStyle);
    if (enforced != null) return enforced;
  }
  return byName(docStyleName) ?? byName(settings.documentDefaultStyle);
}

/// The style name the editor's picker should show as *active* for a document
/// whose own front matter declares [docStyleName]. Under an enforced house style
/// that name wins; otherwise the document's own choice (which may be `null` =
/// "Geen"). Independent of whether the profile still exists, so the picker keeps
/// showing what the file asked for.
String? effectiveDocumentStyleName(AppSettings settings, String? docStyleName) {
  if (settings.documentStyleEnforced && settings.documentDefaultStyle != null) {
    return settings.documentDefaultStyle;
  }
  return docStyleName;
}
