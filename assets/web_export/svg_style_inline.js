// OciDeck — SVG-stijl-inliner (#862).
//
// `flutter_svg` (vector_graphics) tekent GEEN `<style>`/CSS-class-styling; het
// leest alleen inline presentatie-attributen. Mermaid stopt zijn hele theme
// (node-fill, stroke, edge `fill:none`, tekstkleur, font) in een `<style>`-blok
// met class-selectors. Zonder dat blok — `sanitize_svg.dart` verwijdert het,
// want flutter_svg negeert het toch — vallen alle vormen én tekst terug op de
// SVG-standaard `fill:black`: zwarte vakjes met onzichtbare tekst en zwart
// gevulde edges.
//
// Deze functie draait in de browser die mermaid al rendert (de verborgen WebView
// op desktop, de app-pagina op web) en laat die de CSS-cascade oplossen: ze zet
// per element de computed styles als inline `style`-attribuut en verwijdert dan
// het `<style>`-blok. De uitkomst heeft inline stijlen die flutter_svg wél leest.
//
// Eén bron voor beide renderpaden: web laadt dit bestand via `<script src>`
// (CSP `script-src 'self'`), desktop bundelt het in zijn WebView-HTML.
(function () {
  // fill/stroke MOETEN mee, ook waarde `none` (anders vallen edges op de
  // standaard `fill:black` terug). Deze lijst spiegelt de allow-list van
  // sanitize_svg.dart, zodat de opschoning ze daarna niet alsnog weggooit.
  var PROPS = [
    'fill', 'fill-opacity', 'stroke', 'stroke-width', 'stroke-opacity',
    'stroke-dasharray', 'stroke-linecap', 'stroke-linejoin', 'color', 'opacity',
    'font-family', 'font-size', 'font-weight', 'text-anchor',
  ];

  window.__ocideckInlineSvgStyles = function (svg) {
    try {
      var holder = document.createElement('div');
      holder.style.cssText =
        'position:absolute;left:-99999px;top:0;width:0;height:0;overflow:hidden';
      // De SVG komt uit onze eigen mermaid-render (securityLevel: 'strict',
      // htmlLabels: false) en wordt ná dit nog met sanitizeMermaidSvg opgeschoond;
      // innerHTML voert bovendien geen scripts uit. De holder staat buiten beeld
      // en wordt meteen weer verwijderd.
      holder.innerHTML = svg;
      var root = holder.querySelector('svg');
      if (!root) return svg;
      document.body.appendChild(holder);
      var els = [root].concat(Array.prototype.slice.call(root.querySelectorAll('*')));
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (el.tagName === 'style') continue;
        var cs = getComputedStyle(el);
        var st = el.getAttribute('style') || '';
        for (var j = 0; j < PROPS.length; j++) {
          var v = cs.getPropertyValue(PROPS[j]);
          if (v) st += PROPS[j] + ':' + v + ';';
        }
        el.setAttribute('style', st);
      }
      var styleEls = root.querySelectorAll('style');
      for (var k = 0; k < styleEls.length; k++) {
        styleEls[k].parentNode.removeChild(styleEls[k]);
      }
      var out = root.outerHTML;
      holder.parentNode.removeChild(holder);
      return out;
    } catch (e) {
      // Faalt de inliner, dan liever het (ongestylede) diagram dan niets.
      return svg;
    }
  };
})();
