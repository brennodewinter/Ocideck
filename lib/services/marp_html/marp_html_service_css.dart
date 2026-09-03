// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// De stylesheet van de export: het thema-onafhankelijke blok dat altijd meegaat,
// en de kleuren/letters voor een export zonder [ThemeProfile]. Uitgetild uit de
// hoofdbibliotheek voor de bestandsgrootte-ratchet; `_themedCss` blijft daar,
// omdat die het profiel nodig heeft.
part of '../marp_html_service.dart';

/// Zichtbare AI-melding voor HTML. Zij staat onder de TLP-balk wanneer die er
/// is; in doorlopende documentmodus zit TLP in kop en voet en begint zij boven.
String _aiBanner(
  ExportDocumentMetadata metadata, {
  bool classificationBanner = true,
}) {
  if (!metadata.hasUnreviewedAi) return '';
  const l10n = AppLocalizations(Locale('nl'));
  final text = l10n.d(
    'Concept: hier staat AI-tekst die nog niemand heeft nagekeken',
  );
  final top = classificationBanner ? '2.4em' : '0';
  return '<div class="ai-export-banner" style="top:$top">'
      '${MarpHtmlService._htmlText(text)}</div>';
}

/// De opmaak die van geen enkel thema afhangt: de dia-doos, de tijdlijn, de
/// ondertekening, het media-redactievlak, de classificatiebanner en de
/// printregels. Deze gaat **altijd** mee, vóór [_defaultThemeCss] of
/// [_themedCss], zodat een gethematiseerde export dezelfde structuur houdt en
/// een thema alleen de kleuren en de letter overneemt.
///
/// `--ocideck-accent` is de enige haak die het thema hier binnenkomt: de
/// tijdlijn en de ondertekening tekenen ermee, met EU-blauw als waarde voor
/// een export zonder thema.
const _structuralCss = r'''
:root{--ocideck-accent:#003399}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
.ocideck-sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
.slide{position:relative;width:1280px;min-height:720px;margin:24px auto;padding:48px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px}
.slide h1{font-size:48px;margin:.15em 0}
.slide h2{font-size:34px;margin:.15em 0}
.slide p,.slide li{font-size:24px;line-height:1.45}
.slide pre.mermaid{background:transparent;border:0;text-align:center}
.slide img{max-width:100%}
.slide .marp-header,.slide .marp-footer{position:absolute;left:48px;right:48px;z-index:2;font-size:16px;line-height:1.25}
.slide .marp-header{top:18px}.slide .marp-footer{bottom:18px}
.slide .marp-header p,.slide .marp-footer p{font-size:inherit;line-height:inherit;margin:0}
.slide.marp-heading-fit h1,.slide.marp-heading-fit h2,.slide.marp-heading-fit h3,.slide.marp-heading-fit h4,.slide.marp-heading-fit h5,.slide.marp-heading-fit h6{white-space:nowrap}
.slide table{border-collapse:collapse;width:100%}
.slide ol.timeline{list-style:none;margin:.6em 0;padding:0 0 0 24px;border-left:3px solid #ccc}
.slide ol.timeline li{position:relative;margin:0 0 .9em;padding-left:16px}
.slide ol.timeline li::before{content:"";position:absolute;left:-31px;top:.45em;width:11px;height:11px;border-radius:50%;background:var(--ocideck-accent)}
.slide .tl-marker{display:block;font-size:18px;font-weight:700;color:var(--ocideck-accent);letter-spacing:.04em}
.slide .tl-title{display:block;font-size:26px;font-weight:600;line-height:1.3}
.slide .tl-desc{display:block;font-size:20px;opacity:.7;line-height:1.35}
.slide .signoff{margin-top:.8em;max-width:900px}
.slide .signoff-statement{font-style:italic;opacity:.85;font-size:22px}
.slide .signoff-mark{font-family:Georgia,"Times New Roman",serif;font-style:italic;font-size:40px;color:var(--ocideck-accent);margin:.35em 0 .1em}
.slide .signoff-none{font-style:italic;opacity:.6;font-size:22px}
.slide .signoff-meta{font-size:20px;opacity:.8;margin:.1em 0}
.slide .signoff-seal{font-size:18px;opacity:.6;letter-spacing:.03em;margin-top:.7em}
.slide .media-redacted{display:flex;align-items:center;justify-content:center;min-height:200px;margin:.6em 0;background:#000;color:#fff;font-size:20px;letter-spacing:.05em;border-radius:4px;text-align:center;padding:24px}
.slide .image-missing{display:inline-block;padding:14px 20px;border:2px dashed rgba(100,116,139,.5);border-radius:6px;font-size:19px;opacity:.6;font-style:italic}
.slide .media-absent{display:flex;align-items:center;justify-content:center;min-height:180px;margin:.6em 0;border:2px dashed rgba(100,116,139,.5);border-radius:6px;font-size:20px;opacity:.6;font-style:italic;text-align:center;padding:24px}
.slide .cockpit-svg.authentic .cockpit-meter{transform-box:fill-box;transform-origin:center;animation:cockpitPowerOn 1.55s cubic-bezier(.2,.75,.22,1) both;animation-delay:calc(var(--meter-index)*80ms)}
@keyframes cockpitPowerOn{0%{opacity:.08;transform:scale(.965);filter:brightness(.18)}20%{opacity:.72;filter:brightness(1.6)}36%{opacity:1;filter:brightness(.72)}58%{filter:brightness(1.18)}100%{opacity:1;transform:scale(1);filter:brightness(1)}}
@media (prefers-reduced-motion:reduce){.slide .cockpit-svg.authentic .cockpit-meter{animation:cockpitReducedMotion .25s ease-out both}@keyframes cockpitReducedMotion{from{opacity:.5}to{opacity:1}}}
.slide .mermaid-error{margin:.6em 0;padding:16px 20px;border:1px solid #B91C1C;border-left-width:6px;border-radius:6px;background:#FEE2E2;color:#7F1D1D;text-align:left}
.slide .mermaid-error-title{font-size:22px;font-weight:700;margin:0 0 .3em;color:#7F1D1D}
.slide .mermaid-error-label{font-size:16px;font-weight:600;margin:.7em 0 .2em;opacity:.8;color:#7F1D1D}
.slide .mermaid-error-detail,.slide .mermaid-error-source{margin:0;padding:10px 12px;background:rgba(255,255,255,.65);border:0;border-radius:4px;font-size:15px;line-height:1.35;white-space:pre-wrap;overflow:auto;max-height:220px;color:#7F1D1D}
.tlp-export-banner{position:fixed;top:0;left:0;right:0;background:#000;color:#ffc000;text-align:center;font:700 14px/2.4 monospace;z-index:9999;letter-spacing:.06em}
/* Documentmodus (§11.2): één doorlopende leesbare pagina i.p.v. losse 16:9-dia's.
   Alleen de layout hier — géén 16:9-kader, geen vaste hoogte; de kleuren komen
   uit het thema ([_themedDocumentCss]) of [_defaultThemeCss]. */
.document{max-width:46rem;margin:24px auto;padding:32px 40px;line-height:1.65;border-radius:4px;overflow-wrap:break-word}
.document img{max-width:100%}
.document pre{overflow:auto}
.document pre.mermaid{background:transparent;border:0;text-align:center}
.document table{border-collapse:collapse;width:100%}
.document .ocideck-timeline{list-style:none;margin:1.2em 0 1.8em;padding:0}
.document .ocideck-timeline li{display:grid;grid-template-columns:7.25rem 1fr;gap:1rem;position:relative;break-inside:avoid;page-break-inside:avoid;padding-bottom:.9rem}
.document .ocideck-timeline li::before{content:"";position:absolute;left:6.55rem;top:1.05rem;bottom:-.2rem;width:2px;background:color-mix(in srgb,var(--ocideck-accent,#2563eb) 24%,transparent)}
.document .ocideck-timeline li:last-child::before{bottom:calc(100% - 1.1rem)}
.document .ocideck-timeline li::after{content:"";position:absolute;left:6.22rem;top:.75rem;width:.7rem;height:.7rem;border-radius:50%;background:#fff;border:3px solid var(--ocideck-accent,#2563eb);box-shadow:0 0 0 4px color-mix(in srgb,var(--ocideck-accent,#2563eb) 12%,transparent)}
.document .ocideck-timeline-time{position:relative;text-align:right;padding-right:1rem;font-size:.78em;font-weight:700;color:var(--ocideck-accent,#2563eb);font-variant-numeric:tabular-nums}
.document .ocideck-timeline li:last-child .ocideck-timeline-time::after{content:"";position:absolute;right:.3rem;top:1.65rem;width:.75rem;height:2px;background:color-mix(in srgb,var(--ocideck-accent,#2563eb) 24%,transparent)}
.document .ocideck-timeline-label{font-size:.74em;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:var(--ocideck-accent,#2563eb)}
.document .ocideck-timeline-card{position:relative;border:1px solid rgba(100,116,139,.25);border-radius:.7rem;padding:.8rem 1rem;background:rgba(148,163,184,.045);box-shadow:0 4px 14px rgba(15,23,42,.05)}
.document .ocideck-timeline-card::before{content:"";position:absolute;left:-1.8rem;top:1.05rem;width:1.8rem;height:2px;background:color-mix(in srgb,var(--ocideck-accent,#2563eb) 24%,transparent)}
.document .ocideck-timeline-meta{display:inline-block;margin-top:.55rem;padding:.18rem .55rem;border:1px solid rgba(100,116,139,.22);border-radius:999px;font-size:.72em;background:rgba(148,163,184,.09)}
.document hr{border:0;border-top:1px solid rgba(100,116,139,.35);margin:1.6em 0}
/* Voetnoten: kleiner dan de tekst en met een korte lijn erboven — een noot is
   een terzijde, en zo laat papier dat al eeuwen zien. Achteraan, want een
   HTML-pagina heeft geen bladzijden (KNOWN_LIMITATIONS.md). */
.document .ocideck-footnotes{margin-top:2.4em;font-size:.85em;line-height:1.5}
.document .ocideck-footnotes::before{content:"";display:block;width:140px;border-top:1px solid rgba(100,116,139,.35);margin-bottom:.8em}
.document .ocideck-footnotes h2{font-size:1.1em;margin:0 0 .4em}
.document .ocideck-fnref{font-size:.75em;line-height:0}
.document .ocideck-fnback{text-decoration:none}
/* Het afdrukraam: de enige constructie die een browser bij het afdrukken op
   ELKE pagina herhaalt én er ruimte voor vrijhoudt. `position:fixed` leek de
   voor de hand liggende keuze en deed het allebei niet: een vaste band houdt
   geen ruimte vrij (de regel eronder verdween), en met een negatieve offset —
   bedoeld om de band in de paginamarge te leggen — rekent Chrome de plaats
   modulo de pagina en zet hij kop en voet middenin de tekst. Vandaar een
   tabel: kop in `thead`, voet in `tfoot`, de hele body in één cel. De cellen
   zelf dragen géén opmaak; ze zijn alleen het raam. */
.print-frame{width:100%;table-layout:fixed;border-collapse:collapse}
.print-frame>thead{display:table-header-group}
.print-frame>tfoot{display:table-footer-group}
.document .print-frame>thead>tr,.document .print-frame>tfoot>tr,.document .print-frame>tbody>tr{background:none}
.document .print-frame>thead>tr>td,.document .print-frame>tfoot>tr>td,.document .print-frame>tbody>tr>td{padding:0;border:0;background:none;color:inherit;text-align:left;vertical-align:top}
/* Split layout (bulletsImage): text beside an image, matching the theme CSS
   in assets/themes/ocideck.css. The serialiser writes `<!-- _class: split -->`
   and `<div class="split-text">`/`<div class="split-image">`; without these
   rules the two panels stack vertically (#1855). --image-width is set on the
   section from the `_style` directive; 40% is the default. */
section.split{--image-width:40%;--split-margin:48px;display:grid;grid-template-columns:minmax(0,1fr) var(--image-width);gap:var(--split-margin);padding:48px 0 48px var(--split-margin)}
section.split .split-text{min-width:0}
section.split .split-text h1{font-size:1.45em;margin-top:0;margin-bottom:.42em}
section.split .split-text ul{line-height:1.16;padding-left:1em}
section.split .split-text li{margin:.12em 0}
section.split .split-image{position:relative;align-self:stretch;min-height:calc(100vh - 96px);margin:-48px 0}
section.split .split-image p{margin:0;height:100%}
section.split .split-image img{display:block;width:100%;height:100%;object-fit:cover}
/* Image callout overlay (IMAGE_CALLOUTS.md §4.2, §12.2). The slot wraps the
   split-image panel when a slide carries callouts; the box is the painted
   rectangle, and markers are positioned in image-space percentages against it.
   --fx/--fy: focal 0..1 · --z: ze/100 · --iw/--ih: intrinsic pixels.
   ponytail: --iw/--ih default to 16/9 because the Slide model carries no
   intrinsic image dimensions at export time; a render-script pass that reads
   naturalWidth/Height after load is the upgrade path. */
.ocideck-imgslot{position:relative;overflow:hidden;min-height:calc(100vh - 96px)}
.ocideck-imgslot > .ocideck-imgbox{position:absolute;
  left:calc(var(--fx,0.5) * 100%);top:calc(var(--fy,0.5) * 100%);
  transform:translate(calc(var(--fx,0.5) * -100%),calc(var(--fy,0.5) * -100%));
  min-width:100%;min-height:100%;aspect-ratio:var(--iw,16) / var(--ih,9)}
.ocideck-imgzoom{position:absolute;
  width:calc(var(--z,0) * 100%);height:calc(var(--z,0) * 100%);
  left:calc(var(--fx,0.5) * 100%);top:calc(var(--fy,0.5) * 100%);
  transform:translate(calc(var(--fx,0.5) * -100%),calc(var(--fy,0.5) * -100%));
  display:flex;align-items:center;justify-content:center}
.ocideck-imgzoom > .ocideck-imgbox{position:relative;
  aspect-ratio:var(--iw,16) / var(--ih,9)}
.ocideck-imgzoom > .ocideck-imgbox.wide{width:100%;height:auto}
.ocideck-imgzoom > .ocideck-imgbox.tall{height:100%;width:auto}
.ocideck-imgbox > img{display:block;width:100%;height:100%;object-fit:cover}
.ocideck-callout{position:absolute;transform:translate(-50%,-50%);
  display:flex;align-items:center;justify-content:center;
  min-width:1.6em;min-height:1.6em;padding:0 .25em;
  border-radius:50%;font-size:18px;font-weight:700;line-height:1;
  color:#fff;background:var(--ocideck-accent,#003399);
  border:2px solid #fff;
  box-shadow:0 0 0 2px var(--ocideck-accent,#003399),0 1px 4px rgba(0,0,0,.5);
  z-index:3;pointer-events:none}
.ocideck-callout-desc{position:absolute;width:1px;height:1px;padding:0;
  margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
/* Region presentation (§3.1): a region target is an outlined rectangle with
   outside dimming. The box-shadow spreads 100vmax of semi-transparent black
   outward from each region; the imgslot clips it (overflow:hidden), so the
   shadow becomes the "dim everything outside the region" veil with one
   property per region. ponytail: overlapping regions dim each other's
   interior, because a sibling's shadow paints over a transparent box — the
   upgrade path is a single clip-path veil that excludes every region at once. */
.ocideck-region{position:absolute;
  border:2px solid var(--ocideck-accent,#003399);
  box-shadow:0 0 0 100vmax rgba(0,0,0,.4);
  z-index:2;pointer-events:none}
.ocideck-region-num{position:absolute;top:0;left:0;
  transform:translate(-50%,-50%);
  display:flex;align-items:center;justify-content:center;
  width:1.5em;height:1.5em;
  border-radius:50%;font-size:14px;font-weight:700;line-height:1;
  color:#fff;background:var(--ocideck-accent,#003399);
  border:2px solid #fff;
  box-shadow:0 0 0 2px var(--ocideck-accent,#003399),0 1px 4px rgba(0,0,0,.5)}
/* Arrow presentation (§5): a horizontal line from the fixed rail (left edge
   of the imgbox) to the target. The arrowhead is a CSS triangle at the right
   end. The line sits at the target's vertical centre; the rail badge (a
   .ocideck-callout span at left:0) carries the reference letter. */
.ocideck-arrow{position:absolute;height:2px;transform:translateY(-50%);
  background:var(--ocideck-accent,#003399);
  box-shadow:0 0 0 1px #fff,0 1px 3px rgba(0,0,0,.4);
  z-index:2;pointer-events:none}
.ocideck-arrow::after{content:"";position:absolute;right:-1px;top:50%;
  transform:translateY(-50%);
  border:6px solid transparent;border-left:8px solid var(--ocideck-accent,#003399);
  filter:drop-shadow(0 0 1px #fff)}
''';

