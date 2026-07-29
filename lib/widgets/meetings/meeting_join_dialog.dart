// Het venster waarin de gebruiker aan een vergadering gaat meedoen (§6.2).
//
// De volgorde is de hele functie van dit bestand, en hij is met opzet zo dat
// niets verrast:
//
//   1. link plakken;
//   2. lokaal toetsen — welke dienst is dit, en kán het;
//   3. naam invullen;
//   4. **de bekendmaking lezen: wie krijgt er contact, en wat ziet die;**
//   5. en pas dán meedoen.
//
// Stap 4 staat niet onderaan als kleine letters maar vóór de knop, want dat is
// het moment waarop de gebruiker nog nee kan zeggen. Wat er staat komt uit
// `MeetingPreflight` van de adapter — niet uit een zin die hier verzonnen is —
// zodat de bekendmaking niet uiteen kan lopen met wat er werkelijk gebeurt.
//
// **De preflight gebeurt pas na een handeling van de gebruiker** (T8, §7.1.3
// stap 5): het typen van een link raakt geen dienst aan; alleen het indrukken
// van *Controleren* doet dat. Zolang er geen echte adapter is, gebeurt er ook
// dan niets buiten het apparaat.
//
// **Wat hier níet gebeurt: apparaten kiezen.** §6.2 stap 5–7 (toestemming
// vragen, apparaten opsommen, eigen beeld voorvertonen) hoort bij de
// clientlaag die er nog niet is. De dialoog zet de fase daarom door naar
// `preview` zonder een voorvertoning te tonen, en de standaardwaarden blijven
// staan waar §13.2 ze wil: gedempt, camera uit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_failure.dart';
import '../../meetings/meeting_link.dart';
import '../../meetings/meeting_models.dart';
import '../../meetings/meeting_provider.dart';
import '../../meetings/meeting_registry.dart';
import '../../state/meeting_session_provider.dart';
import '../../theme/app_theme.dart';
import 'meeting_failure_text.dart';

/// Meedoen aan een onlinevergadering: link, naam, bekendmaking, meedoen.
class MeetingJoinDialog extends ConsumerStatefulWidget {
  const MeetingJoinDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const MeetingJoinDialog(),
  );

  @override
  ConsumerState<MeetingJoinDialog> createState() => _MeetingJoinDialogState();
}

class _MeetingJoinDialogState extends ConsumerState<MeetingJoinDialog> {
  final _linkController = TextEditingController();
  final _nameController = TextEditingController();

  /// De uitkomst van het lokale toetsen, zodra er getoetst is.
  MeetingLinkResolution? _resolution;

  /// Wat de adapter over déze uitnodiging meldt. Pas gevuld ná *Controleren*.
  MeetingPreflight? _preflight;

  /// Er loopt een preflight of een join.
  bool _busy = false;

