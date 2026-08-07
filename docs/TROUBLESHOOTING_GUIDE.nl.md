> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Probleemoplossingsgids

> **Status:** procedure, actueel · **Status laatst nagekeken:** 2026-07-22 · **Uitgegeven door:** Stichting LibreKAT

Dit document biedt oplossingen voor veelvoorkomende problemen die gebruikers kunnen tegenkomen bij het gebruik van OciDeck.

## Overzicht

Deze gids behandelt veelvoorkomende problemen, hun oorzaken en stapsgewijze oplossingen. Het gaat zowel over problemen die de gebruiker direct raken als over technische problemen die ontwikkelaars of gevorderde gebruikers kunnen ervaren.

## Veelvoorkomende gebruikersproblemen

### Presentatiebestanden openen niet

**Symptomen**: 
- Foutmeldingen bij het openen van deckbestanden
- Lege schermen of vastlopers van de toepassing bij het laden van een bestand  
- Waarschuwingen "Ongeldig bestandsformaat"

**Begin bij wat de melding zegt.** Sinds 2026-07-22 noemt een geweigerde opening
haar reden in plaats van altijd "Kon dit bestand niet openen" te zeggen, dus de melding
wijst meestal rechtstreeks naar de oplossing:

| Melding | Wat het betekent | Wat te doen |
| --- | --- | --- |
| *Dit bestand bestaat op deze plek niet meer* | Het pad is weg — verplaatst, hernoemd of verwijderd | Zoek het op, of haal het uit de recente lijst |
| *Dit bestand is te groot om te openen* | Boven de limiet voor deckgrootte | Splits het deck, of verplaats omvangrijke inhoud naar gekoppelde afbeeldingen |
| *Dit is geen leesbare tekst. OciDeck opent Markdown.* | Geen geldige UTF-8, dus een binair bestand | Waarschijnlijk heb je het verkeerde bestand gekozen |
| *Deze presentatie is beschadigd of half opgeslagen* | De markdown is er wel, maar afgekapt of onleesbaar | Probeer een crashherstel-momentopname of een back-up; de stappen hieronder gelden |
| *Dit is geen Marp/OciDeck-presentatie* | Leesbare Markdown zonder de Marp-front matter | Zie *Validatie van bestandsformaat* hieronder |
| *Kon dit bestand niet openen* | De oorzaak kon niet worden vastgesteld | Het algemene geval; werk de stappen hieronder af |

Die laatste regel is bewust: waar de app de reden niet weet, verzint hij er geen.
Een verkeerde verklaring kost meer tijd dan geen verklaring.

**Oplossingen**:
1. **Controleer de bestandsintegriteit**:
   - Ga na of het .md-bestand niet beschadigd is (probeer het in een teksteditor te openen)
   - Zorg voor de juiste bestandsextensie (.md voor standaarddecks)

2. **Validatie van bestandsformaat**:
   - Bevestig dat het bestand de specificatie van het OciDeck-Markdownformaat volgt  
   - Controleer dat de front matter correct is opgemaakt met YAML-syntaxis
   - Ga na dat slidescheidingen correct zijn opgemaakt (`---` op een eigen regel)