/// De kleuren en letters voor een export zonder [ThemeProfile] — de
/// tegenhanger van [_themedCss], op dezelfde plek in de cascade.
const _defaultThemeCss = r'''
body{background:#1e1e1e;font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#1a1a1a}
.slide{background:#fff}
.slide h1{color:var(--ocideck-title-color,inherit)}
.slide pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;padding:16px;overflow:auto;font-size:18px}
.slide code{font-family:SFMono-Regular,Consolas,"Liberation Mono",monospace}
.slide blockquote{border-left:4px solid #ccc;margin:.5em 0;padding-left:16px;color:#555}
.slide th,.slide td{border:1px solid #ccc;padding:6px 12px;font-size:20px}
.document{background:#fff}
.document h1{color:var(--ocideck-title-color,inherit)}
.document pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;padding:16px;font-size:16px}
.document code{font-family:SFMono-Regular,Consolas,"Liberation Mono",monospace;background:rgba(26,26,26,.12)}
.document pre code{background:transparent}
.document blockquote{border-left:4px solid #ccc;margin:.6em 0;padding-left:16px;color:#555}
.document th,.document td{border:1px solid #ccc;padding:6px 12px}
.document-header,.document-footer{display:flex;align-items:center;gap:14px;min-height:42px;font-size:12px}
.document-header{border-bottom:1px solid rgba(100,116,139,.55);margin-bottom:24px}
.document-footer{border-top:1px solid rgba(100,116,139,.55);margin-top:24px}
.document-header-text,.document-footer-text{flex:1;min-width:0;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:4;overflow:hidden}
.document-tlp{display:inline-block;flex:0 0 auto;padding:3px 7px;border-radius:4px;background:#000;font:700 10px/1.2 monospace;letter-spacing:.025em;white-space:nowrap}

/* De melding dat er ongecontroleerde AI-tekst in dit document staat.
   Kwam van de juridische tak; deze CSS verhuisde intussen hierheen. */
.ai-export-banner{position:fixed;left:0;right:0;background:#3a2c00;color:#ffd75e;text-align:center;font:600 13px/2.4 system-ui,sans-serif;z-index:9998}
''';

