/// LibrePlan import-orchestratie: fetch → parse → convert → slides.
///
/// Deze laag combineert [LibreplanClient] (fetch), [libreplan_xml.dart] (parse)
/// en [libreplan_converters.dart] (convert) tot één operatie die een lijst
/// slides retourneert. De UI-laag (import-dialoog) voegt ze toe aan het deck.
///
/// De orchestratie is testbaar: de client is injecteerbaar, en de fetch-
/// methodes kunnen per slide-type worden gekozen via [LibreplanImportOptions].

import '../../models/slide.dart';
import 'libreplan_client.dart';
import 'libreplan_converters.dart';
import 'libreplan_xml.dart';

/// Welke slides de import moet produceren. De gebruiker kiest dit in de
/// import-dialoog; default is alles aan.
class LibreplanImportOptions {
  final bool gantt;
  final bool wbs;
  final bool resources;
  final bool timesheet;
  final bool resourceLoad;
  final bool status;
  final bool milestones;
  final bool criticalPath;

  const LibreplanImportOptions({
    this.gantt = true,
    this.wbs = true,
    this.resources = true,
    this.timesheet = true,
    this.resourceLoad = true,
    this.status = true,
    this.milestones = true,
    this.criticalPath = true,
  });

  bool get anyEnabled =>
      gantt ||
      wbs ||
      resources ||
      timesheet ||
      resourceLoad ||
      status ||
      milestones ||
      criticalPath;
}

/// Resultaat van een import: de geproduceerde slides per categorie, plus
/// eventuele fouten (per categorie, niet-fataal).
class LibreplanImportResult {
  final List<Slide> slides;
  final List<String> warnings;

  const LibreplanImportResult({
    this.slides = const [],
    this.warnings = const [],
  });

  bool get hasWarnings => warnings.isNotEmpty;
}

/// De import-orchestrator. Haalt data op van LibrePlan via [client], parseert
/// het, zet het om naar slides, en retourneert het resultaat.
class LibreplanImporter {
  LibreplanImporter(this.client);

  final LibreplanClient client;

  Future<LibreplanImportResult> import({
    LibreplanImportOptions options = const LibreplanImportOptions(),
  }) async {
    if (!options.anyEnabled) {
      return const LibreplanImportResult(
        warnings: ['Geen slide-types geselecteerd.'],
      );
    }

    final slides = <Slide>[];
    final warnings = <String>[];

    LibreplanOrder? order;
    if (options.gantt ||
        options.wbs ||
        options.status ||
        options.milestones ||
        options.criticalPath) {
      try {
        final xml = await client.fetchOrders();
        final orders = parseOrderList(xml);
        if (orders.isEmpty) {
          warnings.add('Geen projecten gevonden op de LibrePlan-server.');
        } else {
          order = orders.first;
          if (orders.length > 1) {
            warnings.add(
              '${orders.length} projecten gevonden, importeer het eerste '
              '("${order.name}"). Selecteer een specifiek project via de '
              'projectcode voor de andere.',
            );
          }
        }
      } on LibreplanRequestException catch (e) {
        warnings.add('Projecten ophalen mislukt: ${e.message}');
      }
    }

    if (order != null) {
      if (options.gantt) slides.add(libreplanOrderToGantt(order!));
      if (options.wbs) slides.add(libreplanOrderToWbs(order!));
      if (options.status) slides.add(libreplanOrderToCockpit(order!));
      if (options.milestones) slides.add(libreplanOrderToTimeline(order!));
      if (options.criticalPath) slides.add(libreplanOrderToCriticalPath(order!));
    }

    if (options.resources) {
      try {
        final xml = await client.fetchResources();
        final resources = parseResourceList(xml);
        if (resources.isEmpty) {
          warnings.add('Geen resources gevonden.');
        } else {
          slides.add(libreplanResourcesToTable(resources));
        }
      } on LibreplanRequestException catch (e) {
        warnings.add('Resources ophalen mislukt: ${e.message}');
      }
    }

    if (options.timesheet) {
      try {
        final xml = await client.fetchWorkReports();
        final reports = parseWorkReportList(xml);
        if (reports.isEmpty) {
          warnings.add('Geen werkrapporten gevonden.');
        } else {
          slides.add(libreplanWorkReportsToTable(reports));
        }
      } on LibreplanRequestException catch (e) {
        warnings.add('Werkrapporten ophalen mislukt: ${e.message}');
      }
    }

    if (options.resourceLoad) {
      try {
        final end = DateTime.now();
        final start = end.subtract(const Duration(days: 30));
        final xml = await client.fetchResourceHours(start, end);
        final hours = parseResourceHoursList(xml);
        if (hours.isEmpty) {
          warnings.add('Geen resource-uren gevonden in de laatste 30 dagen.');
        } else {
          slides.add(libreplanResourceHoursToChart(hours));
        }
      } on LibreplanRequestException catch (e) {
        warnings.add('Resource-uren ophalen mislukt: ${e.message}');
      }
    }

    return LibreplanImportResult(slides: slides, warnings: warnings);
  }
}
