// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// De opmaak van de zes rapportagedia's. Thema-onafhankelijk, dus hij hangt aan
// [MarpHtmlService._structuralCss] en niet aan het themablok — dezelfde les als
// bij de tijdlijn en de ondertekening, die hun opmaak verloren zodra er een
// thema meeging.
//
// Kleuren komen binnen langs twee wegen: `--ocideck-accent` uit het thema, en
// inline `style`-waarden op de elementen die per rij verschillen (balkbreedte,
// oordeelkleur). Geen kleuren die betekenis dragen in dit blok — die horen bij
// de rij die ze beschrijft, niet bij het stylesheet.
part of '../marp_html_service.dart';

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