/// De stylesheet die vóór het themablok in elk document gaat: de structuur plus
/// de rapportagedia's en het keuze-menuraster.
///
/// Een functie en geen vierde constante, zodat de aanroeper niet hoeft te weten
/// uit hoeveel stukken dit bestaat.
String exportBaseCss() => '$_structuralCss\n$_reportingCss\n$_menuCss';

/// De printregels, als eigen blok omdat ze ná het thema moeten staan.
///
/// Een thema zet `.document` opnieuw op (`margin`, `max-width`, `box-shadow`)
/// en dat blok komt later in de cascade. Stonden deze regels bij de structuur,
/// dan won de themaregel en droeg de afdruk de slagschaduw en de schermmarge
/// van het beeldscherm mee: een zwarte balk over de kop van het eerste vel en
/// een streep langs de rechterrand van elk vel.
const _printCss = r'''
/* Een paginanummer kan een browser niet aan de inhoud doorgeven: `counter(page)`
   werkt alleen in een `@page`-margeblok, dat geen browser kent, en drukte hier
   op elke pagina "0" af. Op het scherm is er één pagina en klopt de 1; in de
   afdruk zwijgt het nummer liever dan te liegen (KNOWN_LIMITATIONS.md). */
@media print{.document-page-number{display:none}}
/* Bij het afdrukken blijft een kop niet alleen onderaan een blad achter, en
   laat een alinea geen losse regel over de paginagrens achter. Dezelfde regel
   als de Pagina's-weergave in de app hanteert (documentKeepWithNextHeight), zodat
   scherm en druk hetzelfde zeggen. */
@media print{body{background:#fff}.slide{margin:0;box-shadow:none;border-radius:0;page-break-after:always;width:100%;min-height:100vh}.document{margin:0;max-width:100%;box-shadow:none;border-radius:0;orphans:2;widows:2}.document h1,.document h2,.document h3,.document h4,.document h5,.document h6{page-break-after:avoid;break-after:avoid}.document hr{page-break-after:always;border:0;height:0;margin:0}}
''';