3. **Herstelopties**:
   - Gebruik crashherstel-momentopnamen (automatisch gegenereerd — alleen op de desktop; de
     browserbouw schrijft er geen, omdat die geen map heeft om ze naar weg te schrijven)
   - Herstel vanuit een Git-repository indien beschikbaar — een commit bevat de markdown,
     de gepoolde afbeeldingen **en media**, de grafiekdata en je notities; wat er nog
     buiten valt zijn de tekeningen op je slides en, bij een verzegeld deck,
     het zegel. *(Gecorrigeerd 2026-07-22: hier stond dat ook video, audio en de notities
     buiten vielen, wat niet meer klopte sinds #515 en #541.)*
   - Probeer back-upkopieën te openen

### Exportproblemen

**Symptomen**:
- Exports mislukken of leveren beschadigde bestanden op  
- Ontbrekende inhoud in geëxporteerde documenten
- Foutmeldingen tijdens het exportproces
- **De export blijft stilstaan en rendert helemaal niets**

**Oplossingen**:
0. **Houd het venster zichtbaar tijdens het exporteren** (als er helemaal niets rendert):
   PDF en PPTX worden gemaakt door de echte slidevoorbeeldweergave te laten
   tekenen en het resultaat vast te leggen, dus de export heeft nodig dat de app
   daadwerkelijk beelden tekent. Minimaliseer je het venster, zet je een ander
   venster erover, of schakel je naar een andere Space, dan stopt macOS met het
   leveren van beelden — de export heeft dan niets om vast te leggen. Hij geeft
   het nu na 20 seconden op met een expliciete melding in plaats van eindeloos
   te wachten, maar de oplossing is simpelweg het venster op de voorgrond te
   laten. HTML-export wordt hier niet door geraakt: die rasteriseert niet.
0b. **Lees welke stap mislukte.** Een mislukte export noemt nu de stap waarop
   hij struikelde — voorbereiden, de slides naar afbeeldingen renderen, of het
   bestand opbouwen en wegschrijven — gevolgd door de ruwe technische melding.
   Dat onderscheid is de hele diagnose: alleen PDF en PPTX renderen, dus een
   mislukking in de renderstap gaat over een *slide*, en de HTML-export van
   hetzelfde deck werkt meestal nog wel. Een mislukking in de schrijfstap gaat
   over schijfruimte of een map die niet beschrijfbaar is. Citeer de technische
   regel bij het melden; dat is het enige deel dat de oorzaak aanwijst.
1. **Controleer de classificatie-instellingen**:
   - Ga na dat TLP-niveaus de export niet blokkeren
   - Bevestig dat de privacybeschikking-instellingen de export toestaan  

2. **Geheugenbeheer**:
   - Sluit andere toepassingen om systeembronnen vrij te maken  
   - Splits grote presentaties zo nodig in kleinere decks

3. **Formaatspecifieke problemen**:
   - Voor PDF/PPTX: zorg dat geen complexe grafieken of media renderproblemen veroorzaken  
   - Voor HTML: controleer de netwerkbeveiligingsinstellingen die externe assets kunnen blokkeren

### Prestatieproblemen

**Symptomen**:
- Traag renderen van het voorbeeld
- De toepassing loopt vast tijdens het bewerken of presenteren
- Hoog geheugengebruik  

**Oplossingen**:
1. **Optimaliseer de presentatie-inhoud**:
   - Verminder het aantal slides in grote presentaties  
   - Vereenvoudig complexe grafieken (minder datareeksen)
   - Comprimeer afbeeldingsassets vóór de import

2. **Systeembronnen**:
   - Sluit andere toepassingen om RAM vrij te maken
   - Controleer op systeemupdates die de prestaties kunnen verbeteren
   - Overweeg hardware-upgrade als je consequent tegen limieten aanloopt

3. **Cachebeheer**:
   - Wis tijdelijke bestanden waar mogelijk  
   - Herstart OciDeck om geheugencaches te wissen

## Technische problemen

### Netwerk- en beveiligingsproblemen  

**Symptomen**:
- URL-import mislukt door CORS-beperkingen
- WebDAV-verbindingsproblemen
- De privacyscan meldt valse positieven  

**Oplossingen**:
1. **URL-importbeperkingen**:
   - Gebruik de fetch-proxyserver voor externe decks die geen CORS ondersteunen  
   - Controleer de netwerkverbinding en firewall-instellingen

2. **WebDAV-configuratie**:
   - Ga na dat de inloggegevens correct zijn in Instellingen
   - Controleer het servertype: bij *Nextcloud of ownCloud* wordt het DAV-pad
     afgeleid van de host, dus een pad in de server-URL wordt genegeerd; bij *Andere
     WebDAV-server* is dat pad de WebDAV-hoofdmap en is een ontbrekend pad een
     veelvoorkomende oorzaak van "map niet gevonden"
   - Zorg dat de vertrouwde interne server juist is ingesteld als je lokale adressen gebruikt
   - Test de verbinding voordat je opslaat om te controleren dat de configuratie werkt  

3. **Een verbindingsfout lezen**: de melding noemt de oorzaak, dus behandel de
   drie mislukkingen op hostniveau als afzonderlijk — ze vragen om tegengestelde oplossingen:
   - *"De servernaam bestaat niet"* — een DNS-probleem, bijna altijd een typefout
     in de URL. **Vertrouwde interne server** aanvinken helpt hier niet en
     verzwakt de controle voor niets.
   - *"Deze server heeft een privé- of LAN-adres"* — het adres wordt prima
     omgezet, maar wijst naar binnen je netwerk. Dit is het geval waar **Vertrouwde
     interne server** het juiste antwoord is.
   - *"Het certificaat van de server wordt niet vertrouwd"* — de server is
     bereikbaar en TLS mislukte: zelfondertekend, verlopen, of uitgegeven op een
     andere naam. Zelfondertekende certificaten worden niet ondersteund; gebruik
     er een van een erkende uitgever. Merk op dat een als vertrouwd gemarkeerde
     LAN-server gewoon `http` mag gebruiken, wat de certificaatvraag helemaal omzeilt.

   Een vierde, *"De server verwijst door naar een ander adres"*, betekent dat de
   server antwoordt maar elders naartoe wijst — typisch een `http`-URL die de
   server naar `https` opwaardeert. Doorverwijzingen worden nooit gevolgd (dat
   zou de hostcontrole omzeilen), dus voer het uiteindelijke adres zelf in.

4. **Problemen met de privacyscan**:
   - Bekijk de privacybeschikking-instellingen voor het deck / de afzonderlijke slides  
   - Controleer dat redactiemarkeringen correct zijn opgemaakt (`[[...]]`)
   - Een regel die iets blijft melden dat je aanvaardt, kan afzonderlijk worden
     uitgezet — *Deze regel nooit meer melden* op de bevinding zelf

### Bouw- en opstartproblemen

Er is geen installatieprogramma. OciDeck wordt vanuit de broncode gebouwd met de
vastgezette Flutter-toolchain, dus wat elders een installatieprobleem zou zijn, is
hier een bouwprobleem. *Gecorrigeerd 2026-07-21: deze sectie adviseerde vroeger
"verwijder OciDeck volledig voordat je opnieuw installeert" en om achtergebleven
configuratie in "toepassingsmappen" op te schonen — instructies voor een distributie
die niet bestaat.*

**Symptomen**:
- De app start niet of loopt vast bij het opstarten
- Ontbrekende afhankelijkheden of bibliotheekfouten
- Platformspecifieke bouwfouten

**Oplossingen**:
1. **Controleer de vereisten**:
   - Ga na dat je Flutter/Dart-versie overeenkomt met de vastgezette toolchain in
     `.tool-versions` — vooral `make format-check` is versiegevoelig
     (zie [BUILD.md](BUILD.md))
   - Bevestig dat de platform-toolchain correct is geconfigureerd
   - Zorg voor voldoende schijfruimte voor de bouwuitvoer

2. **Begin met een schone bouw**:
   - `flutter clean`, dan `make setup` (dat is `flutter pub get`)
   - In een verse worktree moet `flutter pub get` draaien vóór `make check`, anders
     struikelt de format-controle over `third_party/`
   - Instellingen staan in de gewone voorkeurenopslag van het platform en overleven een
     herbouw; ze verwijderen zet de app terug op de standaardwaarden, en verwijdert ook
     de lijst met opslagverbindingen

3. **Platformspecifieke problemen**:
   - macOS: ga na dat de Xcode-opdrachtregelprogramma's zijn geïnstalleerd
   - Windows: zorg dat de Visual Studio-ontwikkelworkload is ingeschakeld
   - Linux: bevestig de GTK/Clang/Ninja-afhankelijkheden

## Geavanceerde probleemoplossing

### Foutopsporingsprogramma's en logboeken

1. **Toepassingslogboeken**: 
   - OciDeck logt waarschuwingen en fouten naar de foutopsporingsconsole van het platform via
     `dart:developer`. Er is geen voorkeur voor uitgebreid loggen en geen logbestand
     op schijf — heb je de uitvoer nodig, draai dan een debugbouw vanuit een terminal.

2. **Foutanalyse**:
   - Leg foutmeldingen met stacktraces vast waar mogelijk
   - Noteer de exacte stappen die het probleem uitlokken
   - Documenteer omgevingsdetails (OS-versie, Flutter-versie)

### Problemen met de ontwikkelomgeving  

**Symptomen**:
- Bouwfouten tijdens de ontwikkeling  
- De testsuite faalt in de lokale omgeving
- Foutopsporingsproblemen

**Oplossingen**:
1. **Omgevingsverificatie**:
   - Draai `make check` om te controleren dat alle kwaliteitspoorten lokaal slagen
   - Zorg dat de toolchain-versies overeenkomen met de projecteisen (**Flutter 3.44.9**)
   - Ga na dat de afhankelijkheden correct zijn geïnstalleerd (`flutter pub get`) 

2. **Testomgeving**:
   - Gebruik een consistente ontwikkelomgeving binnen het team
   - Valideer dat testgevallen werken in zowel de desktop- als de webbouw  
   - Controleer op platformspecifieke testvereisten

## Problemen met systeemintegratie

### Problemen met de Git-repository  

1. **Mislukte toegang tot de repository**:
   - Ga na dat de repository-URL correct en bereikbaar is
   - Bevestig dat de authenticatiegegevens correct zijn geconfigureerd  
   - Controleer de netwerkverbinding met de gitserver

2. **Branch-/tagbeheer**: 
   - Zorg dat branchnamen overeenkomen met de verwachtingen in de configuratie
   - Gebruikt je deck-repository tags, controleer dan dat ze niet zijn verplaatst of verwijderd

### Bestandssysteemintegratie  

1. **Problemen met padoplossing**:
   - Bevestig dat projectmappen toegankelijk en correct geconfigureerd zijn  
   - Controleer op rechtenproblemen met assetmappen
   - Ga na dat er geen absolute paden worden gebruikt waar relatieve zouden moeten

## Bekende problemen en oplossingen

### Huidige beperkingen

1. **Beperkingen van de webbouw**:
   - Beperkte geheugencapaciteit vergeleken met de desktopversie  
   - Browserspecifieke renderverschillen
   - Geen native bestandssysteemtoegang voor webbouwen  

2. **Prestaties bij grote media**:
   - Zeer grote videobestanden kunnen browserinstabiliteit veroorzaken in webbouwen
   - Geheugenintensieve bewerkingen kunnen de responsiviteit beïnvloeden

### Tijdelijke oplossingen

1. **Voor exportproblemen**: 
   - Probeer een ander exportformaat als er een mislukt
   - Vereenvoudig de presentatie-inhoud vóór het exporteren
   - Gebruik kleinere segmenten voor zeer grote decks  

2. **Voor netwerkproblemen**:
   - Configureer de fetch-proxyserver wanneer CORS-beperkingen directe toegang verhinderen  
   - Test externe verbindingen apart om problemen te isoleren

## Diagnostische procedures

### Systeeminformatie verzamelen

1. **Basisinformatie verzamelen**:
   - Noteer de commit waarvandaan je bouwde, je OS-versie en de Flutter/Dart-versies.
     Er is geen OciDeck-versie om te noemen: er wordt niets uitgebracht, en
     de app toont er geen.
   - Leg exacte foutmeldingen met tijdstempels vast  
   - Documenteer de stappen die je zette voordat het probleem optrad

2. **Diagnostisch testen**:
   - Probeer reproductie op andere bestanden of systemen indien mogelijk
   - Test tegen een bekende goede basislijn (werkend deck)
   - Isoleer variabelen om specifieke probleemomstandigheden vast te stellen  

### Effectief problemen melden

Bij het indienen van foutrapporten of ondersteuningsverzoeken:

1. Voeg volledige foutmeldingen en stacktraces toe  
2. Geef stapsgewijze instructies om het probleem te reproduceren
3. Voeg relevante configuratiebestanden toe indien mogelijk
4. Vermeld systeemspecificaties en omgevingsdetails
5. Geef aan of het probleem zich bij alle bestanden voordoet of alleen bij specifieke

## Waar je een probleem meldt

De Forgejo-issuetracker is het enige kanaal. Er is geen forum, geen mailinglijst,
geen chat en geen aparte documentatiesite — de map `docs/` in deze repository is de
documentatie. Beveiligingsproblemen volgen een andere route; zie
[SECURITY.md](../SECURITY.md).

## Preventieve best practices

### Regelmatig onderhoud

1. **Systeemupdates**: 
   - Pas systeem- en toolchain-updates regelmatig toe. (OciDeck zelf heeft nog geen
     uitgebrachte versies en geen updatemechanisme — je draait wat je hebt gebouwd.)

2. **Back-upstrategieën**:
   - Maak regelmatig een back-up van belangrijke presentaties
   - Test back-upherstelprocedures periodiek
   - Bewaar meerdere versies voor herstelscenario's

3. **Prestatiemonitoring**:  
   - Volg de prestaties van de toepassing in de tijd
   - Pak problemen aan voordat ze kritiek worden
   - Optimaliseer de presentatie-inhoud proactief  

## Als deze gids het niet oplost

Er is één kanaal: een issue in de [Forgejo-tracker](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues). Vermeld wat je uit deze
gids probeerde, de exacte stappen die het probleem reproduceren, je
besturingssysteem, en de commit waarvandaan je bouwde — de app toont geen
versienummer, dus de commit is de enige manier om te zeggen welke OciDeck je
draait. Een beveiligingsprobleem is de uitzondering en gaat naar het adres in
[`../SECURITY.md`](../SECURITY.md) in plaats van naar een openbaar issue.

*(Gecorrigeerd 2026-07-22: deze sectie had als kop "When to Seek Professional Help"
en zette een escalatiepad in drie niveaus uiteen — eenvoudige problemen, complexe
problemen, bugs melden — alsof er ondersteuningsniveaus achter zaten. Die zijn er
niet. Geen ondersteuningscontract, geen betaald niveau, geen tweedelijn: de tracker
en het beveiligingsadres zijn alles wat er is. De sectie was van dezelfde
gegenereerde soort als de gidsen die op 2026-07-19 zijn verwijderd, en is daarom
vervangen door wat er werkelijk bestaat.)*
