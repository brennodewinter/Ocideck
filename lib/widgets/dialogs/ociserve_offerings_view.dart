// De planning-sectie "Aanbod" (issues #2124, #2125 en #2126): het
// self-inschrijvingsaanbod van de organisatie, sessiekeuze per klassikale
// les, wachtlijst, voucherinvoer en de toelatingseisen.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart';
import '../../utils/log.dart';
import '../../utils/session_timezone.dart';
import '../../utils/voucher_code.dart';

/// Het self-aanbod voor één organisatie. Alleen uitvoeringen die de server
// zelf als inschrijfbaar markeert komen in de lijst — de client filtert niet
// zelf op vlaggen die de server al heeft toegepast.
class OciServeOfferingsView extends ConsumerStatefulWidget {
  const OciServeOfferingsView({
    super.key,
    required this.organizationId,
    this.onShowBookings,
  });

  final String organizationId;

  /// Wordt aangeroepen als de gebruiker na inschrijven naar "Mijn
  /// inschrijvingen" wil — de ouder schakelt dan van sectie.
  final VoidCallback? onShowBookings;

  @override
  ConsumerState<OciServeOfferingsView> createState() =>
      _OciServeOfferingsViewState();
}

class _OciServeOfferingsViewState extends ConsumerState<OciServeOfferingsView> {
  static const _maxPages = 5;

  final _voucherController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<OciServeOfferingSummary> _offerings = const [];
  String? _expandedId;
  Map<String, String> _selectedSessions = const {};
  bool _allowWaitlist = false;
  bool _submitting = false;
  String? _submitError;
  OciServeRegistration? _result;
  DateTime? _voucherBlockedUntil;

