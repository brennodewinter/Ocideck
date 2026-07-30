// Alles wat de vergadering in de omlijsting van de app zichtbaar maakt (T15).
//
// Vier kleine dingen bij elkaar, omdat ze één verhaal vormen: het startpunt,
// het statuslampje, de wachtstrip, en de waker die het gespreksvenster bij
// toelating zelf opent. Ze staan in één bestand zodat `app_shell.dart` er één
// import aan heeft in plaats van vier — die schil is al groot genoeg, en de
// bestandsgrootte-ratchet houdt hem daar terecht aan.
//
// Dit bestand is het antwoord op de vraag "waar is de wachtruimte gebleven".
// Nergens: er ís geen wachtscherm. Toelating is de zaak van de organisator en
// kan minuten duren, en OciDeck houdt de gebruiker die minuten niet gevangen in
// een venster dat alleen kan wachten. De presentatie blijft vooraan en volledig
// te bewerken; het wachten wordt gemeld in de omlijsting.
//
// Drie eisen die dat gedrag scherp maken, en die alle drie in de code staan:
//
//   * **Wachten mag nooit als geslaagd lezen.** De indicator verschilt van
//     "u doet mee" in kleur, in pictogram én in tekst — niet alleen doordat hij
//     knippert. Wie kleur niet ziet en beweging niet ziet, leest het nog.
//   * **Het knipperen respecteert beperkte beweging.** Staat
//     `MediaQuery.disableAnimations` aan, dan houdt de indicator zijn eigen
//     kleur en label zonder te animeren. De informatie zit dan nog steeds in
//     kleur en tekst, want die dragen hem ook zonder de animatie.
//   * **De fasewissel wordt aangekondigd, niet alleen getoond.** Elke wissel
//     gaat langs een live region (`Semantics.liveRegion`), zodat een
//     schermlezer hem meldt in plaats van dat de gebruiker moet raden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_models.dart';
import '../../meetings/meeting_state.dart';
import '../../state/meeting_session_provider.dart';
import '../../state/meetings_module_provider.dart';
import 'meeting_failure_text.dart';
import 'meeting_join_dialog.dart';
import 'meeting_workspace.dart';

/// Het startpunt voor een onlinevergadering, achter de modulepoort van T13.
///
/// Staat in de tabbalk en niet in de werkbalk van een presentatie: §6.1 eist
/// dat meedoen lukt met een leeg OciDeck, en een gesprek is geen eigenschap van
/// een deck (T6).
///
/// Verdwijnt zodra er een gesprek loopt — dan is het lampje ernaast de weg naar
/// binnen, en twee ingangen naast elkaar zouden suggereren dat je aan een
/// tweede vergadering kunt beginnen.
class MeetingEntryPoint extends ConsumerWidget {
  const MeetingEntryPoint({super.key, this.iconColour});