  @override
  void dispose() {
    _linkController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Meedoen aan een onlinevergadering')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _linkController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.d('Vergaderlink'),
                  hintText: l10n.d('Plak hier de link uit de uitnodiging'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                minLines: 1,
                onChanged: _onLinkChanged,
              ),
              const SizedBox(height: 8),
              _linkVerdict(l10n),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.d('Uw naam, zoals de anderen die zien'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              Text(
                // T2, eerlijk en vooraf: deze naam is niet geverifieerd.
                l10n.d(
                  'Deze naam kiest u zelf; niemand controleert hem. De anderen zien u als gast.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
              if (_preflight != null) ...[
                const SizedBox(height: 16),
                _EgressNotice(preflight: _preflight!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        if (_preflight == null)
          FilledButton(
            onPressed: _canCheck ? _check : null,
            child: Text(l10n.d('Controleren')),
          )
        else
          FilledButton(
            onPressed: _canJoin ? _join : null,
            child: Text(l10n.d('Meedoen')),
          ),
      ],
    );
  }

  /// Herken de link terwijl er getypt of geplakt wordt.
  ///
  /// Dit gebeurt met de **pure** resolver en nadrukkelijk niet met
  /// `MeetingSessionNotifier.resolveLink`. Twee redenen, en de tweede is de
  /// belangrijkste:
  ///
  ///   1. Herkennen is ontleden en vergelijken met een lijst in de app. Het
  ///      kost niets en raakt geen dienst aan, dus het hoeft niet achter een
  ///      knop te wachten — de gebruiker hoort meteen te zien wát hij plakte.
  ///   2. De notifier legt de uitkomst vást in de sessietoestand: een halve
  ///      link zou de fase op `failed` zetten, en dan verschijnt de wachtstrip
  ///      met een foutmelding terwijl de gebruiker nog aan het typen is. Zo'n
  ///      halve link is geen mislukte vergadering.
  ///
  /// Het aanraken van de dienst zit één stap verder, in [_check] — dat is de
  /// uitdrukkelijke handeling die T8 verlangt.
  void _onLinkChanged(String raw) {
    final trimmed = raw.trim();
    setState(() {
      // Een nieuwe link maakt elk eerder oordeel ongeldig: laat geen
      // goedkeuring van de vorige link blijven staan.
      _preflight = null;
      _resolution = trimmed.isEmpty
          ? null
          : meetingLinkResolver.resolve(trimmed);
    });
  }

  /// Of er iets aan de adapter te vragen valt. Alleen bij een link die lokaal
  /// al herkend is — een onbekende of afgewezen link hoeft geen dienst lastig
  /// te vallen om te horen wat we al weten.
  bool get _canCheck => !_busy && _resolution is MeetingLinkRecognised;

  /// Meedoen mag als de adapter het toestaat en er een naam staat.
  bool get _canJoin =>
      !_busy &&
      (_preflight?.canJoin ?? false) &&
      _nameController.text.trim().isNotEmpty;

  /// Het oordeel over de link: herkend, onbekend, of afgewezen met de reden.
  Widget _linkVerdict(AppLocalizations l10n) {
    final resolution = _resolution;
    if (resolution == null) return const SizedBox.shrink();
    return switch (resolution) {
      MeetingLinkRecognised(:final match) => _note(
        l10n
            .d('Herkend als een vergadering bij {plek}.')
            .replaceAll('{plek}', match.displayOrigin),
        icon: Icons.check_circle_outline,
        colour: AppTheme.slate600,
      ),
      MeetingLinkUnrecognised(:final origin) => _note(
        l10n
            .d('{uitleg} De link wijst naar {plek}.')
            .replaceAll(
              '{uitleg}',
              meetingFailureText(l10n, MeetingFailureKind.unknownProvider),
            )
            .replaceAll('{plek}', origin),
        icon: Icons.help_outline,
        colour: AppTheme.slate600,
      ),
      MeetingLinkRejected(:final failure) => _note(
        meetingFailureText(l10n, failure.kind),
        icon: Icons.error_outline,
        colour: Theme.of(context).colorScheme.error,
      ),
    };
  }

  Widget _note(String text, {required IconData icon, required Color colour}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: colour)),
          ),
        ],
      );

  /// Leg de link vast in de sessie en vraag de adapter wat er mogelijk is.
  ///
  /// Dít is de uitdrukkelijke handeling van §7.1.3 stap 5: pas hier mag er
  /// iets van de aanbieder aangeraakt worden. Het lokale herkennen is al
  /// gebeurd tijdens het typen ([_onLinkChanged]); de notifier doet het
  /// opnieuw omdat hij de uitkomst ook móet vastleggen — twee keer ontleden
  /// van dezelfde tekst is goedkoper dan een tweede weg naar dezelfde
  /// toestand.
  Future<void> _check() async {
    setState(() => _busy = true);
    final notifier = ref.read(meetingSessionProvider.notifier);
    final resolution = notifier.resolveLink(_linkController.text);
    final preflight = resolution is MeetingLinkRecognised
        ? await notifier.preflight()
        : null;
    if (!mounted) return;
    setState(() {
      _resolution = resolution;
      _preflight = preflight;
      _busy = false;
    });
  }

  /// Doe mee, en sluit het venster zodra de adapter het overneemt.
  ///
  /// Het venster gaat dicht vóórdat er verbinding is: wat er daarna gebeurt —
  /// verbinden, wachten op toelating, binnen zijn — hoort in de omlijsting en
  /// niet in een venster dat de presentatie afdekt (T15).
  Future<void> _join() async {
    setState(() => _busy = true);
    final notifier = ref.read(meetingSessionProvider.notifier);
    notifier.requestDevicePermission();
    notifier.devicesReady();
    await notifier.join(displayName: _nameController.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

/// De bekendmaking van §6.2 stap 4: wie krijgt contact, en wat ziet die.
///
/// Alle regels komen uit de preflight van de adapter. Er staat met opzet geen
/// samenvattende zin als "uw gegevens zijn veilig" bij: dat is een belofte die
/// dit venster niet kan nakomen, want wat er aan de andere kant gebeurt is
/// andermans dienst.
class _EgressNotice extends StatelessWidget {
  const _EgressNotice({required this.preflight});

  final MeetingPreflight preflight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = preflight.failure;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.iceBlue.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.iceBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Wat er gebeurt als u meedoet'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (failure != null)
            Text(
              meetingFailureText(l10n, failure.kind),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            )
          else ...[
            for (final line in _lines(l10n))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $line', style: const TextStyle(fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }

  /// De bekendmaking, regel voor regel — uit de feiten van de adapter.
  List<String> _lines(AppLocalizations l10n) => [
    for (final origin in preflight.egressOrigins)
      l10n
          .d('{plek} krijgt contact zodra u meedoet.')
          .replaceAll('{plek}', origin.toString()),
    switch (preflight.identity) {
      MeetingIdentityKind.anonymousDisplayName => l10n.d(
        'U doet mee met alleen de naam die u zelf opgeeft; u bent niet aangemeld als die persoon.',
      ),
      MeetingIdentityKind.ephemeralGuest => l10n.d(
        'De dienst maakt een tijdelijke gastidentiteit voor u, die na de vergadering verdwijnt.',
      ),
      MeetingIdentityKind.serviceAppGuest => l10n.d(
        'U doet mee als gast onder een dienstaccount van een organisatie.',
      ),
      MeetingIdentityKind.hostSponsored => l10n.d(
        'De organisator heeft een identiteit voor u klaargezet.',
      ),
      MeetingIdentityKind.account => l10n.d(
        'Meedoen gaat met uw eigen account bij deze aanbieder.',
      ),
    },
    l10n.d(
      'De aanbieder ziet uw netwerkgegevens en het beeld en geluid dat u verstuurt. Wat u deelt, deelt u met alle deelnemers.',
    ),
    switch (preflight.encryption) {
      // T9: geen valse E2EE-belofte, en "onbekend" is een volwaardig antwoord.
      MeetingEncryptionClaim.transportOnly => l10n.d(
        'Het verkeer is versleuteld naar de dienst toe; de dienst zelf kan meekijken.',
      ),
      MeetingEncryptionClaim.providerManaged => l10n.d(
        'De aanbieder beheert de versleuteling en dus ook de sleutels.',
      ),
      MeetingEncryptionClaim.endToEnd => l10n.d(
        'De aanbieder beschrijft dit als eind-tot-eind versleuteld.',
      ),
      MeetingEncryptionClaim.unknown => l10n.d(
        'Over de versleuteling is niets vastgesteld. OciDeck belooft daar dus niets over.',
      ),
    },
    if (preflight.lobbyExpected)
      l10n.d(
        'U komt eerst in een wachtruimte: een organisator moet u toelaten. Uw presentatie blijft ondertussen gewoon te bewerken.',
      ),
    if (preflight.requiresPassword)
      l10n.d('Deze vergadering vraagt om een wachtwoord.'),
    if (preflight.requiresRegistration)
      l10n.d('Deze vergadering vraagt om aanmelding vooraf.'),
  ];
}
