// Het register van vergaderadapters, en de resolver die eruit kiest.
//
// Eén plek die opsomt welke diensten OciDeck kent — het tegenovergestelde van
// een lijst probeer-endpoints. Een onbekende uitnodiging wordt niet langs de
// adapters gestuurd om te kijken wie hem herkent (`COLLABORATION.md` §7.1.3);
// er wordt lokaal op hostnaam gekozen, of er wordt niets gekozen.
//
// **Vandaag staat er alleen de nep-adapter in, en alleen in een debugbouw.**
// Dat is geen tijdelijke slordigheid maar de eerlijke stand: er is nog geen
// echte aanbieder. `kDebugMode` is bij het bouwen bekend, dus de nep-adapter en
// zijn draaiboek vallen in een uitgebrachte app uit de binary — een gebruiker
// kan geen vergadering "voeren" die niet bestaat, en de lijst is daar dan leeg.
//
// Een adapter erbij is één regel hier plus zijn eigen map onder `providers/`.
// Wat er níet bij hoort: een schakelaar per aanbieder op het instellingenscherm
// (T13) — de gebruiker kiest een vergadering, geen adapternummer.
import 'package:flutter/foundation.dart';

import 'meeting_link.dart';
import 'meeting_models.dart';
import 'meeting_provider.dart';
import 'providers/fake/fake_meeting_provider.dart';

/// De adapters die OciDeck kent, in de volgorde waarin ze bij gelijke
/// hostlengte voorrang krijgen.
List<MeetingProvider> get meetingProviders => const [
  if (kDebugMode) FakeMeetingProvider(),
];

/// De adapters die de gebruiker daadwerkelijk aangeboden mag krijgen.
///
/// §7.1.4 laat `research` en `spike` niet als deelnamemogelijkheid tonen: dat
/// zijn toestanden waarin er documentatie gelezen of geprobeerd is, geen
/// toestanden waarin iemand een echte vergadering in gestuurd mag worden. De
/// nep-adapter staat op `spike` en valt hier dus buiten — herkennen doet hij
/// wel, aanbieden niet.
List<MeetingProvider> get offerableMeetingProviders => [
  for (final provider in meetingProviders)
    if (provider.release == MeetingProviderRelease.experimental ||
        provider.release == MeetingProviderRelease.supported)
      provider,
];

/// De resolver over het volledige register.
///
/// Herkennen mag ruimer dan aanbieden: wie een link plakt die een `spike`-
/// adapter kent, hoort te lezen wát het is in plaats van "onbekend". Of er
/// vervolgens meegedaan kan worden, beslist [offerableMeetingProviders].
MeetingLinkResolver get meetingLinkResolver =>
    MeetingLinkResolver(meetingProviders);

/// De adapter met deze sleutel, of `null`.
MeetingProvider? meetingProviderById(MeetingProviderId id) {
  for (final provider in meetingProviders) {
    if (provider.id == id) return provider;
  }
  return null;
}
