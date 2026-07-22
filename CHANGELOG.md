# Changelog

All notable changes to OciDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/) once it
starts tagging releases. It has not yet: everything below is unreleased work on
`main`.

## [Unreleased]

### Changed
- **De HTML-export is nu écht één bestand.** Er stond dat hij self-contained was,
  maar de afbeeldingen zaten er niet in: die bleven verwijzen naar uw eigen
  `images/`-map. Wie de HTML doorstuurde, stuurde een rapport met kapotte
  plaatjes en zijn eigen mappenstructuur eronder — bij een pentestrapport
  uitgerekend het bewijsmateriaal.

  Nu reist elk beeld mee. Om te voorkomen dat een deck met twintig foto's
  tientallen megabytes wordt, gaat een afbeelding op schermformaat mee (maximaal
  1920 pixels, ruimer dan de dia zelf zodat inzoomen op een schermafdruk scherp
  blijft) en staat hij één keer in het bestand, hoe vaak u hem ook gebruikt. Een
  logo of doorzichtig beeld houdt zijn doorzichtigheid; een bewegende GIF blijft
  bewegen.

  **En de EXIF gaat eraf.** Een foto uit een telefoon draagt de GPS-locatie, het
  tijdstip en het serienummer van het toestel. Die reisden niet mee naar de
  ontvanger van uw rapport.

  Eén uitzondering, met opzet: **video** gaat niet mee. Een videobestand insluiten
  maakt een document van honderden megabytes, en een YouTube- of Vimeo-speler
  werkt niet in een export die per definitie niets van internet mag halen.
- **De zes rapportagedia's zien er in de HTML uit zoals in de app.** Scorecard,
  aanvalsoppervlak, ontdekkingen, checklist, scope-matrix en
  bevindingenoverzicht kwamen in de HTML-export als kale tabel binnen, terwijl u
  in de app kaarten, balken en tellers ziet. Juist de dia's van een
  pentestrapport verloren dus hun vorm in het bestand dat de klant het vaakst
  krijgt. Ze tekenen nu wat de app tekent, inclusief de getallen die worden
  afgeleid en nergens in de tabel staan — "2/4 gedekt", "3/4 getoetst", het
  verschil met het vorige rapport, de langst onopgemerkte blootstelling.
- **De diagramtekenaar is twee grote versies bijgewerkt** (mermaid 10.9.6 →
  11.16.0), en de HTML-sanitiser een patchversie (DOMPurify 3.4.11 → 3.4.12, die
  een lek dicht in de omgang met eigen HTML-elementen). Beide zitten zowel in de
  app als in de HTML-export. U merkt er niets van, behalve dat nieuwere
  diagramsoorten en schrijfwijzen nu werken.
- **Een uitgezette privacycontrole levert geen groen oordeel meer op.** Zette u
  de controle uit bij *Instellingen → Beveiliging*, dan meldde de statusbalk
  daarna gewoon een groen "Klaar voor export". Dat was de gevaarlijkste stand van
  allemaal: met de controle uit levert de scanner een lege uitslag, en van
  buitenaf is "wij hebben niets gevonden" dan niet te onderscheiden van "wij
  hebben niet gekeken". U deelde op een geruststelling die niemand had gegeven.

  Het oordeel is nu grijs en zegt wat er niet is nagekeken — persoonsgegevens,
  bijzondere gegevens en geheimen — met de plek erbij waar u de controle weer
  aanzet. Het exportvenster zegt hetzelfde in woorden. Er wordt niets
  geblokkeerd: u hebt die controle zelf uitgezet, dus dit is geen alarm maar het
  intrekken van een belofte. Grijs en niet oranje, om precies die reden.
- **De sjabloonkiezer zegt buiten het Nederlands dat de voorbeelddia's
  Nederlands zijn.** De naam en de omschrijving van een sjabloon volgen uw eigen
  taal; de dia's erin niet. Wie in het Turks een sjabloon koos, kreeg een
  Nederlands deck zonder dat iets dat had aangekondigd.

  Dat blijft zo, en dat is een keuze. Sjablooninhoud is *deck*-inhoud: ze belandt
  in uw opgeslagen bestand en is vanaf dat moment van u. Zou ze meevertalen, dan
  hing de inhoud van een document af van de menutaal waarin het toevallig is
  aangemaakt, en kregen twee mensen die hetzelfde sjabloon kiezen bestanden die
  ze niet kunnen vergelijken. Eerlijk zijn kost één regel tekst; het alternatief
  kost tienduizenden regels die niemand onderhoudt.
- **Twee stille valkuilen bij een nieuw slidetype weggenomen.** Welke slidetypes
  hun inhoud als tabel bewaren, stond op twee plekken met de hand bijgehouden:
  in de parser én in de serialisatie. Wie een nieuw tabeltype in de parser
  vergat, kreeg geen foutmelding — het deck opende, de dia stond er, en de rijen
  waren na herladen leeg. Datzelfde gold voor "kan deze bulletslide in tweeën?",
  dat op drie plekken apart was uitgeschreven; de kopie in de slidestrook viel
  bij een onbekend type stil terug op "nee", zodat de knip in het paneel wel
  verscheen en op de kaart niet.

  Beide feiten staan nu één keer opgeschreven, naast de opsomming van
  slidetypes zelf, en een toets vergelijkt ze met wat het opslaan-en-teruglezen
  werkelijk doet. Voor u verandert er niets aan wat u ziet; het scheelt bij het
  toevoegen van een slidetype twee bestanden waar het stil mis kon gaan.
- **Een afbeelding van internet wordt nu opgehaald over een vastgezette
  verbinding.** Staat er een `http(s)`-afbeelding op een dia, dan controleerde
  OciDeck eerst of die host niet naar binnen wees — maar liet het ophalen daarna
  aan Flutter over, en dat zoekt de naam nóg een keer op. Wie het domeinnaamsysteem
  in handen heeft, kon in dat korte venster van een publiek adres naar een intern
  adres omschakelen. OciDeck haalt de bytes nu zelf op, over een verbinding die
  vastzit op het gekeurde adres; er is dus geen tweede opzoeking meer.

  Bijkomstig: bewegende afbeeldingen (GIF, geanimeerde WebP) van internet bewegen
  nu ook, net als die uit een map. Ze toonden eerder alleen het eerste beeldje.

  Voor **video** blijft dat venster bestaan — de videospeler van het besturingssysteem
  opent zijn eigen verbinding en er is geen plek om die vast te zetten. Wat daar
  overblijft is een verzoek naar binnen waarvan het antwoord de app nooit bereikt.
- **Het kenmerk van een redactie is langer geworden.** In het bestand met
  redacties naast een geredigeerd rapport draagt elke redactie een kort kenmerk,
  zodat een lezer kan zeggen: "ik betwist redactie a3f1e2b7". Dat kenmerk was
  vier tekens lang, en dat is te kort: bij ongeveer driehonderd redacties in één
  rapport is de kans al één op twee dat er twee hetzelfde heten — en dan wijst
  een betwisting naar twee dingen tegelijk. Voortaan zijn het er minstens acht,
  en meer zodra dat nodig is om ze uit elkaar te houden. Bestaande bestanden
  blijven gewoon leesbaar; het bewijs zat altijd al in de volledige waarde
  ernaast, niet in het kenmerk.
- **De hostinggids stelt nu voorwaarden in plaats van aanbevelingen.** Wie de
  webversie publiek zet, vindt in `docs/HOSTING.md` een blok release-voorwaarden:
  de beveiligingsheaders als échte HTTP-header, en — als u het optionele
  fetch-hulppunt inzet — binden op `127.0.0.1`, een origin-lijst plus
  authenticatie zodra het verder reikt dan strikt same-origin, en verlaagde
  plafonds wanneer u het bewust als open fetcher draait.

  Aanleiding is dat de standaardcontrole van dat hulppunt (`Sec-Fetch-Site:
  same-origin`) wel elke andere *website* buiten de deur houdt, maar geen `curl`.
  Dat is met een header niet op te lossen en stond al eerlijk in de code; het
  stond alleen nergens waar een beheerder erlangs moet. De SSRF-grens zelf
  verandert niet — interne adressen bleven en blijven onbereikbaar.

  In de instellingentabel van `server/fetch-proxy/README.md` stond bovendien dat
  een lege `OCIDECK_PROXY_ALLOWED_ORIGINS` "geen check" betekende. Dat was het
  omgekeerde van wat de code doet: leeg betekent juist de striktste stand.
  Rechtgezet, samen met drie instellingen die er helemaal niet in stonden.
- **Het tijdstempelverzoek draagt nu een nonce.** Vraagt u een RFC 3161-stempel
  aan, dan zit er voortaan een willekeurig getal in het `.tsq`-bestand dat de
  tijdstempeldienst in het token moet herhalen. Daarmee is aan te tonen dát het
  token dat u terugkrijgt het antwoord op úw verzoek is, en niet een ouder token
  voor dezelfde hash dat iemand opnieuw indient. Zonder dat getal was er niets
  om die twee aan elkaar te knopen.

  OciDeck kan die controle bij het inlezen niet zelf doen — het bestand bewaart
  uw verzoek niet, dus na een herstart is de andere helft weg. Wie beide
  bestanden heeft, kan het wél nakijken (`openssl ts -reply -in … -text`).
- **Het zegel is voortaan zelf na te rekenen — met één commando, zonder
  OciDeck.** Tot nu toe stond het zegel in de kop van uw rapport en ging de hash
  over een tussenvorm die OciDeck zelf uitschrijft. Die vorm stond nergens
  beschreven, dus een ontvanger kón hem niet narekenen; en elke latere wijziging
  aan die uitschrijving zou "intact" stil in "gemanipuleerd" veranderen op een
  document dat als bewijsstuk bedoeld is.

  Het zegel en de handtekening staan nu naast het rapport, in
  `<naam>.seal.json`, net als uw tekeningen en aantekeningen. Daardoor kan de
  hash gaan over het rapportbestand zelf. Wie uw rapport ontvangt, doet:

  ```
  sha512sum rapport.md
  ```

  en vergelijkt de uitkomst met `hash` in `rapport.seal.json`. Verder niets: geen
  specificatie om na te spelen, geen bewerking vooraf, geen OciDeck. Datzelfde
  recept staat ook in het auditdossier, dus u hoeft er niets bij uit te leggen.
  De testvector staat in `docs/FILE_FORMAT.md` §6.6 en wordt door een test
  bewaakt.

  Twee dingen om te weten. **Verzegeld is bevroren**: élke wijziging aan het
  bestand breekt het zegel, ook een die u geen inhoud zou noemen — andere
  regeleindes bijvoorbeeld. Dat is de bedoeling, en daarom maakt OciDeck een
  afgerond rapport alleen-lezen en schrijft het er uit zichzelf nooit meer
  overheen. En: stuur `rapport.md` en `rapport.seal.json` samen, of exporteer een
  pakket — dan zitten ze allebei erin.

  Tussen afronden en opslaan staat er kort **Zegel nog niet vastgelegd** in de
  statusbalk: de hash gaat over een bestand, en dat bestaat op dat moment nog
  niet. Eén keer opslaan en de melding wordt **Integriteit intact**.

  **Bestaande verzegelde rapporten hoeft u nergens voor om te zetten.** Ze
  openen zoals ze zijn, hun zegel blijft kloppen, en bij de eerstvolgende keer
  opslaan verhuist het blok naar de nieuwe plek. De hash zelf blijft daarbij
  ongemoeid: een RFC 3161-tijdstempel dekt precies díé waarde, en die notarisatie
  is meer waard dan één uniform formaat.
- **Een gemanipuleerd rapport meldt zichzelf niet langer als in orde.** Het
  nalevingsoverzicht vinkte eis 1.1 ("verzegeld") af zodra er een hash in het
  bestand stond — zonder die hash na te rekenen. Een rapport waar na het
  verzegelen in was geknoeid, droeg zijn oude hash gewoon mee en kwam dus als
  voldaan uit het overzicht dat een auditor leest. De eis rekent de hash nu na,
  en het auditdossier schrijft de uitkomst van die controle erbij in plaats van
  alleen de waarde.
- **Zet u versleuteling aan bij een pakket, dan staat er meteen een sterk
  wachtwoord klaar.** Het veld was leeg, en dan verzint een mens iets dat hij
  kan onthouden. Juist bij dit bestandsformaat is dat de zwakke plek: de manier
  waarop het wachtwoord tot een sleutel wordt omgerekend ligt vast in de
  zip-standaard en is niet te versterken zonder dat andere programma's uw
  pakket niet meer kunnen openen. De sterkte van het wachtwoord is dus wat
  telt. Het staat zichtbaar in beeld zodat u het kunt overnemen, en u kunt er
  altijd uw eigen zin voor in de plaats zetten.
- **OciDeck laat minder op uw schijf achter, en u kunt de rest zelf wissen.**

  Een git-verbinding verwijderen haalde alleen het regeltje uit uw instellingen
  weg. De volledige inhoud van die repository — inclusief de historie — bleef in
  een verborgen map staan, samen met de commitboodschappen die u had getypt. Bij
  een repository met klantgegevens betekende dat: de verbinding is weg, de
  gegevens niet. Die werkkopie gaat nu mee. Wacht er nog werk dat niet naar de
  server is gestuurd, dan gooit OciDeck dat nooit stilzwijgend weg: u ziet welk
  deck, welke tak en welke boodschap het betreft, en u kiest zelf. Zegt u nee,
  dan blijft de verbinding gewoon staan.

  Ook nieuw in *Instellingen → Beveiliging*, onder **Sporen op dit apparaat**:
  de recente lijst in één keer wissen — die bewaart het volledige pad én de
  classificatie van elk deck dat open is geweest — en *alles terugzetten naar de
  begintoestand*, dat ook de herstelbestanden, de git-werkkopieën en de
  wachtwoorden in uw sleutelbos opruimt. Uw presentaties blijven staan: die zijn
  van u.

  Verder ruimt OciDeck nu op wat het zelf liet slingeren: het logo van een
  stijlprofiel dat u verwijdert, en de tijdelijke map waarin `git` draait.

  Uw eigen gegevens uit de privacycontrole — naam, e-mailadres, telefoonnummer —
  stonden in klaartekst bij de instellingen. Die verhuizen bij de eerste start
  naar de sleutelbos van uw besturingssysteem, waar de wachtwoorden ook staan.

  Herstelbestanden worden niet versleuteld, en dat blijft zo; `SECURITY.md` legt
  uit waarom opruimen hier meer oplevert. Wél gelden de zeven dagen nu ook
  terwijl de app draait — voorheen werd er alleen bij het opstarten opgeruimd,
  dus op een machine die aan blijft staan bleef een oud herstelbestand liggen.
  En op Linux zet OciDeck zijn eigen mappen bij de start op "alleen voor u",
  zodat andere accounts op dezelfde computer niet meelezen.

- **Geen base64 meer in uw presentatiebestand.** De belofte van OciDeck is dat u
  met alleen een teksteditor en Marp verder kunt. Op zeven plekken klopte dat
  niet: daar stond een blok onleesbare tekens waar uw inhoud in verstopt zat.

  Het pijnlijkst was de tweekolomsdia. De twee kolommen stonden als base64 in
  commentaar bovenaan, en de nette `<ul><li>` eronder was slechts een plaatje
  van diezelfde inhoud. Wie die zichtbare lijst aanpaste, zag zijn wijziging bij
  het openen verdwijnen — en wie zelf een tweekolomsdia typte, kreeg twee lege
  kolommen terug. Die dia leest nu gewoon wat er staat: `<h3>` is de kolomkop,
  `<li>` is een punt, inspringing is een niveau, `☑`/`☐` maakt er een
  aankruislijst van. Ook een punt met HTML of een liggend streepje erin
  overleeft dat — precies waarvoor die base64 ooit bedoeld was.

  De drie blokken in de kop van het bestand zijn er ook uit. Het stijlprofiel
  reisde alleen mee naar het tweede scherm en gaat nu naast de tekst mee in
  plaats van erin. De afspraken met de klant over de MIAUW-eisen (uitsluitingen
  en bevestigingen) staan voortaan in `<naam>.miauw.json`, naast uw tekeningen
  en aantekeningen — het gaat immers óver het rapport, niet erin. Die reist mee
  naar de prullenbak, in een pakket en in het herstelbestand.

  **Bestaande bestanden hoeft u nergens voor om te zetten.** Ze openen zoals ze
  zijn; bij de eerstvolgende keer opslaan staat alles in de nieuwe vorm.
- **De twee begeleidende bestanden bij een geredigeerde export hebben andere
  namen gekregen.** Ze heetten `<naam>-redacties.json` en
  `<naam>-redacties-verificatiesleutels.json`; dat zijn twee Nederlandse namen
  die op elkaar lijken, terwijl ze precies tegengesteld behandeld moeten worden
  en bij ontvangers in elke taal terechtkomen. Ze heten nu
  `<naam>-redactions.json` — die mag met het rapport mee — en
  `<naam>-redaction-keys.json`, die bij de bron blijft omdat de sleutels erin
  elke weggelakte waarde terugrekenbaar maken.

  Beide bestanden zeggen bovendien in hun eigen inhoud wat ze zijn, in een
  `notice`-veld bovenaan. Een bestandsnaam overleeft geen hernoeming en geen
  zip; de eerste regel van de JSON wel. En het exportvenster noemt allebei de
  bestanden vóórdat u exporteert, met de waarschuwing bij het sleutelbestand —
  tot nu toe zette OciDeck dat bestand naast uw rapport neer zonder er iets over
  te zeggen.
- **De documentatie belooft niet langer meer dan de app doet.** Elf beoordelaars
  liepen de teksten na en vonden op een reeks plekken een belofte die ruimer was
  dan de code. Die zijn teruggebracht tot wat er werkelijk gebeurt, met de datum
  van de correctie in de tekst zodat een lezer kan zien wat er is bijgesteld.

  Het zwaarste punt raakt uw privacy, en daarom staat het ook in de app zelf. De
  verklaring in *Instellingen → Privacy* zei dat gegevens dit apparaat alleen
  verlaten als u dat kiest, en somde daarna alleen bestemmingen op die u zelf
  aanwijst. Er zijn er vier die u niet aanwijst: in de browser gaat een adres dat
  de browser weigert op te halen automatisch naar het hulppunt op de server waar
  de app vandaan komt, het opzoeken van een CVE gaat naar een spiegel van de
  uitgever met ENISA en MITRE als vaste terugval, de lokale CVE-database haalt
  haar bulkgegevens via api.github.com, en een ingesloten YouTube- of
  Vimeo-video laadt de speler bij die dienst. Alle vier staan nu in de
  verklaring, in alle 32 talen, en in `docs/PRIVACY.md`.

  Verder, kort: de HTML-export sluit haar afbeeldingen niet in en heet daarom
  niet meer "self-contained"; het RFC 3161-tijdstempel wordt vergeleken op zijn
  afdruk en niet gecontroleerd op handtekening of certificaat, en dat gebeurt
  wanneer u de dialoog opent — niet bij het openen van het deck; de interface is
  in 32 talen beschikbaar maar een vijftigtal editorlabels staat nog in het
  Nederlands, wat de vertaalpoort niet ziet; het verwijderen van een
  git-verbinding laat de werkkopie op schijf staan; en er valt nog niets te
  downloaden, want er is geen release.
- **Een eerlijk overzicht van de toegankelijkheid**, te lezen via *Instellingen
  → Documentatie → Toegankelijkheid*. Het zet wat werkt en wat niet werkt naast
  elkaar, met de beperkingen vooraan. De belangrijkste: de PDF- en
  PPTX-export zetten elke dia als afbeelding neer. Er zit geen tekstlaag in,
  geen alt-tekst en geen structuur — ook niet de alt-tekst die u in de editor
  invulde. Moet de ontvanger kunnen lézen in plaats van kijken, lever dan de
  markdown of de HTML.
- **De drie git-koppelingen praten voortaan via dezelfde plumbing.** GitHub,
  GitLab en Forgejo/Gitea hadden elk hun eigen — nagenoeg woordelijk gelijke —
  afhandeling van verzoeken, foutstatussen en antwoorden. Dat is samengetrokken,
  zodat een verscherping niet meer op één plek landt en op de andere twee
  achterblijft. Voor u verandert er niets aan wat de koppelingen doen; alleen de
  melding bij een te grote maplijst noemt nu overal het aantal.

### Fixed
- **Een kwetsbaarheidsmelding kwam op het verkeerde adres uit.** Het
  contactkaartje in de issuetracker verwees naar `security@vigilis.nl`, terwijl
  `SECURITY.md` en de gedragscode allebei `security@librekat.nl` noemen. Wie de
  tracker volgde — precies de route die we zelf aanwijzen — mailde een adres dat
  in onze eigen documentatie niet bestaat. Rechtgezet, en er staat nu een test
  op die elk contactadres vergelijkt met `SECURITY.md`, zodat de drie plekken
  niet opnieuw uit elkaar kunnen lopen.
- **Een HTML-export met huisstijl verloor haar opmaak.** De tijdlijn, de
  akkoordpagina, het zwarte vlak van een privacyredactie en — het ergst — de
  balk met de TLP-classificatie bovenaan het document bestonden alleen in de
  variant zónder thema. De app geeft altijd een thema mee, dus in elke echte
  export vielen die vier weg: de tijdlijn werd een genummerde lijst zonder
  tijdbalk, en de markering die de ontvanger moet vertellen hoe hij met het stuk
  om moet gaan, werd een losse regel tekst.
- **Een kapot diagram vertelt nu wat eraan mankeert.** Kon de tekenaar een
  mermaid-diagram niet lezen, dan stond er in de HTML-export een Engels bommetje
  met "Syntax error in text" — zonder te zeggen wélk diagram of wat eraan fout
  was. De ontvanger van een export heeft geen ontwikkelaarsconsole om dat na te
  kijken, en de auteur zag helemaal niets. Nu staat er een leesbare melding op de
  dia zelf, met wat de tekenaar erover zegt en de brontekst van het diagram
  eronder.
- **Een vraag met meerdere juiste antwoorden toont voortaan álle antwoorden.**
  De opdracht luidt "vink alle juiste aan", maar de dia trok er eerst een
  willekeurige greep uit — zoveel als u bij *aantal getoonde opties* had staan.
  Dat is een onmogelijke opdracht: u kunt niet weten of er twee of vijf juiste
  tussen zitten, en een antwoord dat in de vorige ronde goed was ontbrak in de
  volgende. Alle ingevulde antwoorden staan nu op het scherm; alleen de
  volgorde is nog willekeurig, zodat een tweede ronde niet na te spelen is.

  Daarmee geldt de teller *aantal getoonde opties* alleen nog voor
  **meerkeuze** en **volgorde** — de twee soorten die werkelijk uit een pool
  trekken. Bij de andere soorten verdwijnt die teller uit de editor in plaats
  van er te blijven staan zonder iets te doen. De regel in de editor onder een
  vraag zegt nu per soort wat er bij het presenteren gebeurt.
- **Een deck dat op 'alleen afspelen' staat toont nooit meer het
  tijdenoverzicht.** Deelde u een vergrendeld deck uit, dan kreeg degene die het
  afspeelde na afloop uw meetscherm te zien — totaaltijd, tijd per dia — omdat
  de schakelaar *tijdenoverzicht tonen* standaard aan staat en met het bestand
  meereisde. Een vergrendeld deck is bedoeld om áf te spelen; wie dat doet hoort
  achteraf geen rapport over zichzelf te krijgen. De uitzondering zit nu in het
  presentatiescherm zelf, dus ook een deck dat langs een andere weg wordt
  afgespeeld valt eronder. Zet u *alleen afspelen* aan onder
  *Presentatie-eigenschappen*, dan valt de schakelaar *tijden-overzicht tonen*
  daar meteen zichtbaar stil, met de reden eronder; uw bewaarde keuze blijft
  staan, zodat ontgrendelen haar teruggeeft.
- **Een afbeelding in de lopende tekst telt nu overal mee.** Stond een afbeelding
  in een afbeeldingsveld, dan wist OciDeck ervan. Stond hij als `![…](…)` in de
  tekst van een dia, dan keek de ene plek na de andere eraan voorbij, elke keer
  met hetzelfde gevolg: een bestand dat wel getekend werd maar nergens in
  meetelde. Er is nu één antwoord op de vraag "welke afbeeldingen gebruikt deze
  dia", en alle plekken lezen datzelfde antwoord.

  Concreet: de privacycontrole redigeert zo'n afbeelding nu ook op een dia die op
  *redigeren* staat — hij reisde daarvoor gewoon mee naar het scherm en de export
  terwijl de tekst ernaast al zwarte blokken toonde. Het opslaan kopieert hem mee
  naar de map van de presentatie in plaats van naar uw eigen schijf te blijven
  wijzen. Het `.ocideck`-pakket stopt hem in het archief, zodat de ontvanger geen
  gat krijgt. De git-opslag neemt hem op in de gedeelde bestandenmap van de
  repository — anders bleef er in `deck.md` een pad staan dat alleen op uw eigen
  computer klopt — en leest hem daar bij het openen ook weer uit. De PDF- en
  PPTX-export laadt hem vooraf in, zodat er geen leeg vak in belandt. De
  kwaliteitscontrole meldt hem als hij ontbreekt of buiten de presentatie ligt.
  De afbeeldingenbibliotheek telt hem als gebruik, zodat "0 dia's gebruiken dit"
  niet langer een onterechte vrijbrief is om te verwijderen, en wijst hem na het
  opruimen van dubbele bestanden naar het behouden exemplaar. Het overnemen van
  dia's uit een andere presentatie maakt zijn pad absoluut, zodat hij niet naar
  de map van de ontvanger wijst. En in de webversie ziet de opruiming van
  afbeeldingen in het browsergeheugen hem eveneens, en gooit ze hem dus niet meer
  weg terwijl de dia hem nog tekent.
- **De HTML-export herhaalde een lange vrije-tekstdia.** Sinds elke pagina van
  zo'n dia als eigen dia wordt geëxporteerd (zie hieronder), kreeg de HTML-export
  diezelfde lijst voorgeschoteld — en omdat een pagina in het bestandsformaat
  geen eigen gedaante heeft, schreef elke pagina de volledige tekst weg. Een dia
  die in drie pagina's uiteenviel stond dus drie keer achter elkaar in de HTML,
  elke keer compleet. De PDF- en PPTX-export hadden hier geen last van; die
  tekenen de pagina's en zien het verschil wel. De HTML-export schrijft zo'n dia
  nu één keer weg, met de hele tekst erin: het opdelen in pagina's is iets van
  de weergave in OciDeck en staat niet in het bestand.
- **Een lange vrije-tekstdia raakt zijn vervolgpagina's niet meer kwijt bij het
  exporteren.** Zet u meer tekst op een dia dan er past, dan verdeelt OciDeck die
  over meerdere pagina's; in de editor en tijdens het presenteren bladert u
  daardoorheen. De PDF- en PPTX-export deed dat niet: die somt dia's op, tekende
  pagina 1 en liet de rest zonder melding weg. Elke pagina wordt nu als een
  eigen dia op ware grootte geëxporteerd, en omdat de voettekst zijn nummer aan
  zijn plaats in die lijst ontleent, tellen paginanummers in de voettekst de
  vervolgpagina's voortaan mee.

  In dezelfde beweging is de teller die rechtsboven **op** zo'n dia stond
  verdwenen. Die begon bij elke dia opnieuw bij één, terwijl de zaal naar dia 7
  van 24 keek — twee nummeringen door elkaar, waarvan de opvallendste de minst
  betekenisvolle was. Waar u bent blijft gewoon zichtbaar, maar in de rand van
  het programma in plaats van in het beeld van de zaal: het voorbeeldpaneel en
  de presentatorweergave tonen "Pagina 2 / 3" naast het dianummer. Aan het
  presenteren zelf verandert niets — u bladert met dezelfde toetsen eerst door
  de pagina's van een dia en dan pas naar de volgende dia.
- **Een presentatie die naar een submap gaat, komt daar ook onder die naam
  aan.** Sloeg u een deck op naar S3 of WebDAV op een pad zónder map ervoor,
  dan ging het object met een `./` ervoor de lijn over: de sleutel waar
  daadwerkelijk naartoe werd geschreven was anders gespeld dan de herkomst die
  het tabblad bewaarde, en op WebDAV probeerde de client er ook nog een map `.`
  van te maken. Beide kanten normaliseerden dat weg, dus er raakte niets kwijt —
  maar wat over de lijn gaat, hoort te staan zoals u het koos.

- **Een ingesloten YouTube-video gaat niet langer langs het domein dat u
  volgt.** OciDeck gebruikt overal de nocookie-variant van YouTube — behalve op
  één plek, en dat was uitgerekend de speler zelf. Die haalde zijn script van
  `www.youtube.com`, en met dat script bouwde YouTube de speler vervolgens óók
  op `www.youtube.com` in plaats van op de nocookie-vorm. Wie *online media*
  aanzette om één video te tonen, gaf daarmee ongemerkt een bezoek weg aan het
  domein dat wél een profiel opbouwt.

  De speler kan zonder dat script. Het startpunt, het eindpunt, automatisch
  afspelen en het onderdrukken van gerelateerde video's zaten al in de
  insluit-URL, en de meldingen over positie, einde en fouten komen via het
  kanaal dat de speler zelf openzet — hetzelfde kanaal waar dat script een
  omhulsel omheen was. YouTube gaat daarmee dezelfde weg als Vimeo: één kaal
  kader, één adres. Een niet-volgende bron voor dat script bestaat niet;
  `youtube-nocookie.com` levert het niet uit (getoetst 22-07-2026), dus
  weglaten was de enige route.

  Twee dingen erbij. Het YouTube-logo in de speler is een link naar de
  kijkpagina, en één klik daarop tijdens een presentatie verving uw dia door die
  pagina — op precies het domein dat u wilde vermijden. Die navigatie wordt nu
  geweigerd, en de controle kijkt daarbij naar de hostnaam in plaats van naar
  "staat deze tekst er ergens in", zodat een adres dat de naam alleen nabootst
  er niet meer doorheen glipt. En een kader dat wél laadt maar niets terugmeldt,
  levert geen valse foutmelding meer op; laadt er werkelijk niets, dan blijft de
  melding staan.

  Wat er niet mee opgelost is: YouTube ziet nog steeds dát u de video opvraagt,
  en de beelden komen nog steeds van zijn eigen mediaservers. `PRIVACY.md` is
  daarop bijgewerkt.

- **Een bevinding in een tabel zegt nu in welke cel hij zit.** Er stond "Tabel
  14". Dat is het volgnummer dat de scanner intern gebruikt — een getal dat
  nergens op uw dia staat en dat u zonder de breedte van de tabel niet eens kunt
  terugrekenen. Een plaatsaanduiding die zelf een raadsel is, helpt niemand. Er
  staat nu "Tabel rij 4, kolom 2", geteld zoals u ze op de dia telt; de koprij
  heet "Tabel koprij", want die heeft op het scherm ook geen nummer.
- **Een bevinding op een presentatiegegeven stuurt u niet langer naar de
  kleurinstellingen.** Een bevinding die over de hele presentatie gaat, was ooit
  vanzelf een themakwestie: alleen de contrastcontroles meldden zich op dat
  niveau. Sinds de privacycontrole ook de kop van het bestand leest, klopt dat
  niet meer — een e-mailadres in het auteursveld gaat over de hele presentatie en
  heeft niets met kleur te maken.

  Zo'n melding opende toch de kleurinstellingen, zocht daar een veld dat niet
  bestaat, markeerde dus niets, en liet u achter tussen de kleurkiezers. Ze heet
  nu *Presentatiegegevens*, de knop zegt "Open presentatiegegevens", en dat is
  ook wat er opengaat. Het geldt voor alle velden uit de kop: auteur,
  organisatie, beschrijving, trefwoorden, versie, datum, gebruikte standaarden en
  hulpmiddelen, en de twee MIAUW-motiveringen. Zes daarvan hadden bovendien
  helemaal geen plaatsaanduiding in het paneel — een bevinding op het versieveld
  kwam binnen als "Presentatiegegevens · Privacy", en verder zoeken maar. Ze
  worden nu bij naam genoemd.
- **Video en audio worden nu ook op hun inhoud gecontroleerd.** Van een
  afbeelding werd altijd al nagegaan of het écht een afbeelding was; bij video
  en audio werd alleen naar de omvang gekeken. Een willekeurig bestand met de
  naam `.mp4` kwam zo uw presentatie in. Nu wordt de soort aan de inhoud
  herkend, net als bij afbeeldingen.
- **Weigeringen laten voortaan een spoor na.** Werd een deck tegengehouden
  omdat er uitvoerbare inhoud in zat, of een export omdat de rubricering het
  niet toeliet, dan zag u dat wel maar bleef er niets van bewaard. Voor een
  gereedschap dat verzegelde rapporten uitgeeft is juist dát het feit dat u
  achteraf wilt kunnen navertellen. Er komt geen inhoud van uw presentatie in
  te staan — alleen wat voor soort weigering het was.
- **Een export die niets doet, blijft niet meer eeuwig niets doen.** De PDF- en
  PPTX-export maakt zijn afbeeldingen door de échte dia te laten tekenen en het
  resultaat vast te leggen. Daarvoor moet het venster beelden produceren — en
  dat doet macOS niet zodra u het minimaliseert, er een ander venster overheen
  legt, of naar een ander bureaublad wisselt. De export stond dan stil: geen
  dia, geen voortgang, geen melding, en wachten hielp niet.

  Er zit nu een grens op dat wachten. Komt er twintig seconden lang geen beeld,
  dan stopt de export met een melding die zegt wat eraan scheelt in plaats van
  eindeloos stil te staan. En de voortgang meldt zich voortaan al vóórdat er
  gewacht wordt, zodat u tenminste ziet dát hij begonnen is.

  De praktische oplossing blijft eenvoudig: laat het venster tijdens het
  exporteren gewoon op de voorgrond staan. De HTML-export heeft hier geen last
  van; die tekent geen dia's.

- **Uw wachtwoord en uw git-token gaan niet meer onversleuteld over het
  netwerk.** Had u een opslagserver als "vertrouwd intern" gemarkeerd — bedoeld
  voor een eigen doos op uw eigen netwerk — dan stond OciDeck een gewone
  `http`-verbinding toe. Bij WebDAV en git ging uw inloggegeven daar bij élk
  verzoek in leesbare vorm overheen.

  Die vink gaat over de sérver, niet over de weg ernaartoe. Dat verschil is bij
  de inhoud van een presentatie te overzien — u kiest zelf of u dat over uw LAN
  wilt sturen — maar bij een wachtwoord of token niet: wie het één keer
  onderschept, houdt het, en het blijft werken lang nadat die persoon weg is.

  Voor zo'n verbinding is `https` nu vereist. Wat blijft werken: een openbare
  bron zonder inloggegeven, en S3/MinIO (dat ondertekent elk verzoek apart, dus
  er gaat geen herbruikbaar geheim over de lijn). Draait de server op deze
  computer zelf, dan verandert er ook niets — dat verkeer verlaat de machine
  niet.

  Merkt u dit? Dan werd uw wachtwoord tot nu toe leesbaar verstuurd. Zet de
  server op https, of gebruik hem zonder inloggegeven.
- **Een presentatie kan niet meer naar willekeurige poorten verbinden.** Haalde
  een dia een afbeelding of video van een adres op, dan werd wel gecontroleerd
  wélke computer dat was, maar niet op welke poort. De webversie deed dat al
  wel. Beide kanten hanteren nu dezelfde lijst.
- **De webversie zegt nu ook waar een formulier níet heen mag.** De
  beveiligingsregels van de webbundel bepalen per soort verkeer waar de pagina
  iets vandaan mag halen. Voor het versturen van een formulier stond dat er niet
  bij — en anders dan bij de meeste van die regels betekent "niets ingevuld"
  hier niet "dan geldt de algemene regel", maar "dan mag alles". Een injectie
  had een formulier dus naar een willekeurige bestemming kunnen sturen.

  Er staat nu expliciet dat het naar niets mag. OciDeck tekent zijn scherm zelf
  en verstuurt geen enkel formulier, dus u merkt er niets van.

  Gevonden door de nieuwe scan van de webversie, de eerste keer dat die liep.
  De controle op de webbundel bewaakt het voortaan, en die controle is ook
  omgekeerd getoetst: haal je de regel weg, dan valt hij echt om.
- **De webversie verklapt niet meer aan welke presentatie u werkt.** Haalt u een
  deck op via een link, dan vertelde uw browser aan die server standaard van
  welke pagina u kwam — inclusief het volledige adres van uw eigen presentatie.
  Bij een deck-link is juist dat adres vaak het gevoelige deel: wie hem heeft,
  heeft het deck.

  De bundel zegt nu zelf dat er niets meegestuurd mag worden. Dat werkt zonder
  dat uw beheerder er iets voor hoeft te doen — anders dan de meeste van deze
  regels, die alleen gelden als de server ze meestuurt. De controle op de
  webbundel bewaakt het.

  Voor beheerders staat er in de uitrolgids nu ook bij dat de server
  `Strict-Transport-Security` hoort mee te sturen; dat ontbrak. Zonder die kop
  gaat het állereerste verzoek naar uw server nog over een onbeveiligde
  verbinding, en dat is precies het moment waarop iemand ertussen kan gaan
  zitten. En de losse ophaaldienst zet zijn "niet zelf raden wat voor bestand
  dit is"-kop voortaan óók op een weigering, niet alleen als het lukt.

- **De licenties, kennisgevingen en SBOM kloppen weer.** Een reeks dingen die
  stil fout stonden, en die u pas merkt als u OciDeck of een export van OciDeck
  aan iemand anders doorgeeft.

  De gevendorde plugin `desktop_multi_window` stond overal als MIT genoteerd,
  maar is Apache-2.0. Dat is nu rechtgezet in de SBOM en de kennisgevingen, de
  zes bestanden die wij in die fork wijzigden dragen de wijzigingsnotitie die
  Apache-2.0 vraagt, en beide forks hebben een `MODIFICATIONS.md` met de
  herkomstcommit erbij. In de SBOM dragen ze nu ook een hash — daarvoor waren
  zij de enige twee onderdelen zonder.

  Twaalf afhankelijkheden die u wél meekrijgt, stonden niet in
  `THIRD_PARTY_NOTICES.md`. Ze staan er nu allemaal in, met hun licentie, en een
  test houdt die lijst voortaan bij de tijd.

  Belangrijker voor u: de licentieteksten reisden niet mee. De vier
  OFL-bestanden van de lettertypen zaten in geen enkele build, en er was geen
  plek in de app om een licentie te lezen. Onder **Instellingen → Over OciDeck**
  staat nu **Alle licentieteksten tonen**, met alles erin — pakketten,
  lettertypen, het gezichtsmodel en de JavaScript uit de HTML-export. Diezelfde
  export draagt voortaan zelf een blok met de volledige licentieteksten en per
  ingesloten bibliotheek een licentieregel; bij het doorsturen van een export
  bent u de verspreidende partij, en die kunt u nu ook zijn.

  Tot slot: het Klingon-vlaggetje in de taalkiezer was het embleem van het
  Klingon-rijk — een beeldmerk van iemand anders dat in elke uitgeleverde
  versie meereisde. Het is vervangen door een nuchter `tlh`-plaatje. De taal
  blijft gewoon.
