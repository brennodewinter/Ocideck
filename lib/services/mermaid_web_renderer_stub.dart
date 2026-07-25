/// De niet-web tegenhanger van `mermaid_web_renderer.dart`.
///
/// Het conditional-import-patroon (`import 'stub' if (dart.library.js_interop)
/// 'web'`) vraagt op elk platform een `renderMermaid`-symbool. Op desktop/mobiel
/// rendert de verborgen WebView de diagrammen; deze functie wordt daar dus nooit
/// aangeroepen — `MermaidRenderService.render` neemt het web-pad alleen achter
/// `kIsWeb`. Hij bestaat puur zodat de conditional import op IO compileert.
Future<String?> renderMermaid(String source) async => null;
