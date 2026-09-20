// De planning-sectie "Mijn inschrijvingen" (issues #2123 en #2127):
// binnenkort en geweest bijeenkomsten, de aangeboden-plek-flow en zelf
// afmelden met het annuleervenster van de uitvoering.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../utils/session_timezone.dart';

/// De eigen inschrijvingen voor één organisatie. Locatie, instructeur,
/// wachtlijstpositie en het annuleervenster staan niet in `me/bookings` maar
/// in de uitvoering — die wordt daarom per voorkomende uitvoering
/// bijgehaald (begrensd, mislukt → kaart zonder die velden).
class OciServeBookingsView extends ConsumerStatefulWidget {
  const OciServeBookingsView({super.key, required this.organizationId});

  final String organizationId;

  @override
  ConsumerState<OciServeBookingsView> createState() =>
      _OciServeBookingsViewState();
}

class _OciServeBookingsViewState extends ConsumerState<OciServeBookingsView> {
  /// Pagina's en uitvoeringen zijn begrensd: een pathologisch grote agenda
  /// mag de dialoog niet eindeloos laten laden.
  static const _maxBookingPages = 5;
  static const _maxEnrichedOfferings = 10;

  bool _loading = true;
  String? _error;
  List<OciServeBooking> _bookings = const [];
  Map<String, OciServeOfferingSummary> _offerings = const {};
  Map<String, OciServeTrainingSession> _sessions = const {};
  String? _actingOn;

