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
  'finding',
  'findings-summary',
  'checklist',
  'scope-matrix',
  'sign-off',
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

// Front-matter keys MarkdownService._doParse actually reads. `marp` is the
// canonical Marp marker OciDeck assumes and deliberately ignores. Anything
// else (a typo, or a Marp option OciDeck does not implement like `header`,
// `footer`, `size`, `style`) is silently dropped by the parser, so the
// validator warns that it has no effect.
const _knownFrontMatterKeys = {
  'marp',
  'theme',
  'paginate',
  'title',
  'author',
  'organization',
  'version',
  'date',
  'description',
  'keywords',
  'tlp',
  // Rapportmetadata die de parser wél leest (zonder deze regels meldt de
  // checker "wordt genegeerd" bij sleutels die juist effect hebben).
  'language',
  'tool',
  'standards',
  'privacy',
  'ocideck_target_seconds',
  'ocideck_show_rehearsal_summary',
  'ocideck_play_only',
  'ocideck_finalized',
  'ocideck_seal_hash',
  'ocideck_seal_algo',
  'ocideck_seal_at',
  // RFC 3161-tijdstempel bij het zegel + MIAUW-uitzonderingen/-bevestigingen.
  'ocideck_seal_tsr',
  'ocideck_miauw_waivers',
  'ocideck_miauw_confirmations',
  'ocideck_sig_name',
  'ocideck_sig_role',
  'ocideck_sig_cert',
  'ocideck_sig_date',
  'ocideck_sig_statement',
  'ocideck_sig_typed',
  'ocideck_sig_image',
  'ocideck_style_profile',
};

// Comment directives `_parseBlockDirectives` understands. A comment that looks
// like a directive (`_key:` / `ocideck_key:`) but is not one of these is
// dropped without effect — e.g. Marp's per-slide `_paginate`, `_header`,
// `_footer`, `_color` — so the validator flags it.
const _supportedCommentDirectives = {
  '_class',
  '_style',
  'tlp',
  'advance',
  'skip',
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
};
