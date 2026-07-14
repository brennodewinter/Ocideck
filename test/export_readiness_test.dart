import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/classification_policy.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/export_readiness.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/quality_export_policy.dart';

SlideQualityResult _resultWith({int errors = 0, int warnings = 0}) {
  return SlideQualityResult([
    for (var i = 0; i < errors; i++)
      const SlideQualityIssue(
        slideIndex: 0,
        kind: SlideQualityIssueKind.missingMediaFile,
        category: SlideQualityCategory.altText,
        severity: MarkdownValidationSeverity.error,
      ),
    for (var i = 0; i < warnings; i++)
      const SlideQualityIssue(
        slideIndex: 0,
        kind: SlideQualityIssueKind.textDensityWarning,
        category: SlideQualityCategory.textDensity,
        severity: MarkdownValidationSeverity.warning,
      ),
  ]);
}

void main() {
  const allow = ExportDecision.allow();
  const noQualityIssues = QualityExportDecision.allow();

  test('alles open → ready', () {
    final readiness = evaluateExportReadiness(
      needsSave: false,
      classificationDecision: allow,
      qualityDecision: noQualityIssues,
    );
    expect(readiness.status, ExportReadinessStatus.ready);
    expect(readiness.canOpenExport, isTrue);
  });

  test('opslaan gaat vóór alle andere gates', () {
    final readiness = evaluateExportReadiness(
      needsSave: true,
      classificationDecision: ExportDecision.block('TLP'),
      qualityDecision: QualityExportDecision.needsAcknowledgement(
        errorCount: 2,
        warningCount: 1,
        canAcknowledge: false,
      ),
    );
    expect(readiness.status, ExportReadinessStatus.needsSave);
    expect(readiness.canOpenExport, isFalse);
  });

  test('classificatieblokkade gaat vóór kwaliteit en draagt de reden', () {
    final readiness = evaluateExportReadiness(
      needsSave: false,
      classificationDecision: ExportDecision.block('reden van beleid'),
      qualityDecision: QualityExportDecision.needsAcknowledgement(
        errorCount: 1,
        warningCount: 0,
      ),
    );
    expect(readiness.status, ExportReadinessStatus.blockedByClassification);
    expect(readiness.blockReason, 'reden van beleid');
  });

  test('harde kwaliteitsblokkade wordt blockedByQuality met tellingen', () {
    final policy = QualityExportPolicy(blockOnErrors: true);
    final readiness = evaluateExportReadiness(
      needsSave: false,
      classificationDecision: allow,
      qualityDecision: policy.evaluate(_resultWith(errors: 2, warnings: 3)),
    );
    expect(readiness.status, ExportReadinessStatus.blockedByQuality);
    expect(readiness.errorCount, 2);
    expect(readiness.warningCount, 3);
    expect(readiness.canOpenExport, isTrue);
  });

  test('bevestigbare kwaliteitsmeldingen worden qualityWarnings', () {
    const policy = QualityExportPolicy();
    final readiness = evaluateExportReadiness(
      needsSave: false,
      classificationDecision: allow,
      qualityDecision: policy.evaluate(_resultWith(warnings: 3)),
    );
    expect(readiness.status, ExportReadinessStatus.qualityWarnings);
    expect(readiness.warningCount, 3);
    expect(readiness.canOpenExport, isTrue);
  });

  test('uitgeschakeld kwaliteitsbeleid → ready ondanks meldingen', () {
    final policy = QualityExportPolicy.fromEnabled(false);
    final readiness = evaluateExportReadiness(
      needsSave: false,
      classificationDecision: allow,
      qualityDecision: policy.evaluate(_resultWith(errors: 1)),
    );
    expect(readiness.status, ExportReadinessStatus.ready);
  });

  test('werkt samen met het echte enforcement-beleid', () {
    const enforcement = ClassificationEnforcementPolicy(
      requireClassification: true,
    );
    final readiness = evaluateExportReadiness(
      needsSave: false,
      classificationDecision: enforcement.evaluate(TlpLevel.none),
      qualityDecision: noQualityIssues,
    );
    expect(readiness.status, ExportReadinessStatus.blockedByClassification);
    expect(readiness.blockReason, isNotNull);
  });

  group('de privacy-gate telt mee', () {
    // Drie onafgehandelde bevindingen; de rest is bewust afgehandeld.
    const openstaand = PrivacyExportSummary(unresolved: 3, accepted: 2);

    test('zonder privacybeslissing blijft alles zoals het was', () {
      // De parameter is optioneel: elke bestaande aanroep krijgt "allow" en
      // gedraagt zich exact als vóór deze wijziging.
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: allow,
        qualityDecision: noQualityIssues,
      );
      expect(readiness.status, ExportReadinessStatus.ready);
      expect(readiness.privacyUnresolved, 0);
    });

    test('gate op blokkeren → blockedByPrivacy, met de telling', () {
      // Dit is de melding die ontbrak: hiervóór stond hier "Klaar voor export",
      // in het groen, met drie onafgehandelde bevindingen in het deck.
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.block);
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: allow,
        qualityDecision: noQualityIssues,
        privacyDecision: policy.evaluate(openstaand),
      );
      expect(readiness.status, ExportReadinessStatus.blockedByPrivacy);
      expect(readiness.privacyUnresolved, 3);
      // De dialoog mag wél open: daar staat hoe je het oplost.
      expect(readiness.canOpenExport, isTrue);
    });

    test('gate op waarschuwen → privacyWarnings', () {
      const policy = PrivacyExportPolicy();
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: allow,
        qualityDecision: noQualityIssues,
        privacyDecision: policy.evaluate(openstaand),
      );
      expect(readiness.status, ExportReadinessStatus.privacyWarnings);
      expect(readiness.privacyUnresolved, 3);
    });

    test('gate uit → ready, ook met openstaande bevindingen', () {
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.off);
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: allow,
        qualityDecision: noQualityIssues,
        privacyDecision: policy.evaluate(openstaand),
      );
      expect(readiness.status, ExportReadinessStatus.ready);
    });

    test('alles afgehandeld → ready', () {
      // De gate straft geen persoonsgegevens af, hij straft onopgemerkte
      // persoonsgegevens af.
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.block);
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: allow,
        qualityDecision: noQualityIssues,
        privacyDecision: policy.evaluate(
          const PrivacyExportSummary(accepted: 4, redacted: 1),
        ),
      );
      expect(readiness.status, ExportReadinessStatus.ready);
    });

    test('privacy gaat vóór kwaliteit als beide waarschuwen', () {
      // Een IBAN die de deur uit gaat is van een andere orde dan een bullet te
      // veel.
      const policy = PrivacyExportPolicy();
      const qualityPolicy = QualityExportPolicy();
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: allow,
        qualityDecision: qualityPolicy.evaluate(_resultWith(warnings: 3)),
        privacyDecision: policy.evaluate(openstaand),
      );
      expect(readiness.status, ExportReadinessStatus.privacyWarnings);
    });

    test('een TLP-blokkade gaat nog steeds vóór privacy', () {
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.block);
      final readiness = evaluateExportReadiness(
        needsSave: false,
        classificationDecision: ExportDecision.block('TLP'),
        qualityDecision: noQualityIssues,
        privacyDecision: policy.evaluate(openstaand),
      );
      expect(readiness.status, ExportReadinessStatus.blockedByClassification);
    });
  });
}