  @override
  void initState() {
    super.initState();
    ensureSessionTimezones();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifier = ref.read(ociServeProvider.notifier);
      final bookings = <OciServeBooking>[];
      String? cursor;
      for (var page = 0; page < _maxBookingPages; page++) {
        final result = await notifier.myBookings(
          widget.organizationId,
          cursor: cursor,
          includePast: true,
        );
        bookings.addAll(result.bookings);
        cursor = result.nextCursor;
        if (cursor == null) break;
      }
      final offeringIds = <String>{
        for (final booking in bookings) booking.offeringId,
      }.take(_maxEnrichedOfferings);
      final offerings = <String, OciServeOfferingSummary>{};
      final sessions = <String, OciServeTrainingSession>{};
      for (final offeringId in offeringIds) {
        try {
          final offering = await notifier.courseOffering(
            organizationId: widget.organizationId,
            offeringId: offeringId,
          );
          offerings[offeringId] = offering;
          for (final session in offering.sessions) {
            sessions[session.id] = session;
          }
        } catch (error) {
          // Verrijking is niet essentieel: de kaart toont dan geen locatie,
          // instructeur of wachtlijstpositie.
          logWarning('OciServe: uitvoering bij boeking laden', error);
        }
      }
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _offerings = offerings;
        _sessions = sessions;
        _loading = false;
      });
    } catch (error, stack) {
      logError('OciServe: inschrijvingen laden', error.runtimeType, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'load_failed';
      });
    }
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
      return _empty(
        l10n,
        palette,
        Icons.cloud_off_outlined,
        l10n.d('Uw inschrijvingen konden niet worden opgehaald.'),
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.d('Opnieuw proberen')),
        ),
      );
    }
    if (_bookings.isEmpty) {
      return _empty(
        l10n,
        palette,
        Icons.event_available_outlined,
        l10n.d('U bent nog niet ingeschreven voor een bijeenkomst.'),
      );
    }
    final now = DateTime.now().toUtc();
    bool active(OciServeBooking b) =>
        b.startsAt.isAfter(now) &&
        (b.status == OciServeBookingStatus.booked ||
            b.status == OciServeBookingStatus.waitlisted);
    final offered = _bookings
        .where(
          (b) =>
              b.status == OciServeBookingStatus.offered &&
              b.startsAt.isAfter(now),
        )
        .toList();
    final upcoming = _bookings.where(active).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past =
        _bookings.where((b) => !active(b) && !offered.contains(b)).toList()
          ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 28),
      children: [
        for (final booking in offered)
          _bookingCard(l10n, theme, palette, booking),
        if (upcoming.isNotEmpty) ...[
          _sectionHeader(l10n.d('Binnenkort'), theme, palette),
          for (final booking in upcoming)
            _bookingCard(l10n, theme, palette, booking),
        ],
        if (past.isNotEmpty) ...[
          _sectionHeader(l10n.d('Geweest'), theme, palette),
          for (final booking in past)
            _bookingCard(l10n, theme, palette, booking),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, ThemeData theme, AppPalette palette) =>
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _bookingCard(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeBooking booking,
  ) {
    final material = MaterialLocalizations.of(context);
    final session = _sessions[booking.sessionId];
    final offering = _offerings[booking.offeringId];
    final clock = sessionClockView(
      booking.startsAt,
      booking.endsAt,
      booking.timezone,
    );
    final offered = booking.status == OciServeBookingStatus.offered;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: offered
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: offered ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.sessionTitle.isEmpty
                            ? booking.offeringName
                            : booking.sessionTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (booking.offeringName.isNotEmpty)
                        Text(
                          booking.offeringName,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                _statusChip(l10n, theme, booking, session),
              ],
            ),
            const SizedBox(height: 10),
            _detailRow(
              palette,
              Icons.calendar_month_outlined,
              '${material.formatFullDate(clock.sessionStart)} · '
              '${material.formatTimeOfDay(TimeOfDay.fromDateTime(clock.sessionStart))}'
              '–${material.formatTimeOfDay(TimeOfDay.fromDateTime(clock.sessionEnd))}',
            ),
            if (!clock.sameZone)
              _detailRow(
                palette,
                Icons.public,
                l10n
                    .d('In uw tijdzone: {datum} · {van}–{tot}')
                    .replaceAll(
                      '{datum}',
                      material.formatFullDate(clock.localStart),
                    )
                    .replaceAll(
                      '{van}',
                      material.formatTimeOfDay(
                        TimeOfDay.fromDateTime(clock.localStart),
                      ),
                    )
                    .replaceAll(
                      '{tot}',
                      material.formatTimeOfDay(
                        TimeOfDay.fromDateTime(clock.localEnd),
                      ),
                    ),
              ),
            if (session != null && (session.location?.isNotEmpty ?? false))
              _detailRow(palette, Icons.place_outlined, session.location!),
            if (session != null && session.instructors.isNotEmpty)
              _detailRow(
                palette,
                Icons.person_outline,
                session.instructors
                    .map((instructor) => instructor.displayName)
                    .where((name) => name.isNotEmpty)
                    .join(', '),
              ),
            if (offered) _offerBody(l10n, theme, palette, booking, clock),
            if (_cancellable(booking, offering, clock))
              _cancelBody(l10n, theme, palette, booking, offering, clock),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(AppPalette palette, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: palette.mutedText),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: palette.mutedText, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );

  Widget _statusChip(
    AppLocalizations l10n,
    ThemeData theme,
    OciServeBooking booking,
    OciServeTrainingSession? session,
  ) {
    final position = session?.waitlistPosition;
    final label = switch (booking.status) {
      OciServeBookingStatus.booked => l10n.d('Ingeschreven'),
      OciServeBookingStatus.waitlisted =>
        position != null && position > 0
            ? l10n
                  .d('Op de wachtlijst, plaats {plaats} van {totaal}')
                  .replaceAll('{plaats}', '$position')
                  .replaceAll(
                    '{totaal}',
                    '${position > (session!.waitlisted) ? position : session.waitlisted}',
                  )
            : l10n.d('Op de wachtlijst'),
      OciServeBookingStatus.offered => l10n.d('Er is een plaats vrij'),
      OciServeBookingStatus.cancelled => l10n.d('Geannuleerd'),
      OciServeBookingStatus.attended => l10n.d('Aanwezig geweest'),
      OciServeBookingStatus.noShow => l10n.d('Niet aanwezig geweest'),
      OciServeBookingStatus.unknown => l10n.d('Onbekende status'),
    };
    final highlight = booking.status == OciServeBookingStatus.offered;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlight
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _offerBody(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeBooking booking,
    SessionClockView clock,
  ) {
    final material = MaterialLocalizations.of(context);
    // De exacte aanbiedingsdeadline zit niet in het deelnemerscontract; de
    // server laat een aanbod nooit later dan 24 uur voor aanvang staan.
    final bound = clock.sessionStart.subtract(const Duration(hours: 24));
    final busy = _actingOn == booking.id;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n
                .d(
                  'Er is een plaats vrij voor u. Bevestig zo snel mogelijk — het aanbod vervalt uiterlijk {deadline}.',
                )
                .replaceAll(
                  '{deadline}',
                  '${material.formatFullDate(bound)} '
                      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(bound))}',
                ),
            style: TextStyle(
              color: AppPalette.of(theme).accentInk,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: busy ? null : () => _confirm(booking),
                child: Text(busy ? l10n.d('Bezig…') : l10n.d('Bevestigen')),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: busy ? null : () => _decline(booking),
                child: Text(l10n.d('Afzien')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Alleen toekomstige, actieve boekingen zijn zelf af te melden.
  bool _cancellable(
    OciServeBooking booking,
    OciServeOfferingSummary? offering,
    SessionClockView clock,
  ) =>
      booking.startsAt.isAfter(DateTime.now().toUtc()) &&
      (booking.status == OciServeBookingStatus.booked ||
          booking.status == OciServeBookingStatus.waitlisted);

  Widget _cancelBody(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeBooking booking,
    OciServeOfferingSummary? offering,
    SessionClockView clock,
  ) {
    final material = MaterialLocalizations.of(context);
    final session = _sessions[booking.sessionId];
    final withinWindow =
        offering != null &&
        session != null &&
        DateTime.now().toUtc().isAfter(offering.cancellationDeadline(session));
    if (withinWindow) {
      final deadline = offering.cancellationDeadline(session);
      final wall = sessionClockView(deadline, deadline, booking.timezone);
      return _detailRow(
        palette,
        Icons.event_busy_outlined,
        l10n
            .d(
              'Zelf afmelden kon tot {deadline}. Daarna afmelden kan alleen nog via {organisatie}.',
            )
            .replaceAll(
              '{deadline}',
              '${material.formatFullDate(wall.sessionStart)} '
                  '${material.formatTimeOfDay(TimeOfDay.fromDateTime(wall.sessionStart))}',
            )
            .replaceAll('{organisatie}', _organizationName(l10n)),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _actingOn == null ? () => _cancel(booking, clock) : null,
        icon: const Icon(Icons.event_busy_outlined, size: 17),
        label: Text(l10n.d('Afmelden')),
      ),
    );
  }

  String _organizationName(AppLocalizations l10n) {
    final memberships =
        ref.read(ociServeProvider).account?.activeMemberships ?? const [];
    for (final membership in memberships) {
      if (membership.organizationId == widget.organizationId &&
          membership.name.isNotEmpty) {
        return membership.name;
      }
    }
    return l10n.d('uw organisatie');
  }

  Future<void> _confirm(OciServeBooking booking) => _act(
    booking,
    (notifier) => notifier.confirmBookingOffer(
      organizationId: widget.organizationId,
      bookingId: booking.id,
      idempotencyKey: const Uuid().v4(),
    ),
  );

  Future<void> _decline(OciServeBooking booking) => _act(
    booking,
    (notifier) => notifier.declineBooking(
      organizationId: widget.organizationId,
      bookingId: booking.id,
      idempotencyKey: const Uuid().v4(),
    ),
  );

  Future<void> _cancel(OciServeBooking booking, SessionClockView clock) async {
    final l10n = context.l10n;
    final material = MaterialLocalizations.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Afmelden voor bijeenkomst')),
        content: Text(
          l10n
              .d(
                'Wilt u zich afmelden voor {titel} op {datum}? Een eventuele plaats op de wachtlijst gaat dan naar de volgende.',
              )
              .replaceAll(
                '{titel}',
                booking.sessionTitle.isEmpty
                    ? booking.offeringName
                    : booking.sessionTitle,
              )
              .replaceAll(
                '{datum}',
                material.formatFullDate(clock.sessionStart),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Afmelden')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _act(
      booking,
      (notifier) => notifier.cancelBooking(
        organizationId: widget.organizationId,
        bookingId: booking.id,
        idempotencyKey: const Uuid().v4(),
      ),
    );
  }

  Future<void> _act(
    OciServeBooking booking,
    Future<OciServeSessionBooking> Function(OciServeNotifier) call,
  ) async {
    setState(() => _actingOn = booking.id);
    try {
      await call(ref.read(ociServeProvider.notifier));
      if (!mounted) return;
      await _load();
    } catch (error, stack) {
      logError('OciServe: boeking bijwerken', error.runtimeType, stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mutationError(context.l10n, error))),
      );
    } finally {
      if (mounted) setState(() => _actingOn = null);
    }
  }

  String _mutationError(AppLocalizations l10n, Object error) {
    if (error is OciServeException) {
      if (error.isPlanningConflict('cancellation notice')) {
        return l10n.d(
          'Afmelden kan niet meer: de termijn is verstreken. Neem contact op met uw organisatie.',
        );
      }
      if (error.isPlanningConflict('no pending offer')) {
        return l10n.d('Dit aanbod is niet meer geldig. De lijst is ververst.');
      }
    }
    return l10n.d('De wijziging is niet gelukt. Probeer het opnieuw.');
  }

  Widget _empty(
    AppLocalizations l10n,
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
