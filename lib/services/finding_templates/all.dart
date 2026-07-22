// ── lib/services/finding_templates/ ──────────────────────────────────────────
// Alleen inhoud: één bestand per taal met de sjabloonteksten, plus dit bestand
// dat ze op taalcode ontsluit. Er staat hier geen logica — het parsen, zoeken
// en kiezen van een sjabloon zit in ../finding_template_library.dart, en de
// datatypes in lib/models/finding_template.dart.
//
// Een taal toevoegen is dus: een `<code>.dart` erbij en een regel in de map
// hieronder. Wat er per bestand wél en niet vertaald mag worden, staat in de
// kop van elk taalbestand en wordt bewaakt door
// test/finding_template_languages_test.dart. Overzicht: docs/SOURCE_MAP.md.
// ─────────────────────────────────────────────────────────────────────────────
//
// De sjabloonbronnen per taal, bij elkaar gebracht.
//
// Eén bestand per taal, net als lib/l10n/translations/: sjablonen zijn
// inhoud (data), geen UI-strings, dus ze gaan niet door `d(...)`. Ze worden
// opgezocht op de taal van het *rapport* (Deck.language), niet die van de
// interface — PENTEST_MIAUW §12.3.

import 'bg.dart';
import 'cs.dart';
import 'da.dart';
import 'de.dart';
import 'el.dart';
import 'en.dart';
import 'es.dart';
import 'et.dart';
import 'fi.dart';
import 'fr.dart';
import 'fy.dart';
import 'ga.dart';
import 'gsw.dart';
import 'hr.dart';
import 'hu.dart';
import 'id.dart';
import 'it.dart';
import 'la.dart';
import 'lt.dart';
import 'lv.dart';
import 'mt.dart';
import 'nl.dart';
import 'pap.dart';
import 'pl.dart';
import 'pt.dart';
import 'ro.dart';
import 'sk.dart';
import 'sl.dart';
import 'sv.dart';
import 'tlh.dart';
import 'tr.dart';
import 'uk.dart';

/// Taalcode → (slug → sjabloon-Markdown). `en` is de terugval en moet dus
/// altijd elke slug bevatten; guard: test/finding_template_languages_test.dart.
const Map<String, Map<String, String>> findingTemplateSources = {
  'bg': findingTemplatesBg,
  'cs': findingTemplatesCs,
  'da': findingTemplatesDa,
  'de': findingTemplatesDe,
  'el': findingTemplatesEl,
  'en': findingTemplatesEn,
  'es': findingTemplatesEs,
  'et': findingTemplatesEt,
  'fi': findingTemplatesFi,
  'fr': findingTemplatesFr,
  'fy': findingTemplatesFy,
  'ga': findingTemplatesGa,
  'gsw': findingTemplatesGsw,
  'hr': findingTemplatesHr,
  'hu': findingTemplatesHu,
  'id': findingTemplatesId,
  'it': findingTemplatesIt,
  'la': findingTemplatesLa,
  'lt': findingTemplatesLt,
  'lv': findingTemplatesLv,
  'mt': findingTemplatesMt,
  'nl': findingTemplatesNl,
  'pap': findingTemplatesPap,
  'pl': findingTemplatesPl,
  'pt': findingTemplatesPt,
  'ro': findingTemplatesRo,
  'sk': findingTemplatesSk,
  'sl': findingTemplatesSl,
  'sv': findingTemplatesSv,
  'tlh': findingTemplatesTlh,
  'tr': findingTemplatesTr,
  'uk': findingTemplatesUk,
};
