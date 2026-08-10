// Part of markdown_validator.dart — the vocabulary the checker validates
// against, split out to keep the validator itself under the file-size ratchet.
// Plain data: the class tokens, front-matter keys and comment directives that
// `MarkdownService`'s parser actually understands. Keep these in step with the
// parser — a name missing here makes the checker warn about something that
// really does work.
part of 'markdown_validator.dart';

const _knownClassTokens = {
  'title',
  'section',
  'two-bullets',
  'split',
  'quote',
  'video',
  'table',
  'code',
  'chart',
  'cockpit',
  'question',
  'timeline',
  'scorecard',
  'actions',
  // Keuze-menu (#1162): blokken als link-bullets.
  'menu',
  'assets',
  'discoveries',
  'finding',
  'findings-summary',
  'checklist',
  'scope-matrix',
  'sign-off',
  // Procesverbetering-engines (PROCESS_IMPROVEMENT §6).
  'matrix',
  'canvas',
  'tree',
  'flow',
  'phase-gate',
  // Managementsysteem-module (ISO_MANAGEMENTSYSTEEM §4).
  'control-status',
  'gantt',
  'timeline-horizontal',
  'timeline-vertical',
  'timeline-steps',
  'timeline-static',
  'logo-safe',
  'no-logo',
  'no-footer',
  'table-editable',
};

const _validListStyles = {'bullets', 'numbered', 'checklist', 'richText'};

// De front-matter-sleutels staan niet hier maar in `front_matter_merge.dart`
// ([kOwnedFrontMatterKeys]) — de checker leest diezelfde lijst.
//
// Dat is geen gemakzucht maar een gelijkheid die uit het formaatcontract volgt:
// een sleutel die OciDeck schrijft, leest hij ook (anders zou hij hem bij het
// opslaan kwijtraken), en een sleutel die hij leest maar niet schrijft zou bij
// het eerste opslaan verdwijnen. De twee lijsten zijn dus per definitie
// dezelfde, en twee kopieën ervan lopen alleen maar uit de pas. Deze stond
// eerder los en miste toen precies zeven sleutels die de parser wél las.

// Comment directives `_parseBlockDirectives` understands. A comment that looks
// like a directive (`_key:` / `ocideck_key:`) but is not one of these is
// passed through without visual effect — e.g. Marp's per-slide `_paginate`,
// `_header`, `_footer`, `_color` — so the validator explains the limitation.
const _supportedCommentDirectives = {
  '_class',
  '_style',
  '_color',
  '_backgroundColor',
  '_backgroundImage',
  '_header',
  '_footer',
  'tlp',
  'advance',
  'skip',
  'ocideck_detail',
  'ocideck_list_style',
  'ocideck_checklist_progress',
  // Checklist<->scope-koppeling; `_parseFindingLink` licht deze.
  'ocideck_checklist_scope',
  'ocideck_continue_numbering',
  'ocideck_continue_split',
  'ocideck_title_image_overlay',
  'ocideck_title_text_color',
  'ocideck_bullet_marker',
  'ocideck_timeline_duration',
  'ocideck_timeline_current',
  // Opgeheven per 0.1.0: de tweekolomsdia draagt haar inhoud in de zichtbare
  // `<ul><li>`. Nog wel bekend, zodat een bestand van vóór die versie niet vol
  // waarschuwingen komt te staan over commentaren die het gewoon nog mag
  // hebben; bij het opslaan verdwijnen ze.
  'ocideck_two_bullets_left',
  'ocideck_two_bullets_right',
  'ocideck_two_bullets_left_title',
  'ocideck_two_bullets_right_title',
  // Per-slide attestation link comments (PENTEST_MIAUW §3.1 / AI_ASSIST §16.3):
  // the parser lifts these in `_parseFindingLink`, so the checker must not flag
  // them as unsupported.
  'ocideck_finding_id',
  'ocideck_finding_role',
  'ocideck_ai_assisted',
  // Per-image directives the parser lifts before the generic scan
  // (crop focal point + WCAG alt-text, AI_ASSIST §6.1).
  'ocideck_image_focus',
  'ocideck_image_focus2',
  'ocideck_image_alt',
  'ocideck_image_alt2',
  // Per-slide privacy disposition (OCIWACHT §4.2): accept / shield /
  // redact. Zonder deze regel meldt de checker een onbekende directive.
  'ocideck_privacy',
  // Per-slide kwaliteitsdispositie: accept. De tegenhanger van
  // `ocideck_privacy` voor contrast-, dichtheids- en alt-tekstmeldingen.
  'ocideck_quality',
  // Welk verbetersjabloon een engine-dia volgt (PROCESS_IMPROVEMENT §3.1).
  'ocideck_template',
  'ocideck_layout',
  'ocideck_gantt_scale',
  'ocideck_gantt_sections',
  // Niet-lineaire navigatie (#1162): het stabiele dia-anker waar een menublok of
  // sprong-uit naar wijst, en de per-dia sprong-uit zelf.
  'ocideck_slide_anchor',
  'ocideck_next',
  // Taalbewuste getalnotatie in tabelcellen (render-time, opt-in per kolom).
  'ocideck_table_num_cols',
};
