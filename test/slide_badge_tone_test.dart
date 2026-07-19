// Welke kleur krijgt een badge, en waarom die?
//
// De kern van de afspraak: grijs betekent "hier is iets gevonden en jij hebt
// gezegd dat het zo mag" — niet "hier is niets". Dat onderscheid is precies wat
// er eerder wegviel, toen een afgehandelde slide spoorloos uit beeld verdween en
// er daarna uitzag als een schone slide.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/widgets/slides/slide_badge_tone.dart';

void main() {
  SlideQualityIssue issue(MarkdownValidationSeverity severity) =>
      SlideQualityIssue(
        slideIndex: 0,
        kind: SlideQualityIssueKind.bulletCountHigh,
        category: SlideQualityCategory.content,
        severity: severity,
      );

  PrivacyFinding finding(PrivacyConfidence confidence) => PrivacyFinding(
    ruleId: 'contact.name',
    family: PrivacyFamily.contact,
    confidence: confidence,
    slideIndex: 0,
    field: 'bullets',
    start: 0,
    end: 5,
    maskedSample: 'j…l',
  );

  group('kwaliteit', () {
    test('niets gevonden geeft geen badge', () {
      expect(qualityBadgeTone(const [], accepted: false), SlideBadgeTone.none);
    });

    test('een fout weegt zwaarder dan een waarschuwing', () {
      expect(
        qualityBadgeTone([
          issue(MarkdownValidationSeverity.warning),
          issue(MarkdownValidationSeverity.error),
        ], accepted: false),
        SlideBadgeTone.error,
      );
    });

    test('alleen tips geven geen badge', () {
      // Een tip is advies over vakmanschap. Op elke slide met een tip een badge
      // zetten maakt de lijst bont zonder iemand iets te vertellen.
      expect(
        qualityBadgeTone([
          issue(MarkdownValidationSeverity.informational),
        ], accepted: false),
        SlideBadgeTone.none,
      );
    });

    test('geaccepteerd wordt grijs, niet onzichtbaar', () {
      expect(
        qualityBadgeTone([
          issue(MarkdownValidationSeverity.error),
        ], accepted: true),
        SlideBadgeTone.accepted,
      );
    });

    test('accepteren op een schone slide geeft nog steeds niets', () {
      // Anders zou elke geaccepteerde slide een grijze badge houden ook nadat
      // het probleem zelf is opgelost.
      expect(qualityBadgeTone(const [], accepted: true), SlideBadgeTone.none);
    });
  });

  group('privacy', () {
    test('een zekere treffer waarschuwt', () {
      expect(
        privacyBadgeTone([finding(PrivacyConfidence.certain)], accepted: false),
        SlideBadgeTone.warning,
      );
    });

    test('een onzekere treffer krijgt de gedempte toon', () {
      // Anders dan bij kwaliteit krijgt een onzekere treffer hier wél een
      // badge: een mogelijk persoonsgegeven is een ander belang dan een tip
      // over bulletlengte. De toon zegt "kijk hier even", niet "dit gaat mis".
      expect(
        privacyBadgeTone([
          finding(PrivacyConfidence.possible),
        ], accepted: false),
        SlideBadgeTone.hint,
      );
    });

    test('één zekere treffer tussen onzekere maakt het een waarschuwing', () {
      expect(
        privacyBadgeTone([
          finding(PrivacyConfidence.possible),
          finding(PrivacyConfidence.likely),
        ], accepted: false),
        SlideBadgeTone.warning,
      );
    });

    test('geaccepteerd wordt grijs, ook bij een zekere treffer', () {
      expect(
        privacyBadgeTone([finding(PrivacyConfidence.certain)], accepted: true),
        SlideBadgeTone.accepted,
      );
    });
  });

  group('standen', () {
    test('alleen de open standen vragen nog om een beslissing', () {
      // Stuurt de dubbelklik: een gekleurde badge accepteer je, een grijze
      // draai je terug.
      expect(SlideBadgeTone.hint.isOpen, isTrue);
      expect(SlideBadgeTone.warning.isOpen, isTrue);
      expect(SlideBadgeTone.error.isOpen, isTrue);
      expect(SlideBadgeTone.accepted.isOpen, isFalse);
      expect(SlideBadgeTone.none.isOpen, isFalse);
    });

    test('een beslissing wint van elke ernst', () {
      // Zodra de auteur heeft beslist, spreekt de badge niet meer luid — hoe
      // ernstig de melding op zichzelf ook was. Dat ís de beslissing.
      expect(
        worstBadgeTone(SlideBadgeTone.error, SlideBadgeTone.accepted),
        SlideBadgeTone.accepted,
      );
      expect(
        worstBadgeTone(SlideBadgeTone.hint, SlideBadgeTone.error),
        SlideBadgeTone.error,
      );
    });

    test('de grijze toon verschilt zichtbaar van de gedempte', () {
      // Anders lezen "ik twijfel" en "jij hebt beslist" als hetzelfde.
      expect(
        SlideBadgeTone.accepted.background,
        isNot(SlideBadgeTone.hint.background),
      );
    });
  });
}