/// De rand-CSS voor een document-tabelcel, afgeleid uit de
/// [ThemeProfile.tableBorderStyle] en [ThemeProfile.tableBorderColor].
/// Feature 5: lined → alleen horizontale lijnen, boxed → volledig omkaderd,
/// none → geen randen.
String _documentTableBorderCss(ThemeProfile t) {
  final border = t.tableBorderColor;
  return switch (t.tableBorderStyle) {
    TableBorderStyle.boxed => 'border:1px solid $border;',
    TableBorderStyle.lined => 'border-bottom:1px solid ${border}80;',
    TableBorderStyle.none => '',
  };
}

/// Celopvulling als CSS `padding`-waarde, afgeleid uit
/// [ThemeProfile.tableCellPaddingPx].
String _documentTableCellPadding(ThemeProfile t) {
  final p = t.tableCellPaddingPx;
  return '${(p * 0.6).toStringAsFixed(1)}px ${(p + 4).toStringAsFixed(1)}px';
}

/// Zebrastrepen voor oneven body-rijen, alleen wanneer
/// [ThemeProfile.tableZebraStriped] aanstaat.
String _documentTableZebraCss(ThemeProfile t) => t.tableZebraStriped
    ? '.document tbody tr:nth-child(even){background:${t.tableZebraColor}}'
    : '';

