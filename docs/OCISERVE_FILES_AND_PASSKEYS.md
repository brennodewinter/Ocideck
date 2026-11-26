# OciServe-bestanden, deellinks en passkeys

Bestand → OciServe opent de catalogus van een actieve organisatie. De bron staat
ook in het Openen-venster en op het beginscherm. De gebruiker kiest de organisatie,
bladert met breadcrumbs en opent een Markdown-bestand of `.ocideck`-pakket.
Volgende pagina laadt maximaal honderd volgende resultaten. Servers zonder deze
catalogus en accounts zonder rechten krijgen een melding met een herhaalactie.
Handmatige WebDAV-, Git-, S3-, lokale en gewone URL-bronnen behouden hun eigen pad.

Openen maakt een lokale kopie. De bestaande bytespoort valideert tekst, pakketten
en hun assets. Downloaden heeft een grens van 32 MiB en een totale native deadline
van dertig seconden. Annuleren sluit de netwerkverbinding; een organisatie- of
sessiewissel maakt eerder werk ongeldig. De tijdelijke herkomst draagt alleen
server, organisatie, bestands-ID, naam en ETag. Opslaan schrijft geen serverbestand
terug. Een lokaal bestand moet bewust buiten dit leespad naar de organisatie
worden gepubliceerd voordat het als organisatiebestand kan worden gedeeld.

## Delen en beheren

De Delen-knop naast een bestand of map, of Delen via OciServe bij een geopend
organisatiebestand, opent het beheer. Effectieve `content:create`- en
`content:edit`-rechten bepalen welke beheeringangen de catalogus toont; de server
blijft de autoriteit. Het overzicht bevat de shares die de maker of beheerder
volgens het servercontract mag beheren.

De server legt bij aanmaak de gepubliceerde versie vast. Lokale wijzigingen worden
niet geüpload. Een map wordt een vaste snapshot, inclusief lege submappen, met
maximaal 2.000 items. De virtuele root kan niet worden gedeeld. Beheer toont de vastgelegde doelnaam, itemtelling en byteomvang uit het
serverantwoord. Later toegevoegd materiaal valt buiten een bestaande
snapshot.

Zonder ingevuld eindtijdstip geldt zeven dagen; maximaal negentig dagen. Het
invoerveld accepteert ISO-datum/tijd in de getoonde lokale zone of met expliciete
UTC-offset. Het beheer toont het lokale tijdstip met zone én de UTC-instant.
Een optioneel wachtwoord bevat 8–256 UTF-8-bytes. Het wachtwoord blijft alleen in
het invoervenster en het lopende verzoek; het wordt geen voorkeur, exportveld of
logbericht. Leeg laten bij aanpassen behoudt het bestaande wachtwoord; verwijderen
is een aparte keuze.

Een link verschijnt eenmalig bij aanmaak of rotatie. Kopiëren vereist een aparte
actie en een mislukte klembordactie blijft zichtbaar. Er wordt niet automatisch
gekopieerd. Bij verlies van het create-antwoord wordt geen nieuwe share aangemaakt:
het venster blokkeert een tweede aanmaak, behoudt de idempotencysleutel en verwijst
naar vernieuwen en rotatie van de bestaande share. Rotatie en intrekken vragen
bevestiging. Aanpassen maakt bestaande grants ongeldig. Een versieconflict vraagt
om verversen. Gedownloade lokale kopieën blijven bestaan na intrekken.

## Ontvangen en platformgrenzen

Bestand → Importeren → Openen via URL herkent uitsluitend de canonieke HTTPS-route
`/api/v1/public/file-shares/open#<share_id>.<token>`. Deze resolver loopt vóór de
gewone URL-import, mediaprobes en proxyfallback. Afwijkende vormen worden geweigerd.
Een ontvanger gebruikt geen organisatieaccount. Het wachtwoord gaat uitsluitend in
een TLS POST-body. De afzonderlijke client bewaart de kortlevende sharegrant alleen
in geheugen en stuurt hem naar dezelfde origin. Er is geen OIDC-token, tenantcache,
recent-bestand-URL of herstelveld met een deelgeheim. Sluiten ruimt de grant op.

Een gedeelde map gebruikt dezelfde browserweergave met eigen breadcrumbs,
paginering en bestandsselectie. Het openen levert een lokale kopie zonder
schrijfcredential. Een ongeldig, ingetrokken of verlopen geheim krijgt de generieke
servermelding. Een wachtwoordvraag kan opnieuw worden geprobeerd; bij rate limiting
vraagt de app minstens een minuut te wachten.

| Platform/pad | Gedrag in deze implementatie |
| --- | --- |
| macOS, Windows, Linux met bestaande OciServe-aanmelding | Organisatiecatalogus, linkbeheer en geplakte publieke links via begrensde HTTPS-transporten. |
| Web met publieke link | Afzonderlijke Fetch-client; geen cookies, referrer, redirects of proxy. De publieke OciServe-routes staan credentialloze CORS toe; accountcookies geven daar cross-origin geen toegang. |
| Web met organisatieaccount | OciServe-BFF op dezelfde HTTPS-origin; externe aanmelding met PKCE, HttpOnly-sessiecookie en CSRF. OAuth-tokens blijven op de server. |
| Web `?deck=` met OciServe-link | Gevalideerde share-resolver; de query wordt vóór ontgrendeling uit de adresbalk verwijderd. |
| Zelfgehoste private server | Native: alleen de expliciet vertrouwde serverorigin mag private DNS-adressen gebruiken. Web: de browser beheert DNS en vereist de eigen HTTPS-origin voor accounts. |
| Automatische native app-links | Er is geen universele OS-associatie voor willekeurige zelfgehoste origins. De gegarandeerde route is de HTTPS-browserlanding en expliciet plakken in OciDeck. Er wordt geen custom scheme met deelgeheim geïntroduceerd. |

