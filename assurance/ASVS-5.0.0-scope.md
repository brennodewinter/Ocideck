# ASVS 5.0.0 — scopebepaling

> **Herzien:** 2026-11-25 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim. Zie [`README.md`](README.md) voor waarom dit niet in
> `docs/` staat.

Lat: **OWASP ASVS 5.0.0, Level 2** — 253 van de 345 eisen staan op L1 of L2.

Een ronde die klakkeloos alle 253 afloopt, levert vooral "niet van toepassing"
op en verbergt daarmee juist de eisen die er wél toe doen. ASVS is geschreven
voor webapplicaties en API's; OciDeck is een lokaal-eerst bureaubladtoepassing.
**De motivering waaróm iets buiten scope valt, is daarom het waardevolle deel
van dit document** — niet de telling.

## Product en grenzen

OciDeck is lokaal-eerst. De optionele fetch-proxy, OciServe, ASR, WebDAV, S3,
git, feeds, LibrePlan, XMPP en Jitsi voegen elk een eigen grens toe. De tabel
volgt de huidige client en de meegeleverde fetch-proxy. IdP, OciServe- en
ASR-backends, feedhosts, opslagservers en de Jitsi/XMPP-uitrol worden apart
beheerd. Hun eisen worden aan de juiste partij toegedeeld. Zie
[het dreigingsmodel](../docs/SECURITY_DESIGN.md#threat-model) en de
[OWASP ASVS 5.0.0-uitgave](https://github.com/OWASP/ASVS/releases/tag/v5.0.0).

## Per hoofdstuk

| Hoofdstuk | Afbakening na herziening | Reden en bronanker |
| --- | --- | --- |
| **V1** Encoding and Sanitization | Deels | Markdown en export blijven in scope. Nieuwe tekstinvoer omvat XML-stanza’s, RSS/Atom, iframe-aanbiedingen en serverberichten. Zie `XmppStanza`, `parsePodcastFeed` en `MarkdownTransferBridge`. LDAP, XPath en SQL hebben hier geen interpreter. |
| **V2** Validation and Business Logic | In scope voor invoer en toestandovergangen | Invoercontroles gelden ook voor ASR, feeds en OciServe. Relevante toestandovergangen omvatten deelnemersrollen, afspeelsessies, revisies en outbox. De eigenlijke authenticatie hoort bij V6. Server-side anti-automatisering en transactievergrendeling horen bij de dienstbeheerder. |
| **V3** Web Frontend Security | Deels | De webbundel, CSP en browseropslag blijven relevant. `MarkdownTransferBridge` en `markdown_transfer_web.dart` voegen parent/origin-, toestemming- en limietgrenzen toe. De uitrol moet `frame-ancestors` leveren. OciDeck stelt geen eigen browserauthenticatiecookie in. |
| **V4** API and Web Service | Deels | De fetch-proxy heeft een HTTP-endpoint. De ASR- en XMPP-clients verwerken HTTP/WebSocket-berichten en begrenzen invoer. Server-side instellingen voor ASR, XMPP en OciServe zitten bij die diensten. GraphQL heeft geen bekende route. |
| **V5** File Handling | In scope | Pakketten, bestanden en afbeeldingen blijven onbetrouwbare invoer. Daar komen OciServe-lespakketten, ASR-audio, opnamestaging en gedownloade feed-enclosures bij. Zie `FileServiceImport`, `recording_staging_io.dart` en `FeedStoreNotifier`. |
| **V6** Authentication | Deels | Native OciServe valideert OIDC en lidmaatschap. Het IdP beheert wachtwoorden, MFA, passkeys en herstel. XMPP onderhandelt SASL. Bij WebDAV-samenwerking fase 0.5 bepaalt de opslag-ACL wie kan deelnemen. De pakketwachtwoordeisen blijven relevant. |
| **V7** Session Management | Deels | OciServe bewaart access-tokens in geheugen en kan refresh-tokens in de sleutelbos bewaren. Uitloggen en volledige reset hebben verschillende gevolgen voor de outbox. XMPP en vergaderingen brengen afzonderlijke sessies en deelnemersidentiteiten mee. |
| **V8** Authorization | Deels | OciServe-API bepaalt toegang per organisatie en deelnemer. OciDeck controleert actief lidmaatschap en houdt accountbinding bij step-up vast. Rollen van `XmppTransport` en de WebDAV-eigenaarsrol vereisen afzonderlijke toetsing. De WebDAV-ACL bepaalt externe schrijfbevoegdheden. |
| **V9** Self-contained Tokens | Deels | OciServe valideert het OIDC-ID-token en bevestigt toegang via `/me`. Claimuitgifte en autorisatie van API-tokens blijven serververantwoordelijkheid. SAML heeft geen route. |
| **V10** OAuth and OIDC | In scope voor OciServe | `OciServePkceAuthenticator` gebruikt native Authorization Code + PKCE, loopbackcallback, discovery en issuerpoort. Step-up bindt de nieuwe sessie aan dezelfde gebruiker. De webbouw weigert deze route. |
| **V11** Cryptography | In scope | Pakketten, SHA-512-zegel, RFC 3161, pins en nonces houden hun onderwerp. `XmppKeyExchange` en verzegelde companion-events voegen sleuteluitwisseling en gegevensversleuteling toe. WebRTC gebruikt DTLS-SRTP. |
| **V12** Secure Communication | In scope | WebDAV, S3, git, LibrePlan, feeds, XMPP, Jitsi, OciServe, AI en ASR hebben elk een transportbeleid. Native pinning geldt op de daarvoor ingerichte routes. Web gebruikt browsergrenzen en WebRTC-media volgt het ICE-pad. Zie het dreigingsmodel en de afwijkingen. |
| **V13** Configuration | Deels | Clientgeheimen, opt-ins, ASR-bestemming, OciServe-issuer en web-embedding zijn relevante instellingen. De beheerder van een fetch-proxy, IdP of vergaderserver heeft een eigen uitrolverantwoordelijkheid. |
| **V14** Data Protection | In scope | OciWacht, deck- en browseropslag blijven relevant. Microfoonaudio, ASR-serververwerking, leerlinggegevens en voortgang, XMPP-metadata en tijdelijke pakketten voegen gevoelige gegevens toe. Retentie verschilt per route. |
| **V15** Secure Coding and Architecture | In scope | SBOM, parsers en begrensde invoer blijven onderwerp. WebRTC, decoders en externe diensten brengen nieuwe afhankelijkheden en vertrouwensgrenzen mee. De inventaris hieronder signaleert nieuwe servicemodules. |
| **V16** Logging and Error Handling | Deels | Clientlogs, geredigeerde foutmeldingen en diagnose komen ook voor in ASR en OciServe. Logretentie, logtoegang en centrale analyse van externe diensten horen bij de beheerder. |
| **V17** WebRTC | Deels, client en uitrol apart | `JitsiMeetingSession` en `WebrtcMediaCore` onderhandelen over mediaverbindingen. De client verwerkt DTLS-fingerprints en ICE-kandidaten. TURN-beleid, configuratie van DTLS-SRTP en signaleringscapaciteit van een bridge moeten per uitrol beoordeeld worden. |

De oude schatting van ongeveer 95 toepasselijke eisen is vervallen. Deze
herziening beoordeelt hoofdstukken en grenzen. Een actuele telling per eis
vraagt een afzonderlijke beoordeling.

## Herziening bij nieuwe modules

De inventaris hieronder volgt de directe mappen en zelfstandige Dart-bestanden
in `lib/services/`. Een wijziging vraagt om herziening van de geraakte
hoofdstukken en het restrisico. Draai daarna
`dart run tool/check_dated_claims.dart --write-assurance-inventory`.
De dagelijkse controle meldt ook dossiers waarvan de review ouder dan
180 dagen is.

<!-- assurance-inventory service-modules: 205 549fd50fb82573a4d61d1876b0b37d7a86e83290d2dcbf6e81fa261add763f09 -->

## Waar het product strenger is dan de lat vraagt

Dit hoort erbij, anders leest een scopebepaling als een tekortenlijst.

- `NetGuard._embeddedIPv4` pelt IPv4-in-IPv6 af in álle drie de vormen —
  mapped, compatible én NAT64 — een klasse fouten die de meeste implementaties
  laat liggen.
- `NetGuard.connectPinned` combineert resolve-then-pin met TLS die tegen de
  hóstnaam blijft valideren, zodat pinning geen certificaat op een IP vereist.
- `tool/check_conventions.dart` bevat met `audienceBoundary` een
  privacygrens die de uitgevoerde conventiecontrole laat falen.
- De basislijn voor kale `catch (_)` staat op nul.
- Het git-subproces draait met `includeParentEnvironment: false`, een lege
  `HOME`, een lege `hooksPath` en weigert operanden die met een streepje
  beginnen.
- `BrowserGitTransport` weigert principieel elk verzoek met inloggegevens door
  het fetch-hulppunt te sturen.

Verscheidene daarvan zijn L3-vormige maatregelen in een L2-beoordeling.
