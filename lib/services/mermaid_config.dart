/// De initialisatie-instellingen voor Mermaid, als één bron van waarheid.
///
/// Er zijn twee renderpaden: op desktop/mobiel een verborgen WebView
/// ([MermaidRenderService]), op web de gebundelde mermaid.min.js rechtstreeks in
/// de app-pagina via JS-interop (`mermaid_web_renderer.dart`, #851). Beide
/// initialiseren mermaid — en beide MOETEN dat met precies dezelfde beveiligings-
/// posture doen. Stond de config op twee plekken, dan zou één ervan stil kunnen
/// afwijken; de WebView-kant zet hem via `jsonEncode(kMermaidInitConfig)` in de
/// pagina, de web-kant via `.jsify()`, zodat er geen tweede kopie bestaat.
///
/// De sleutels, en waarom ze staan zoals ze staan:
///
///  * `securityLevel: 'strict'` — mermaid schoont de uitvoer met DOMPurify en
///    voert geen click-bindingen of scripts uit. (De app schoont daarna nog een
///    keer met `sanitizeMermaidSvg`, een allow-list; dubbel met opzet.)
///  * `htmlLabels: false`, óók per diagramsoort (`flowchart`, `class`): met
///    htmlLabels tekent mermaid labels in een `<foreignObject>`, en dat element
///    haalt de SVG-opschoning weg — dan houd je lege vakjes zonder tekst over.
///  * `secure: [...]` — de onaantastbare sleutels. Mermaids eigen standaardlijst
///    wordt hierdoor VERVANGEN, dus 'secure' en 'maxTextSize' moeten er zelf in:
///    zonder 'secure' kan een diagramrichtlijn de lijst overschrijven en daarmee
///    de rest van de beperkingen alsnog opheffen.
///
/// `startOnLoad: false` omdat we zelf `render()` aanroepen; `theme: 'neutral'`
/// voor een rustig, thema-onafhankelijk uiterlijk in het witte kader.
const Map<String, Object?> kMermaidInitConfig = {
  'startOnLoad': false,
  'theme': 'neutral',
  'securityLevel': 'strict',
  'htmlLabels': false,
  'flowchart': {'htmlLabels': false},
  'class': {'htmlLabels': false},
  'secure': [
    'secure',
    'securityLevel',
    'startOnLoad',
    'maxTextSize',
    'suppressErrorRendering',
    'htmlLabels',
  ],
};

/// De URL waarop de gebundelde mermaid op web wordt geserveerd.
///
/// Flutter serveert een asset onder `assets/` + de assetsleutel, en die sleutel
/// is hier zelf `assets/web_export/mermaid.min.js` — vandaar de dubbele
/// `assets/`. De app-CSP staat `script-src 'self'` toe, dus een `<script src>`
/// naar deze zelfde-origin-URL mag; inline of `blob:` injecteren mag níet
/// (geen 'unsafe-inline', geen blob: in script-src), daarom de URL en niet de
/// tekst. Een test leidt deze waarde af uit pubspec en bewaakt dat hij klopt.
const String kMermaidWebScriptUrl = 'assets/assets/web_export/mermaid.min.js';

/// De URL van de gebundelde SVG-stijl-inliner (#862), op web geserveerd als
/// `<script src>`. Zelfde dubbele-`assets/`-sleutel en CSP-reden als
/// [kMermaidWebScriptUrl]: flutter_svg leest geen `<style>`, dus deze inliner
/// zet mermaids theme-styling als inline attributen vóór het tekenen.
const String kSvgStyleInlineScriptUrl =
    'assets/assets/web_export/svg_style_inline.js';
