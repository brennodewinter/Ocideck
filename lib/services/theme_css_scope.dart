/// Scóóp gegenereerde thema-CSS op het class-token van een stijlbereik
/// (#2996), zodat meerdere stijlprofielen in één stylesheet kunnen leven.
///
/// Elke selector die op [root] begint krijgt `.<token>` er achter
/// (`section.title` → `section.stijl-donker.title`); elke andere selector —
/// de tabelregels van `_marpTableCss`, `.slide`-regels zonder root — krijgt
/// `[root].<token>` ervóór als afstammeling. At-rules (`@font-face`,
/// `@media`-koppen) zijn geen selectors en blijven ongemoeid; `:root` wordt
/// het bereikelement zelf, zodat een profielvariabele binnen de dia geldt.
///
/// De uitvoer is bewust geen parser: hij verwerkt uitsluitend de door
/// OciDeck gegenereerde profiel-CSS (platte regels, geen nesting), niet
/// willekeurige stylesheets.
String scopeThemeCss(
  String css, {
  required String root,
  required String token,
}) => css.replaceAllMapped(RegExp(r'([^{}]+)\{'), (m) {
  final scoped = m
      .group(1)!
      .split(',')
      .map((raw) {
        final sel = raw
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
            .trim();
        if (sel.isEmpty || sel.startsWith('@')) return sel;
        if (sel == ':root') return '$root.$token';
        // Woordgrens na de wortel: `.slideout` of `sectionx` mogen niet
        // meeliften als `.<token>out`.
        if (sel.startsWith(root) &&
            (sel.length == root.length ||
                '. :>+~'.contains(sel[root.length]))) {
          return '$root.$token${sel.substring(root.length)}';
        }
        return '$root.$token $sel';
      })
      .join(', ');
  return '$scoped {';
});