- **Uw eigen regels in de kop breken het zegel niet meer.** Sinds OciDeck de
  front matter bijwerkt in plaats van herbouwt, blijft wat u er zelf in zet
  netjes staan — een eigen `style:`-blok, een commentaarregel, een handmatige
  `header:`. Alleen dekte het documentzegel die regels óók. Wie zijn eigen CSS
  bijstelde in een verzegeld deck, kreeg daarna te horen dat het document na het
  afronden gewijzigd was, terwijl er geen letter inhoud veranderd was.

  Het zegel dekt voortaan wat OciDeck schrijft, niet wat u schrijft. Uw regels
  blijven in het bestand staan en blijven van u; ze aanpassen geldt niet langer
  als manipulatie. Uw zichtbare ondertekening valt er bewust wél onder, zodat
  knoeien daarmee zichtbaar blijft. Dezelfde afweging als bij de formaatversie:
  een vals alarm is duurder dan geen alarm.

  *Bijgesteld een dag later, toen het zegel over het bestand ging in plaats van
  erin (zie hierboven).* Beide helften van deze alinea zijn daarmee achterhaald.
  Een hash over het bestand kan geen regels overslaan — de ontvanger draait
  `sha512sum` over het hele bestand, en een oordeel dat alleen OciDeck kan
  navertellen was nu juist wat we kwijt wilden. Uw eigen regels vallen er dus
  weer onder, en uw ondertekening er juist niet meer (die staat nu naast het
  zegel in plaats van eronder). Wat het valse alarm wegneemt is niet langer een
  uitzondering maar de bevriezing zelf: een afgerond rapport is alleen-lezen,
  dus u kunt uw CSS er niet meer in bijstellen en er achteraf door verrast
  worden.

- **De documentatie noemt de juiste dekkingsvloer.** Vijf plaatsen in `docs/`
  hielden vol dat de afgedwongen dekking 78 % was — één zei 79 % — terwijl de
  Makefile al op `--min=80` staat. Wie de documentatie geloofde, dacht ruimte te
  hebben die er niet is. `docs/CHECKS.md` had het als enige goed; de rest volgt
  dat nu. De twee andere getallen in diezelfde tabel (bestandslengte 1000,
  methodelengte 150) zijn tegen `tool/check_conventions.dart` en
  `tool/check_method_length.dart` nagelopen en kloppen wel.
- **Een `style:`-blok in de kop van het bestand blijft een blok.** Zette u daar
  Marp-CSS in met een regel die op `thema: iets` leek, dan las OciDeck dat als
  het thema van de presentatie, en kwam er bij het opslaan een tweede
  `theme:`-regel bij. De ingebouwde controle klaagde bovendien over elke regel
  van dat blok. Lezen, schrijven en controleren hanteren nu dezelfde regel.
- **Een aankruislijst kunt u weer uitzetten door de vinkjes weg te halen.** De
  zichtbare opmaak kon de lijststijl wel aanzetten maar nooit terug; haalde u
  de hokjes weg, dan bleef het een aankruislijst.
- **Een bestand van een nieuwere OciDeck wordt niet meer half gelezen.** De
  bestanden naast uw presentatie — tekeningen, aantekeningen — dragen een
  versienummer. Dat werd niet of verkeerd gelezen: wat een nieuwere versie erin
  had gezet werd voor de helft ingeladen, en bij het eerstvolgende opslaan
  verdween de rest. Nu wordt zo'n bestand niet geladen én niet overschreven, dus
  het blijft heel tot u het opent met een versie die het begrijpt.
- **Zes landpakketten stonden aan en keken naar niets.** Cyprus, Luxemburg,
  Letland, Malta, IJsland en Liechtenstein stonden als vinkje in *Instellingen →
  Beveiliging*, standaard aan, terwijl er voor die landen geen enkele regel
  bestond. Wie ze zag staan mocht aannemen dat er naar Cypriotische of Maltese
  nummers werd gekeken, en las "niets gevonden" waar in werkelijkheid niemand
  had gekeken. Dat is het verkeerde soort geruststelling, en het is precies wat
  `docs/PRIVACY.md` belooft niet te doen. De zes zijn daarom uit de lijst
  gehaald tot hun regel er is.

  Twee landen zijn juist wél gaan werken. Slowakije deelt het rodné číslo met
  Tsjechië — het nummer stamt uit Tsjecho-Slowakije en heeft in beide landen
  dezelfde vorm en dezelfde controle — en de Litouwse persoonscode heeft
  dezelfde dubbele mod-11 als de Estse. Beide nummers worden nu herkend zodra u
  het Slowaakse respectievelijk het Litouwse pakket aan hebt staan, zonder dat
  wie beide buurlanden aan heeft dezelfde treffer twee keer krijgt.
- **Zes velden uit de documentgegevens werden gemeld maar niet weggelakt.** De
  controle keek al naar de versie, de datum, de gebruikte normen, de gebruikte
  hulpmiddelen en de twee soorten MIAUW-motiveringen, maar het profiel
  *geredigeerd* liet ze staan. U kreeg dus een melding die u met redigeren niet
  kón oplossen, en de waarde ging alsnog mee in PDF, PPTX, HTML en het
  publieksvenster. Juist de motiveringen zijn hier gevoelig: die reizen
  gecodeerd mee in de kop van het bestand, waar geen enkele vluchtige controle
  ze leest, en beginnen niet zelden met "op verzoek van".

  Hetzelfde gold voor het scopeveld van een controlelijst-dia. Dat staat
  zichtbaar op de dia en werd gescand, maar bleef staan — inclusief een adres
  met een klant- of gebruikersnaam erin.
- **Het redactieoverzicht telt nu wat er werkelijk is weggelakt.** Het bestand
  dat opsomt wat er uit een export is gehaald, kreeg regels voor twee soorten
  dingen die niet in het document staan: een aanwijzing die niet weggelakt
  wordt (het woord "diagnose" zonder dat er iemand bij staat) en een bevinding
  die nergens naar wijst. Een ontvanger ging dan zoeken naar zwarte blokken die
  er niet zijn, wat het overzicht juist onbetrouwbaar maakt. Omgekeerd ontbraken
  de redacties in de documentgegevens volledig: een weggelakte auteursnaam had
  geen enkele regel om naar te wijzen en dus ook niets om tegen te betwisten.
- **Werkelijke celwaarden uit een grafiekbestand stonden in het logboek.** Kon
  OciDeck een cel niet als getal lezen, dan schreef de waarschuwing tot vijf van
  die cellen letterlijk weg. Een grafiekbestand kan een omzet per klant of een
  uitslag per persoon bevatten, en de cel die "geen getal" is, is vaak juist de
  tekstkolom ernaast. De melding noemt nu alleen nog hoeveel cellen het betrof;
  wélke het zijn, ziet u in het bestand zelf.
- **Wat u zelf in de kop van een bestand zet, blijft nu staan.** Zette u met de
  hand een `header:`, `footer:`, `size:` of `style:` in de front matter — gewone
  Marp-opties — dan was die verdwenen zodra OciDeck het bestand één keer had
  opgeslagen. Een commentaarregel, een lege regel of een ingesprongen blok ging
  op dezelfde manier verloren. OciDeck bouwde de kop namelijk opnieuw op uit wat
  het zelf kende.

  Dat gebeurt niet meer: bij het opslaan worden alleen de regels bijgewerkt die
  OciDeck ook echt beheert. Al het andere blijft exact staan waar het stond,
  inclusief uw eigen aanhalingstekens en de volgorde die u koos. De belofte dat
  een OciDeck-bestand gewone Marp is, geldt daarmee ook de andere kant op.

  De markdown-controle in de app zei bij zo'n sleutel "wordt genegeerd". Dat
  klopte niet meer en is nu: hij doet niets in OciDeck, maar hij blijft
  behouden.
- **Grafiekcijfers die bij het opslaan niet weggeschreven konden worden, worden
  gemeld.** Opslaan haalt de cijfers van een grafiek uit de markdown en zet ze in
  een bestand in `data/`; de presentatie houdt alleen de verwijzing over. Lukte
  dat schrijven niet — het `source`-pad wees buiten de projectmap, de schijf was
  vol, de rechten ontbraken — dan stond er een geslaagde opslag op het scherm
  terwijl die cijfers alleen nog in dit venster bestonden. De opslag geeft de
  klacht nu door en u krijgt een foutmelding met de betrokken bestanden erbij, in
  dezelfde vorm als de melding die u bij het *openen* al kreeg.

  Daarnaast wordt een databestand dat u ondertussen buiten de app hebt gewijzigd
  niet meer overschreven. Veranderden beide kanten, dan won tot nu toe de app en
  verdween de wijziging van degene die het bestand bijwerkte, met niets meer dan
  een regel in het logboek. Nu blijft het bestand op schijf staan zoals het is
  geworden en hoort u van de botsing; wat in de editor staat is niet weg, het
  staat alleen nog niet op schijf.
- **Een dia die door zijn classificatie wordt achtergehouden, verdwijnt niet
  langer zwijgend.** Een dia met een strengere TLP-classificatie dan de
  presentatie haalt het publiek niet — dat is de bedoeling — maar er was in de
  editor niets van te zien. Beide niveaus staan standaard op *geen*, dus één dia
  op AMBER valt weg uit een deck waarvan het deckniveau nooit is gezet.

  In de diastrook draagt zo'n dia nu een eigen vlaggetje **Achtergehouden** en is
  hij gedimd zoals een overgeslagen dia, met een eigen kleur en een tooltip die
  het niveau noemt; boven de lijst staat hoeveel dia's het betreft. Blijft er
  niets over om te tonen of te exporteren, dan noemt de melding de echte oorzaak.
  Daar stond "Alle slides zijn overgeslagen", en dat wees naar *Alles tonen* —
  een knop die aan een classificatie niets verandert.
- **Opslaan naar git zegt vóór de commit wat er niet meereist.** In de commit
  gaan `deck.md`, de gedeelde afbeeldingenpool en de grafiekdata. Video, audio,
  de tekeningen op uw dia's en de gebruikersnotities gaan niet mee; naar een
  bestand of een `.ocideck`-pakket gaan ze wél, dus wie van schijf naar git
  verhuisde raakte ze kwijt zonder dat er iets misging. Het enige wat erover werd
  gezegd was een regel ná de commit, en die ging alleen over video en audio.

  Nu telt een venster vóór de commit per soort wat achterblijft, en u kiest of
  het door mag gaan. Achteraf melden is geen melding meer: dan denkt u al dat uw
  werk in de repository staat. Wat er wél en niet meegaat is verder ongewijzigd —
  alleen de waarschuwing is nieuw.
- **De browser waarschuwt voordat u een tabblad met onopgeslagen werk sluit.** In
  de webversie bestaat geen crashherstel: er is geen map om een herstelkopie in
  te schrijven, dus er wordt niets bewaard. Op desktop werkt dat wél, en niets
  vertelde u dat het hier anders is. Zodra u iets wijzigt zegt de app dat nu één
  keer, en zolang er niet-opgeslagen werk openstaat vraagt de browser om
  bevestiging voordat het tabblad weggaat. De tekst van die vraag is van de
  browser zelf en niet te kiezen. Op desktop verandert er niets: daar houdt het
  venster het sluiten al tegen en stelt de app dezelfde vraag zelf.
- **De herstelkopie neemt de tekeningen mee.** Tekenen op een dia maakt de
  presentatie gewijzigd, dus een deck waarin u alleen getekend had werd wel
  automatisch bewaard — maar de tekenlaag zit in een eigen bestand naast de
  markdown en ging niet mee in de kopie. Na een crash kwam het deck terug zonder
  de tekeningen, zonder dat iets dat zei. De autosave schrijft de tekenlaag nu
  mee en het herstel zet haar terug. Een tekenlaag die niet te lezen is houdt het
  herstel van de tekst niet tegen, net zoals bij een beschadigd bestand op schijf.
- **De tijdlijn kapt haar tekst niet langer af.** Een tijdlijn met zes normale
  gebeurtenissen liet van élke titel en élke beschrijving een deel wegvallen
  achter een `…`. De oorzaak was een schatting: het aantal regels werd afgeleid
  uit `lengte / tekens-per-regel`, wat de werkelijke breedte van de letters in
  uw profiellettertype niet kan kennen. Op een dia van zes kaarten sloeg die
  schatting om bij een marge van 0,2 promille, waarna de beschrijving terugviel
  op één regel van ongeveer 35 tekens — terwijl er 64 stonden.

  De kaarten meten nu de echte tekst en kiezen de grootste lettergrootte waarbij
  alles heel blijft. Daarbij mogen ze breder worden dan voorheen (de oude
  bovengrens lag ruim onder wat de tijdlijn aankan), mag een lange titel een
  tweede regel gebruiken, en kan een uitzonderlijk lange markering de titel niet
  meer uit de kaart duwen. Wat niet verandert: kaarten blijven binnen hun eigen
  rij, dus ze kunnen nooit over elkaar heen vallen.

### Added
- **Twee nieuwe vraagsoorten: een beeldpaar en een getypt antwoord.** De
  vraagdia kende vier soorten, en die vroegen alle vier om een keuze uit een
  rijtje tekst.

  **Twee afbeeldingen** legt twee beelden naast elkaar en laat de kijker de
  juiste aanwijzen — "welke van deze twee schermen is de phishingpagina". U
  kiest in de editor twee afbeeldingen, geeft ze elk een bijschrift en zet met
  één knop vast welke de juiste is. Bij het presenteren wisselen links en rechts
  per ronde, dus noem ze in uw bijschrift niet "de linker" en "de rechter". Zet
  u er met de hand meer paren in het bestand, dan komt er elke ronde één juiste
  en één foute uit die verzameling. Ontbreekt een van de beelden, dan meldt de
  bestandscontrole dat — een lege tegel waar een antwoord hoort merkt u anders
  pas als u in de zaal staat. In een HTML-export komen de twee beelden gewoon
  als afbeeldingen achter de vraag te staan, zonder dat erbij staat welke de
  goede is.

  **Getypt antwoord** laat de kijker het antwoord intypen in plaats van
  aanwijzen. U vinkt aan welke antwoorden goed gerekend worden — meer dan één
  mag — en schuift met een regelaar in hoeverre het getypte antwoord daarop moet
  lijken: standaard 85 %, wat een tikfout doorlaat maar een ander woord niet.
  Hoofdletters, spaties vooraan en achteraan en dubbele spaties worden
  weggepoetst voordat er vergeleken wordt; leestekens blijven staan, omdat ze
  soms bij het antwoord horen — een losse punt te veel haalt u zelden onder de
  drempel. Typen gaat op uw eigen scherm en het beamervenster toont mee wat
  er staat. Zolang er getypt wordt gaan de toetsen naar het invoerveld en niet
  naar de sneltoetsen — anders sprong een `3` in het antwoord naar dia 3 —
  behalve `Enter` (bevestigen), `PgUp`/`PgDn` (bladeren, zodat een
  presentatieklikker blijft werken), `Esc` (presentatie afsluiten) en
  `Ctrl/Cmd+W`. Vóór het antwoorden is er op geen van beide schermen iets van de
  oplossing te zien — maar dat is enscenering, geen geheimhouding: het
  beamervenster krijgt het hele deck, dus een vraagdia is niet de plek om iets
  te verbergen voor wie bij die machine kan.

  Zodra het antwoord binnen is, komt er in plaats van het invoerveld een
  **correctie**: *Jouw antwoord* en *Het juiste antwoord* onder elkaar, met het
  verschil aangewezen. Wat er te veel stond is rood en doorgestreept, wat er
  miste groen en onderstreept — de doorstreping en de onderstreping staan er
  náást de kleur, zodat de aanwijzing ook leesbaar blijft voor wie rood en groen
  slecht uit elkaar houdt. Eronder staat het percentage naast de drempel die u
  koos ("Overeenkomst: 62% · nodig: 85%"), want een kaal getal is nog geen
  oordeel. De vergelijking is net zo soepel als het goedrekenen zelf —
  hoofdletters en dubbele spaties tellen niet mee — dus er wordt nooit een
  verschil aangewezen dat niet meetelde, en bij een letterlijk goed antwoord
  blijft de vergelijking helemaal weg. Heeft u meerdere antwoorden goed
  gerekend, dan wordt er gecorrigeerd tegen het antwoord dat het dichtst bij het
  getypte lag, niet tegen het eerste in uw lijst.
- **Het tijdenoverzicht na een oefenronde toont nu ook de vragen.** Onder de
  tijd per dia staat elke beantwoorde vraag, met de tijd van díe poging en of
  het antwoord goed was. Elke poging apart en niet opgeteld: bij *opnieuw
  proberen* mag een vraag zo vaak beantwoord worden als nodig, en drie pogingen
  in vijf seconden is een ander verhaal dan één poging van twee minuten. Een
  vraag die u overslaat zonder te antwoorden telt niet mee. De knop *Kopieer*
  neemt het vragenblok mee naar het klembord.
- **Een afbeelding midden in een tekstdia.** Zet u op een dia met vrije tekst een
  `![beschrijving](images/foto.png)` op een eigen regel, dan tekent OciDeck die
  afbeelding voortaan op die plek in de tekst. Tot nu toe bleef daar de kale
  markdowncode staan. Het bestandsformaat kon dit al — de tekst gaat letterlijk
  het bestand in en er weer uit — alleen keek er niemand naar.

  De maat regelt u met dezelfde aanwijzing als Marp: `![w:600 h:400](…)`. Die
  telt in Marp's eigen maatvoering, waarin een dia 1280 breed is, zodat `w:600`
  in de app hetzelfde betekent als in de HTML-export. Laat u `w:` weg, dan
  gebruikt de afbeelding de volle breedte van de tekstkolom. Laat u `h:` weg,
  dan krijgt hij een vast vak van een kwart van de diabreedte hoog. Dat vak komt
  bewust niet uit de afbeelding zelf: OciDeck moet weten hoeveel ruimte er weg
  gaat vóórdat er ook maar één bestand is ingelezen, anders zou de tekst
  verspringen zodra een foto binnen is. Binnen dat vak wordt de afbeelding
  passend geschaald zonder bij te snijden — wilt u hem hoger of lager, geef dan
  `h:` op. Voor elke andere markdownlezer is die `w:`/`h:` gewone
  beschrijvingstekst, dus uw bestand blijft leesbaar buiten OciDeck.

  Alleen een afbeelding die alléén op zijn regel staat wordt zo getekend; eentje
  midden in een zin blijft tekst, zodat een zin niet halverwege door een plaatje
  wordt gebroken.
- **Een lang document opknippen in hoofdstukken.** Plakt u een heel document in
  een tekstdia, dan staan de `#`-koppen ervan midden in die ene dia. In Marp ís
  `#` de titel van een dia, dus zo'n kop doet zich voor als titel zonder er een
  te zijn, en u kunt dat hoofdstuk niet verplaatsen, overslaan of apart
  presenteren.

  Boven het tekstvak verschijnt daarom een regel die zegt hoeveel dia's het
  oplevert, met de knop **Splits op hoofdstukken**. Elk hoofdstuk wordt een eigen
  dia met de kop als titel; staat er een `##` direct onder zo'n kop, dan wordt
  dat de ondertitel. De tekst vóór het eerste hoofdstuk blijft bij de dia waar u
  al was, met zijn eigen titel. Het is één bewerking, dus één keer ongedaan maken
  zet alles terug.

  Het gebeurt alleen als u erom vraagt. Een bestaand deck met koppen in de tekst
  komt bij het openen ongewijzigd terug — herstructureren tijdens het inlezen zou
  stilzwijgend veranderen wat u had opgeschreven. Een `##` blijft een kop bínnen de
  dia, en een `#` in een codeblok is broncode en knipt niet. Op een dia met tekst
  én een afbeelding wordt het niet aangeboden: waar die afbeelding heen moet is
  een keuze die alleen u kunt maken.
- **Een export met ongecontroleerde AI-tekst zegt dat voortaan zelf.** OciDeck
  markeert een veld dat een AI heeft opgesteld en houdt *Afronden & verzegelen*
  tegen tot een mens erop **Nagekeken** heeft gedrukt. Die poort werkte, maar
  alleen binnen de app: wie de PDF, de PPTX of de HTML in handen kreeg, zag
  nergens dat er nog niet-nagekeken AI-tekst in stond. De transparantie hield op
  precies waar ze nodig werd.

  De melding reist nu mee, in dezelfde gelaagde vorm als de TLP-markering:
  machineleesbaar in de trefwoorden van de PDF en de PPTX en in een
  `<meta name="ai-generated">` in de HTML; leesbaar in het veld *Onderwerp*, dat
  elke lezer in de eigenschappenkaart van het bestand ziet; zichtbaar als balk
  boven aan de HTML-export, onder de TLP-balk; en als `-ai-concept` in de
  bestandsnaam. Dat laatste om dezelfde reden als bij een geredigeerde export:
  de duurste fout is de verwisseling, en die moet u kunnen zien zonder het
  bestand te openen.

  Het exportvenster meldt het vóór u op een formaatknop drukt, zodat de andere
  bestandsnaam geen verrassing achteraf is. Exporteren blijft gewoon mogelijk —
  verzegelen is een verklaring en blijft geblokkeerd, maar de normale manier om
  iets nagekeken te krijgen is het naar een lezer sturen. Ook de geredigeerde
  uitvoering houdt de melding vast: redigeren haalt persoonsgegevens weg, niet
  de herkomst van de tekst, en juist dat exemplaar bereikt de wijdste kring.

  Zodra u de tekst hebt nagekeken meldt de export niets meer. Dat is geen gat
  maar precies waar die knop voor staat.

- **Bij elk merk dat OciDeck voert, staat nu wie het bezit.**
  `THIRD_PARTY_NOTICES.md` heeft een merkenparagraaf met Marp, Nextcloud,
  YouTube en Vimeo: per naam de eigenaar, en de mededeling dat er geen band mee
  bestaat. Die namen staan in de interface en in de documentatie omdat er geen
  andere manier is om te zeggen wat het product doet — het formaat dat het
  schrijft, de server waar het heen praat, de speler die het insluit. Dat is
  nominatief gebruik en juridisch laag risico, maar alleen zolang de eigenaar
  erbij staat; zonder vermelding blijft de suggestie hangen dat het merk van ons
  is of dat er wordt samengewerkt.

  Er is geen nieuw document voor gemaakt; het staat waar de andere
  kennisgevingen al stonden. Een controle bewaakt het voortaan: elke
  embed-aanbieder en elke WebDAV-smaak zit in een opsomming in de code, dus een
  nieuwe merknaam valt op vóórdat hij ongenoemd in de interface belandt.

- **Op macOS heeft OciDeck nu een menubalk.** Bestand, Bewerken, Presentatie,
  Venster en Help, met de handelingen die u tot nu toe alleen vond als u wist
  waar u moest kijken: in een `⋮`-menu, in de statusbalk, of achter een sneltoets
  die nergens stond. Op een Mac is de menubalk de plek waar u ontdekt wát een
  programma kan.

  Er komen maar twee sneltoetsen bij (`Cmd + ,` voor de instellingen en
  `Cmd + N` voor een nieuw tabblad); de rest bestond al en wordt er alleen
  zichtbaar. Knippen, kopiëren, plakken en alles selecteren staan er ook in —
  deze balk vervangt het standaardmenu van macOS, en dat mag u geen
  tekstbewerking kosten. Een handeling waarvoor geen presentatie open staat,
  blijft staan maar grijs: een menu-item dat komt en gaat, leert niemand wat de
  app kan.

  Windows en Linux krijgen hun venstermenu van het bureaublad zelf en de
  webversie heeft er geen, dus daar verandert er niets.
- **Ongedaan maken, opnieuw, zoeken, de eigenschappen, deze handleiding en het
  sneltoetsenoverzicht staan nu ook in het opdrachtenpalet** (`Ctrl/Cmd + K`).
  Ongedaan maken en opnieuw bestonden alleen als twee kleine icoontjes in de
  werkbalk, terwijl het palet in deze app de plek is waar een functie gevonden
  wordt. Wat er niet in staat, bestaat voor de meeste mensen niet.
- **Het openscherm zegt eindelijk waar u bent.** Er stonden een logo en vier
  knoppen, en geen antwoord op de enige vraag die iemand daar heeft. Onder het
  logo staat nu één regel over wat OciDeck maakt, onder *Nieuwe presentatie*
  hoeveel sjablonen er achter die knop klaarstaan — geteld uit de catalogus
  zelf, dus dat aantal kan niet verouderen — en naast *Instellingen* een knop
  **Gebruikershandleiding**. Die stond tot nu toe drie klikken diep onder
  *Instellingen → Documentatie*, precies waar iemand die nog niets weet niet
  gaat kijken.
- **Bij het kiezen van een slidetype staat de uitleg er nu bij.** Onder het
  rooster verschijnt de toelichting van het type dat uw muis of uw
  toetsenbordfocus aanwijst. Die tekst bestond al — volledig, in alle talen —
  maar verscheen pas ná het invoegen, achter een dichtgeklapte "Wat kan ik
  hier?". Wie moest kiezen, koos dus op een tekening en één woord. Dezelfde zin
  gaat mee als schermlezer-tekst op het kaartje zelf, zodat wie niet kijkt hem
  hoort op het moment dat de keuze valt.
- **U kunt nu zien wat de ontvanger krijgt, vóórdat u iets verstuurt.** Staat een
  dia op *weglaten uit tonen en exporteren*, dan verschijnt boven de
  voorvertoning een melding die zegt wat er gebeurt — de gevonden gegevens worden
  zwart gemaakt, én álle afbeeldingen, video en audio van die dia gaan niet mee.
  Dat tweede stond nergens, en het is de duurste verrassing van de twee: een dia
  die in de export ineens leeg is, ziet eruit als een fout in plaats van als uw
  besluit.

  Naast die melding staat een schakelaar **Wat zij zien / Mijn tekst**. Aan toont
  hij die ene dia door dezelfde bewerking waar presenteren en exporteren doorheen
  gaan. Tot nu toe beloofde het label in de editor dat er iets zou worden
  weggelaten, veranderde het scherm niets, en gaf pas de PDF antwoord — en dan is
  het bestand er al.

  De schakelaar staat standaard uit en dat is de hele opzet: u moet uw eigen
  tekst kunnen zien om hem te kunnen wijzigen. Uw markdown-bestand houdt hoe dan
  ook alles.
- **Opslaan laat zien dat het bezig is.** In de statusbalk draait tijdens een
  opslag een melding met de bestemming erbij — *Opslaan…*, *Uploaden naar
  WebDAV…*, *Uploaden naar S3…*, *Vastleggen in git…* — en de opslagknop in de
  werkbalk staat zolang uit. Een opslag naar een server is één upload per
  mediabestand en een git-commit zijn meerdere heen-en-weertjes; op een trage
  verbinding was dat niet te onderscheiden van een vastgelopen programma, en dus
  klikte u nog eens, en nog eens. De bestemming staat erbij omdat die zegt of het
  aan uw schijf of aan uw verbinding ligt.
- **Een scan die de webversie aanvalt zoals een buitenstaander dat zou doen**
  (`make dast`, met OWASP ZAP). Waar de andere controles de broncode lezen,
  bekijkt deze wat er werkelijk over de lijn gaat wanneer de pagina wordt
  geladen. Hij is adviserend: de uitkomst is om te lézen, niet om de bouw te
  breken.

  Richt hem desgewenst op een echt gepubliceerde instantie
  (`make dast DAST_URL=…`); dan meet hij ook de instellingen van de server die
  hem uitserveert, en dat is precies wat geen enkele controle op de broncode kan
  zien.

  Wat er onderdrukt wordt, is bewust minimaal: alleen de drie meldingen die de
  tijdelijke testserver zélf veroorzaakt. Alles waar een echte host
  verantwoordelijk voor is, blijft in beeld — ook al valt het lokaal niet op te
  lossen.

  De eerste keer dat hij liep, vond hij meteen iets: de beveiligingsregels van
  de webversie zeggen niets over waar een formulier naartoe mag worden
  verstuurd. Dat wordt apart hersteld.

- **Een poort die de code op drie beveiligingsfouten controleert** (`make sast`,
  met Semgrep). Hij let op precies drie dingen: of certificaatcontrole ergens
  wordt uitgezet buiten de plek waar dat bij het vastpinnen hoort, of er een
  extern programma wordt gestart buiten de git-laag — dat ontsnapt namelijk aan
  de netwerkbewaking — en of er een niet-veilige toevalsgenerator wordt gebruikt
  voor iets dat een sleutel of wachtwoord heet.

  De regels staan in de repository zelf en worden niet van internet gehaald
  tijdens het controleren: dat houdt de poort werkend zonder verbinding, en
  voorkomt dat de controle zelf gegevens wegstuurt.

  Ze zijn in twee richtingen getoetst — nul meldingen op de bestaande code, en
  wél alarm op een bestand waarin de fouten expres waren gezet. Wat er in
  commentáár over die fouten geschreven staat, wordt terecht genegeerd; dat is
  ook precies waarom hier een echte parser staat en geen zoekopdracht op tekst.

- **Een poort die de repository op weggelekte geheimen doorzoekt**
  (`make check-secrets`). Twee onafhankelijke scanners — gitleaks en trufflehog
  — kijken naar de werkbestanden én naar de volledige geschiedenis, want een
  wachtwoord dat ooit is vastgelegd en later weggehaald, is nog steeds gelekt.
  De poort hoort bij `make check-full` en is verplicht vóór een wijziging wordt
  voorgesteld.

  De eerste ronde vond niets echts: alle treffers zaten in de privacyscanner
  zelf en in zijn tests. Die bestanden bestáán om op geheimen lijkende waarden
  te bevatten — anders kun je niet aantonen dat de scanner ze herkent — en zijn
  daarom uitgezonderd. Wat dat kost, staat in `.gitleaks.toml` opgeschreven in
  plaats van stilzwijgend aangenomen.

  Trufflehog controleert gevonden sleutels standaard door ze naar de
  uitgevende dienst te sturen. Dat staat hier uit: dan zou een controle op
  weglekken zelf gegevens wegsturen.

- **De privacycontrole kijkt nu naar alle 27 EU-lidstaten.** Zes landpakketten —
  Cyprus, Luxemburg, Letland, Malta, IJsland en Liechtenstein — stonden wel als
  vinkje in de instellingen maar keken naar niets; ze zijn eerder deze maand
  uitgezet omdat "niemand keek" niet als "niets gevonden" mag lezen. Ze staan nu
  weer aan, en nu doen ze ook echt iets.

  Vier van de zes nummers dragen een controlegetal: de IJslandse kennitala, de
  Letse personas kods, het Luxemburgse matricule (dat er zelfs twee heeft) en de
  Cypriotische fiscale identificatiecode. Die melden zichzelf, net als het PESEL
  of het rijksregisternummer.

  Voor twee is er geen controlegetal dat wij konden nagaan: het Maltese
  identiteitskaartnummer en de Liechtensteinse PEID. Die melden alleen wanneer
  er ook een bijpassend woord naast staat, en nooit met de hoogste zekerheid.
  Een controlegetal verzinnen dat er geloofwaardig uitziet zou erger zijn dan
  geen: het wijst echte nummers af en laat verzonnen nummers door. Voor Cyprus
  betekent dat ook dat de regel op de fiscale code zit en niet op het
  identiteitskaartnummer, want dat laatste heeft geen enkele controle.
- **Een bestand vertelt nu welke formaatversie het heeft** (`ocideck_format` in
  de front matter). Dat is nodig om oudere bestanden later te kunnen blijven
  openen zonder te raden. Er verandert niets aan wat u ziet, maar drie regels
  liggen vast en staan in `docs/FILE_FORMAT.md`: een bestand zonder die sleutel
  is versie 1 — dat is elk met de hand geschreven Marp-bestand en nooit een
  fout; een ouder bestand opent altijd en wordt bijgewerkt bij het opslaan, niet
  bij het openen; en een bestand van een nieuwere OciDeck wordt niet teruggezet
  naar een oudere versie. Andermans bestand verandert dus niet doordat u ernaar
  kijkt.
- **De interface spreekt nu ook Turks.** OciDeck draaide in 31 talen — alle
  EU-talen plus een paar daarbuiten — maar Turks ontbrak, terwijl het een van de
  grootste talen van Europa is en de taal van een kandidaat-lidstaat. `tr` is nu
  een volwaardige taal en geen half werk: alle 76 sleutelstrings, alle 2.074
  bronstrings en de drie meegeleverde bevindingsjablonen zijn vertaald, en
  Flutter zelf schakelt mee naar zijn Turkse Material-vertaling. *Instellingen →
  Algemeen → Taal* toont Türkçe met de Turkse vlag; de sorteersleutel van de
  talenlijst kent nu ook de ı en de ğ, zodat namen met die letters landen waar
  een lezer ze zoekt. Het vertaalwerk bracht en passant een spatiefout in de
  Nederlandse bron aan het licht (zie *Fixed*).
- **Een achtergrondafbeelding op de tussentitel, net als op de titeldia.** Een
  tussentitel kon alleen een effen kleur dragen terwijl de titeldia allang een
  schermvullend beeld kon hebben — een gat, geen keuze. De tussentitel krijgt nu
  dezelfde bediening (kiezen, "vult hele slide", zoom, bijsnijden, grijze waas,
  tekstkleur) en rendert het beeld in dezelfde drie modi, maar houdt zijn eigen
  gecentreerde uiterlijk. Presentatie, export en Marp-HTML volgen vanzelf; de
  titel-over-beeld-contrastcontrole geldt nu ook hier, met de sectie-eigen
  achtergrondkleur als waas.
- **Een zichtbare zoekknop in de markdown-weergave.** Zoeken kon er al (Ctrl/Cmd+F,
  het menu, de opdrachtenbalk), maar niets in de weergave zelf verried dat — dus
  "in markdown kan ik niet zoeken". Er staat nu een vergrootglas in de kopregel
  dat dezelfde zoekbalk opent.
- **Zoeken in alle decks gaat sneller op desktop.** *Zoeken in alle decks…* las
  tot nu toe elk deck in de repository één voor één over de REST-laag. Staat de
  repository lokaal gekloond (desktop met native git), dan wijst `git grep` nu
  eerst aan wélke decks de term bevatten, en worden alléén die gelezen — K in
  plaats van N. De versneller is forge-onafhankelijk (Gitea, GitHub én GitLab) en
  volledig: hij ziet elke deck. Zonder clone — in de browser, of vóór de eerste
  keer openen — valt het zoeken stil terug op de volledige scan, die overal
  werkt. De treffers zelf, en de eerlijke meldingen over onleesbare of afgekapte
  resultaten, blijven ongewijzigd.
- **Server-side zoeken bij GitLab.** Is er geen lokale clone (op web, of vóór de
  eerste keer openen), dan vraagt het zoeken bij GitLab eerst aan de forge zélf
  welke decks de term bevatten — via de blobs-zoekopdracht — en leest alleen die.
  Dat scheelt opnieuw de N lezingen. Deze weg is geïndexeerd en dus
  **best-effort**: een net gewijzigd deck kan door indexeringsvertraging nog
  ontbreken, en het zoekscherm zegt dat er dan bij. Het vereist wel dat de
  instantie Advanced- of Exact Search aan heeft; zo niet, dan valt het terug op
  de volledige scan.

  De andere twee doen bewust niet mee. Gitea/Forgejo heeft er domweg geen
  REST-endpoint voor. GitHub heeft `/search/code` wél, maar die index is
  woord-/tokengebaseerd: een deelwoord (`dekk` in `dekking`) matcht er niet,
  terwijl de lokale scan juist op deelstrings zoekt. Als voorfilter zou hij dus
  stelselmatig decks overslaan die je wél bedoelde — en een versneller die de
  uitkomst verandert is geen versnelling. Bij beide doet `git grep` (met clone)
  of de volledige scan het werk.
- **Uitleg over de tokenrechten in de instellingen.** Onder het tokenveld van een
  git-verbinding staat nu, afhankelijk van de gekozen forge, welke rechten het
  token nodig heeft: bij Gitea/Forgejo lees- en schrijfrechten op de repository
  (en dat server-side zoeken er niet is), bij GitHub de `repo`-scope, en bij
  GitLab `read_repository`/`write_repository`/`read_api` met de Advanced/Exact
  Search-voorwaarde. Proactief, niet pas nadat een verbindingstest is mislukt.

- **Een ontdekkingendia: wat we niet wisten te hebben.** Het aanvalsoppervlak
  *telt* wat nieuw is; deze dia *noemt* het. De handvol objecten die de scan
  vond en die in geen enkele inventaris stonden — schaduw-IT, een vergeten
  acceptatieomgeving, een certificaat van een team dat allang gereorganiseerd is.

  Per ontdekking: wat het is, wat voor soort object, hoeveel dagen het
  onopgemerkt bereikbaar was, en wie het nu bezit. Dat derde veld is waarom de
  dia bestaat. "We vonden twaalf nieuwe dingen" is een scanresultaat en leest als
  huishouding; "één stond veertien maanden open" is de zin die blijft hangen.
  Dus begint de dia met de langste blootstelling en niet met het aantal, en zegt
  hij die boven de zestig dagen in maanden — 420 zegt niemand iets, veertien
  maanden meteen.

  De balken staan op één gedeelde schaal, gezet door de langste. Laat de dagen
  leeg als u het niet weet: een eerste scan heeft geen historie om tegen te
  meten, en dan zegt de dia "onbekend" in plaats van een balk van nul te tekenen
  die zou beweren dat u er meteen bij was. Een lege eigenaar leest als "geen
  eigenaar" en valt rood op — blootstelling en eigenaarschap zijn twee feiten en
  krijgen twee eigen tekens, zodat ze allebei een zwart-witafdruk overleven.

  Zes ontdekkingen is het maximum. Wie er meer noemt maakt een bijlage.

  Waarom dit geen tabel is: een tabel kan dezelfde vier kolommen dragen, maar kan
  niet zeggen wélke regel het probleem is. De kop en de gedeelde schaal worden
  afgeleid en nooit opgeslagen, dus ze kunnen de regels eronder niet tegenspreken.
  Opslag blijft een gewone Markdown-tabel, dus wat uw scan produceert kan de dia
  rechtstreeks schrijven.

- **Een nieuw grafiektype: norm en prestatie.** Per rij een meetbalk voor de
  werkelijke waarde, grijze achtergrondbanden voor de schaal waartegen u
  oordeelt, en een streepje waar de afgesproken norm ligt. Bedoeld voor het
  SLA-verhaal: "kritiek verhelpen binnen veertien dagen — gehaald in 38% van de
  gevallen".

  Het punt is dat de norm als *norm* getekend wordt, een streepje op de meetlat,
  en niet als tweede staaf ernaast. Dat is het verschil tussen twee getallen
  naast elkaar en de vraag of het gehaald is.

  Dit is het enige grafiektype waarvoor het datamodel moest meegroeien: een
  streefwaarde hoort bij een x-positie en niet bij een reeks, dus hij kan niet
  in een `ChartSeries` wonen. Vandaar de twee nieuwe velden `targets` en
  `bands`, die alleen voor dit type worden weggeschreven — anders blijft er een
  streefwaarde in een taartdiagram hangen na een typewissel.

  Zonder streefwaarden zakt de grafiek netjes terug tot een gewone horizontale
  staaf, dus een half ingevulde grafiek toont nog steeds iets zinnigs.


