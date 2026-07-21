/// Het beleid voor providers waarvan de fout aan de gebruiker wordt getóónd.
///
/// Riverpod 3 probeert een provider die een `Exception` gooit uit zichzelf
/// opnieuw, met oplopende wachttijd en zonder einde (alleen een `Error` wordt
/// met rust gelaten — zie `ProviderContainer`'s standaard-`retry`). Een provider
/// die opnieuw begint staat in `AsyncLoading`, en `AsyncValue.when` toont dan de
/// laadindicator. Het gevolg: elk scherm dat met `when(error: …)` een nette
/// uitleg klaar heeft staan, bleef in plaats daarvan eeuwig laden — de
/// bladeraars over WebDAV, S3 en git toonden nooit "controleer gebruikersnaam en
/// wachtwoord" of "geen repository ingesteld".
///
/// Voor deze bronnen is herhalen ook zinloos: het gaat om configuratie,
/// aanmelding en geblokkeerde hosts, en die veranderen niet vanzelf. Opnieuw
/// proberen hoort hier een knop te zijn — zichtbaar, en door de gebruiker
/// gekozen.
///
/// `null` betekent: niet opnieuw proberen.
Duration? noAutoRetry(int retryCount, Object error) => null;
