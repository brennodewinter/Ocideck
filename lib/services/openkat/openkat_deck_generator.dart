import '../../models/deck.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import '../../models/slide.dart';
import 'openkat_aggregator.dart';
import 'openkat_report_composer.dart';
import 'openkat_report_facts.dart';
import 'openkat_report_scenarios.dart';
import 'openkat_slide_provenance.dart';

export 'openkat_report_engine.dart';

/// Compatibiliteitsfaçade voor de bestaande import- en herimportketen.
///
/// Nieuwe aanroepers gebruiken [OpenKatReportEngine]. Deze klasse behoudt het
/// oude managementdeckcontract en vooral de markersemantiek van herimport.
class OpenKatDeckGenerator {
  final OpenKatAggregator aggregator;

  const OpenKatDeckGenerator({this.aggregator = const OpenKatAggregator()});

  Deck generate(
    List<OpenKatOrganization> organizations, {
    String title = 'OpenKAT managementoverzicht',
    String? outputPath,
  }) {
    final facts = OpenKatReportFacts(organizations, aggregator: aggregator);
    final request = OpenKatReportRequest(
      scenarioId: 'management-overview',
      scope: const OpenKatReportScope.portfolio(),
      currentAsOf: _latestReportDate(organizations),
      title: title,
    );
    final plan = const OpenKatManagementScenario().compose(facts, request);
    return OpenKatReportComposer(
      facts,
    ).compose(request, plan, outputPath: outputPath);
  }

  Deck update(Deck existing, List<OpenKatOrganization> organizations) {
    final fresh = generate(organizations, title: existing.title);
    return updateGenerated(existing, fresh);
  }

  /// Vervangt alleen gegenereerde OpenKAT-views door een vers scenariodeck.
  ///
  /// De motor maakt bewust een nieuw deck. Deze façade bewaart bij bijwerken
  /// handmatige dia's en kopieën van het geopende deck. Een gegenereerde dia
  /// heeft een deterministische id; een handmatige kopie krijgt juist een
  /// nieuwe. Daardoor blijft het oorspronkelijke blok herkenbaar als een kopie
  /// met dezelfde view-marker ervoor is gezet of elders heen is verplaatst.
  Deck updateGenerated(Deck existing, Deck fresh) {
    final freshByView = <String, Slide>{
      for (final slide in fresh.slides) ?_viewIdOf(slide): slide,
    };
    final originalByView = <String, Slide>{};
    final existingByView = <String, List<Slide>>{};
    for (final slide in existing.slides) {
      final view = _viewIdOf(slide);
      if (view != null) {
        existingByView.putIfAbsent(view, () => []).add(slide);
      }
    }
    for (final entry in existingByView.entries) {
      final view = entry.key;
      final candidates = entry.value;
      final freshSlide = freshByView[view];
      final markedOrigins = candidates.where(_isGeneratedOrigin).toList();
      if (markedOrigins.length == 1) {
        originalByView[view] = markedOrigins.single;
        continue;
      }
      if (markedOrigins.length > 1) {
        throw OpenKatUnsafeUpdateException(view);
      }
      if (freshSlide != null) {
        final exact = candidates
            .where((slide) => slide.id == freshSlide.id)
            .toList();
        if (exact.length == 1) {
          // Een nog geopende legacygeneratie heeft dezelfde deterministische
          // id als haar verse tegenhanger. De vervanging krijgt de duurzame
          // origin-marker en is vanaf dan ook na heropenen herkenbaar.
          originalByView[view] = exact.single;
          continue;
        }
      }
      throw OpenKatUnsafeUpdateException(view);
    }
    final slides = <Slide>[];
    for (final slide in existing.slides) {
      final view = _viewIdOf(slide);
      if (view == null || !identical(originalByView[view], slide)) {
        slides.add(slide);
        continue;
      }
      final replacement = freshByView.remove(view);
      if (replacement != null) {
        slides.add(
          replacement.copyWith(
            privacy: slide.privacy,
            clearPrivacy: slide.privacy == null,
          ),
        );
      }
    }
    slides.addAll(
      fresh.slides.where((slide) => freshByView.containsKey(_viewIdOf(slide))),
    );
    return existing.copyWith(
      title: fresh.title,
      language: fresh.language,
      slides: slides,
    );
  }

  static final RegExp _viewMarker = RegExp(
    r'<!--\s*ocideck_openkat_view:\s*([^\s>]+)\s*-->',
  );

  String? _viewIdOf(Slide slide) =>
      _viewMarker.firstMatch(slide.notes)?.group(1);

  bool _isGeneratedOrigin(Slide slide) =>
      OpenKatSlideProvenance.isUnchangedGeneratedOrigin(slide);

  DateTime _latestReportDate(List<OpenKatOrganization> organizations) {
    DateTime? latest;
    for (final organization in organizations) {
      for (final snapshot in organization.snapshots) {
        if (!snapshot.usable) continue;
        if (latest == null || snapshot.reportDate.isAfter(latest)) {
          latest = snapshot.reportDate;
        }
      }
    }
    return latest ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

/// Een bestaand deck waarvan het gegenereerde origineel niet bewijsbaar is.
///
/// De UI biedt in dit geval een nieuw rapport aan; de bestaande dia's blijven
/// volledig ongewijzigd.
class OpenKatUnsafeUpdateException implements Exception {
  final String viewId;

  const OpenKatUnsafeUpdateException(this.viewId);
}