### Fixed
- **Een vraagdia zonder juist antwoord hield de presentatie voorgoed vast.** De
  quiz blokkeert doorbladeren tot er juist geantwoord is, en de maat daarvoor was
  of er ópties stonden. Een vraag met twee opties waarvan er géén als juist is
  aangemerkt levert echter een lege verzameling juiste antwoorden op: elk
  antwoord telt dan als fout, en in de standaard retry-stand vergrendelt een fout
  niet. Zo'n dia was per definitie niet te halen en alleen met afsluiten te
  verlaten. De maat is nu of er een juist antwoord te gévén valt — wat de
  tekenroutines zelf al "niet presenteerbaar" noemden.
- **Een live bewerkte tabel kwam verouderd terug in de editor — en werd stil
  teruggedraaid.** Wat je tijdens het presenteren in een tabelcel typte (of
  afvinkte op een checklist) belandde wél in het deck, maar de editorvelden
  cachen hun tekst in eigen controllers en lezen pas opnieuw bij een
  revisiesprong. Na afloop stond daar dus nog de tekst van vóór de presentatie,
  en de eerstvolgende toetsaanslag in zo'n veld schreef die hele oude inhoud
  terug — je live bewerking was weg zonder dat iets dat meldde. Na het sluiten
  van de presentatie verversen de velden nu, mits er live iets gewijzigd is.
- **Het beamervenster slikte je toetsen op.** Bij dubbelschermpresenteren is de
  beamer een eigen venster met een eigen engine. Dat venster negeerde álle
  toetsen behalve Cmd/Ctrl+W en stuurde niets door — dus zodra het de
  toetsenbordfocus had, en één klik op het beamerbeeld is daarvoor genoeg, deed
  geen enkele sneltoets nog iets. Wie op dat moment in een live bewerkte tabel
  stond te typen kwam er met Escape niet meer uit. Elke onafgehandelde toets
  reist nu naar de presenter en wordt daar afgehandeld alsof hij op de laptop was
  ingetikt; de modifiers gaan mee, want de overkant kan ze niet uitlezen.
- **Een kale N opent nu de eigen notities.** De legenda beloofde Ctrl+N, maar wie
  tijdens het presenteren gewoon N tikte kreeg niets terwijl elke andere
  sneltoets daar juist een kale letter is. N opent het notitiepaneel; Ctrl+N
  blijft werken en blijft binnen het paneel de enige toggle, want daar typt een
  kale N een letter in je notitie.
- **Zinnen opknippen bewaart de volzin in de sprekersnotities.** Wie een
  meerzinnige bullet in losse bullets liet knippen hield de woorden maar verloor
  het verhaal: op de slide staan daarna losse zinnen, terwijl het verband er juist
  in de volzin zat. Die volzin gaat nu mee naar de notities, met dezelfde context
  (tussenkop, inspring-niveau) als *Uitleg naar notities* al meegaf. Daarnaast
  biedt het kwaliteitspaneel de actie alleen nog aan zolang de slide er niet te
  vol van wordt: opknippen levert méér bullets op, dus op een slide die de
  leesbaarheidsdrempel al raakt maakte deze fix het probleem groter. Daar blijft
  alleen *Splits slide* staan — één scenario per melding.
- **Het percentage plakt niet meer tegen het volgende woord.** De strengste
  melding over te veel tekst op een slide las "het lettertype wordt sterk
  verkleind (55%van de ontwerpgrootte)" — de zin wordt uit drie stukken geplakt
  en op die naad ontbrak een spatie. De variant erboven deed het al goed. Omdat
  het Nederlandse fragment tegelijk de opzoeksleutel is, was de fout door alle
  talen heen gekopieerd; hij is nu in alle tweeëndertig hersteld. Een test loopt
  voortaan elke melding in elke taal langs en struikelt over een percentage dat
  tegen een letter aan komt te staan.
- **Een macOS-build die weer leesbaar is: tienduizend linkerwaarschuwingen weg.**
  Elke `flutter build macos` eindigde in een muur van ruim 10.000 regels
  `ld: warning: no platform load command found in '…libopencv.a[x86_64][…]'`,
  afgesloten met `ld: warning: ignoring duplicate libraries: '-lc++'`. Het komt
  uit de ingekochte `DartCvMacOS`-pod: die levert OpenCV als voorgebouwd,
  universeel archief van een kwart gigabyte, waarvan de x86_64-helft grotendeels
  bestaat uit Intel IPP-objecten zonder platform-load-command — en de pod koppelt
  libc++ een tweede keer terwijl de toolchain dat al doet. Geen van beide is code
  die wij schrijven of kunnen herstellen, en samen overstemden ze alles wat er
  wél toe deed. De `post_install`-haak in `macos/Podfile` dempt de koppelaar nu
  op precies dat ene doel (`-Wl,-w`), plus de compilerwaarschuwingen uit de
  meegeleverde `dartcv`-bronnen — dezelfde behandeling die
  `video_player_avfoundation` daar al kreeg. Elk ander doel, `Runner` voorop,
  blijft zijn waarschuwingen onverkort tonen. Een release-build gaat daarmee van
  10.455 regels uitvoer naar 40.
- **Een badge die iets meldt, en een popover die het ook laat zien.** Op een dia
  met alléén een gezichtstreffer of een titel-over-beeld-contrastprobleem kleurde
  de badge wel, maar zei de popover "geen meldingen meer op deze slide" en toonde
  het overzicht een probleem dat bij het aanklikken verdween. De badge en de
  popover lezen nu dezelfde ruwe uitslagen als het overzicht — voor gezichten én
  voor contrast — zodat ze elkaar niet meer tegenspreken. Een geaccepteerde
  beeldtreffer wordt daarbij grijs in plaats van spoorloos te verdwijnen.
- **"Deze regel nooit meer melden" doet nu ook iets bij gezichten.** De knop
  schreef `image.face` keurig weg bij de uitgezette regels, maar de beeldcontrole
  las die lijst nooit — dus er gebeurde niets. Nu eert ze de uitgezette regels,
  omkeerbaar via Instellingen → Beveiliging.
- **Web/io-verschillen die stil de verkeerde kant op vielen, rechtgezet.** Een
  gerichte vergelijking van de platformvarianten leverde vijf punten op:
  - De gezichtencontrole beloofde op web dat "elke afbeelding lokaal wordt
    doorgerekend" terwijl de webvariant een no-op is. De schakelaar staat op web
    nu uit en uitgeschakeld, met de reden erbij.
  - Online CVE-opzoeken is desktop-only; de documentatie beweerde ten onrechte
    dat het op web bleef werken (HOSTING.md/USER_GUIDE.md rechtgezet).
  - Een offline git-opslag van een te groot of niet-tekstueel deck gooide op web
    een uitzondering die niemand ving: geen melding, niets in de wachtrij. Die
    wordt nu een nette "Opslaan mislukt: … gebruik de desktopversie".
  - De byte-cap op git-antwoorden werd op web pas ná het inlezen van het hele
    lichaam gecontroleerd; nu eerst een Content-Length-poort en een lopende cap,
    net als op desktop (met een eerlijke kanttekening over browserbuffering in
    SECURITY_DESIGN).
  - Een beschadigde web-werkkopie werd als "deck verworpen" gelezen en liet de
    wachtende commit stil vallen als "niets te synchroniseren"; corruptie wordt
    nu apart gemeld en als echte fout behandeld.
- **De webversie ruimt afbeeldingen op die nergens meer worden gebruikt.** Elke
  gekozen of geplakte afbeelding, video en audio leefde in het geheugen en bleef
  daar staan — ook nadat de dia was verwijderd of vervangen — zodat het geheugen
  van een tabblad onbegrensd groeide. Na het verwijderen van dia's en na het
  opslaan veegt de app nu de media weg die geen enkel open tabblad, geen
  ongedaan-/opnieuw-stap en het diaklembord meer aanhaalt. De sweep is bewust
  breed: alles wat nog terug kan komen, blijft. Op schijf (desktop) speelt dit
  niet.
- **Web-opslag waarschuwt voordat een kaal `.md` je afbeeldingen laat vallen.**
  Op web is opslaan een `.md`-download; afbeeldingen, video en audio die je in
  het tabblad koos, leven alleen in het geheugen en reizen niet mee in een los
  tekstbestand — bij heropenen waren ze weg, terwijl de opslag succes meldde. Er
  verschijnt nu een waarschuwing met de raad om als `.ocideck`-pakket te
  exporteren; de keuze blijft aan de gebruiker (geen blokkade). Op schijf speelt
  dit niet — daar kopieert de opslag de media naar een `images/`-map.
- **Geredigeerde media laat een zichtbaar spoor na in de HTML-export.** De
  privacyprojectie haalt beeld, video en audio van een slide af; de
  PDF/PPTX-export tekende daar een zwart vlak, maar de HTML-export liet alleen
  een lege plek — terwijl de tekst ernaast wél zwarte blokken toonde. De
  ontvanger ziet nu ook in de HTML dát er iets is weggehaald.
- **Wat het apparaat verlaat, gaat eerst door de privacyprojectie.** De
  AI-context die de vindingeneditor meestuurde was de ruwe brontekst; de
  projectie die bij elke andere uitgang vooropstaat, stond hier niet. Nu wordt
  de context eerst voor externe verwerking geprojecteerd, met de identifiers
  (CVSS/CWE/CVE) onaangeroerd.
- **Getallen die in een dossier belanden kloppen weer.** "Onbereikbaar" telde
  mee als getoetst (het dossier meldde "3/3" terwijl er één van de drie was
  getest); hetzelfde scope-object op twee matrices woog dubbel en de winnende
  status hing van de diavolgorde af; hernummeren hing detaildia's aan de
  verkeerde bevinding; en 99,5% werd als 100% getoond. Ook telde de
  MIAUW-analyse detaildia's als losse bevindingen.
- **Alleen kijken in de visuele notitiestand sloopt geen tekst meer.** De
  heen-en-terugweg door de rijke-tekstlaag is niet verliesvrij (een tabel komt
  er als losse woorden uit, `\*` verliest zijn backslash); de stand schreef die
  uitkomst onvoorwaardelijk terug. Nu alleen na een echte wijziging.
- **Paginanotities raken niet meer kwijt.** Een rijke-tekstdia over meerdere
  pagina's leverde meerdere notities met dezelfde dia-index; de decoder claimde
  op de dia alleen en stootte de tweede af naar een andere dia of naar niets. De
  claim staat nu op (dia, pagina).
- **Twee poorten sluiten weer voor het geval waarvoor ze bedoeld zijn.** De
  harde exportblokkade bij kwaliteitsfouten ging stilzwijgend mee uit met de
  aparte bevestigingsvraag; en "Kopieer als afbeelding" toetste alleen de
  markering van het dek, waardoor een TLP:RED-dia in een TLP:GREEN-dek naar het
  klembord kon. Nu geldt de strengste van dek en dia.
- **Tijdlijn- en akkoorddia's komen niet meer als ruwe tekst uit de
  HTML-export.** Een tijdlijn toonde "2024-01 :: Start" met de interne scheiding
  erin; de akkoordpagina was een kop met wit eronder terwijl de verklaring op
  dekniveau klaarstond. Beide worden nu volwaardig gerenderd.
- **Een merge blijft niet half toegepast staan.** `NativeGitMirror.mergeRemote`
  ving alleen git-fouten rond het blok dat óók schrijft; een mislukte schrijf
  liet de merge half toegepast met een open MERGE_HEAD achter. Elke fout leidt
  nu tot afbreken en terugmelden.
- **Een dode CWE-check en een dode F-NN-verwijzing opgeruimd.**
  `EisCheck.everyFindingHasCwe` was een wees zonder EIS in de catalogus en liep
  nooit; en een wees-detaildia (kop verwijderd) hield een titelprefix die naar
  een verdwenen bevinding wees.
- **Een geredigeerde export op web laat zijn redactiemanifest niet meer vallen.**
  Op de desktop landen de commitments en de verificatiesleutels naast de export;
  op web werd alleen het rapport gedownload en verdween het manifest, waarna geen
  enkele redactie meer na te trekken was. De browser-download levert nu dezelfde
  bestanden mee.

### Added
- **Eén bron, een managementversie en een techniekversie.** Markeer een slide als
  **verdieping** en hij gaat mee in de volledige export maar valt weg in de
  beknopte. De exportdialoog vraagt voortaan *met verdieping* of *beknopt*, en de
  keuze landt in de bestandsnaam (`…-beknopt.pdf`) — om dezelfde reden als bij
  het redactieprofiel: de verkeerde versie versturen moet je kunnen zíen, niet
  hoeven onthouden.

  Dit is nadrukkelijk een dérde as, naast classificatie en redactie. TLP vraagt
  wie het mag zien, redactie welke gegevens eruit mogen, verdieping hoeveel
  detail deze lezer wil. Een slide kan prima openbaar zijn en tóch meer dan
  waarvoor een managementpubliek kwam. Zou verdieping in TLP zijn gevouwen, dan
  moest u uw bijlage als vertrouwelijk classificeren om hem uit de korte versie
  te houden — een onwaarheid waar later iemand op afgaat.

  De keuze verschijnt alleen als er iets te kiezen valt: het deck moet zowel
  verdiepingsslides als gewone hebben. Presenteren blijft ongemoeid en toont
  altijd alles; halverwege een voordracht ontdekken dat er slides ontbreken is
  geen verbetering.

  Onderwater is het samengestelde oordeel "bereikt deze slide het publiek" nu één
  functie. Het stond tweemaal uitgeschreven — in de slidelijst en in de
  indexvertaling van de startselectie — en dat is precies hoe een vierde poort er
  straks op één van beide plekken niet in belandt.

### Changed
- **De scorecard is een dashboard geworden, en de invoer ervan een strak
  formulier.** De slide zette de cijfers in een dunne strook bovenaan, ongeacht
  hoeveel het er waren: één cijfer kreeg net zoveel beeld als vijf, en dat is
  precies verkeerd om. Voortaan bepaalt het *aantal* de indeling — één cijfer
  vult de slide als één groot getal, twee of drie staan naast elkaar, vier vormen
  een blok van 2×2 en vijf staan drie boven twee. De lettergrootte volgt uit de
  kaart die een cijfer daadwerkelijk krijgt en niet uit een vaste breuk van de
  slide, dus de veelvoorkomende gevallen zijn niet langer klein gemaakt voor het
  drukste geval.

  Elk cijfer staat nu op een eigen kaart, met de accentkleur van het stijlprofiel
  als tint en als streep langs de bovenrand, de verandering als gekleurde pil, en
  eronder wat het cijfer verving ("was 375") — een gegeven dat wél werd
  opgeslagen maar nooit werd getoond. Op een volle vijf-cijferslide vervalt die
  regel ten gunste van een groter getal; de pil erboven zegt dan al wat er
  veranderde. Groen en rood blijven vastliggen: die betekenen iets in plaats van
  dat ze versieren.

  In de editor is een cijfer teruggebracht tot één compacte kaart van twee
  regels. De twee toelichtingen die onder élk cijfer herhaald werden staan nu één
  keer onder de kop en op het richtingveld zelf — bij vijf cijfers was die
  herhaling het grootste deel van het paneel. De kaartkop toont de verandering
  als gekleurde chip zoals de slide hem tekent, zodat het effect van de
  richtingkeuze zichtbaar is tijdens het typen. Sorteren gaat met een sleepgreep,
  net als bij opsommingen, tijdlijnen, slides en opslaglocaties; de twee
  pijlknopjes per cijfer zijn daarmee verdwenen.

- **Het sjabloon *Rapportage* begint nu met de nieuwe rapportagetypes.** Het
  KPI-dashboard was een cockpit met wijzerplaten; dat is nu een **scorecard**,
  omdat een rapportage die elke maand terugkomt hoort te leiden met wat er
  veranderde en niet met wat het getal toevallig is. De vier voorbeeldcijfers
  tonen bewust alle uitkomsten — vooruit, achteruit en ongewijzigd — zodat
  meteen zichtbaar is wat de richtingkeuze per cijfer doet.

  De actielijst was een checklist met "… (eigenaar, datum)" tussen haakjes in de
  tekst. Dat is nu een gewone **tabel** met de kolommen Actie, Eigenaar,
  Deadline en Status — dezelfde kolommen die de actielijst-preset van de
  tabeleditor neerzet, zodat een deck dat uit het sjabloon komt en een deck dat
  uit de preset komt hetzelfde lezen.

  De deadlines blijven leeg: een sjabloon met ingebakken datums veroudert, en
  een lege deadline is bovendien meestal precies wat er in de vergadering moet
  worden afgesproken.

### Added
- **De tabel markeert verlopen datums, en begint waar u wilt beginnen.** Twee
  eigenschappen die het opgeheven slidetype 'Acties en besluiten' had, maar nu
  van het tabeltype zelf zijn — dus mét plakken uit een spreadsheet, kolommen
  bijzetten, en bewerken tijdens het presenteren.

  Zet **Verlopen datums markeren** aan en een cel met een datum van vóór
  vandaag kleurt rood. OciDeck kijkt daarvoor naar de dag waarop u presenteert,
  niet naar een opgeslagen vlag: een deck dat drie maanden later terugkomt,
  markeert zijn eigen verlopen deadlines in plaats van te blijven beweren dat
  alles op schema ligt. Er is dan ook geen status "te laat" die u zelf zet —
  wat u typt bevriest op de dag dat u het typte.

  De markering staat standaard uit. Een tabel met historische datums zou anders
  volledig rood kleuren, en een waarschuwing die overal staat waarschuwt
  nergens voor.

  Alleen jjjj-mm-dd telt als datum. `05-08-2026` is twee verschillende dagen
  afhankelijk van wie het typte, en een deadline is een slechte plek om te
  gokken; een cel die niet strikt ISO is, wordt simpelweg niet gemarkeerd.
  Bestaande-maar-onmogelijke datums vallen ook af: 31 februari rolt in Dart
  stilzwijgend door naar maart, en die stilte is hier niet gewenst.

  Zolang de tabel nog leeg is, biedt de editor daarnaast een **preset** aan die
  in één klik de kolommen van een actielijst neerzet — Actie, Eigenaar,
  Deadline, Status — en de datummarkering aanzet. De knop verdwijnt zodra er
  iets in de tabel staat, zodat hij nooit overschrijft wat u al had getypt.


- **De laatste vier geheimen.** Azure-sleutels en SAS-tokens, wachtwoordhashes
  (bcrypt, argon2, sha512-crypt, NTLM-dumps), TOTP-seeds uit een `otpauth://`-URI,
  en een vangnet voor hoog-entropische strings. Dat laatste is de eerste
  geheimregel met een contextpoort: hij herkent geen prefix maar willekeur, en
  willekeur staat overal in een technisch deck. Commit-hashes, UUID's en
  checksums zijn expliciet uitgesloten, en de melding blijft `mogelijk`.
- **Zes Nederlandse nummers naast het BSN.** Het oude btw-nummer van een
  eenmanszaak, het V-nummer, het A-nummer, het BIG-nummer, de AGB-code en het
  proces-verbaalnummer. Alleen het btw-nummer mag contextloos vuren: `NL` + negen
  cijfers + `B` + twee cijfers is een vorm die nergens anders voorkomt, en halen
  die negen cijfers de elfproef, dan *zijn* ze het BSN van de ondernemer. De
  andere vijf zijn kale cijferreeksen en eisen een contextwoord, want
  `Ordernummer 20250131` heeft de vorm van een AGB-code. Het A-nummer krijgt
  bewust geen checksum: die wordt vaak geclaimd maar nergens publiek
  gedocumenteerd, en gokken zou echte A-nummers afwijzen.
- **Een strenge stand voor de privacycontrole.** `privacyStrictSeverity` onder
  *Instellingen → Beveiliging* maakt van elke zekere bevinding een fout in plaats
  van een waarschuwing, waarmee de export erop kan blokkeren. Standaard uit,
  omdat aanzetten verandert wat een bestaande instelling betekent. Alleen zekere
  bevindingen schuiven mee.
- **Een nieuw slidetype: het aanvalsoppervlak.** Tot acht soorten extern
  bereikbare objecten — webapplicaties, mailservers, VPN-endpoints, API's — met
  per soort hoeveel er zijn, hoeveel er werk kosten, hoeveel nieuw zijn en
  hoeveel er geen eigenaar hebben.

  Een regel is een *soort*, geen los object. Dat is de hele keuze: een scan
  levert honderden hosts en een managementslide draagt er acht. Wie ze allemaal
  opsomt, maakt een bijlage. De vraag die deze slide beantwoordt is hoe groot
  het oppervlak is, hoeveel ervan werk kost, en wat niemand bezit.

  Die laatste kolom is de bestuurlijke. Een object zonder eigenaar is geen
  technisch probleem maar een governance-probleem: er is niemand die het
  oplost, en vaak wist niemand dat het bestond.

  Elke soort krijgt een balk met het werk-aandeel ingevuld. Alle balken delen
  één schaal, gezet door de grootste soort op de slide, zodat een categorie van
  drie niet even breed tekent als een van driehonderd. De totaalregel onderaan
  wordt uit de rijen opgeteld en nooit ingetypt, zodat hij ze niet kan
  tegenspreken.

  OciDeck scant zelf niets; de cijfers komen uit uw eigen tool. De editor telt
  mee terwijl u typt en waarschuwt als een deelgetal groter is dan het totaal
  waar het bij hoort. Corrigeren doet hij het niet: dat zou de fout verbergen in
  wat het getal produceerde, en juist zulke fouten hoort een rapportage te laten
  zien.

  Het type hoort bij de uitbreiding **Informatieveiligheid** en wordt alleen
  aangeboden als die aan staat — een aanvalsoppervlak is MIAUW-materiaal, geen
  algemeen presentatiemiddel. Een deck dat er al een draagt, toont hem altijd.
- **Een nieuw slidetype: de scorecard.** Tot vijf kerncijfers, elk met het cijfer
  van de vorige rapportage ernaast. Bedoeld voor een rapportage die elke maand of
  elk kwartaal terugkomt: het getal zelf is context, de verandering is het
  nieuws.

  Het type bewaart de vórige waarde, niet het verschil. Dan klopt het verschil
  altijd met de twee getallen die er staan, kan de slide ook tonen wat het was,
  en is er niets dat met de hand is ingetikt en door niets wordt gecontroleerd.
  Is er nog geen eerdere meting, dan blijft die kolom leeg en toont de slide
  géén verandering — nadrukkelijk geen "+0", want dat zou beweren dat het cijfer
  gelijk bleef terwijl het nooit eerder is gemeten.

  Per cijfer geef je de richting op: *lager is beter*, *hoger is beter* of
  *neutraal*. Die keuze bepaalt alleen de kléúr van een verandering; de pijl
  volgt altijd de cijfers. OciDeck kan namelijk niet weten of stijgen goed
  nieuws is — meer assets in beeld is vooruitgang als je aan het inventariseren
  bent en een probleem als je aan het opruimen bent. Een daling blijft dus een
  pijl omlaag, of hij nu groen of rood kleurt.

  De verandering staat er ook met teken bij (`+37`, `-24`), zodat de richting een
  zwart-witafdruk overleeft. De scorecard volgt verder het stijlprofiel van het
  deck; groen en rood zijn de bewuste uitzondering, omdat die betekenis dragen in
  plaats van opmaak — dezelfde redenering als waarom de heatmap zijn eigen
  kleurramp houdt.

  De cijfers staan als gewone Markdown-tabel in het bestand, dus een script dat
  je cijfers al produceert kan de tabel rechtstreeks schrijven. Het type staat
  bij de algemene slidetypes en niet achter de informatieveiligheidsmodule: een
  paar kerncijfers met hun vorige stand is net zo bruikbaar voor een
  projectrapportage of een stuurgroepupdate.
- **De privacycontrole kijkt nu ook buiten Europa.** Naast de EU, de EER,
  Zwitserland en het VK kent OciDeck nu de persoonsnummers van de Verenigde
  Staten, Canada, Australië, India, Brazilië, Zuid-Afrika, Curaçao en Aruba. Ze
  staan allemaal standaard aan.

  Dat laatste is een keuze en geen gemak. Een landpakket aanzetten kost bijna
  geen ruis, want elke regel draagt óf een controlecijfer óf de eis dat er een
  woord als "SSN" of "sedula" bij staat — een Braziliaans CPF heeft zelfs twee
  onafhankelijke controles. Maar de reden dat ze áán moeten staan is een andere:
  bescherming hoort niet af te hangen van de vraag of je wist dat er een vinkje
  was. Wie een deck met Amerikaanse of Zuid-Afrikaanse persoonsgegevens opent,
  heeft de controle het hardst nodig op het moment dat hij er het minst aan
  denkt. Per land uitzetten kan nog steeds, onder *Instellingen → Beveiliging*.

- **De maatstaf blijft de AVG, ook bij landen die het zelf anders regelen.** Het
  Amerikaanse recht werkt met een opsomming van wat als persoonsgegeven telt; de
  AVG met een open norm. Dat verschil verandert wat er gemeld wordt:

  Een Medicare-nummer of het nummer van een zorgverlener is daar routineuze
  administratie. Hier is het een gegeven over gezondheid, met het gewicht dat
  daarbij hoort. "Last 4 of SSN" geldt in Amerikaanse praktijk als voldoende
  afgeschermd — maar vier cijfers naast een naam of een geboortedatum wijzen nog
  altijd één persoon aan, dus `XXX-XX-1234` wordt gemeld. En een Amerikaans
  ITIN identificeert iemand die belasting betaalt zonder recht op een
  SSN, wat raakt aan verblijfsstatus.

  Het werkt ook de andere kant op. Een Indiase PAN codeert in zijn vierde letter
  wat voor houder het is, en maar één waarde daarvan betekent een natuurlijk
  persoon. Het PAN van een bedrijf wordt dus helemaal niet gemeld. Gelijk hebben
  over wat een persoonsgegeven is, snijdt twee kanten op.

- **Voor Curaçao en Aruba is er geen controlecijfer, en dat staat er ook zo bij.**
  De sedula en het Arubaanse persoonsnummer hebben geen openbaar gedocumenteerde
  controle. Ze worden daarom alleen gemeld als er een woord als "sedula" of
  "persoonsnummer" bij staat, en nooit met de hoogste zekerheid. Liever een
  voorzichtige regel die zwijgt zonder context dan een blinde vlek binnen het
  eigen Koninkrijk.
- **Negen Europese persoonsnummers erbij.** Oostenrijk, Zwitserland, Tsjechië en
  Slowakije, Denemarken, Griekenland, Hongarije, Ierland, Noorwegen en Slovenië.
  Op één na dragen ze allemaal hun eigen controlecijfer, dus ze herkennen zichzelf
  en kosten nauwelijks valse meldingen.

  Twee uitzonderingen, en allebei bewust. Het Deense CPR-nummer heeft sinds 2007
  géén controlecijfer meer — daarop controleren zou echte nummers afwijzen — dus
  dat wordt alleen gemeld als er ook een woord als "CPR" bij staat. Hetzelfde
  geldt voor het Hongaarse TAJ-nummer: dat is negen cijfers met een controle die
  één op de tien willekeurige getallen doorlaat, en zonder die eis ging het af op
  gewone klantnummers.

- **"Maar het is toch geanonimiseerd" wordt nu tegengesproken.** Staan
  geboortedatum, postcode en geslacht samen op één slide, dan wijzen die drie
  meestal één persoon aan — ook zonder naam erbij. Latanya Sweeney liet in 1997
  zien dat het voor 87% van de Amerikaanse bevolking opgaat.

  Juist omdat geen van de drie op zichzelf een identificatienummer is,
  overleven ze het schrappen van namen, en heet zo'n tabel daarna
  "geanonimiseerd". OciDeck merkt nu op wanneer die drie samenvallen, of ze nu
  in de tekst staan of als kolommen in een tabel.

  Twee van de drie levert niets op. Anders zou elke adreslijst een waarschuwing
  geven.

- **Creditcardnummers worden herkend.** Een kaartnummer draagt twee
  onafhankelijke bewijzen in zich: een controlecijfer én een nummerreeks die
  zegt van welke kaartmaatschappij het is. Allebei moeten kloppen, want één op
  de tien willekeurige cijferreeksen haalt dat controlecijfer — zonder de tweede
  eis zou elk ordernummer van zestien cijfers een creditcard zijn.

  De beveiligingscode (CVV) wordt alleen gemeld als er ook een kaartnummer bij
  staat. Los is "123" niets; samen zijn het een bruikbare betaalinstructie. De
  officiële testkaartnummers uit betaalhandleidingen blijven buiten schot.

- **Gegevens in de sprekersnotities worden apart gemeld.** Notities zijn
  onzichtbaar op de slide maar gaan wél mee in een PowerPoint-export. Wie zijn
  presentatie nakijkt op wat er te zien is, kijkt daar dus precies langsheen.
  Staat er iets in dat een waarschuwing waard is, dan zegt OciDeck dat nu met
  zoveel woorden.

- **"Betrokkene is katholiek opgevoed" wordt nu herkend.** De meertalige
  begrippenlijst levert zelfstandige naamwoorden — *katholicisme*, *socialisme*,
  *jodendom* — en zo schrijft niemand over een persoon. Voor het Nederlands zijn
  de persoonsvormen er nu bij: *katholiek*, *moslim*, *gereformeerd*, *joods*,
  *communist*, *liberaal*, en zo'n veertig meer.

  De grens die daarbij is aangehouden: beschrijft een woord een **persoon** of
  een **instelling**? *Christen* gaat mee, *christelijk* niet — dat gaat in
  Nederlands zakelijk taalgebruik meestal over een school, een omroep of een
  feestdag. Om dezelfde reden ontbreken *kerkelijk* en *praktiserend*.

- **De taalmelding in het kwaliteitspaneel is preciezer geworden.** Hij keek per
  taal, en zei "gedekt" zodra er íéts voor die taal was. Daardoor kregen vijftien
  talen — Zweeds, Deens, Fins, Grieks, Hongaars en meer — een groene melding op
  grond van alleen religie- en ideologietermen, terwijl er voor die talen geen
  enkele ziektenaam is. Een Zweeds dossier met een diagnose erin zag er dus
  gecontroleerd uit zonder dat te zijn.

  De melding zegt nu wat er precies ontbreekt, en gaat uit van de ziektenamen —
  veruit de grootste categorie.

- **Religies, ideologieën en vakbondstermen worden nu in 27 talen herkend.** Voor
  bijzondere persoonsgegevens over geloof, politieke overtuiging,
  vakbondslidmaatschap en etnische afkomst kende OciDeck een handvol
  Nederlandse, Engelse, Duitse, Franse en Spaanse woorden. Daar komen nu de
  begrippen zelf bij, uit de meertalige EU-thesaurus EuroVoc: `katholicisme`,
  `islam`, `jodendom`, `communisme`, `fascisme`, `sociaal-democratie` — in alle
  EU-talen plus een paar daarbuiten.

  Net als bij de aandoeningsnamen onderbreekt zo'n woord op zichzelf niets. "Onze
  cursus behandelt islam en jodendom" is lesmateriaal; "Dhr. Bakker:
  protestantisme" is een persoonsgegeven, en alleen het tweede geeft een
  waarschuwing.

  Vijftien begrippen die *over* het onderwerp gaan in plaats van over iemand —
  kerk, theologie, heilige boeken, concilie — zijn er bewust uit gelaten. Die
  uitsluiting werkt op het begrip en niet op het Nederlandse woord, dus ze geldt
  meteen in alle 27 talen.

- **De privacycontrole kent nu 62.490 aandoeningsnamen, in negen talen.** Tot nu
  toe herkende OciDeck gezondheidsgegevens aan een handvol signaalwoorden —
  "diagnose", "medicatie", "ziekteverzuim". Die wijzen ergens naar; ze zíjn het
  gegeven niet. Nu worden ook de aandoeningen zelf herkend, uit de
  nomenclatuur van Orphanet (CC BY 4.0): van "taaislijmziekte" tot "ziekte van
  Alexander", in het Nederlands, Engels, Duits, Frans, Spaans, Italiaans, Pools,
  Portugees en Tsjechisch.

  Dat maakt vooral de **redactie** beter. Een signaalwoord weglakken laat de
  mededeling staan; een aandoeningsnaam weglakken haalt het gegeven zelf weg.
  En een aandoeningsnaam blijft op zichzelf een informatieve melding — "onze
  afdeling behandelt cystinose" is een dienstbeschrijving, geen dossier. Pas met
  een persoon erbij wordt het een waarschuwing.

  Voor negen talen is dit meteen het verschil tussen "een paar signaalwoorden"
  en een bruikbaar lexicon, en de taaldekkingsmelding in het kwaliteitspaneel
  beweegt mee.

- **Vóór een release-build zie je nu of er upstream iets nieuwers is.** OciDeck
  bundelt referentiedata — WSTG, MASTG, MASWE, CWE, MIAUW, CVSS — en die
  wandelt mee in elk artefact dat je uitbrengt. Er was al een controle die
  meldt wanneer een bron verder is, maar die zat in de merge-poort: hij
  blokkeert, en hij draait niet op het moment dat je een release maakt.

  `make catalogs-outdated` stelt dezelfde vraag op het moment dat hij ertoe
  doet, en breekt niets. Hij draait vanzelf als eerste stap van
  `make build-release`, vóór de builds, zodat de melding niet onder twintig
  minuten compileruitvoer verdwijnt. Een nieuwe upstreamversie is namelijk geen
  defect in wat je bouwt — het is een afweging, en die is aan de mens die de
  release maakt. Een controle die de release zou afbreken, wordt binnen twee
  releases weggevlagd, en dan ben je precies de zichtbaarheid kwijt die je
  wilde.

  Geen netwerk breekt de release evenmin af, maar het zegt wél dát er niet
  gekeken is. Stilte mag hier niet als goedkeuring lezen.

- **Werk dat op verbinding wacht staat nu in de statusbalk.** Sla je op terwijl
  de forge onbereikbaar is, dan blijft het op deze computer wachten tot er weer
  verbinding is. Dat is precies wat je wil — maar je zag het alleen wanneer je
  er zelf naar vroeg, en dan stond het er meestal al even.

  Er staat nu een amberkleurige melding in de balk zolang er iets wacht, met
  het aantal erbij, over al je git-verbindingen samen. Is er niets, dan zegt de
  balk er niets over: een balk die altijd iets meldt, wordt niet meer gelezen.

  De melding is bewust niet aanklikbaar. Legen doe je met *Wachtrij legen* in
  het `…`-menu, dat kan vragen en melden; een badge die bij een tik een
  netwerkactie start, doet meer dan hij belooft.
- **De branch van een git-repository is nu in te vullen.** Er was geen veld
  voor, dus stond hij altijd op `main`. Een repo die op `master` staat was
  daardoor via de instellingen onbruikbaar, en bewust op een andere branch
  werken kon niet.

  Het veld mag leeg blijven: dan neemt de verbindingstest over wat de forge
  als standaard opgeeft, zoals hij al deed. Vul je zelf iets in dat afwijkt,
  dan zégt de test dat wel — *"let op: de standaardbranch is main, jij werkt op
  ontwikkel"* — maar hij overschrijft je keuze niet. Wie een andere branch
  intypt, bedoelt dat.
- **Een zelfondertekend certificaat kun je nu vertrouwen — precies dat ene.**
  Een zelf gehoste server op je eigen netwerk heeft vaak geen certificaat van
  een erkende uitgever. Dat is juist de groep waarvoor "vertrouwde interne
  server" bestaat, en tot nu toe strandde die verbinding gewoon.

  Alles doorlaten wat zelfondertekend is, zou de beveiliging weggooien: het
  certificaat van iemand die tussen jou en de server zit, is óók
  zelfondertekend. Daarom gaat het per certificaat. Strandt de verbindingstest
  op het certificaat, dan toont *Certificaat bekijken* wie het heeft
  uitgegeven, tot wanneer het geldig is en zijn SHA-256-vingerafdruk. Die
  vergelijk je met wat je server zelf meldt — komen ze overeen, dan praat je
  met de juiste machine — en pas dan kies je *Vertrouwen*.

  Vervangt de server het certificaat later, dan vraagt OciDeck het opnieuw. Van
  de app uit gezien zien een verlenging en een aanvaller er namelijk hetzelfde
  uit, dus die afweging hoort bij de mens die de server kent.

  Geldt voor alle drie de netwerkbronnen: WebDAV, S3 en git. Bij S3 en git
  werd een certificaatprobleem tot nu toe als gewone netwerkstoring gemeld —
  die kennen nu, net als WebDAV, een eigen foutsoort ervoor, zodat de weg naar
  *Certificaat bekijken* er überhaupt is.
- **De statusregel zegt nu of een bron ooit heeft geántwoord, niet alleen of
  hij is ingevuld.** Een verbinding werd groen zodra de velden gevuld waren —
  ook bij een server die nog nooit was aangeraakt. Dat groene vinkje beloofde
  iets wat niemand had gecontroleerd.

  Er zijn nu drie standen in plaats van twee: *niet ingesteld* (grijs),
  *ingesteld maar niet getest* (amber, en het staat er in woorden bij — kleur
  alleen is geen boodschap), en *werkte* (groen, met datum en tijd in de
  tooltip). Een geslaagde verbindingstest wordt bewaard, dus je ziet het ook
  nog na het afsluiten van de app.

  Wijzig je de server, dan vervalt die waarneming: ze ging over iets anders.
  Een *mislukte* test wist juist niets — die bewijst dat het nú niet gaat, niet
  dat het vorige week niet ging, en die eerdere waarneming is nog steeds het
  beste dat we hebben.
- **Een git-repository kun je testen vóórdat je hem gebruikt.** WebDAV en S3
  hadden allebei een knop *Verbinding testen*; bij git zei het paneel alleen of
  er ergens op de machine een `git` stond — wat niets zegt over de URL, de
  eigenaar, de repository of het token. Elke instelfout kwam pas bij de eerste
  opslag boven, en juist git heeft de meeste manieren om het mis te hebben.

  De test doet één aanroep en beantwoordt daarmee vier vragen tegelijk: bestaat
  de repository, hoe heet zijn standaardbranch, is hij nog leeg, en mag dit
  token schrijven. Dat laatste is een waarschuwing en geen fout — de verbinding
  wérkt, maar opslaan zou later stranden, en dat hoor je liever nu.

  De standaardbranch is geen bijvangst. Er is geen invoerveld voor, dus stond
  hij altijd op `main`: een repository met `master` was via de instellingen
  onbruikbaar en faalde met alleen ruwe uitvoer van een mislukte clone. De
  forge weet zelf hoe zijn branch heet; de test vraagt het en neemt het over.
