// OciDeck — SVG-stijl-inliner + tekst-normalisatie + pijlpunten (#862, #868, #941).
//
// `flutter_svg` (vector_graphics) tekent GEEN `<style>`/CSS-class-styling; het
// leest alleen inline presentatie-attributen. Mermaid stopt zijn hele theme
// (node-fill, stroke, edge `fill:none`, tekstkleur, font) in een `<style>`-blok
// met class-selectors. Zonder dat blok — `sanitize_svg.dart` verwijdert het,
// want flutter_svg negeert het toch — vallen alle vormen én tekst terug op de
// SVG-standaard `fill:black`: zwarte vakjes met onzichtbare tekst en zwart
// gevulde edges. Dat was #862.
//
// Maar de vormen goed kleuren was niet genoeg (#868): flutter_svg plaatst
// mermaids labels óók verkeerd. Mermaid legt tekst neer met `text-anchor:middle`,
// `em`-eenheden in `y`/`dy`, en per woord geneste `<tspan>`s — precies de
// tekstlayout die flutter_svg niet betrouwbaar volgt. Het gevolg: labels
// verspringen buiten hun node en overlappen, de nodes lijken leeg.
//
// Deze functie draait in de browser die mermaid al rendert (de verborgen WebView
// op desktop, de app-pagina op web) en doet drie dingen terwijl de SVG in de DOM
// hangt, zodat meten kan:
//
//   1. inline: per element de computed styles als `style`-attribuut zetten en het
//      `<style>`-blok verwijderen — flutter_svg leest die inline stijlen wél;
//   2. bakken: elke tekstregel omzetten naar één platte `<tspan>` met absolute
//      px-`x`/`y` en `text-anchor:start`, op exact de plek die de browser al had
//      berekend (`getStartPositionOfChar`). Geen `middle`, geen `em`, geen
//      geneste tspans meer — alleen de vorm die flutter_svg het best ondersteunt.
//   3. pijlpunten: mermaid tekent die met een `<marker>`, die flutter_svg negeert
//      (#941). Meet per edge het eindpunt en de richting (`getPointAtLength`) en
//      zet er een expliciete `<polygon>`-driehoek neer.
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

  // Zet per element de computed styles als inline `style`-attribuut.
  function inlineStyles(root) {
    var els = [root].concat(Array.prototype.slice.call(root.querySelectorAll('*')));
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.tagName && el.tagName.toLowerCase() === 'style') continue;
      var cs = getComputedStyle(el);
      var st = el.getAttribute('style') || '';
      // Scheidingsteken afdwingen: een bestaande `style="stroke: none"` zónder
      // afsluitende `;` zou anders samensmelten met de eerste toevoeging tot
      // `stroke: nonefill:…` — ongeldige CSS die de fill zou verliezen.
      if (st && st.charAt(st.length - 1) !== ';') st += ';';
      for (var j = 0; j < PROPS.length; j++) {
        var v = cs.getPropertyValue(PROPS[j]);
        if (v) st += PROPS[j] + ':' + v + ';';
      }
      el.setAttribute('style', st);
    }
  }

  function removeStyleElements(root) {
    var styleEls = root.querySelectorAll('style');
    for (var k = 0; k < styleEls.length; k++) {
      styleEls[k].parentNode.removeChild(styleEls[k]);
    }
  }

  // `text-anchor:start` in zowel attribuut als inline stijl, zodat er geen
  // `middle` blijft hangen die flutter_svg alsnog anders zou plaatsen.
  function setStart(el) {
    el.setAttribute('text-anchor', 'start');
    if (el.style) el.style.textAnchor = 'start';
  }

  // Eén tekstregel (`<text>` of een rij-`<tspan>`) platslaan: meet waar het
  // eerste teken nú staat (ná mermaids `middle`-anchoring en `em`-berekening),
  // en leg die plek vast als absolute `x`/`y` met `text-anchor:start`. De inhoud
  // wordt platte tekst — de per-woord geneste tspans vervallen.
  function bakeSpan(el) {
    try {
      if (!el.getNumberOfChars || el.getNumberOfChars() === 0) {
        setStart(el);
        return;
      }
      var p = el.getStartPositionOfChar(0);
      var s = el.textContent;
      while (el.firstChild) el.removeChild(el.firstChild);
      el.textContent = s;
      el.setAttribute('x', p.x);
      el.setAttribute('y', p.y);
      el.removeAttribute('dy');
      setStart(el);
    } catch (e) {
      // Lukt meten niet voor dit label, laat het dan zoals het was.
    }
  }

  function bakeText(root) {
    var texts = root.querySelectorAll('text');
    for (var i = 0; i < texts.length; i++) {
      var text = texts[i];
      var rows = [];
      for (var c = 0; c < text.children.length; c++) {
        var ch = text.children[c];
        if (ch.tagName && ch.tagName.toLowerCase() === 'tspan') rows.push(ch);
      }
      // Meerdere rij-tspans (gewrapte labels) elk apart bakken; anders het
      // `<text>` zelf, dat dan de directe tekst draagt.
      if (rows.length === 0) {
        bakeSpan(text);
      } else {
        for (var r = 0; r < rows.length; r++) bakeSpan(rows[r]);
      }
      setStart(text);
    }
  }

  // Teken één pijlpunt als expliciete driehoek aan het uiteinde van [el].
  // [atLen]/[awayLen] zijn booglengtes: het punt van de pijl en een punt iets
  // verderop de lijn, waaruit de richting volgt. De driehoek gaat in dezelfde
  // ouder als de edge, zodat een eventuele transform op die groep óók voor de
  // pijl geldt (getPointAtLength geeft coördinaten in de lokale ruimte).
  function addArrowHead(el, atLen, awayLen, len, half, color, svgns) {
    try {
      var tip = el.getPointAtLength(atLen);
      var back = el.getPointAtLength(awayLen);
      var dx = tip.x - back.x, dy = tip.y - back.y;
      var m = Math.sqrt(dx * dx + dy * dy);
      if (!(m > 0)) return;
      dx /= m; dy /= m;
      var bx = tip.x - dx * len, by = tip.y - dy * len; // midden van de basis
      var px = -dy * half, py = dx * half; // loodrecht op de richting
      var pts = tip.x + ',' + tip.y + ' ' +
        (bx + px) + ',' + (by + py) + ' ' +
        (bx - px) + ',' + (by - py);
      var poly = document.createElementNS(svgns, 'polygon');
      poly.setAttribute('points', pts);
      poly.setAttribute('fill', color);
      poly.setAttribute('stroke', 'none');
      (el.parentNode || el).appendChild(poly);
    } catch (e) {
      // Lukt meten niet voor deze edge, sla de pijlpunt dan over.
    }
  }

  // Zet mermaids pijlpunten om in expliciete driehoeken.
  //
  // Mermaid tekent elke pijl met een `<marker>` (`marker-end="url(#…)"`).
  // flutter_svg (vector_graphics) rendert `<marker>` NIET, dus de pijlpunten
  // verdwenen en een flowchart verloor zijn richting. Hier meten we — terwijl de
  // SVG in de DOM hangt, dus vóór het `<style>`-blok weg is — het eindpunt en de
  // richting van elke edge met een marker, en zetten er een `<polygon>` neer die
  // flutter_svg wél tekent. `sanitize_svg.dart` laat `polygon`/`points`/`fill`
  // staan.
  function bakeArrows(root) {
    var svgns = 'http://www.w3.org/2000/svg';
    var shapes = root.querySelectorAll('path, line, polyline');
    for (var i = 0; i < shapes.length; i++) {
      var el = shapes[i];
      if (typeof el.getTotalLength !== 'function') continue;
      var cs = getComputedStyle(el);
      // marker-end/-start kunnen als attribuut óf via CSS-class staan; de
      // computed style vangt beide (het `<style>`-blok hangt hier nog).
      var hasEnd =
        el.getAttribute('marker-end') || (cs.markerEnd && cs.markerEnd !== 'none');
      var hasStart =
        el.getAttribute('marker-start') ||
        (cs.markerStart && cs.markerStart !== 'none');
      if (!hasEnd && !hasStart) continue;
      var total;
      try { total = el.getTotalLength(); } catch (e) { continue; }
      if (!(total > 0)) continue;
      var strokeW = parseFloat(cs.strokeWidth) || 1;
      var len = 8 + strokeW * 2; // lengte van de pijlpunt in gebruikerseenheden
      var half = len * 0.42; // halve breedte aan de basis
      var color = cs.stroke && cs.stroke !== 'none' ? cs.stroke : '#333333';
      if (hasEnd) {
        addArrowHead(el, total, Math.max(0, total - 2), len, half, color, svgns);
      }
      if (hasStart) {
        addArrowHead(el, 0, Math.min(total, 2), len, half, color, svgns);
      }
      el.removeAttribute('marker-end');
      el.removeAttribute('marker-start');
    }
  }

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
      // Volgorde telt: eerst de stijlen inline zetten (zodat het font in het
      // `style`-attribuut staat), dan de pijlpunten bakken (die lezen `stroke` en
      // `marker-end`, dus vóór het `<style>`-blok weg is), dan dat blok weg (geen
      // class-regel die `text-anchor` terugzet), en pas dán tekst bakken — meten
      // gebeurt met het inline-font, dus zonder `<style>` nog even correct.
      inlineStyles(root);
      bakeArrows(root);
      removeStyleElements(root);
      bakeText(root);
      var out = root.outerHTML;
      holder.parentNode.removeChild(holder);
      return out;
    } catch (e) {
      // Faalt de inliner, dan liever het (ongestylede) diagram dan niets.
      return svg;
    }
  };
})();
