// Pure-Dart language registry — deliberately free of any Flutter import.
//
// Build tooling that runs on the standalone Dart VM (`dart run`, e.g.
// `make translate-docs-check`) needs the list of interface languages and the
// documentation's base language. It cannot get them from [AppLocalizations] or
// [DocumentationService]: those live in libraries that import
// `package:flutter/material.dart` and `dart:ui`, and the standalone VM cannot
// compile that graph (under some toolchains it does not even fail cleanly — the
// FFI use-site transformer crashes). So the data lives here, with no Flutter
// dependency, and both the app and the tooling read the same single source.
//
// [AppLocalizations.languageNames] and [DocumentationService.baseLanguage]
// re-expose these constants, so the app keeps its existing API.
library;

/// Display name of every interface language OciDeck ships, keyed by its code.
///
/// Adding a language is more than one line — see the new-language checklist —
/// but this map is where the canonical set of codes lives.
const Map<String, String> kLanguageNames = {
  'nl': 'Nederlands',
  'en': 'English',
  'it': 'Italiano',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'fy': 'Frysk',
  'pap': 'Papiamento',
  'la': 'Latina',
  'id': 'Bahasa Indonesia',
  'pl': 'Polski',
  'uk': 'Українська',
  'gsw': 'Schwiizerdütsch',
  'el': 'Ελληνικά',
  'da': 'Dansk',
  'sv': 'Svenska',
  'hr': 'Hrvatski',
  'cs': 'Čeština',
  'fi': 'Suomi',
  'bg': 'Български',
  'lv': 'Latviešu',
  'lt': 'Lietuvių',
  'mt': 'Malti',
  'et': 'Eesti',
  'hu': 'Magyar',
  'ga': 'Gaeilge',
  'pt': 'Português',
  'ro': 'Română',
  'sl': 'Slovenščina',
  'sk': 'Slovenčina',
  'tlh': 'tlhIngan Hol',
  'tr': 'Türkçe',
};

/// The language the documentation is authored in. Every other language is a
/// generated `.<code>.md` variant; see `DocumentationService`. It is one of the
/// [kLanguageNames] codes, and `translate_docs.dart` excludes it from the set of
/// languages it translates into.
const String kDocsBaseLanguage = 'en';