- **Afbeeldingen en media gaan nu écht mee met de presentatie — en je ziet
  wanneer dat níet zo is.** Je kunt er niet van uitgaan dat de ontvanger
  dezelfde schijven, netwerkmappen of rechten heeft als jij. Een verwijzing naar
  een bestand elders werkt bij de maker prima en is bij de ontvanger een gat.

  Slepen en de afbeeldingenbibliotheek zetten tot nu toe een absoluut pad in de
  slide en vertrouwden erop dat de kopieerslag bij opslaan het wel zou
  rechttrekken. Beide nemen het bestand nu meteen over. En een deck dat nog niet
  is opgeslagen heeft geen eigen map, dus kopieerde er tot nu toe niets:
  verplaatste je het bronbestand vóór de eerste opslag, dan was de verwijzing
  stuk. Zulke media gaan nu naar een tijdelijke stagingmap met dezelfde indeling
  als een echt project, waarna opslaan ze op hun definitieve plek zet.
  Die tijdelijke map ruimt zichzelf op: bij het opstarten verdwijnen sessies
  waar een week niets meer aan is gebeurd — dezelfde termijn als de
  herstelbestanden, want een teruggehaald deck wijst erin.

  Naast het pad in de editor staat een badge die zegt wat er gebeurt als je de
  presentatie doorgeeft: *Nog niet opgeslagen* (gekopieerd en veilig, alleen nog
  niet definitief), *Buiten de presentatie* (gaat niet mee), *Van internet*, of
  *Alleen in deze sessie*. Het kwaliteitspaneel geeft hetzelfde deck-breed, zodat
  je niet slide voor slide hoeft te controleren.

  Verder: de placeholder zegt nu wát er mis is — *Bestand niet gevonden*,
  *Buiten de presentatie*, *Weg na herladen* — in plaats van vier verschillende
  situaties met hetzelfde grijze vlak af te doen; de controle op ontbrekende
  media zweeg juist bij een niet-opgeslagen deck en doet dat niet meer; gesleepte
  bestanden worden net als gekozen bestanden op magic bytes gecontroleerd; en
  twee verschillende afbeeldingen die allebei `screenshot.png` heten worden niet
  langer stilzwijgend één.

- **S3 als opslagplek, naast lokale mappen, WebDAV en git.** Daarmee wordt zo
  ongeveer alles gedekt wat je in de praktijk tegenkomt: naast AWS S3 werkt
  elke S3-compatible dienst — een eigen MinIO, Ceph, Wasabi, Scaleway,
  Hetzner. Het endpoint is een vrij invulveld en geen lijstje AWS-regio's,
  juist omdat zelf hosten en Europese aanbieders het interessante geval zijn.

  Een S3-bucket is gewoon een verbinding in dezelfde lijst als de rest: geef
  hem een naam, sleep hem waar je hem hebben wilt, en de bovenste bruikbare is
  de standaard. Instellen gaat met endpoint, bucket, regio en een access key;
  de secret access key gaat versleuteld de sleutelhanger van je
  besturingssysteem in en niet het instellingenbestand.

  Twee dingen die eigen zijn aan S3 en die OciDeck daarom expliciet maakt. De
  **adressering** bepaalt of de bucketnaam vóór de host of in het pad komt —
  AWS wil het eerste, de meeste zelf gehoste endpoints het tweede; komt een
  bucket die zeker bestaat terug als "niet gevonden", dan is dit vrijwel altijd
  de knop. En S3 is objectopslag, geen bestandssysteem: de bescherming tegen
  twee mensen die elkaars werk overschrijven leunt op *voorwaardelijk
  schrijven*, wat AWS pas sinds 2024 kan en andere implementaties wisselend.
  Waar een endpoint het niet kan, zegt OciDeck dat — in plaats van stilletjes
  te overschrijven.

  Openen en opslaan gaat via *Openen vanuit S3* en *Opslaan naar S3* in het
  bestandsmenu, met dezelfde bladeraar, dezelfde formaatkeuze en dezelfde
  conflictafhandeling als bij WebDAV. Een deck dat je uit een bucket opende,
  gaat bij opslaan vanzelf naar diezelfde bucket terug.

- **Het kwaliteitspaneel zegt nu wanneer het voor jouw taal niets te zoeken
  heeft.** OciDeck herkent woorden als "diagnose" of "verdachte" in een handvol
  talen; de interface draait er in dertig. Tot nu toe zag je dat verschil
  nergens: de balk werd groen, de lijst met uitgevoerde controles zag er
  compleet uit, en "niets gevonden" las als "er zit niets in". Terwijl er voor
  die taal geen woordenlijst bestond.

  Staat je presentatie in een taal zonder lijst, dan staat dat er nu bij — met
  de nuance die erbij hoort: controles op een controlegetal (BSN, IBAN,
  paspoortstrook) werken gewoon, want die zijn taalonafhankelijk. Alleen de
  woordherkenning valt weg.

- **Landpakketten zijn instelbaar geworden.** Nummers als het BSN of het PESEL
  zijn landgebonden, en je kunt nu per land aangeven of OciDeck ze meeneemt.
  Standaard staat heel Europa aan — EU-27 plus de EER, Zwitserland en het VK —
  en dat is bewust de ruime keuze: de meeste van die nummers hebben een
  controlegetal, dus ze aanzetten levert vrijwel geen valse meldingen op.

  Wat je ook uitzet, de taalonafhankelijke laag blijft draaien: IBAN,
  e-mailadressen, sleutels en paspoortstroken worden altijd nagekeken.

- **Een aangeefster is geen verdachte, en de melding zegt dat nu ook.** Tot nu
  toe leverden "verdachte M. de Vries" en "aangeefster M. de Vries" een
  identieke melding op, terwijl dat juridisch en menselijk twee volstrekt
  verschillende dingen zijn — en de tweede degene is voor wie een lek het hardst
  aankomt. OciDeck herkent nu drie rollen: verdachte, aangever of slachtoffer,
  en getuige.

  De vierde mogelijkheid is de belangrijkste: **onbekend**, en dat is de
  standaard. Staat er geen aanwijzing in de tekst, of staan er juist twee rollen
  in dezelfde zin, dan zegt OciDeck niets over wie het betreft. Dat is met opzet
  zo gebouwd: een keuze tussen alleen "verdachte" en "niet-verdachte" heeft geen
  vakje voor onwetendheid, en dwingt daarmee precies de fout af die je hier niet
  wilt maken.

- **De trefwoordenlijst voor bijzondere persoonsgegevens weet nu wat voor woord
  ze bevat.** Tot nu toe leidde OciDeck uit de lengte van een woord af hoe het
  gezocht moest worden: kort betekende "alleen als heel woord", lang betekende
  "ook met een uitgang eraan". Dat werkte verrassend ver, maar het brak allebei
  de kanten op. "Arrest" is lang genoeg voor de soepele regel en moest juist een
  heel woord zijn — het is namelijk ook een uitspraak van de Hoge Raad, en dat
  woord staat in elke juridische presentatie. En "ziekteverzuim" hoort juist wél
  gevonden te worden in "ziekteverzuimcijfers", wat helemaal niet kon.

  Elk woord draagt nu zelf die informatie, plus een taal en een maat voor hoe
  specifiek het is. Die laatste bepaalt welk woord de melding krijgt als er
  meerdere in dezelfde zin staan: "de diagnose leidde tot ziekteverzuim" wijst
  nu het tweede aan, want het eerste valt in elke projectvergadering.

  Daarnaast worden diagnosecodes (ICD-10) en geneesmiddelcodes (ATC) herkend —
  alleen met een woord als "hoofddiagnose" of "geneesmiddel" ernaast, want `A12`
  is ook een tabelverwijzing en een zaalnummer.

- **Geboortedata en locatiecoördinaten worden herkend.** Twee controles met
  precies tegengestelde regels, en dat is met opzet. Een geboortedatum wordt
  alleen gemeld als er ook een woord als "geboren" of "geboortedatum" bij staat:
  een datum is de meest voorkomende getalsvorm in een presentatie — releases,
  deadlines, kwartaalcijfers — en zonder die eis meldt de controle vooral de
  agenda. Coördinaten hebben zo'n woord juist niet nodig, want twee
  kommagetallen met minstens vier decimalen komen in gewone tekst niet voor.

  Die vier decimalen zijn een bewuste ondergrens: dat is ongeveer elf meter. Met
  minder wijst een coördinaat een dorp aan in plaats van een voordeur, en dan is
  het geen persoonsgegeven meer. `geo:`-links en what3words-adressen worden ook
  herkend, en grafiekgegevens blijven buiten schot — een dataset ís nu eenmaal
  een rij getallenparen.

- **IP-adressen, MAC-adressen, IMEI's en socialemediaprofielen worden herkend.**
  De patronen zijn simpel; het werk zit in wat er níét op af mag gaan. Een
  versienummer is vier getallen met punten ertussen, een tijdstip is twee
  getallen met een dubbele punt, en een git-hash is hex — zonder poorten meldt
  zo'n controle vooral zichzelf. Dus: de adresreeksen die de IETF expres voor
  documentatie heeft gereserveerd tellen niet mee, een IMEI moet zijn Luhn
  halen, en een kale UUID zwijgt tot er `IDFA` of `advertentie` naast staat.

  Een adres uit de privéreeksen (`10.x`, `192.168.x`) meldt wel maar onderbreekt
  niet: dat is interne infrastructuur en geen persoonsgegeven, al blijft een
  intern adresplan in een publieke slide iets om te weten.

- **Een gescand paspoort in een slide wordt herkend.** De twee of drie regels
  vol hoofdletters en `<`-tekens onderaan een identiteitsbewijs — de
  machineleesbare zone — zijn geen willekeurige tekst: er zitten vier
  controlecijfers in, waarvan er één over de andere heen ligt. OciDeck rekent ze
  na, en alleen als ze allemaal kloppen is er een melding. Daardoor kan die
  melding meteen hard zijn zonder verder bewijs: er staat een documentnummer, een
  nationaliteit, een geboortedatum en een vervaldatum in één blok, en dat is
  precies de set waarmee identiteitsfraude begint. Paspoort, identiteitskaart en
  het oudere kaartformaat worden alle drie herkend.