/// Accentkleurige onderrand onder de koprij, alleen wanneer
/// [ThemeProfile.tableAccentHeaderBorder] aanstaat.
String _documentTableAccentHeaderCss(ThemeProfile t) =>
    t.tableAccentHeaderBorder
    ? '.document thead th{border-bottom:2px solid ${t.accentColor}}'
    : '';

/// De thema-afhankelijke opmaak van de doorlopende documentmodus
/// (`<section class="document">`, §11.2): dezelfde kleuren en letter als een
/// dia, maar als leesbare pagina — een redelijke kolombreedte, comfortabele
/// marges en regelafstand, géén 16:9-kader en geen vaste hoogte.
///
/// Top-level in dit part-bestand (en niet in `_themedCss` in de
/// hoofdbibliotheek) zodat die onder de bestandsgrensratchet blijft. GÉÉN
/// externe `url()`/`@font-face`: de CSP is het vangnet, niet de vergunning.
String _themedDocumentCss(ThemeProfile t, String family, String codeFamily) {
  final logoSize = t.effectiveDocumentLogoSize;
  final bandText = t.effectiveDocumentBandTextColor;
  final bandBackground = t.effectiveDocumentBandBackgroundColor;
  final logoHeight = (logoSize * 0.5).round().clamp(32, 240);
  // De basislettergrootte van de documentstijl, in CSS-pixels van de
  // puntmaat. De koppen, noten en tijdlijnkaartjes van `.document` staan in
  // `em`, dus ze schalen vanzelf mee — net als in de app. Zonder de omzetting
  // pt→px was 11 pt hier 11 px: een derde kleiner dan de PDF (#1947).
  final bodyFontSize = documentBodyFontSizeToCssPx(t.documentBodyFontSize);
  return '.document{max-width:46rem;margin:24px auto;padding:32px 40px;'
      'background:${t.slideBackgroundColor};color:${t.textColor};'
      '--ocideck-accent:${t.accentColor};'
      'font-family:$family;font-size:${bodyFontSize.toStringAsFixed(1)}px;'
      'line-height:1.65;border-radius:4px;'
      'box-shadow:0 4px 24px rgba(0,0,0,.4)}'
      '.document h1{color:var(--ocideck-title-color,'
      '${t.effectiveDocumentHeadingColor})}'
      // h2 tot en met h6, niet alleen h2: de documentweergave in de app
      // kleurt élke subkop met het accent, en tot hier deed de export dat
      // alleen voor h2 — een `###` viel in de export stil terug op de
      // bodykleur en zei op papier dus iets anders dan op het scherm.
      '.document h2,.document h3,.document h4,.document h5,.document h6'
      '{color:${t.effectiveDocumentSubheadingColor}}'
      '.document a{color:${t.accentColor}}'
      '.document pre{background:${t.codeBackgroundColor};color:${t.codeTextColor};'
      'border:1px solid ${t.codeTextColor}38;border-radius:6px;padding:16px;'
      'font-family:$codeFamily}'
      '.document pre code{color:${t.codeTextColor};background:transparent}'
      // Inline `code` krijgt een tint van de tekstkleur, niet het codeblok-vlak
      // erboven — dezelfde som als `AppTheme.inlineCodeBackground` in de app,
      // want wat je op het scherm ziet hoort te zijn wat je afdrukt. `1F` is
      // 12% van 255. De regel hierboven is specifieker, dus code *in* een blok
      // blijft doorzichtig.
      '.document code{font-family:$codeFamily;background:${t.textColor}1F}'
      // Een vlak in een tint van het accent, met een streep ervoor — dezelfde
      // vorm als de documentweergave in de app en als de PDF-export. Stond hier
      // eerder als `opacity:.85`: dat dempt het citaat in plaats van het aan te
      // zetten, en dan zegt het blad iets anders dan het scherm. `1A` is 10% van
      // 255, dezelfde tint als `quoteBg`.
      '.document blockquote{border-left:3px solid ${t.accentColor};'
      'background:${t.accentColor}1A;margin:.6em 0;padding:8px 14px;'
      'border-radius:0 6px 6px 0}'
      '.document th{background:${t.tableHeaderBackgroundColor};'
      'color:${t.tableHeaderTextColor};${_documentTableBorderCss(t)}'
      'padding:${_documentTableCellPadding(t)}}'
      '.document td{color:${t.tableTextColor};${_documentTableBorderCss(t)}'
      'padding:${_documentTableCellPadding(t)}}'
      '${_documentTableZebraCss(t)}'
      '${_documentTableAccentHeaderCss(t)}'
      '.document-header,.document-footer{display:flex;align-items:center;gap:14px;'
      'min-height:42px;color:$bandText;background:$bandBackground;font-size:12px}'
      '.document-header{border-bottom:1px solid ${t.accentColor}8c;margin-bottom:24px}'
      '.document-footer{border-top:1px solid ${t.accentColor}8c;margin-top:24px}'
      '.document-header-text,.document-footer-text{flex:1;min-width:0;'
      'display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:4;'
      'overflow:hidden}'
      '.document-page-number{white-space:nowrap;font-variant-numeric:tabular-nums}'
      '.document-page-number::after{content:"1"}'
      '.document-logo{display:inline-flex;align-items:center;flex:0 0 auto}'
      '.document-logo img{display:block;width:${logoSize}px;max-width:70%;'
      'max-height:${logoHeight}px;height:auto;object-fit:contain}';
}