  /// De kleur van de omlijsting waarin hij staat; `null` laat het thema kiezen.
  final Color? iconColour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(meetingsModuleRevealProvider)) {
      return const SizedBox.shrink();
    }
    if (ref.watch(meetingSessionActiveProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Tooltip(
      // De activiteit, niet de leverancier (T14): welke dienst het wordt volgt
      // uit de link die de gebruiker plakt.
      message: l10n.d('Onlinevergadering…'),
      child: InkWell(
        onTap: () => MeetingJoinDialog.show(context),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.videocam_outlined,
            size: 16,
            color: iconColour ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Opent het gespreksvenster zodra de gebruiker is toegelaten (§6.3).
///
/// Tekent zelf niets. Dat staat er met een reden: wachten kan minuten duren, en
/// wie in die tijd gewoon doorwerkt — precies wat T15 wil — heeft geen venster
/// in beeld om iets in te drukken. Zou het venster niet zelf opengaan, dan zat
/// de gebruiker bínnen de vergadering zonder het te weten, met een microfoon
/// die volgens de dienst meedoet.
///
/// Alleen de overgang *naar* `connected` telt, en alleen vanuit de wachtruimte
/// of het verbinden: bij een gesprek dat gewoon doorloopt zou een venster dat
/// zich opnieuw opdringt hinderlijk zijn.
class MeetingAdmissionWatcher extends ConsumerWidget {
  const MeetingAdmissionWatcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<MeetingPhase>(meetingSessionProvider.select((s) => s.phase), (
      previous,
      next,
    ) {
      if (next != MeetingPhase.connected) return;
      if (previous != MeetingPhase.lobby &&
          previous != MeetingPhase.connecting) {
        return;
      }
      if (!context.mounted) return;
      MeetingWorkspaceDialog.show(context);
    });
    return const SizedBox.shrink();
  }
}

/// Het lampje in de tabbalk: pictogram, kleur en label per fase.
///
/// Verdwijnt volledig wanneer er geen gesprek is — er is dan niets te melden,
/// en een grijs lampje "voor het geval dat" is ruis.
class MeetingStatusIndicator extends ConsumerWidget {
  const MeetingStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(meetingSessionProvider);
    final label = meetingPhaseLabelOf(state.phase);
    if (label == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final text = meetingPhaseLabel(l10n, label);
    final look = _lookFor(context, label);
    return Semantics(
      // De aankondiging bij elke fasewissel; zonder dit is de overgang van
      // "wachten" naar "u doet mee" alleen zichtbaar.
      liveRegion: true,
      label: text,
      button: true,
      child: Tooltip(
        message: text,
        child: InkWell(
          onTap: () => MeetingWorkspaceDialog.show(context),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: _Blinker(
                active: look.blinks,
                child: Icon(look.icon, size: 16, color: look.colour),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoe een fase eruitziet: pictogram, kleur, en of hij knippert.
class _Look {
  const _Look(this.icon, this.colour, {this.blinks = false});

  final IconData icon;
  final Color colour;
  final bool blinks;
}

/// Elk label krijgt een eigen pictogram *en* een eigen kleur, zodat geen twee
/// toestanden op elkaar lijken voor wie er één van de twee niet ziet.
_Look _lookFor(BuildContext context, MeetingPhaseLabel label) {
  final scheme = Theme.of(context).colorScheme;
  return switch (label) {
    MeetingPhaseLabel.preparing => _Look(
      Icons.hourglass_empty,
      scheme.onSurfaceVariant,
    ),
    MeetingPhaseLabel.connecting => _Look(
      Icons.sync,
      scheme.onSurfaceVariant,
      blinks: true,
    ),
    // De wachtruimte: eigen pictogram (de zittende kat van T15), eigen kleur,
    // en knipperend. Nadrukkelijk niet het pictogram van "verbonden".
    MeetingPhaseLabel.waitingForAdmission => _Look(
      Icons.pets,
      scheme.tertiary,
      blinks: true,
    ),
    MeetingPhaseLabel.connected => _Look(Icons.videocam, scheme.primary),
    MeetingPhaseLabel.reconnecting => _Look(
      Icons.wifi_tethering_error,
      scheme.error,
      blinks: true,
    ),
    MeetingPhaseLabel.leaving => _Look(Icons.logout, scheme.onSurfaceVariant),
    MeetingPhaseLabel.ended => _Look(
      Icons.videocam_off_outlined,
      scheme.onSurfaceVariant,
    ),
    MeetingPhaseLabel.failed => _Look(Icons.error_outline, scheme.error),
  };
}

/// Laat zijn kind zachtjes pulseren — of niet, wanneer de gebruiker beperkte
/// beweging heeft gevraagd.
///
/// De animatie is versiering en geen informatie: zet hem uit en de toestand is
/// nog steeds te lezen aan kleur, pictogram en label. Dat is precies de eis van
/// T15, en de reden dat hier geen tweede signaal nodig is als vervanging.
class _Blinker extends StatefulWidget {
  const _Blinker({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Blinker> createState() => _BlinkerState();
}

class _BlinkerState extends State<_Blinker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldRun = widget.active && !reduceMotion;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
    if (!shouldRun) return widget.child;
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.35, end: 1)),
      child: widget.child,
    );
  }
}

/// De niet-modale strip die zegt waarop gewacht wordt, met *Verlaten* erbij.
///
/// Hij verschijnt alleen in de fasen waarin er werkelijk iets hangt, en hij
/// dekt de presentatie niet af — dat is het hele verschil met een wachtvenster.
/// `Verlaten` staat er in élke van die fasen op, want §17 eist dat weggaan
/// altijd bereikbaar blijft.
class MeetingWaitingStrip extends ConsumerWidget {
  const MeetingWaitingStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(meetingSessionProvider);
    if (!_shows(state)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final label = meetingPhaseLabelOf(state.phase);
    if (label == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isFailure = state.phase == MeetingPhase.failed;
    return Material(
      color: isFailure ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              isFailure ? Icons.error_outline : Icons.pets,
              size: 16,
              color: isFailure
                  ? scheme.onErrorContainer
                  : scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _message(l10n, state, label),
                style: TextStyle(
                  fontSize: 12,
                  color: isFailure
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
            ),
            if (isFailure || state.phase == MeetingPhase.ended)
              TextButton(
                onPressed: () =>
                    ref.read(meetingSessionProvider.notifier).reset(),
                child: Text(l10n.d('Sluiten')),
              )
            else ...[
              TextButton(
                onPressed: () => MeetingWorkspaceDialog.show(context),
                child: Text(l10n.d('Gespreksvenster')),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(meetingSessionProvider.notifier).leave(),
                child: Text(l10n.d('Verlaten')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// De strip hangt in de fasen waarin er iets loopt of net misging.
  ///
  /// Nadrukkelijk niet tijdens `connected`: dan is er niets om op te wachten,
  /// en een blijvende balk boven de presentatie zou dan alleen in de weg zitten.
  /// Het lampje in de tabbalk blijft dan de melding.
  bool _shows(MeetingState state) => switch (state.phase) {
    MeetingPhase.lobby ||
    MeetingPhase.reconnecting ||
    MeetingPhase.failed ||
    MeetingPhase.ended => true,
    _ => false,
  };

  String _message(
    AppLocalizations l10n,
    MeetingState state,
    MeetingPhaseLabel label,
  ) {
    if (state.phase == MeetingPhase.failed && state.failure != null) {
      return meetingFailureText(l10n, state.failure!.kind);
    }
    if (state.phase == MeetingPhase.lobby) {
      return l10n.d(
        'Een organisator moet u nog toelaten. U kunt gewoon doorwerken; zodra u binnen bent, opent het gespreksvenster zich.',
      );
    }
    return meetingPhaseLabel(l10n, label);
  }
}