- **De privacycontrole koppelt een bijzonder gegeven nu aan een persóón.** Een
  diagnose of een verdenking is pas een bijzonder persoonsgegeven als er iemand
  bij hoort — een slide *óver* de AVG noemt die woorden zonder er een te
  bevatten. Tot nu toe telde alleen een BSN, een nationaal nummer of een
  e-mailadres als die persoon, en dus gebeurde er bij de meest voorkomende
  formulering van allemaal precies niets: "Marieke de Vries wordt verdacht van
  diefstal" bleef een informatieve hint.

  Namen worden daarom op drie nieuwe manieren herkend, en géén ervan kijkt naar
  de naam zelf — het blijft dus geen naamherkenning die op woordenlijsten of een
  taalmodel leunt, want een woord met een hoofdletter is ook gewoon het begin
  van een zin. Wat telt is wat eromheen staat: een **persoonspredicaat** ("wordt
  verdacht van", "meldde zich ziek") dat geen ander onderwerp dan een mens kan
  hebben, een **e-mailadres dat de naam terugzegt** ("Marieke de Vries" naast
  `m.devries@example.com`), en de al bestaande aanhef en labels, die zwaarder wegen
  dan voorheen omdat "mevr." een uitspraak van de auteur is en geen gok.

  Een naam koppelt bewust niet zo ver als een BSN. Een BSN geldt voor de hele
  slide; een naam reikt tot het eind van de zin waarin hij staat. Zonder die
  grens tilde één naam bovenaan een lang stuk vrije markdown élk trefwoord in de
  duizend regels eronder naar een harde waarschuwing — en dat is precies het
  gedrag waardoor mensen een privacycontrole uitzetten.

- **Wat de auteur zelf markeert, levert geen melding meer op.** Een waarde tussen
  `[[…]]` wordt onvoorwaardelijk geredigeerd, dus er nog over waarschuwen vraagt
  om iets te doen aan iets wat net gedaan ís — precies het soort melding waardoor
  mensen de hele controle uitzetten. Het viel op in de handleiding, waar het
  voorbeeld `arrested at [[Kalverstraat 12]]` zichzelf liet aanmelden.

  De onderdrukking werkt op **positie** en niet op waarde: staat hetzelfde adres
  twee keer op een slide en is er één gemarkeerd, dan wordt de andere gewoon
  gemeld. Een vergelijking op tekst zou ze allebei laten verdwijnen, en dat is een
  vals-negatieve die niemand ziet.

  Wat blijft staan, is de melding over het ónderwerp: de artikel 9- en
  10-treffers komen niet uit de waarde maar uit de woorden eromheen, dus een
  volledig gemarkeerde zin over een verdachte meldt nog steeds dat de slide over
  een strafzaak gaat. Een markering verbergt een waarde, geen onderwerp.

### Fixed
- **Vier dingen die de ontvanger van een export te zien kreeg — of juist niet.**

  *Een uitgezet script in commentaar maakte de hele HTML-export blanco.* De
  beveiliging tegen uitbraak uit het markdown-blok keek alleen naar `</script`,
  maar dat is niet de enige uitgang: een `<!--` zet de HTML-lezer in een andere
  stand, en een `<script` daarna in nóg een, waar een echte `</script>` het blok
  niet meer sluit. Alles daarna werd scripttekst — inclusief het stukje dat de
  dia's zichtbaar maakt. De ontvanger opende een lege witte pagina, zonder
  foutmelding. En de invoer is doodgewoon: een codedia die kwetsbare paginabron
  citeert, precies wat een pentestrapport doet.

  *Het `.ocideck`-pakket ging om de classificatiepoort heen.* Bij een
  vrijgaveplafond gaf "Exporteer naar PDF" een nette weigering en "Exporteer
  pakket" gewoon een bestand — terwijl een pakket de meest complete uitvoer is
  die de app kent. Erger nog, en zónder dat er een instelling voor nodig was: het
  pakket hield achtergehouden dia's niet achter. Een dia op *overslaan*, of met
  een strengere eigen classificatie dan het deck, is onzichtbaar in de presenter,
  op het zaalscherm en in de PDF — en ging mee in het pakket dat naar de klant
  gaat.

  *Negatieve waarden tekenden niet.* Een verliesreeks of een afwijking ten
  opzichte van een nulmeting kwam uit op een lege grafiek met een y-as van 0 tot
  1, terwijl de gegevens van −5 tot −8 liepen. Aannemelijk ogende onzin, wat
  erger is dan een zichtbaar lege grafiek.

  *Een quizdia zette de antwoordsleutel in het document.* Zonder eigen weergave
  viel het vraagblok terug op de codeweergave, en stond de hele specificatie
  leesbaar op de dia — inclusief welk antwoord het goede is. Wie een quizdeck als
  voorbereiding rondstuurde, deelde de antwoorden mee.

- **De staart van de bugjacht: ruim twintig bevindingen ineens.** Wat overbleef
  na de eerdere rondes — geen samenhangend cluster meer, maar wel stuk voor stuk
  een pad waarlangs iets stils misging.

  *Privacy en veiligheid.* Een tijdstempeltoken van duizenden niveaus diep liet
  de app omvallen bij het openen van een deck dat iemand je stuurt. Vier velden
  werden nooit gescand — `version`, `date`, de standaarden- en
  gereedschapslijst, het scope-object en, het kwalijkst, de MIAUW-motiveringen,
  die base64-gecodeerd meereizen en dus voor elk vangnet onzichtbaar zijn. Wat
  niet gescand wordt, wordt ook niet geredigeerd. Een kolomkop telde niet mee als
  context, waardoor een kolom "BSN" met nummers eronder slechts een aanwijzing
  opleverde. En bij een tabel met ongelijke rijen botsten celindexen, zodat een
  redactie op de verkeerde cel landde.

  *Werk dat verdween.* Een beschadigde bijschrift-sidecar nam alle andere
  bijschriften in die map mee. De inhoud van een dia kon via een foutmelding in
  de log belanden. Een opslag zonder verbinding kwam niet in de wachtrij. De
  offline werkkopie werd gewist vóór de nieuwe was geschreven. Twee gelijktijdige
  schrijvers deelden één tijdelijk bestand. De markdown-editor gooide getypt werk
  weg zodra je elders in het deck iets veranderde. En bij platte opslag gingen de
  afbeeldingen vóór het bestand dat de conflictbewaking draagt.

  *Verkeerd gelezen, verkeerd geschreven.* S3-lijsten werden als Latin-1 gelezen,
  zodat `café.md` onvindbaar werd. De tijdlijn-scheiding ontsnapte niet. Een
  reeksnaam met puntkomma's stemde het CSV-scheidingsteken weg. Twee bestanden
  met dezelfde naam werden één bestand in een pakket. Een miniatuur was maar op
  één as begrensd.

  *Hangen, blokkeren, wachten.* Een antwoord dat halverwege stilvalt hing voor
  altijd — de timeouts dekten alleen de kop. Het uitpakken van het CVE-archief
  blokkeerde het scherm en maakte Afbreken onbruikbaar. Zoeken las de hele index
  uit, ook als er allang genoeg gevonden was. En de rijke tekst mat het hele
  document opnieuw bij elke aanslag: 26 ms → 0,002 ms.

  *En de rest.* De prullenbak liet sidecars achter, een volle schijf kon een
  geredigeerd rapport zonder manifest achterlaten, plakken was twee
  ongedaan-maak-stappen, en Ctrl/Cmd+F deed in de gewone editor niets terwijl de
  sneltoets de toets wél opat.

  Het fetch-hulppunt kreeg een poortgrens en een plafond op gelijktijdige
  verzoeken. De moduletekst beloofde dat een niet-geconfigureerde deployment geen
  open relais is; dat klopt niet — `Sec-Fetch-Site` houdt browsers tegen, geen
  `curl` — en die belofte is nu bijgesteld in plaats van andersom.

- **Zeven velden konden uit een opgeleverd bevindingsrapport verdwijnen.** Alle
  zeven zonder melding, en de meeste pas zichtbaar bij de klant.

  Het ernstigst: `copyWith` gaf het **MASWE-nummer** niet door — het enige veld
  van de veertien dat ontbrak. Het automatisch hernummeren van bevindingen
  gebruikt dat en schrijft het resultaat terug naar het bestand, dus één keer
  hernummeren haalde de regel definitief uit het rapport. De paginabouwer liet
  daarnaast **MASWE, testverwijzing en hertest-uitkomst** volledig vallen, ook op
  de eerste pagina: een bevinding die lang genoeg was om over twee dia's te
  lopen, verloor ze uit elke weergave. Een verdwenen hertest-uitkomst is het
  verschil tussen "opgelost" en niets.

  De overige vier zijn ontsnappingsgaten. Een **kopregel in de beschrijving**
  knipte de tekst af en liet de rest overlopen in het veld waarvan hij toevallig
  de naam droeg. Een **backtick** in de scope of de testverwijzing kapte de
  waarde af, net als een **blokhaak** in de CWE-naam en een **regeleinde** in de
  hertest-notitie. En een **CVSS-vector van een andere versie dan 4.0** stond wel
  in het bestand maar werd bij het herladen gewist — de schrijfkant bewaarde hem,
  alleen de lezer was streng.

- **Het herstelbestand overleefde het herstellen niet.** Drie dingen aan het
  terugzetten van niet-opgeslagen werk deden het tegenovergestelde van wat
  herstel hoort te doen.

  Het wissen ging vóór het controleren: eerst het bestand weg, dan pas kijken of
  het deck gelezen kon worden. Lukte dat niet — en een crash ín de parser is een
  waarschijnlijke reden dát er een herstelbestand ligt — dan was het enige
  exemplaar net opgeruimd, en kwam je terug bij een leeg tabblad zonder melding.
  Nu blijft het staan, en zegt de app het ook.

  Daarna zat er een gat van 25 seconden: het herstelde tabblad kreeg een verse
  sleutel, dus zijn eigen herstelbestand ontstond pas bij de volgende autosave.
  Juist in die seconden loopt een app vast die zojuist opnieuw dezelfde inhoud
  opende. Het tabblad neemt nu de bestaande sleutel over.

  En met twee vensters open wiste een nette afsluiting van het ene de
  crashbescherming van het andere — de herstelmap is gedeeld en werd in zijn
  geheel leeggeveegd. Afsluiten ruimt nu alleen de eigen tabbladen op.

- **Opslaan ging niet terug naar waar de presentatie vandaan kwam.** Wie een
  deck van WebDAV, S3 of git opende en daarna gewoon op opslaan drukte (of
  Ctrl/Cmd+S), zag het als lokaal bestand landen. De server hield de oude
  versie, de laptop kreeg de nieuwe, en niets meldde dat de twee uit elkaar
  liepen — het is precies het soort fout dat je pas ontdekt als iemand anders
  de verouderde versie opent.

  Terugschrijven naar de bron kon wel, maar alleen via een apart menu-item per
  soort opslag. Dat betekende dat de gebruiker moest onthouden welk van de
  opslaanknoppen bij zijn bron hoorde, terwijl het antwoord al vastlag: waar
  het vandaan komt, gaat het naartoe terug. Nu volgt opslaan de herkomst,
  zonder te vragen, naar hetzelfde pad in hetzelfde formaat.

- **Zes menu-items voor openen en opslaan zijn er twee geworden.** In plaats
  van "Openen vanaf WebDAV", "Openen vanuit S3", "Openen uit git" en drie
  bijbehorende opslaanvarianten staat er nu één **Openen uit…** en één
  **Opslaan naar…**. Beide beginnen met dezelfde vraag — welke verbinding — en
  die vraag wordt overgeslagen als er maar één is, dus wie één server heeft
  merkt van de hele keuze niets.

  De vraag die iemand heeft is "waar staat mijn presentatie", niet "welk
  protocol draait op de plek waar mijn presentatie staat". Het welkomscherm
  bood om dezelfde reden alleen WebDAV aan; wie met S3 of git werkte kon daar
  nergens heen. Nu is het daar dezelfde ingang.

  "Opslaan naar…" blijft bestaan als de uitzondering: het deck bewust ergens
  ánders neerzetten. Wat git écht toevoegt — synchroniseren, geschiedenis,
  versies, uitbrengen ter review — staat nog gewoon in zijn eigen blok.

- **"Gebundelde standaarden" heet nu "Standaarden en methodieken".** De sectie
  bij Over OciDeck somt naast standaarden ook MIAUW op, en dat is een methodiek.
  Een rapportage die vermeldt waartegen is getoetst, hoort het onderscheid niet
  te laten vervagen in de kop erboven.
- **Afronden & verzegelen stond in het menu met de module uit.** Verzegelen is
  documentintegriteit uit de uitbreiding Informatieveiligheid, maar het menu-item
  keek alleen of het deck al verzegeld was. Het stond daarmee pal naast zijn
  buurman "Bijlage hulpmiddelen invoegen", die de module-check wél had, en het
  RFC3161-tijdstempel dat ná het verzegelen komt zat er ook al achter. Wie de
  uitbreiding uit had staan, kon dus wel verzegelen maar het zegel daarna niet
  van een tijdstempel voorzien: het spoor was halverwege afgesloten.

  Dezelfde knop op de ondertekeningsdia is meegegaan. Die was de laatste weg
  eromheen: een dia van een moduletype blijft renderen met de module uit, dus
  een rapport dat er al een droeg bood het verzegelen alsnog aan. De
  handtekeningvelden blijven wél bewerkbaar — die gegevens horen bij het deck,
  niet bij de schakelaar.
- **Tien soorten inhoud verdwenen bij opslaan en weer inlezen.** Het bestand ís
  het document, dus alles wat je kunt typen hoort er na een rondje nog te staan.
  Geen van deze gevallen gaf een melding — je zag het pas als je ging kijken, en
  meestal pas veel later.

  - *Een ``` in een codevoorbeeld kapte de code af,* en met een `---` erachter
    scheurde de slide bovendien in tweeën. De fence is nu altijd langer dan wat
    erin staat, zoals CommonMark voorschrijft.
  - *Een opmerking van de auteur verdween uit de tekst en dook op in de
    sprekersnotities;* een notitie die begon met `skip` of `tlp:` werd andersom
    als richtlijn opgegeten, inclusief het overslaan van de slide.
  - *Backslash-ontsnappingen werden bij het inlezen weggehaald,* waarna `\- geen
    lijst` na één keer opslaan een échte opsommingsstreep was.
  - *Een meerregelig citaat werd afgekapt tot de eerste regel.*
  - *Een tabelrij met alleen streepjes* — de gebruikelijke invulling voor "niet
    van toepassing" — *werd als scheidingsrij weggegooid,* met de andere kolommen
    erbij.
  - *Een door de auteur getypte `<div>`-regel verdween* uit een vrije-tekstslide,
    met inhoud en al.
  - *Een zero-width space van de auteur werd overal weggehaald,* terwijl de
    ontsnapping hem alleen tussen streepjes zet. Geplakte web- en CJK-tekst zit
    er vol mee.
  - *Een afsluitende komma in CSV liet zijn lege veld vallen,* waardoor het
    plakken van een spreadsheet met een lege laatste cel in zijn geheel werd
    afgekeurd — en *het plakken van een markdown-tabel negeerde de `\|`* die de
    app zelf schrijft.

- **Vier keer stond het middel er al, en was het op één plek niet aangesloten.**
  Uit de bugjacht kwam dit als het karakteristieke patroon van de codebase naar
  voren: niet een ontbrekend idee, maar een geschreven en getoetst mechanisme dat
  één oppervlak niet bereikte.

  - *De offline CVE-database meldde "lokaal beschikbaar" op grond van een
    metabestand van een paar honderd byte.* De index zelf — honderden megabytes,
    en dus precies wat een opruimtool weghaalt — werd nergens gecontroleerd. Elke
    opzoeking kwam dan leeg terug, en omdat er bewust niet wordt teruggevallen op
    de online keten las dat als "deze CVE is niet van toepassing". De controle
    kijkt nu naar het bestand zelf, inclusief de lengte die al werd vastgelegd
    maar nooit gelezen.
  - *Na ongedaan maken kon een dia toevoegen omvallen.* De selectie bleef staan
    waar hij stond terwijl het deck korter werd; `addSlide` rekende daarmee door
    en gooide een RangeError, waarna de knop niets deed. Ook via plakken en het
    slepen van een afbeelding. Het klemmen zat al in de buurmethoden, en
    `clampIndex` — geschreven om de selectie bij te trekken — werd nergens
    aangeroepen.
  - *Een bestandsnaam met een `|` trok de bijlage met bewijshashes uit elkaar,*
    waardoor een hash bij het verkeerde bestand kwam te staan.

- **De privacycontrole scande bij elke aanslag het hele deck.** `scanSlide` was
  geschreven voor per-dia-onthouden en werd niet gebruikt, dus een deck van 500
  dia's kostte bij elke toets een volledige scan. Nu wordt per dia onthouden:
  gemeten 137 ms → 0,5 ms na één aanslag. De sleutel draagt de scanner, de dia én
  de positie, zodat een gewijzigde instelling of een verschoven dia nooit een
  verouderde bevinding kan opleveren.

- **Een tweede ronde op dezelfde dag overschreef de eerste.** De werkbranch
  draagt alleen een datum, dus elke opslag van hetzelfde deck op dezelfde dag
  komt op dezelfde branch uit. Bij een verse ronde vroeg het opslaan de forge
  waar die branch nú stond en committeerde daar bovenop — waarmee de basis per
  definitie de kop was en de concurrency-guard nooit kón vuren.

  Eén gebruiker was al genoeg: 's ochtends openen vanaf main en opslaan, 's
  middags opnieuw vanaf main openen en opslaan, en de ochtend was van de kop
  verdwenen, met *"Opgeslagen in git"* in beeld. Met twee mensen kwam er nog bij
  dat het legen van de wachtrij de verwijderlijst uit de remote boom berekent:
  een bestand dat de ander had toegevoegd werd dan actief weggehaald.

  De basis is nu de commit waar het deck daadwerkelijk tegenaan gelezen is. Staat
  de branch verderop, dan botst het en voegt de driewegs-merge beide kanten
  samen. Alleen bij een écht verse branch is de kop de basis — die takken we op
  dat moment zelf af.

- **Een tabwissel tijdens het opslaan verlegde de git-herkomst.** Een commit gaat
  over het netwerk en duurt. Klikte je ondertussen naar een ander tabblad, dan
  kreeg dát tabblad de herkomst van het deck dat aan het opslaan was — en
  committeerde bij de volgende opslag zijn eigen inhoud over de deckmap van het
  eerste deck heen. Bij samenvoegen was het erger: het samengevoegde deck landde
  in het verkeerde tabblad, met diens ongedaan-maken-geschiedenis gewist en de
  herstelkopie opgeruimd. Het tabblad ligt nu vast vóór de eerste netwerkronde,
  zoals bij WebDAV en S3 al het geval was.

- **De beeldcontrole meldde een gezicht dat er niet was, en je kon er niets mee.**
  Een gegenereerde tekening van dieren in pak — een uil frontaal, een kikker met
  bril — leverde de melding "herkenbaar gezicht" op. Terecht van de detector
  gezien: een uilenkop ís een schijf met twee ogen en een snavel ertussen, en dat
  is precies de vorm waar YuNet op zit. Maar er stond geen mens op, en de melding
  was nergens weg te zetten: de dispositie op de dia — Accepteren, Accepteren +
  waarschuwen, Weglaten — werd door de beeldcontrole als enige controle niet
  gelezen. Dat is nu wel zo, met dezelfde regel die de tekstscan al hanteerde.
  Een beoordeelde dia zwijgt.

  De gevoeligheid is met opzet níét aangepast. De drempel meten leek een
  makkelijkere uitweg — de dierenkoppen halen 0,801 tot 0,832 en zouden bij 0,85
  verdwijnen — maar op een echte kroegfoto uit hetzelfde deck scoren twee mensen
  op de achtergrond 0,869 en 0,884. Juist die gezichten, klein en onscherp en van
  iemand die niet wist dat hij op de foto stond, wil je niet missen om een
  tekening kwijt te raken. De meting staat nu bij `kFaceScanScoreThreshold`, zodat
  de volgende drempeldiscussie niet weer bij nul begint.

- **Het pad van een afbeelding was niet te selecteren.** De bestandsnaam onder de
  beeldkiezer stond er om overgenomen te worden — uit een privacybevinding komt
  een naam als `images/pasted_1781245807752.png` — maar je kon hem alleen
  overtypen, en daar sluipt een typefout in. Het pad is nu selecteerbaar in alle
  zeven beeldeditors. De placeholder blijft dat niet: daar valt niets te kopiëren.

- **Een vinkje tijdens het presenteren overschreef de bron met zwarte blokken.**
  De presenter draait op het geprojecteerde deck — de zwartgelakte afleiding die
  de zaal ziet. Eén checklistpunt aanvinken schreef de héle geprojecteerde slide
  terug naar het echte deck: titel, notities en de overige punten reisden in hun
  geredigeerde vorm mee. Na opslaan was de oorspronkelijke tekst weg.

  De regel stond al in de code — *een oppervlak dat de gegevens niet kán zien,
  mag ze ook niet terugschrijven* — en werd voor tabellen ook afgedwongen, met
  test en al. De checklist was er alleen nooit op aangesloten. Nu gaat het
  aanvinken uit zodra er op die slide iets is weggelakt, en weigert de presenter
  het alsnog als het bericht van het zaalvenster komt.

- **Wat je tijdens het opslaan typte, verdween.** Opslaan nam een momentopname,
  schreef die weg — bij een deck met afbeeldingen al gauw seconden — en zette
  daarna die oude opname terug. Alles wat er ondertussen bij kwam, was op dat
  moment weg. Het slot tegen dubbel opslaan hielp niet: de concurrent is hier
  niet een tweede save maar het toetsenbord.

  Erger was de vlag erachter. Het deck werd schoon gemeld, waarmee ook de
  herstelkopie werd opgeruimd — het getypte werk stond dus niet in het geheugen,
  niet op schijf en niet in de recovery, en undo kon er evenmin bij. Nu blijft
  nieuwer werk staan en blijft het vuil, zodat de volgende opslag het meepakt.

- **Een handtekening kon het geheugen opmaken bij het openen van een deck.** De
  getekende handtekening reist mee in de front matter en ging als enige
  deck-afbeelding buiten de decodeercap om. Een egaal gekleurde PNG van
  30000×30000 is een paar KB op schijf en ~3,6 GB uitgepakt: een deck dat iemand
  je stuurt, was daarmee genoeg. De opmaak (`height: 44`) hielp niet — die
  begrenst de layout, niet de decode. Alle vier de plekken lopen nu langs
  dezelfde poort als elke andere afbeelding.

- **Een deck uit een pakket opende met lege grafieken.** Sinds grafiekdata naar
  een los bestand verhuisde, munt OciDeck voor nieuwe databestanden altijd
  `.json`. Het uitpakken van een `.ocideck` las elk databestand echter als CSV.
  Op JSON levert dat geen fout maar onzin — de eerste regel `{` werd de
  kopregel, dus geen enkele reeks — en het resultaat was een grafiek zonder
  cijfers. De enige test die dit pad dekte gebruikte een `.csv` en bleef daarom
  groen. Het uitpakken kiest de lezer nu op de extensie, zoals elk ander
  laadpad.

- **Een grafiek zonder cijfers bleef stil.** Een lege plot is niet te
  onderscheiden van een grafiek waar nog niets in staat, dus wie een deck opende
  waarvan het databestand ontbrak, zag alleen een lege slide. Twee paden meldden
  het niet: het bestandskiezer-pad gooide de waarschuwing weg, en het bytes-pad
  (web, drag-drop, URL-import) kende er geen. Dat laatste pad heeft geen
  projectmap en kán een `data/…`-verwijzing dus niet oplossen — een grens van
  het pad, geen fout, maar wel iets om te zeggen in plaats van te verzwijgen.
  Beide melden nu welke verwijzing niet ingevuld kon worden.

- **Een woonadres kon volledig door de controle glippen, en het viel niet op.**
  `Woonadres: Weidemolen 12, 1234 AB Amsterdam` werd niet gemeld. De
  oorzaak was één ontbrekend woord: een straat werd herkend aan een lijstje
  achtervoegsels, en `-molen` stond er niet in. Dat lijstje kán ook nooit af
  zijn — Nederlandse straatnamen hebben een staart van `-veld`, `-hoeve`,
  `-akker`, `-horst` die je niet uitput.

  Kwalijker was wat erop volgde. Een postcode en een straat bevestigden elkáár,
  dus zonder straattreffer bleef ook de postcode "mogelijk" — en meldingen van
  dat niveau haalt het exportrapport niet. Er kwam dus geen waarschuwing: het
  deck zag er schoon uit. En stond de slide wél op *weglaten*, dan bleef er
  `Woonadres: ██████ Amsterdam` staan, met straat, huisnummer en
  woonplaats gewoon leesbaar.

  Een adres wordt nu herkend aan zijn vorm in plaats van aan zijn staart: staat
  de postcode direct achter het huisnummer, dan is dat het adres — van straat
  tot en met woonplaats, in één keer, zonder woordenlijst. Daarnaast telt
  `Woonadres:` voortaan als label, net als `Naam:` dat al deed. Het label zelf
  blijft staan: u hoort te kunnen zien dát er een adres weg is.

- **Een geredigeerde foto was niet van een vergeten foto te onderscheiden.** Op
  een slide die op *weglaten* stond verdween de afbeelding, maar wat ervoor in
  de plaats kwam was het lichtgrijze vak met het woord "Afbeelding" — hetzelfde
  vak als op een slide waar u nog gewoon geen foto had gekozen. Naast tekst met
  zwarte blokken erin las dat als slordigheid in plaats van als een ingreep, en
  de ontvanger kon het verschil niet zien.

  Er komt nu een zwart redactievlak met het woord "Geredigeerd" voor in de
  plaats, in dezelfde taal als de `████`-blokken in de tekst. Hetzelfde geldt
  voor video en audio, die langs een andere placeholder liepen met precies
  dezelfde fout. Het vlak blijft zwart in donkere modus — het volgde anders het
  kleurenpalet van de editor, dat daar omkeert, en een bijna wit redactievlak is
  geen redactie.

- **Een vastgepind certificaat gold wel voor de verbindingstest, niet voor het
  klonen.** Wie op een eigen forge een zelfondertekend certificaat vertrouwde,
  kreeg een groen vinkje bij het testen en daarna een clone die afketste op
  datzelfde certificaat. De twee wegen naar dezelfde server gaven een
  verschillend antwoord: de REST-weg vergelijkt de vingerafdruk zelf, en `git`
  kent zoiets niet.

  De handleiding beloofde het overigens al — *"each connection carries its own
  pinned certificate"* — dus dit was niet alleen een gat, het was een gat waar
  de documentatie overheen las.

  Git kent alleen een CA-bestand, geen vingerafdruk. OciDeck vraagt het
  certificaat nu zelf op bij het gecontroleerde adres, vergelijkt de
  vingerafdruk, en geeft het pas dán aan git als vertrouwd anker. De beslissing
  blijft dus hier liggen. De certificaatcontrole van git blijft gewoon aan staan
  — hem uitzetten zou ook de naamcontrole slopen, en dan was het vastpinnen
  niets meer waard.

- **Verzoeken naar `https`-servers gingen onversleuteld over de lijn.** Om een
  DNS-rebind onmogelijk te maken zet OciDeck de socket vast op het adres dat de
  veiligheidscontrole heeft goedgekeurd. Dat gebeurt met een eigen
  `connectionFactory` — en wie die zet, is in Dart volledig zelf
  verantwoordelijk voor TLS. Het standaardpad van de SDK zet het versleutelen
  op; het fabriekspad neemt letterlijk over wat je teruggeeft.

  Er werd een kale socket teruggegeven. Gevolg: elk `https`-verzoek ging als
  platte HTTP naar poort 443, inclusief de `Authorization`-header met je
  WebDAV-wachtwoord of je git-token erin. De server antwoordde met *"the plain
  HTTP request was sent to HTTPS port"*, dus de verbinding werkte ook niet —
  maar de gegevens waren er dan al uit.

  Dit raakte alles wat over het netwerk ging: WebDAV, S3, git, het ophalen van
  een deck van een URL, de CVE-database en de AI-backend. Alle zeven plekken
  lopen nu via één gedeelde functie die het TLS zelf opzet, gevalideerd tegen
  de hostnaam terwijl de socket op het gekeurde adres vastgepind blijft.

  Geen enkele test ving dit, en dat was geen toeval: ze praten allemaal
  `http://127.0.0.1`, dus het TLS-pad werd nooit aangeraakt. Er is nu een test
  die naar de eerste bytes op de lijn kijkt — een TLS-verbinding begint met een
  handshake-record, platte HTTP met de naam van de methode.

- **De native git-weg ging buiten de adrescontrole om.** Elke uitgaande
  verbinding in OciDeck wordt geresolved, gefilterd en op het goedgekeurde adres
  vastgezet — behalve clone, fetch en push. Die draaien in een echt
  `git`-subproces, en dat deed zijn eigen DNS, zijn eigen omleidingen en zijn
  eigen verbinding. De server-URL ging er ongetoetst in, zonder adresfiltering
  en zonder schemacontrole.

  Wat het makkelijk maakte om te missen: wie in Instellingen de git-verbinding
  testte, gebruikte de REST-weg, en die ís volledig gepind. De guard zien afgaan
  bewees niets over clone/fetch/push.

  NetGuard eromheen leggen kan niet — er is geen socket van ons om in te haken.
  Nu krijgt git de uitkomst opgelegd: `http.curloptResolve` bindt de hostnaam aan
  het goedgekeurde adres (TLS blijft tegen de náám valideren, dus een DNS-rebind
  kan de bestemming niet meer verzetten), en `http.followRedirects=false` maakt
  van elke omleiding een fout. Dat laatste weegt hier zwaarder dan elders: het
  token reist als HTTP-header mee, en een header volgt een omleiding gewoon mee.
  Verder dezelfde eis als bij WebDAV en S3: https, tenzij de server bewust als
  vertrouwd intern is gemarkeerd.

  De test toetst niet alleen dat OciDeck de juiste instellingen meegeeft, maar
  ook dat `git` zich eraan houdt — anders is het een papieren maatregel.

- **De privacyverklaring verzweeg S3 en git.** De toestemmingspoort somt op wat
  het apparaat verlaat, en die opsomming eindigt op een dubbele punt: *"Gegevens
  verlaten dit apparaat alleen als jij dat kiest:"*. Wie zo'n lijst leest, leest
  hem als volledig. Hij was het niet. S3 stond er nooit in en git al sinds het
  bestaat niet — twee opslagsoorten die decks naar een server sturen, ontbraken
  in precies de tekst waarop je aftekent dat je weet wat er weggaat.

  Er stond ook niets over de **git-werkkopie**: een verbonden repository zet een
  echte clone met volledige deckinhoud op je schijf, en anders dan de
  herstelkopieën wordt die *niet* na zeven dagen opgeruimd. En "geheimen staan
  in de sleutelbos" bleek twee randen te hebben: bij S3 geldt dat voor de geheime
  sleutel, niet voor de access key ID, en het git-token verlaat de sleutelbos
  zolang er een push loopt.

  Dat dit zo lang kon blijven staan, kwam doordat niets het zag. De opsomming
  wordt nu getoetst tegen `StorageConnectionKind`, een sealed enum — een vijfde
  opslagsoort breekt de test en dwingt de auteur langs de verklaring.

- **"Geen toegang" en "verkeerd wachtwoord" waren dezelfde melding.** Een 401
  en een 403 leverden allebei *"Aanmelden mislukt — controleer gebruikersnaam
  en wachtwoord"*. Bij een 403 is dat het enige advies dat zéker niet helpt: je
  bent binnen, je mag alleen hier niet bij. Wie het opvolgt, gaat een wachtwoord
  zitten controleren dat klopt.

  De twee zijn nu gescheiden, voor WebDAV en voor de drie git-forges. Bij git
  gaat het meestal om een token met te weinig scope, of een limiet die de forge
  oplegt — ook daar helpt "controleer je token" niet, maar "geef het meer
  rechten" wel.

  **S3 blijft bewust ongesplitst.** Die geeft óók 403 bij een verkeerde
  handtekening of een verkeerde regio, dus daar zou splitsen op de status juist
  misleiden: de bestaande melding noemt alle drie de oorzaken, en dat klopt.
- **Een afgewezen push werd op een niet-Engelse machine als "offline"
  weggeschreven.** Wanneer iemand anders je voor is geweest, weigert git je
  push. OciDeck herkende dat aan de Engelse tekst in zijn uitvoer
  ("non-fast-forward", "fetch first") — maar git spreekt de taal van de schil,
  en die werd ongewijzigd doorgegeven. Op een Nederlandse of Duitse machine
  matchte er niets, werd de afwijzing als storing geclassificeerd, en verdween
  het werk stil in de wachtrij in plaats van een conflictmelding te geven.

  Het verschil is niet cosmetisch: bij een afwijzing hoor je te zien dát er een
  conflict is, want anders werk je door op een basis die achterhaald is. `git`
  draait nu met `LC_ALL=C` (en een lege `LANGUAGE`, want gettext laat die
  vóórgaan), zodat hij altijd in het Engels antwoordt. De herkenning zelf is
  een aparte functie geworden, zodat de gevallen te testen zijn zonder een
  echte remote te hoeven laten weigeren.
- **Eén weggevallen verbinding was meteen een mislukte actie.** Er zat nergens
  een tweede poging in: één TCP-hik tijdens het ophalen van een mappenoverzicht
  of het downloaden van een deck, en je kreeg een foutmelding.

  Leesacties — bladeren, downloaden, de verbindingstest — proberen het nu één
  keer opnieuw wanneer de verbinding wegviel, met een korte pauze ertussen. Eén
  keer, want een tweede poging vangt de hik op waar het om gaat en alles daarna
  is wachten op iets dat structureel stuk is.

  Wat er nadrukkelijk *niet* onder valt: opslaan. Een mislukte upload opnieuw
  sturen is niet hetzelfde als hem één keer sturen — de bewaking die controleert
  of er intussen niemand anders heeft geschreven, hangt aan wat er op dát moment
  op de server staat. Ook een time-out telt niet mee: die kostte je al de volle
  wachttijd, en er nog een ronde bovenop doen maakt een trage server twee keer
  zo traag. Een geweigerd wachtwoord evenmin — dat is een antwoord, geen storing.
- **Een geplakte Nextcloud-DAV-URL wordt opgemerkt in plaats van half
  genegeerd.** Nextcloud toont in zijn eigen instellingenscherm de volledige
  DAV-URL — `https://cloud.example.nl/remote.php/dav/files/jan/Presentaties` —
  en dat is wat mensen hier in het serverveld plakken.

  Bij servertype *Nextcloud* leidt OciDeck het DAV-pad zelf af en gooide het
  geplakte pad weg. De verbinding wérkte daardoor meestal gewoon, maar de
  submap die iemand er bewust in had staan verdween zonder een woord, en het
  veld bleef iets tonen dat niet was wat de app gebruikte. Bij *Andere
  WebDAV-server* is datzelfde pad juist de wortel, dus de twee standen faalden
  in tegengestelde richting — en geen van beide zei waarom.

  OciDeck herkent de vorm nu (zowel het huidige `/remote.php/dav/files/…` als
  het oudere `/remote.php/webdav/…`) en biedt aan hem uit elkaar te halen: de
  server in het URL-veld, de gebruikersnaam en de submap op hun eigen plek. Met
  een knop en niet automatisch — het herschrijft wat je zojuist plakte, en dat
  hoort je eigen keuze te blijven. Velden die je zelf al had ingevuld blijven
  staan; alleen de server-URL wordt altijd opgeschoond, want daar staat de knop
  voor.
- **Git-fouten kwamen onvertaald en onafgemaakt op je scherm.** WebDAV en S3
  hadden allebei een tabel die een foutsoort omzet in een uitlegbare,
  vertaalde melding. Git had er geen. `GitForgeException` viel door de
  centrale vertaling heen naar *"er ging onverwacht iets mis"*, en de schermen
  die hem wél apart afvingen toonden de servicetekst rechtstreeks — Nederlands
  voor iedereen, ongeacht taalkeuze, en bij een onbekende status letterlijk
  *"Onverwachte status 418"*.

  Git heeft nu zijn eigen tabel, met bij een 404 de nuance die de forge
  afdwingt: die geeft óók 404 wanneer je token de repo niet mag zien, dus de
  melding zegt "of je token mag het niet zien" in plaats van te beweren dat er
  niets is. De ruwe tekst blijft bestaan en gaat naar het logboek — daar wil je
  die 418 juist wél lezen.

  Ook rechtgezet: de drie bladervensters (WebDAV, S3, git) sloegen alles
  behalve "niet ingesteld" plat tot één zin — *"Kon de map niet laden.
  Controleer je verbinding en instellingen."* — terwijl de tabel ernaast al kon
  zeggen dát het wachtwoord fout was of dat de servernaam niet bestaat. Alle
  drie gebruiken nu diezelfde tabel. En "verbinding mislukt" en "de server gaf
  een fout" zijn uit elkaar gehaald: bereikbaar-maar-stuk vraagt iets anders
  van je dan onbereikbaar.

  Ten slotte wezen vier meldingen nog naar *Instellingen → WebDAV*, een
  tabblad dat sinds de verbindingenlijst niet meer bestaat.
- **Een mislukte verbinding zegt nu wát er mis is.** De servicelaag wist
  meestal precies waarom iets faalde, en gooide die kennis één laag vóór de
  gebruiker weg.

  Het schadelijkste geval was een tikfout in de servernaam. De SSRF-beveiliging
  gaf "geen adressen" terug voor twee heel verschillende oorzaken — een naam
  die niet bestaat, en een naam die naar een intern adres wijst — waarna de app
  van beide maakte: *"Markeer een privé/LAN-server eerst als vertrouwd."* Bij
  een typefout hielp dat niet alleen niets, het zette de gebruiker aan een
  veiligheidsvink om te zetten die het probleem niet was. Wie hem al aan had
  staan, kreeg hetzelfde advies nog eens. De twee redenen zijn nu gescheiden,
  in alle drie de opslagsoorten.

  Daarnaast eindigde elke WebDAV-bewerking op één `catch` die alles tot
  "Verbinding mislukt" platsloeg. Een afgewezen certificaat, een dichte poort
  en een omleiding werden zo dezelfde zin, terwijl het verschil alleen in het
  logboek stond — waar de gebruiker niet kijkt. Een zelfondertekend of verlopen
  certificaat zegt dat nu, en een server die doorstuurt ook: die omleiding
  volgen we bewust niet, maar dat is iets anders dan een storing.
- **Een wachtwoord dat niet in de sleutelhanger paste, verdween zonder een
  woord.** Lukte het wegschrijven van een WebDAV-wachtwoord, een S3-sleutel, een
  git-token of een AI-API-sleutel niet — een vergrendelde keychain, een
  geweigerde toegangsvraag — dan werd de fout op drie lagen ingeslikt: de
  opslagklasse gooide netjes door, de provider ving hem af en gaf `false`
  terug, en de settings-dialoog keek naar dat antwoord niet om. Het venster
  sloot alsof alles goed was gegaan.

  Je merkte het pas bij de eerste verbinding, en dan lijkt het een verkeerd
  wachtwoord: je gaat je inloggegevens controleren die nooit zijn opgeslagen.
  Zo'n mislukte schrijfactie meldt zich nu, met erbij wat er straks gebeurt
  ("de verbinding blijft om je wachtwoord vragen"), zodat je het spoor volgt
  dat ergens heen leidt. Los van de melding over een mislukte prefs-schrijf,
  want de gevolgschade is een andere.
- **Aankruislijsten in de documentatie waren geen aankruislijsten.** De lezer
  in de app kende het `- [ ]`-patroon niet en liet de haakjes gewoon staan, dus
  de checklist voor het uitrollen van de webversie las als "• [ ] Served over
  HTTPS". Precies bij een lijst die je afvinkt terwijl je hem uitvoert, is dat
  het verschil tussen een hulpmiddel en ruis. Er staan nu vakjes, aangevinkte
  vakjes voor `- [x]`, en een schermlezer noemt ze bij naam. De vakjes zijn
  bewust niet aanklikbaar: dit is meegeleverde documentatie, dus een vinkje zou
  nergens naartoe kunnen worden weggeschreven.
- **De melding over de Informatieveiligheidsmodule bleef hangen boven een
  presentatie waar ze niet over ging.** Open je een rapport met
  module-slidetypes terwijl de module uit staat, dan bood OciDeck aan hem aan
  te zetten. Die melding had alleen een *Inschakelen*-knop: nee zeggen kon
  niet, en wachten tot hij vanzelf wegtikte evenmin als je nog aan het kijken
  was. Erger: sloot je de presentatie of wisselde je van tabblad, dan bleef de
  melding staan en beweerde iets over een presentatie die niet meer in beeld
  was.

  De melding is nu een balk bovenin met alle drie de antwoorden: **Naar de
  slide** springt naar de eerste slide waar het om gaat, zodat je zelf kunt
  nagaan of het klopt vóórdat je iets aanzet (kijken sluit de balk niet — je
  keek immers om te beslissen), **Inschakelen** zet de module aan, en het
  **✕** stuurt hem weg. De balk verdwijnt uit zichzelf zodra zijn bewering niet
  meer klopt: je wisselt van tabblad, je sluit de presentatie, of je haalt de
  laatste module-slide weg. Ook de sprong kijkt elke keer opnieuw waar die
  slide zit, want je kunt er intussen slides voor hebben weggehaald.
- **Twee mensen die hetzelfde deck op WebDAV opsloegen overschreven elkaar
  stil.** Het opslaan deed een kale PUT: wie als laatste opsloeg won, en de
  ander merkte pas weken later dat zijn werk weg was. De ontwerpdocumentatie
  verwees al naar een "WebDAV atomic-write guard" als bestaand precedent —
  die bestond niet.

  Bij het ophalen onthoudt OciDeck nu de versieaanduiding (`ETag`) die de
  server aan het bestand hangt, en stuurt die bij het terugschrijven mee als
  voorwaarde. Is het bestand daar inmiddels veranderd, dan weigert de server
  en krijg je de keuze: *Opslaan als* om beide versies te houden, of
  *Overschrijven* om die van de ander te laten vallen. Alleen terugschrijven
  naar precies het bestand dat je opende wordt zo bewaakt; voor een doelpad
  dat je zelf koos valt er niets te vergelijken.

  Servers die geen `ETag` geven kunnen niet gecontroleerd worden. Daar blijft
  het gedrag zoals het was — zonder bescherming, maar ook zonder dat opslaan
  vastloopt.

### Added
- **De privacycontrole kijkt nu ook naar afbeeldingen.** Een foto waarop iemand
  herkenbaar staat is een persoonsgegeven, ook zonder naam erbij — en de
  tekstscanner kon dat per definitie nooit vinden: die leest `mem:11162735-…`.
  Draait volledig op je eigen machine met een meegeleverd model van 232 KB.

  **Aanwezigheid, nooit identiteit.** Het model levert per gezicht een kader,
  vijf punten en een score; OciDeck houdt alléén het aantal over en gooit de rest
  meteen weg. Er wordt niets opgeslagen, geen sjabloon berekend, niets vergeleken.
  Dat onderscheid is de reden dat dit geen biometrische verwerking is (EDPB
  Richtsnoeren 3/2019 §74-76) — een privacytool die gezichtssjablonen aanlegt om
  je vóór gezichtssjablonen te waarschuwen, maakt precies het probleem waar hij
  voor waarschuwt.

  De melding zegt bewust *gezicht* en niet *persoon*: iemand van achteren, in
  profiel, met zonnebril omlaag kijkend of met het hoofd buiten de uitsnede wordt
  gemist. Omdat hij daardoor structureel ondertelt en nooit overtelt, staat er
  "minstens N" in plaats van een exact klinkend getal. En een afbeelding in een
  formaat dat niet te lezen is — HEIC, de iPhone-standaard — meldt *niet
  gecontroleerd*, nooit *niets gevonden*.

  Eigen schakelaar onder *Instellingen → Veiligheid*: dit is de zwaarste controle,
  en hem uitzetten laat de tekstcontrole gewoon draaien.
- **Een melding zegt nu ook wáár ze zit.** De privacyscanner wist allang precies
  waar een bevinding stond — veld, fragment, begin- en eindpositie — maar die
  kennis sneuvelde op weg naar het kwaliteitspaneel. Wat je overhield was
  "Slide 5 · Privacy — persoonsnaam (B…r)": genoeg om te weten dát er iets is, te
  weinig om het te vinden. Het paneel zet het veld er nu bij ("Opsomming 3"), en
  klikken op een melding selecteert het gemelde stuk tekst in het editorveld.
  Springen naar een melding werkt daarbij ook in opsommingen, waar de meeste
  tekst staat en dus de meeste bevindingen landen.
- **Een aparte privacybadge op de thumbnail.** Privacy zat in de kwaliteitsbadge
  gevouwen, dus hetzelfde oranje bolletje kon contrast betekenen, of
  tekstdichtheid, of een BSN in de tekst. Wie een deck nakeek op
  persoonsgegevens kon niet zien wélke slides daarover gingen. Privacy heeft nu
  een eigen badge met het PrivacyKat-merkteken, ernaast in plaats van erin.
- **Klik op een badge om te lezen wat er gevonden is**, en dubbelklik om te
  beslissen: op een gekleurde badge accepteer je, op een grijze draai je die
  acceptatie terug. Bij *leave out* en *accept + warn* doet dubbelklikken
  bewust niets — dat zou zwart gelakte persoonsgegevens terugzetten in je export
  zonder dat iemand erom vroeg.
- **Kwaliteitsproblemen zijn per slide te accepteren.** Een titelbeeld dat met
  opzet rustig contrasteert, een tabel die nu eenmaal veel rijen heeft: daar viel
  niets over te zeggen, dus bleef de badge oranje en leerde je vooral dat badges
  te negeren zijn. Accepteren maakt de badge grijs, houdt de meldingen leesbaar
  en haalt ze uit de export-gate. Round-trippt als
  `<!-- ocideck_quality: accept -->`.
- **Elke WebDAV-server kan nu een bron zijn, niet alleen Nextcloud.** Wat als
  "Nextcloud" in de instellingen stond was altijd al gewone WebDAV: PROPFIND,
  GET, PUT, MKCOL. Eén ding was Nextcloud-eigen, het pad
  `/remote.php/dav/files/<gebruiker>`, en dat sloot alle andere servers uit.

  Bij *Instellingen → Opslag → WebDAV* kies je nu het servertype. Bij
  **Nextcloud of ownCloud** verandert er niets: je vult de server-URL in en het
  pad wordt afgeleid. Bij **Andere WebDAV-server** valt er niets te raden, dus
  ís het pad dat je in de server-URL zet de WebDAV-wortel. De app-wachtwoordtip
  verdwijnt dan, want die voorziening bestaat alleen bij Nextcloud.

  Bestaande bronnen blijven werken zonder dat je iets hoeft te doen; die lezen
  als Nextcloud, want dat waren ze.

### Fixed
- **`vog` vond de vogels.** De trefwoordmatcher was een kale substring-zoekopdracht
  zonder woordgrenzen, waardoor "De vogels vliegen over het weiland" een
  strafrechtelijk gegeven meldde en "medicatie-expertise" een gezondheidsgegeven.
  Er zit nu een woordgrens omheen, met twee modi: korte termen (`hiv`, `ggz`,
  `vog`) matchen alleen als héél woord, langere op woordbegin met een vrij
  achtervoegsel — want de Nederlandse morfologie is suffigerend.

  Datzelfde gebrek werkte ook de andere kant op: de lijst bevatte de verbogen vorm
  `verdachte`, waardoor "wordt verdacht van diefstal" — de gebruikelijkste
  formulering van precies het geval waar artikel 10 over gaat — volledig gemist
  werd. De stam staat er nu.
- **Een zwart blok dat niets verborg.** Op een slide met redactie werd "Jan had een
  diagnose bij de huisarts" tot "Jan had een ████████ bij de huisarts": het
  trefwoord ging weg, er werd niets gevoeligs verborgen, en "Jan" bleef staan. De
  ontvanger concludeerde uit het blok dat daar iets stond. Een aanwijzing wordt nu
  alleen weggelakt als het bereik is verbreed tot de hele mededeling — dan is het
  gegeven niet het woord maar de uitspraak.

### Changed
- **Een geaccepteerde bevinding verdwijnt niet meer spoorloos.** Wie een
  privacybevinding accepteerde, zag daarna nérgens meer dat er iets gevonden
  wás: de melding ging uit het paneel én de badge van de thumbnail, en die slide
  zag er daarna precies zo uit als een slide waarop niets staat. Accepteren was
  daarmee hetzelfde geworden als verbergen. De badge blijft nu staan en wordt
  grijs. Het paneel blijft wél stil — daar hoort een genomen beslissing niet
  meer te zeuren.
- **De opslagwijze heet WebDAV in plaats van Nextcloud** — in de lijst met
  opslagwijzen, in de menu-items (*Openen vanaf WebDAV*, *Opslaan naar WebDAV*)
  en in de foutmeldingen die naar het instellingenscherm verwijzen. Nextcloud
  was de naam van één server voor iets dat het protocol beschrijft.
- **Opslag staat onder één kop in de instellingen.** De bibliotheken en de
  exportmap stonden onder "Algemeen", Nextcloud had een eigen tabblad en git nóg
  een — wie wilde weten waar zijn presentaties konden staan, moest dat op drie
  plekken bij elkaar zoeken. Het staat nu onder *Instellingen → Opslag*, in de
  volgorde waarin je het vraagt: eerst wáár je werk bewaard wordt (bibliotheken,
  exportmap), daarna lángs welke weg het daar komt.

  Die laatste is een lijst met een regel per opslagwijze — deze computer,
  WebDAV, git — met de stand van zaken ernaast, en je klapt er een open om
  hem in te stellen. "Deze computer" staat er met opzet bij, ook al valt er
  niets in te stellen: een lijst met alleen de netwerkwegen wekt de indruk dat
  opslaan op je eigen schijf iets bijzonders is in plaats van het gewone geval.
  Een opslagwijze die er later bij komt wordt een regel in die lijst, geen
  tabblad erbij.

### Fixed
- **De statusregel van een opslagwijze liep achter op het typen.** Hij bleef
  "Niet ingesteld" melden terwijl de server er vlak boven al was ingevuld.
  Dichtgeklapt is die regel het enige wat je van een opslagwijze ziet, dus als
  hij tijdens het invullen niet klopt, klopt het onderdeel niet.
- **Zoekresultaten kunnen niet meer naar het verkeerde tabblad springen.** De
  verkeerde sprongen zelf waren al rechtgezet door de zoekindex te hernummeren;
  wat hier verandert is dat de fout niet meer kán ontstaan. Een zoekingang wees
  naar een volgnummer, en niets koppelde dat getal aan een tabblad — een tabblad
  ertussen schuiven verschoof stilzwijgend de betekenis van elk nummer daarna.
  Ingangen wijzen nu op naam, dus er is geen nummer meer dat kan verschuiven.

### Added
- **Een slide die klein wordt gerenderd door zijn buren zegt dat nu zelf.** De
  pagina's van een gesplitste reeks delen één lettergrootte — die van de volste
  pagina — zodat een lijst over meerdere slides niet halverwege van formaat
  verandert. Daar zit een valkuil in: staat er één pagina in de reeks die veel
  voller is dan de rest, dan trekt die alle andere mee omlaag. Een korte slide
  met vijf bullets kan zo op 20% van de ontwerpgrootte belanden terwijl zijn
  eigen inhoud 85% toelaat, en de gewone dichtheidscontrole zweeg daarover: die
  kijkt naar de tekst óp de slide, en die was prima.

  De melding komt nu te staan bij de slide die te klein rendert, met beide
  formaten erbij en een verwijzing naar de pagina die het veroorzaakt. De knop
  **Haal volle pagina uit de reeks** knipt die pagina er aan beide kanten uit:
  hij komt op zichzelf te staan en de rest van de reeks krijgt zijn eigen
  grootte terug. Er wordt niets verplaatst en niets samengevoegd — alleen de
  voortzettingsmarkeringen gaan om, dus één keer ongedaan maken zet het terug.
  De volle pagina houdt zijn eigen meldingen en fixes; losmaken vertelt OciDeck
  dat de pagina niet bij de lijst hoort, het maakt de pagina niet korter.

  Omdat dit de melding is die je juist niet gaat zoeken — de slide op je scherm
  ziet er kapot uit terwijl er niets mis is met zijn eigen tekst — staat de knop
  ook in de editor-kopregel, als **Repareer slide** naast de Kwaliteit-chip. Hij
  verschijnt alleen zolang de slide die je bewerkt wordt meegetrokken, en de
  tooltip draagt de volledige uitleg. Alle andere fixes blijven in het paneel.
- **De voortzettingsvlag is nu een gewone instelling in de editor.**
  `continuesSplit` bepaalde hoe groot je tekst werd weergegeven, maar ontstond
  alleen als bijproduct van "Splits slide" en was daarna nergens meer te zien of
  te wijzigen — behalve in de Markdown. Bulletslides (één kolom, twee kolommen,
  bullets + afbeelding) hebben nu een schakelaar **Voortzetting van vorige
  slide**, zichtbaar zodra de vorige slide er een reeks mee kan vormen. De
  ondertitel noemt wat het kost — je deelt één lettergrootte met de volste
  pagina van de reeks — want dat is de reden dat je hem zou willen uitzetten.
  Zet je de slide om naar een type of liststyle die geen reeks kan vormen, dan
  wordt de vlag gewist in plaats van onzichtbaar te blijven staan.
- **Een bevinding kan nu ook een mobiele zwakheid aanwijzen (MASWE).** Naast het
  CWE-veld staat een MASWE-veld met een eigen zoeker over de gebundelde lijst.
  Beide mogen naast elkaar: een mobiele zwakheid verwijst zelf ook naar een CWE,
  dus de bevinding wordt in beide talen leesbaar. In het rapport verschijnt de
  zwakheid als aanhaling met een link naar de OWASP-pagina, en op de dia als
  label naast het CWE-label.

  Twee keuzes die je merkt bij het gebruik. De zoeker zet zwakheden waarvan de
  uitleg bij OWASP nog niet is geschreven onderaan en markeert ze, zodat je niet
  verrast op een lege pagina belandt. En anders dan bij CWE vult het kiezen géén
  beschrijving in: die tekst is bij OWASP nog concept, en dat als jouw bevinding
  in een klantrapport laten belanden zou niet kloppen.
- **De mobiele zwakhedenlijst (OWASP MASWE) zit erin, met de koppeling naar
  CWE.** Elke MASTG-test verwijst naar een zwakheid; die zwakheden zijn er nu
  ook, inclusief het CWE-nummer waar ze op uitkomen — zodat een mobiele
  bevinding zowel in de mobiele als in de algemene taal te leggen valt. Bij de
  gebundelde standaarden staan nu ook MASTG en MASWE vermeld.

  Twee dingen die eerlijk gezegd moeten worden over deze lijst. Drie kwart van
  de zwakheden is bij OWASP zelf nog niet uitgeschreven; die staan er wél in
  (ernaar verwijzen is gewoon juist — je haalt een lijst aan, geen handleiding)
  maar ze zijn gemarkeerd, zodat je weet dat de toelichting bij de bron nog dun
  is. En MASWE brengt geen genummerde versies uit, dus wat wordt vastgelegd is
  de **datum** van de momentopname. Dat is een zwakkere aanhaling dan bij WSTG
  of MASTG, en het staat er zo bij in plaats van dat er een versienummer bij
  wordt verzonnen.
- **Mobiele pentests krijgen hun checklist: OWASP MASTG zit erin.** Tot nu toe
  kon je een scope-object wel als *mobiel* aanmerken — met MASTG als standaard —
  maar viel die checklist niet te vullen; alleen de webkant (WSTG) was gebundeld.
  Nu staan de 186 tests van **MASTG v2.0.0** erin, apart voor Android en iOS,
  omdat een mobiele test zelden beide raakt en een lijst waarvan de helft niet
  van toepassing is toch wordt weggeklikt. De testlijst komt uit de herbouwde
  v2-uitgave van 30 juni 2026; de tests die OWASP daarbij heeft ingetrokken en
  de nog ongeschreven plaatshouders zitten er bewust niet in — die zouden een
  controle beloven die niemand kan uitvoeren.
- **Vastleggen welke hulpmiddelen bij het onderzoek zijn gebruikt.** Bij
  *Presentatie-info* noteer je per regel een tool met versie, publieke
  referentie en een korte beschrijving — precies de drie dingen die MIAUW-eis
  4.8.2 vraagt. Met *Bijlage hulpmiddelen invoegen…* in het `…`-menu maak je daar
  in één klik een echte bijlagetabel van, in de taal van het **rapport** (niet
  die van je interface, zodat een Nederlandse tester geen Nederlandse
  kolomkoppen in een Engels rapport krijgt). Ontbreekt bij een tool de versie,
  de referentie of de beschrijving, dan zegt OciDeck dat erbij — zonder je tegen
  te houden.

  De eis zelf blijft iets dat je zelf bevestigt. OciDeck maakt de bijlage
  makkelijk, maar kan niet vaststellen dat hij daarna nog klopt: je kunt de
  slide bewerken of verwijderen. Alleen de tester kan verklaren dat de bijlage
  volledig is, en een vinkje dat dat automatisch zou beweren is er geen.
- **Een rapport legt nu vast tegen welke standaarden is getoetst — met versie.**
  Bij *Presentatie-info* vul je de gebruikte standaarden in, met een knop die de
  versies invult die deze versie van OciDeck meedraagt. Die versies worden
  **bevroren** in het bestand: een rapport uit dit jaar dat je volgend jaar
  opent, blijft zeggen waartegen er destijds echt is getoetst, ook als OciDeck
  inmiddels een nieuwere standaard meelevert. Dat maakt meteen zichtbaar wanneer
  er iets veranderd is: bij *Afronden & verzegelen* meldt OciDeck het als een
  standaard sinds het onderzoek is bijgewerkt — geen blokkade, want tegen een
  oudere versie toetsen is legitiem, maar het hoort geen verrassing achteraf te
  zijn.

  MIAUW-eis 4.3.2 blijft wél iets dat je zelf bevestigt. Dat stond hier
  aanvankelijk anders — de eis werd automatisch afgevinkt zodra je standaarden
  had vastgelegd. Dat was onterecht: 4.3.2 vraagt om een overzicht *in de
  managementsamenvatting*, en de vastlegging in het bestand komt niet in de
  slides terecht die de klant krijgt. Een compliance-vinkje mag niet afgaan op
  iets dat in de levering ontbreekt, dus de eis staat weer op handmatig
  bevestigen. De vastlegging en de verouderingsmelding blijven gewoon werken.
- **Zichtbaar welke versie van elke standaard erin zit — en een poort die merkt
  wanneer die achterloopt.** OciDeck draagt referentiedata mee (OWASP WSTG,
  MITRE CWE, het MIAUW-schema, de CVSS-specificatie). Welke versie dat was, stond
  tot nu toe alleen in proza verspreid over code en documentatie, en niets
  controleerde het — zo kan een gebundelde standaard jarenlang verouderen zonder
  dat iemand het merkt. *Instellingen → Over* toont nu per standaard de versie,
  wat er precies van gebundeld is, de licentie en de bron. Daarnaast vergelijkt
  `make deps-check` die versies met de bron en meldt wat achterloopt. **Elke**
  gebundelde standaard wordt echt bevraagd — OWASP via zijn releases, MITRE via
  de CWE-API, FIRST door te kijken of er al een nieuwere specificatie is
  gepubliceerd — zodat een nieuwe versie niet in stilte voorbij kan gaan. Bij CWE
  controleert de poort meteen of de gebundelde lijst even veel zwakheden bevat
  als de bron zegt, want een half geregenereerde bundel is een stillere fout dan
  een verouderde.
- **In a git repository, a changed chart now reads as a changed number.** Chart
  data is stored as its own file next to `deck.md`, on a fixed path, so editing
  one cell shows up in the history as that one cell. It is deliberately kept out
  of the shared image pool: paths there are content hashes, so every edit would
  land as a brand-new file and orphan the previous one — no diff to read at all.
  A version you released carries its data along too, so comparing two versions
  compares their numbers instead of two empty charts. A data file that cannot be
  fetched leaves the chart empty and says so, rather than passing for a chart
  that never had numbers.
- **Chart data moves out of the presentation file by itself.** A chart with
  forty rows used to bury hundreds of numbers in the `.md`. On save, a chart
  that still carries its data inline is now given a file of its own in `data/`
  and the presentation keeps only a reference — so existing presentations
  convert the first time you save them, with nothing to do and nothing to
  notice. The file is named after the chart's title and keeps that name
  afterwards, even if you rename the chart, so its history stays readable. A
  chart you have not entered numbers in yet gets no file, and copying a chart
  slide gives the copy its own file rather than letting the two overwrite each
  other. Data files this deck wrote and no longer uses are cleaned up on save;
  anything else in `data/` is left alone.

  Because storing the data separately is now automatic, importing a CSV no
  longer asks whether to keep it in the slide or as a file — one of those two
  answers could no longer be honoured.
- **A chart can keep its numbers in a separate file, without giving up the
  grid.** A chart with forty rows used to bury hundreds of numbers in the
  presentation file, which made the markdown hard to read and its version
  history useless. Such a chart can now keep its data in `data/<name>.json`
  next to the deck, leaving only a reference behind — and unlike before, it
  stays fully editable. Type in the grid and the file is rewritten when you
  save; edit the file in a spreadsheet instead and the app picks it up when the
  deck next opens. Linking a chart used to make it read-only, because there was
  no way back to the file and an edit would quietly disappear at the next save.

  The two directions do not fight. Saving only rewrites a data file whose
  numbers you actually changed in the app, so an edit made elsewhere while the
  deck was open is still there afterwards. If both sides changed, the app wins —
  it holds what you last saw — and the clash is reported rather than swallowed.

  Colours, title and min/max stay with the slide, never in the data file, so the
  file can be replaced wholesale without the chart losing its look. New files
  are JSON; a deck that already links a `.csv` keeps getting CSV, since
  something outside the app may point at it. A missing or corrupt data file
  leaves the chart as it was instead of blanking it.
- **Search across every deck in the repository, not just the open one.**
  *Zoeken in alle decks…* in the `…` menu searches every deck in the git
  repository and tells you exactly where each hit sits: which deck, which slide,
  and the line it is on. Pick one and that deck opens. If a deck could not be
  read, you still get the hits from the rest — with a note naming the deck that
  was skipped, because a search that is quietly short is worse than one that
  admits it. The same when there are more hits than fit: it says so instead of
  cutting the list in silence.
- **See which decks use which image — and what nothing uses any more.**
  *Afbeeldingen in de repository…* in the `…` menu lists every image in the
  shared pool with the decks that reference it. Images pulled from the current
  text but still present in a released version are shown as exactly that, not as
  junk: deleting one would break a version someone already presented. At the
  bottom, the images nothing references any more — a proposal, not a verdict,
  since another branch may still use them. If any deck or released version could
  not be read, that list is not shown at all: an unreadable deck could be the one
  user of an image, and there is no undo for a deletion. The overview only tells
  you; removing an image is still a deliberate manual act.
- **GitHub and GitLab now work too, not just Forgejo/Gitea.** *Settings → Git*
  gained a **forge type** you pick alongside the server URL, and everything the
  git storage does — opening, saving, concept branches, review, merging, version
  tags, comparing — works the same on all three. The differences are real and
  hidden on purpose: the three disagree about how to commit several files at
  once, how they authenticate, how they number merge requests, and how they
  detect that someone else got there first. One caveat worth knowing: on GitLab
  the file browser cannot show file sizes, because its listing does not carry
  them.
- **Two people editing one deck no longer take turns — concurrent edits are
  merged.** If someone else saved while you were working, saving used to bounce
  you back with "reload and try again". Now the two edits are merged: everything
  that can be resolved automatically is (they changed one slide, you changed
  another; you both made the same change; one of you only reordered), and the
  save goes through with a note that their work came along. Only slides you both
  changed *differently* — or where one deleted what the other edited — come back
  as a choice, one slide at a time, with your side kept until you decide.
  Nothing is ever discarded on either side. The merge works per slide rather than
  per line of text, because a text merge would leave conflict markers in
  `deck.md` and an unparseable deck is exactly what you cannot be shown while
  choosing. One safeguard worth naming: the deck's classification becomes the
  stricter of the two, so a merge can never quietly drop someone's TLP
  escalation. On desktop with native `git` the same thing happens, but
  with git doing more of the work: it finds the real common ancestor, merges the
  rest of the tree itself, and records a proper merge commit — so the history
  shows what actually happened instead of a flattened overwrite.
- **Editing a git deck now happens on a concept branch, and you release it for
  review.** Saving a deck opened from git no longer commits straight to the main
  branch: the first save of an editing round starts a dated *concept* branch
  (`decks/<naam>/<datum>`) and every save lands there — durable and offline-safe
  on both the REST and native-git planes, and you never have to name or pick the
  branch. When the round is ready, **"Uitbrengen ter review…"** in the `…` menu
  opens a pull request from your concept to the main branch so it can be reviewed
  before it goes out. That step is gated by the classification policy, fail-closed
  and *before* anything is pushed: unlike the export ceiling it weighs the
  strictest TLP across the whole deck, so a single `TLP:RED` slide in an otherwise
  unclassified deck stops the release.
- **Merge a reviewed concept and record the version — "Concept mergen…" and
  "Versie vastleggen…".** Once the review is done, *Concept mergen…* merges the
  pull request into the main branch (optionally cleaning up the concept branch)
  and re-bases your tab onto main, so the next edit starts a fresh round. *Versie
  vastleggen…* then marks the version you presented with a release tag
  (`decks/<naam>/vX`) on the main branch — which is exactly what *Versies…* lists.
  Recording a version passes the same fail-closed classification gate as
  releasing for review (weighed on the strictest TLP in the deck), so a version
  can never be tagged past its classification ceiling. Both work on every plane,
  since pull requests and tags are the forge's job.
- **Open an earlier released version of a deck — "Versies…".** For a deck opened
  from git, the `…` menu now lists the versions that were released of it (the
  `decks/<naam>/vX` tags), newest first. Pick one and it opens **read-only** — a
  snapshot to look at, not a target to save over, so reviewing last quarter's
  deck can never overwrite this quarter's work. Like every other open from a
  forge, the version passes the same import gate before it is shown. Works on the
  web too, since versions are a forge listing rather than something native `git`
  has to resolve.
- **See what changed between two versions — "Vergelijken…".** From the versions
  list you can now pick two releases and see exactly what happened between them:
  which slides were added, removed, changed or moved. Because a deck has no slide
  IDs, slides are matched on content — identical ones find each other even after
  a reorder, and a *reworded* slide reads as one change rather than an addition
  plus a deletion. For a changed slide, "Verschillen" puts the two versions side
  by side with the differing fields called out.
- **New chart type: horizontal stacked bar.** The stacked bar chart can now be
  laid on its side — one bar per label with the series stacked left-to-right.
  Like the horizontal bar it suits long category names, and it keeps the
  part-to-whole reading of a stacked bar; a wide enough segment prints its value.
  Available in the chart type picker, the variants dialog, the preview, the
  presenter, PDF, PPTX, and the HTML export's inline SVG, with a screen-reader
  text alternative like every other chart.
- **See a deck's commit history — "Git history…".** For a deck opened from git on
  a machine with native `git`, the `…` menu now shows its timeline: every commit
  that touched the deck, newest first, each with its author, date, and a badge
  marking whether it is already on the forge or still waiting locally to push.
- **On desktop with `git`, saving a deck is now a real local commit — genuine
  offline history.** When native `git` is present, OciDeck keeps a real clone of
  the repository: opening reads from it, and saving writes the deck as an actual
  `git commit` and pushes it. That commit is durable and offline — edit on a
  plane, make ten saves, and ten commits are waiting to push when you land,
  nothing queued or approximate. On reconnect *Sync now* pushes them. If someone
  moved the branch while you were away, your commit is kept locally and the push
  is held rather than overwriting their work (a real merge comes in a later
  phase). Images ride along in the shared pool exactly as before. On the web, or
  a desktop without `git`, the REST path from the previous releases is used
  unchanged. The `git` token is delivered to the subprocess through its
  environment only — verified never to land in `.git/config` or the command line.
- **On desktop, OciDeck now detects a native `git` and shows it under *Settings →
  Git*.** This is the groundwork for real offline history (a genuine local commit
  per save, ten-commits-on-a-plane): the app finds your installed `git` (≥2.19),
  reports the version, and falls back to the REST path when it is absent — so
  nothing changes on web or on a machine without `git`. The detection is careful
  on macOS: it checks for the Xcode command-line tools first, so it never trips
  the `/usr/bin/git` shim into popping an install dialog, and it never probes at
  startup — only when you open the git settings. Every `git` invocation is
  hardened (no shell, the token supplied through the environment and never in the
  command line or `.git/config`, no inherited config or hooks, a timeout).
- **Saving to git now survives losing your connection.** If the save cannot
  reach the forge, the deck's text is kept in a durable local working copy and
  the deck joins a queue — you are told "saved, syncs when you're back online"
  rather than shown an error. The queue survives closing the app. It empties on
  the next successful save and via *"Nu synchroniseren"* in the `…` menu; a deck
  that lands updates its tab so the next save does not trip over a stale base.
  An image you add while offline is pooled and committed when the queue syncs, so
  a reconnect gets the whole deck — as long as you have not closed the app in
  between (an unsaved in-memory image does not survive a restart, the same limit
  a saved `.md` with in-memory images already has). Your text is always safe.
- **A deck can now be saved back to a git repository — "Opslaan naar git…",
  beside "Opslaan naar Nextcloud".** Saving writes the deck as one commit: the
  markdown plus its images, and the images go to the shared pool exactly as
  opening reads them back, so the round-trip is lossless and a picture five
  decks share is stored once. Saving a deck that came from git offers its own
  name and updates in place; a new deck is published by choosing a deck name
  (it becomes `decks/<name>`). If someone else moved the branch since you opened
  it, the save is refused as a conflict rather than overwriting their work — you
  reload and save again. Works on the web too (git is plain https+JSON). Video
  and audio do not go along yet; you are told when a deck has them. The offline
  queue (save now, sync on reconnect) follows next.
- **Images in a deck opened from git now load, and are stored once per
  repository.** A picture used by five presentations is one file in the
  repository, named after a hash of its own bytes — so adding it again cannot
  duplicate it. The bytes are re-hashed on the way in: a repository claiming a
  file is a given image has to prove it.
- **Decks can be opened from a git repository (Forgejo/Gitea).** A folder gives
  you the latest version of a presentation; a repository keeps every version
  you ever saved. This is the first slice: read-only opening, configured under
  *Settings → Git repository*, with the token in the OS keychain rather than the
  settings file. A repository is untrusted input like any other source, so the
  markdown passes the same safety scan as a URL import — coming from your own
  forge does not make it trusted. Unlike Nextcloud this also works on the web
  build. Saving, versions and releases follow; see
  [`docs/design/GIT_STORAGE.md`](docs/design/GIT_STORAGE.md).
- **The bundled finding templates now exist in all 30 languages.** A tester
  writing a Dutch report pulled in an English skeleton and rewrote it by hand;
  the templates are OciDeck's own starter content, so they follow the reader.
  They follow the **report's** language (Settings → Presentation properties), not
  the interface's — writing an English report from a Dutch UI still gives you an
  English skeleton, and a report with no recorded language gets English.
  Only the prose is translated. A template's section headings stay English
  because they are what the parser matches on, its CWE line is a MITRE citation,
  and its severity is FIRST's published band label — the same label the finding
  itself stores, so a translated one would contradict the finding rendered right
  beside it. A "Dutch template" is Dutch prose in a fixed skeleton, and a test
  now proves that: it parses every template in every language and fails if any
  section comes back empty.

- **A report can record the language it is written in, and findings now read in
  that language.** MIAUW requires the report language to be agreed and recorded
  before a pentest starts (EIS 2.3), but a deck had nowhere to put it — so the
  requirement sat in the compliance overview as a permanently open item you could
  only ever tick by hand. It is now a field under Presentation properties, stored
  in the front matter as `language`, and EIS 2.3 is derived from it like any other
  content-based requirement (18 of the 88 are now automatic, up from 17).
  It also fixes something that reached the client. Every finding rendered its
  section headings — *Description*, *Confirmation (reproduction)*, *Possible
  impact*, *Recommendation* — in English no matter what language the report was
  written in, and because PDF/PPTX export rasterises the same previews, a Dutch
  MIAUW report went out with English headings. The heading now follows the
  **report's** language, not the interface language: a Dutch tester writing for an
  international client still gets an English report from a Dutch UI. The Markdown
  keeps its stable English anchors, so the file round-trips exactly as before and
  a deck that records no language renders precisely what it always did.

- **The About screen names where the project comes from.** Right above "Waar
  komt de naam vandaan?" it now says that OciDeck is a by-product of the Pilot
  Informatieautonomie, with a link to www.pilotinformatieautonomie.nl.
- **Style profiles can be exported and imported as a file.** A profile could
  only travel inside a deck (in the front matter); there was no way to download
  one or load one in. Two buttons next to the profile name (Settings →
  Presentation style) now write the profile you are editing to a
  `.ocideckstyle` file — on the web build it downloads — and read such a file
  back. So a house style can be handed to a colleague or kept in a repository
  without a deck around it. An import is added as a *new* profile and selected;
  an existing name is never overwritten, the import gets a unique name instead.
  A **custom logo travels inside the file** (embedded as base64), so the profile
  arrives complete, while the local path to your logo is deliberately left out —
  it means nothing to the receiver and would leak your user name. Built-in logos
  stay a reference. The file is JSON in a small envelope with a format marker and
  version, so an arbitrary `.json` is refused rather than half-read
  (FILE_FORMAT §3.3). An imported profile is treated as untrusted input and goes
  through the same hardened gate as a profile from a deck: colours are validated
  to strict `#RRGGBB` and fonts are whitelisted. On the web build a restored
  custom logo lives only until the page reloads (the browser has no persistent
  file storage) — everything else in the profile keeps working.
- **Group headings ("tussenkoppen") inside a bullet list.** A single bullets
  slide can now be split into visually separated groups without splitting the
  slide: add a heading with **Tussenkop toevoegen**, or turn any row into one
  with the divider button beside it. A group heading renders as a bold accent
  label above a thin rule; leaving its text empty makes a **wordless divider** —
  just the rule between two groups. Headings carry no bullet, checkbox or number
  and don't count toward the list, and they work on plain, numbered and checklist
  lists as well as the two-column and bullets-with-image layouts. They travel with
  the deck in the `.md` (an inline `U+E010` marker on the list item, so the file
  stays valid Marp) and round-trip losslessly. Splitting an over-full slide (the
  **Split slide** density fix) now breaks between groups, so a heading is never
  stranded with a stray bullet at the foot of a page.
- **Opening a security report while the Informatieveiligheid module is off now
  offers to turn it on.** When you open a presentation that contains security
  slide types (a finding, findings overview, checklist, scope matrix or
  sign-off) while the module is disabled, a one-time snackbar with an **Enable**
  action appears — so the module is discoverable from the deck that needs it,
  not just buried in settings. The prompt shows once per open (never while you
  edit) and only when the module is off; the slides render either way, so this
  is purely a discovery aid.
- **The privacy check now detects addresses, Dutch postcodes and labelled
  names.** A street with a house number (`Kalverstraat 12`) and a Dutch postcode
  (`1234 AB`) each surface as a hint; when they sit close together on a slide
  they escalate to a warning, because a postcode plus a house number pins one
  home address. Person names are detected only behind a salutation (`dhr.`) or a
  label (`naam:`) — never by guessing — and stay a hint. All three are redacted
  on slides set to *redact*, in every field including the title. A bare name in a
  title (with no label) still needs the manual `[[…]]` marking.
- **New quality fix "Explanation to notes" for overcrowded bullet slides.**
  Splitting bullets keeps all the text on the slide; this fix removes it. For a
  bullet shaped like *label : explanation* — split on a colon, a spaced hyphen or
  the first full stop, when the explanation is substantial — it keeps just the
  label on the slide and moves the full original line to the speaker notes. The
  content is not lost, only relocated, and one undo brings it back.

### Changed
- **De gebundelde standaarden zijn voortaan met één commando bij te werken.**
  WSTG werd tot nu toe met de hand overgetikt; dat maakte een versiesprong duur
  genoeg om uit te stellen — precies waardoor MASTG een half jaar bleef liggen.
  `make refresh-catalogs` haalt WSTG, MASTG en MASWE bij de bron op en
  genereert ze opnieuw. Bewust géén onderdeel van de gewone controle: een
  standaard bijwerken verandert waar een rapport naar verwijst, en dat is een
  beslissing, geen bouwstap.
- Twee WSTG-categorieën heten nu zoals de gids ze zelf noemt — *Testing for
  Error Handling* en *Testing for Weak Cryptography* — in plaats van de
  ingekorte vormen die de handmatige lijst had. Het gaat om materiaal van
  derden, dus dat wordt gereproduceerd en niet bijgeschaafd. De testlijst zelf
  is ongewijzigd: dezelfde 97 tests met dezelfde titels.
- **Evidence thumbnails no longer decode at full resolution.** A finding's
  evidence thumbnail is 44 pixels wide, but the screenshot behind it is usually
  a few thousand — and the whole bitmap went into memory. A report carrying
  dozens of evidence items paid for that many times over. The thumbnail now
  decodes at four times its display width, which is well above any realistic
  pixel ratio, so nothing looks different. Signatures are deliberately left
  untouched: they are small drawn images that must stay sharp as proof of
  signing.
- **The licence documentation now says what is actually bundled.**
  `LICENSE_COMPLIANCE.md` stated that no OWASP WSTG checklist content shipped, so
  CC-BY-SA-4.0 share-alike was not triggered — while the module had bundled the
  97 verbatim WSTG test titles from the day it landed. It even named the
  condition for its own undoing ("should verbatim checklist content be bundled
  later, it must ship with attribution + share-alike"); nobody came back to it.
  The same lapse left the full 969-entry MITRE CWE asset out of the table
  entirely, while listing only the 41-entry curated floor.
  OWASP WSTG is now recorded with **attribution to the OWASP Foundation, a link
  to the licence and to the guide, and share-alike** — as are the full CWE asset,
  the CVSS band labels reproduced from FIRST's rating scale, and the finding
  templates. What is bundled is stated plainly: the WSTG **checklist index** (id,
  title, category), not the guide's substance. Share-alike travels with that
  dataset; the app bundles it as a collection, so the EUPL-1.2 code around it is
  unaffected.
  A test now derives the table from the app's own catalogue registry, so a sixth
  dataset cannot reach a user without its terms being written down first.

- **The Informatieveiligheid module is simply on or off now — no provisioning.**
  Enabling it used to run a fetch-verify-cache pipeline: an ordered mirror list,
  a pinned hash, a local cache, a manual pack import for air-gapped machines, and
  a card explaining which step had failed. None of it did anything. No mirror was
  ever live, so every run fell back to a pack bundled with the app; the pack held
  a second copy of the CWE list nobody read back (the module's data has always
  been compiled in); and the whole run existed to flip one boolean. The pipeline,
  the pack (**288 KB off every download, for everyone**) and its buttons — *Nu
  bijwerken*, *Opnieuw proberen*, *Pakket importeren*, *Gegevens opschonen* — are
  gone. The switch reveals the module at once, offline, and no longer needs the
  outbound-traffic consent. The reference data travels with the app version, so
  upgrading OciDeck is the only update path — which is what actually happened
  before, minus the ceremony. The card still lists what is available locally, in
  counts, from the catalogues the app really queries. **The module now reaches
  the network nowhere**: its entry in the outbound-sink allowlist is dropped, not
  relaxed.

- **Checklists no longer sit under Extensions in the settings sidebar.** The
  pane had ended up between Uitbreidingen and Over OciDeck, which read as if
  checklists were part of the extensions. The sidebar order is now Checklists,
  Uitbreidingen, Documentatie — the extensions last, with their documentation
  right after them.
- **The privacy feature is now called OciWacht.** "Privacy Shield" was a
  confusing name — it collides with the (invalidated) EU–US Privacy Shield
  data-transfer framework, which this feature has nothing to do with. The
  privacy scan, the per-slide dispositions and the enforced egress boundary are
  now branded **OciWacht** throughout the app and the documentation (design spec
  renamed `docs/design/OCIWACHT.md`). Behaviour is unchanged; this is a rename.
- **The PrivacyKat mark now appears where privacy-sensitive risks are pointed
  out, not only as an egress marker.** The shield was designed as the product's
  mark for personal data, but it only ever showed up next to "this deck came from
  a URL" and a couple of settings switches — never on an actual privacy risk. Now
  it does: the recipient-facing **PERSONAL DATA** badge on a slide (the *accept +
  warn* disposition) is the PrivacyKat shield rather than a generic tip icon, and
  every **privacy row in the quality panel** carries the shield instead of the
  plain warning triangle — so a personal-data finding is distinguishable at a
  glance from a contrast or text-density one.

### Fixed
- **`1,234` from a spreadsheet is now read correctly instead of dropped.**
  Whether that is one thousand two hundred thirty-four or one-point-two-three-
  four depends on where the file was written, and one cell cannot say. A file
  usually can: a `10,5` elsewhere in it proves the comma is a decimal mark, a
  `10.5` proves it groups thousands, and `1.234,56` settles itself because the
  last mark is always the decimal one. That evidence is now gathered across
  every value before any of them is read — and nothing is inferred from your
  language or region, because a file from a colleague abroad does not follow
  either. When the file truly does not say (every comma followed by exactly
  three digits) the import **asks**, showing what your own numbers become under
  each reading; closing that question cancels the import rather than choosing
  for you.
- **A Dutch Excel export finally charts as itself.** A spreadsheet whose decimal
  mark is a comma writes CSV with **semicolons**, and OciDeck read the whole line
  as one cell: labels like `Q1;10` and no series at all. The separator (comma,
  semicolon or tab) is now detected per file. That also settles `10,5`: with a
  semicolon between the fields a comma cannot be separating them, so it can only
  be a decimal mark, and the value reads as ten and a half.
- **A value that cannot be read is now said out loud instead of drawn as 0.**
  `12%`, `€ 1.000`, or a bare `1,234` in a comma-separated file — that last one
  is 1234 in one country and 1.234 in another, and guessing would mean inventing
  a number. It still charts as 0, because a chart has to draw something, but the
  import now names how many values were unreadable and shows the first few
  verbatim so you can find them in the source file. A silent 0 is the more
  damaging failure: it looks exactly like a real measurement of zero. An empty
  cell stays unreported — a short row means "no value here", which is a
  statement, not a mistake.
- **Chart CSV from Excel no longer falls apart on quoted values.** A cell like
  `"Amsterdam, NL"` or `"1.234"` was split on the comma inside the quotes, so the
  row gained a cell, every value after it shifted one column, and the chart drew
  the wrong numbers — without a single warning. Quoted fields are now read per
  RFC 4180: commas inside quotes belong to the field, and a doubled `""` is one
  literal quote. CSV without quotes parses exactly as it did before, trimming
  included. One limitation is deliberate and documented: a line break inside a
  quoted field is still not supported, since a chart row is a label plus numbers
  and has no use for one.
- **A chart whose data lives in a separate file no longer loses that data when
  saved to git, opened on the web, or shown on the beamer.** A chart slide can
  keep its numbers in a file next to the deck (`data/…`) and leave only a
  `source` reference in the markdown. That reference is a path relative to a
  project folder on disk — and three places handed the deck to something that
  has no such folder, while writing only the reference. Saving to git committed
  the reference without the numbers, so after a push the data was gone for good,
  with no warning. A package opened in the browser ignored its `data/` members,
  and a deck downloaded as a single `.md` left with a path that pointed nowhere;
  both opened with empty plots. The audience window on a second screen showed
  the same empty plot. In all four cases the numbers now travel along with the
  deck. Charts that keep their data inline — the default — were never affected.
  Each case has a regression test, including one proving a `source` that points
  outside the package with `../` is still refused.
- **Screen readers now announce the image buttons by name.** The paste, copy and
  clear buttons in the image picker bar, and the reset button on the zoom
  slider, were wrapped *in* a tooltip rather than carrying one. Flutter attaches
  that tooltip to a surrounding node, so the button itself arrived at the screen
  reader unnamed — while the row beside it was announced as "Afbeelding plakken
  uit klembord". Each button now carries its own name (WCAG 2.2 SC 4.1.2).
  Nothing changes on screen. A new test walks the semantics tree and fails on
  any button that offers no name, so this cannot quietly return.
- **A bullet that is simply a long sentence can now be moved to the speaker
  notes too.** *"Uitleg naar notities"* only appeared on a bullet shaped like
  *label: explanation* — so the very line that most needed to leave the slide, a
  full sentence with no colon anywhere in it, was the one line the fix would not
  touch. Such a bullet now keeps its first five words on the slide and sends the
  whole line down to the notes. The label reads like a clipped sentence
  sometimes; nothing is lost, so it can be tidied by hand.
- **The slide rail no longer throws "setState() called during build" after the
  deck changes.** Riverpod computes a derived value only when something reads
  it. With nothing reading the privacy chain, a deck change left it stale
  without scheduling a refresh — and the next widget to read it was a thumbnail
  being built, so the refresh landed in the middle of a build and Flutter
  refused it. The tab now keeps its own chain subscribed for as long as it
  lives, so a deck change is worked through before the frame instead of inside
  it.
- **Moving a bullet's explanation to the speaker notes now takes its context
  along.** *"Uitleg naar notities"* left the label on the slide and moved the
  full line down, but wrote the lines as a flat list: the "tussenkoppen" they
  sat under were dropped and nested bullets lost their indent. A speaker reading
  back "geregeld via de centrale IAM-oplossing" had no way to tell which part of
  the slide it belonged to. Each heading now comes along once, above the first
  line that falls under it, and every line keeps its indent level.
- **"Split slide" now simply fills pages of eight bullets and leaves the rest on
  a last page.** It used to balance the pages and weigh how many bullets
  physically fit at natural size — and that measurement was the problem: with
  long bullets only two or three fit, so the page size collapsed and one slide
  fell apart into a stack of five. The split now counts bullets and nothing
  else: twenty become 8/8/4, eleven become 8/3. The one concession to taste is
  that it never leaves a runt behind — one or two bullets is not a slide, so a
  list that would end that way falls apart evenly instead: nine become 5/4, not
  8/1. A checklist keeps its roomier twelve, a two-column slide
  seven per column, and a slide that is not over-full at all still halves on
  request — that is what *"In tweeën splitsen"* in the slide menu asks for.
  Page breaks no longer step aside for a group heading, so a "tussenkop" can now
  land at the foot of a page: the price of a split you can predict before you
  press it.
- **The export-readiness status now shows the PrivacyKat mark for privacy
  warnings.** The "N privacy findings without a choice" chip (and "Privacy
  blocks export") in the status bar carried a generic warning icon instead of
  the PrivacyKat shield used on the slide badge and in the quality panel. It now
  shows the same mark, so the personal-data warning reads as one brand
  everywhere.
- **An embedded video that will not play now says why.** Every failure mode of a
  YouTube/Vimeo embed used to collapse into the same dead rectangle — a blank
  grey box indistinguishable from "still loading", and from "online media is
  off". There was no error handling at all: no `onWebResourceError`, no
  `onHttpError`, no reaction to the player's own error events. So "the video does
  not load and I cannot see why" was exactly right — there was nothing to see.
  Now the slide shows the reason: **the owner disabled embedding** (by far the
  most common; the clip can only be watched on the platform itself), the video is
  **gone or private**, the **link is invalid**, or there is **no connection to
  the source** — each with its own icon and text. A valid embed that is merely
  slow shows a spinner, so loading no longer looks like failure. (The separate
  macOS bug where embeds never started at all was fixed in #251; this is the
  feedback that was missing on top of it.)
- **The privacy check is now visible everywhere the quality of the deck is
  shown.** The scanner was running, and its findings did land in the quality
  panel — but three places that rebuild the "quality" view by hand quietly left
  privacy out, so the same deck disagreed with itself depending on where you
  looked. Now aligned:
  - The list of **performed checks** on a green quality bar named contrast, alt
    text, media files and text density — four checks — and silently omitted the
    privacy check, ninety-plus rules on personal data, special categories and
    secrets. Open a pentest report, read no word about privacy in the quality
    list, and the honest conclusion is that it was not checked. It was. And the
    mirror case: when the privacy check is switched **off**, it is no longer
    listed under "performed checks" (that would be a lie under that heading) —
    the panel says instead that it is off. A green bar with a complete-looking
    list, while nothing was actually looked at, is the most dangerous state this
    panel can show.
  - **Thumbnail badges** watched only the four original checks, so a slide whose
    only problem was an IBAN in the text looked perfectly clean in the rail. It
    now carries a badge like any other issue. (Same edit fixed a pre-existing
    bug: the badge keyed on *warnings*, so a slide with only an **error** — a
    contrast error with no accompanying warning — showed no badge at all. The
    worst slide in the deck was the only one unmarked.)
  - The **status bar** export-readiness chip knew about the save, classification
    and quality gates but not the privacy gate. A deck full of undecided personal
    data, with the privacy gate set to *block*, showed a green *Ready to export* —
    the status bar promising the opposite of what the export would do. It now
    counts the undecided findings and turns red when the gate blocks, in the same
    order as the other gates (privacy before quality). The gate itself was already
    enforced in the export dialog; only the at-a-glance status was blind to it.

### Changed
- **Notes blocks now open only when there is something in them.** *Speaker notes*
  and *User notes* both started expanded, always — two tall empty editors under
  every slide, on the majority of slides that have no notes at all. They now start
  collapsed when the field is empty and expanded when it is not, so the block is
  open exactly when it has something to say. Opening or closing one by hand sticks
  while you stay on that slide; stepping to the next slide asks the question again
  for that slide, which is the only way the default can stay true as you move
  through a deck.
- **Slide settings, redesigned.** The block had grown one feature at a time, and it
  showed: seven settings in one flat list with three different row shapes mixed
  together — a full-width audio card, checkboxes with the control on the *left*,
  dropdowns with the control on the *right*. Nothing lined up. Now the settings are
  grouped by the question you are actually asking (*on this slide*, *while
  presenting*, *classification and privacy*), every row has the same shape with the
  control on the right, the auto-advance duration only appears once you switch it
  on, and a setting you cannot use (a logo toggle with no logo in the style profile)
  is not shown at all rather than shown greyed out.

  The groups are **cards that sit side by side** when the editor column is wide
  enough, and stack back when it is not. A settings row spanning the full width put
  the label at x≈290 and its switch at x≈1330 — a thousand pixels of nothing between
  two things that belong together. Right-aligning the control is right; doing it
  across the full width is not. Inside a card the eye travels a couple of hundred
  pixels instead of a thousand, the alignment survives, and the horizontal space is
  finally used *for* something instead of given away.

  Collapsed, the header now badges **everything that deviates from the default** —
  not just TLP. That was not only ugly but a gap: *leave out of display and export*
  decides what the recipient gets, and you could not see it without expanding the
  block. So you did not expand, and so you did not see it.
- **The promise is now written down where it matters.** *The check does not
  guarantee that everything is found; it reduces the chance that personal data
  leaks out unintentionally.* That sentence now appears in the privacy statement
  (which is also the consent gate), under the setting itself, and — most
  importantly — in the **export dialog, always, including when nothing was
  found**. That quiet case is the dangerous one: a deck with findings warns you
  by itself, but a deck without findings shows a green *Ready to export*, and
  that reads as "clean". It says no more than: we found nothing.

### Fixed
- **A YouTube video never played on macOS — and the app blamed your settings.**
  The embed host built its `WebViewController` in one cascade, and
  `setBackgroundColor` sits in the middle of it. On macOS that call is not
  implemented (`opaque is not implemented on macOS`), so it threw, the cascade
  died, and the controller was never assigned. What you saw was a dead grey
  panel with the word *Video* — indistinguishable from a blocked source. So the
  conclusion was reasonable and wrong: *online media must be off*. It was on;
  the player had simply never been built. The background colour was cosmetic
  (the embed HTML already paints itself black), so it is now a best-effort call
  outside the cascade. YouTube and Vimeo embeds play on macOS.
- **A YouTube link is not an error, so it is no longer red.** The source chip in
  the video editor labelled a YouTube URL with the *danger* colour — the red this
  product uses, elsewhere, to mean "something is wrong here". A perfectly valid
  link therefore looked broken, right next to a quality panel where red really
  does mean broken. The chip only says which *kind* of source this is; an online
  source is an online source, and it now shares the same teal as the others.
- **A special-category datum is a statement, not a word.** Redaction blanked only
  the keyword that fired, which left this on screen:

  > Marieke de Vries reported sick with a ████████

  The name is still there, the sick note is still there, and `diabetes-` is still
  there literally. Nothing had been removed — a word had been covered, which is
  exactly the mistake this whole design exists to prevent. Now, once a health,
  criminal, religious or union datum is traceable to a person on the same slide,
  the redaction takes the whole line. The same goes for a case number: "Case
  ████ against M. de Vries" still tells you she is a suspect.

### Added
- **Phone numbers (`contact.phone`).** In international form (`+CC` followed by
  the national number) they are validated against the list of assigned ITU country
  calling codes and a valid E.164 length — a real check, so it becomes a proper
  warning. A national
  number needs a separator (`06-24681357`); a bare run of digits needs a context
  word, because `0417164300` on its own is just as likely to be an old bank
  account number. Dates, ISBNs, amounts and the reserved "drama" ranges that films
  and manuals use are excluded by design.
- **Two versions from one source.** When a deck holds findings, the export dialog
  asks who the export is for. **Full** removes only what you marked *leave out* —
  the client or auditor gets a report they can actually verify against. **Redacted**
  removes everything the check finds, including on slides you accepted, because
  "this room may see it" is not the same as "everyone may see it".

  This is the heart of the pentest-report case. Without the choice you would have to
  pick *between* those two, and in practice the full version always wins — because
  that is the one that has to go out the door.

  The profile lands in the filename (`report-geredigeerd.pdf`). Not cosmetic: the
  most expensive mistake here is sending the full copy to the wider circle, and a
  mix-up should be something you can *see* rather than something you have to
  remember. The redaction manifest follows the profile too, and verification now
  takes the profile as an argument — measuring a redacted manifest against the full
  yardstick would flag an honest report as suspect, which is exactly the false alarm
  we removed from the seal.

  The export dialog picks the profile without ever touching the source deck: it holds
  a *factory* that hands out one `ExportBundle` per profile, and that closure lives in
  the shell where the source legitimately is. The projection boundary holds.
- **Forty email addresses in a table is not forty findings — it is a membership
  list.** One email address on a slide is a contact detail. Forty in a table is an
  exported list, and that is a different conversation entirely: with the GDPR, with
  your data protection officer, and with the people on that list.

  The scanner already saw those forty, forty times over. But forty separate notices
  are exactly what a user learns to click away — the panel overflows and the message
  drowns in the noise. What was missing was the insight sitting on top.

  Two signals, and the first is by far the stronger: a **table header** that names
  the column ("Naam", "E-mail", "BSN", "Date of birth"). That is a pasted CSV, and
  the header says in so many words that the cells below are personal data. Nobody
  labels a column "BSN" when it holds no BSNs, which makes it close to
  false-positive-free. The second is cruder: the same rule firing three or more
  times on one slide, which catches the pasted list that is not a table.

  The bulk notice sits **on top of** the individual findings, not instead of them,
  and it reports the *count* rather than the values — that is what you need to know.
  One example row under a header is not a list, and a plain contact slide (name,
  email, phone of one person) is left alone.
- **Structural leaks — the hiding places a generic PII scanner misses.** A user
  path (`/Users/jan.jansen/…`) simply gives away a name, and it is most often in
  the path of an image you dragged in, travelling along into the Markdown and the
  HTML export. Plus tokens in URL queries (a presigned S3 link, an Azure SAS
  token), personal data in query strings, share links with built-in access
  (SharePoint, Drive, Dropbox — whoever has the link has the file), and `mailto:`
  addresses.

  These are not personal data *in* the text, but they leak all the same.

  Reporting and redacting are deliberately different here: **a path is reported but
  never redacted**, because a redacted path is a broken image. Rename the file or
  move it — that is a decision only you can make.

  And an embedded data-URI is reported as an honest admission rather than an alarm:
  we cannot look inside it, and it could just as well be a screenshot of a CRM
  screen full of names. Saying nothing would leave you believing we had seen
  everything.

  What keeps the family usable is the generic-account exclusion: `/home/runner`,
  `/Users/admin`, `C:\Users\Public`. Without it every CI log and every Docker
  example fires, and the rule is switched off within a day.
- **Your own details are the sender, not a finding.** Put your name, email
  address, phone number or your organisation's domain under *Settings → Security*
  and they stop being reported — and stop being redacted.

  This was the single most predictable false positive left. Your address in the
  footer, your name on the title slide, your number on the contact slide: without
  this list, nearly *every* deck fires, and it fires on the one slide that is
  always there.

  It is deliberately a list rather than a heuristic. Guessing who the author is —
  from the front matter, from the OS account — is sometimes wrong, and when it is
  wrong it suppresses a *real* finding. A list is never wrong: it contains exactly
  what you put in it.

  The matching is exact or by domain, and nothing in between. `politie.nl` covers
  `j.jansen@politie.nl`, but not `j.jansen@nietpolitie.nl` — a loose substring
  match would have covered that too, which is a whole different organisation
  quietly silenced. That trap was caught while writing the tests, not after.
- **An export gate that does not punish personal data — only *unnoticed* personal
  data.** Before writing a file, OciDeck tells you how many findings you have not
  decided about, and how many you did handle (accepted, warned, redacted). You can
  go past it deliberately; under *Settings → Security* you can also silence it, or
  block the export until every certain finding has a choice.

  The distinction is the whole design. A police briefing where everything is
  deliberately accepted goes through without a peep. Warn on that and the user
  learns exactly one thing: that this dialog can be clicked away. Informational
  hints never hold up an export either — we said ourselves we are not sure about
  those, and blocking on them would discredit the gate immediately.

  The hard block is enforced at the export chokepoint, not just in the dialog: a
  gate that lives only in a dialog is not a gate. There is a test that calls
  `ExportService` directly, with acknowledgement set, and still gets refused.
- **Switch off a single rule instead of the whole check.** Click *Never report this
  rule again* on a finding and it stops firing; the disabled rules appear as chips
  under *Settings → Security*, one tap from coming back.

  This escape hatch matters more than it looks. Without it, the only way out of a
  rule that misfires on your content is switching off the whole check — and that is
  a one-way door in practice: once it is off, nobody turns it back on.

  A disabled rule is **not redacted either**, which is the exact opposite of the
  master switch, and deliberately so. The master switch says *don't bother me* — not
  a judgement about your content, so a deck set to redact keeps redacting. Switching
  off a rule says *this rule is wrong about my content*, and honouring that means we
  must not black it out. Someone who disables the BSN check because their order
  numbers trip it does not want those order numbers blacked out in the export.

  It also unlocks the three heaviest article-9 categories — political opinion, ethnic
  origin, sexual orientation — which now ship but start out **off**. Their keywords
  appear far too often in ordinary business language for anything else, but the choice
  belongs to the user, not to us.
- **Special categories of personal data (GDPR art. 9/10) — and the trick that
  makes them usable.** Health, criminal-law, religion, trade-union membership,
  biometrics, genetic notation (dbSNP `rs334`, HGVS `p.Val600Glu`), and the Dutch
  prosecution case number.

  Keyword detection for these categories is normally worthless, and not subtly so:
  a slide *about* the GDPR says "health data" without containing any. A privacy
  lesson, a DPIA deck, a processing register — all full of exactly the words we are
  looking for. Warn on those and the check is switched off within a day.

  So a keyword on its own reports nothing that interrupts you. It becomes a real
  warning only when the **same slide** also carries something that identifies a
  person — a BSN, a national number, an email address. Then the special-category
  detail is traceable to a person, which is precisely what article 9 protects.

      slide about privacy law:   "health data"                     → silent
      case slide:  "BSN 728398242 — diagnosis established in March" → warning

  An API key does not count as a person, and neither does an IBAN: they say nothing
  about *who*. And the escalation is per slide, not per deck — a BSN on slide 1 must
  not pull the word "diagnosis" on slide 12 upwards, because those two never sit
  side by side for the recipient.

  Politics, ethnicity and sexual orientation are deliberately **not** shipped yet:
  a diversity-policy slide is *about* ethnicity without containing ethnic data, and
  without a per-rule off switch that false-positive rate is indefensible. Better no
  rule than a rule that discredits the whole check.
- **European identification numbers — fifteen countries, and the scanner got no
  louder.** Belgian rijksregisternummer, German Steuer-ID, French NIR, Spanish
  DNI/NIE, Portuguese NIF, Polish PESEL, Italian codice fiscale, Croatian OIB,
  Bulgarian EGN, Romanian CNP, Swedish personnummer, Finnish henkilötunnus,
  Estonian isikukood, UK NHS number and NINO.

  Turning on twenty checksums at once is defensible precisely *because* they are
  checksums: a checksum does not cost precision, it buys precision. Enabling the
  Croatian OIB does not make the scanner shout, it makes it wider. The noise never
  lived in the self-validating numbers — it lives in the handful without one, and
  those (UK NINO, Swedish personnummer, NHS number) carry a mandatory context word,
  exactly like the BSN.

  The interesting part is what a checksum *doesn't* do. The Bulgarian EGN uses a
  mod-11, which lets roughly one in ten random ten-digit numbers through — the same
  trap as the elevenproof. It fired on a 32-bit ARGB colour value in a JSON example
  in OciDeck's own documentation. These numbers embed a **birth date**, so that is
  validated too: month 94 does not exist. Caught by the false-positive corpus test,
  which scans our own docs for exactly this reason.
- **Secret scanning: API keys, tokens, private keys, passwords.** Vendor tokens
  carry a fixed prefix — `AKIA`, `ghp_`, `xoxb-`, `sk_live_` — and that prefix is
  the proof, so this family is close to false-positive-free without needing a
  checksum. Plus PEM private keys, database URLs with an inline password, and
  plain-text passwords in fifteen languages.

  A JWT is not recognised by its shape but by **decoding its header** and checking
  for an `alg` field. `eyJ` is just base64 for `{"`, so shape alone would fire on
  any embedded JSON; decoding takes the false-positive rate to near zero — worth
  it, because a JWT is itself a container full of personal data.

  What keeps it usable is the placeholder gate. A slide that explains *how* to
  configure a key must stay quiet: `api_key: <your-key>`, `password: changeme`,
  `sk_test_…`, and AWS's own documented `AKIAIOSFODNN7EXAMPLE` all pass without a
  peep. So does `const token = null;` — a code slide full of null assignments
  would otherwise discredit the scanner in one go. That last one was caught by a
  test, not by foresight.
- **A privacy check that reads your slides for personal data — on this device.**
  Identification numbers, contact details, bank accounts. Findings appear in the
  quality panel next to the contrast and readability checks; on by default,
  switchable under *Settings → Security*. Nothing is sent anywhere, and a finding
  never shows you the value it found — only a masked fragment (`j…l`). A privacy
  check that lists the citizen service numbers it found has moved the problem,
  not solved it.

  The interesting part is what it *doesn't* warn about. A BSN is validated by the
  elevenproof, but roughly **one in eleven random nine-digit numbers passes that
  test** — order numbers, invoice numbers, customer numbers. Warn on all of those
  and the check gets switched off within a week, after which it detects nothing at
  all. So a BSN needs the checksum **and** a context word nearby to become a
  warning; without context it stays an informational hint that interrupts nobody.
  A corpus test throws a thousand random numbers at it and asserts zero warnings —
  while confirming the findings *are* there, as hints. The context gate suppresses
  the interruption, not the detection.

  Same reasoning for the known-fake registry: the example IBAN from every banking
  manual, the official test-BSN range (`999999xxx`), `123456782` (which passes the
  elevenproof — it was chosen to), the card schemes' test numbers, `example.com`
  addresses. A deck that lights up red on its own demo content destroys trust in
  every other finding. The false-positive corpus test also scans OciDeck's own
  documentation, for exactly that reason.

  It is an aid, not a guarantee: no OCR on images, no linked files, nothing
  without a recognisable pattern. A slide with no findings is a slide in which
  *we* found nothing.
- **Redaction — and it actually leaves the data out.** Wrap text in double square
  brackets (`[[Jan de Vries]]`) and OciDeck removes it from everything it shows
  and exports, while your Markdown keeps the original. The point is what it is
  *not*: it is not a black rectangle drawn over text that is still in the file.
  The characters are replaced at a single boundary — `PrivacyProjection` — before
  anything is rendered or written, so the PDF has no text layer under the blocks,
  the PPTX speaker notes (plain text in the file, invisible on the slide) do not
  carry the value, the HTML source does not contain it in the embedded Markdown
  or behind a CSS rule, the document metadata does not either, and a screen
  reader cannot read it because it never reaches the widget tree. A test exports
  a deck with a known value and hunts for it in every one of those places,
  unzipping the PPTX rather than scanning raw bytes — deflated XML would hide the
  string even if it were there. The replacement has a fixed width: mirroring the
  original length would tell the reader what kind of value was removed.

  The boundary is a *type*, not an agreement. Receiving surfaces take an
  `AudienceDeck`, which only the projection can mint, and `check-conventions`
  fails if one of them ever accepts a raw `Deck` again. The real risk here is
  human — someone adds a fourth export format next year and hands it the source —
  and a convention in a design document does not stop data; a compile error does.

  One consequence worth naming: a slide with a redaction can no longer be
  table-edited *during a presentation*. The presenter writes a live edit back as
  a whole slide, and it only ever saw the blocks. A surface that cannot see the
  data may not write it back either.

- **A privacy badge marks decks that came from a URL.** When a deck is fetched
  from a web address (the URL import, or a `?deck=…` share link on the web
  build), the status bar shows an **“Extern”** badge — a “PrivacyKat” mark in the
  EU blue/yellow palette. Opening such a link makes your device contact that
  server; the badge makes that provenance visible (hover for the source host)
  without blocking the open. Decks opened from your own disk carry no badge.
  Translated into every interface language.

### Security
- **The CVE list can now live on your own machine, so looking one up tells nobody
  anything.** *Settings → Beveiliging → Lokale CVE-database* downloads the whole
  CVE List V5 corpus (the official CVE Program list, via GitHub) and indexes it
  locally. After that, **Zoek CVE…** searches on your device and **no search term
  leaves it** — which is the entire point: for a pentester, *which* vulnerability
  you are looking up is often the most sensitive thing they know.

  It does not need the online-lookup switch — offline search needs no permission,
  because it sends nothing. And it deliberately does **not** fall back to the
  internet when a local search comes up empty. That fallback would be the obvious
  convenience, and it would leak exactly the term you kept local, at exactly the
  moment you were searching for something unusual. A test pins that: a local miss
  must not reach the network.

  The price is real and is stated **before** the button, not after: ~550 MB to
  download, ~1.5 GB of disk while it builds (the release is a zip inside a zip),
  a few hundred MB left behind, and ten to thirty minutes. You confirm those
  numbers, watch a progress bar that names the phase it is in, and can cancel.
  Cancelling or failing leaves nothing half-installed — a partial index is thrown
  away and any working one is left alone.

  Desktop only. On the web the section is not shown at all, rather than offering a
  button that could not work.

- **The online CVE switch now says what it costs you.** Turning on *CVE opzoeken
  (online)* sends your search term to the configured mirror — and, because the
  lookup falls through on a miss, the same term then goes to **ENISA and MITRE**
  as well. For a pentester, *which* vulnerability you are looking up is often the
  most sensitive thing they know: it discloses what is being investigated, and by
  implication where the weakness is. That was already true, and was explained
  nowhere near the switch. A PrivacyKat badge now sits next to it, and hovering
  it spells out exactly that. It blocks nothing — it makes the trade visible
  while the choice is still yours.

- **The RFC 3161 timestamp panel no longer shows a "verified" badge for a
  token it hasn't verified.** The panel displayed a green check and
  "Getijdstempeld op &lt;time&gt;" whenever the token's message imprint matched
  the seal — but the TSA's CMS signature and certificate chain are deliberately
  not checked in-app, so that time is the token's *claim*, not a verified fact
  (anyone holding the deck can mint a token with an arbitrary time and a
  matching imprint). The green trust badge is replaced with a neutral clock
  icon, and an explicit caption now spells it out — "The TSA signature is not
  verified in-app; only the hash matches." — so the panel no longer overstates
  what was checked. Translated into every interface language.
- **The HTML export's CSP now pins every network-capable resource, not just
  scripts and fetches.** The export already blocked remote scripts (nonce) and
  `connect-src`/remote `img-src`, but with no `default-src` the `media-src`,
  `font-src` and `form-action` directives were unset and therefore unrestricted
  — so a `<video src="https://…">`, a hostile `@font-face { url() }` or a
  planted `<form action="https://…">` that survived DOMPurify could still call
  home when the exported file was opened. All three are now pinned to local
  sources (`'self' data: blob: file:` / `'none'`). MathJax is tex-svg (no web
  fonts) and the bundled CSS carries no `url()`, so this never bites a real
  export.
- **The web fetch-proxy fails closed by default.** `server/fetch-proxy`
  served *any* requester when `OCIDECK_PROXY_ALLOWED_ORIGINS` was unset, so an
  operator who deployed it without that variable ran an (SSRF-guarded, but
  otherwise open) fetch relay for arbitrary public URLs. With no allowlist it
  now serves only the app's own same-origin fetch (proven by `Sec-Fetch-Site`,
  which a cross-site page cannot forge); the previous open behaviour is still
  available but must be chosen deliberately with `OCIDECK_PROXY_ALLOW_ANY=1`,
  which also logs a startup warning.
- **The Mermaid SVG sanitiser can no longer be split apart by a control
  character.** `sanitizeMermaidSvg` refused `javascript:`/`data:` URLs with a
  plain `startsWith`, but a URL parser ignores ASCII whitespace and control
  bytes while reading a scheme — so `java<tab>script:`, a newline (which XML
  normalisation or a `&#10;` reference can plant) or a leading NUL all slipped
  through, and `vbscript:` was not checked at all. The scheme test now strips
  every C0 control and space before matching and also rejects `vbscript:`. This
  is a defence-in-depth layer (the in-app renderer runs no script and the HTML
  export re-sanitises with DOMPurify under a nonce CSP), but the layer now
  actually holds its stated contract.
- **CI runs with a least-privilege token and no lingering credentials.** Both
  workflows now declare `permissions: contents: read` (they only read the repo
  and upload artifacts, which use the separate Actions runtime token), so a
  compromised dependency or action can't push, open PRs or edit issues with the
  job token. Every `actions/checkout` also sets `persist-credentials: false`, so
  the auth token is not written into `.git/config` for a later step to reuse.
- **The coverage gate now actually runs — and can finally see an untested file.**
  `make coverage` was in no aggregate target, and the CI workflow that ran it
  cannot fire on the Forgejo remote, so the coverage floor was enforced by
  nobody. `make check` now depends on it. The floor also had a hole: lcov only
  records files a test imported, so a file no test touches is not 0% — it is
  outside the fraction entirely, and adding a wholly untested file moved the
  percentage not one hair. `--require-instrumented` enumerates `lib/` from disk
  and fails on any non-baselined file that is in no test. Floor raised 65% → 73%
  (actual: 74.2%).
- **The network guard now sees every way to open a socket.** It scanned for
  `HttpClient(` alone, so its own promise — "a new raw client fails this test" —
  was untrue for `package:http`, `dio`, `Socket`, `SecureSocket`, `WebSocket`
  and `RawDatagramSocket`: an `http.get(deckSuppliedUrl)` added anywhere in
  `lib/` passed every gate untouched. The current code is sound (the desktop
  URL-import is pinned; the one `package:http` caller is web-only), but nothing
  kept it that way. Now it does.
- **Layering is enforced.** `lib/models/` may not import Flutter's UI layer or
  `lib/widgets/` (hard 0); the count in `lib/services/` is ratcheted at today's
  8 and may only shrink. A service should run headless — no widget tree, and
  testable without pumping one.
- **Severity speedometer on findings.** A finding with a CVSS score now shows a
  compact cockpit speedometer next to its header — a green→amber→red gauge with
  the needle at the score — so the reader sees the severity at a glance alongside
  the score badge. It uses the effective score (the CIA-weighted context score
  when the scope object is rated, otherwise the base score) and renders the same
  in the app and in exports.

### Added
- **The security module now says what it actually has.** *Settings →
  Uitbreidingen → Informatieveiligheid* used to report exactly one thing —
  "Gegevens lokaal beschikbaar" — which left open whether that meant a full CWE
  list or an empty shell. It now lists **what is available, in counts**: CWE
  weaknesses, WSTG test cases, MIAUW requirements, CVSS score-table rows and
  finding templates, each with the upstream standard it follows, plus the version
  of the data pack in use.

  The counts come from the catalogues the app *actually queries*, not from what a
  pack claims to contain. That distinction is the point: a reassuring tick over an
  empty list is worse than no tick at all.

  **Nu bijwerken** re-fetches the reference data even when a verified pack is
  already cached — which is exactly when you want to know whether something newer
  exists. Previously that path short-circuited on the cache, so a refresh could
  only ever have been a button that did nothing. The fingerprint check still runs:
  forcing an update means fetching again, not verifying less.

- **You can search the settings.** There are around eighty of them now, spread
  over twelve tabs, and finding one meant knowing which tab a developer had
  filed it under. A search box sits in the settings header: type and you get the
  matching settings with the tab and section they live in; click one and it jumps
  there, scrolls the section into view and flashes it.

  It searches synonyms too, not just what is printed on screen — type `youtube`,
  `vimeo` or `mp4` and you land on **Online media**, which is the setting you
  actually wanted and is not called any of those things. That matters most for
  exactly the people who don't know the app's vocabulary yet.

### Changed
- **A video slide no longer nags for a title or speaker notes.** The
  accessibility nudge that asked every video for a description was excessive: a
  clip that speaks for itself needs no title, and the video editor has no caption
  or alt-text field to silence the tip with — only a title. So it fired on
  essentially every video and could not be answered on its own terms. Images and
  charts keep their description nudge, where there *is* a field to fill in.

- **MIAUW slides use the width better.** The finding, checklist, scope-matrix and
  findings-summary slides had a wide side margin (14% of the slide) that pushed
  content into extra pages. The side margin is narrowed (content grows from
  ~0.86× to ~0.91× of the slide width), the finding paginator is retuned to the
  wider line so a borderline finding stays on one page instead of splitting, the
  checklist/scope coverage bars are widened, and the HTML export now stretches
  tables to the full width and trims the slide padding — fewer pages for the same
  content.

### Fixed
- **Online video did not work, in two different ways at once.** A YouTube, Vimeo
  or `.mp4` link on a video slide was reported as *"Video: bestand niet gevonden"*.
  The missing-media check ran `File(...).existsSync()` over *any* video or image
  path, and the path resolver knows only local paths — so it glued the URL onto
  the project folder (`<project>/https:/youtu.be/…`), found nothing there, and
  called an online source a missing file. The URL gate now sits in front of the
  disk check, so an online source is never reported as missing.

  Separately, and confusingly at the same time, those slides showed *"Online media
  staat uit"* even with the setting **on**. The `allowRemoteMedia` flag is handed
  to each preview by hand and defaults to `false` (fail-closed, deliberately), but
  four surfaces never passed it — including the thumbnail rail, which is the only
  slide preview you actually see while editing. So online media was hard-off in
  the editor no matter what the settings said. The flag now reaches the rail, the
  full-deck preview, play-only mode and the presenter. Export stays fail-closed on
  purpose: an online source is exported as a clickable link, not baked in.

- **Three source files were invisible to `grep` and unreviewable in `git diff`.**
  `tabs_provider.dart`, `slide_dedup_service.dart` and `annotation_codec.dart`
  each held a control character as a raw *byte* inside a string literal (a NUL
  join-separator; SOH/STX/ETX field separators in the annotation fingerprint).
  Dart compiles that fine, but every byte-oriented tool then reads the file as
  binary: `grep` silently skipped all 890 lines of `tabs_provider.dart` — no
  output at all, not "no matches" — and `git diff` rendered changes to
  `slide_dedup_service.dart` as `Bin … bytes` rather than a readable diff. In a
  tool built for security review, a source file that no grep audit can see and
  no reviewer can read is a real hazard. Replaced with the equivalent escapes
  (byte-identical strings, so fingerprints and the file format are unchanged)
  and guarded by `make check-conventions` so it cannot come back.
- **A few remaining interface labels are now localised.** The checklist preview's
  `ID`/`Test` column headers, the audio-play tooltip and the export target-path
  hint now go through the translation layer, so they follow the interface
  language like the rest of the app.

### Added
- **Link a finding to a checklist test.** The finding editor gains a **Gekoppelde
  test (Linked test)** picker listing the tests on the checklist(s) that cover the
  finding's scope object. Picking one records it on the finding (a `**Test:**`
  line, shown as a chip on the finding card) and **writes back** to the checklist:
  the matching row is marked an anomaly and linked to the finding. Changing or
  clearing the choice moves or removes that link. This closes the loop between a
  finding and the test that revealed it (feedback #8). Localised in all interface
  languages.
- **Your own checklist templates.** A new **Checklists** tab under Settings lets
  you create, edit and delete reusable checklist templates (a name, a standard
  label and its test items). Any template can be loaded into a checklist slide
  via a new **Sjabloon laden…** menu in the checklist editor (next to the WSTG
  button), and the per-scope-object generator can pre-fill non-WSTG objects
  (Infra/IoT/…) from a template you pick. Templates are stored in the app
  settings (`customChecklists`), so they persist across decks. Localised in all
  interface languages.
- **Checklists per scope-object.** A `checklist` slide can now be linked to a
  scope-matrix object (a **Scope-object** field in the checklist editor, shown in
  the preview), so each scope element carries its own test list. The scope-matrix
  editor gains **Genereer checklists voor scope-objecten**: one click creates a
  checklist per scope object that lacks one — the full OWASP WSTG list for
  Web/API objects, or an empty checklist titled with the object's derived
  standard (PTES/ISTG/FSTM/MASTG) otherwise. It is idempotent (objects already
  linked to a checklist are skipped) so it is safe to re-run. The link round-trips
  as an `<!-- ocideck_checklist_scope: … -->` comment. Localised in all interface
  languages.
- **The full MITRE CWE list, offline.** The **Kies CWE…** picker now searches the
  complete MITRE CWE weakness list (~940 entries), bundled as an offline asset
  (`assets/cwe/cwe_full.json`, generated by `tool/build_cwe_catalog.dart`) that
  merges over the curated 40-entry floor — so every weakness is findable by name
  or number, with no network. The curated floor keeps its richer
  description/remediation snippets.
- **Look up CVEs online (opt-in).** The finding editor and wizard gain a **Zoek
  CVE…** action that searches a CVE against a source cascade — the configured NVD
  mirror first (by id pattern), then **ENISA EUVD** (which also does keyword
  search) and **MITRE** (exact-id lookup) as fallbacks — and shows each match's
  description + CVSS score; picking one appends its id to the CVE field (the
  finding's CVSS 4.0 vector is never overwritten).
  It is **off by default** and fail-closed: enable **CVE opzoeken (online)** under
  Settings → Security (which also requires your consent), where the mirror base
  URL is configurable (default `https://cveapi.librekat.nl`). The fetch is
  SSRF-pinned and desktop-only (disabled on web). Localised in all interface
  languages.
- **Record retest (hertest) outcomes on findings.** A finding now carries a
  **Hertest** status — *Niet hertest* (default) / *Opgelost* / *Nog aanwezig* /
  *Deels opgelost* — set from a dropdown in the finding editor, with an optional
  retest note. A finding that was resolved after retest shows a green **Opgelost
  na hertest** badge on its card (amber for still-present/partially resolved),
  while its CVSS severity stays visible. The findings summary and the management
  summary always name the retest — **Opgelost na hertest: x** (also 0 when
  nothing was retested) — so "x found, x resolved after retest" is reported; the
  findingsSummary editor refreshes the figure from the deck. Round-trips via a
  `**Retest:**` meta line (language-independent English token). Localised in all
  interface languages.
- **Load the seven PTES phases into a timeline.** The timeline editor gains a
  **PTES-fasen laden (Load PTES phases)** button that seeds the seven
  Penetration Testing Execution Standard phases (Voorafgaande afspraken →
  Rapportage) as ready-to-edit events, non-destructively (matched by title,
  replacing a lone blank starter). Localised in all interface languages.
- **The CVSS/CIA builder now reads in the interface language.** The per-metric
  CVSS 4.0 builder (CVSS-wizard) and the scope object's CIA-rating dropdowns show
  their metric names and values in the interface language (Aanvalsvector,
  Netwerk, Hoog, …); the canonical tokens (`AV`/`N`/`L`/`H`, …) and the English
  FIRST names stay as the on-disk/reference form. Translated in all 30 languages.
- **Guide the CVSS score with a CIA-weighted context score.** Each scope object
  in the **scope matrix** now carries a **CIA rating** (Confidentiality /
  Integrity / Availability, each `H`/`M`/`L` or empty), stored in three new
  `C`/`I`/`A` columns appended after `Note` (older five-column matrices still
  parse). A finding that references a rated scope object gets a **context
  (environmental) score** derived from that rating on top of its base CVSS 4.0
  vector — the weighting lives on the scope object, so re-rating it re-scores
  every finding on it. The finding editor gains a **CVSS-wizard** button (the
  guided per-metric builder, now also available when editing, not only when
  creating) and a scope-object picker sourced from the matrix; the read-out shows
  the base score plus the context score. The context score flows everywhere — the
  finding card, previews and PDF/PPTX export — and the findings-summary and
  management-summary counts use the context severity band. The finding wizard now
  stores the **base vector** (the CIA weighting is no longer baked in). Localised
  in all interface languages.
- **Load the full OWASP WSTG test list into a checklist.** The
  "Uitvoering testen conform standaard" (checklist) editor gains a
  **WSTG-testen laden (Load WSTG tests)** action that fills the list in one click
  with the complete **OWASP WSTG v4.2** checklist — 97 tests across all 12
  categories — instead of typing each test by hand. The standard version is now
  shown (next to the button and written into the standard label, so it appears on
  the slide and in exports). Loading is **non-destructive**: it only appends the
  tests whose id you don't already have, preserving existing rows and their
  statuses, so you can re-load after editing without losing progress. The catalog
  is a bundled, offline dataset (no network), mirroring the offline CWE catalog.
  Localised in all interface languages.
- **Attach evidence to a finding.** The finding editor now has a **Bewijs
  (Evidence)** section: **Screenshot toevoegen** and **Video toevoegen** attach a
  screenshot or a video as evidence. Each piece of evidence becomes its own slide
  right after the finding and joins the same finding group (shares the finding id,
  role `evidence`), so it moves, round-trips in the `.md`, and exports with the
  finding. The section lists the group's evidence with a thumbnail and lets you
  jump to or remove each item; adding evidence requires a finding id, since that
  is what links it to the finding. Localised in all interface languages.
- **Draw a signature on the sign-off page.** Next to the typed signature, the
  sign-off editor and the **Afronden & verzegelen** dialog now offer
  **Handtekening tekenen (Draw signature)** — a pad you sign with the mouse,
  trackpad, touch or stylus. The drawing is stored as a self-contained embedded
  PNG in the deck's visual signature (the existing `ocideck_sig_image` field), so
  it round-trips in the `.md` and is covered by the document seal like the rest
  of the attestation. Wherever the sign-off is shown — the editor preview, the
  presenter, and the **PDF/PPTX export** — a drawn signature takes precedence
  over the typed name. Localised in all interface languages.
- **The sign-off signature now appears in the PDF/PPTX export.** The rasterised
  export previously dropped the deck's visual signature (both the typed name and
  a drawn one), so a sealed report exported without its attestation signature.
  The signature and seal date now travel into the export rasteriser, and the
  drawn image is precached so it paints on the captured frame.
- **Error messages are copyable.** Failure notifications (export, import,
  Nextcloud download/save, and the module card) now carry a **Kopiëren (Copy)**
  action that puts the exact message on the clipboard, and stay on screen a
  little longer so there is time to read and copy them — so a failure can be
  reported or looked up without retyping it. The Informatieveiligheid module's
  status line is also selectable for the same reason. Reuses the existing copy
  strings, so it is localised in all interface languages.
- **The Informatieveiligheid module now works offline, out of the box.** Its
  baseline reference data is **bundled with the app** (as a signed-by-hash asset)
  and provisioned from there on enable — no mirror, no download, no outbound
  traffic, and no consent needed (nothing leaves the device). The bundled pack is
  verified against the fingerprint compiled into the app before use, exactly like
  an import. This replaces the skeleton behaviour where enabling always failed
  with "no source reachable" because no mirror served the pack yet. The manual
  **Pakket importeren (Import pack)** path remains for an air-gapped/updated pack
  and now explains, on the card, what an importable pack is (a `.zip` verified
  against the built-in fingerprint; only a pack matching your app version is
  accepted). Localised in all interface languages (PENTEST_MIAUW §6).
- **Retry a failed module fetch, and a clearer reason when it fails** — the
  *Informatieveiligheid* extension card now offers **Opnieuw proberen (Try
  again)** whenever the module is on but its reference data is not yet present,
  so a fetch that failed because the network was briefly down — or because the
  outbound-traffic consent had not been granted yet — can be re-run in place
  without toggling the module off and on. It sits next to the existing **Pakket
  importeren (Import pack)** recourse and is hidden on the web build, which
  cannot reach a mirror. The "no source reachable" message was also reworded: it
  now states plainly that the data could not be retrieved from any source and
  points to the two recourses, instead of implying the user's own internet
  connection is at fault. Localised in all interface languages (PENTEST_MIAUW §6).
- **Low-contrast warning in the style-profile editor** — *Settings → Colours* now
  shows a live warning beneath any colour whose contrast the deck-level quality
  panel would flag, so you catch the problem while designing the style instead of
  later in a presentation. It is driven by the same `SlideQualityAnalyzer` (and
  your configured contrast threshold), so the two never disagree: body, accent,
  title (against both the title band and section background), table text, table
  header, code, and checklist-marker colours are all covered, amber for a warning
  and red for a hard contrast error. Each warning shows the actual contrast ratio
  inline (e.g. `1.0:1` for white-on-white) and repeats the panel's full message —
  label, ratio and required minimum — as a tooltip. This catches self-defeating
  combinations such as white title text on a white title background, where the
  title-slide heading would otherwise render invisibly.
- **Six new chart types** — chart slides gain **area** (a filled line),
  **horizontal bar** (for rankings and long labels), **combo** (bars plus the
  last series as a line on a second axis, e.g. revenue + growth %), **donut** (a
  pie with the total in the centre), **waterfall** (the first series as up/down
  steps building on a running total) and **heatmap** (a value-coloured grid that
  doubles as a likelihood × impact **risk matrix**). The heatmap is coloured by a
  dedicated, theme-independent sequential **heat** scale — pale→deep-red on light
  slides, dark→bright on dark ones — so it reads as a heatmap rather than taking
  the deck's accent colour; the numeric value is printed in every cell. Each
  renders natively
  (preview, presenter, PDF, PPTX) and as self-contained SVG in the HTML export,
  round-trips through the same `chart` JSON block, animates on enter, and carries
  a screen-reader text alternative. Type names are localised in all interface
  languages.
- **One-click audit dossier** — with the Informatieveiligheid module on and a
  **finalised, sealed** report, the **Auditdossier exporteren** command bundles the
  whole hand-off into one archive (PENTEST_MIAUW §10.11): the ordinary `.ocideck`
  package (report `.md` + assets + evidence images) plus an `AUDIT_DOSSIER.md` index
  that restates the report identity, the seal facts (SHA-512 hash, seal time, RFC
  3161 timestamp presence + how to verify), the management summary, the MIAUW
  compliance tally (Voldaan / Openstaand / Uitgesloten) and the evidence SHA1 +
  SHA-256 hash table. Optionally password-protected with WinZip **AES-256**, so the
  report, its evidence and the hash tables travel together as one encrypted,
  auditor-ready file. Localised in all interface languages.
- **MIAUW report template** — with the Informatieveiligheid module on, the
  new-presentation dialog offers a **MIAUW-pentestrapport** template that
  scaffolds a full MIAUW-conforming report in one step: a cover, the four MIAUW
  parts as section dividers (*Algemeen*, *Plan van aanpak*, *Executie*,
  *Rapportage*), a document-management overview, a sign-off page, a scope matrix,
  a management summary, a research timeline, an example finding, a per-standard
  checklist and an appendix list. The template stays hidden until the module is
  revealed, so the catalogue is unchanged for everyone else (PENTEST_MIAUW §4.1).
  Localised in all interface languages.
- **AI drafting for finding text fields** — with the optional AI backend on, the
  finding editor shows a **Tekst voorstellen (AI)** button under the description,
  possible-impact and recommendation fields. It drafts that field with a local
  model, grounded **only** on the tester's own facts for the finding (title, scope
  object, CVSS, CWE/CVE and the already-filled fields), and a hard guardrail
  **strips any CWE/CVE/CVSS identifier the model invents** that is not already in
  those facts. Draft-only: an AI-drafted field gets an **AI-concept** badge and
  sealing stays blocked until the tester presses **Nagekeken**, so the EIS 1.6
  truthful-reporting signature always covers human-verified text (PENTEST_MIAUW
  §16). Off by default; desktop only. Localised in all interface languages.
- **RFC 3161 trusted timestamp for the seal** — a finalised, sealed report can now
  be anchored in time. The **RFC3161-tijdstempel** command (command palette)
  **exports a request (`.tsq`)** over the SHA-512 seal hash, which the user has
  OpenKAT or any timestamp authority (TSA) timestamp out-of-band, then **imports
  the returned token (`.tsr`)**. OciDeck verifies it **offline** — the token's
  message imprint must equal the seal hash — and stores it in the deck front
  matter (`ocideck_seal_tsr`), showing a "timestamped on …" or "does not match"
  status that is re-checked on every open. OciDeck never contacts the TSA itself,
  and the token is excluded from the sealed content hash (no new dependency; a
  small ASN.1/DER codec does the encoding). PENTEST_MIAUW §8-A2. Localised in all
  interface languages.
- **Management summary derived from the deck** — a **Managementsamenvatting**
  command (command palette) shows a management overview computed live from the
  deck: the number of findings per severity band, how many scope objects were
  tested, and the **standards used** (WSTG / PTES / MASTG / … derived from the
  scope objects' types and the checklists present). It regenerates from the deck,
  so it always matches the report (PENTEST_MIAUW §10.3). Localised in all
  interface languages.
- **Report automation: renumber findings, evidence hashes, scope-coverage gaps**
  (PENTEST_MIAUW §10). The command palette gained **Bevindingen hernummeren**,
  which renumbers every finding sequentially (`F-01`, `F-02`, … in deck order) —
  rewriting each group's shared id and its `F-NN` heading prefix in one undoable
  step (skipped on a sealed deck). **Scope-dekking controleren** opens a panel
  listing scope objects that are in scope but neither tested nor referenced by any
  finding — the "did you test everything you scoped" guardrail. A new evidence-hash
  service computes the MIAUW-required **SHA1** (plus SHA-256) of an artefact and
  builds the appendix hash table. Both new commands are gated behind the security
  module. Localised in all interface languages.
- **MIAUW compliance overview (the 92 EIS)** — a new **MIAUW-compliance** command
  (command palette) opens a gap-analysis panel that scores each MIAUW requirement
  (EIS) as **Voldaan** / **Openstaand** / **Uitgesloten door klant**, grouped by
  the four parts. Content-derivable requirements are checked automatically from
  the deck (every finding carries a CVSS vector / scope / CWE / sections; a
  management summary, scope matrix, checklist, timeline and sign-off are present;
  the deck is sealed); organisational requirements are tagged *Handmatig*. **Every
  requirement is waivable** with a mandatory reason — a gap analysis, never a hard
  gate, that only *warns* when a foundational EIS (1.1, 1.6) is excluded. Waivers
  round-trip in the deck front matter (`ocideck_miauw_waivers`). This first
  increment ships a curated in-repo EIS subset (the always-on offline floor); the
  full 92-EIS schema follows as a provisioned pack (PENTEST_MIAUW §9). Localised in
  all interface languages.
- **Guided finding wizard** — a new finding is now authored through a step-by-step
  wizard (opened from **Slide toevoegen → Bevinding**) instead of a blank slide:
  title → scope object → a **per-metric CVSS 4.0 builder** (dropdown per metric,
  with a live score + severity read-out) → CWE (reusing the offline CWE picker) →
  CVE → the four narrative sections. The CVSS step also takes the scope object's
  **CIA rating** (Confidentiality / Integrity / Availability), which pre-fills the
  Environmental `CR`/`IR`/`AR` requirements so the offered score is **CIA-weighted**
  by default (PENTEST_MIAUW §4.1/§10.5). On finish it emits a whole **finding
  group** — the structured header plus an optional detail and evidence placeholder,
  all sharing one finding id — inserted in one step. Localised in all interface
  languages.
- **Security theme profile with severity colour tokens** — theme profiles now
  carry five **severity colour tokens** (Critical / High / Medium / Low /
  Informational, the FIRST bands) that drive finding cards, CVSS badges and the
  findings-summary chart, so the whole security look is retunable from one place
  (Settings → presentation style → *Severity (bevindingen)*). A new built-in
  **"Security"** profile ships a clean, professional pentest-report style (light
  pages, dark slate title band, red accent) with the standard severity palette.
  Defaults mirror the previous hardcoded colours, so existing decks render
  identically; the tokens travel in the deck's style profile and pass the same
  strict `#RRGGBB` validation as every other profile colour (PENTEST_MIAUW §11).
  Localised in all interface languages.
- **Auto-tag untagged images with a local vision model** — the image library's
  carousel gained an **auto-tag** button (visible only when the optional AI
  backend is on). It walks every image that has **no** searchable tags yet, asks a
  local vision model for a handful of keyword tags in the interface language, and
  saves them to the description sidecar so the picture becomes findable. It only
  fills **empty** descriptions — a human or earlier tag is never overwritten — and
  after a run an **Ongedaan maken** action clears exactly the tags that run wrote,
  so a bad bulk pass is fully reversible. Off by default; desktop only
  (AI_ASSIST §6). Localised in all interface languages.
- **Offline CWE picker with deterministic snippet autofill** — the finding
  editor gained a **"Kies CWE…"** button that opens a searchable picker over a
  bundled, offline catalog of the most pentest-relevant MITRE CWE weaknesses
  (OWASP Top 10 + common web/infra findings). Picking one sets the finding's CWE
  field and, **only when they are still empty**, fills the description and
  recommendation with a short, neutral snippet — a good starting point written
  **without an LLM** that the tester then specialises; it never overwrites text
  already entered. Every entry links back to the canonical `cwe.mitre.org`
  definition. Fully offline; the full 944-weakness list arrives later as a
  provisioned data pack (PENTEST_MIAUW §6/§10.6). Localised in all interface
  languages.
- **Suggest image alt-text with a local vision model** — when the optional AI
  backend is on, the image / two-images / bullets-with-image editors show a
  **"Stel alt-tekst voor (AI)"** button next to the alt-text box. It downscales
  the picture, sends it to a local vision model through the shared `/v1` backend,
  and drafts concise WCAG alt-text in the deck's language, stripping "image of…"
  filler. It is **draft-only**: the text is inserted for review, an existing
  human alt-text is never replaced without confirming, and AI-drafted alt-text is
  marked (`ocideck_ai_assisted`) so **Afronden & verzegelen** stays blocked until
  it is reviewed. Off by default; desktop only (AI_ASSIST §6). Localised in all
  interface languages.
- **AI alt-text is traceable and reversible** — an AI-drafted alt-text shows an
  **"AI-concept"** badge in the editor with a **"Nagekeken"** button that keeps
  the text but clears its AI marker (so it survives the bulk cleanup and no longer
  blocks sealing). A **"Wis AI-alt-teksten"** command (command palette, Ctrl/Cmd+K)
  removes every still-unreviewed AI alt-text across the deck in one undoable step —
  a safety net if a bulk suggestion run goes wrong — while leaving human-written
  and reviewed alt-text untouched. Localised in all interface languages.
- **Image alt-text for screen readers (WCAG 1.1.1)** — image slides now carry a
  dedicated **alt-text** field, separate from the visible caption. The image, two-
  images and bullets-with-image editors gained an *Alt-tekst* box; a screen reader
  now announces the alt-text when set, falling back to the caption and then a
  generic "image" as before. The slide-quality check counts alt-text (or a
  caption) so its nudge clears once either is present. Alt-text is per-usage, so it
  travels in the `.md` as an `<!-- ocideck_image_alt: … -->` comment (and `_alt2`
  for the second image of a two-images slide); see
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §8. Localised in all interface
  languages. (Groundwork for AI_ASSIST §6; the optional "suggest alt-text" vision
  model follows.)
- **Sign-off slide type (`signOff`)** — the *Ondertekening* type is now a
  structured truthful-reporting page (MIAUW 1.6) instead of a free-Markdown
  scaffold. A dedicated editor authors the deck-wide **visual signature** — the
  truthfulness statement, rapporteur name/role, **certification** and typed
  signature — and offers **Afronden & verzegelen** right on the slide; the
  preview renders that attestation with the document **seal status** ("Verzegeld
  op …" once sealed). The signature is the same reusable, seal-covered
  `DocumentSignature` used elsewhere (one signer per report), now with a
  certification field (`ocideck_sig_cert`); the finalise dialog gained the field
  too and pre-fills from the slide. Sealing stays blocked until every AI-drafted
  field is reviewed. Localised in all interface languages. See
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §3 and §5.
- **Sealing waits for AI-drafted text to be reviewed** — groundwork for the
  optional AI drafting assistant (AI_ASSIST §16.3): a slide can carry an
  `ocideck_ai_assisted` marker naming the fields whose text was drafted by AI and
  not yet human-checked. While any slide carries such a marker, **Afronden &
  verzegelen** is blocked and names the slides still to review, so the EIS 1.6
  truthfulness attestation always covers human-verified text. The marker
  round-trips in the `.md` (see [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §8);
  nothing writes it yet — the drafting assistant that sets and clears it lands
  later. Localised in all interface languages.
- **Findings-summary slide type (`findingsSummary`)** — the *Bevindingenoverzicht*
  type is now a structured management overview instead of a free-Markdown
  scaffold. A dedicated editor captures the number of findings per CVSS 4.0
  severity band (Critical / High / Medium / Low / Informational); the preview
  renders a severity-coloured **bar chart** (via `fl_chart`) with the exact
  per-band counts and a derived total. **"Vernieuw uit deck"** recomputes the
  counts from the deck's `finding` slides — each finding's severity is derived
  from its CVSS vector, an absent vector counting as informational — while the
  counts stay hand-editable. Storage is a **plain Markdown table** (PENTEST_MIAUW
  §4.3.4 / §11), so it aligns with the `checklist` / `scopeMatrix` handling and
  round-trips losslessly; the total is derived, never stored. Localised in all
  interface languages. See [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §5.
- **Reusable finding-template library** — findings can be started from a
  reusable template instead of a blank slide. A searchable **"Uit sjabloon…"**
  picker in the finding editor offers a set of bundled starter findings (SQL
  injection, reflected XSS, weak password policy — each with a CVSS 4.0 vector,
  CWE and description / reproduction / impact / recommendation); picking one
  fills those fields so the tester can specialise it, while the scope object,
  CVE ids and finding id stay per-engagement. Templates are plain Markdown with
  YAML front matter (title, severity, `cvss_vector`, `cvss_version`, `cwe`,
  `references`), so they are diffable and (in a later step) importable as
  community/team packs (PENTEST_MIAUW §17). Localised in all interface languages.
- **Finding slide type (`finding`)** — the *Bevinding* type is now a structured
  header card instead of a free-Markdown scaffold. A dedicated editor captures
  the scope object, the **CVSS 4.0 vector** (with a live, derived score +
  severity band), CWE and CVE references, and the description / reproduction /
  impact / recommendation sections; the preview renders a severity-coloured card
  with a CVSS badge and CWE/CVE chips. Severity is always **derived** from the
  vector by the native CVSS 4.0 engine, never stored. Findings can be linked into
  a **group** — a header card plus its detail and evidence slides — through a
  shared finding id (`ocideck_finding_id`) and role (`ocideck_finding_role`), so
  the whole finding moves and round-trips as a unit. Storage stays Markdown-close
  and human-readable (PENTEST_MIAUW §3.1); see
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §4. Localised in all interface
  languages.
- **Checklist slide type (`checklist`)** — the *Checklist* type is now a
  structured, standard-driven test list instead of a free-Markdown scaffold. A
  dedicated editor captures a standard label and a list of tests, each with an
  id, name, MIAUW **tri-state** status (*Getoetst* / *Afwijking* / *Niet
  toetsbaar* / *Niet getoetst*), an optional link to a finding id, and a note.
  The preview shows a derived tested/total progress bar and per-row status chips.
  Storage stays a **plain Markdown table** (PENTEST_MIAUW §3.2), so it aligns
  with the existing `table` handling and round-trips losslessly; the progress is
  derived, never stored. Localised in all interface languages. See
- **Scope-matrix slide type (`scopeMatrix`)** — the *Scope-matrix* type is now a
  structured matrix instead of a free-Markdown scaffold. A dedicated editor lists
  the scope objects, each with a **type** (Web / Infra / IoT / Firmware / API /
  Mobile / Other) that **automatically fixes its test standard** (Web→WSTG,
  Infra→PTES, IoT→ISTG, Firmware→FSTM, API→WSTG, Mobile→MASTG — PENTEST_MIAUW
  §10.7), a coverage status (Tested / Anomaly / Unreachable / Not tested) and a
  note. The preview renders the objects × standard × status matrix with a derived
  coverage bar. Storage stays a **plain Markdown table** (§4.4), so it aligns with
  the `table` handling and round-trips losslessly; the standard and the coverage
  are derived, never stored. Localised in all interface languages. See
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §5.
- **Informatieveiligheid slide types (scaffold)** — five new slide types for
  pentest reporting (*Bevinding*, *Bevindingenoverzicht*, *Checklist*,
  *Scope-matrix*, *Ondertekening*) are registered end to end: enum, metadata,
  picker wireframes, editor, preview and Markdown round-trip (each rides its own
  Marp `_class` token — `finding`, `findings-summary`, `checklist`,
  `scope-matrix`, `sign-off`). They belong to the *Informatieveiligheid*
  category and only appear in the add-slide picker once that module is enabled.
  For now each behaves as a free-Markdown body; the structured editors follow per
  type. Localised in all interface languages. See
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §4.
- **Animated GIFs play** — an imported animated GIF (or WebP/APNG) now keeps
  animating in the preview, presentation and audience window instead of freezing
  on its first frame. The decode-size cap that guards against memory-bomb images
  now only downscales pictures that actually exceed the limit, so within-limit
  animations decode at native resolution and play. Exports (PDF/PPTX) still
  capture a single still frame, as before.
- **Crop images to fit** — when a picture is bigger than its slot and part falls
  outside, a **Crop** button (image slide, title background, bullets + image, and
  each image of a two-images slide) opens a live editor. Drag the image to choose
  which part stays in view; for the full-slide image and title background you can
  also zoom in the same dialog. The crop is a non-destructive focal point — the
  original file is untouched and it round-trips in the `.md`
  (`ocideck_image_focus`, see [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §8). See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Images*.
- **Search the documentation** — *Settings → Documentation* now has a search box
  above the document list. Type one or more words and the list narrows to the
  documents whose title or body contains all of them, each shown with a short
  excerpt where the words are highlighted. Clearing the box restores the full
  grouped list. Bodies are searched in the current interface language. See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Accessibility*.
- **Play-only lock** — a deck can be marked *play-only* in its file
  (`ocideck_play_only: true` in the front matter, or the **Play only (locked)**
  switch in *Presentation properties*). A play-only deck opens locked: the
  editor, toolbar, menus, shortcuts and export are gone — only the first slide is
  shown with a **Play** button. Starting playback switches the app to full
  screen; the presentation runs exactly as normal. Closing the deck restores the
  normal working of the app. The lock lives in the file, so it travels with the
  deck when shared; to remove it, delete the `ocideck_play_only` key from the
  markdown. See [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Play-only decks* and
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §3.
- **Findings are highlighted in the code, not just the gutter.** After
  **Check** in markdown mode, each line with a validation issue now gets a
  coloured band behind the code with a stronger left accent bar — red for
  errors, amber for warnings — so problems stand out where you edit. The bands
  scroll with the text and clear as soon as you start typing (the findings are
  stale then), matching the existing line-number markers.
- **Per-slide markdown view** — markdown mode can now show a single slide's
  markdown instead of the whole presentation. A graphical sliding toggle at the
  top of the markdown editor switches between **Full presentation** and **This
  slide** (with a `n/total` counter); selecting another slide reloads its
  markdown. Both scopes edit and quality-check the same way — **Apply** in the
  per-slide scope parses just that fragment back into the deck (and splits into
  several slides if you add `---` separators), with user notes and annotations
  re-anchored exactly as in whole-deck mode. See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md) → *Markdown mode*.
- **Optional password encryption for `.ocideck` packages** — when you export a
  package you can now protect it with a password. OciDeck encrypts every file in
  the package with **AES-256** (the WinZip AES standard). The export dialog shows
  an intelligent, entropy-based strength meter (a long passphrase beats a short
  password with symbols — it never forces a mandatory "!") and can generate a
  strong random password (choose **32** or **256** characters) that you can copy
  to share out of band. Opening an encrypted package prompts for the password,
  with a clear message on a wrong one. Encryption is entirely optional; existing
  unencrypted packages keep opening as before. See
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §7.1 for the format and its caveats.
- **Roomier documentation reader with adjustable text size** — the in-app reader
  now uses the full window width, so wide tables get the space they need instead
  of being squeezed into a narrow column (running text still keeps a readable
  line length). A subtle **A−/A+** control in the app bar enlarges or shrinks the
  document text; the choice is remembered and is separate from the app-wide
  interface text size.
- **All project documentation is now readable in-app** — Settings →
  Documentation previously listed only the user guide, shortcuts and file
  format. It now also opens the architecture overview, build instructions,
  quality checks, source-code map, license compliance and the SBOM, plus a
  separate **Design** section for forward-looking specs (starting with the
  real-time collaboration design). Every title is translated in all languages,
  and a new guard test fails the build if a document lands in `docs/` without
  being bundled and shown in the reader, so nothing can silently go missing
  again.
- **`Ctrl/Cmd + W` closes the presentation** — pressing the standard
  window-close shortcut during a presentation now exits it, just like closing a
  window elsewhere. It works from any mode and from both the presenter and the
  beamer window (in dual-screen mode the beamer asks the presenter to close).
- **Fifteen conversation-preparation templates** — the new-presentation wizard
  now helps you prepare for a difficult or important conversation. Work
  conversations: **job interview** (STAR answers), **performance review**,
  **salary negotiation**, **asking for more responsibility** and **raising a
  workplace problem**. Difficult personal conversations: **resolving a
  conflict**, **giving or receiving criticism**, **delivering bad news**,
  **setting boundaries** and **discussing a strained relationship or
  friendship**. Commercial/persuasive conversations: **client conversation**,
  **sales conversation** (SPIN), **supplier negotiation** (BATNA/ZOPA),
  **pitch** and **getting buy-in in a meeting**. The genuinely high-stakes,
  emotional conversations weave in the *Crucial Conversations* method (Patterson,
  Grenny, McMillan & Switzler): start with heart, separate facts from your
  story, make it safe, STATE your path, listen (AMPP) and move to action; the
  commercial and interview templates use a scenario-specific framework instead.
  Each has fill-in preparation and anticipation tables plus a progress checklist
  for agreements, and its title and description are translated in all 30
  non-Dutch languages.
- **Three shift-briefing templates** — the new-presentation wizard now offers a
  **Security briefing** (current events and previous shift, points of attention,
  special notes for the day, building/site maintenance and staffing), an
  **Operational police briefing** (hotspots/hot times/hot crimes, person and
  vehicle wanted notices with threat level, priorities and area assignments,
  officer safety) and an **Enforcement briefing (BOA)** (focus locations and
  nuisance, ongoing actions, powers and legal framework, cooperation with and
  escalation to the police). Each is an enriched briefing with fill-in tables,
  a pre-shift checklist with progress, and a handover/debrief. Titles and
  descriptions are translated in all 30 non-Dutch languages.
- **In-app documentation reader** — a new **Documentation** tab in Settings
  lists the user guide, keyboard shortcuts, the file-format reference and the
  full EUPL 1.2 licence; each opens in a spacious, accessible full-screen reader
  that **renders** the Markdown (headings, lists, tables, code, links) instead
  of showing raw source in a cramped box. Text follows the OS text-size setting,
  is selectable, and links open externally; the reading column is width-bounded
  for legibility. The consent screen's "read the full licence" now opens the
  same reader. Documents load **locale-aware**: a translated variant
  (e.g. `docs/USER_GUIDE.de.md`) is used automatically when bundled, otherwise
  the source-language document. Built on the app's own inline-Markdown renderer —
  no new dependency. The few new UI strings are translated in all 30 non-Dutch
  languages.
- **Dead-code gate (`make check-dead-code`)** — a new quality check, wired into
  `make check` and CI, that walks the `lib/` import graph from the app
  entrypoint and fails on any orphaned `.dart` file reachable via no
  `import`/`export`/`part` (both branches of a conditional import counted). This
  closes the analyzer's blind spot: `flutter analyze --fatal-infos` already
  rejects unreachable code and unused imports/private elements, but a whole
  detached file stayed green. A companion **`make fix`** helper applies
  `dart fix --apply` + reformat for local cleanup. See `docs/CHECKS.md`.
- **Dark mode for the editor** — selecting the dark app-appearance profile
  (*Settings → Appearance*) now also darkens the editor chrome, not just the
  Material widgets. Every semantic `AppTheme` colour token resolves per mode
  (`AppTheme.isDark`, tied to the profile), so surfaces, text, borders and status
  tints flip together. Slide content stays a fixed white canvas (a slide is a
  design surface), and brand/accent colours are unchanged across modes.
- **Advisory supply-chain scan (`make trivy`)** — an optional [Trivy](https://trivy.dev)
  scan that checks the resolved Dart packages (`pubspec.lock`) for known CVEs —
  previously only licence-checked, not vulnerability-scanned — and sweeps the
  repo for committed secrets. Scanners and scope live in `trivy.yaml`. It is
  advisory: not part of `make check`/`check-full` (it needs the external `trivy`
  binary and Dart/pub advisory data is still sparse), and the matching CI job
  runs with `exit-code: 0` so it reports without blocking merges. Documented in
  `docs/CHECKS.md`. The CI job pins `trivy-action` to `v0.36.0`, and `make trivy`
  bypasses a stale docker credential helper via an empty `DOCKER_CONFIG` so the
  (auth-free) vuln-DB download can't be blocked by it.
- **Pinned-Action freshness monitor (`make check-actions`)** — an advisory check
  that reads `.github/pinned-actions.json` and asks each exact-pinned third-party
  CI Action's release API whether a newer version exists, so a stale pin stands
  out (the Action analogue of `make deps-check`). Floating `@vN` Actions
  auto-update and are not tracked. Documented in `docs/CHECKS.md`.
- **Contextual help in the editor** — a subtle "What can I do here?" button at
  the top of the slide editor expands a short, slide-type-specific hint (e.g.
  chart: CSV import; video: trimming/cut-at-playhead; table: paste from a
  spreadsheet). An info tooltip next to the per-slide TLP control explains that
  slides above the deck's level are left out when presenting and exporting. Every
  slide type has a hint (enforced by an exhaustive switch); all hints are
  translated in the 30 non-Dutch languages.
- **Command palette (Ctrl/Cmd+K)** — a searchable overlay listing the common
  actions (present, export, save, new chart, find & replace, image library,
  toggle markdown/visual mode, full-deck preview, new tab, open, package/URL
  import, settings, and setting each TLP level). Type to filter (accent- and
  case-insensitive), arrow keys to move, Enter to run, Esc to close; disabled
  actions (e.g. export before saving) stay visible but greyed. Also reachable
  from the "⋮" menu. Labels reuse the existing menu/tooltip strings; the few new
  strings are translated in all 30 non-Dutch languages.
- **Software Bill of Materials (SBOM)** — a complete, machine-readable inventory
  of every shipped component (Dart/Flutter packages direct + transitive, the
  vendored JS/CSS export bundles, the plugin forks in `third_party/`, the bundled
  fonts, and the build SDKs) in **both** common machine-readable formats —
  CycloneDX 1.6 (`sbom/ocideck.cdx.json`) and SPDX 2.3 (`sbom/ocideck.spdx.json`)
  — plus a human-readable Markdown view (`sbom/ocideck.sbom.md`). Generated
  from the existing sources of truth by `dart run tool/generate_sbom.dart`
  (`make sbom`); each component carries its version, SHA-256, purl and licence
  (classified by the same logic as `make licenses`). A `make sbom-verify`
  staleness gate — wired into CI, `make check-full`, and the test suite — fails
  the build if dependencies change without the SBOM being regenerated. The SBOM
  ships in the web build (`build/web/sbom/`) and as a release artifact, and is
  the artefact required by the **EU Cyber Resilience Act** (Reg. (EU) 2024/2847,
  Annex I Part II §1). See [`docs/SBOM.md`](docs/SBOM.md).
- **Ordering questions** — a fourth question kind next to multiple choice,
  true/false and multiple-correct: the answers as entered in the editor are the
  correct order (rearranged with up/down arrows). Presenting draws a random
  subset, keeps its relative order as the right answer and shows it shuffled
  (never accidentally already correct); the viewer taps the options into order
  and confirms. A wrong answer reveals the options **in the correct order**,
  marking each misplaced one in red with an explicit *Your order: n* line —
  correctly placed ones turn green. Timer, on-wrong policy (retry with a fresh
  draw, or lock-and-continue) and the interactive audience window work exactly
  as for the other kinds. Round-trips in the ```` ```question ```` JSON block
  as `"kind": "ordering"`; translated in all 30 non-Dutch languages.
- **Nextcloud (WebDAV) as a file source** — browse a folder on your Nextcloud
  and open `.ocideck` packages or Marp `.md` decks straight from it, and save a
  deck back, either as a single `.ocideck` package or as a flat `.md` plus its
  asset folders. Configure the server under *Settings → Nextcloud* (server URL,
  username, app password, optional subfolder) with a **Test connection** button.
  The **app password is stored encrypted in the OS keychain**, never in the
  preferences file. A self-hosted server on a private/LAN address is only
  reachable after ticking **Trusted internal server**; deck-supplied URLs stay
  blocked by the SSRF guard. Downloads pass through the same safety gate and
  size/zip limits as every other import. Entry points: the welcome screen, the
  `…` menu (*Open from Nextcloud* / *Save to Nextcloud*).
- **OciDeck logo on startup** — the welcome screen and the first-run consent
  dialog now show the OciDeck cat logo.
- **One-command builds for every target** — `make build-web` (hardened),
  `make build-macos` / `build-windows` / `build-linux`, and `make build-all`
  (web plus the host's native desktop target). A release CI workflow
  (`.github/workflows/release.yml`) builds web, macOS, Windows and Linux on a
  version tag and uploads each as an artifact. See [`docs/CHECKS.md`](docs/CHECKS.md).
- **Edit a table while presenting** — tables can be changed live during a
  presentation (filling in figures, ticking items in front of an audience).
  It is opt-in per table: a new **Table editable while presenting** checkbox in
  *Per-slide options* (off by default, so tables stay read-only otherwise),
  round-tripping in the `.md` as a `table-editable` `_class` token. On an
  editable table a subtle pencil icon (top-right) toggles editing — dimmed when
  off, highlighted when on — alongside the **E** key. While editing, the arrow
  keys move the text cursor inside the cell, **Tab** / **⇧Tab** switch cells
  (a new row is added past the last cell), and `Esc` leaves editing; changes
  mirror to the beamer in dual-screen mode.
- **Online media by URL** — image and video slides accept an `http(s)` URL as
  the source, rendered live (no local copy). Off by default: the new
  **Online media** security setting must be enabled before any remote source is
  fetched; until then the slide shows a placeholder with the URL. On export, a
  remote source also emits a clickable literal URL.
- **YouTube/Vimeo embeds** — a video slide can embed a YouTube or Vimeo link,
  played by the official iframe player (designed to extend to more providers).
- **Watch a video in parts ("cut")** — a video can be split at a playback point:
  the first part stays on this slide and the remainder moves to a new slide with
  the same source, which can be cut again. Works for local, online and embedded
  video. The trim window round-trips in the `.md` (a `#t=START,END` media
  fragment on `<video>`, or `data-start`/`data-end` on the embed iframe).
- **Redesigned settings dialog** — the settings window moves from a flat tab bar
  to a sidebar navigation (sections on the left, a titled content area on the
  right, a footer action bar), without changing any of the settings themselves.
- **"Over OciDeck" screen** — a new About section in Settings, opened from the
  OciDeck logo at the bottom of the settings sidebar. It explains where the name
  comes from (the *Ocicat* breed of the author's cats plus a slide *deck*),
  introduces publisher **Stichting LibreKAT** with its mission, contact details
  and a link to librekat.nl, and shows the three mascot cats (Branie, Keiko,
  Otis) with photos. Translated in all 30 non-Dutch languages.
- **Title background can fill the whole slide** — a "fill slide" toggle on title
  slides shows the background image edge-to-edge (cover, cropping the overflow)
  instead of being limited to the zoom slider. Toggling it back off restores the
  zoom you had set.
- **Low-contrast title text is detected and auto-fixed** — when a title slide's
  text has too little contrast against its background image, the slide-quality
  panel flags it (with the measured ratio) and offers a one-click **Herstel**
  that picks the smallest effective change: enable the grey wash, or switch the
  title text light/dark for that one slide (a new per-slide title text colour
  that round-trips in the `.md`). The check also feeds the export gate.
- **Timeline slides** — a new `timeline` slide type that turns a list of dated
  events into an animated, eye-candy timeline. Each event is a plain Markdown
  list item using `marker :: title :: description` (marker and description
  optional), so the `.md` stays a readable, Marp-compatible list — no JSON block.
  The renderer draws a glowing accent spine with nodes and cards that alternate
  above/below (horizontal rail) or left/right (vertical spine), styled from the
  active profile (accent, fonts, background). When a horizontal rail gets
  crowded the cards stack onto multiple *floors* (heights) so they tile instead
  of colliding. On enter, the line draws itself first and the events are then
  placed onto it one after another. **Layout** is *auto* (horizontal
  for short timelines, vertical for longer ones) or forced horizontal/vertical;
  **animation** is *draw-in on open*, *step-by-step* (each click reveals the next
  event, kept in sync on the audience window) or *none*. Layout and animation
  round-trip as `_class` tokens (`timeline-horizontal` / `timeline-vertical` /
  `timeline-steps` / `timeline-static`); the events live in the list itself. The
  draw-in **animation speed** is adjustable per slide via a slider (≈0.4–6 s) and
  round-trips in an `ocideck_timeline_duration` comment.
- **Question slides (interactive quiz)** — a new `question` slide type that turns a
  presentation into a short quiz. Three kinds, chosen in the editor: **multiple
  choice** (one correct answer shown with a random pick of wrong ones), **true /
  false** (the prompt is a statement; the editor sets whether it is true), and
  **multiple correct answers** (tick all correct, then **Confirm**). The answer
  pool is unlimited; a configurable number of options (default 4) is drawn at
  random each run. Options: an optional **answer-time** countdown (running out =
  wrong), an **on-wrong** policy (*try again* — blocks advancing until correct, a
  click draws a fresh set — or *allow continuing* — reveal, lock, move on), and an
  optional **image** with a pan-and-zoom detail popup. Presenting **blocks
  advancing** until the question is answered correctly (or answered and locked);
  correct turns green, wrong turns red and highlights the right answer. On a
  two-screen setup the audience window is interactive and stays in sync. The quiz
  spec round-trips in a fenced ` ```question ` JSON block; the live answer state is
  session-only and a static export shows the question without interactivity.
- **User notes (recipient / course)** — personal notes per slide, fully separate
  from speaker notes (`Slide.notes`). Stored in a `<name>.user-notes.json`
  sidecar (fingerprint-anchored like annotations). Hidden by default while
  presenting; `Ctrl/Cmd + N` toggles a local **My notes** panel on the presenter
  window only. Visual editor: collapsible **User notes** block below **Speaker
  notes** (matching amber/blue headers, each with a discard button). Slides
  that carry user notes show a blue badge on their thumbnail in the slide list.
- **Find & replace in Markdown mode** — an in-editor find bar searches the live
  markdown buffer (`Ctrl/Cmd+F`; replace row via `Ctrl/Cmd+H`), with next/previous
  navigation, match counter, case sensitivity, and replace current / replace all.
  Visual mode keeps the existing find & replace dialog over slide fields.
- **Presentation timer / rehearsal mode** — the presenter view now doubles as a
  rehearsal clock that measures without coaching. A **countdown** runs against a
  target time (default under *Settings → General → Presentation*, or set live with
  `K` as `MMSS`; `0` turns it off) and turns red when you go over. The clock bar
  also shows the time spent on the **current slide**, accumulated per slide across
  the run. `R` resets the run (elapsed and per-slide timings, keeping the target).
  Leaving the presenter after a run shows a **summary** (total vs. target, time per
  slide) with copy-to-clipboard. Session-only: nothing is persisted to disk or the
  `.md` file.
- **Duplicate clean-up in the image library** — a footer button finds
  byte-identical images by md5 checksum, keeps one file per group (preferring
  the one used in slides, then the oldest), merges the tags/descriptions and
  captions of the copies onto it, repoints slides that used a copy — in open
  decks and in `.md` presentations on disk that are not currently open — and
  deletes the copies after confirmation.
- **Untagged-images filter in the image library** — a toggle next to the search
  box shows only images without a description/tags, making it easy to see which
  ones still need attention.
- **Delete warning covers decks on disk** — deleting an image from the library
  now also warns when presentations that are not currently open still
  reference it.
- **Source-code slides** — a "code sheet" with per-language syntax highlighting,
  stored as a fenced code block. Background, text colour and monospace font are
  part of the style profile, with a syntax-colouring toggle; turning it off renders
  the block in a single colour (e.g. green on black for a CRT-terminal look). The
  code is sized to fill the panel — larger when there's room, smaller for long
  fragments.
- **Charts** — bar, line, pie, and **spider/radar** chart slides. Data is entered
  in an in-app grid or imported from CSV; the spec is stored as JSON in a ```chart
  block. Data can stay inline or be linked to a CSV in a separate `data/`
  directory. Rendered natively in-app (preview, presenter, PDF, PPTX) and as
  self-contained SVG in the HTML export.
  - Optional **min/max**: horizontal reference lines on bar/line charts, or a
    fixed scale on spider/radar charts shown as a small legend beside the figure.
  - **Legend hover** highlights the matching series (or pie slice). Line-chart
    tooltips attach to the dot under the cursor (showing every overlapping dot),
    and spider/radar points show a tooltip on hover too.
- **Custom theme colours** — every style-profile colour can be entered as a custom
  hex value in addition to the presets.
- **Per-slide TLP classification** — each slide can carry its own Traffic Light
  Protocol level; slides classified stricter than the level the deck is shown at
  are withheld when presenting and exporting.
- **Export release ceiling** — an optional maximum TLP level that may be
  exported. When set, a deck classified *above* it cannot be exported in any
  format; the gate is enforced at the single export chokepoint and fails closed
  (no file is written when blocked, and the export dialog explains why).
  Classifying a deck stays optional — the ceiling only stops decks that exceed
  it, and it is off by default.
- **Classification enforcement** — extends the export gate with an optional
  **required minimum TLP**, a **classification required** flag (reject decks
  with no TLP level), and a **classification watermark** on every slide
  (diagonal `TLP · organisation`, WYSIWYG in preview and raster exports).
  Settings live under *Settings → General → Accessibility → Classification
  enforcement*. The title-bar TLP chip highlights in orange when export is
  blocked because the deck is unclassified.
- **Export metadata** — PDF, PPTX, and HTML exports embed title, author,
  description, keywords, and TLP (Subject prefix, Keywords, HTML `<meta
  name="classification">` / `<meta name="tlp">`, plus a fixed HTML banner).
- **Dual-screen presenter** — on a second display the beamer shows the slide
  while the laptop shows the presenter view (current/next slide, notes, timer),
  kept in sync over method channels.
- **Annotation layer** — draw on slides while presenting (pen, highlighter,
  eraser, laser pointer). Kept fully separate from the Marp Markdown, mirrored
  live to the beamer, and persisted in a `<name>.ink.json` sidecar.
- **App theming** — customizable app appearance profiles, including a dark
  interface.
- **Paste a table into a table cell** — pasting a spreadsheet selection (Excel,
  Numbers, LibreOffice Calc, Google Sheets), CSV (comma or semicolon), or a
  markdown table into any cell of the table editor fills the whole grid from
  that cell, growing rows and columns as needed. Works with `Ctrl/Cmd+V` and
  `Shift+Insert` on macOS, Windows, and Linux; plain text still pastes into the
  single cell.
- **Slide-type chooser previews** — the add-slide dialog shows a miniature
  wireframe of each layout (in the spirit of other presentation tools) instead
  of an abstract icon, and is fully keyboard-operable (`Tab`/`Enter`/`Esc`).
- **Accessibility (WCAG 2.1)**:
  - An **interface text size** setting (100–200%, Settings → General →
    Accessibility) that scales all editor text; slides themselves keep their
    fixed design size.
  - The panel divider is focusable and **keyboard-resizable** (arrow keys), with
    a visible focus state, and presents itself to screen readers as a slider.
  - **Screen-reader support**: slide thumbnails announce one concise label
    ("Slide 3/12: title") instead of their full content; charts expose their
    type, title, and underlying values as a text alternative; the presenter
    announces each slide change.
  - Improved contrast for hint/label text in the editors.
- **Slide quality** — continuous accessibility and readability checks while you
  edit. A bar below the preview summarises open issues (tips, warnings, errors);
  expand it or open **View issues…** for the full list. Filter by severity, click
  an issue to jump to the relevant slide field or open *Settings → Colours* with
  the matching theme colour highlighted. Checks cover style-profile contrast
  (body, title, table, code, accent, checklist, footer), alt text and media
  descriptions, missing image/video files on disk, and text density (bullets,
  tables, code, markdown, title, quote). Thumbnail badges and inline editor hints
  mark affected slides and fields. Export respects *Warn on export* and optional
  *Block export on serious quality issues* under *Settings → General →
  Accessibility*.
- Project documentation: contributing guide, security policy, architecture and
  build notes, user guide, keyboard-shortcut reference, third-party notices, and
  the EUPL-1.2 licence text.

### Changed
- **A new scope matrix starts with one object, and objects can be reordered.**
  Instead of two starter rows, a fresh scope matrix begins with a single scope
  object; each row gains move-up/move-down buttons to change the order (removing
  a row already worked down to the last one).
- **Attach evidence to a finding without first typing a finding id.** The
  "Screenshot/Video toevoegen" buttons are always enabled; when the finding has
  no id yet, one is derived from the title (`F-xx`) or generated on the first
  piece of evidence. Adding several screenshots/videos already worked (each is
  its own evidence slide) — the id is no longer a gate.
- **The "Checklist" security slide type is renamed to "Uitvoering testen conform
  standaard".** The old name clashed with the bullets *Checklist* list style;
  the new name says what the slide is (a per-standard test run, e.g. OWASP WSTG).
  Only the UI label changed — the `checklist` file-format class is unchanged, so
  existing reports round-trip untouched. Localised in all interface languages.
- **The editor's slide-type selector now opens the same visual picker as "Slide
  toevoegen".** The **TYPE** control in the editor header used to be a plain
  pulldown that listed every slide type in one long, flat list — and, unlike the
  add-slide dialog, it always showed the Informatieveiligheid types even with the
  module off, so the two places disagreed about which types exist. It now opens
  the shared picker (category tabs, search and wireframe previews) and gates the
  security types exactly like the add dialog, so both surfaces offer an identical
  set. A slide that is already a security type can still be re-typed among the
  security types with the module off, so imported reports are never a dead-end.
- **The markdown checker is more critical and less noisy.** It now warns about
  **unknown front-matter keys** (a typo like `pagenate:`, or a Marp option
  OciDeck does not implement such as `header`/`footer`/`size`/`style`) and about
  **unsupported directive comments** (Marp's per-slide `<!-- _paginate -->`,
  `<!-- _header -->`, `<!-- _color -->`, …), which the parser silently drops — so
  you now get told instead of wondering why they have no effect. At the same
  time, plain prose speaker-note comments no longer trigger a spurious "missing
  `_class`" warning, and HTML shown inside a code block (a `<div>`, an
  `![img](…`, a `<video>`) is no longer mis-flagged as broken markup. Unclosed
  code fences are detected by real open/close tracking rather than a parity
  count, so two unclosed fences can no longer cancel each other out.
- **The documentation list is now grouped into named sections.** Settings →
  Documentation previously showed one long flat list with a single **Design**
  heading at the bottom, so every other document floated without a category. The
  documents are now organised under headings by audience — **User** (user guide,
  shortcuts, file format), **Technical** (architecture, build, quality checks,
  source map), **License and compliance** (license compliance, SBOM, the EUPL
  license) and **Design** — with each heading translated in all languages.
- **Switching between slides in the rail is snappier.** Clicking a slide in the
  side rail used to rebuild and repaint every visible thumbnail just to move the
  selection outline, which could stutter while building a large or content-heavy
  deck. Each thumbnail now tracks its own selection, so only the previously and
  newly selected cards refresh; the mini-previews are also isolated so an
  unrelated card never triggers a re-render of its neighbours.
- **Text-heavy slides lay out faster.** The routine that sizes bullet and
  rich-text bodies to fit their slide used to run a fixed number of measurement
  passes; it now stops as soon as the size has settled to within a fraction of a
  point (visually identical). On dense slides that roughly halves the text-
  measurement work behind every preview and thumbnail.
- **The RASCI / TVB template no longer pre-fills the role assignments.** The
  RASCI matrix, the role overview and the tasks/responsibilities/authority table
  used to ship with example assignments (CISO, management, SOC, IT, …) baked into
  every cell, which presumes an organisation structure the template cannot know.
  Those assignment cells are now empty (`…`) and the three tables are live-
  editable, so you fill in who holds which role for your own organisation; only
  the generic example role and task labels remain as scaffolding.
- **Found slides insert at the cursor, not at the end.** The *Slide zoeken*
  (find slides) picker now inserts each chosen slide right after the current
  slide and selects it, so consecutive picks stay in order at your position —
  matching *Add slide*, *Paste slide*, *Paste image* and *Import slides*, which
  already inserted at the cursor.
- **Move a whole multi-selection at once.** Select several slides (shift- or
  cmd-click, Ctrl/Cmd+A) and drag any one of them: the entire selection moves as
  a single contiguous block, preserving its order, and the selection follows to
  the new position. A non-contiguous selection is gathered into one block at the
  drop point. Dragging a single slide is unchanged.
- **Splitting an over-full bullet slide now divides evenly.** When both halves
  fit within the per-page optimum, "Split slide" halves the bullets (e.g. 10
  bullets become 5/5 instead of 8/2) rather than cramming page 1 and leaving a
  near-empty continuation. Slides too full to fit in two pages still fill page 1
  to the optimum and leave the remainder, which you can split again. Applies to
  single-column, checklist and two-column slides.
- **A split "bullets + image" slide keeps its image on the continuation page.**
  The follow-up page is now itself a *bullets + image* slide that inherits the
  same picture (previously it became a full-width, image-less bullets slide), so
  the two pages look consistent and share one font size. You can still swap the
  continuation to a plain bullets page (or give it a different image) per page via
  the slide **type** picker.
- **Opening the same presentation twice now jumps to its tab** instead of
  loading a second copy. Every open-from-path flow (file picker, recent files,
  drag-and-drop, deep link) checks whether the file is already open — comparing
  normalised absolute paths — and, if so, selects that existing tab rather than
  creating a duplicate. This prevents version confusion where two tabs edit the
  same file independently. In-memory opens on the web (which carry no file path)
  are unaffected.
- **Calmer slide editor.** The editor header now packs everything onto one
  strip: the type and style pickers, a "What can I do here?" hint, a compact
  **Quality** chip (the word coloured by status; the counts move to its tooltip
  and its expanded panel) and a gear button for **Slide settings**. Each of the
  three toggles expands its content just below the strip. The secondary
  per-slide controls (audio, logo, footer, table option, timing, TLP) live
  behind the gear (collapsed by default); a set per-slide TLP still shows as a
  small badge next to the gear so the classification stays visible. Speaker and
  user notes keep their own collapsible fields.
- **Settings: "Privacy" is now "Licentie en Privacy", with a separate
  "Beveiliging" (Security) tab.** The renamed tab keeps the licence/privacy
  statement and the consent controls. The **Online media** toggle and the
  crash-recovery-files control move to the new *Beveiliging* tab, since they are
  security choices rather than privacy ones. The tab title and the new tab are
  translated in all 30 non-Dutch languages.
- **Bullet slides** can now carry an optional **subheading** under the title; the
  **two bullet columns** type can have an optional **heading above each column**,
  separate from the slide title.
- Slide text auto-sizing now measures with the deck's own font, so text grows to
  use the available space more accurately instead of staying smaller than needed.
- The two bullet columns are measured **independently** and then rendered at a
  **shared size** set by the busiest column, so the two columns always look
  typographically related. Dense two-column slides spend less height on the
  title, headings, and gaps so the list items themselves render larger.
- Slide transitions in the presenter no longer flash a black frame (neighbour
  images are precached and `gaplessPlayback` is enabled) — important for
  recording.
- **Spider/radar charts** now use the available space: axis labels are measured
  and placed snugly around the polygon (up to three lines, full remaining
  width), so the diagram renders considerably larger and long labels stay
  readable instead of being truncated.
- Bullet auto-fit now stops growing at ≈32 pt (on a 16:9 deck) — the upper end
  of the 24–32 pt range presentation-design guidance recommends for body text —
  so slides with few bullets no longer render body text that competes with the
  title.
- After resizing the slide panel (dragging the divider or resizing the window),
  the list scrolls the slide being edited back into view.
- **Speaker notes** in the visual editor now use the same collapsible header
  pattern as user notes, with a discard button in the header row.
- **Maintainability: the two largest source files were split up.** The
  localization data now lives one file per language under `lib/l10n/translations/`
  (`app_localizations.dart` shrank from ~7,600 to ~160 lines and only assembles
  the lookup maps), and `fullscreen_presenter.dart` (~3,500 → ~1,270 lines) was
  split into themed `part` files under `widgets/presentation/parts/`. No
  behavioural change; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### Fixed
- **A long finding no longer shrinks to unreadable text.** A `finding` slide
  with a lot of prose used to scale its whole card down to fit one slide — the
  text got smaller *and* stopped using the full slide width. It is now
  **paginated** everywhere it renders — the **export** (PDF/PPTX and the
  self-contained HTML), the **presenter**, and the **in-editor preview** (page
  through with the arrow keys, the page indicator shows "Pagina i / N"): an
  overflowing finding spans several full-size slides (page 1 keeps the
  severity/CWE header card and the sections that fit; each continuation page
  repeats the heading with a small "(i/N)" marker and holds the next sections). A
  finding that fits one slide is untouched. This is render-time only — the finding
  is still edited as one slide and the `.md` on disk is unchanged.
- **Per-slide title colour lost in the self-contained HTML export.** A title slide
  whose title text colour was overridden (the "Titelkleur: Wit/Donker" choice, e.g.
  a dark title over a light background image) rendered with the theme's default
  title colour in the standalone HTML export, so a title tuned for its background
  could vanish. The override now travels into the export as a per-slide CSS
  variable that the title heading reads, matching the app preview, presenter and
  PDF/PPTX. Only a strict hex value is accepted, so it cannot break out of the
  attribute it is written into.
- **"Bank" mistranslated on the About page.** The label for the foundation's bank
  (Triodos) reused the Dutch source word `Bank`, which also labels the cockpit
  artificial-horizon **roll angle** — so in every non-Dutch language the About
  page showed the *aviation* translation (e.g. French *Roulis* — "roll"). The
  financial label now has its own key and reads correctly (*Banque*, *Banco*, …),
  independent of the cockpit gauge.
- **Folder pickers that a browser cannot honour are hidden on the web.** In the
  browser there is no file system — decks open from their bytes and every export
  is a download — so choosing a folder has no meaning. Three controls relied on a
  native directory picker that the browser does not implement, so their button
  did nothing when clicked (no error, no dialog): the *presentation folder* and
  *export folder* settings (*Settings → General*), and the **Find slides** /
  **Import slides** buttons in the slide list. All of these are now hidden when
  running on the web.
- **Deleting a slide keeps focus on the slide above it.** Removing a slide (via
  its context menu or the Delete/Backspace key) now selects the slide *above* the
  deleted one instead of jumping back to the first slide; deleting the first
  slide moves focus to the new first slide. The slide-list rail now also scrolls
  that focused slide back into view instead of snapping to the top — previously,
  deleting a slide below the selected one left the list showing the first slide.
- **A `---` inside a fenced code block no longer splits a slide.** Slide
  separation is now fence-aware: a `---` line inside a ```` ``` ```` or `~~~`
  block (a code sample, a diff hunk, an embedded YAML document) is treated as
  code, not as a slide break, so such slides are no longer silently torn in two.
  The parser and the in-app markdown checker share one splitter so they always
  agree on the slide boundaries.
- **The markdown checker now matches the parser on Windows/Mac line endings.**
  The checker normalises CRLF/CR up front, like the parser already did; without
  this a pasted CRLF document made it silently skip the front-matter and
  slide-structure checks while the parse still succeeded.
- **The documentation reader no longer throws while you drag its scrollbar.** On
  desktop the reader's scrollbar was not bound to its own scroll view, so
  dragging the thumb raised *"The Scrollbar's ScrollController has no
  ScrollPosition attached"* (repeatedly). The reader now gives the scrollbar and
  its scroll view a shared `ScrollController`, so dragging works cleanly.
- **"Continue numbering" is now available on a split bullets-with-image slide.**
  A "bullets + image" slide is a `bulletsImage` slide, edited in the bullets-
  with-image editor — which was missing the *Continue numbering from previous
  slide* toggle that the plain bullets editor already had. So after splitting a
  numbered bullets-with-image slide, its second half could not be told to carry
  on the count, even though the renderer (`numberedListStartFor`) already
  supported it. The toggle now appears in that editor too, under the same
  condition (a numbered list whose preceding slide is also numbered).
- **The slide rail now continues a numbered list across a split.** After
  splitting a numbered slide and ticking *Continue numbering from previous
  slide* on the second half, the builder's thumbnail rail still restarted the
  count at 1, even though the main preview and the actual presentation continued
  it (7, 8, 9…). The rail thumbnails now compute the same start number
  (`numberedListStartFor`) as the main preview and the presenter/audience views,
  so the overview matches what is shown.
- **Code-colour contrast is judged against the large-text threshold.** The
  theme quality check treated the code text/background pair as normal body text
  (WCAG AA 4.5:1), so the LibreKAT house-style green on the dark code panel
  (~3.6:1) drew a spurious "too little contrast" warning even though code on a
  slide renders at display size. It is now checked against the large-text
  threshold (3.0:1), consistent with the title and table-header pairs; code that
  is dense enough to render small is still caught separately by the density
  check.
- **Web: a saved deck no longer reads as "not saved yet".** On the web build,
  saving is a browser download, which returns no file path, so the status bar's
  filename slot stayed on "Not saved yet" right next to the green "Saved" chip.
  It now shows the downloaded filename (with a tooltip explaining it went to your
  downloads folder); desktop is unchanged.
- **Consent dialog no longer crashes its action bar.** A `Spacer` in the
  `AlertDialog` actions (which are laid out in an OverflowBar, not a Flex) threw
  a layout error that the release build swallowed into a dark placeholder box
  (and spammed the console on web). The two actions are now split with
  `actionsAlignment` instead.
- The export quality gate now includes the asynchronous title-image contrast
  warnings, so the gate and the on-screen quality panel no longer disagree.
- Turning the title "fill slide" option back off no longer discards the zoom you
  had dialled in.
- Hover on charts (tooltips, legend highlight) now works on a second screen:
  macOS only delivered mouse-moved events to the key window, so the borderless
  beamer window never saw them; the stuck hover state after the pointer left a
  window is gone for the same reason.
- Bar-chart x-axis labels could run through each other: the spacing maths now
  matches how bar groups are actually laid out, and the final label shrinks to
  the real gap when it sits closer than a full step.
- A crash in the slide list ("A _RenderLayoutBuilder was mutated…") when its
  keyed items were rebuilt during layout — both the resize-detection inside the
  panel and the shell's width computation now avoid LayoutBuilders above the
  reorderable list.
- A scheduler crash when jumping away from a slide before a quality-focus callback
  ran on a caption or editor field (`ref` used after the widget unmounted).
- **Saving can no longer corrupt a deck.** Decks, sidecars, theme CSS, copied
  chart data, exported packages and URL-imported files are now written
  atomically (to a temp file, then renamed into place), so a crash, full disk or
  process kill mid-write leaves the original file intact instead of half-written.
- **Save failures are no longer silent.** A failed write (read-only volume, full
  disk, permission denied) now shows an error and keeps the deck marked as
  unsaved, instead of being swallowed and reported as success. `Save` reliably
  reports failure so closing a tab/window no longer crashes or loses work, and a
  *Save As* whose file cannot be re-read afterwards surfaces a warning rather
  than silently treating the deck as saved.
- **Windows (CRLF) markdown files now open correctly** — line endings are
  normalised before parsing, so frontmatter and slide separators are no longer
  missed and the whole deck no longer collapses into a single slide.
- A truncated or corrupt `.md`, or a file with non-UTF-8 bytes, now reports
  "could not open" instead of silently opening as an empty presentation that
  could be overwritten.
- Rapid double `Cmd/Ctrl+S` can no longer start two overlapping writes to the
  same file.
- **Uncaught errors are now caught and logged.** The app runs inside a guarded
  zone with framework- and platform-level error handlers, so an unexpected
  error during a presentation no longer disappears silently or leaves the UI
  wedged; in release a build failure shows a quiet placeholder instead of a red
  error box.
- The Mermaid diagram render cache is now bounded (LRU), so a long session with
  many distinct diagrams can no longer grow memory without limit.
- Crash recovery no longer leaves a stale autosave file after a deck is saved:
  the periodic autosave and the "saved → discard" cleanup are now serialised
  per tab, so the app won't falsely offer to restore already-saved work on the
  next start.
- Importing a package (`.ocideck` zip) is more robust: a corrupt archive entry
  is skipped instead of aborting the whole import, and an entry that declares an
  oversized uncompressed size is rejected before being inflated into memory.
- Audience-window sync failures during a presentation are now logged instead of
  silently swallowed, so a beamer that drifts out of sync leaves a trace.
- **Switching to Markdown mode and back no longer wipes slide drawings.** Ink
  annotations are re-anchored across the toggle (previously they were dropped,
  and a following save deleted their sidecar — permanent loss). Linked chart
  data is also kept across the toggle.
- Front-matter parsing is more forgiving: indented keys and missing spaces after
  the colon (e.g. hand-edited files) are now read correctly instead of being
  silently ignored.
- Rapidly switching between slides with video or audio can no longer leave an
  orphaned media player or double-dispose a controller.
- Undo no longer risks merging edits to different slides into one step (the
  coalescing key is now the stable slide id, not its position).

### Security
- **The web build is now self-contained and CSP-hardened.** CanvasKit and the
  Roboto UI font are bundled locally instead of fetched from Google's CDN, so the
  running app makes **zero third-party requests**, and `web/index.html` ships a
  strict Content-Security-Policy (`script-src 'self' 'wasm-unsafe-eval'`, no
  `unsafe-inline`/`unsafe-eval`). Build with `make build-web`.
- **Deck asset paths are confined to the project folder on every read path.**
  An untrusted `.md` can no longer use absolute or `../` image/logo/chart paths
  to make the slide-quality analyzer probe arbitrary files (a file-existence
  oracle that ran automatically on open), the exporter precache read files
  outside the project, the Save-As chart copy read outside the project, or the
  copy-to-clipboard action exfiltrate an arbitrary file. All of these now use
  the same containment guard as the preview (`resolveSlideAssetPath`).
- A deck `.md` is now size-capped (32 MiB) on open to avoid loading and parsing
  a maliciously oversized file.
- The HTML export now carries a **nonce-based Content-Security-Policy** so an
  injected inline script that survives sanitization still cannot execute when
  the file is opened. Mermaid in the export runs in strict mode and its SVG is
  re-sanitized with DOMPurify; the in-app mermaid webview has its own CSP.
- **Image decoding is dimension-capped** everywhere a deck-supplied image is
  shown, exported, or precached, so a tiny but huge-dimensioned file can no
  longer exhaust memory and crash the app.
- **URL import now resolves the hostname** and refuses it when it maps to an
  internal address, closing the SSRF bypass where a public name points at a
  loopback/private/metadata IP.
- **Copy-to-clipboard follows symlinks** and refuses a project-internal symlink
  that points outside the project, so it can't be used to exfiltrate an
  arbitrary file.
- **Imported images are validated by magic bytes** (not just the file
  extension) and capped at 64 MiB; video/audio imports are capped at 1 GiB.
- **URL import pins the connection** to the validated address, closing the
  DNS-rebinding window where a host re-resolves to an internal IP at connect
  time.
- **Symlink containment now also covers the render/export path** (cached), not
  just copy-to-clipboard, so a project-internal symlink pointing outside the
  project can't be rendered into an export.

## Initial development

This section was headed `[1.0.0]` and linked to a release tag that does not
exist. Nothing has ever been tagged or released; the entry is kept because it
records what the first working version could do, but it is not a version.

### Added
- Initial feature set: structured, slide-by-slide editor for Marp presentations with
  typed slide templates, live preview, fullscreen presenter, deck-wide TLP
  marking, media handling, import, and export to Marp Markdown, PDF, PPTX, and
  self-contained HTML. Decks save as a self-contained project/package with copied
  assets. Localized in Dutch, English, Italian, German, French, Spanish, Frisian,
  and Papiamento.

[Unreleased]: https://pawprint.vigilis.online/LibreKAT/Ocideck/commits/branch/main