/// De vorm van de drie keuze-menu-indelingen (#1162). Thema-onafhankelijk, net
/// als de rapportage-opmaak: alleen de layout staat hier, de kleuren
/// (rand/vulling uit het accent, of een rustige rand uit de tekstkleur) zet
/// [renderMenuSlide] inline per blok. `grid-auto-rows` geeft elke rij dezelfde
/// hoogte, zodat het een net raster blijft; de afbeelding staat als kleine
/// vierkante duim náást de tekst, zoals in de app. `menu-stack` is hetzelfde
/// raster met één kolom en lagere rijen (de indeling "onder elkaar"), en
/// `menu-ring` zet de schijven op de plek die [renderMenuSlide] per schijf als
/// percentage meegeeft. De hoverlift maakt een aanklikbaar (doel)blok voelbaar
/// in een geopende export.
const _menuCss = r'''
.slide .menu-grid{display:grid;gap:22px;margin:.5em 0;grid-auto-rows:180px}
.slide .menu-stack{grid-template-columns:1fr;grid-auto-rows:120px;gap:16px}
.slide .menu-category{margin:.6em 0 .2em;font-size:26px;font-weight:700;opacity:.75}
.slide .menu-card{display:flex;flex-direction:row;align-items:center;gap:18px;padding:16px 20px;overflow:hidden;border:2px solid;border-radius:16px;text-decoration:none;color:inherit}
.slide .menu-card .menu-thumb{flex:0 0 auto;width:96px;height:96px;border-radius:12px;object-fit:cover}
.slide .menu-card .menu-text{flex:1 1 auto;min-width:0}
.slide .menu-card .menu-label{font-size:28px;font-weight:600;line-height:1.2}
.slide .menu-card .menu-desc{margin-top:4px;font-size:20px;line-height:1.25;opacity:.72}
.slide .menu-card .menu-arrow{flex:0 0 auto;font-size:28px;line-height:1}
.slide a.menu-card,.slide a.menu-disc{transition:filter .12s ease}
.slide a.menu-card:hover,.slide a.menu-disc:hover{filter:brightness(1.06)}
.slide .menu-dense{grid-auto-rows:110px;gap:14px}
.slide .menu-dense .menu-card{gap:12px;padding:10px 14px}
.slide .menu-dense .menu-card .menu-thumb{width:60px;height:60px}
.slide .menu-dense .menu-card .menu-label{font-size:20px}
.slide .menu-dense .menu-card .menu-desc{font-size:15px}
.slide .menu-ring{position:relative;width:100%;aspect-ratio:1;margin:.5em auto}
.slide .menu-disc{position:absolute;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;padding:10px;overflow:hidden;border:2px solid;border-radius:50%;text-align:center;text-decoration:none;color:inherit}
.slide .menu-disc .menu-disc-thumb{width:38%;aspect-ratio:1;border-radius:50%;object-fit:cover}
.slide .menu-disc .menu-label{font-size:20px;font-weight:600;line-height:1.15;overflow:hidden;overflow-wrap:anywhere}
.slide .menu-disc .menu-desc{font-size:15px;line-height:1.15;opacity:.8;overflow:hidden;overflow-wrap:anywhere}
''';

