import 'document_page_setup.dart';
import '../models/page_size.dart';
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

/// De paginaopmaak die voor dít document geldt: wat het document zelf draagt,
/// anders de app-instelling.
///
/// Dezelfde volgorde als bij de stijl ([effectiveDocumentStyleName]) — een
/// afgedwongen huisstijl zou er als eerste stap bij komen; die bestaat voor de
/// paginaopmaak nog niet. Maat en marges gelden los van elkaar: een document dat
/// alleen `papersize:` draagt houdt de ingestelde marges.
DocumentPageSetup effectiveDocumentPageSetup(
  AppSettings settings,
  String source,
) {
  final own = documentPageSetup(source);
  final size = own.size ?? settings.documentPageSize;
  // Eigen marges van het document winnen, tenzij ze niet in het vel passen —
  // dan valt de tekstspiegel negatief en crasht de layout. In dat geval
  // gelden de instellingen, en passen die ook niet, dan de standaardmarge,
  // en past die zelfs niet (een extreem klein vel), dan een marge die wél
  // past met een veilige minimum-textspiegel van 10 mm.
  PageMargins margins;
  if (own.margins != null && marginsFitPaper(size, own.margins!)) {
    margins = own.margins!;
  } else if (marginsFitPaper(size, settings.documentPageMargins)) {
    margins = settings.documentPageMargins;
  } else if (marginsFitPaper(size, const PageMargins())) {
    margins = const PageMargins();
  } else {
    final (w, h) = size.dimensions;
    margins = PageMargins(
      topMm: ((h - 10) / 2).clamp(0, 25),
      bottomMm: ((h - 10) / 2).clamp(0, 25),
      leftMm: ((w - 10) / 2).clamp(0, 20),
      rightMm: ((w - 10) / 2).clamp(0, 20),
    );
  }
  return (size: size, margins: margins);
}
