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
''';