## Webaanmelding voor eigen installaties

De origin is configureerbaar: `https://ocideck.librekat.nl` is een voorbeeld,
geen vaste dienst of allowlist voor alle gebruikers. Stel in OciServe
`OCISERVE_BFF_ENABLED=true`, de bestaande BFF-encryptiesleutel en
`OCISERVE_BFF_OCIDECK_ORIGIN=https://ocideck.librekat.nl` in. Dezelfde host moet
`/api/` met behoud van Host naar OciServe proxyen. Een OciDeck-installatie onder een
subpad gebruikt nog steeds `/api/` aan de origin-root. Vul in OciDeck die eigen
HTTPS-origin in als serveradres. Een andere API-origin voor accounts wordt geweigerd.

Provision Keycloak met `OCIDECK_WEB_ORIGIN` op dezelfde origin. Dit maakt de aparte
publieke client `ocideck-web`, met PKCE S256 en uitsluitend de exacte callback
`https://ocideck.librekat.nl/api/v1/auth/web/callback`. Bij een andere provider moet
de beheerder die client en callback zelf registreren en
`OCISERVE_OIDC_OCIDECK_WEB_CLIENT_ID` overeenkomstig instellen. De bestaande
Keiko-client blijft gescheiden. Zonder geconfigureerde webondersteuning meldt
OciDeck dat de server moet worden ingericht.

De knop reserveert een aanmeldvenster binnen de gebruikersklik. Het oorspronkelijke
tabblad bewaart het werk en wacht op de eigen, met het verzoek gecorreleerde
sessiehandshake. Bij een geblokkeerd venster kan de gebruiker opnieuw klikken.
Sessiemetadata en CSRF blijven in geheugen; de cookie is Secure en HttpOnly.
Herstel na herladen leest de bestaande serversessie. Iedere accountaanvraag is
gebonden aan de geaccepteerde sessie-ID, zodat een ander tabblad niet ongemerkt het
account voor een lopende bewerking kan vervangen. Uitloggen trekt de serversessie
in. Niet-verstuurde webvoortgang blijft alleen in het tabblad; er komt geen
OAuth-token of versleutelde native outbox in browseropslag. Een step-up zonder
actieve gebruikersklik biedt een expliciete heraanmeldknop.

## Passkeys

Inloggen met passkey of andere methode gebruikt de bestaande externe browser,
Authorization Code, PKCE, state, nonce, issuerbinding en callback. De provider
bepaalt de aangeboden methoden. OciDeck implementeert zelf geen authenticator en
stuurt geen Keycloak-specifieke aanname naar een externe IdP. Wachtwoord/OTP,
annulering, browser-timeout, refresh en ingelogd blijven houden hun bestaande pad.

Passkeys beheren staat bij het accountprofiel en bij Instellingen → eLearning als
`provider_features.passwordless_enrollable` en `passkey_management_url` beschikbaar
zijn. Alleen een HTTPS-adres op de gevalideerde issuer-origin, zonder userinfo of
fragment, wordt geopend. Registratie en herstel blijven bij de provider. Step-up
vraagt de bestaande ACR/freshness en herhaalt een uitdaging maximaal eenmaal; een
passkey bewijst niet op zichzelf een extra factor of een hoger niveau.

De server-PR [OciServe #781](https://pawprint.vigilis.online/brenno/OciServe/pulls/781)
bevat de echte HTTPS-Keycloakproef met de gepinde image, virtuele authenticator en
native clientconfiguratie: de passkey-route gaf `swk` en ACR `0`, en voldeed niet
alleen aan `phr`. Dat serverbewijs vervangt geen proef op elke fysieke authenticator
of elk desktopplatform. Deze clientwijziging valideert de contracten en UI met
unit- en widgettests; fysieke passkey-interoperabiliteit blijft provider/platformwerk.

## Gedeelde Dart-code en verificatie

`packages/ociserve_file_contract` is een zelfstandige pure-Dart-package onder EUPL-1.2
voor OciDeck en Keiko. Hij bevat identifiers, catalogus- en sharemodellen, canonieke
linkparsing, cursorweergave, statusgegevens en datum-/wachtwoordvalidatie.
Transport, OAuth/BFF, foutvertaling, browserlaunch en Flutter-shell staan erbuiten.
Keiko kan dezelfde package met een gepinde repositoryrevisie overnemen; er wordt
geen tweede deelprotocol ontworpen.

De OpenAPI-fixture is gepind op OciServe
`fe6594a15c64b217adf7bff50683e40da06d7972`. De driftpoort controleert alle nieuwe
routes en antwoordvelden, inclusief providerfeatures. Contracttests oefenen de
originbinding, omvang, ETag, wachtwoordvalidatie, rate limiting, verlopen/intrekken,
annulering, idempotency, rotatie en redactie van canarywaarden. Widgettests oefenen
root → map → bestand, breadcrumbs, paginering, orgwissel met een laat antwoord,
uitloggen, bevestiging bij intrekken en expliciet kopiëren. De bestaande tekst- en
pakketpoort blijft verantwoordelijk voor corrupte of onveilige inhoud.
