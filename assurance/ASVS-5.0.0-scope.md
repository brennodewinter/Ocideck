# ASVS 5.0.0 — scopebepaling

> **Status:** vastgesteld 2026-07-22 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim. Zie [`README.md`](README.md) voor waarom dit niet in
> `docs/` staat.

Lat: **OWASP ASVS 5.0.0, Level 2** — 253 van de 345 eisen staan op L1 of L2.

Een ronde die klakkeloos alle 253 afloopt, levert vooral "niet van toepassing"
op en verbergt daarmee juist de eisen die er wél toe doen. ASVS is geschreven
voor webapplicaties en API's; OciDeck is een lokaal-eerst bureaubladtoepassing.
**De motivering waaróm iets buiten scope valt, is daarom het waardevolle deel
van dit document** — niet de telling.

## Eén correctie op de aanname vooraf

"Geen backend" klopt voor het bureaublad en niet voor het hele product.
`server/fetch-proxy/ocideck_fetch_proxy.py` is een echte HTTP-dienst — een
`ThreadingHTTPServer` met één `do_GET` — waar de webbouw op terugvalt wanneer
CORS een directe lezing blokkeert (`FileServiceNet.fetchUrlBytes`,
`BrowserGitTransport`). Hij is optioneel en wordt door de beheerder uitgerold,
maar hij zit in deze repository en hij is onderdeel van het webverhaal. Dat
trekt V4 en delen van V3, V13 en V16 terug in scope.

Wie de scope bepaalt zonder die map te openen, komt tot een te gunstig antwoord.

## Per hoofdstuk