/// De opmaak van de zes rapportagedia's. Ook thema-onafhankelijk: kleuren die
/// betekenis dragen staan inline op de rij die ze beschrijft, en de accentkleur
/// komt via `--ocideck-accent` binnen.
const _reportingCss = r'''
.slide .rep{margin:.2em 0}
.slide .rep-title{font-size:40px;font-weight:700;margin:0 0 .35em;line-height:1.15}
.slide .rep-sub{font-size:22px;margin:.1em 0;opacity:.75}
.slide .rep-totals{font-size:20px;font-weight:600;opacity:.65;margin:.5em 0 0;padding-top:.4em;border-top:1px solid currentColor}
.slide .rep-bar{position:relative;height:14px;border-radius:7px;background:rgba(100,116,139,.22);overflow:hidden;min-width:2px}
.slide .rep-bar>i{position:absolute;left:0;top:0;bottom:0;display:block;border-radius:7px}
.slide .rep-progress{display:flex;align-items:center;gap:16px;margin:.5em 0 .2em}
.slide .rep-progress .rep-bar{flex:0 0 58%}
.slide .rep-progress span{font-size:21px;opacity:.75}
.slide .rep-table{width:100%;border-collapse:collapse;margin:.4em 0 0;table-layout:auto}
/* Een rapportagetabel is geen tabeldia: de gevulde kopbalk en de gekleurde
   cellen die het thema aan `th`/`td` geeft, horen hier niet. Expliciet
   terugzetten, want zonder deze regel kleurt het thema ook de objectnamen en de
   kolomkoppen van een scope-matrix als tabelkop. */
.slide .rep-table th,.slide .rep-table td{border:0;background:none;color:inherit;padding:7px 10px;font-size:21px;text-align:left;vertical-align:middle}
.slide .rep-table thead th{font-size:17px;font-weight:700;opacity:.55;text-transform:none;padding-bottom:2px}
.slide .rep-table thead tr{border-bottom:1px solid rgba(100,116,139,.35)}
.slide .rep-table tbody tr+tr{border-top:1px solid rgba(100,116,139,.15)}
.slide .rep-table tbody th,.slide .rep-table tfoot th{font-weight:600}
.slide .rep-table tfoot tr{border-top:1px solid rgba(100,116,139,.35)}
.slide .rep-table tfoot td,.slide .rep-table tfoot th{font-size:23px;font-weight:700;opacity:.9}
.slide .rep-num{text-align:right;font-weight:700;font-variant-numeric:tabular-nums;white-space:nowrap}
.slide .rep-unknown{opacity:.45;font-weight:400}
.slide .rep-barcell{width:38%;padding-right:18px}
.slide .rep-chip{display:inline-block;padding:2px 12px;border-radius:999px;font-size:18px;font-weight:600;white-space:nowrap}
.slide .sc-grid{display:flex;flex-wrap:wrap;gap:18px}
.slide .sc-card{flex:1 1 200px;min-width:180px;border:1px solid rgba(100,116,139,.28);border-radius:10px;overflow:hidden}
.slide .sc-rule{height:7px;background:var(--ocideck-accent)}
.slide .sc-body{padding:16px 18px 18px}
.slide .sc-label{font-size:20px;font-weight:600;opacity:.7;margin:0 0 .2em}
.slide .sc-value{font-size:54px;font-weight:700;line-height:1;letter-spacing:-.02em;margin:0}
.slide .sc-unit{font-size:26px;font-weight:600;opacity:.6;margin-left:.25em}
.slide .sc-change{display:inline-block;margin:.35em 0 0;padding:2px 12px;border-radius:999px;font-size:20px;font-weight:700}
.slide .sc-prev{font-size:18px;opacity:.45;margin:.3em 0 0}
.slide .dc-headline{display:flex;align-items:baseline;gap:14px;margin:.2em 0 .5em}
.slide .dc-headline strong{font-size:52px;font-weight:800;line-height:1;color:#B91C1C}
.slide .dc-headline span{font-size:21px;font-weight:600;opacity:.65}
.slide .dc-kind{display:block;font-size:17px;font-weight:400;opacity:.55}
.slide .dc-unowned{font-weight:700}
.slide .fs-chart{display:flex;align-items:flex-end;gap:28px;margin-top:.7em}
.slide .fs-col{flex:1 1 0;display:flex;flex-direction:column;align-items:center}
.slide .fs-bar{position:relative;width:100%;max-width:96px;height:250px;background:rgba(100,116,139,.09);border-radius:4px}
.slide .fs-bar>i{position:absolute;left:0;right:0;bottom:0;display:block;border-radius:4px 4px 0 0;min-height:2px}
.slide .fs-count{font-size:26px;font-weight:700;margin:.25em 0 0}
.slide .fs-band{font-size:19px;font-weight:600;opacity:.65;margin:0;text-align:center}
''';

