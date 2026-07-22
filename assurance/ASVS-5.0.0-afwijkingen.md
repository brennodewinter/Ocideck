# ASVS 5.0.0 — bewuste afwijkingen

> **Status:** vastgesteld 2026-07-22 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim. Zie [`README.md`](README.md).

Eisen die binnen scope vallen en tóch niet worden gehaald. Elk met de reden, en
met wat er in plaats daarvan staat. Een afwijking zonder tegenmaatregel is een
gat; een afwijking mét is een keuze.

---

## V11.4.4 — sleutelverlenging bij pakketversleuteling

**De eis.** Een wachtwoord dat een sleutel wordt, hoort door een KDF met
voldoende werkfactor te gaan.

**Wat er staat.** De AES-zip-laag leidt af met **PBKDF2-HMAC-SHA1, 1000
iteraties**. Dat getal ligt vast in de WinZip-AES-specificatie, staat in de
`archive`-afhankelijkheid (`ZipFile.deriveKey`) en is van OciDeck uit niet te
verhogen. Het is ruwweg drie ordes van grootte onder wat vandaag voor
PBKDF2-HMAC-SHA256 wordt aangeraden.

**Waarom dit zo blijft.** Het écht repareren betekent WinZip AES verlaten voor
een eigen container met een moderne KDF. Dan kan geen enkel ander
zip-bewust gereedschap het pakket nog openen — en "u kunt er met gewone
middelen bij" is hier geen gemak maar een kernbelofte. Een eigen containerformaat
zet de gebruiker vast bij ons; precies wat dit product niet doet. Die belofte
weegt zwaarder dan een iteratietelling die alleen bijt bij een zwak wachtwoord.

**Wat er in plaats daarvan is gedaan.** De entropie van het wachtwoord is het
enige wat wél in eigen hand ligt, en een zwakke KDF leunt daar volledig op.
Sinds 2026-07-22 vult het exportvenster bij het aanzetten van versleuteling
meteen een gegenereerd wachtwoord in, zichtbaar zodat het over te nemen is
(`PackageEncryptDialog`). Een leeg veld nodigde uit tot iets onthoudbaars, en
dat is het zwakste dat erin kan. Daarnaast blijft de entropiemeter, en
`docs/FILE_FORMAT.md` §7.1 benoemt de zwakke afleiding met zoveel woorden en
noemt age, GPG en `7z -mhe=on` als sterkere alternatieven.

**Restrisico.** Een gebruiker die het gegenereerde wachtwoord overtypt met iets
zwaks, houdt een pakket dat met genoeg rekenkracht te openen is. Dat is
zichtbaar gemaakt, niet weggenomen.

---

## V5.4.3 — virusscan op geüploade bestanden

**Waarom niet.** Een scanner bundelen of aanroepen in een lokaal-eerste editor
zonder uitgaand verkeer koopt niets wat het besturingssysteem niet al biedt, en
voegt precies het soort afhankelijkheid en updatekanaal toe dat dit project
weigert.

**Wat er in plaats daarvan is.** `MarkdownSafetyScanner` (fail-closed op
uitvoerbare inhoud, vóór het parsen, op dezelfde bytes die geparst worden),
magic-byte-controle op afbeeldingen én sinds 2026-07-22 ook op video en audio
(`ImageService.mediaMimeFromBytes`), harde groottelimieten, en padinsluiting
tegen zip-slip (`safeOutPath`, `resolveContainedRealPath`).

---

## V16.2.4, V16.4.2, V16.4.3 — logformaat, logbescherming, logs wegsturen

**Waarom niet.** Er is geen logverwerker, geen SIEM en geen tweede machine. De
enige afvoer is `dart:developer` via `lib/utils/log.dart`, stil in een
release-bouw. Een gestructureerd formaat opleggen aan een stroom die niemand
verzamelt, is ceremonie.

**Wat er wél is.** `_safeError` herschrijft een `FormatException` naar
melding-plus-positie, juist omdat een `jsonDecode`-fout anders de geparste bron
— deckinhoud, mogelijk bijzondere persoonsgegevens — in de log echoot. En sinds
2026-07-22 laten ook de weigeringen van `TabsProvider`, `GitCliIo` en
`ExportService` een spoor na, zonder deckinhoud mee te nemen.

---

## V6.2.4 en V6.2.12 — lijsten met gelekte en veelgebruikte wachtwoorden

**Waarom niet.** Een controle tegen gelekte wachtwoorden vereist uitgaand
verkeer met (een afgeleide van) een wachtwoordzin. Dat is precies wat dit
product niet doet, en een lokale kopie van zo'n lijst is een terugkerende
gegevensbron van honderden megabytes in een toepassing die offline hoort te
werken.

**Wat er in plaats daarvan is.** `estimatePasswordStrength` schat op entropie en
wáárschuwt in plaats van samenstellingsregels op te leggen — wat ASVS elders
juist vraagt. En het wachtwoord dat standaard klaarstaat, is gegenereerd.

---

## V15.3.4 — het oorspronkelijke client-IP door proxy's heen

**Waarom niet.** De fetch-proxy leest en logt bewust geen client-IP;
`log_message` is overschreven met de reden erbij ("geen URL's in de log
(privacy)"). Dat is een privacymaatregel, geen omissie.

**Het gevolg, expliciet.** De proxy kan daardoor geen enkele beslissing per
client nemen — er is geen snelheidsbegrenzing per afzender mogelijk. Dat wordt
hier vastgelegd in plaats van teruggedraaid. De begrenzingen die er wél zijn
(`MAX_INFLIGHT`, `MAX_BYTES`, time-outs) gelden over alle clients heen.

---

## V1.3.6 — de domeinhelft van de SSRF-allowlist

**Waarom niet volledig.** De eis vraagt om een allowlist van protocollen,
domeinen, paden én poorten. Een dekfetcher wiens hele doel het ophalen van een
door de gebruiker genoemde URL is, kan geen bestemmings-domeinallowlist hebben;
dat zou de functie opheffen in plaats van beveiligen.

**Wat er wél is gedaan.** De protocolhelft was er al (`http`/`https`), en de
**poorthelft is op 2026-07-22 gesloten**: `NetGuard.allowedWebPorts` hanteert nu
dezelfde verzameling als `ALLOWED_PORTS` in de fetch-proxy. Die twee zijn de
twee helften van dezelfde wacht — web haalt via de proxy op, bureaublad
rechtstreeks — en ze weken uiteen. Daarbovenop staan de bestaande lagen: een
blokkade op interne adressbereiken, resolve-then-pin tegen DNS-rebind, en geen
enkele omleiding volgen.

---

## V12 — plat HTTP naar een S3-endpoint dat als vertrouwd intern is gemarkeerd

**Waarom dit anders ligt dan bij WebDAV en git.** Voor WebDAV en git is deze
afwijking op 2026-07-22 juist *opgeheven*: daar gaat een herbruikbaar geheim
(een Basic-wachtwoord, een token) bij élk verzoek mee, en wie dat één keer van
de lijn plukt, houdt het. Die schade overleeft de verbinding.

SigV4 ondertekent elk verzoek apart. Die handtekening vervalt en is niet opnieuw
te gebruiken, dus er gaat geen herbruikbaar geheim over de lijn. Wat op platte
tekst wél meekijkbaar is, is de inhoud van de decks — en dat is de afweging die
de gebruiker met "vertrouwd intern" bewust zelf maakt, voor het gangbare geval
van een MinIO op het eigen netwerk zonder TLS.

**Restrisico.** Deckinhoud is op zo'n verbinding leesbaar voor wie op dat
netwerksegment meekijkt. De sleutel niet.