| Hoofdstuk | L1+L2 | Oordeel | Motivering |
|---|---:|---|---|
| **V1** Encoding and Sanitization | 27 | **In scope** | De app leest Markdown, HTML en SVG van buiten, geeft HTML uit (`MarpHtmlService`), bouwt JS-strings voor een offscreen WebView (`MermaidRenderService`) en start een subproces (`GitCliIo`). Ongeveer de helft is echt van toepassing; LDAP, XPath, JNDI, memcache, SMTP en LaTeX hebben hier geen interpreter. |
| **V2** Validation and Business Logic | 11 | **Deels** | V2.1/V2.2 (invoervalidatie en de documentatie ervan) gelden: `MarkdownValidator`, `ThemeProfile.fromJson`, `ImageService.imageMimeFromBytes`. V2.3 (opeenvolgende stappen, transacties, resourcelocking) en V2.4 (anti-automatisering) veronderstellen meerdere gebruikers op een server. |
| **V3** Web Frontend Security | 19 | **Deels** | Er is een webbundel (`web/index.html`, bewaakt door `tool/check_web_hardening.dart`). **V3.3 Cookie Setup valt eruit:** de app zet nergens een cookie, dus Secure/SameSite/HttpOnly hebben geen onderwerp. V3.4 (koppen) geldt wel, maar wordt grotendeels door de beheerder geleverd, niet door het artefact. |
| **V4** API and Web Service | 10 | **Deels** | Uitsluitend vanwege de fetch-proxy. V4.1/V4.2 gelden daarvoor. V4.3 (GraphQL) en V4.4 (WebSocket) vallen eruit: geen van beide bestaat in `lib/` of `server/`. |
| **V5** File Handling | 9 | **In scope** | Dit is het kernaanvalsoppervlak: zip-uitpakken en zip-slip (`FileServiceImport`), begrensde uitvoer (`_CappedOutputStream`), magic bytes (`ImageService`). |
| **V6** Authentication | 35 | **Deels — grotendeels n.v.t.** | Geen accounts, geen inlog, geen MFA, geen wachtwoordherstel, geen identity provider. Wat wél geldt: V6.2 als analogie voor de pakketzin (`generatePassword`, `estimatePasswordStrength`) en V6.3.2 (geen standaardaccounts) voor de proxy. |
| **V7** Session Management | 18 | **Buiten scope** | Er bestaat geen sessiebegrip: geen sessie-id, geen cookie, geen door de app uitgegeven token, geen inlogstaat. `SharedPreferences` bewaart instellingen, geen identiteit. Zonder sessie is er geen fixatie, geen time-out, geen beëindiging en geen herauthenticatie — alle 18 eisen missen hun onderwerp. |
| **V8** Authorization | 7 | **Buiten scope** | Eén gebruiker, één vertrouwensdomein, geen server-zijdig handhavingspunt. `ClassificationEnforcementPolicy` lijkt erop, maar dezelfde persoon stelt de eis én voldoet eraan: dat is datagovernance, geen autorisatie. |
| **V9** Self-contained Tokens | 7 | **Buiten scope** | Geen JWT, geen SAML, geen zelfdragend token. Het documentzegel is een kale SHA-512 over gecanoniseerde inhoud (`DocumentIntegrity.computeHash`), geen ondertekend bearer-artefact. |
| **V10** OAuth and OIDC | 29 | **Buiten scope** | Nul OAuth-code. Een git-forge authenticeert met een door de gebruiker geplakt persoonlijk toegangstoken; er is geen authorization-code-stroom, geen redirect-URI en geen toestemmingsscherm. |
| **V11** Cryptography | 14 | **In scope** | Pakketversleuteling, het SHA-512-zegel, de SHA-256-certificaatpin, CSPRNG-nonces, RFC 3161. |
| **V12** Secure Communication | 9 | **In scope** | Vier onafhankelijke TLS-cliënten (WebDAV, S3, git-REST, native git) plus de AI-weg en de CVE-inname, alle via `NetGuard`. |
| **V13** Configuration | 13 | **Deels** | V13.3 (geheimenbeheer) en V13.4 (informatielekkage) gelden rechtstreeks. V13.2 geldt alleen voor de uitrol van de proxy. |
| **V14** Data Protection | 9 | **In scope** | De hele OciWacht-laag (`lib/services/privacy/`) is een gegevensclassificatie-implementatie, en de webbouw raakt browseropslag. |
| **V15** Secure Coding and Architecture | 13 | **In scope** | Toeleveringsketen (`tool/generate_sbom.dart`, `tool/check_bundled_js.dart`), begrenzingen, verdedigend programmeren. |
| **V16** Logging and Error Handling | 16 | **Deels** | Foutafhandeling (V16.5) geldt volledig. Voor logging is er één afvoer — `dart:developer` via `lib/utils/log.dart` — dus V16.4.2/16.4.3 (logbescherming, logs wegsturen) missen hun onderwerp; V16.1–16.3 gelden in verkleinde vorm. |
| **V17** WebRTC | 7 | **Buiten scope** | Geen peerverbinding, geen STUN of TURN. Video is een `<video>`-element plus host-beperkte iframes (`VideoSource`); er is geen `RTCPeerConnection`. |

**Netto: ongeveer 95 eisen met een echt onderwerp.** De overige ~158 vallen weg
om de redenen hierboven.

## Waar het product strenger is dan de lat vraagt

Dit hoort erbij, anders leest een scopebepaling als een tekortenlijst.

- `NetGuard._embeddedIPv4` pelt IPv4-in-IPv6 af in álle drie de vormen —
  mapped, compatible én NAT64 — een klasse fouten die de meeste implementaties
  laat liggen.
- `NetGuard.connectPinned` combineert resolve-then-pin met TLS die tegen de
  hóstnaam blijft valideren, zodat pinning geen certificaat op een IP vereist.
- `tool/check_conventions.dart` bevat met `audienceBoundary` een
  privacygrens die bij de bouw faalt — een compile-time grens, geen afspraak.
- De basislijn voor kale `catch (_)` staat op nul.
- Het git-subproces draait met `includeParentEnvironment: false`, een lege
  `HOME`, een lege `hooksPath` en weigert operanden die met een streepje
  beginnen.
- `BrowserGitTransport` weigert principieel elk verzoek met inloggegevens door
  het fetch-hulppunt te sturen.

Verscheidene daarvan zijn L3-vormige maatregelen in een L2-beoordeling.