/// Feature 3: de `@page`-regel voor paginamaat en marges. Top-level CSS
/// (buiten `@media print` — `@page` is zelf al een print-regel). Leeg wanneer
/// geen van beide is gezet, zodat de browser-default geldt.
String _pageAtRuleCss(PageSizeSpec? size, PageMargins? margins) {
  if (size == null && margins == null) return '';
  // De marges zijn die van de auteur, onaangeroerd. Ze werden vroeger opgehoogd
  // om een strook voor de kop- en voetband vrij te houden; die band staat sinds
  // het afdrukraam (`.print-frame`) binnen de tekstspiegel en houdt zijn eigen
  // ruimte vrij. Ophogen zou de ruimte dus twee keer reserveren.
  final parts = <String>[];
  if (size != null) {
    parts.add(
      'size:${margins == null ? size.cssName : size.cssSizeWith(margins)}',
    );
  }
  if (margins != null) {
    parts.add('margin:${margins.cssMargin}');
    // De afloopdoos hoort bij CSS Paged Media. De vergrote `size` hierboven
    // doet het werk dat élke afdrukmotor honoreert; dit is de aanvulling voor
    // een motor die de standaard kent. Snijtekens (`marks`) staan er bewust
    // niet bij — zie [PageMargins].
    if (margins.hasBleed) {
      parts.add('bleed:${_fmtBleedMm(margins.bleedMm)}mm');
    }
  }
  return '@page{${parts.join(';')}}';
}

/// Millimeters zonder overbodige nullen — `3` in plaats van `3.0`.
String _fmtBleedMm(double mm) =>
    mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : mm.toString();
