// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// De stylesheet van de export: het thema-onafhankelijke blok dat altijd meegaat,
// en de kleuren/letters voor een export zonder [ThemeProfile]. Uitgetild uit de
// hoofdbibliotheek voor de bestandsgrootte-ratchet; `_themedCss` blijft daar,
// omdat die het profiel nodig heeft.
part of '../marp_html_service.dart';

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
.slide{position:relative;width:1280px;min-height:720px;margin:24px auto;padding:48px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.4);border-radius:4px}
.slide h1{font-size:48px;margin:.15em 0}
.slide h2{font-size:34px;margin:.15em 0}
.slide p,.slide li{font-size:24px;line-height:1.45}
.slide pre.mermaid{background:transparent;border:0;text-align:center}
.slide img{max-width:100%}
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
.slide .mermaid-error{margin:.6em 0;padding:16px 20px;border:1px solid #B91C1C;border-left-width:6px;border-radius:6px;background:#FEE2E2;color:#7F1D1D;text-align:left}
.slide .mermaid-error-title{font-size:22px;font-weight:700;margin:0 0 .3em;color:#7F1D1D}
.slide .mermaid-error-label{font-size:16px;font-weight:600;margin:.7em 0 .2em;opacity:.8;color:#7F1D1D}
.slide .mermaid-error-detail,.slide .mermaid-error-source{margin:0;padding:10px 12px;background:rgba(255,255,255,.65);border:0;border-radius:4px;font-size:15px;line-height:1.35;white-space:pre-wrap;overflow:auto;max-height:220px;color:#7F1D1D}
.tlp-export-banner{position:fixed;top:0;left:0;right:0;background:#000;color:#ffc000;text-align:center;font:700 14px/2.4 monospace;z-index:9999;letter-spacing:.06em}
@media print{body{background:#fff}.slide{margin:0;box-shadow:none;border-radius:0;page-break-after:always;width:100%;min-height:100vh}}
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

/* De melding dat er ongecontroleerde AI-tekst in dit document staat.
   Kwam van de juridische tak; deze CSS verhuisde intussen hierheen. */
.ai-export-banner{position:fixed;left:0;right:0;background:#3a2c00;color:#ffd75e;text-align:center;font:600 13px/2.4 system-ui,sans-serif;z-index:9998}
''';

/// De stylesheet die vóór het themablok in elk document gaat: de structuur plus
/// de rapportagedia's.
///
/// Een functie en geen derde constante, zodat de aanroeper niet hoeft te weten
/// uit hoeveel stukken dit bestaat.
String exportBaseCss() => '$_structuralCss\n$_reportingCss';

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