  @override
  void initState() {
    super.initState();
    ensureSessionTimezones();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _voucherController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifier = ref.read(ociServeProvider.notifier);
      final offerings = <OciServeOfferingSummary>[];
      String? cursor;
      for (var page = 0; page < _maxPages; page++) {
        final result = await notifier.courseOfferings(
          widget.organizationId,
          cursor: cursor,
        );
        offerings.addAll(result.offerings);
        cursor = result.nextCursor;
        if (cursor == null) break;
      }
      if (!mounted) return;
      setState(() {
        _offerings = offerings;
        _loading = false;
      });
    } catch (error, stack) {
      logError('OciServe: aanbod laden', error.runtimeType, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'load_failed';
      });
    }
  }

  OciServeOfferingSummary? get _expanded {
    for (final offering in _offerings) {
      if (offering.id == _expandedId) return offering;
    }
    return null;
  }

  void _expand(OciServeOfferingSummary offering) {
    setState(() {
      _expandedId = offering.id;
      _selectedSessions = const {};
      _allowWaitlist = false;
      _submitError = null;
      _result = null;
      _voucherBlockedUntil = null;
      _voucherController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(
        palette,
        Icons.cloud_off_outlined,
        l10n.d('Het aanbod kon niet worden opgehaald.'),
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.d('Opnieuw proberen')),
        ),
      );
    }
    if (_offerings.isEmpty) {
      return _message(
        palette,
        Icons.app_registration_outlined,
        l10n.d('Er is nu geen aanbod om u voor in te schrijven.'),
      );
    }
    final expanded = _expanded;
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 28),
      children: [
        for (final offering in _offerings)
          expanded == null || expanded.id != offering.id
              ? _offeringCard(l10n, theme, palette, offering)
              : _enrollmentForm(l10n, theme, palette, offering),
      ],
    );
  }

  Widget _offeringCard(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeOfferingSummary offering,
  ) {
    final lessons = offering.classroomLessons.length;
    final sessions = offering.sessions.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _expand(offering),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _offeringArtwork(theme, offering, width: 88, height: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offering.name.isEmpty
                            ? l10n.d('Uitvoering')
                            : offering.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n
                            .d('{lessen} klassikale lessen · {sessies} sessies')
                            .replaceAll('{lessen}', '$lessons')
                            .replaceAll('{sessies}', '$sessions'),
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 12.5,
                        ),
                      ),
                      if (offering.voucherRequired)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            l10n.d('Vouchercode vereist'),
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: palette.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _offeringArtwork(
    ThemeData theme,
    OciServeOfferingSummary offering, {
    required double width,
    required double height,
  }) {
    Widget fallback() => ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.event_note_outlined,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
    final hash = offering.imageHash;
    if (hash == null || hash.isEmpty) {
      return SizedBox(width: width, height: height, child: fallback());
    }
    final provider = CappedImage(
      'ociserve-offering:$hash',
      () => ref
          .read(ociServeProvider.notifier)
          .courseImage(organizationId: widget.organizationId, imageHash: hash),
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          semanticLabel: offering.name,
          errorBuilder: (context, error, stack) {
            logWarning('OciServe: aanbodafbeelding tonen mislukt', error);
            return fallback();
          },
        ),
      ),
    );
  }

  Widget _enrollmentForm(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeOfferingSummary offering,
  ) {
    final material = MaterialLocalizations.of(context);
    final selected = _selectedSessions;
    final allChosen = offering.classroomLessons.every(
      (lesson) => selected.containsKey(lesson.id),
    );
    final chosenSessions = <OciServeTrainingSession>[
      for (final lesson in offering.classroomLessons)
        if (selected[lesson.id] case final sessionId?)
          offering.sessions.firstWhere((s) => s.id == sessionId),
    ];
    final anyFull = chosenSessions.any((s) => s.isFull);
    final voucherText = _voucherController.text.trim();
    final voucherNeeded = offering.voucherRequired;
    final voucherLooksValid = hasValidVoucherChecksum(voucherText);
    final eligible = offering.eligibility.eligible;
    final blocked = _voucherBlockedUntil;
    final stillBlocked = blocked != null && blocked.isAfter(DateTime.now());
    final canSubmit =
        allChosen &&
        eligible &&
        !_submitting &&
        _result == null &&
        (!anyFull || _allowWaitlist) &&
        (!voucherNeeded || voucherLooksValid) &&
        !stillBlocked;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.of(theme).accentInk, width: 1.5),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    offering.name.isEmpty
                        ? l10n.d('Uitvoering')
                        : offering.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.d('Sluiten'),
                  onPressed: () => setState(() => _expandedId = null),
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
            if (_result == null) ...[
              _eligibilityBlock(l10n, theme, palette, offering),
              for (final lesson in offering.classroomLessons)
                _lessonPicker(l10n, theme, palette, material, offering, lesson),
              if (anyFull)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _allowWaitlist,
                  onChanged: (value) =>
                      setState(() => _allowWaitlist = value ?? false),
                  title: Text(
                    l10n.d(
                      'Plaats mij op de wachtlijst voor de volle sessie(s)',
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              if (voucherNeeded)
                _voucherField(l10n, theme, voucherText, voucherLooksValid),
              const SizedBox(height: 10),
              _summary(
                l10n,
                theme,
                palette,
                material,
                offering,
                chosenSessions,
              ),
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _submitError!,
                    style: TextStyle(color: AppTheme.dangerFg, fontSize: 12.5),
                  ),
                ),
              if (stillBlocked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n
                        .d(
                          'Te veel pogingen — probeer het over {seconden} seconden opnieuw.',
                        )
                        .replaceAll(
                          '{seconden}',
                          '${blocked.difference(DateTime.now()).inSeconds + 1}',
                        ),
                    style: TextStyle(color: AppTheme.dangerFg, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: canSubmit
                        ? () => _submit(offering, chosenSessions)
                        : null,
                    child: Text(
                      _submitting ? l10n.d('Bezig…') : l10n.d('Inschrijven'),
                    ),
                  ),
                  if (!eligible)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          l10n.d(
                            'Inschrijven kan pas als u aan alle toelatingseisen voldoet.',
                          ),
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ] else
              _resultBody(l10n, theme, palette, material, offering, _result!),
          ],
        ),
      ),
    );
  }

  Widget _lessonPicker(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    MaterialLocalizations material,
    OciServeOfferingSummary offering,
    OciServeClassroomLesson lesson,
  ) {
    final sessions = offering.sessionsForLesson(lesson.id);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lesson.title.isEmpty ? l10n.d('Les') : lesson.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          RadioGroup<String>(
            groupValue: _selectedSessions[lesson.id],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedSessions = {..._selectedSessions, lesson.id: value};
              });
            },
            child: Column(
              children: [
                for (final session in sessions)
                  _sessionOption(l10n, theme, palette, material, session),
              ],
            ),
          ),
          if (sessions.isEmpty)
            Text(
              l10n.d('Geen sessies gepland.'),
              style: TextStyle(color: palette.mutedText, fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _sessionOption(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    MaterialLocalizations material,
    OciServeTrainingSession session,
  ) {
    final clock = sessionClockView(
      session.startsAt,
      session.endsAt,
      session.timezone,
    );
    final chosen = _selectedSessions[session.lessonId] == session.id;
    final seatText = session.isFull
        ? l10n.d('Vol')
        : l10n
              .d('{vrij} plaatsen vrij')
              .replaceAll('{vrij}', '${session.freeSeats}');
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: session.id,
      title: Text(
        '${material.formatFullDate(clock.sessionStart)} · '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(clock.sessionStart))}'
        '–${material.formatTimeOfDay(TimeOfDay.fromDateTime(clock.sessionEnd))}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        [
          if (session.location?.isNotEmpty ?? false) session.location!,
          if (session.instructors.isNotEmpty)
            session.instructors
                .map((i) => i.displayName)
                .where((n) => n.isNotEmpty)
                .join(', '),
          seatText,
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: palette.mutedText),
      ),
    );
  }

  Widget _voucherField(
    AppLocalizations l10n,
    ThemeData theme,
    String text,
    bool looksValid,
  ) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _voucherController,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: l10n.d('Vouchercode'),
            hintText: l10n.d('OCVO-XXXX-XXXX-XXXX-XXXX-XX'),
            helperText: l10n.d(
              'De code wordt niet opgeslagen en alleen bij inschrijven verstuurd.',
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (text.isNotEmpty && !looksValid)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.d(
                'Deze code klopt niet — controleer de code op typefouten.',
              ),
              style: TextStyle(color: AppTheme.dangerFg, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _eligibilityBlock(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeOfferingSummary offering,
  ) {
    final outcomes = offering.eligibility.outcomes;
    if (outcomes.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Toelatingseisen'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final outcome in outcomes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (outcome.status) {
                      OciServeRequirementStatus.met ||
                      OciServeRequirementStatus.waived =>
                        Icons.check_circle_outline,
                      OciServeRequirementStatus.expiresBeforeStart =>
                        Icons.schedule,
                      _ => Icons.error_outline,
                    },
                    size: 16,
                    color: switch (outcome.status) {
                      OciServeRequirementStatus.met ||
                      OciServeRequirementStatus.waived => AppTheme.successFg,
                      OciServeRequirementStatus.expiresBeforeStart =>
                        AppTheme.warningFg,
                      _ => AppTheme.dangerFg,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${outcome.label.isEmpty ? outcome.reason : outcome.label}'
                      '${outcome.reason.isEmpty ? '' : ' — ${outcome.reason}'}'
                      ' · ${_outcomeStatus(l10n, outcome.status)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          if (!offering.eligibility.eligible)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.d(
                  'Voldoet u bijna? Vraag uw organisatie of een ontheffing mogelijk is.',
                ),
                style: TextStyle(color: palette.mutedText, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  String _outcomeStatus(
    AppLocalizations l10n,
    OciServeRequirementStatus status,
  ) => switch (status) {
    OciServeRequirementStatus.met => l10n.d('voldaan'),
    OciServeRequirementStatus.notMet => l10n.d('nog niet voldaan'),
    OciServeRequirementStatus.waived => l10n.d('ontheffing verleend'),
    OciServeRequirementStatus.expiresBeforeStart => l10n.d(
      'verloopt vóór de start',
    ),
    OciServeRequirementStatus.unknown => '',
  };

  Widget _summary(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    MaterialLocalizations material,
    OciServeOfferingSummary offering,
    List<OciServeTrainingSession> chosen,
  ) {
    if (chosen.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Uw inschrijving'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final session in chosen)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '· ${session.title.isEmpty ? l10n.d('Sessie') : session.title}: '
                '${material.formatFullDate(sessionClockView(session.startsAt, session.endsAt, session.timezone).sessionStart)}'
                '${session.isFull && _allowWaitlist ? ' — ${l10n.d('wachtlijst')}' : ''}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultBody(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    MaterialLocalizations material,
    OciServeOfferingSummary offering,
    OciServeRegistration result,
  ) {
    OciServeTrainingSession? sessionFor(String id) {
      for (final session in offering.sessions) {
        if (session.id == id) return session;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.successFg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.d('Uw inschrijving is verwerkt.'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final booking in result.bookings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '· ${sessionFor(booking.sessionId)?.title ?? l10n.d('Sessie')}: '
              '${booking.status == OciServeBookingStatus.waitlisted ? l10n.d('op de wachtlijst') : l10n.d('ingeschreven')}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 14),
        if (widget.onShowBookings != null)
          FilledButton.tonal(
            onPressed: widget.onShowBookings,
            child: Text(l10n.d('Bekijk mijn inschrijvingen')),
          ),
      ],
    );
  }

  Future<void> _submit(
    OciServeOfferingSummary offering,
    List<OciServeTrainingSession> chosen,
  ) async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = await ref
          .read(ociServeProvider.notifier)
          .registerForOffering(
            organizationId: widget.organizationId,
            offeringId: offering.id,
            sessionIds: [for (final s in chosen) s.id],
            allowWaitlist: _allowWaitlist,
            // De vouchercode gaat alleen mee in dit verzoek — hij wordt
            // nooit bewaard, nooit in SharedPreferences en nooit gelogd.
            voucherCode: offering.voucherRequired
                ? formatVoucherCode(_voucherController.text) ??
                      _voucherController.text.trim()
                : null,
            idempotencyKey: const Uuid().v4(),
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
        _voucherController.clear();
      });
    } catch (error, stack) {
      logError('OciServe: inschrijven', error.runtimeType, stack);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (error is OciServeException && error.problem?.retryAfter != null) {
          _voucherBlockedUntil = DateTime.now().add(error.problem!.retryAfter!);
        }
        _submitError = _registerError(context.l10n, error);
      });
    }
  }

  /// Vertaalt de server-weigering naar producttaal — nooit een HTTP-code
  /// of een rauwe serverzin aan de gebruiker tonen.
  String _registerError(AppLocalizations l10n, Object error) {
    if (error is OciServeException) {
      if (error.isPlanningConflict('not open for self-enrollment')) {
        return l10n.d('Inschrijven voor deze uitvoering is gesloten.');
      }
      if (error.isPlanningConflict('self-enrollment limit')) {
        return l10n.d(
          'U heeft het maximum aantal inschrijvingen voor deze uitvoering bereikt.',
        );
      }
      if (error.isPlanningConflict('already enrolled')) {
        return l10n.d('U bent al ingeschreven voor deze uitvoering.');
      }
      if (error.isPlanningConflict('session is full')) {
        return l10n.d(
          'De gekozen sessie is vol. Kies een andere sessie of plaats u op de wachtlijst.',
        );
      }
      if (error.isPlanningConflict('overlaps an existing booking')) {
        return l10n.d(
          'Deze sessie overlapt met een bestaande afspraak in uw agenda.',
        );
      }
      if (error.isPlanningConflict('voucher required')) {
        return l10n.d('Voor deze uitvoering is een vouchercode vereist.');
      }
      if (error.isPlanningConflict('voucher is not valid')) {
        return l10n.d('Deze vouchercode is niet geldig voor deze uitvoering.');
      }
      if (error.isPlanningConflict('requirements not met')) {
        return l10n.d('U voldoet nog niet aan de toelatingseisen.');
      }
      if (error.isPlanningConflict('exactly one session')) {
        return l10n.d('Kies per les precies één sessie.');
      }
      if (error.problem?.retryAfter case final wait?) {
        return l10n
            .d(
              'Te veel pogingen — probeer het over {seconden} seconden opnieuw.',
            )
            .replaceAll('{seconden}', '${wait.inSeconds + 1}');
      }
    }
    return l10n.d('Inschrijven is niet gelukt. Probeer het opnieuw.');
  }

  Widget _message(
    AppPalette palette,
    IconData icon,
    String message, {
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: palette.mutedText),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    ),
  );
}
