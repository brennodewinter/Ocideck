part of '../app_localizations.dart';

const _stringsSv = {
  'bankLabel': 'Bank',
  'newPresentation': 'Ny presentation',
  'open': 'Öppna...',
  'openEllipsis': 'Öppna…',
  'recentFiles': 'Senaste filer',
  'newTab': 'Ny flik',
  'imageLibrary': 'Bildbibliotek',
  'presentFullscreen': 'Presentera (helskärm) · P för presentatörsvy',
  'visualMode': 'Visuellt läge',
  'markdownMode': 'Markdown-läge',
  'save': 'Spara',
  'more': 'Mer',
  'export': 'Exportera',
  'exportReady': 'Exportera (PDF/PPTX/HTML)',
  'exportNeedsSave': 'Spara presentationen innan du exporterar',
  'exportNeedsClean': 'Spara dina ändringar innan du exporterar',
  'saved': 'Sparad',
  'unsaved': 'Osparad',
  'unsavedChanges': 'Spara ändringar (Ctrl/Cmd+S)',
  'noUnsavedChanges': 'Inga osparade ändringar',
  'notSavedYet': 'Inte sparad än',
  'noFileYet': 'Den här presentationen har ingen fil än',
  'slides': 'bilder',
  'skipped': 'överhoppade',
  'allSlidesIncluded': 'Alla bilder presenteras och exporteras',
  'skippedSlidesExcluded': 'bild(er) presenteras eller exporteras inte',
  'styleProfile': 'Stilprofil',
  'classification': 'Klassificering',
  'exportNextToDeck': 'Exportera bredvid deck',
  'exportsNextToDeck': 'Exporter sparas bredvid decket',
  'exportFolder': 'Export',
  'newPresentationTab': 'Ny presentation (flik)',
  'exportPackage': 'Exportera paket…',
  'importPackage': 'Importera paket…',
  'importUrl': 'Importera från URL…',
  'findReplace': 'Sök och ersätt',
  'fullDeckPreview': 'Visa hela decket',
  'settings': 'Inställningar',
  'settingsGeneral': 'Allmänt',
  'settingsColors': 'Färger',
  'language': 'Språk',
  'applicationLanguage': 'Applikationsspråk',
  'languageHelp':
      'Gränssnittet byter språk direkt. Presentationens innehåll ändras inte.',
  'exportFolderSetting': 'Exportmapp',
  'nextToPresentationFile': 'Bredvid presentationsfilen',
  'choose': 'Välj',
  'removeExportFolder': 'Ta bort exportmapp',
  'exportFolderHelp':
      'Alla exporter (PDF/PPTX) sparas här. Om ingen anges sparas exporter bredvid presentationsfilen.',
  'cancel': 'Avbryt',
  'close': 'Stäng',
  'saveSettings': 'Spara',
  'exportDialogTitle': 'Exportera',
  'exportAgain': 'Exportera igen',
  'exportIntro':
      'Exporten använder exakt förhandsvisningen från redigeraren, inklusive din stilprofil.',
  'imageQualityPdf': 'Bildkvalitet (PDF)',
  'normal': 'Normal',
  'compressed': 'Komprimerad',
  'compressedHelp':
      'JPEG med lägre upplösning, avsedd för utdelningsblad, med en mycket mindre fil (sparas separat som ”-compact”).',
  'losslessHelp': 'Förlustfria bilder i full upplösning.',
  'exportAsPdf': 'Exportera som PDF',
  'exportAsPptx': 'Exportera som PPTX',
  'exportAsOdp': 'Exportera som ODP',
  'exportAsHtml': 'Exportera som HTML (Marp, offline)',
  'exportAsLatex': 'Exportera som LaTeX (Beamer)',

  'renderingSlides': 'Renderar bilder…',
  'buildingHtml': 'Bygger HTML…',
  'buildingExport': 'bygger…',
  'slideOf': 'Bild',
  'of': 'av',
  'exportedTo': 'Exporterad till:',
};

const _dutchSourceSv = {
  'Handtekening tekenen': 'Rita signatur',
  'Teken je handtekening in het vak hieronder.':
      'Rita din signatur i rutan nedan.',
  // Extra grafiektypen (vlak / horizontale staaf / waterval) en hun hints.
  'Vlak': 'Yta',
  'Horizontale staaf': 'Liggande stapel',
  'Waterval': 'Vattenfall',
  'Laatste reeks als lijn op een tweede as; de rest als staven.':
      'Sista serien som linje på en andra axel; de övriga som staplar.',
  'Eerste reeks: elke waarde is een op- of neerwaartse stap op het vorige totaal.':
      'Första serien: varje värde är ett steg upp eller ner på den löpande summan.',
  'Reeks = rij, kolom = label, celkleur volgt de waarde. Label de assen kans en impact voor een risicomatrix.':
      'Serie = rad, kolumn = etikett, cellfärgen följer värdet. Namnge axlarna sannolikhet och konsekvens för en riskmatris.',
  'Auditdossier exporteren': 'Exportera revisionsdossier',
  'Finaliseer en verzegel het rapport eerst.':
      'Slutför och försegla rapporten först.',
  'Auditdossier geëxporteerd naar:': 'Revisionsdossier exporterat till:',
  'MIAUW-pentestrapport': 'MIAUW-pentestrapport',
  'Volledige MIAUW-rapportstructuur: documentbeheer, scope, executie, managementsamenvatting, bevindingen, checklists en ondertekening.':
      'Fullständig MIAUW-rapportstruktur: dokumenthantering, omfattning, genomförande, ledningssammanfattning, resultat, checklistor och signering.',
  'Tekst voorstellen (AI)': 'Föreslå text (AI)',
  'Het model gaf geen tekst terug.': 'Modellen returnerade ingen text.',
  'Er staat al tekst. Vervangen door het AI-concept?':
      'Det finns redan text. Ersätt med AI-utkastet?',
  'RFC3161-tijdstempel': 'RFC3161-tidsstämpel',
  'Verzegel het deck eerst.': 'Försegla decket först.',
  'Verzoek (.tsq) exporteren': 'Exportera begäran (.tsq)',
  'Token (.tsr) importeren': 'Importera token (.tsr)',
  'Nog geen tijdstempel': 'Ingen tidsstämpel än',
  'Getijdstempeld op': 'Tidsstämplad den',
  'Tijdstempel komt niet overeen met de seal-hash':
      'Tidsstämpeln matchar inte sigillhashen',
  'Tijdstempelverzoek opgeslagen': 'Tidsstämpelbegäran sparad',
  'Tijdstempel geïmporteerd': 'Tidsstämpel importerad',
  'Managementsamenvatting': 'Sammanfattning för ledningen',
  'Bevindingen totaal': 'Totalt antal fynd',
  'scope-objecten getest': 'omfångsobjekt testade',
  'Gebruikte standaarden': 'Använda standarder',
  'Bewijs-hashes kopiëren': 'Kopiera bevis-hashar',
  'Bewijs-hashes gekopieerd': 'Bevis-hashar kopierade',
  'Bevindingen hernummeren': 'Numrera om fynd',
  'Scope-dekking controleren': 'Kontrollera scope-täckning',
  'Scope-dekking': 'Scope-täckning',
  'Geen dekkingsgaten': 'Inga täckningsluckor',
  'In scope, maar niet getest en geen bevinding:':
      'Inom scope, men inte testat och utan fynd:',
  'MIAUW-compliance': 'MIAUW-efterlevnad',
  'Voldaan': 'Uppfylld',
  'Openstaand': 'Öppen',
  'Uitgesloten door klant': 'Utesluten av kunden',
  'Handmatig': 'Manuell',
  'Uitsluiten': 'Uteslut',
  'Opheffen': 'Upphäv',
  'Reden voor uitsluiting': 'Skäl för uteslutning',
  'Fundamentele eisen zijn uitgesloten': 'Grundläggande krav är uteslutna',
  'Nieuwe bevinding (wizard)': 'Nytt fynd (guide)',
  'Bevinding maken': 'Skapa fynd',
  'CIA-rating (scope-object)': 'CIA-bedömning (omfångsobjekt)',
  'Vertrouwelijkheid': 'Konfidentialitet',
  'Integriteit': 'Integritet',
  'Beschikbaarheid': 'Tillgänglighet',
  'Detailslide toevoegen': 'Lägg till detaljbild',
  'Bewijsslide toevoegen': 'Lägg till bevisbild',
  'CIA-gewogen': 'CIA-viktad',
  'Severity (bevindingen)': 'Allvarlighetsgrad (fynd)',
  'CWE kiezen': 'Välj CWE',
  'Zoek op naam of CWE-nummer': 'Sök på namn eller CWE-nummer',
  'Geen CWE gevonden': 'Ingen CWE hittades',
  'Kies CWE…': 'Välj CWE…',
  'AI-concept': 'AI-utkast',
  'Nagekeken': 'Granskad',
  'Wis AI-alt-teksten': 'Rensa AI-alt-texter',
  'AI-alt-teksten wissen': 'Rensa AI-alt-texter',
  'Verwijder alle nog niet-nagekeken AI-alt-teksten? Handmatige en nagekeken alt-teksten blijven staan.':
      'Ta bort alla AI-alt-texter som ännu inte granskats? Manuella och granskade behålls.',
  'aantal': 'antal',
  'Wissen': 'Rensa',
  'AI-alt-teksten gewist.': 'AI-alt-texter rensade.',
  'Alle afbeeldingen hebben al tags.': 'Alla bilder har redan taggar.',
  'Afbeeldingen taggen…': 'Taggar bilder…',
  'afbeeldingen getagd door AI.': 'bilder taggade av AI.',
  'Ongetagde afbeeldingen taggen met AI': 'Tagga otaggade bilder med AI',
  'Ongedaan maken': 'Ångra',
  'Kon de afbeelding niet lezen voor AI-analyse.':
      'Bilden kunde inte läsas för AI-analys.',
  'Het model gaf geen alt-tekst terug.': 'Modellen returnerade ingen alt-text.',
  'Er staat al alt-tekst. Vervangen door het AI-concept?':
      'Det finns redan alt-text. Ersätt den med AI-utkastet?',
  'Vervangen': 'Ersätt',
  'AI-assistentie is niet beschikbaar. Controleer de instellingen.':
      'AI-hjälp är inte tillgänglig. Kontrollera inställningarna.',
  'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).':
      'AI-anropet misslyckades (modellen inte laddad eller servern onåbar).',
  'Bezig met AI-analyse…': 'Analyserar med AI…',
  'Stel alt-tekst voor (AI)': 'Föreslå alt-text (AI)',
  'Alt-tekst (beschrijving voor schermlezers)':
      'Alternativtext (beskrivning för skärmläsare)',
  'Hoog': 'Hög',
  'Middel': 'Medel',
  'Laag': 'Låg',
  'Informatief': 'Informativ',
  'Vernieuw uit deck': 'Uppdatera från deck',
  'Aantal bevindingen per ernst': 'Antal fynd per allvarlighetsgrad',
  'Afbeeldingen': 'Bilder',
  'Afbeeldingen en media worden gedeeld door presentaties in dezelfde map. De exacte naam kies je zo in het systeemvenster.':
      'Bilder och media delas av presentationer i samma mapp. Det exakta namnet väljer du strax i systemfönstret.',
  'Alle bibliotheken': 'Alla bibliotek',
  'Andere map…': 'Annan mapp…',
  'Bibliotheken': 'Bibliotek',
  'Geen bibliotheek': 'Inget bibliotek',
  'Je kiest de map en de naam in het volgende venster. De afbeeldingen komen in een submap images/ en media in media/, naast het presentatiebestand.':
      'Du väljer mappen och namnet i nästa fönster. Bilderna hamnar i en undermapp images/ och media i media/, bredvid presentationsfilen.',
  'Kies bestandsnaam…': 'Välj filnamn…',
  'Kies een map om de presentatie in te bewaren.':
      'Välj en mapp att spara presentationen i.',
  'Kies in welke bibliotheek de presentatie komt.':
      'Välj vilket bibliotek presentationen ska ligga i.',
  'Map toevoegen': 'Lägg till mapp',
  'Nog geen bibliotheek. Voeg er een toe bij Instellingen, of kies hierboven een map om te doorzoeken.':
      'Inget bibliotek ännu. Lägg till ett under Inställningar, eller välj en mapp ovan att söka i.',
  'Presentatie opslaan': 'Spara presentation',
  'Zo worden de bestanden bewaard': 'Så här sparas filerna',
  'Aangepast…': 'Egen…',
  'Aangepaste tijd': 'Egen tid',
  'Waarheidsverklaring': 'Sanningsförsäkran',
  'Rapporteur': 'Rapportör',
  'Certificering': 'Certifiering',
  'Nog niet ondertekend': 'Ännu inte signerad',
  'Nog niet verzegeld': 'Ännu inte förseglad',
  'Verzegeld op': 'Förseglad den',
  'Verzegeld. Sla op (Ctrl/Cmd+S) om te bewaren.':
      'Förseglad. Spara (Ctrl/Cmd+S) för att behålla den.',
  'Deze rapportage is naar waarheid opgesteld.':
      'Denna rapport har upprättats sanningsenligt.',
  'Verzegelen kan pas als alle AI-concepten zijn nagekeken. Nog te controleren op dia:':
      'Försegling är möjlig först när alla AI-utkast har granskats. Återstår att kontrollera på bild(er):',
  'Uit sjabloon…': 'Från mall…',
  'Sjabloon kiezen': 'Välj mall',
  'Scope-object': 'Scope-objekt',
  'CVSS 4.0-vector': 'CVSS 4.0-vektor',
  'Bevestiging (reproductie)': 'Bekräftelse (reproduktion)',
  'Mogelijke impact': 'Möjlig påverkan',
  'Aanbeveling': 'Rekommendation',
  'Bevinding-id': 'Iakttagelse-id',
  'Controleer de CVSS-vector': 'Kontrollera CVSS-vektorn',
  'Notitie': 'Anteckning',
  'Status': 'Status',
  'getoetst': 'testad',
  'Test toevoegen': 'Lägg till test',
  'Test verwijderen': 'Ta bort test',
  'Niet getoetst': 'Inte testad',
  'Getoetst': 'Testad',
  'Afwijking': 'Avvikelse',
  'Niet toetsbaar': 'Inte testbar',
  'Object': 'Objekt',
  'gedekt': 'täckt',
  'Object toevoegen': 'Lägg till objekt',
  'Object verwijderen': 'Ta bort objekt',
  'Niet getest': 'Inte testad',
  'Getest': 'Testad',
  'Onbereikbaar': 'Onåbar',
  'Infrastructuur': 'Infrastruktur',
  'Mobiel': 'Mobil',
  'Overig': 'Övrigt',
  '(leeg)': '(tom)',
  'Audio': 'Ljud',
  'Bijschrift': 'Bildtext',
  'Bron citaat': 'Citatkälla',
  'Codetaal': 'Kodspråk',
  'Geen zichtbare verschillen — de slides zijn inhoudelijk gelijk.':
      'Inga synliga skillnader — bilderna har samma innehåll.',
  'In meerdere presentaties': 'I flera presentationer',
  'Kop kolom 1': 'Rubrik kolumn 1',
  'Kop kolom 2': 'Rubrik kolumn 2',
  'Lijststijl': 'Liststil',
  'Notities': 'Anteckningar',
  'Tweede bijschrift': 'Andra bildtexten',
  'Tweede opsomming': 'Andra punktlistan',
  'Vergelijk met:': 'Jämför med:',
  'Verschillen': 'Skillnader',
  'Verschillen tussen slides': 'Skillnader mellan bilder',
  'duplica(a)t(en) verborgen': 'dubblett(er) dolda',
  'slides — verfijn je zoekopdracht': 'bilder — förfina din sökning',
  'unieke slide(s)': 'unik(a) bild(er)',
  'Bevinding': 'Iakttagelse',
  'Bevindingenoverzicht': 'Sammanställning av iakttagelser',
  'Scope-matrix': 'Omfattningsmatris',
  'Ondertekening': 'Underskrift',
  'Eén bevinding: onderwerp, CVSS-score, CWE/CVE en de beschrijving, reproductie, impact en aanbeveling.':
      'En iakttagelse: ämne, CVSS-poäng, CWE/CVE samt beskrivning, reproduktion, konsekvens och rekommendation.',
  'Managementoverzicht: aantallen bevindingen per ernst, met grafiek en hoofdoorzaken.':
      'Ledningsöversikt: antal iakttagelser per allvarlighetsgrad, med diagram och grundorsaker.',
  'Een testlijst volgens een standaard (zoals OWASP WSTG), met status per test en koppeling naar bevindingen.':
      'En testlista enligt en standard (såsom OWASP WSTG), med status per test och koppling till iakttagelser.',
  'Een matrix van scope-objecten tegen standaarden en de mate van toetsing.':
      'En matris över omfattningsobjekt mot standarder och graden av granskning.',
  'De waarheidsverklaring met rapporteur, certificering, handtekening en verzegeling.':
      'Sanningsförsäkran med rapportör, certifiering, underskrift och försegling.',
  'Uitbreidingen': 'Tillägg',
  'Gegevens opschonen': 'Rensa data',
  'Gegevens lokaal beschikbaar': 'Data tillgängliga lokalt',
  'Geef eerst toestemming voor uitgaand verkeer bij Licentie en Privacy.':
      'Ge först samtycke till utgående trafik under Licens och integritet.',
  'Op het web nog niet beschikbaar': 'Inte tillgängligt på webben ännu',
  'Nog niet opgehaald': 'Inte hämtat ännu',
  'AI-assistentie': 'AI-assistans',
  'AI-assistentie is alleen beschikbaar in de desktopversie.':
      'AI-assistans är endast tillgängligt i skrivbordsversionen.',
  'AI-assistentie is optioneel en staat standaard uit. Er wordt niets verstuurd totdat je dit inschakelt en zelf een backend kiest. Deze functie werkt alleen op de desktopversie.':
      'AI-assistans är valfritt och avstängt som standard. Ingenting skickas förrän du aktiverar det och själv väljer en backend. Den här funktionen fungerar endast i skrivbordsversionen.',
  'AI-backend': 'AI-backend',
  'Lokaal (op dit apparaat)': 'Lokalt (på den här enheten)',
  'Zelf gehost (eigen server)': 'Självhostad (din egen server)',
  'Cloud (externe dienst)': 'Moln (extern tjänst)',
  'Modelnaam': 'Modellnamn',
  'API-sleutel (optioneel)': 'API-nyckel (valfritt)',
  'Een clouddienst vereist eerst je privacytoestemming bij "Licentie en Privacy" en werkt niet in de webversie.':
      'En molntjänst kräver först ditt integritetssamtycke under "Licens och integritet" och fungerar inte i webbversionen.',
  'Ik begrijp dat gegevens naar deze externe dienst worden verstuurd':
      'Jag förstår att data skickas till den här externa tjänsten',
  'Zoek een slidetype': 'Sök efter en bildtyp',
  'Alfabetisch sorteren': 'Sortera alfabetiskt',
  'Algemeen': 'Allmänt',
  'Informatieveiligheid': 'Informationssäkerhet',
  'Alle': 'Alla',
  'Linksom': 'Rotera vänster',
  'Rechtsom': 'Rotera höger',
  'Sleep de afbeelding om te kiezen welk deel zichtbaar blijft.':
      'Dra i bilden för att välja vilken del som förblir synlig.',
  'Zoek in documentatie…': 'Sök i dokumentation…',
  'Geen documenten gevonden': 'Inga dokument hittades',
  'Alleen afspelen (vergrendeld)': 'Endast uppspelning (låst)',
  'Deze presentatie is vergrendeld op alleen afspelen.':
      'Denna presentation är låst för endast uppspelning.',
  'Vergrendelt het deck tot presenteren: de editor, menu\'s en export zijn niet beschikbaar. Uitzetten kan daarna alleen door de sleutel uit het markdown-bestand te halen.':
      'Låser deck till presentation: redigeraren, menyerna och export är inte tillgängliga. Kan endast låsas upp genom att ta bort nyckeln från markdown-filen.',
  'Volledige presentatie': 'Hela presentationen',
  'Ontwerp': 'Design',
  'Gebruiker': 'Användare',
  'Techniek': 'Teknik',
  'Licentie en naleving': 'Licens och efterlevnad',
  'Architectuur': 'Arkitektur',
  'Licentienaleving': 'Licensefterlevnad',
  'Softwarestuklijst (SBOM)': 'Programvaruförteckning (SBOM)',
  'Beschermen met een wachtwoord (AES-256)':
      'Skydda med ett lösenord (AES-256)',
  'Bewaar dit wachtwoord goed: raak je het kwijt, dan is dit pakket niet meer te openen.':
      'Förvara detta lösenord säkert: om du tappar bort det går paketet inte längre att öppna.',
  'Dit pakket is met een wachtwoord beveiligd. Voer het wachtwoord in om het te openen.':
      'Detta paket är lösenordsskyddat. Ange lösenordet för att öppna det.',
  'Dit pakket is versleuteld; er kon niet om een wachtwoord worden gevraagd.':
      'Detta paket är krypterat; det gick inte att be om ett lösenord.',
  'Exporteren': 'Exportera',
  'Genereer sterk wachtwoord': 'Generera starkt lösenord',
  'Maak het langer voor betere bescherming.':
      'Gör det längre för bättre skydd.',
  'Onjuist wachtwoord. Probeer het opnieuw.': 'Fel lösenord. Försök igen.',
  'Ontgrendelen': 'Lås upp',
  'Optioneel. Alleen wie het wachtwoord heeft, kan het pakket openen.':
      'Valfritt. Endast den som har lösenordet kan öppna paketet.',
  'Redelijk': 'Godtagbart',
  'Sterk': 'Starkt',
  'Tip: een lange wachtwoordzin is veiliger dan een kort wachtwoord met symbolen.':
      'Tips: en lång lösenordsfras är säkrare än ett kort lösenord med symboler.',
  'Versleuteld pakket': 'Krypterat paket',
  'Wachtwoord': 'Lösenord',
  'Wachtwoord gekopieerd naar klembord.': 'Lösenordet kopierat till urklipp.',
  'Wachtwoord tonen': 'Visa lösenord',
  'Wachtwoord verbergen': 'Dölj lösenord',
  'Zeer sterk': 'Mycket starkt',
  'Zeer zwak': 'Mycket svagt',
  'Zwak': 'Svagt',
  'Tekst kleiner': 'Mindre text',
  'Tekst groter': 'Större text',
  'Documentatie': 'Dokumentation',
  'Gebruikershandleiding': 'Användarhandbok',
  'Bestandsformaat': 'Filformat',
  'Online openen': 'Öppna online',
  'Dit document kon niet worden geladen.':
      'Det gick inte att läsa in det här dokumentet.',
  'Kwaliteit': 'Kvalitet',
  'Slide-instellingen': 'Bildinställningar',
  'De openingsslide met een grote titel en ondertitel. Voeg via de afbeeldingsbibliotheek een achtergrondbeeld toe.':
      'Öppningsbilden med en stor titel och underrubrik. Lägg till en bakgrundsbild via bildbiblioteket.',
  'Een opsomming. Laat een regel inspringen met spaties voor een subpunt; begin met "[ ]" voor een afvinkbaar item.':
      'En punktlista. Dra in en rad med blanksteg för en underpunkt; börja med "[ ]" för en avbockningsbar post.',
  'Twee opsommingskolommen naast elkaar — handig om twee dingen te vergelijken.':
      'Två punktkolumner sida vid sida — praktiskt för att jämföra två saker.',
  'Opsomming links, afbeelding rechts. Kies een beeld uit de bibliotheek of sleep het naar binnen.':
      'Punkter till vänster, bild till höger. Välj en bild från biblioteket eller dra in en.',
  'Twee afbeeldingen naast elkaar, elk met een eigen bijschrift.':
      'Två bilder sida vid sida, var och en med egen bildtext.',
  'Eén grote, beeldvullende afbeelding met een optioneel bijschrift.':
      'En stor, helskärmsfyllande bild med en valfri bildtext.',
  'Zet begin- en eindtijd in seconden om te knippen, of knip live op het afspeelpunt in het voorbeeld.':
      'Ange start- och sluttid i sekunder för att klippa, eller klipp live vid uppspelningspunkten i förhandsvisningen.',
  'Een uitgelicht citaat met bronvermelding.':
      'Ett framhävt citat med källhänvisning.',
  'Plak een selectie uit een spreadsheet met Ctrl/Cmd+V, of typ per cel. Vink "bewerkbaar tijdens presenteren" aan om live te wijzigen.':
      'Klistra in ett urval från ett kalkylark med Ctrl/Cmd+V, eller skriv per cell. Bocka i "redigerbar under presentation" för att ändra live.',
  'Ruwe Markdown met koppen, code, wiskundige LaTeX-formules en mermaid-diagrammen.':
      'Rå Markdown med rubriker, kod, matematiska LaTeX-formler och mermaid-diagram.',
  'Een codeblok met syntaxiskleuring. Kies de programmeertaal voor de juiste opmaak.':
      'Ett kodblock med syntaxmarkering. Välj programmeringsspråket för rätt formatering.',
  'Importeer cijfers uit een CSV-bestand of typ ze in het rooster. Kies staaf, lijn, taart of radar.':
      'Importera siffror från en CSV-fil eller skriv in dem i rutnätet. Välj stapel, linje, tårta eller radar.',
  'Een dashboard van meters. Geef elke meter een waarde, bereik en label.':
      'En instrumentpanel med mätare. Ge varje mätare ett värde, intervall och en etikett.',
  'Een interactieve quizvraag. Kies het soort (meerkeuze, juist/onjuist, meerdere goed of volgorde) en vul de antwoorden in.':
      'En interaktiv quizfråga. Välj typen (flerval, sant/falskt, flera rätta eller ordning) och fyll i svaren.',
  'Een tijdlijn van gedateerde gebeurtenissen. Kies de opmaak en hoe de gebeurtenissen verschijnen.':
      'En tidslinje med daterade händelser. Välj layouten och hur händelserna visas.',
  'De TLP-classificatie bepaalt wie de slide mag zien. Slides met een hoger niveau dan het deck worden bij presenteren en exporteren weggelaten.':
      'TLP-klassificeringen avgör vem som får se bilden. Bilder med en högre nivå än decket utelämnas vid presentation och export.',
  'Wat kan ik hier?': 'Vad kan jag göra här?',
  'Uitvoeren': 'Kör',
  'Nieuwe grafiek': 'Nytt diagram',
  'Commandopalet': 'Kommandopalett',
  'Typ een commando…': 'Skriv ett kommando…',
  'Instelling opslaan is mislukt.': 'Det gick inte att spara inställningen.',
  'Let op: de webversie kan alleen ophalen van servers die dit toestaan (CORS).':
      'Obs: webbversionen kan bara hämta från servrar som tillåter det (CORS).',
  'Geen': 'Ingen',
  'Nieuw': 'Ny',
  'Verwijderen': 'Ta bort',
  'Herstellen': 'Återställ',
  'Opslaan en sluiten': 'Spara och stäng',
  'Niet opslaan': 'Spara inte',
  'Niet-opgeslagen werk herstellen?': 'Återställa osparat arbete?',
  'Niet-opgeslagen wijzigingen': 'Osparade ändringar',
  'Er is een presentatie met niet-opgeslagen wijzigingen gevonden van een vorige sessie:':
      'En presentation med osparade ändringar hittades från en tidigare session:',
  'Deze presentatie heeft niet-opgeslagen wijzigingen. Sla de presentatie op voordat het tabblad sluit.':
      'Den här presentationen har osparade ändringar. Spara den innan du stänger fliken.',
  'Importeren via URL': 'Importera från URL',
  'Plak de link naar een .ocideck-pakket of een Marp-markdownbestand.':
      'Klistra in länken till ett .ocideck-paket eller en Marp-Markdown-fil.',
  'Ophalen': 'Hämta',
  'Laat los om toe te voegen': 'Släpp för att lägga till',
  'Afbeeldingen → nieuwe slides · .md / .ocideck → openen':
      'Bilder → nya bilder · .md / .ocideck → öppna',
  'Open eerst een presentatie om afbeeldingen toe te voegen.':
      'Öppna en presentation innan du lägger till bilder.',
  'Alle slides zijn overgeslagen — niets om te tonen.':
      'Alla bilder är överhoppade, så det finns inget att visa.',
  'Alle slides zijn overgeslagen — niets om te exporteren.':
      'Alla bilder är överhoppade, så det finns inget att exportera.',
  'Kon dit pakket niet importeren.': 'Kunde inte importera det här paketet.',
  'Pakket geëxporteerd naar:': 'Paket exporterat till:',
  'Export mislukt:': 'Exporten misslyckades:',
  'Deze slide kan geen afbeelding ontvangen. Kies eerst een afbeeldingsslide.':
      'Den här bilden kan inte ta emot en bild. Välj en bildbild först.',
  'Kon van deze URL geen presentatie ophalen.':
      'Kunde inte hämta en presentation från den här URL:en.',
  'Sleep om de slide-preview breder of smaller te maken':
      'Dra för att göra bildförhandsvisningen bredare eller smalare',
  'TLP-classificatie (Traffic Light Protocol)':
      'TLP-klassificering (Traffic Light Protocol)',
  'Titelpagina': 'Titelbild',
  'Tussentitel': 'Avsnittsrubrik',
  'Alleen Bullets': 'Endast punkter',
  'Twee Bulletkolommen': 'Två punktkolumner',
  'Bullets + Afbeelding': 'Punkter + bild',
  'Twee Afbeeldingen': 'Två bilder',
  'Grote Afbeelding': 'Stor bild',
  'Video': 'Video',
  'Tabel': 'Tabell',
  'Vrije Markdown': 'Fri Markdown',
  'Overgeslagen': 'Överhoppad',
  'Weer tonen bij presenteren/exporteren': 'Visa igen vid presentation/export',
  'Overslaan bij presenteren/exporteren': 'Hoppa över vid presentation/export',
  'Kopiëren': 'Kopiera',
  'Kopieer als afbeelding': 'Kopiera som bild',
  'Dupliceren': 'Duplicera',
  'Niet meer overslaan': 'Hoppa inte över',
  'Overslaan': 'Hoppa över',
  'Titel': 'Titel',
  'Titel (optioneel)': 'Titel (valfritt)',
  'Slide titel': 'Bildtitel',
  'Ondertitel': 'Underrubrik',
  'Subtitel': 'Underrubrik',
  'Optionele subtitel': 'Valfri underrubrik',
  'Bullets': 'Punkter',
  'Bullet toevoegen': 'Lägg till punkt',
  'Verwijder': 'Ta bort',
  'Citaat': 'Citat',
  'Citaat tekst...': 'Citattext...',
  'Auteur': 'Författare',
  'Naam van de auteur': 'Författarens namn',
  'Achtergrondafbeelding': 'Bakgrundsbild',
  'Achtergrondafbeelding (optioneel)': 'Bakgrundsbild (valfritt)',
  'De afbeelding wordt schermvullend als achtergrond getoond met verminderde opaciteit zodat de tekst leesbaar blijft.':
      'Bilden visas i helskärm som bakgrund med minskad opacitet så att texten förblir läsbar.',
  'Zoom achtergrond': 'Bakgrundszoom',
  'Zoom afbeelding': 'Bildzoom',
  'Afbeelding (rechts)': 'Bild (höger)',
  'Bullets (links)': 'Punkter (vänster)',
  'Breedte afbeeldingspaneel (rechts)': 'Bildpanelens bredd (höger)',
  'Linker afbeelding': 'Vänster bild',
  'Rechter afbeelding': 'Höger bild',
  'Verdeling (links / rechts)': 'Fördelning (vänster / höger)',
  'Audio bij deze slide': 'Ljud för den här bilden',
  'Audio automatisch afspelen': 'Spela ljud automatiskt',
  'Audio verwijderen': 'Ta bort ljud',
  'Geen audiobestand gekozen': 'Ingen ljudfil vald',
  'Video automatisch afspelen': 'Spela video automatiskt',
  'Kiezen': 'Välj',
  'Uit bibliotheek…': 'Från biblioteket…',
  'Van computer…': 'Från datorn…',
  'Afbeelding plakken uit klembord': 'Klistra in bild från urklipp',
  'Kopieer afbeelding naar klembord': 'Kopiera bild till urklipp',
  'Afbeelding gekopieerd naar klembord.': 'Bild kopierad till urklipp.',
  'Kopiëren naar klembord mislukt.': 'Kopieringen till urklipp misslyckades.',
  'Verwijder afbeelding': 'Ta bort bild',
  'Geen afbeelding gekozen': 'Ingen bild vald',
  'Caption / bronvermelding (bijv. © Naam Fotograaf)':
      'Bildtext / kredit (t.ex. © Fotografens namn)',
  'Caption / bronvermelding': 'Bildtext / kredit',
  'Beschrijving (doorzoekbaar)': 'Beskrivning (sökbar)',
  'Markdown inhoud': 'Markdown-innehåll',
  '# Slide\n\nInhoud hier...': '# Bild\n\nInnehåll här...',
  'Rij toevoegen': 'Lägg till rad',
  'Kolom toevoegen': 'Lägg till kolumn',
  'Kolom': 'Kolumn',
  'verwijderen': 'ta bort',
  'Koprij verwijderen': 'Ta bort rubrikrad',
  'Rij verwijderen': 'Ta bort rad',
  'Tip: druk op Enter binnen een cel voor een nieuwe regel.':
      'Tips: tryck på Enter i en cell för en ny rad.',
  'Presentatie openen': 'Öppna presentation',
  'Opslaan als': 'Spara som',
  'Pakket importeren': 'Importera paket',
  'Pakket exporteren': 'Exportera paket',
  'Map met presentaties kiezen': 'Välj presentationsmapp',
  'Map voor exports': 'Exportmapp',
  'Logo kiezen': 'Välj logotyp',
  'Kies een afbeelding': 'Välj en bild',
  'Kies een video': 'Välj en video',
  'Kies een audiobestand': 'Välj en ljudfil',
  'Bladeren…': 'Bläddra…',
  'Geen map gekozen': 'Ingen mapp vald',
  'Map kiezen': 'Välj mapp',
  'Kies een map met presentaties om te beginnen.':
      'Välj en mapp med presentationer för att börja.',
  'meer treffer(s)': 'fler träff(ar)',
  'Slide zoeken': 'Hitta bild',
  'Slides importeren': 'Importera bilder',
  'Importeren': 'Importera',
  'Klaar': 'Klar',
  'Toevoegen': 'Lägg till',
  'Toegevoegd': 'Tillagd',
  'Selecteer alles': 'Markera alla',
  'Deselecteer alles': 'Avmarkera alla',
  'Zoek slides op tekst, titel, onderschrift, pad…':
      'Sök bilder efter text, titel, bildtext, sökväg…',
  'Zoek op presentatie, titel of tekst…':
      'Sök efter presentation, titel eller text…',
  'Geen andere presentaties (.md) in deze map gevonden.':
      'Inga andra presentationer (.md) hittades i den här mappen.',
  'Geen slides gevonden voor': 'Inga bilder hittades för',
  'Typ zoektermen om slides uit al je presentaties te vinden.':
      'Skriv sökord för att hitta bilder i alla dina presentationer.',
  'toegevoegd': 'tillagd',
  'Eerste': 'Första',
  'treffer(s)': 'träff(ar)',
  'slide': 'bild',
  'Zoeken en vervangen': 'Sök och ersätt',
  'Zoeken naar': 'Sök',
  'Vervangen door': 'Ersätt med',
  'Vervang': 'Ersätt',
  'Vorige': 'Föregående',
  'Volgende': 'Nästa',
  'Vet': 'Fet',
  'Cursief': 'Kursiv',
  'Doorhalen': 'Genomstruken',
  'Code': 'Kod',
  'Link': 'Länk',
  'Kop': 'Rubrik',
  'Hoofdlettergevoelig': 'Skiftlägeskänslig',
  'Vervang alles': 'Ersätt alla',
  'Niets vervangen': 'Inget ersatt',
  'vervangen': 'ersatta',
  'Geen resultaten': 'Inga resultat',
  'resultaat': 'resultat',
  'resultaten': 'resultat',
  'Nieuwe presentatie': 'Ny presentation',
  'Bijv. Kwartaalupdate Q4': 'T.ex. Q4-uppdatering',
  'Vul een titel in': 'Ange en titel',
  'Aanmaken': 'Skapa',
  'Slide type kiezen': 'Välj bildtyp',
  'Presentatie-eigenschappen': 'Presentationsegenskaper',
  'Versie': 'Version',
  'Bijv. Jan Jansen': 'T.ex. Anna Andersson',
  'Bijv. Vigilis': 'T.ex. Vigilis',
  'Bijv. 2026-05-30': 'T.ex. 2026-05-30',
  'Beschrijving': 'Beskrivning',
  'Korte omschrijving van de presentatie': 'Kort presentationsbeskrivning',
  'Trefwoorden': 'Nyckelord',
  'Komma-gescheiden, bijv. kwartaal, cijfers, 2026':
      'Kommaseparerade, t.ex. kvartal, siffror, 2026',
  'Deze gegevens worden in de markdown opgeslagen en zijn doorzoekbaar bij het openen.':
      'Dessa uppgifter lagras i Markdown och är sökbara vid öppning.',
  'App-thema': 'Apptema',
  'Look-and-feel': 'Utseende och känsla',
  'Kopie maken en aanpassen': 'Skapa och anpassa en kopia',
  'Thema verwijderen': 'Ta bort tema',
  'Themanaam': 'Temanamn',
  'Dit is een ingebouwd thema. Maak een kopie om kleuren aan te passen.':
      'Det här är ett inbyggt tema. Skapa en kopia för att anpassa dess färger.',
  'Donkere interface': 'Mörkt gränssnitt',
  'Lettertype interface': 'Gränssnittsteckensnitt',
  'Past contrast, invoervelden en systeemcomponenten aan.':
      'Justerar kontrast, inmatningsfält och systemkomponenter.',
  'Hoofdkleur en bovenbalk': 'Primärfärg och övre fält',
  'Knoppen en accenten': 'Knappar och accenter',
  'Schermachtergrond': 'Skärmbakgrund',
  'Kaarten en dialogen': 'Kort och dialoger',
  'Gedempte tekst': 'Dämpad text',
  'Zijpanelen': 'Sidopaneler',
  'Tekst op zijpanelen': 'Text på sidopaneler',
  'Voorbeeldtekst': 'Exempeltext',
  'Knop': 'Knapp',
  'Naam van het stijlprofiel': 'Namn på stilprofilen',
  'Stijlprofiel': 'Stilprofil',
  'Nieuw profiel': 'Ny profil',
  'Standaardprofiel laden': 'Ladda standardprofil',
  'Profiel verwijderen': 'Ta bort profil',
  'Lettertype': 'Teckensnitt',
  'Kleuren': 'Färger',
  'Tekst': 'Text',
  'Accent / bullets': 'Accent / punkter',
  'Tabeltekst': 'Tabelltext',
  'Tabel koptekst': 'Tabellrubriktext',
  'Titelachtergrond': 'Titelbakgrund',
  'Titeltekst': 'Titeltext',
  'Sectieachtergrond': 'Avsnittsbakgrund',
  'Geselecteerd': 'Vald',
  'Logo': 'Logotyp',
  'Geen logo ingesteld': 'Ingen logotyp inställd',
  'Verwijder logo': 'Ta bort logotyp',
  'Logo positie': 'Logotypposition',
  'Linksboven': 'Uppe till vänster',
  'Rechtsboven': 'Uppe till höger',
  'Linksonder': 'Nere till vänster',
  'Rechtsonder': 'Nere till höger',
  'Footertekst': 'Sidfotstext',
  'bijv. Vertrouwelijk · {title} · {date}':
      't.ex. Konfidentiellt · {title} · {date}',
  'Footerpositie': 'Sidfotsposition',
  'Tokens: {page}, {total}, {date}, {title}. Footer verschijnt op alle slides behalve titel- en sectieslides, tenzij je hem per slide uitzet.':
      'Token: {page}, {total}, {date}, {title}. Sidfoten visas på alla bilder utom titel- och avsnittsbilder, om du inte inaktiverar den per bild.',
  'Links': 'Vänster',
  'Midden': 'Centrerat',
  'Rechts': 'Höger',
  'Paginanummers tonen (rechtsonder)': 'Visa sidnummer (nere till höger)',
  'Voorvertoning': 'Förhandsvisning',
  'De snelle bruine vos springt over de luie hond.':
      'Yxskaftbud, ge vår WC-zonmö IQ-hjälp.',
  'Preview': 'Förhandsvisning',
  'Uitzoomen': 'Zooma ut',
  'Uitgezoomd': 'Utzoomad',
  'Inzoomen': 'Zooma in',
  'Ingezoomd': 'Inzoomad',
  'van de foto zichtbaar': 'av fotot synligt',
  'Volledig zichtbaar (100%)': 'Helt synligt (100 %)',
  'Uitzoomen (meer van de foto zichtbaar)': 'Zooma ut (mer av fotot synligt)',
  'Inzoomen (minder van de foto zichtbaar)':
      'Zooma in (mindre av fotot synligt)',
  'Terugzetten (volledige afbeelding zichtbaar)':
      'Återställ (hela bilden synlig)',
  'Zoom resetten': 'Återställ zoom',
  'Preview inklappen': 'Fäll ihop förhandsvisning',
  'Preview uitklappen': 'Fäll ut förhandsvisning',
  'Vorige slide': 'Föregående bild',
  'Volgende slide': 'Nästa bild',
  'paginering aan': 'sidnumrering på',
  'Thema': 'Tema',
  'volledig deck': 'hela däcket',
  'Slide': 'Bild',
  'TYPE': 'TYP',
  'STIJL': 'STIL',
  'Terug naar standaardstijl': 'Tillbaka till standardstil',
  'Sprekersnotities...': 'Talaranteckningar...',
  'Sprekersnotities': 'Talaranteckningar',
  'Notities voor tijdens het presenteren':
      'Anteckningar för under presentationen',
  'Toepassen': 'Tillämpa',
  'Markdown kon niet worden verwerkt. Controleer de syntax.':
      'Markdown kunde inte bearbetas. Kontrollera syntaxen.',
  'Controleren': 'Kontrollera syntax',
  'Syntaxproblemen gevonden': 'Syntaxproblem hittades',
  'De markdown bevat': 'Markdown innehåller',
  'fout(en) en': 'fel och',
  'waarschuwing(en). Slides kunnen daardoor verkeerd worden ingelezen.':
      'varning(ar). Bilder kanske inte tolkas korrekt.',
  'Terug naar editor': 'Tillbaka till redigeraren',
  'Toch toepassen': 'Tillämpa ändå',
  'Geen syntaxproblemen gevonden': 'Inga syntaxproblem hittades',
  'fout(en),': 'fel,',
  'waarschuwing(en)': 'varning(ar)',
  'Afbeelding kiezen': 'Välj bild',
  'Afbeeldingen laden…': 'Läser in bilder…',
  'Sluiten (Esc)': 'Stäng (Esc)',
  'Zoek op naam of beschrijving…': 'Sök efter namn eller beskrivning…',
  'Raster': 'Rutnät',
  'Coverflow': 'Coverflow',
  'Geen afbeeldingen gevonden': 'Inga bilder hittades',
  'Geen resultaten voor': 'Inga resultat för',
  'Pas je zoekterm aan of voeg een beschrijving toe.':
      'Justera ditt sökord eller lägg till en beskrivning.',
  'Selecteer een\nafbeelding': 'Välj en\nbild',
  'Gekopieerd': 'Kopierad',
  'Afbeelding verwijderen?': 'Ta bort bild?',
  'Het bestand wordt permanent van schijf verwijderd. Deze actie kan niet ongedaan worden gemaakt.':
      'Filen tas bort permanent från disken. Den här åtgärden kan inte ångras.',
  'Let op: deze afbeelding wordt nog gebruikt in':
      'Varning: den här bilden används fortfarande i',
  'Verwijderen maakt die slides leeg. Dit kan niet ongedaan worden gemaakt.':
      'Om du tar bort den töms dessa bilder. Detta kan inte ångras.',
  '↑↓←→ navigeren  ·  Enter kiezen  ·  Dubbelklik selecteert':
      '↑↓←→ navigera  ·  Enter väljer  ·  Dubbelklick markerar',
  'Sneltoetsen': 'Kortkommandon',
  'Toetsenlegenda': 'Teckenförklaring',
  'spatie': 'mellanslag',
  'klik': 'klick',
  'cijfers': 'siffror',
  'Klik of druk op H / Esc om te sluiten':
      'Klicka eller tryck på H / Esc för att stänga',
  'Naar slidenummer': 'Gå till bildnummer',
  'Eerste · laatste slide': 'Första · sista bilden',
  'Slide-overzicht': 'Bildöversikt',
  'Slide-overzicht (pijltjes + Enter)': 'Bildöversikt (pilar + Enter)',
  'Presenter view (notities, klok)': 'Presentatörsvy (anteckningar, klocka)',
  'Scherm wisselen (meerdere schermen)': 'Byt skärm (flera skärmar)',
  'Zwart · wit scherm': 'Svart · vit skärm',
  'Automatische modus aan/uit': 'Automatiskt läge på/av',
  'Herhalen (loop) aan/uit': 'Upprepa (loop) på/av',
  'Deze legenda': 'Denna teckenförklaring',
  'Terug / afsluiten': 'Tillbaka / avsluta',
  'Tijd resetten (R)': 'Nollställ tid (R)',
  'HUIDIGE SLIDE': 'AKTUELL BILD',
  'VOLGENDE': 'NÄSTA',
  'NOTITIES': 'ANTECKNINGAR',
  'Einde van de presentatie': 'Slut på presentationen',
  'Verstreken': 'Förfluten',
  'Klok': 'Klocka',
  'Geen notities voor deze slide.': 'Inga anteckningar för den här bilden.',
  'Mijn notities': 'Mina anteckningar',
  'Gebruikersnotities': 'Användaranteckningar',
  'Gebruikersnotities voor deze slide...':
      'Användaranteckningar för den här bilden...',
  'Notities weggooien': 'Släng anteckningar',
  'Notities voor de ontvanger tijdens een cursus':
      'Anteckningar för mottagaren under en kurs',
  'Mijn notities aan/uit': 'Växla mina anteckningar på/av',
  'Wissel scherm (S)': 'Byt skärm (S)',
  'Kon niet van scherm wisselen.': 'Kunde inte byta skärm.',
  'P publiek · H legenda · G overzicht · B/W zwart/wit · R tijd · Esc stop':
      'P publik · H teckenförklaring · G översikt · B/W svart/vit · R tid · Esc stopp',
  'P publiek · H legenda · S scherm · G overzicht · B/W zwart/wit · R tijd · Esc stop':
      'P publik · H teckenförklaring · S skärm · G översikt · B/W svart/vit · R tid · Esc stopp',
  'pijltjes + Enter of klik om te springen':
      'pilar + Enter eller klicka för att hoppa',
  'Afsluiten (Escape)': 'Avsluta (Escape)',
  'Sluiten (G of Esc)': 'Stäng (G eller Esc)',
  'Slide renderen…': 'Renderar bild…',
  'Slide gekopieerd naar klembord.': 'Bilden kopierad till urklipp.',
  'Kopiëren mislukt.': 'Kopieringen misslyckades.',
  'Geen ander deck open. Open eerst een ander tabblad.':
      'Inget annat deck är öppet. Öppna en annan flik först.',
  '1 slide kopiëren naar…': 'Kopiera 1 bild till…',
  'slides kopiëren naar…': 'bilder att kopiera till…',
  'slide(s) gekopieerd naar': 'bild(er) kopierade till',
  '1 slide geïmporteerd.': '1 bild importerad.',
  'slides geïmporteerd.': 'bilder importerade.',
  'Export wordt voorbereid…': 'Förbereder export…',
  'tip(s)': 'tips',
  'fout(en)': 'fel',
  'Kwaliteitsoverzicht': 'Kvalitetsöversikt',
  'Bekijk meldingen…': 'Visa meddelanden…',
  'Bekijk alle meldingen…': 'Visa alla meddelanden…',
  'Tips': 'Tips',
  'Waarschuwingen': 'Varningar',
  'Fouten': 'Fel',
  'Tip: voeg alt-tekst / bijschrift toe voor toegankelijkheid':
      'Tips: lägg till alt-text / bildtext för tillgänglighet',
  'Zoek in slides…': 'Sök i bilder…',
  'Geen slides met': 'Inga bilder med',
  'SLIDES': 'BILDER',
  'Geen afbeelding op het klembord gevonden.': 'Ingen bild hittades i urklipp.',
  'Afbeelding plakken': 'Klistra in bild',
  'Slide toevoegen': 'Lägg till bild',
  'Slide plakken': 'Klistra in bild',
  '1 slide overgeslagen': '1 bild överhoppad',
  'slides overgeslagen': 'bilder överhoppade',
  'Alles tonen': 'Visa alla',
  'geselecteerd': 'markerade',
  'Kopiëren naar ander deck': 'Kopiera till ett annat deck',
  'Weer tonen': 'Visa igen',
  'Selectie opheffen': 'Avmarkera',
  'Ik ga akkoord met de EUPL 1.2-licentie en heb gelezen welke gegevens OciDeck bewaart.':
      'Jag godkänner licensen EUPL 1.2 och har läst vilka data OciDeck lagrar.',
  'Lees de volledige licentie': 'Läs hela licensen',
  'OciDeck is vrije software onder de EUPL 1.2-licentie. Voordat je begint, vragen we je de licentie te accepteren. Hieronder lees je ook welke gegevens OciDeck op dit apparaat bewaart en wanneer er iets je apparaat verlaat.':
      'OciDeck är fri programvara under licensen EUPL 1.2. Innan du börjar ber vi dig godkänna licensen. Nedan kan du också läsa vilka data OciDeck lagrar på den här enheten och när något lämnar din enhet.',
  'OciDeck verzamelt geen statistieken en stuurt uit zichzelf niets naar buiten. Standaard blijft alles op dit apparaat. Gegevens verlaten dit apparaat alleen als jij dat kiest:\n\n•  Nextcloud/WebDAV: verbind je met een server, dan worden je inlognaam en wachtwoord bewaard (het wachtwoord veilig in de sleutelbos van je systeem) en worden de presentaties die je opent of opslaat naar die server verstuurd.\n•  Openen via URL: OciDeck haalt het bestand op van het adres dat je invoert.\n•  Online media (staat standaard uit): indien ingeschakeld laadt OciDeck afbeeldingen en video\'s van de adressen in je dia\'s.\n•  Externe links (zoals de online licentie) openen in je browser.':
      'OciDeck samlar ingen statistik och skickar inget på egen hand. Som standard stannar allt på den här enheten. Data lämnar enheten bara när du väljer det:\n\n•  Nextcloud/WebDAV: när du ansluter till en server sparas ditt användarnamn och lösenord (lösenordet säkert i systemets nyckelring) och de presentationer du öppnar eller sparar skickas till den servern.\n•  Öppna via URL: OciDeck hämtar filen från den adress du anger.\n•  Onlinemedia (av som standard): när det är aktiverat laddar OciDeck bilder och videor från adresserna i dina bilder.\n•  Externa länkar (som onlinelicensen) öppnas i din webbläsare.',
  'OciDeck wordt geleverd onder de European Union Public Licence v1.2. Door akkoord te gaan aanvaard je deze licentie. Je mag OciDeck gebruiken, kopiëren, aanpassen en verspreiden onder de voorwaarden van de EUPL 1.2.':
      'OciDeck tillhandahålls under European Union Public Licence v1.2. Genom att godkänna accepterar du denna licens. Du får använda, kopiera, ändra och distribuera OciDeck enligt villkoren i EUPL 1.2.',
  'Om te werken en je werk niet te verliezen, bewaart OciDeck gegevens lokaal op dit apparaat:\n\n•  Je instellingen en voorkeuren (taal, mappen, stijl- en weergaveprofielen, recente bestanden).\n•  Je presentatiematerialen: de presentaties die je opslaat, automatische herstelkopieën en bijlagen zoals afbeeldingsbeschrijvingen.\n•  Deze toestemmingskeuze.\n\nJe kunt dit verwijderen door de bestanden te wissen of de instellingen te resetten.':
      'För att fungera och för att skydda ditt arbete lagrar OciDeck data lokalt på den här enheten:\n\n•  Dina inställningar och preferenser (språk, mappar, stil- och utseendeprofiler, senaste filer).\n•  Ditt presentationsmaterial: de presentationer du sparar, automatiska återställningskopior och bilagor såsom bildbeskrivningar.\n•  Detta samtyckesval.\n\nDu kan ta bort detta genom att radera filerna eller återställa inställningarna.',
  'Volledige licentie online (23 officiële taalversies)':
      'Fullständig licens online (23 officiella språkversioner)',
  'Wat OciDeck op dit apparaat bewaart':
      'Vad OciDeck lagrar på den här enheten',
  'Wat je apparaat verlaat': 'Vad som lämnar din enhet',
  'Vul server-URL en gebruikersnaam in': 'Ange server-URL och användarnamn',
  'Verbinding mislukt': 'Anslutningen misslyckades',
  'Aanmelden mislukt — controleer gebruikersnaam en wachtwoord':
      'Inloggningen misslyckades — kontrollera användarnamn och lösenord',
  'De server staat op een privé-adres. Vink "Vertrouwde interne server" aan om verbinding toe te staan.':
      'Servern finns på en privat adress. Kryssa i "Betrodd intern server" för att tillåta anslutningen.',
  'Map niet gevonden op de server': 'Mappen hittades inte på servern',
  'Ongeldige server-URL': 'Ogiltig server-URL',
  'Het antwoord van de server was te groot': 'Serversvaret var för stort',
  'Nextcloud': 'Nextcloud',
  'Server-URL': 'Server-URL',
  'Gebruikersnaam': 'Användarnamn',
  'App-wachtwoord': 'App-lösenord',
  'Maak hiervoor een app-wachtwoord aan in Nextcloud':
      'Skapa ett app-lösenord för detta i Nextcloud',
  'Submap (optioneel)': 'Undermapp (valfritt)',
  'Vertrouwde interne server': 'Betrodd intern server',
  'Nodig wanneer de server op een privé- of thuisnetwerk (LAN) draait. Sta alleen verbindingen toe naar servers die je zelf vertrouwt.':
      'Behövs när servern körs på ett privat nätverk eller hemnätverk (LAN). Tillåt bara anslutningar till servrar du själv litar på.',
  'Verbinding testen': 'Testa anslutning',
  'Verbinding gelukt': 'Anslutningen lyckades',
  'Wijzigingen worden bewaard wanneer je op Opslaan klikt.':
      'Ändringar sparas när du klickar på Spara.',
  'Vernieuwen': 'Uppdatera',
  'Deze map is leeg': 'Den här mappen är tom',
  'Kon dit bestand niet openen.': 'Kunde inte öppna den här filen.',
  'Dit is geen Marp/OciDeck-presentatie.':
      'Det här är ingen Marp/OciDeck-presentation.',
  'Downloaden mislukt:': 'Nedladdningen misslyckades:',
  'Opslaan mislukt:': 'Sparandet misslyckades:',
  'Opslaan naar Nextcloud': 'Spara till Nextcloud',
  'Doelpad (zonder extensie)': 'Målsökväg (utan filändelse)',
  'Als .ocideck-pakket (één bestand, met assets)':
      'Som ett .ocideck-paket (en fil, med tillgångar)',
  'Als losse .md plus afbeeldingen': 'Som en separat .md plus bilder',
  'Opslaan': 'Spara',
  'Presenteren': 'Presenterar',
  'Tijden-overzicht tonen na afloop': 'Visa tidsöversikt efteråt',
  'De tijd per slide wordt altijd gemeten; dit bepaalt alleen of het overzicht na deze presentatie verschijnt.':
      'Tiden per bild mäts alltid; detta styr bara om översikten visas efter denna presentation.',
  'Onveilige presentatie geblokkeerd': 'Osäker presentation blockerad',
  'Deze presentatie is niet geopend. Het bestand bevat inhoud die code kan uitvoeren, en een presentatie hoort alleen gegevens te bevatten — niets uitvoerbaars.':
      'Den här presentationen öppnades inte. Filen innehåller innehåll som kan köra kod, och en presentation ska bara innehålla data — inget körbart.',
  'Gevonden:': 'Hittat:',
  'Regel': 'Rad',
  'Scriptuitvoering': 'Skriptkörning',
  'Ingesloten inhoud': 'Inbäddat innehåll',
  'Onveilige URL': 'Osäker URL',
  'Zoekopdracht wissen': 'Rensa sökning',
  'Bullet verwijderen': 'Ta bort punkt',
  'Kolom verwijderen': 'Ta bort kolumn',
  'Rij omhoog': 'Flytta rad uppåt',
  'Rij omlaag': 'Flytta rad nedåt',
  'Optie verwijderen': 'Ta bort alternativ',
  'Optie toevoegen': 'Lägg till alternativ',
  'Duur verkorten': 'Minska varaktighet',
  'Duur verlengen': 'Öka varaktighet',
  'Afspelen': 'Spela upp',
  'Pauzeren': 'Pausa',
  'Opsommingsteken': 'Punkt',
  'Stip': 'Prick',
  'Pootje': 'Tass',
  'In tweeën splitsen': 'Dela i två',
  'Uitgevoerde controles': 'Utförda kontroller',
  'Contrast en leesbaarheid van tekstkleuren':
      'Kontrast och läsbarhet hos textfärger',
  'Alt-teksten en bijschriften van afbeeldingen, grafieken en media':
      'Alt-text och bildtexter för bilder, diagram och media',
  'Aanwezigheid van gekoppelde mediabestanden':
      'Förekomst av länkade mediefiler',
  'Tekstdichtheid: bullets, woorden, quotes, tabellen en code':
      'Textdensitet: punkter, ord, citat, tabeller och kod',
  'Thema, slides, footer, checklist en titels over afbeeldingen, getoetst aan WCAG AA (4,5:1 voor tekst, 3:1 voor grote tekst).':
      'Tema, bilder, sidfot, checklista och titlar över bilder, kontrollerade mot WCAG AA (4,5:1 för text, 3:1 för stor text).',
  'Elke afbeelding, grafiek, video en audio heeft een beschrijving nodig voor schermlezers en bijsluiters.':
      'Varje bild, diagram, video och ljud behöver en beskrivning för skärmläsare och handouts.',
  'Verwijzingen naar afbeeldingen, video en audio worden gecontroleerd op een bestaand bestand in het project.':
      'Referenser till bilder, video och ljud kontrolleras mot en befintlig fil i projektet.',
  'Aantal en lengte van bullets, woorden, nesting, kolombalans en de dichtheid van quotes, titels, tabellen en code zodat alles leesbaar past.':
      'Antal och längd på punkter, ord, nästling, kolumnbalans och densiteten hos citat, titlar, tabeller och kod så att allt får plats läsbart.',
  'Bodytekst met contrast onder {crit}:1 telt als fout; daarboven tot de AA-norm als waarschuwing.':
      'Brödtext med kontrast under {crit}:1 räknas som fel; däröver upp till AA-normen som varning.',
  'Geen drempelwaarde: een niet-lege beschrijving is verplicht.':
      'Inget tröskelvärde: en icke-tom beskrivning krävs.',
  'Geen drempelwaarde: het gekoppelde bestand moet binnen de projectmap bestaan.':
      'Inget tröskelvärde: den länkade filen måste finnas inom projektmappen.',
  'Waarschuwing boven {b1} bullets (1 kolom), {bcl} (checklist) of {b2} (2 kolommen); kritiek boven {bc1} of {bc2}. Woorden boven {w1}/{w2}, gemiddeld boven {avg} per bullet. Quote boven {q} tekens, titel boven {t} tekens. Nesting dieper dan niveau {lvl}. Tekst die tot onder {warn}% moet krimpen waarschuwt, onder {crit}% is kritiek.':
      'Varning över {b1} punkter (1 kolumn), {bcl} (checklista) eller {b2} (2 kolumner); kritiskt över {bc1} eller {bc2}. Ord över {w1}/{w2}, i genomsnitt över {avg} per punkt. Citat över {q} tecken, titel över {t} tecken. Nästling djupare än nivå {lvl}. Text som måste krympa under {warn}% varnar, under {crit}% är kritiskt.',
  'Zoek op deze computer': 'Sök på den här datorn',
  'Zoek op titel, pad of thema…': 'Sök på titel, sökväg eller tema…',
  'Bekende mappen worden doorzocht…': 'Söker i kända mappar…',
  'gevonden': 'hittade',
  'Geen thema': 'Inget tema',
  'Kopieer syntaxproblemen': 'Kopiera syntaxproblem',
  'Syntaxproblemen gekopieerd naar klembord.':
      'Syntaxproblem kopierade till urklipp.',
  'Online media': 'Onlinemedia',
  'Online media staat uit': 'Onlinemedia är av',
  'Online media toestaan': 'Tillåt onlinemedia',
  'Sta het live laden toe van afbeeldingen en video\'s via een URL en van YouTube/Vimeo-embeds. Standaard uit voor je privacy en veiligheid.':
      'Tillåt att bilder och videor laddas direkt från en URL och från YouTube/Vimeo-inbäddningar. Av som standard för din integritet och säkerhet.',
  'Bestandspad of URL (YouTube, Vimeo, .mp4 …)':
      'Filsökväg eller URL (YouTube, Vimeo, .mp4 …)',
  'Bestand kiezen': 'Välj fil',
  'Speel het segment van deze slide af in het voorbeeld en knip op het punt waar je wilt splitsen: het tweede deel komt op een nieuwe slide.':
      'Spela upp den här bildens segment i förhandsvisningen och klipp vid den punkt där du vill dela: den andra delen hamnar på en ny bild.',
  'Begin (sec)': 'Start (sek)',
  'Einde (sec)': 'Slut (sek)',
  'einde': 'slut',
  'Knip de video op het huidige afspeelpunt':
      'Klipp videon vid aktuellt uppspelningsläge',
  'Speel de video eerst af in het voorbeeld':
      'Spela upp videon i förhandsvisningen först',
  'Knip hier': 'Klipp här',
  'Online': 'Online',
  'Lokaal bestand': 'Lokal fil',
  'Geen video': 'Ingen video',
  'Titeltekst heeft te weinig contrast met de achtergrondafbeelding':
      'Titeltexten har för lite kontrast mot bakgrundsbilden',
  'Herstel': 'Åtgärda',
  'Tijdlijn': 'Tidslinje',
  'Indeling': 'Layout',
  'Automatisch': 'Automatisk',
  'Horizontaal': 'Horisontell',
  'Verticaal': 'Vertikal',
  'Animatie': 'Animation',
  'Intekenen bij openen': 'Rita in vid öppning',
  'Markeer als huidig punt': 'Markera som nuvarande punkt',
  'Huidig punt weghalen': 'Ta bort nuvarande punkt',
  'Stap voor stap': 'Steg för steg',
  'Geen animatie': 'Ingen animation',
  'Snel': 'Snabb',
  'Gebeurtenissen': 'Händelser',
  'Gebeurtenis toevoegen': 'Lägg till händelse',
  'Markering': 'Markering',
  'bijv. 2024': 't.ex. 2024',
  'Titel van gebeurtenis': 'Händelsetitel',
  'Omschrijving (optioneel)': 'Beskrivning (valfritt)',
  'Soort vraag': 'Frågetyp',
  'Meerkeuze': 'Flerval',
  'Vraag': 'Fråga',
  'Wat wil je vragen?': 'Vad vill du fråga?',
  'Antwoorden': 'Svar',
  'Antwoord': 'Svar',
  'Antwoord toevoegen': 'Lägg till svar',
  'Goed antwoord': 'Rätt svar',
  'Geef minstens één goed én één fout antwoord op.':
      'Ange minst ett rätt och ett fel svar.',
  'Weergave': 'Visning',
  'Aantal getoonde opties': 'Antal visade alternativ',
  'Maximale antwoordtijd in seconden (0 = geen limiet)':
      'Maximal svarstid i sekunder (0 = ingen gräns)',
  'Bij een fout antwoord': 'Vid ett fel svar',
  'Opnieuw proberen': 'Försök igen',
  'Doorgaan toestaan': 'Tillåt att fortsätta',
  'Fout = niet doorgaan; de vraag moet opnieuw.':
      'Fel = kan inte fortsätta; frågan måste göras om.',
  'Fout = wel doorgaan, maar niet opnieuw doen.':
      'Fel = får fortsätta, men inget nytt försök.',
  'Afbeelding (optioneel)': 'Bild (valfritt)',
  'Breedte afbeelding': 'Bildbredd',
  'Goed!': 'Rätt!',
  'Helaas, fout': 'Tyvärr, fel',
  'van': 'av',
  'opties worden willekeurig getoond': 'alternativ visas slumpmässigt',
  'antwoordtijd': 'svarstid',
  'bij fout: opnieuw proberen': 'vid fel: försök igen',
  'bij fout: door, niet opnieuw': 'vid fel: fortsätt, inget nytt försök',
  'Beantwoord eerst de vraag.': 'Besvara frågan först.',
  'Klik om opnieuw te proberen': 'Klicka för att försöka igen',
  'Juist / Onjuist': 'Sant / Falskt',
  'Meerdere juiste antwoorden': 'Flera rätta svar',
  'Stelling': 'Påstående',
  'Formuleer een stelling die juist of onjuist is':
      'Formulera ett påstående som är sant eller falskt',
  'Juist': 'Sant',
  'Onjuist': 'Falskt',
  'De stelling hierboven is juist of onjuist; kies welke.':
      'Påståendet ovan är sant eller falskt; välj vilket.',
  'Selecteer alle juiste antwoorden': 'Välj alla rätta svar',
  'Bevestig': 'Bekräfta',
  'Volgorde': 'Ordningsföljd',
  'Zet de antwoorden hier in de juiste volgorde. Bij presenteren worden ze geschud getoond.':
      'Lägg svaren här i rätt ordning. Vid presentation visas de blandade.',
  'Geef minstens twee antwoorden op.': 'Ange minst två svar.',
  'Tik de antwoorden aan in de juiste volgorde':
      'Tryck på svaren i rätt ordning',
  'Jouw volgorde': 'Din ordning',
  'Het juiste antwoord': 'Det rätta svaret',
  'De afbeelding wordt schermvullend als achtergrond getoond. Gebruik de waas als de titel meer rust of contrast nodig heeft.':
      'Bilden visas i helskärm som bakgrund. Använd oskärpan när titeln behöver mer lugn eller kontrast.',
  'Cockpit-kleurschema': 'Cockpit-färgschema',
  'De statuskleuren van de cockpit-meters. Maak benoemde varianten; het gekozen schema geldt voor alle cockpit-slides.':
      'Statusfärgerna för cockpit-mätarna. Skapa namngivna varianter; det valda schemat gäller för alla cockpit-bilder.',
  'Standaard': 'Standard',
  'Kleurschema verwijderen': 'Ta bort färgschema',
  'Schemanaam': 'Schemanamn',
  'Dit is het ingebouwde schema. Maak een kopie om kleuren aan te passen.':
      'Det här är det inbyggda schemat. Gör en kopia för att justera färger.',
  'Goed': 'Bra',
  'Waarschuwing': 'Varning',
  'Kritiek': 'Kritiskt',
  'Te laag (koud)': 'För lågt (kallt)',
  'Lucht (horizon)': 'Himmel (horisont)',
  'Grond (horizon)': 'Mark (horisont)',
  'De statuskleuren volgen het cockpit-kleurschema; pas het aan of maak varianten via Instellingen → Cockpit.':
      'Statusfärgerna följer cockpit-färgschemat; justera det eller skapa varianter via Inställningar → Cockpit.',
  'Veel bullets op deze slide': 'Många punkter på den här bilden',
  'bullets': 'punkter',
  'Overweeg de inhoud te splitsen.': 'Överväg att dela upp innehållet.',
  'Erg veel bullets op deze slide': 'För många punkter på den här bilden',
  'Splits deze inhoud over meerdere slides.':
      'Dela upp innehållet över flera bilder.',
  'Veel woorden in bullets': 'Många ord i punkter',
  'woorden': 'ord',
  'Maak bullets korter of splits de slide.':
      'Gör punkterna kortare eller dela bilden.',
  'Erg veel woorden in bullets': 'För många ord i punkter',
  'Gemiddeld lange bullets': 'Långa punkter i genomsnitt',
  'woorden per bullet': 'ord per punkt',
  'Maak elke bullet kernachtiger.': 'Gör varje punkt mer koncis.',
  'Bullet met meerdere zinnen gevonden. Maak bullets kernachtiger of splits de inhoud.':
      'Punkt med flera meningar hittades. Gör punkterna mer koncisa eller dela upp innehållet.',
  'Diepe bulletniveaus gevonden': 'Djupa punktnivåer hittades',
  'niveau': 'nivå',
  'Beperk nesting voor betere leesbaarheid.':
      'Begränsa nästlingen för bättre läsbarhet.',
  'Twee kolommen zijn sterk uit balans':
      'Två kolumner är kraftigt obalanserade',
  'tegenover': 'mot',
  'Verdeel of splits de inhoud.': 'Omfördela eller dela upp innehållet.',
  'Slidetitel': 'Bildtitel',
  'Cockpitmeters': 'Cockpitmätare',
  'Meter toevoegen': 'Lägg till mätare',
  'Animeren bij binnenkomst': 'Animera vid inträde',
  'Activatieduur': 'Aktiveringstid',
  'Splits slide': 'Dela bild',
  'Doornummeren vanaf vorige slide': 'Fortsätt numrering från föregående bild',
  'Begin de nummering waar de vorige slide ophield.':
      'Börja numreringen där föregående bild slutade.',
  'Volg thema-animatieduur': 'Följ temats animeringstid',
  'Animatie bij openen': 'Animera vid inträde',
  'Meter': 'Mätare',
  'Type': 'Typ',
  'Waarde': 'Värde',
  'Eenheid': 'Enhet',
  'Pitch': 'Pitch',
  'Bank': 'Bank',
  'Werkelijk': 'Faktisk',
  'Doel': 'Mål',
  'Markeringslabel': 'Markörsetikett',
  'Min': 'Min',
  'Max': 'Max',
  'Neutraal van': 'Neutral från',
  'Neutraal tot': 'Neutral till',
  'Groen van': 'Grön från',
  'Groen tot': 'Grön till',
  'Rood van': 'Röd från',
  'Snelheidsmeter': 'Hastighetsmätare',
  'Voltmeter': 'Voltmätare',
  'Thermometer': 'Termometer',
  'Hoogtemeter': 'Höjdmätare',
  'Stijgen/dalen': 'Stig/sjunk',
  'Kunstmatige horizon': 'Horisont',
  'Koers': 'Kurs',
  'Ander profiel kiezen': 'Välj en annan profil',
  'Cockpit': 'Cockpit-instrumentpanel',
  'Doeltijd voor de aftelling in de presenter. Tijdens presenteren fijn af te stellen met de toets K.':
      'Måltid för presentatörens nedräkning. Finjustera den under presentationen med tangenten K.',
  'Pagina': 'Sida',
  'Presentatiestijl': 'Presentationsstil',
  'Tekst...': 'Text...',
  'Teksteditor': 'Textredigerare',
  'Volgende pagina': 'Nästa sida',
  'Volgende slide of pagina': 'Nästa bild eller sida',
  'Vorige pagina': 'Föregående sida',
  'Vorige slide of pagina': 'Föregående bild eller sida',
  'Toegankelijkheid': 'Tillgänglighet',
  'Presentatie': 'Presentation',
  'Tabel kopachtergrond': 'Tabellhuvudbakgrund',
  'Doeltijd': 'Måltid',
  'Doeltijd (aftellen)': 'Måltid (nedräkning)',
  'Geen aftelling': 'Ingen nedräkning',
  'uit': 'av',
  'Doeltijd / aftellen (K)': 'Mål / nedräkning (K)',
  'Doeltijd / aftellen instellen (MMSS)': 'Ställ in mål / nedräkning (MMSS)',
  'Tijd & oefenrun resetten': 'Återställ tid och genomgång',
  'Resterend': 'Återstående',
  'Over de tijd': 'Över tiden',
  'Binnen de tijd': 'Inom tiden',
  'Deze slide': 'Denna bild',
  'Oefenrun': 'Genomgång',
  'Totaal': 'Totalt',
  'Totale tijd': 'Total tid',
  'Geen slides gemeten.': 'Inga bilder uppmätta.',
  'Tijden gekopieerd naar klembord.': 'Tider kopierade till urklipp.',
  'Kopieer': 'Kopiera',
  'Sluiten': 'Stäng',
  'Tekstgrootte van de interface': 'Gränssnittets textstorlek',
  'Vergroot alle tekst van de bewerkomgeving tot maximaal 200%. De slides zelf veranderen niet mee.':
      'Förstorar all redigerartext upp till 200 %. Bilderna själva påverkas inte.',
  'Breedte van het slidepaneel': 'Bildpanelens bredd',
  'Pijltjestoetsen passen de breedte aan': 'Piltangenterna justerar bredden',
  'Tip: plak met Cmd/Ctrl+V een tabel uit je spreadsheet in een cel om de hele tabel te vullen.':
      'Tips: klistra in en tabell från ditt kalkylark i en cell med Cmd/Ctrl+V för att fylla hela tabellen.',
  'Annuleren': 'Avbryt',
  'Checklist': 'Uppgiftschecklista',
  'Voortgangsgrafiek tonen': 'Visa förloppsdiagram',
  'Toont afgevinkt en niet afgevinkt als percentages.':
      'Visar markerade och omarkerade poster som procent.',
  'Afgevinkt': 'Markerad',
  'Niet afgevinkt': 'Omarkerad',
  'Er zijn geen aangevinkte checklist-items om te legen.':
      'Det finns inga markerade checklistposter att rensa.',
  'Alle checkboxen legen?': 'Rensa alla kryssrutor?',
  'Hiermee worden alle': 'Detta avmarkerar alla',
  'aangevinkte checklist-items in de hele presentatie uitgevinkt. Dit kun je ongedaan maken met Ctrl/Cmd+Z.':
      'markerade checklistposter i hela presentationen. Du kan ångra detta med Ctrl/Cmd+Z.',
  'Alles legen': 'Rensa alla',
  'checklist-items uitgevinkt.': 'checklistposter avmarkerade.',
  'Alle checkboxen legen': 'Rensa alla kryssrutor',
  'Afgevinkte tekst doorhalen': 'Stryk över markerad text',
  'Toont een streep door voltooide checklistitems.':
      'Visar slutförda checklistposter med en genomstrykning.',
  'Na media automatisch doorgaan': 'Gå vidare automatiskt efter media',
  'Opsomming': 'Punkter',
  'Nummering': 'Numrering',
  'Varianten': 'Varianter',
  'Grafiekvarianten maken': 'Skapa diagramvarianter',
  'Slides toevoegen': 'Lägg till bilder',
  'Omhoog': 'Flytta upp',
  'Omlaag': 'Flytta ned',
  'Niet toevoegen': 'Lägg inte till',
  'Deze slides gebruiken dezelfde data, kleuren en titel. Kies met de pijlen de volgorde na de huidige slide.':
      'Dessa bilder använder samma data, färger och titel. Använd pilarna för att välja deras ordning efter den aktuella bilden.',
  'Afbeelding': 'Bild',
  'Broncode': 'Källkod',
  'Bullet': 'Punkt',
  'Plak of typ hier je broncode...':
      'Klistra in eller skriv din källkod här...',
  'Programmeertaal': 'Programmeringsspråk',
  'TLP van deze slide': 'TLP för denna bild',
  'Wis annotaties (C)': 'Rensa anteckningar (C)',
  'Stoppen (Esc)': 'Stoppa (Esc)',
  'Pen · markeerstift · gum': 'Penna · överstrykningspenna · suddgummi',
  'Laser · annotaties wissen': 'Laser · rensa anteckningar',
  'Grafiek': 'Diagram',
  'Type grafiek': 'Diagramtyp',
  'Staaf': 'Stapel',
  'Lijn': 'Linje',
  'Cirkel': 'Cirkel',
  'Spider': 'Spider',
  'CSV importeren': 'Importera CSV',
  'Gekoppeld aan': 'Länkad till',
  'Ontkoppelen': 'Ta bort länk',
  'Geen grafiekgegevens': 'Inga diagramdata',
  'Label': 'Etikett',
  'Rij': 'Rad',
  'Reeks': 'Serie',
  'Kleur van reeks': 'Seriefärg',
  'Kleur van rij': 'Radfärg',
  'Hexkleur': 'Hex-färg',
  'Sorteren': 'Sortera',
  'Oplopend sorteren': 'Sortera stigande',
  'Aflopend sorteren': 'Sortera fallande',
  'Bij een cirkel worden maximaal de eerste twee reeksen getoond; de labels vormen de segmenten.':
      'Cirkeldiagram visar högst de två första serierna; etiketterna bildar segmenten.',
  'Een spider-diagram heeft minstens drie labels (assen) nodig; elke reeks vormt een vlak.':
      'Ett spider-diagram behöver minst tre etiketter (axlar); varje serie bildar en form.',
  'Een spider-diagram heeft minstens drie labels nodig':
      'Ett spider-diagram behöver minst tre etiketter',
  'Minimumlijn (optioneel)': 'Minimilinje (valfritt)',
  'Maximumlijn (optioneel)': 'Maximilinje (valfritt)',
  'Schaalminimum (optioneel)': 'Skalminimum (valfritt)',
  'Schaalmaximum (optioneel)': 'Skalmaximum (valfritt)',
  'geen': 'ingen',
  'Broncode achtergrond': 'Kodbakgrund',
  'Broncode tekst': 'Kodtext',
  'Syntaxkleuring': 'Syntaxfärgning',
  'Uit = alles in één kleur (bijv. groen op zwart voor een CRT-scherm).':
      'Av = allt i en färg (t.ex. grönt på svart för en CRT-skärm).',
  'Eigen kleur (hex)': 'Egen färg (hex)',
  'Bijvoorbeeld #33FF33 voor een CRT-groen scherm.':
      'Till exempel #33FF33 för en CRT-grön skärm.',
  'Broncode lettertype': 'Kodtypsnitt',
  'Kop (optioneel)': 'Rubrik (valfritt)',
  'Subkop (optioneel)': 'Underrubrik (valfritt)',
  'Subkop': 'Underrubrik',
  'Systeem (monospace)': 'System (monospace)',
  'Platte tekst': 'Vanlig text',
  'HTML opent in elke browser zonder internet en rendert codeblokken, wiskunde en mermaid-diagrammen.':
      'HTML öppnas i vilken webbläsare som helst utan internet och renderar kodblock, matematik och Mermaid-diagram.',
  'Laatste slide': 'Sista bilden',
  'Logo px': 'Logotyp px',
  'Markdown voor laatste slide': 'Markdown för sista bilden',
  'PREVIEW': 'FÖRHANDSVISNING',
  'Slides gerenderd.': 'Bilder renderade.',
  'Standaard laatste slide gebruiken': 'Använd standardsista bild',
  'Wordt automatisch toegevoegd bij presenteren en exporteren.':
      'Läggs till automatiskt vid presentation och export.',
  'gerenderd.': 'renderade.',
  'renderen…': 'renderar…',
  'voorbereiden…': 'förbereder…',
  'Duplicaten opruimen': 'Rensa upp dubbletter',
  'Zoek byte-identieke afbeeldingen (md5), voeg tags en opmerkingen samen en verwijder de kopieën':
      'Hitta byte-identiska bilder (md5), slå samman taggar och anteckningar och ta bort kopiorna',
  'Geen dubbele afbeeldingen gevonden.': 'Inga dubbletter av bilder hittades.',
  'Dubbele afbeeldingen opruimen?': 'Rensa upp dubbletter av bilder?',
  'Van elke groep blijft één bestand staan. Tags en opmerkingen worden samengevoegd en slides die een kopie gebruiken verwijzen daarna naar het behouden bestand — ook in presentaties die nu niet geopend zijn.':
      'En fil per grupp behålls. Taggar och anteckningar slås samman, och bilder som använder en kopia kommer därefter att peka på den behållna filen — inklusive presentationer som inte är öppna just nu.',
  'Opruimen': 'Rensa upp',
  '1 presentatiebestand bijgewerkt.': '1 presentationsfil uppdaterad.',
  'presentatiebestanden bijgewerkt.': 'presentationsfiler uppdaterade.',
  'niet geopend': 'inte öppen',
  '1 dubbele afbeelding verwijderd.': '1 dubblettbild borttagen.',
  'dubbele afbeeldingen verwijderd.': 'dubblettbilder borttagna.',
  'Alleen afbeeldingen zonder tags tonen': 'Visa endast bilder utan taggar',
  'Alle afbeeldingen hebben tags.': 'Alla bilder har taggar.',
  'Zet het filter uit om alles weer te zien.':
      'Stäng av filtret för att se allt igen.',
  'Welkom bij OciDeck': 'Välkommen till OciDeck',
  'Licentie (EUPL 1.2)': 'Licens (EUPL 1.2)',
  'Volledige licentie online': 'Fullständig licens online',
  'Akkoord gaan': 'Godkänn',
  'Privacy': 'Integritet',
  'Toestemming': 'Samtycke',
  'Toestemming intrekken': 'Återkalla samtycke',
  'Toestemming intrekken?': 'Återkalla samtycke?',
  'Intrekken': 'Återkalla',
  'U hebt al toegestemd in het gebruik van OciDeck.':
      'Du har redan samtyckt till användningen av OciDeck.',
  'U kunt uw toestemming op elk moment intrekken. Na intrekking moet u deze voorwaarden opnieuw accepteren.':
      'Du kan återkalla ditt samtycke när som helst. Efter återkallelse måste du acceptera dessa villkor igen.',
  'Als u uw toestemming intrekt, moet u deze voorwaarden opnieuw accepteren wanneer u OciDeck opnieuw start.':
      'Om du återkallar ditt samtycke måste du acceptera dessa villkor igen när du startar om OciDeck.',
  'Slidekwaliteit': 'Bildkvalitet',
  'Geen kwaliteitsproblemen gevonden': 'Inga kvalitetsproblem hittades',
  'Thema (hele presentatie)': 'Tema (hela presentationen)',
  'Kwaliteitsprobleem': 'Kvalitetsproblem',
  'Kwaliteitsproblemen': 'Kvalitetsproblem',
  'Kwaliteitsproblemen (inclusief ernstige)':
      'Kvalitetsproblem (inklusive allvarliga)',
  'Voeg alt-tekst / bijschrift toe voor toegankelijkheid':
      'Lägg till alt-text / bildtext för tillgänglighet',
  'Alt-tekst': 'Alt-text',
  'Tekstdichtheid': 'Textdensitet',
  'Contrast': 'Kontrast',
  'heeft geen bijschrift/alt-tekst.': 'har ingen bildtext/alt-text.',
  'contrastverhouding': 'kontrastförhållande',
  '(minimaal ': '(minst ',
  ':1 voor normale tekst).': ':1 för normal text).',
  ':1 voor grote tekst).': ':1 för stor text).',
  ':1).': ':1).',
  'Contrast van tekst op of over een afbeelding kan niet automatisch worden gecontroleerd — controleer visueel.':
      'Kontrast för text på eller över en bild kan inte kontrolleras automatiskt — verifiera visuellt.',
  'Grafiek heeft geen titel of beschrijvende data — voeg een titel of seriesnamen toe.':
      'Diagrammet har ingen titel eller beskrivande data — lägg till en titel eller serienamn.',
  'heeft geen titel of sprekernotities die de inhoud beschrijven.':
      'har ingen titel eller talaranteckningar som beskriver innehållet.',
  'Veel tekst op deze slide: het lettertype wordt verkleind tot ':
      'Mycket text på denna bild: teckenstorleken minskas till ',
  ' van de ontwerpgrootte.': ' av designstorleken.',
  'Veel tekst op deze slide: het lettertype wordt sterk verkleind (':
      'Mycket text på denna bild: teckenstorleken minskas kraftigt (',
  ' van de ontwerpgrootte). Overweeg de inhoud te splitsen.':
      ' av designstorleken). Överväg att dela upp innehållet.',
  'Grote tabel (': 'Stor tabell (',
  ' rijen, ': ' rader, ',
  ' kolommen): celtekst staat op het minimumformaat.':
      ' kolumner): celltexten är på minsta storlek.',
  'Veel broncode (': 'Mycket källkod (',
  ' regels) — de tekst wordt sterk verkleind om te passen.':
      ' rader) — texten minskas kraftigt för att passa.',
  'Veel vrije markdown (': 'Mycket fri markdown (',
  ' regels) — controleer of alles leesbaar blijft op de slide.':
      ' rader) — kontrollera att allt förblir läsbart på bilden.',
  'Lange titelpagina (': 'Lång titelbild (',
  ' tekens) — de tekst wordt verkleind om te passen.':
      ' tecken) — texten minskas för att passa.',
  'Thema bodytekst': 'Temats brödtext',
  'Thema titel': 'Temats titel',
  'Thema tabeltekst': 'Temats tabelltext',
  'Thema tabelkop': 'Temats tabellhuvud',
  'Thema code': 'Temats kod',
  'Thema accent': 'Temats accent',
  'Eerste afbeelding': 'Första bilden',
  'Tweede afbeelding': 'Andra bilden',
  'Waarschuwing bij export': 'Varna vid export',
  'Minimale contrastverhouding': 'Minsta kontrastförhållande',
  'Tekst onder deze verhouding wordt gemarkeerd. 4.5 = WCAG AA, 3.0 = WCAG AA grote tekst. Hoger is strenger.':
      'Text under detta förhållande flaggas. 4.5 = WCAG AA, 3.0 = WCAG AA stor text. Högre är strängare.',
  'Vraag bevestiging voordat je exporteert wanneer er slide-kwaliteitsproblemen zijn.':
      'Be om bekräftelse före export när det finns bildkvalitetsproblem.',
  'Kwaliteitsproblemen gevonden': 'Kvalitetsproblem hittades',
  'Toch exporteren': 'Exportera ändå',
  'ernstige probleem(en)': 'allvarligt/allvarliga problem',
  'De presentatie heeft kwaliteitsproblemen (':
      'Presentationen har kvalitetsproblem (',
  'Lange quote (': 'Långt citat (',
  'Footer-tekst': 'Sidfotstext',
  'Checklist (niet aangevinkt)': 'Checklista (omarkerad)',
  'Checklist (aangevinkt)': 'Checklista (markerad)',
  ': bestand niet gevonden (': ': filen hittades inte (',
  'Blokkeer export bij ernstige kwaliteitsproblemen':
      'Blockera export vid allvarliga kvalitetsproblem',
  'Export is niet mogelijk zolang er fouten in de slide-kwaliteitscontrole staan.':
      'Export är inte möjlig så länge bildkvalitetskontrollerna rapporterar fel.',
  'Export geblokkeerd vanwege ernstige kwaliteitsproblemen.':
      'Export blockerad på grund av allvarliga kvalitetsproblem.',
  'Alle meldingen': 'Alla meddelanden',
  'Classificatie-handhaving': 'Klassificeringshantering',
  'Vrijgaveplafond': 'Frisläppningstak',
  'Hoogste TLP-niveau dat geëxporteerd mag worden. Leeg = geen plafond.':
      'Högsta TLP-nivå som får exporteras. Tomt = inget tak.',
  'Vereist minimumniveau': 'Nödvändig lägsta nivå',
  'Laagste classificatie die een deck moet hebben om te exporteren. Leeg = geen minimum.':
      'Lägsta klassificering en presentation måste ha för att exporteras. Tomt = inget minimum.',
  'Geen plafond': 'Inget tak',
  'Geen minimum': 'Inget minimum',
  'Classificatie verplicht': 'Klassificering krävs',
  'Weiger export wanneer het deck geen TLP-niveau heeft.':
      'Neka export när presentationen inte har någon TLP-nivå.',
  'Classificatie-watermerk': 'Klassificeringsvattenstämpel',
  'Toon een diagonaal watermerk met TLP en organisatie op elke slide.':
      'Visa en diagonal vattenstämpel med TLP och organisation på varje bild.',
  'Stel een TLP-niveau in — export is geblokkeerd door het classificatiebeleid.':
      'Ange en TLP-nivå — export blockeras av klassificeringspolicyn.',
  'Tabel bewerken': 'Redigera tabell',
  'Tabel bewerken (op tabeldia)': 'Redigera tabell (på tabellbilder)',
  'Tabel bewerken (E)': 'Redigera tabell (E)',
  'Tab wisselt cel · Esc sluit': 'Tab växlar cell · Esc stänger',
  'Gestapelde staaf': 'Staplad stapel',
  'Spreiding': 'Spridning',
  'PgUp/PgDn bladert door de slides': 'PgUp/PgDn bläddrar bland bilderna',
  'Wacht op antwoord…': 'Väntar på svar…',
  'Afbeelding slidevullend': 'Bilden fyller bilden helt',
  'Vult de hele slide en snijdt de randen bij':
      'Fyller hela bilden och beskär kanterna',
  'Afbeelding paneelvullend': 'Bild fyller panelen',
  'Vult het paneel en snijdt de randen bij':
      'Fyller panelen och beskär kanterna',
  'Afbeeldingen paneelvullend': 'Bilder fyller sina paneler',
  'Vult elk paneel en snijdt de randen bij':
      'Fyller varje panel och beskär kanterna',
  'Vullen (bijsnijden)': 'Fylla (beskära)',
  'Afbeelding vult hele slide': 'Bilden fyller hela bilden',
  'Aan: vult de hele slide, titel eroverheen (bijgesneden). Uit: beeld bovenaan, titel in een band eronder.':
      'På: fyller hela bilden, titel ovanpå (beskuren). Av: bild överst, titel i ett band under.',
  'Grijze waas over afbeelding': 'Grå slöja över bilden',
  'Maakt de achtergrond rustiger achter titel en subtitel.':
      'Gör bakgrunden lugnare bakom titel och undertitel.',
  'Licht': 'Ljus',
  'Donker': 'Mörk',
  'Pen (D)': 'Penna (D)',
  'Markeerstift (T)': 'Överstrykningspenna (T)',
  'Gum (E / Shift+E)': 'Suddgummi (E / Shift+E)',
  'Laser (X)': 'Laser (X)',
  'Metriek': 'Mätvärde',
  'Inhoud': 'Innehåll',
  'Vraag is niet speelbaar: geef minstens één goed én één fout antwoord op.':
      'Frågan kan inte spelas: ange minst ett rätt och ett fel svar.',
  'CSV-koppeling verbreken?': 'Koppla bort CSV-filen?',
  'De data blijft in de slide staan, maar wijzigingen in het CSV-bestand komen niet meer mee.':
      'Datan stannar i bilden, men ändringar i CSV-filen följer inte längre med.',
  'Afbeelding geweigerd: te groot (max 64 MB) of geen ondersteund formaat.':
      'Bilden avvisades: för stor (max 64 MB) eller inte ett format som stöds.',
  'Geen afbeelding op het klembord.': 'Ingen bild i urklipp.',
  'Kon de afbeelding niet opslaan.': 'Kunde inte spara bilden.',
  'Kon de afbeelding niet verwijderen. Controleer of het bestand niet in gebruik is en of je schrijfrechten hebt.':
      'Kunde inte ta bort bilden. Kontrollera att filen inte används och att du har skrivrättigheter.',
  'Geen schrijfrechten op deze locatie. Kies een andere map.':
      'Inga skrivrättigheter på den här platsen. Välj en annan mapp.',
  'De schijf is vol.': 'Disken är full.',
  'Bestand of map niet gevonden.': 'Filen eller mappen hittades inte.',
  'Kon het bestand niet lezen of schrijven.':
      'Kunde inte läsa eller skriva filen.',
  'Netwerkfout — controleer je verbinding en probeer het opnieuw.':
      'Nätverksfel — kontrollera din anslutning och försök igen.',
  'Er ging onverwacht iets mis. Kijk in het logboek voor details.':
      'Något gick oväntat fel. Se loggen för detaljer.',
  'Server niet bereikbaar — controleer je verbinding en de server-URL.':
      'Servern kan inte nås — kontrollera din anslutning och serverns URL.',
  'Aanmelden mislukt. Controleer gebruikersnaam en wachtwoord; gebruik bij Nextcloud een app-wachtwoord, niet je accountwachtwoord.':
      'Inloggningen misslyckades. Kontrollera användarnamn och lösenord; använd med Nextcloud ett applösenord, inte ditt kontolösenord.',
  'Bestand of map niet gevonden op de server.':
      'Filen eller mappen hittades inte på servern.',
  'Het bestand is groter dan de toegestane limiet.':
      'Filen är större än den tillåtna gränsen.',
  'De server gaf een fout. Probeer het later opnieuw.':
      'Servern returnerade ett fel. Försök igen senare.',
  'Het bestand is beschadigd of onleesbaar.': 'Filen är skadad eller oläslig.',
  'Import geweigerd: het pakket overschrijdt de veiligheidslimieten.':
      'Importen nekades: paketet överskrider säkerhetsgränserna.',
  'Kon van deze URL geen presentatie ophalen. Controleer de URL en je verbinding.':
      'Kunde inte hämta en presentation från denna URL. Kontrollera URL:en och din anslutning.',
  'Aanmelden mislukt — controleer gebruikersnaam en wachtwoord. Tip: gebruik bij Nextcloud een app-wachtwoord (Instellingen → Beveiliging), niet je accountwachtwoord.':
      'Inloggningen misslyckades — kontrollera användarnamn och lösenord. Tips: använd med Nextcloud ett applösenord (Inställningar → Säkerhet), inte ditt kontolösenord.',
  'Annuleren…': 'Avbryter…',
  'Afbeeldingen vergelijken…': 'Jämför bilder…',
  'Presentaties scannen…': 'Skannar presentationer…',
  'Opruimen…': 'Städar upp…',
  'Kon een of meer mappen van de bibliotheek niet lezen; de lijst kan onvolledig zijn.':
      'Kunde inte läsa en eller flera biblioteksmappar; listan kan vara ofullständig.',
  'Uit recente bestanden verwijderen': 'Ta bort från senaste filer',
  'OciDeck wordt gestart…': 'Startar OciDeck…',
  'Herstelbestanden': 'Återställningsfiler',
  'Herstelbestanden nu wissen': 'Radera återställningsfiler nu',
  'Er waren geen herstelbestanden.': 'Det fanns inga återställningsfiler.',
  'herstelbestand(en) gewist.': 'återställningsfil(er) raderade.',
  'Klaar voor export': 'Klar för export',
  'kwaliteitswaarschuwing(en)': 'kvalitetsvarning(ar)',
  'Nog opslaan nodig': 'Behöver sparas först',
  'TLP blokkeert export': 'TLP blockerar exporten',
  'Kwaliteit blokkeert export': 'Kvaliteten blockerar exporten',
  'Verhoog contrast': 'Öka kontrasten',
  'Open kleurinstellingen': 'Öppna färginställningar',
  'Voeg alt-tekst toe': 'Lägg till alt-text',
  'Voeg beschrijving toe': 'Lägg till beskrivning',
  'Zinnen naar losse bullets': 'Meningar till separata punkter',
  'Laatst geëxporteerd als': 'Senast exporterad som',
  'Bepaalt kleuren, lettertype en logo. Later aan te passen via de presentatie-eigenschappen of instellingen.':
      'Bestämmer färger, typsnitt och logotyp. Kan ändras senare via presentationsegenskaperna eller inställningarna.',
  'Stijlprofielen beheren…': 'Hantera stilprofiler…',
  'Geavanceerd': 'Avancerat',
  'Knippen en audio': 'Klippning och ljud',
  'Bereik en kleurzones': 'Intervall och färgzoner',
  'Leeg deck': 'Tom presentation',
  'Korte briefing': 'Kort briefing',
  'Status-briefing': 'Statusbriefing',
  'Projectstart / kick-off': 'Projektstart / kick-off',
  'Voorbespreking communicatie': 'Förmöte om kommunikation',
  'Projecttijdlijn': 'Projekttidslinje',
  'Informatieveiligheid: RASCI / TVB': 'Informationssäkerhet: RASCI / TVB',
  'Takenplan informatieveiligheid': 'Plan för säkerhetsuppgifter',
  'Certificering voortgang': 'Certifieringsframsteg',
  'Training / workshop': 'Utbildning / workshop',
  'Rapportage': 'Rapportering',
  'Onderzoeksverhaal': 'Undersökningsberättelse',
  'Technische uitleg': 'Teknisk förklaring',
  'Interactieve quiz': 'Interaktivt quiz',
  'Situatie, feiten en gevraagd besluit in zes slides.':
      'Situation, fakta och begärt beslut på sex bilder.',
  'Statusdashboard, voortgang per werkstroom en besluiten.':
      'Statusdashboard, framsteg per arbetsström och beslut.',
  'Waarom, doel, scope, stakeholders en tijdlijn.':
      'Varför, mål, omfattning, intressenter och tidslinje.',
  'Doelgroepen, kernboodschap, kanalen en woordvoering.':
      'Målgrupper, kärnbudskap, kanaler och talespersonsroll.',
  'Fases, mijlpalen, afhankelijkheden en beslismomenten.':
      'Faser, milstolpar, beroenden och beslutspunkter.',
  'Rollen, RASCI-matrix en taakafspraken vastleggen.':
      'Fastställ roller, RASCI-matris och uppgiftsöverenskommelser.',
  'Taken, prioriteiten, eigenaren en bewijsstukken.':
      'Uppgifter, prioriteringar, ägare och underlag.',
  'Voortgang per domein, controls en auditplanning.':
      'Framsteg per domän, kontroller och revisionsplanering.',
  'Leerdoelen, kernconcepten, oefening en quizvraag.':
      'Lärandemål, kärnbegrepp, övning och quizfråga.',
  'Samenvatting, KPI-dashboard, trend en acties.':
      'Sammanfattning, KPI-dashboard, trend och åtgärder.',
  'Vraag, methode, tijdlijn van bevindingen en conclusies.':
      'Fråga, metod, tidslinje över fynd och slutsatser.',
  'Architectuur, componenten, codevoorbeeld en checklist.':
      'Arkitektur, komponenter, kodexempel och checklista.',
  'Drie vraagvormen met uitleg en nabespreking.':
      'Tre frågetyper med förklaring och uppföljning.',
  'Sjabloon': 'Mall',
  'Post-incident review / lessons learned':
      'Post-incident review / lessons learned',
  'Datalek / privacy-incident beoordeling':
      'Dataläcka / bedömning av integritetsincident',
  'DPIA / privacy impact assessment':
      'DPIA / konsekvensbedömning för dataskydd',
  'Risicoanalyse / risk register': 'Riskanalys / riskregister',
  'Business continuity / DR-test': 'Business continuity / DR-test',
  'Tabletop-oefening / crisisoefening': 'Tabletop-övning / krisövning',
  'BOB-crisisrapportage': 'BOB-krisrapportering',
  'CAB / release readiness': 'CAB / release readiness',
  'Stuurgroep / project board update': 'Styrgrupp / project board-uppdatering',
  'Auditbevindingen en opvolging': 'Revisionsfynd och uppföljning',
  'Leveranciersbeoordeling / vendor risk': 'Leverantörsbedömning / vendor risk',
  'Architectuurbesluit / ADR-presentatie':
      'Arkitekturbeslut / ADR-presentation',
  'Beleid uitrollen / implementatieplan':
      'Utrullning av policy / genomförandeplan',
  'Overdracht / handover': 'Överlämning / handover',
  'Retrospective / teamverbetering': 'Retrospektiv / teamförbättring',
  'PPL Vluchtvoorbereiding': 'PPL-flygförberedelse',
  'Tijdlijn, impact, oorzaken en verbeteracties na een incident.':
      'Tidslinje, påverkan, orsaker och förbättringsåtgärder efter en incident.',
  'Beoordeel gegevens, risico, meldplicht en communicatie.':
      'Bedöm uppgifter, risk, anmälningsplikt och kommunikation.',
  'Verwerking, grondslag, privacyrisico\'s en maatregelen.':
      'Behandling, rättslig grund, integritetsrisker och åtgärder.',
  'Leg risico\'s, kans, impact, maatregelen en eigenaren vast.':
      'Dokumentera risker, sannolikhet, påverkan, åtgärder och ägare.',
  'Scenario, hersteldoelen, testbevindingen en verbeterpunten.':
      'Scenario, återställningsmål, testfynd och förbättringspunkter.',
  'Scenario, injects, besluiten, waarnemingen en evaluatie.':
      'Scenario, injects, beslut, observationer och utvärdering.',
  'Leid een crisisteam door beeldvorming, oordeelsvorming en besluitvorming, met live situatiebeeld, informatievragen, dilemma\'s, besluitenlog en actielijst.':
      'Led ett kristeam genom lägesbild, bedömning och beslutsfattande, med lägesbild i realtid, informationsfrågor, dilemman, beslutslogg och åtgärdslista.',
  'Wijziging, impact, tests, rollback, communicatie en go/no-go.':
      'Ändring, påverkan, tester, rollback, kommunikation och go/no-go.',
  'Voortgang, planning, budget, risico\'s en besluiten gevraagd.':
      'Framsteg, planering, budget, risker och begärda beslut.',
  'Bevindingen, root cause, maatregelen, bewijs en status.':
      'Fynd, root cause, åtgärder, underlag och status.',
  'Dienst, data, afhankelijkheid, eisen, risico\'s en besluit.':
      'Tjänst, data, beroende, krav, risker och beslut.',
  'Context, opties, trade-offs, besluit en gevolgen.':
      'Kontext, alternativ, trade-offs, beslut och konsekvenser.',
  'Doelgroep, planning, communicatie, training en adoptie.':
      'Målgrupp, planering, kommunikation, utbildning och införande.',
  'Status, open acties, risico\'s, contacten en eerste stappen.':
      'Status, öppna åtgärder, risker, kontakter och första steg.',
  'Feiten, patronen, start-stop-continue en verbeteracties.':
      'Fakta, mönster, start-stop-continue och förbättringsåtgärder.',
  'Bereid een VFR-vlucht voor met route, weer, NOTAMs, prestaties, weight & balance, brandstof, alternates en persoonlijke go/no-go checks.':
      'Förbered en VFR-flygning med rutt, väder, NOTAM, prestanda, weight & balance, bränsle, alternates och personliga go/no-go-kontroller.',
  'Zoek een sjabloon': 'Sök efter en mall',
  'Geen sjablonen gevonden': 'Inga mallar hittades',
  // Duplicaatdetectie & opruimen (open-lijsten).
  'Identieke kopieën': 'Identiska kopior',
  'Zelfde titel, andere inhoud': 'Samma titel, olika innehåll',
  'Dubbele presentaties opruimen': 'Rensa dubblerade presentationer',
  'Naar de prullenbak verplaatst:': 'Flyttad till papperskorgen:',
  'Kon niet naar de prullenbak verplaatsen.':
      'Kunde inte flyttas till papperskorgen.',
  'Geen dubbele presentaties gevonden.':
      'Inga dubblerade presentationer hittades.',
  'Laatste kopie blijft behouden': 'Den sista kopian behålls',
  'Nog geopend in een tabblad': 'Fortfarande öppen i en flik',
  'Naar prullenbak': 'Till papperskorgen',
  'Deze presentatie staat ook op een andere plek:':
      'Den här presentationen finns även på en annan plats:',
  '"Oci" verwijst naar de ocicat, het kattenras van de katten van Brenno de Winter. "Deck" is het Engelse woord voor een diaset. OciDeck maakt van eenvoudige tekst een verzorgde presentatie.':
      '"Oci" syftar på ocicaten, kattrasen för Brenno de Winters katter. "Deck" är det engelska ordet för en bildserie. OciDeck gör en välgjord presentation av enkel text.',
  'Adressen': 'Adresser',
  'Bestuur': 'Styrelse',
  'Beveiliging': 'Säkerhet',
  'Brenno de Winter (voorzitter), Jan Klopper (secretaris) en Astrid Oosenbrug (penningmeester).':
      'Brenno de Winter (ordförande), Jan Klopper (sekreterare) och Astrid Oosenbrug (kassör).',
  'Contact': 'Kontakt',
  'De katten van Brenno': 'Brennos katter',
  'De mascottes van OciDeck en verwante projecten zijn de ocicats van Brenno de Winter.':
      'Maskotarna för OciDeck och närliggande projekt är Brenno de Winters ocicats.',
  'De stichting is op 23 oktober 2025 bij notariële akte opgericht te Leeuwarden en heeft haar statutaire zetel in Noordwijk.':
      'Stiftelsen bildades den 23 oktober 2025 genom notariehandling i Leeuwarden och har sitt stadgeenliga säte i Noordwijk.',
  'Deze instellingen bepalen wat OciDeck vanaf het internet mag laden en welke sporen op dit apparaat achterblijven. Ze staan los van je privacyverklaring en toestemming, die je bij "Licentie en Privacy" vindt.':
      'De här inställningarna avgör vad OciDeck får läsa in från internet och vilka spår som lämnas kvar på den här enheten. De är oberoende av din integritetspolicy och ditt samtycke, som du hittar under "Licens och Integritet".',
  'Doelstellingen van de stichting:\n\n•  Opensource-software en -hardware voor veilige digitale infrastructuren stimuleren.\n•  Transparantie en reproduceerbaarheid in beveiligingsprocessen bevorderen.\n•  Onderzoek, trainingen en activiteiten rond digitale weerbaarheid organiseren.\n•  Burgers, bedrijven, overheid en maatschappelijke organisaties met elkaar verbinden.':
      'Stiftelsens mål:\n\n•  Främja programvara och hårdvara med öppen källkod för säker digital infrastruktur.\n•  Främja transparens och reproducerbarhet i säkerhetsprocesser.\n•  Organisera forskning, utbildning och aktiviteter kring digital motståndskraft.\n•  Förbinda medborgare, företag, det offentliga och civilsamhällesorganisationer med varandra.',
  'E-mail': 'E-post',
  'Kernwaarden: veiligheid, vrijheid en openheid, soevereiniteit, integriteit, kennisdeling, betrouwbaarheid, menselijkheid, luisteren en verbinden, "just culture" en duurzaamheid.':
      'Kärnvärden: säkerhet, frihet och öppenhet, suveränitet, integritet, kunskapsdelning, tillförlitlighet, mänsklighet, att lyssna och förbinda, "just culture" och hållbarhet.',
  'Licentie en Privacy': 'Licens och Integritet',
  'Mascotte van MIAUW.': 'Maskot för MIAUW.',
  'Mascotte van OpenKAT.': 'Maskot för OpenKAT.',
  'Mascotte van de checklisttool.': 'Maskot för checklistverktyget.',
  'OciDeck wordt uitgegeven door Stichting LibreKAT. De stichting werkt aan een veiligere digitale samenleving via open, controleerbare informatiebeveiliging, met de nadruk op kennisdeling, community-vorming en het ondersteunen van opensource-oplossingen.':
      'OciDeck ges ut av Stichting LibreKAT. Stiftelsen arbetar för ett säkrare digitalt samhälle genom öppen, kontrollerbar informationssäkerhet, med tonvikt på kunskapsdelning, gemenskapsbyggande och stöd till lösningar med öppen källkod.',
  'Over OciDeck': 'Om OciDeck',
  'Telefoon': 'Telefon',
  'Uitgever: Stichting LibreKAT': 'Utgivare: Stichting LibreKAT',
  'Verzorgde presentaties uit eenvoudige tekst — vrij, controleerbaar en met je gegevens op je eigen apparaat.':
      'Välgjorda presentationer av enkel text — fritt, kontrollerbart och med dina data på din egen enhet.',
  'Waar komt de naam vandaan?': 'Var kommer namnet ifrån?',
  'Website van de stichting': 'Stiftelsens webbplats',
  'Opgeslagen als download in je map met downloads.':
      'Sparad som en nedladdning i din nedladdningsmapp.',
  'Beveiligingsbriefing / dienststart': 'Säkerhetsgenomgång / passstart',
  'Actualiteiten, aandachtsvestigingen, bijzonderheden, onderhoud en bezetting voor de beveiligingsdienst.':
      'Aktuellt, uppmärksamhetspunkter, särskilda förhållanden, underhåll och bemanning för bevakningstjänsten.',
  'Operationele politiebriefing': 'Operativ polisgenomgång',
  'Actualiteiten, hotspots, signaleringen, opdrachten, eigen veiligheid en gebiedsinzet voor de dienst.':
      'Aktuellt, hotspots, efterlysningar, uppdrag, egen säkerhet och områdesinsats för passet.',
  'Handhavingsbriefing (BOA)': 'Tillsynsgenomgång (BOA)',
  'Aandachtslocaties, overlast, evenementen, bevoegdheden, eigen veiligheid en gebiedsinzet voor de handhavingsdienst.':
      'Uppmärksamhetsplatser, störningar, evenemang, befogenheter, egen säkerhet och områdesinsats för tillsynstjänsten.',
  'Sollicitatiegesprek': 'Anställningsintervju',
  'Functioneringsgesprek': 'Medarbetarsamtal',
  'Salarisonderhandeling': 'Löneförhandling',
  'Meer verantwoordelijkheid vragen': 'Be om mer ansvar',
  'Probleem op de werkvloer aankaarten': 'Ta upp ett problem på arbetsplatsen',
  'Conflict uitpraten': 'Prata igenom en konflikt',
  'Kritiek geven of ontvangen': 'Ge eller ta emot kritik',
  'Slecht nieuws brengen': 'Framföra dåliga nyheter',
  'Grenzen stellen': 'Sätta gränser',
  'Stroef lopende relatie bespreken': 'Diskutera en ansträngd relation',
  'Klantgesprek': 'Kundsamtal',
  'Verkoopgesprek': 'Säljsamtal',
  'Onderhandeling met leveranciers': 'Förhandling med leverantörer',
  'Pitch geven': 'Hålla en pitch',
  'Iets voor elkaar krijgen in een vergadering': 'Få igenom något på ett möte',
  'Bereid je voor met STAR-antwoorden, eigen vragen en arbeidsvoorwaarden.':
      'Förbered dig med STAR-svar, egna frågor och anställningsvillkor.',
  'Resultaten, ontwikkelwensen en afspraken volgens de aanpak voor cruciale gesprekken.':
      'Resultat, utvecklingsönskemål och överenskommelser enligt metoden för avgörande samtal.',
  'Onderbouwing, bandbreedte en tegenargumenten volgens de aanpak voor cruciale gesprekken.':
      'Underbyggnad, spännvidd och motargument enligt metoden för avgörande samtal.',
  'Vraag je leidinggevende om een grotere rol volgens de aanpak voor cruciale gesprekken.':
      'Be din chef om en större roll enligt metoden för avgörande samtal.',
  'Maak een probleem bespreekbaar zonder te beschuldigen, volgens de aanpak voor cruciale gesprekken.':
      'Gör ett problem samtalbart utan att anklaga, enligt metoden för avgörande samtal.',
  'Kom er samen uit met feiten, veiligheid en luisteren, volgens de aanpak voor cruciale gesprekken.':
      'Nå en lösning tillsammans med fakta, trygghet och lyssnande, enligt metoden för avgörande samtal.',
  'Geef en ontvang feedback met feit, effect en verzoek, volgens de aanpak voor cruciale gesprekken.':
      'Ge och ta emot feedback med fakta, effekt och begäran, enligt metoden för avgörande samtal.',
  'Breng slecht nieuws duidelijk en met respect, volgens de aanpak voor cruciale gesprekken.':
      'Framför dåliga nyheter tydligt och med respekt, enligt metoden för avgörande samtal.',
  'Zet je grens rustig en duidelijk neer, volgens de aanpak voor cruciale gesprekken.':
      'Sätt din gräns lugnt och tydligt, enligt metoden för avgörande samtal.',
  'Bespreek een relatie of vriendschap die stroef loopt, volgens de aanpak voor cruciale gesprekken.':
      'Diskutera en relation eller vänskap som blivit ansträngd, enligt metoden för avgörande samtal.',
  'Behoefteanalyse, waardevertaling en bezwaren voor een goed klantgesprek.':
      'Behovsanalys, värdeöversättning och invändningar för ett bra kundsamtal.',
  'SPIN-vragen, waardevertaling, bezwaren en afsluiten voor een verkoopgesprek.':
      'SPIN-frågor, värdeöversättning, invändningar och avslut för ett säljsamtal.',
  'Eisen, onderhandelruimte en tactieken met BATNA en ZOPA voor een leveranciersonderhandeling.':
      'Krav, förhandlingsutrymme och taktiker med BATNA och ZOPA för en leverantörsförhandling.',
  'Haak, probleem, oplossing, bewijs en vraag voor een overtuigende pitch.':
      'Krok, problem, lösning, bevis och begäran för en övertygande pitch.',
  'Stakeholders, argumentatie en bezwaren om een besluit of steun te krijgen in een vergadering.':
      'Intressenter, argumentation och invändningar för att få ett beslut eller stöd på ett möte.',
  // Document integrity (A1) — finalise, seal (SHA-512) and signature.
  'Afronden & verzegelen': 'Slutför och försegla',
  'Verzegelen': 'Försegla',
  'Handtekening (optioneel)': 'Signatur (valfritt)',
  'Naam': 'Namn',
  'Rol of functie': 'Roll eller funktion',
  'Verklaring': 'Förklaring',
  'Getypte handtekening': 'Inskriven signatur',
  'Deze presentatie is afgerond en verzegeld en kan niet worden bewerkt.':
      'Den här presentationen är slutförd och förseglad och kan inte redigeras.',
  'Integriteit intact': 'Integritet intakt',
  'Gewijzigd na afronden': 'Ändrad efter slutförande',
  'Verzegeld met SHA-512. De inhoud komt overeen met het zegel.':
      'Förseglad med SHA-512. Innehållet matchar sigillet.',
  'De inhoud wijkt af van het zegel — het bestand is na het afronden gewijzigd.':
      'Innehållet avviker från sigillet — filen ändrades efter slutförandet.',
  'Presentatie afgerond en verzegeld.':
      'Presentationen är slutförd och förseglad.',
};

const _dutchSourceAddSv = <String, String>{
  'Crashherstel werkt nu niet — de herstelmap is niet beschrijfbaar. Sla je werk handmatig op.':
      'Kraschåterställning fungerar inte just nu — återställningsmappen är inte skrivbar. Spara ditt arbete manuellt.',
  'Donker logo kiezen': 'Välj mörkt logo',
  'Geen donker logo ingesteld': 'Inget mörkt logo valt',
  'Verwijder donker logo': 'Ta bort mörkt logo',
  'De dia-achtergrond is donker, maar het logo heeft geen donkere variant. Het logo is op de dia vrijwel onzichtbaar. Stel een donker logo in de presentatie-instellingen.':
      'Diabakgrunden är mörk, men logotypen har ingen mörk variant. Logotypen är nästan osynlig på diabilden. Ställ in ett mörkt logo i presentationsinställningarna.',
  'Klik met Ctrl/Cmd of Shift om meerdere bestanden te kiezen.':
      'Klicka med Ctrl/Cmd eller Shift för att välja flera filer.',
  'Presentaties openen': 'Öppna presentationer',
  'Aangeboden als download:': 'Erbjuden som nedladdning:',
  'De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.':
      'Webbläsaren tog inte emot nedladdningen. Tillåt nedladdningar för den här webbplatsen och försök igen.',
  'De sessiebestanden zijn niet opgeslagen. De wijzigingen staan nog in het deck.':
      'Sessionsfilerna sparades inte. Ändringarna finns kvar i presentationen.',
  'Klik op de afbeelding waar deze regel naar verwijst.':
      'Klicka på bilden där denna punkt hänvisar till.',
  'Sleep op de afbeelding om een gebied te markeren.':
      'Dra på bilden för att markera ett område.',
  'Geldt voor de hele dia — bepaalt hoe verwijzingen tijdens de presentatie worden getekend, niet hoe je ze bewerkt.':
      'Gäller hela bilden — avgör hur referenser ritas under presentationen, inte hur du redigerar dem.',
  'Draaien schrijft een gedraaide kopie naast het origineel; je oorspronkelijke bestand blijft ongewijzigd.':
      'Rotering skriver en vriden kopia bredvid originalet; din ursprungliga fil lämnas oförändrad.',
  'Doel toevoegen': 'Lägg till mål',
  'Doel verwijderen': 'Ta bort mål',
  'Verwijzing verwijderen': 'Ta bort referens',
  'Vorm van de markering': 'Markörens form',
  'doel': 'mål',
  'doelen': 'mål',
  'Verwijzing verwijderd': 'Referens borttagen',
  'Afbeeldingsverwijzing': 'Bildreferens',
  'heeft ongeldige coördinaten en wordt niet getekend — pas de doelpositie aan in de verwijzingeneditor.':
      'har ogiltiga koordinater och ritas inte — justera målpositionen i referenseditorn.',
  'verwijst naar een (A)-markering die niet in de tekst staat, of omgekeerd — zet de letter in de tekst of verwijder de verwijzing.':
      'hänvisar till ett (A)-märke som inte finns i texten, eller tvärtom — lägg till bokstaven i texten eller ta bort referensen.',
  'komt twee keer voor op deze dia — elke markering (A), (B) … mag maar één verwijzing hebben.':
      'förekommer två gånger på denna bild — varje märke (A), (B) … får bara ha en referens.',
  'Deze dia heeft afbeeldingsverwijzingen maar geen anker — de verwijzingen kunnen niet aan de dia worden gekoppeld. Geef de dia een anker in de editor.':
      'Denna bild har bildreferenser men ingen ankare — referenserna kan inte kopplas till bilden. Ge bilden en ankare i editorn.',
  'Pijlen kruisen elkaar op deze dia — overweeg pinmarkeringen in plaats van pijlen voor leesbaarheid.':
      'Pilar korsar varandra på denna bild — överväg pin-markörer istället för pilar för läsbarhet.',
  'valt buiten het zichtbare deel van de afbeelding — pas het focuspunt, zoom of doelpositie aan, of de markering verschijnt niet op de dia.':
      'faller utanför den synliga delen av bilden — justera brännpunkt, zoom eller målposition, annars visas inte markören på sliden.',
  'Beschrijving (voor schermlezer en export)':
      'Beskrivning (för skärmläsare och export)',
  'valt buiten beeld — pas het focuspunt, zoom of doelpositie aan.':
      'faller utanför det synliga området — justera brännpunkt, zoom eller målposition.',
  'markering': 'markering',
  'Pijlen': 'Pilar',
  'Stap-voor-stap': 'Steg för steg',
  'Punt': 'Punkt',
  'markeringen': 'markeringar',
  'Eén tabel past niet op de bladbreedte, ook niet op de kleinste letter.':
      'En tabell får inte plats på sidbredden, inte ens vid minsta grad.',
  '{n} tabellen passen niet op de bladbreedte, ook niet op de kleinste letter.':
      '{n} tabeller får inte plats på sidbredden, inte ens vid minsta grad.',
  'Lange woorden en waarden zoals hashes of IP-adressen zijn daardoor middenin afgebroken.':
      'Långa ord och värden som hashar eller IP-adresser har därför brutits mitt i.',
  'Splits de tabel, of zet lange waarden onder elkaar in plaats van naast elkaar.':
      'Dela tabellen, eller placera långa värden under varandra i stället för bredvid varandra.',
  'Een ODT (OpenDocument Text) die opent in LibreOffice of Word. Bewerkbaar, met native voetnoten en koppen als outline. Het open tegenhanger van een Word-bestand.':
      'En ODT (OpenDocument Text) som öppnas i LibreOffice eller Word. Redigerbar, med inbyggda fotnoter och rubriker som disposition. Det öppna alternativet till en Word-fil.',
  'Een Word-document (.docx) dat opent in Word, Pages en LibreOffice. Bewerkbaar, met native voetnoten en koppen als outline. Mermaid-diagrammen worden als hoogwaardige afbeeldingen ingebed.':
      'Ett Word-dokument (.docx) som oppnas i Word, Pages och LibreOffice. Redigerbart, med inhemska fotnoter och rubriker som disposition. Mermaid-diagram backas in som hogkvalitativa bilder.',
  'Een ePub 3 met herflowbare tekst voor e-readers, tablets en telefoons. Koppen worden navigatie, noten staan achterin.':
      'En ePub 3 med anpassningsbar text för e-läsare, surfplattor och telefoner. Rubriker blir navigation, noter står längst bak.',
  'De paginaopmaak in dit document bevat ongeldige waarden en is genegeerd. De instellingen worden gebruikt.':
      'Sidinställningarna i detta dokument innehåller ogiltiga värden och ignorerades. Dina inställningar används.',
  'Het bestand is gewijzigd door een ander programma.':
      'Filen har ändrats av ett annat program.',
  'Herladen': 'Ladda om',
  'Kies kolommen voor de tijdlijn': 'Välj kolumner för tidslinjen',
  'Een tijdlijn gebruikt twee of drie kolommen. Kies welke kolommen uit deze tabel de tijdlijn worden. De overige kolommen verdwijnen uit de tabel.':
      'En tidslinje använder två eller tre kolumner. Välj vilka kolumner från denna tabell som blir tidslinjen. De återstående kolumnerna försvinner från tabellen.',
  'Volgorde (marker)': 'Ordning (markör)',
  'Toelichting (optioneel)': 'Beskrivning (valfri)',
  'Regel {n} bevat HTML-commentaar of HTML-tags. De visuele editor kan dit niet weergeven — Bron-modus is geactiveerd.':
      'Rad {n} innehåller HTML-kommentarer eller HTML-taggar. Den visuella editorn kan inte visa detta — Källläge aktiverat.',
  'Regel {n} bevat ontsnapte leestekens (zoals \\*). De visuele editor kan dit niet verliesvrij weergeven — Bron-modus is geactiveerd.':
      'Rad {n} innehåller escaped skiljetecken (som \\*). Den visuella editorn kan inte visa detta förlustfritt — Källläge aktiverat.',
  'Regel {n} is een losse tabelregel buiten een tabelblok. De visuele editor kan dit niet weergeven — Bron-modus is geactiveerd.':
      'Rad {n} är en löst tabellrad utanför ett tabellblock. Den visuella editorn kan inte visa detta — Källläge aktiverat.',
  'Bronmodus beschermt opmaak die de visuele editor niet verliesvrij ondersteunt. Schakel naar Bron voor deze constructies.':
      'Källläge skyddar markup som den visuella editorn inte stöder förlustfritt. Växla till Källa för dessa konstruktioner.',
  'Het logo komt korrelig uit de printer: het bestand is {breed}×{hoog} px en komt op deze maat uit op {dpi} dpi.':
      'Logotypen blir kornig i tryck: filen är {breed}×{hoog} px, vilket ger {dpi} dpi i den här storleken.',
  'Kies een logo van minstens {px} px breed, of zet de logomaat kleiner.':
      'Välj en logotyp som är minst {px} px bred, eller minska logotypstorleken.',
  'Thema accent op de documentband': 'Temats accent på sidhuvud/sidfot',
  'Er is een document met niet-opgeslagen wijzigingen gevonden van een vorige sessie:':
      'Ett dokument med osparade ändringar hittades från en tidigare session:',
  'Er zijn {n} bestanden met niet-opgeslagen wijzigingen gevonden van een vorige sessie:':
      'Det finns {n} filer med osparade ändringar från en tidigare session:',
  'Er zijn bestanden met niet-opgeslagen wijzigingen. Sla ze op voordat de app sluit.':
      'Det finns filer med osparade ändringar. Spara dem innan du stänger appen.',
  'Dit document heeft niet-opgeslagen wijzigingen. Sla het document op voordat het tabblad sluit.':
      'Det här dokumentet har osparade ändringar. Spara det innan du stänger fliken.',
  'De export is niet gelukt. Je document is niet gewijzigd; probeer het opnieuw of kies een ander formaat.':
      'Exporten lyckades inte. Ditt dokument är oförändrat; försök igen eller välj ett annat format.',
  'Thema documentkop': 'Temats dokumentrubrik',
  'Thema documentband': 'Temats sidhuvud/sidfot',
  'Een PDF met echte tekst: te selecteren, te doorzoeken en voor te lezen, met de koppen als bladwijzers. Formules, mermaid-diagrammen en grafieken worden getekend; noten staan achterin.':
      'En PDF med riktig text: markerbar, sökbar och uppläsbar, med rubrikerna som bokmärken. Formler, mermaid-diagram och grafer ritas ut; noterna står sist.',
  'Deze tekens konden niet in de PDF worden gezet en ontbreken erin:':
      'Dessa tecken kunde inte sättas i PDF:en och saknas i den:',
  'Diagram (bron)': 'Diagram (källa)',
  'Exporteer naar HTML of LaTeX als ze in het document horen.':
      'Exportera till HTML eller LaTeX om de hör hemma i dokumentet.',
  'Formule (bron)': 'Formel (källa)',
  'Grafiek (bron)': 'Graf (källa)',
  'Bijvoorbeeld project-id': 'Till exempel project-id',
  'Een document kan maximaal 100 vrije velden bevatten.':
      'Ett dokument kan innehålla högst 100 anpassade fält.',
  'Een veldwaarde mag maximaal 4096 tekens bevatten.':
      'Ett fältvärde får innehålla högst 4096 tecken.',
  'Gebruik {naam} in de kop- of voettekst.':
      'Använd {naam} i sidhuvudet eller sidfoten.',
  'Naam is ongeldig, gereserveerd of niet uniek.':
      'Namnet är ogiltigt, reserverat eller inte unikt.',
  'markeringen hebben geen herkenbare volgordewaarde. Ze blijven zichtbaar.':
      'Markörer har inget igenkännbart ordningsvärde. De förblir synliga.',
  'Tijdlijn · vervolg': 'Tidslinje · fortsättning',
  'Aflopend': 'Fallande',
  'De waarden in de volgordekolom staan niet oplopend.':
      'Värdena i ordningskolumnen är inte stigande.',
  'Deze tijdlijn is nog niet compleet. Pas de tabel aan of toon hem als gewone tabel.':
      'Denna tidslinje är inte klar ännu. Justera tabellen eller visa den som en normal tabell.',
  'Een tijdlijn werkt met twee of drie kolommen. Pas de tabel aan of toon hem als gewone tabel.':
      'En tidslinje fungerar med två eller tre kolumner. Justera tabellen eller visa den som en normal tabell.',
  'Huidige volgorde behouden': 'Behåll nuvarande ordning',
  'Lege gebeurtenissen blijven zichtbaar. Controleer rij:':
      'Tomma händelser förblir synliga. Kontrollera rad:',
  'Niet-herkende waarden': 'Okända värden',
  'Oplopend': 'Stigande',
  'Sorteren als…': 'Sortera som...',
  'Sorteren en tijdlijn maken': 'Sortera och skapa tidslinje',
  'Sorteren toepassen': 'Tillämpa sortering',
  'Tijdlijn maken': 'Skapa tidslinje',
  'Tijdlijn maken?': 'Skapa en tidslinje?',
  'Voeg minstens één gebeurtenis toe of toon dit als gewone tabel.':
      'Lägg till minst en händelse eller visa den som ett vanligt bord.',
  'Waarden bekijken': 'Visa värden',
  'gebeurtenissen gevonden.': 'händelser hittades.',
  'waarden herkend.': 'värden erkända.',
  'waarden niet herkend. Die rijen blijven onderaan in hun huidige volgorde.':
      'värden som inte känns igen. Dessa rader ligger kvar längst ner i deras nuvarande ordning.',
  'Basislettergrootte: {pt} pt': 'Grundstorlek på text: {pt} pt',
  'Basislettergrootte': 'Grundstorlek på text',
  'Koppen, voetnoten en tijdlijnkaarten schalen mee met deze maat.':
      'Rubriker, fotnoter och tidslinjekort skalar med den här storleken.',
  'Footer': 'Sidfot',
  'Geldt voor documenten en presentaties':
      'Gäller för dokument och presentationer',
  'Alleen voor documenten': 'Endast för dokument',
  'Alleen voor presentaties': 'Endast för presentationer',
  'Als tabel weergeven': 'Visa som tabell',
  'Als tijdlijn weergeven': 'Visa som tidslinje',
  'De waarden lijken niet allemaal van hetzelfde type. Kies hoe OciDeck ze moet lezen; niet-herkende waarden blijven onderaan in hun oorspronkelijke volgorde staan.':
      'Värdena verkar inte alla vara av samma typ. Välj hur OciDeck ska läsa dem; okända värden förblir längst ner i sin ursprungliga ordning.',
  'Deze kolom bevat nog geen waarden die op deze manier gesorteerd kunnen worden.':
      'Denna kolumn innehåller ännu inga värden som kan sorteras på detta sätt.',
  'Deze tabel kan nog niet als tijdlijn worden weergegeven en blijft ongewijzigd.':
      'Denna tabell kan ännu inte visas som en tidslinje och förblir oförändrad.',
  'Een tijdlijn werkt met twee of drie kolommen. Deze tabel blijft ongewijzigd.':
      'En tidslinje fungerar med två eller tre kolumner. Denna tabell förblir oförändrad.',
  'Gebeurtenis': 'Händelse',
  'Gebeurtenissen bewerken': 'Redigera händelser',
  'Hoe wil je deze kolom sorteren?': 'Hur vill du sortera den här kolumnen?',
  'Kolom aflopend sorteren': 'Sortera kolumn fallande',
  'Kolom oplopend sorteren': 'Sortera kolumn stigande',
  'Sorteren met aandachtspunten?': 'Sortera efter intressanta platser?',
  'Tijd': 'Tid',
  'Tijdlijn bekijken': 'Visa tidslinjen',
  'Voeg eerst minstens één gebeurtenis toe. Deze tabel blijft ongewijzigd.':
      'Lägg först till minst en händelse. Denna tabell förblir oförändrad.',
  'Alles': 'Alla',
  'Presentaties': 'Presentationer',
  'Documenten': 'Dokument',
  'Voorbeeld': 'Förhandsgranskning',
  'Voorbeeld tonen': 'Visa förhandsgranskning',
  'Voorbeeld tonen bij openen': 'Visa förhandsgranskning vid öppning',
  'Wijs een bestand aan om er hier een voorbeeld van te zien.':
      'Peka på en fil för att se en förhandsgranskning här.',
  'Dit bestand kan niet worden getoond. Openen weigert het ook — de inhoud is onveilig, beschadigd of onleesbaar.':
      'Den här filen kan inte visas. Öppning avvisar den också — innehållet är osäkert, skadat eller oläsbart.',
  'Dit document is leeg.': 'Det här dokumentet är tomt.',
  'Deze presentatie heeft nog geen dia.':
      'Den här presentationen har inga bilder än.',
  'Alleen het begin van het document wordt getoond.':
      'Endast början av dokumentet visas.',
  'Bestanden zoeken op deze computer': 'Hitta filer på den här datorn',
  'Dubbele bestanden opruimen': 'Rensa dubblerade filer',
  'bestand(en) gevonden': 'fil(er) hittade',
  'Geen presentaties of documenten gevonden.':
      'Inga presentationer eller dokument hittades.',
  'Geen presentaties of documenten gevonden in de bekende mappen.':
      'Inga presentationer eller dokument hittades i de kända mapparna.',
  'Zoek op bestandsnaam, titel of tekst in het bestand…':
      'Sök efter filnamn, titel eller text i filen…',
  'Toont in het openscherm een gerenderd voorbeeld van het bestand dat je aanwijst, zodat je ziet wat erin staat voordat je het opent.':
      'Visar i öppna-fönstret en renderad förhandsgranskning av filen du pekar på, så att du ser innehållet innan du öppnar den.',
  'Voetnoot': 'Fotnot',
  'Noten': 'Noter',
  'Voetnoten achterin het document': 'Fotnoter sist i dokumentet',
  'De tekst van de voetnoot': 'Fotnotens text',
  'Schrijfbreedte': 'Skrivbredd',
  'Paginabreedte': 'Sidbredd',
  'Leeskolom': 'Läskolumn',
  'Ware grootte': 'Verklig storlek',
  'Pagina-einden gelden alleen op paginabreedte.':
      'Sidbrytningar gäller bara vid sidbredd.',
  'Hoe breed de leeskolom in de visuele modus is. Smal leest rustig, breed gebruikt meer van het scherm. Of je op die kolom, op paginabreedte of op het hele venster schrijft, kies je in de werkbalk.':
      'Hur bred läskolumnen är i visuellt läge. Smal läses lugnt, bred använder mer av skärmen. Om du skriver på den kolumnen, i sidbredd eller över hela fönstret väljer du i verktygsfältet.',
  'De sprong "{doel}" wijst naar een dia die niet meer bestaat; tijdens het presenteren gebeurt er niets. Kies een andere doeldia.':
      'Hoppet "{doel}" pekar på en slide som inte längre finns; under presentationen händer ingenting. Välj en annan slide som mål.',
  'In een cirkel': 'Cirkel',
  'Onder elkaar': 'Lista',
  'Categorie': 'Kategori',
  'Categorie toevoegen': 'Lägg till kategori',
  'Categorie opheffen (blokken blijven behouden)':
      'Ta bort kategori (blocken behålls)',
  'Uitleg': 'Beskrivning',
  'Een keuzemenu: elk blok springt bij aanklikken naar een andere dia. Typ per blok een label en een uitleg, kies de doeldia en eventueel een afbeelding. Kies de indeling: raster, onder elkaar of in een cirkel. Met categorieën wissel je tijdens het presenteren tussen groepen blokken. Een blok zonder doel is gewone tekst.':
      'En valmeny: varje block hoppar till en annan diabild när man klickar på det. Skriv en etikett och en beskrivning för varje block, välj måldiabilden och eventuellt en bild. Välj layout: rutnät, lista eller cirkel. Med kategorier växlar du mellan grupper av block under presentationen. Ett block utan mål är vanlig text.',
  'Alleen een lege dia.': 'Endast en tom bild.',
  'Hoofdstukken op nieuwe pagina': 'Kapitel på ny sida',
  'Elk hoofdstuk begint nu op een nieuwe pagina':
      'Varje kapitel börjar nu på en ny sida',
  'Elk hoofdstuk begon al op een nieuwe pagina':
      'Varje kapitel började redan på en ny sida',
  'Snijtekens': 'Skärmärken',
  'Alleen in de LaTeX/PDF-export, en alleen met afloop. Vereist het crop-pakket in je TeX-installatie; een browser-afdruk van de HTML-export zet ze niet.':
      'Endast i LaTeX/PDF-exporten och endast med utfall. Kräver paketet crop i din TeX-installation; en webbläsarutskrift av HTML-exporten lägger inte till dem.',
  'Deze paginaopmaak staat in dit document':
      'Den här sidlayouten är sparad i det här dokumentet',
  'Deze paginaopmaak komt uit je instellingen':
      'Den här sidlayouten kommer från dina inställningar',
  'Paginaopmaak': 'Sidlayout',
  'De paginamaat en marges staan nu in dit document; wie het opent krijgt dezelfde pagina. Haal ze eruit om je eigen instelling te laten gelden.':
      'Sidstorleken och marginalerna finns nu i det här dokumentet; den som öppnar det får samma sida. Ta bort dem så gäller din egen inställning.',
  'De paginamaat en marges komen nu uit je instellingen, dus bij een ander kan het document anders uitvallen. Zet ze in het document om dat vast te leggen.':
      'Sidstorleken och marginalerna kommer nu från dina inställningar, så hos någon annan kan dokumentet se annorlunda ut. Spara dem i dokumentet för att låsa fast det.',
  'Uit het document halen': 'Ta bort från dokumentet',
  'In dit document vastleggen': 'Spara i det här dokumentet',
  'Rij erboven': 'Rad ovanför',
  'Rij eronder': 'Rad nedanför',
  'Rij weghalen': 'Radera rad',
  'Kolom links': 'Kolumn till vänster',
  'Kolom rechts': 'Kolumn till höger',
  'Kolom weghalen': 'Radera kolumn',
  'Met afloop wordt de pagina rondom groter dan het gekozen formaat, zodat inkt die tot de rand loopt dóór de snijlijn heen gaat. De afloop geldt voor élke export tot je hem weer op 0 zet. Laat dit op 0 voor gewoon afdrukken.':
      'Med utfall blir sidan större än det valda formatet runt om, så att färg som går ut i kanten fortsätter förbi skärlinjen. Utfallet gäller för varje export tills du ställer tillbaka det till 0. Lämna 0 för vanlig utskrift.',
  'Pagina\'s': 'Sidor',
  'Maat': 'Storlek',
  'Staand': 'Stående',
  'Liggend': 'Liggande',
  'documenten': 'dokument',
  'posters en boeken': 'affischer och böcker',
  'enveloppen': 'kuvert',
  'Afloop voor de drukker (mm)': 'Utfall för tryckeriet (mm)',
  'Pagina {n} van {m}': 'Sida {n} av {m}',
  'Pagina-einden tonen': 'Visa sidbrytningar',
  'Pagina-einden verbergen': 'Dölj sidbrytningar',
  'Boven (mm)': 'Överkant (mm)',
  'Onder (mm)': 'Nederkant (mm)',
  'Links (mm)': 'Vänster (mm)',
  'Rechts (mm)': 'Höger (mm)',
  'Smal (860 px)': 'Smal (860 px)',
  'Standaard (1100 px)': 'Standard (1100 px)',
  'Breed (1400 px)': 'Bred (1400 px)',
  'Volledige breedte': 'Full bredd',
  'Paginamaat': 'Sidstorlek',
  'Randstijl': 'Kantstil',
  'Tabelstijl': 'Tabellstil',
  'Geen randen': 'Inga kanter',
  'Lijnen (horizontaal)': 'Linjer (vågräta)',
  'Omrand (volledig)': 'Inramad (fullständig)',
  'Zebrastrepen (om en om)': 'Zebrarandning (varannan)',
  'Accentlijn onder koprij': 'Accentlinje under rubrikraden',
  'Tabel randkleur': 'Tabellens kantfärg',
  'Tabel zebrakleur': 'Tabellens zebrafärg',
  'Celopvulling: {px} px': 'Cellutfyllnad: {px} px',
  'Inhoudsopgave': 'Innehållsförteckning',
  'Inhoudsopgave — voeg koppen toe om de inhoudsopgave te vullen.':
      'Innehållsförteckning — lägg till rubriker för att fylla den.',
  'Schrijfbreedte editor': 'Skrivbredd i redigeraren',
  'Pagina-instellingen export': 'Sidinställningar för export',
  'Paginamaat (ISO-216) en marges voor HTML-print, LaTeX en PDF-export.':
      'Sidstorlek (ISO 216) och marginaler för HTML-utskrift, LaTeX och PDF-export.',
  '{maat} (liggend)': '{maat} (liggande)',
  'Mermaid': 'Mermaid',
  'Opmaak': 'Formgivning',
  'Afbeelding aanpassen': 'Justera bild',
  'Groot bestand': 'Stor fil',
  'Dit bestand is {grootte} groot. Dat is meer dan de aanbevolen limiet van {limiet}. Importeren kan traag zijn en veel geheugen vragen — op een kleiner apparaat kan de app vastlopen.':
      'Denna fil är {grootte} stor. Det är mer än den rekommenderade gränsen på {limiet}. Import kan vara långsam och kräva mycket minne — på en mindre enhet kan appen frysa.',
  'Toch importeren': 'Importera ändå',
  'Koptekst': 'Sidhuvud',
  'Afbeelding niet opgehaald': 'Bilden hämtades inte',
  'De doelmap kon niet worden aangemaakt of beschreven. Controleer of de ingestelde locatie beschikbaar is.':
      'Målmappen kunde inte skapas eller skrivas till. Kontrollera att den inställda platsen är tillgänglig.',
  'De ingestelde map is niet beschikbaar; de presentatie is in de documentenmap geopend:':
      'Den inställda mappen är inte tillgänglig; presentationen har öppnats i mappen Dokument:',
  'De naam in deze URL bestaat niet, of is niet op te zoeken. Controleer de URL op een typefout.':
      'Namnet i denna URL finns inte eller går inte att slå upp. Kontrollera URL:en för ett skrivfel.',
  'Deze URL stuurt door naar een ander adres. Vul dat adres rechtstreeks in — een omleiding volgen we niet, want die kan de veiligheidscontrole omzeilen.':
      'Denna URL omdirigerar till en annan adress. Ange den adressen direkt — vi följer inte omdirigeringar, eftersom de kan kringgå säkerhetskontrollen.',
  'Deze URL wijst naar een privé- of LAN-adres. Zulke adressen worden om veiligheidsredenen niet opgehaald.':
      'Denna URL pekar på en privat adress eller LAN-adress. Av säkerhetsskäl hämtas sådana adresser inte.',
  'Deze link is geen http(s)-adres. Plak een link die met http:// of https:// begint.':
      'Den här länken är inte en http(s)-adress. Klistra in en länk som börjar med http:// eller https://.',
  'Deze server gebruikt geen https. Gebruik een https-adres — je wachtwoord gaat bij elk verzoek mee en zou anders onversleuteld over het netwerk gaan.':
      'Den här servern använder inte https. Använd en https-adress — ditt lösenord skickas med vid varje begäran och skulle annars gå okrypterat över nätverket.',
  'Dit endpoint gebruikt geen https. Gebruik een https-endpoint, of markeer het als vertrouwd intern — anders gaan je presentaties onversleuteld over het netwerk.':
      'Den här slutpunkten använder inte https. Använd en https-slutpunkt eller markera den som betrodd intern — annars går dina presentationer okrypterat över nätverket.',
  'Gebruik een https-adres — anders gaat je wachtwoord onversleuteld over het netwerk.':
      'Använd en https-adress — annars går ditt lösenord okrypterat över nätverket.',
  'Gebruik een https-endpoint, of vink "Vertrouwd intern endpoint" aan — anders gaan je presentaties onversleuteld over het netwerk.':
      'Använd en https-slutpunkt eller kryssa i "Betrodd intern slutpunkt" — annars går dina presentationer okrypterat över nätverket.',
  'Het beveiligingscertificaat van deze server wordt niet vertrouwd. Controleer de URL of probeer een andere bron.':
      'Den här serverns säkerhetscertifikat är inte betrott. Kontrollera URL:en eller prova en annan källa.',
  'Het endpoint stuurt door naar een ander adres — meestal een verkeerde regio of endpoint-URL. Controleer de regio en het endpoint bij Instellingen → Opslag; opnieuw proberen helpt hier niet.':
      'Slutpunkten omdirigerar till en annan adress — oftast fel region eller slutpunkts-URL. Kontrollera regionen och slutpunkten under Inställningar → Lagring; att försöka igen hjälper inte här.',
  'Het endpoint stuurt door — meestal een verkeerde regio of endpoint-URL. Opnieuw proberen helpt hier niet.':
      'Slutpunkten omdirigerar — oftast fel region eller slutpunkts-URL. Att försöka igen hjälper inte här.',
  'Lokaal opgeslagen, maar publiceren naar de forge lukte niet:':
      'Sparat lokalt, men publiceringen till forgen misslyckades:',
  'Op deze URL staat geen presentatie (niet gevonden). Controleer of de link nog klopt.':
      'Det finns ingen presentation på denna URL (hittades inte). Kontrollera att länken fortfarande stämmer.',
  'Video kan niet worden geladen': 'Videon kan inte läsas in',
  'Titel boven afbeelding': 'Titel över bilden',
  'Toont de titel boven de afbeelding in plaats van eroverheen':
      'Visar titeln över bilden istället för ovanpå den',
  'Afbeeldingslay-out': 'Bildlayout',
  'Beide': 'Båda',
  'Volvlak': 'Fullbleed',
  'Kolombreedte': 'Kolumnbredd',
  'Linker kolomafbeelding': 'Vänster kolumnbild',
  'Rechter kolomafbeelding': 'Höger kolumnbild',
  'Geen linker kolomafbeelding': 'Ingen vänster kolumnbild',
  'Geen rechter kolomafbeelding': 'Ingen höger kolumnbild',
  'Volvlak: de afbeelding als schermvullende achtergrond. Links/Rechts/Beide: één of twee beeldkolommen naast de titeltekst.':
      'Fullbleed: bilden som skärmfyllande bakgrund. Vänster/Höger/Båda: en eller två bildkolumner bredvid titeltexten.',
  'Hernoemen': 'Byt namn',
  'Naam wijzigen': 'Ändra namn',
  'De extensie blijft vast — het bestandsformaat verandert niet door de naam.':
      'Filändelsen förblir fast — att byta namn ändrar inte filformatet.',
  'De naam mag geen mappen of bijzondere tekens bevatten.':
      'Namnet får inte innehålla mappar eller specialtecken.',
  'Hernoemd naar': 'Bytt namn till',
  'Kon de afbeelding niet hernoemen. Bestaat er al een bestand met die naam?':
      'Kunde inte byta namn på bilden. Finns det redan en fil med det namnet?',
  'Starthoek (graden)': 'Startvinkel (grader)',
  'Percentages op de taartpunten tonen': 'Visa procent på tårtbitarna',
  'Nieuw hoofdstuk op een nieuwe pagina': 'Nytt kapitel på en ny sida',
  'Laat elk hoofdstuk (een H1-kop) bij het exporteren en afdrukken op een nieuwe pagina beginnen.':
      'Låt varje kapitel (en H1-rubrik) börja på en ny sida vid export och utskrift.',
  'Pagina-einde': 'Sidbrytning',
  'Stijl': 'Stil',
  'Geen (platte tekst)': 'Ingen (vanlig text)',
  'Documentstijl': 'Dokumentstil',
  'Standaard documentstijl': 'Standarddokumentstil',
  'Deze stijl afdwingen': 'Framtvinga den här stilen',
  'De documentstijl wordt afgedwongen via de instellingen.':
      'Dokumentets stil framtvingas via inställningarna.',
  'De standaardstijl voor documenten die zelf geen stijl kiezen. Puur weergave en export — het schrijft niets in een bestand.':
      'Standardstilen för dokument som inte själva väljer en stil. Endast visning och export — inget skrivs till en fil.',
  'Negeer de eigen stijl van een document en gebruik overal de standaardstijl (huisstijl).':
      'Ignorera ett dokuments egen stil och använd standardstilen (grafisk profil) överallt.',
  'De doelschijf heeft onvoldoende ruimte. Maak ruimte vrij en probeer het opnieuw.':
      'Måldisken har inte tillräckligt med utrymme. Frigör utrymme och försök igen.',
  'Het zegel van dit deck klopt niet meer met de inhoud — het is bewerkt na het verzegelen.':
      'Detta decks sigill matchar inte längre innehållet — det redigerades efter förseglingen.',
  'HTML opent in elke browser zonder internet en rendert codeblokken, wiskunde en mermaid-diagrammen. LaTeX (Beamer) compileer je met pdflatex of xelatex.':
      'HTML öppnas i vilken browser som helst utan internet och renderar kodblock, matematik och mermaid-diagram. LaTeX (Beamer) kompileras med pdflatex eller xelatex.',
  'Een LaTeX article-document. Wiskunde gaat rechtstreeks door; afbeeldingen worden op relatief pad gereferentieerd. Compileer met pdflatex of xelatex.':
      'Ett LaTeX article-dokument. Matematik går direkt igenom; bilder refereras med relativ sökväg. Kompilera med pdflatex eller xelatex.',
  'Afbeelding geplakt': 'Bild klistrad',
  'Bibliotheekmap niet bereikbaar': 'Biblioteksmapp kan inte nås',
  'De bibliotheekmap is niet bereikbaar. Kies een map hieronder of pas Opslag aan onder ⋮ → Instellingen.':
      'Biblioteksmappen kan inte nås. Välj en mapp nedan eller justera Lagring under ⋮ → Inställningar.',
  'De map uit Instellingen is offline of verplaatst. Kies hier een map met afbeeldingen.':
      'Mappen från Inställningar är offline eller flyttad. Välj en mapp med bilder här.',
  'Kies een map met afbeeldingen': 'Välj en mapp med bilder',
  'Map toevoegen…': 'Lägg till mapp…',
  'Overzicht inklappen': 'Fäll ihop översikt',
  'Overzicht uitklappen': 'Fäll ut översikt',
  'Pakket (.ocideck)': 'Paket (.ocideck)',
  'Tabel geplakt': 'Tabell klistrad',
  'Voeg een map toe of gebruik "Bladeren" voor één bestand.':
      'Lägg till en mapp eller använd "Bläddra" för en enskild fil.',
  'dia\'s uit dit document.': 'bilder från detta dokument.',
  'Het logo van dit stijlprofiel is niet gevonden en wordt niet getoond (pad: {pad}). Kies een logo in de presentatie-instellingen.':
      'Logotypen för denna stilprofil hittades inte och visas inte (sökväg: {pad}). Välj en logotyp i presentationsinställningarna.',
  'Converteer naar document…': 'Konvertera till dokument…',
  'Converteer naar presentatie…': 'Konvertera till presentation…',
  'Converteren': 'Konvertera',
  'De indeling in dia\'s (de tekst loopt door als één document).':
      'Indelningen i bilder (texten fortsätter som ett enda dokument).',
  'De indeling in dia\'s is een voorstel; presentatie en document zijn geen perfecte spiegeling van elkaar.':
      'Indelningen i bilder är ett förslag; presentation och dokument är inte en perfekt spegelbild av varandra.',
  'Document exporteren': 'Exportera dokument',
  'Een geredigeerde kopie van de platte tekst — opent in elke Markdown-lezer.':
      'En maskad kopia av klartexten — öppnas i vilken Markdown-läsare som helst.',
  'Een thematische regel (---) wordt een diagrens.':
      'En tematisk linje (---) blir en bildgräns.',
  'Exporteren maakt een geredigeerde kopie voor een ontvanger. Je byte-getrouwe origineel bewaar je met Opslaan.':
      'Export skapar en maskad kopia för en mottagare. Ditt byte-trogna original behåller du med Spara.',
  'Exporteren…': 'Exportera…',
  'Eén toegankelijk HTML-bestand dat in elke browser opent zonder internet, met tabellen, wiskunde, mermaid en grafieken.':
      'En enda tillgänglig HTML-fil som öppnas i vilken webbläsare som helst utan internet, med tabeller, matematik, mermaid och diagram.',
  'Het thema en de opmaak per dia (_class).':
      'Temat och formateringen per bild (_class).',
  'Het zegel: een geconverteerd bestand is nieuw en draagt geen zegel.':
      'Sigillet: en konverterad fil är ny och bär inget sigill.',
  'Naar document converteren?': 'Konvertera till dokument?',
  'Naar presentatie converteren?': 'Konvertera till presentation?',
  'Nog een export': 'Ännu en export',
  'Voor de bredere kring: alles wat de controle vindt gaat eruit. Het bestand krijgt "-geredigeerd" in de naam.':
      'För den bredare kretsen: allt som kontrollen hittar tas bort. Filen får "-maskade" i namnet.',
  'Voor de opdrachtgever of auditor: alleen wat je zelf op "weglaten" hebt gezet, gaat eruit. De rest blijft leesbaar.':
      'För uppdragsgivaren eller revisorn: bara det du själv har markerat som "utelämna" tas bort. Resten förblir läsbar.',
  'Wat gaat er verloren bij het converteren:':
      'Vad går förlorat vid konverteringen:',
  'Wat verandert er bij het converteren:': 'Vad ändras vid konverteringen:',
  'We maken een kopie in een nieuw tabblad; je originele bestand blijft ongewijzigd.':
      'Vi skapar en kopia i en ny flik; din ursprungliga fil förblir oförändrad.',
  'Welk formaat?': 'Vilket format?',
  'document': 'dokument',
  'volledig': 'fullständig',
  'Invoegen': 'Infoga',
  'Visueel': 'Visuell',
  'Document': 'Dokument',
  'Nieuw document': 'Nytt dokument',
  'Geldt voor {n} slides van deze gesplitste reeks.':
      'Gäller för {n} bilder i den här uppdelade serien.',
  'Los automatisch op wat kan': 'Åtgärda det som kan automatiseras',
  'OpenKAT gaf een onverwacht antwoord ({code}). Probeer later opnieuw of vraag uw beheerder om hulp.':
      'OpenKAT gav ett oväntat svar ({code}). Försök igen senare eller be administratören om hjälp.',
  'Vanuit een OpenKAT-server': 'Från en OpenKAT-server',
  'Vanuit een map': 'Från en mapp',
  'Sluit één of meer OpenKAT-omgevingen aan (bijvoorbeeld productie en acceptatie). OciDeck toont beschikbare rapportages; de inhoud haalt u binnen via een JSON-export uit OpenKAT.':
      'Anslut en eller flera OpenKAT-miljöer (till exempel produktion och acceptans). OciDeck visar tillgängliga rapporter; innehållet hämtar du via en JSON-export från OpenKAT.',
  'Server toevoegen…': 'Lägg till server…',
  'Rapportage van server…': 'Rapport från server…',
  'Nog geen OpenKAT-server aangesloten.': 'Ingen OpenKAT-server ansluten än.',
  'Bezig…': 'Arbetar…',
  'OpenKAT-server bewerken': 'Redigera OpenKAT-server',
  'OpenKAT-server toevoegen': 'Lägg till OpenKAT-server',
  'OpenKAT-server toevoegen…': 'Lägg till OpenKAT-server…',
  'OpenKAT-server verwijderen?': 'Ta bort OpenKAT-server?',
  'Dit verwijdert “{name}” en het bijbehorende toegangstoken van dit apparaat. Dat kunt u niet ongedaan maken.':
      'Detta tar bort “{name}” och tillhörande åtkomsttoken från den här enheten. Det går inte att ångra.',
  'Weergavenaam': 'Visningsnamn',
  'Bijvoorbeeld Productie of Acceptatie':
      'Till exempel Produktion eller Acceptans',
  'Adres van OpenKAT': 'OpenKAT-adress',
  'Verbinding met: {host}': 'Anslutning till: {host}',
  'Eigen netwerk (LAN)': 'Eget nätverk (LAN)',
  'Alleen voor OpenKAT op het eigen netwerk. Staat HTTP toe en laat privé-adressen toe. Uitgeschakeld: alleen HTTPS.':
      'Endast för OpenKAT i det egna nätverket. Tillåter HTTP och privata adresser. Av: endast HTTPS.',
  'Toegangstoken': 'Åtkomsttoken',
  'Laat leeg om het opgeslagen token te behouden':
      'Lämna tomt för att behålla det sparade tokenet',
  'Plak het token hier': 'Klistra in tokenet här',
  'Vraag uw OpenKAT-beheerder om een API-token in het beheerdersscherm. Het token blijft op dit apparaat, in de sleutelhanger van uw besturingssysteem — niet in het deck.':
      'Be er OpenKAT-administratör om ett API-token i adminpanelen. Tokenet stannar på den här enheten, i operativsystemets nyckelring — inte i decket.',
  'Verbinding wordt getest…': 'Testar anslutning…',
  'Test de verbinding voordat u opslaat, zodat u weet dat naam, adres en token kloppen.':
      'Testa anslutningen innan du sparar, så att namn, adress och token stämmer.',
  'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.':
      'OpenKAT-anslutningen finns bara i desktopversionen.',
  'Lees OpenKAT-rapportages in als één managementoverzicht — vanuit een map of vanaf een server.':
      'Läs in OpenKAT-rapporter som en managementöversikt — från en mapp eller en server.',
  'Er staat al een OpenKAT-bron ingesteld; de koppeling blijft daarom bereikbaar, zodat een bestaand OpenKAT-deck bij te werken blijft.':
      'En OpenKAT-källa är redan konfigurerad; anslutningen förblir tillgänglig så att ett befintligt OpenKAT-deck kan uppdateras.',
  'Rapportage van OpenKAT-server': 'Rapport från OpenKAT-server',
  'Rapportage van OpenKAT-server…': 'Rapport från OpenKAT-server…',
  'Server: {name}': 'Server: {name}',
  'Organisaties worden opgehaald…': 'Hämtar organisationer…',
  'Rapportages worden opgehaald…': 'Hämtar rapporter…',
  'Er zijn geen organisaties zichtbaar voor dit token. Vraag uw beheerder om toegang, of kies een andere server.':
      'Inga organisationer syns för det här tokenet. Be administratören om åtkomst eller välj en annan server.',
  'Er staan geen organisatierapportages klaar op deze server. Maak in OpenKAT eerst een aggregaat-organisatierapport, of kies een andere organisatie.':
      'Inga organisationsrapporter är klara på den här servern. Skapa först en samlad organisationsrapport i OpenKAT, eller välj en annan organisation.',
  'JSON-export uit OpenKAT': 'JSON-export från OpenKAT',
  'OpenKAT levert de rapportage-inhoud als JSON-bestand. Exporteer in OpenKAT het gekozen rapport als JSON, en wijs dat bestand of de map hieraan.':
      'OpenKAT levererar rapportinnehållet som JSON-fil. Exportera den valda rapporten som JSON i OpenKAT och peka på den filen eller mappen här.',
  'Gekozen: {reportName} · {orgName} · {serverName}':
      'Valt: {reportName} · {orgName} · {serverName}',
  'JSON-bestand kiezen…': 'Välj JSON-fil…',
  'Map met exports kiezen…': 'Välj exportmapp…',
  'Vul een weergavenaam in, bijvoorbeeld Productie.':
      'Ange ett visningsnamn, till exempel Produktion.',
  'Vul een weergavenaam en een adres in.':
      'Ange ett visningsnamn och en adress.',
  'Plak een toegangstoken om verder te gaan.':
      'Klistra in ett åtkomsttoken för att fortsätta.',
  'Vul een adres in, bijvoorbeeld https://openkat.voorbeeld.nl':
      'Ange en adress, till exempel https://openkat.voorbeeld.nl',
  'Dit adres is niet geldig. Controleer of u een volledige URL heeft ingevuld.':
      'Den här adressen är ogiltig. Kontrollera att du angav en fullständig URL.',
  'Het adres moet met https:// beginnen, of zet Eigen netwerk aan voor HTTP op het eigen netwerk.':
      'Adressen måste börja med https://, eller slå på Eget nätverk för HTTP i det egna nätverket.',
  'Verbonden met {host}. Er zijn nog geen organisaties zichtbaar voor dit token.':
      'Ansluten till {host}. Inga organisationer syns för det här tokenet än.',
  'Verbonden met {host}. {n} organisatie(s) bereikbaar.':
      'Ansluten till {host}. {n} organisation(er) tillgängliga.',
  'De verbinding met OpenKAT is mislukt. Controleer het adres en uw netwerk, en probeer opnieuw.':
      'Anslutningen till OpenKAT misslyckades. Kontrollera adressen och nätverket och försök igen.',
  'Er is geen toegangstoken. Plak het token van uw beheerder en probeer opnieuw.':
      'Inget åtkomsttoken. Klistra in tokenet från er administratör och försök igen.',
  'Alleen HTTPS is toegestaan, tenzij Eigen netwerk aan staat.':
      'Endast HTTPS tillåts om Eget nätverk inte är på.',
  'OpenKAT weigerde het token. Vraag uw beheerder om een geldig API-token en plak het opnieuw.':
      'OpenKAT avvisade tokenet. Be administratören om ett giltigt API-token och klistra in det igen.',
  'OpenKAT reageerde niet op tijd. Controleer of de server bereikbaar is en probeer opnieuw.':
      'OpenKAT svarade inte i tid. Kontrollera att servern är nåbar och försök igen.',
  'Dit adres is niet bereikbaar. Controleer de spelling van de hostnaam en of u op het juiste netwerk zit.':
      'Den här adressen går inte att nå. Kontrollera stavningen av värdnamnet och att du är på rätt nätverk.',
  'OpenKAT gaf een onverwacht groot antwoord. Probeer later opnieuw of vraag uw beheerder om hulp.':
      'OpenKAT gav ett oväntat stort svar. Försök igen senare eller be administratören om hjälp.',
  'Verbonden': 'Ansluten',
  'Token ontbreekt': 'Token saknas',
  'Laatst gecontroleerd mislukt': 'Senaste kontrollen misslyckades',
  'Nog niet gecontroleerd': 'Inte kontrollerad än',
  'Zoekveld wissen': 'Rensa sökfält',
  'Gantt': 'Gantt',
  'Dag': 'Dag',
  'Week': 'Vecka',
  'Maand': 'Månad',
  'Tijdschaal': 'Tidsskala',
  'De as-granulariteit van het Gantt-diagram. “Auto” kiest op basis van het datumbereik van de taken.':
      'Axelns granularitet för Gantt-diagrammet. “Auto” väljer baserat på uppgifternas datumintervall.',
  'Sectiedelingen': 'Sektionsindelningar',
  'Behandel een taaknaam die met “## ” begint als een sectiekop in het diagram.':
      'Behandla ett uppgiftsnamn som börjar med “## ” som en sektionsrubrik i diagrammet.',
  'Secties': 'Sektioner',
  'Een projectschema als Gantt-diagram. Vul de tabel met taak, start, duur, voortgang en afhankelijkheden; het diagram wordt afgeleid. Een taaknaam die met “Milestone:” begint is een nulduur-mijlpaal.':
      'En projekttidplan som Gantt-diagram. Fyll i tabellen med uppgift, start, längd, förlopp och beroenden; diagrammet härleds. Ett uppgiftsnamn som börjar med “Milestone:” är en milstolpe med noll längd.',
  'Let op: er staan mogelijk persoonsgegevens in de sessie-data.':
      'Observera: sessionsdatan kan innehålla personuppgifter.',
  'Privacy-bevindingen in sessie-data': 'Integritetsfynd i sessionsdata',
  'De privacyscan vond mogelijk persoonsgegevens in de sessie-data. De export redigeert deze automatisch; klik op een bevinding voor de details.':
      'Integritetsgenomsökningen kan ha hittat personuppgifter i sessionsdatan. Exporten maskar dem automatiskt; klicka på ett fynd för detaljerna.',
  'Tijdens het presenteren heb je checklists ingevuld en tabellen bijgewerkt op {aantal} dia’s.':
      'Under presentationen fyllde du i checklistor och uppdaterade tabeller på {aantal} bilder.',
  'en nog {aantal} dia’s.': 'och {aantal} bilder till.',
  'Sessie-wijzigingen bewaren?': 'Spara ändringar i sessionen?',
  'In deck behouden': 'Behåll i presentationen',
  'Downloaden als losse bestanden': 'Ladda ner som separata filer',
  'Map voor sessie-bestanden kiezen': 'Välj mapp för sessionsfiler',
  'Zoek op taal of code': 'Sök på språk eller kod',
  'Geen talen gevonden': 'Inga språk hittades',
  'De sectie "{sectie}" is geen standaardsectie van een bevinding en wordt niet getoond of geëxporteerd (de inhoud blijft wel in het bronbestand). Hernoem de kop naar Description, Confirmation (reproduction), Possible impact of Recommendation.':
      'Avsnittet "{sectie}" är inte ett standardavsnitt i ett fynd och visas eller exporteras inte (innehållet finns dock kvar i källfilen). Byt namn på rubriken till Description, Confirmation (reproduction), Possible impact eller Recommendation.',
  'Breedte aanpassen': 'Justera bredd',
  'Niet akkoord en afsluiten': 'Avvisa och avsluta',
  'Vul de datum van vandaag in': 'Fyll i dagens datum',
  'Springt naar': 'Hoppar till',
  'Geen sprong': 'Inget hopp',
  'Blok toevoegen': 'Lägg till block',
  'Blok verwijderen': 'Ta bort block',
  'Geen afbeelding': 'Ingen bild',
  'Afbeelding verwijderen': 'Ta bort bild',
  'Nog geen blokken. Voeg een keuzeblok toe.':
      'Inga block ännu. Lägg till ett valblock.',
  'Keuzemenu': 'Valmeny',
  'Hierna': 'Därefter',
  'Volgende dia': 'Nästa bild',
  'Sprong': 'Hopp',
  'Kies naar welke dia de presentatie na deze springt. Standaard is dat gewoon de volgende dia. Zo laat je een keuze-tak aan het eind terugkeren naar het menu.':
      'Välj vilken bild presentationen hoppar till efter denna. Som standard är det helt enkelt nästa bild. Så kan en valgren återvända till menyn i slutet.',
  'De doeldia bestaat niet meer — de presentatie gaat hier gewoon verder.':
      'Målbilden finns inte längre — presentationen fortsätter helt enkelt här.',
  'Bewerk deze dia als markdown-bron': 'Redigera denna bild som markdown-källa',
  'Dit is een presentatie, geen Markdown-bestand. OciDeck kan hem importeren naar een nieuw deck.':
      'Det här är en presentation, inte en Markdown-fil. OciDeck kan importera den till ett nytt deck.',
  'Dit is een presentatie, geen Markdown-bestand. Zet de module Importeren aan om hem om te zetten naar een deck.':
      'Det här är en presentation, inte en Markdown-fil. Aktivera modulen Importera för att omvandla den till ett deck.',
  'De zwakhedenlijst (78): id, titel, MASVS-categorie, platform, de CWE-koppeling en een korte omschrijving. Plus een brug van de oude beta-nummering (tot 0119) naar de canonieke id\'s, zodat de MASTG-kruiskoppeling blijft kloppen.':
      'Listan över svagheter (78): id, titel, MASVS-kategori, plattform, CWE-kopplingen och en kort beskrivning. Plus en brygga från den gamla beta-numreringen (upp till 0119) till de kanoniska id:na, så att MASTG-korsreferensen fortsätter att stämma.',
  'Alle integraties': 'Alla integrationer',
  'Alles inschakelen': 'Aktivera alla',
  'Alles uitschakelen': 'Inaktivera alla',
  'Koppelingen met andere systemen. Elke koppeling staat standaard uit en blijft inactief tot u haar inschakelt.':
      'Anslutningar med andra system. Varje anslutning är avstängd som standard och förblir inaktiv tills du aktiverar den.',
  'Presentaties uit PowerPoint (.pptx), Keynote (.key) en Impress (.odp) binnenhalen als bewerkbaar deck. Koppelingen met andere systemen, zoals OpenKAT, staan onder Integraties.':
      'Hämta in presentationer från PowerPoint (.pptx), Keynote (.key) och Impress (.odp) som ett redigerbart deck. Anslutningar med andra system, som OpenKAT, finns under Integrationer.',
  'Media (WebRTC)': 'Media (WebRTC)',
  'Media-stack testen': 'Testa mediestacken',
  'De media-stack werkt op dit apparaat.':
      'Mediestacken fungerar på den här enheten.',
  'De media-stack kon niet laden op dit apparaat.':
      'Mediestacken kunde inte läsas in på den här enheten.',
  'Media-versleuteling (E2EE): uit op dit platform.':
      'Mediekryptering (E2EE): av på den här plattformen.',
  'Media-versleuteling (E2EE): nog niet beschikbaar.':
      'Mediekryptering (E2EE): inte tillgänglig ännu.',
  'Media-versleuteling (E2EE): aan.': 'Mediekryptering (E2EE): på.',
  'Conferentie-URL (optioneel): toont de OciDeck-companion-kamer':
      'Konferens-URL (valfritt): visar OciDeck-companion-rummet',
  'Companion-kamer': 'Companion-rum',
  'Aanwezig in de kamer': 'Närvarande i rummet',
  'De bijnaam is al in gebruik in de kamer.':
      'Smeknamnet används redan i rummet.',
  'Deze kamer is alleen voor leden.': 'Det här rummet är endast för medlemmar.',
  'Deze kamer vereist een wachtwoord.': 'Det här rummet kräver ett lösenord.',
  'De kamer kon niet worden betreden.': 'Det gick inte att gå in i rummet.',
  'Sessie actief als': 'Session aktiv som',
  'Ingelogd, maar de server kon geen sessie opzetten (resource-binding mislukt).':
      'Inloggad, men servern kunde inte upprätta en session (resursbindning misslyckades).',
  'XMPP-server testen': 'Testa XMPP-server',
  'Voer een XMPP-server, een Jabber-ID en een wachtwoord in en test de verbinding. Er wordt niets bewaard; dit controleert alleen of het account werkt. Laat de Jabber-ID leeg voor anonieme toegang.':
      'Ange en XMPP-server, ett Jabber-ID och ett lösenord och testa anslutningen. Ingenting sparas; detta kontrollerar bara om kontot fungerar. Lämna Jabber-ID:t tomt för anonym åtkomst.',
  'Serveradres (wss://…)': 'Serveradress (wss://…)',
  'Jabber-ID (gebruiker@domein)': 'Jabber-ID (användare@domän)',
  'Verbinden…': 'Ansluter…',
  'Verbonden — authenticatie geslaagd via': 'Ansluten — autentiserad via',
  'De server biedt geen inlogmethode die OciDeck ondersteunt.':
      'Servern erbjuder ingen inloggningsmetod som OciDeck stöder.',
  'De gebruikersnaam of het wachtwoord werd niet geaccepteerd.':
      'Användarnamnet eller lösenordet godkändes inte.',
  'De server kon zich niet bewijzen (wederzijdse verificatie mislukt).':
      'Servern kunde inte bevisa sin identitet (ömsesidig autentisering misslyckades).',
  'De server wilde de verbinding omleiden naar een andere host; geweigerd.':
      'Servern ville omdirigera anslutningen till en annan värd; nekades.',
  'De server reageerde niet op tijd.': 'Servern svarade inte i tid.',
  'Kon geen verbinding maken met de server. Gebruik wss:// en een geldig adres.':
      'Kunde inte ansluta till servern. Använd wss:// och en giltig adress.',
  'De verbinding met de server mislukte.':
      'Anslutningen till servern misslyckades.',
  'XMPP-verbinding testen': 'Testa XMPP-anslutning',
  'Controleer of OciDeck een XMPP-server kan bereiken en met uw account kan inloggen. Er wordt niets bewaard.':
      'Kontrollera om OciDeck kan nå en XMPP-server och logga in med ditt konto. Ingenting sparas.',
  'Markeer alle juiste antwoorden. Bij presenteren worden alle antwoorden in willekeurige volgorde getoond.':
      'Markera alla rätta svar. Vid presentationen visas alla svar i slumpmässig ordning.',
  'Markeer de goede antwoorden. Bij presenteren wordt één goed antwoord met een willekeurige greep uit de foute antwoorden getoond.':
      'Markera de rätta svaren. Vid presentationen visas ett rätt svar tillsammans med ett slumpmässigt urval av felaktiga svar.',
  'Vraag is niet speelbaar: {aantal} antwoorden, terwijl deze vraagsoort er maximaal {maximum} toestaat.':
      'Frågan kan inte spelas: {aantal} svar, medan denna frågetyp tillåter högst {maximum}.',
  'Actueel': 'Aktuell',
  'Codeblok': 'Kodblock',
  'Controleren…': 'Kontrollera...',
  'Documentoverzicht': 'Dokumentöversikt',
  'Doorgaan met bewerken': 'Fortsätt redigera',
  'Geen opdrachten gevonden': 'Inga uppdrag hittades',
  'Genummerde lijst': 'Numrerad lista',
  'Huidig concept': 'Nuvarande koncept',
  'Invoegen of opmaken': 'Infoga eller formatera',
  'Invoegen of opmaken (Ctrl/Cmd+Spatie)':
      'Infoga eller formatera (Ctrl/Cmd+Mellanslag)',
  'Je wijzigingen zijn nog niet toegepast. Wil je ze verwerpen?':
      'Dina ändringar har inte tillämpats ännu. Vill du avvisa dem?',
  'Kop 1': 'Rubrik 1',
  'Kop 2': 'Rubrik 2',
  'Kop 3': 'Rubrik 3',
  'Markdown-broneditor': 'Markdown källredigerare',
  'Niet toegepast': 'Inte tillämpat',
  'Niet-toegepaste wijzigingen': 'Ej tillämpade ändringar',
  'Pas de huidige wijzigingen eerst toe of verwerp ze voordat je van bereik wisselt.':
      'Tillämpa eller avvisa aktuella ändringar innan du byter scope.',
  'Problemen gevonden': 'Problem hittades',
  'Schrijftips': 'Skrivtips',
  'Snel herstellen': 'Återhämta dig snabbt',
  'Taak': 'Uppgift',
  'Toegepaste versie': 'Tillämpad version',
  'Visuele bewerking is uitgeschakeld omdat deze Markdown niet verliesvrij kan worden omgezet.':
      'Visuell redigering är inaktiverad eftersom denna Markdown inte kan konverteras förlustfritt.',
  'Wijzigingen vergelijken': 'Jämför förändringar',
  'Wijzigingen verwerpen': 'Avvisa ändringar',
  'Zoek een opdracht…': 'Hitta ett uppdrag...',
  'kolom': 'kolumn',
  'schrijftips': 'skrivtips',
  'tekens': 'tecken',
  'Persoonsgegevens weggelaten': 'Personuppgifter utelämnade',
  'Persoonsgegevens gemarkeerd voor de ontvanger':
      'Personuppgifter markerade för mottagaren',
  'Afbeeldingen beheren': 'Hantera bilder',
  'Er staan nog geen afbeeldingen in je bibliotheekmappen.':
      'Det finns inga bilder i dina biblioteksmappar ännu.',
  'Voortgang per sectie': 'Framsteg per sektion',
  'Nog te doen': 'Återstår',
  'Voortgangsoverzicht en -grafiek bijgewerkt':
      'Framstegsöversikt och -diagram uppdaterade',
  'Genereer managementreview (9.3)': 'Generera ledningens genomgång (9.3)',
  'Voegt een ingevuld sjabloon voor de directiebeoordeling (ISO-clausule 9.3) toe, met de huidige voortgang erin.':
      'Lägger till en förifylld mall för ledningens genomgång (ISO-avsnitt 9.3) med det aktuella framsteget.',
  'Managementreview (clausule 9.3) — Input':
      'Ledningens genomgång (avsnitt 9.3) — Underlag',
  'Managementreview (clausule 9.3) — Output':
      'Ledningens genomgång (avsnitt 9.3) — Resultat',
  'Managementreview (9.3) toegevoegd': 'Ledningens genomgång (9.3) tillagd',
  'Er staat al een managementreview in dit deck':
      'Det här decket innehåller redan en ledningens genomgång',
  '## Input (9.3.2)\n\n- **a.** Status van acties uit eerdere directiebeoordelingen\n- **b.** Wijzigingen in interne en externe onderwerpen die het managementsysteem raken\n- **c.** Wijzigingen in behoeften en verwachtingen van belanghebbenden\n- **d.** Prestaties en doeltreffendheid — {p}% geïmplementeerd ({impl}/{app} beheersmaatregelen van toepassing)\n    - Trends in afwijkingen en corrigerende maatregelen\n    - Monitoring- en meetresultaten\n    - Auditresultaten\n- **e.** Toereikendheid van middelen\n- **f.** Doeltreffendheid van maatregelen tegen risico\'s en kansen\n- **g.** Kansen voor verbetering':
      '## Underlag (9.3.2)\n\n- **a.** Status för åtgärder från tidigare ledningens genomgångar\n- **b.** Förändringar i interna och externa frågor som påverkar ledningssystemet\n- **c.** Förändringar i intressenternas behov och förväntningar\n- **d.** Prestanda och verkan — {p}% implementerat ({impl}/{app} tillämpliga åtgärder)\n    - Trender i avvikelser och korrigerande åtgärder\n    - Resultat av övervakning och mätning\n    - Revisionsresultat\n- **e.** Resursernas tillräcklighet\n- **f.** Verkan av åtgärder mot risker och möjligheter\n- **g.** Möjligheter till förbättring',
  '## Output (9.3.3)\n\n- Besluiten over kansen voor continue verbetering\n- Besluiten over eventuele wijzigingen aan het managementsysteem\n- Benodigde middelen\n\n_Vul de besluiten, acties en eigenaren hieronder in._':
      '## Resultat (9.3.3)\n\n- Beslut om möjligheter till ständig förbättring\n- Beslut om eventuella ändringar av ledningssystemet\n- Resursbehov\n\n_Fyll i beslut, åtgärder och ansvariga nedan._',
  'Procesverbetering: DMADV-project': 'Processförbättring: DMADV-projekt',
  'DMADV-skelet voor het ontwerpen en verifiëren van een nieuw proces.':
      'DMADV-skelett för att designa och verifiera en ny process.',
  'Procesverbetering: Kaizen-project': 'Processförbättring: Kaizen-projektet',
  'Compact verbeterproject met Plan-, Do- en Check-fases.':
      'Kompakt förbättringsprojekt med Plan, Gör och Kontrollera faser.',
  'Procesverbetering: A3-project': 'Processförbättring: A3-projekt',
  'A3-skelet voor probleem, analyse en verbeteracties.':
      'A3-skelett för problem, analys och förbättringsåtgärder.',
  'Procesverbetering: 8D-project': 'Processförbättring: 8D-projekt',
  '8D-skelet voor probleembeschrijving, oorzaken en borging.':
      '8D-skelett för problembeskrivning, orsaker och försäkran.',
  'Rapporteer de voortgang van een ISO-managementsysteem (27001/9001/42001): status per beheersmaatregel en een afgeleid voortgangsoverzicht. Standaard uit; zet de uitbreiding aan om het dia-type te gebruiken.':
      'Rapportera framstegen för ett ISO-ledningssystem (27001/9001/42001): status per åtgärd och en härledd framstegsöversikt. Avstängt som standard; aktivera tillägget för att använda bildtypen.',
  'Module aan. De ISO-index is lokaal beschikbaar ({n} beheersmaatregelen over drie normen); alleen de nummers en korte titels, niet de normtekst.':
      'Modul aktiv. ISO-indexet är tillgängligt lokalt ({n} åtgärder över tre standarder); endast numren och de korta titlarna, inte standardtexten.',
  'Beheersmaatregel-status': 'Åtgärdsstatus',
  'Alleen de clausule-index 4–10 (28 sub-clausules + korte titels). ISO 9001 kent geen Annex A. De normtekst is NIET gebundeld.':
      'Endast klausulindexet 4–10 (28 underklausuler + korta titlar). ISO 9001 har ingen Annex A. Standardtexten ingår INTE.',
  'Alleen de index van Annex A (38 control-ids + korte titels) en de negen doelstelling-koppen A.2–A.10. De normtekst is NIET gebundeld.':
      'Endast Annex A-indexet (38 åtgärds-id:n + korta titlar) och de nio målrubrikerna A.2–A.10. Standardtexten ingår INTE.',
  'Alleen de index van Annex A (93 control-ids + korte titels) en de vier thema-koppen. De normtekst is NIET gebundeld.':
      'Endast Annex A-indexet (93 åtgärds-id:n + korta titlar) och de fyra temarubrikerna. Standardtexten ingår INTE.',
  'De implementatiestatus per beheersmaatregel van een ISO-norm (27001/9001/42001). Laad de controls uit een norm en vul status, eigenaar en bewijs in.':
      'Implementeringsstatus per åtgärd i en ISO-standard (27001/9001/42001). Läs in åtgärderna från en standard och fyll i status, ägare och bevis.',
  'ISO copyright — index als feitreferentie, normtekst niet meegeleverd':
      'ISO-upphovsrätt — index som faktareferens, standardtext ingår inte',
  'Maakt of vernieuwt een overzichtsdia met de voortgang per sectie (afgeleid uit alle beheersmaatregel-dia\'s).':
      'Skapar eller uppdaterar en översiktsbild med framstegen per avsnitt (härledd från alla åtgärdsbilder).',
  'Voegt de beheersmaatregelen van een ISO-norm toe (alleen de index; alleen nieuwe ids).':
      'Lägger till åtgärderna från en ISO-standard (endast indexet; endast nya id:n).',
  'Alle secties': 'Alla avsnitt',
  'Beheersmaatregel': 'Åtgärd',
  'Beheersmaatregel toevoegen': 'Lägg till åtgärd',
  'Beheersmaatregelen laden…': 'Läs in åtgärder…',
  'Genereer voortgangsoverzicht': 'Skapa framstegsöversikt',
  'Geïmplementeerd': 'Implementerad',
  'ISO 27001 · Annex A — Organisatorisch (A.5)':
      'ISO 27001 · Annex A — Organisatorisk (A.5)',
  'Kies een norm': 'Välj en standard',
  'Managementsysteem': 'Ledningssystem',
  'Niet gescoord': 'Ej bedömd',
  'Niveau': 'Nivå',
  'Nog geen beheersmaatregel-dia\'s om samen te vatten':
      'Inga åtgärdsbilder att sammanfatta ännu',
  'Sectie': 'Avsnitt',
  'Streefdatum': 'Måldatum',
  'Van toepassing': 'Tillämplig',
  'Voortgang': 'Framsteg',
  'Voortgang managementsysteem': 'Ledningssystemets framsteg',
  'Welk deel?': 'Vilken del?',
  'beheersmaatregelen geladen': 'åtgärder inlästa',
  'geïmplementeerd': 'implementerat',
  'Module aan. Rekenkern, dia-indelingen en sjablonen zijn lokaal beschikbaar ({n} control-chartfactoren).':
      'Modulen är på. Beräkningskärna, bildlayouter och mallar är tillgängliga lokalt ({n} styrdiagramfaktorer).',
  'SIPOC-procesoverzicht': 'SIPOC-processöversikt',
  'Bepaal de scope en afhankelijkheden van een proces via leveranciers, input, hoofdstappen, output en klanten.':
      'Fastställ en process omfattning och beroenden genom leverantörer, indata, huvudsteg, utdata och kunder.',
  'Hulpmiddelen voor procesverbetering (SIPOC, DMAIC, Kaizen en A3). Standaard uit; zet de uitbreiding aan om de bijbehorende sjablonen en dia-indelingen te gebruiken.':
      'Verktyg för processförbättring (SIPOC, DMAIC, Kaizen och A3). Avstängda som standard; aktivera tillägget för att använda tillhörande mallar och bildlayouter.',
  'Videovergaderingen': 'Videomöten',
  'Neem deel aan videovergaderingen en presenteer vanuit OciDeck met een eigen interface: deelnemers naast uw slide, niet in het venster van een andere app. Bring-your-own-server (Jitsi of Matrix); OciDeck host niets en houdt de gespreksgegevens buiten AI. De aansluiting op een vergaderdienst volgt in een volgende versie.':
      'Delta i videomöten och presentera från OciDeck med ett eget gränssnitt: deltagarna bredvid din slide, inte i ett annat programs fönster. Bring-your-own-server (Jitsi eller Matrix); OciDeck är inte värd för något och håller samtalsdatan borta från AI. Anslutningen till en mötestjänst kommer i en framtida version.',
  'Videovergadering': 'Videomöte',
  'Nog geen actieve vergadering. Het aansluiten op een vergaderdienst wordt in een volgende versie toegevoegd.':
      'Inget aktivt möte ännu. Anslutningen till en mötestjänst läggs till i en framtida version.',
  'Dempen opheffen': 'Slå på ljud',
  'Dempen': 'Stäng av ljud',
  'Camera aan': 'Kamera på',
  'Camera uit': 'Kamera av',
  'Scherm delen': 'Dela skärm',
  'Vergadering verlaten': 'Lämna mötet',
  'De afbeeldingenbibliotheek is te groot; alleen de nieuwste afbeeldingen worden getoond.':
      'Bildbiblioteket är för stort; endast de nyaste bilderna visas.',
  'Dit pakket is te groot (maximaal 512 MB). Anders kan OciDeck het daarna niet meer openen. Gebruik minder of kleinere afbeeldingen, video’s of audiobestanden.':
      'Det här paketet är för stort (högst 512 MB). Annars kan OciDeck inte öppna det efteråt. Använd färre eller mindre bilder, videor eller ljudfiler.',
  'De afbeeldingen samen zijn te groot voor één HTML-bestand (maximaal 512 MB). Gebruik minder of kleinere afbeeldingen, of exporteer als PDF of pakket.':
      'Bilderna är tillsammans för stora för en enda HTML-fil (högst 512 MB). Använd färre eller mindre bilder, eller exportera som PDF eller paket.',
  'Deze export heeft te veel dia’s op te hoge resolutie om veilig te renderen. Exporteer in delen of gebruik de gecomprimeerde PDF.':
      'Den här exporten har för många bilder i för hög upplösning för att kunna renderas säkert. Exportera i delar eller använd den komprimerade PDF:en.',
  'Rond de presentatie eerst af en sla haar op; daarna kun je de herkomst ondertekenen.':
      'Slutför och spara presentationen först; sedan kan du signera dess ursprung.',
  'Herkomst ondertekend.': 'Ursprung signerat.',
  'De herkomst kon niet worden ondertekend.': 'Ursprunget kunde inte signeras.',
  'Herkomst ondertekenen': 'Signera ursprung',
  'Herkomst bevestigd': 'Ursprung bekräftat',
  'Ondertekend met een eerder bevestigde sleutel — dit deck komt van die eigenaar.':
      'Signerad med en tidigare bekräftad nyckel — den här presentationen kommer från den ägaren.',
  'Ondertekend': 'Signerad',
  'Ondertekend, nog niet geverifieerd. Vingerafdruk:':
      'Signerad, ännu inte verifierad. Fingeravtryck:',
  'Gewijzigd na ondertekenen': 'Ändrad efter signering',
  'De inhoud wijkt af van wat is ondertekend — het bestand is na het ondertekenen gewijzigd.':
      'Innehållet skiljer sig från det signerade — filen ändrades efter signeringen.',
  'Herkomst ongeldig': 'Ursprung ogiltigt',
  'De herkomst-ondertekening klopt niet of is vervalst.':
      'Ursprungssignaturen är felaktig eller förfalskad.',
  'Herkomst niet hier te controleren': 'Ursprung kan inte kontrolleras här',
  'De ondertekening is aanwezig, maar kan hier niet worden nagerekend — controleer tegen het oorspronkelijke `.md`-bestand.':
      'Signaturen finns men kan inte beräknas om här — kontrollera den mot den ursprungliga `.md`-filen.',
  'Bestaande identiteit vervangen?': 'Ersätt befintlig identitet?',
  'Dit apparaat heeft al een samenwerkingsidentiteit. Herstellen vervangt die door de identiteit uit de sleutel. Heb je van de huidige identiteit een herstelsleutel bewaard? Zonder back-up ben je die kwijt.':
      'Den här enheten har redan en samarbetsidentitet. Återställning ersätter den med identiteten från nyckeln. Har du sparat en återställningsnyckel för den nuvarande identiteten? Utan säkerhetskopia förlorar du den.',
  'Het webgeheugen voor presentatiemedia is vol (maximaal 256 MB). Sla je werk eerst op als .ocideck om verlies te voorkomen. Gebruik daarna minder of kleinere afbeeldingen, video’s of audiobestanden, sluit andere decks of herlaad zonder andere decks te openen.':
      'Webbminnet för presentationsmedier är fullt (högst 256 MB). Spara först ditt arbete som en .ocideck-fil för att förhindra dataförlust. Använd sedan färre eller mindre bilder, videor eller ljudfiler, stäng andra bildspel eller läs in på nytt utan att öppna andra bildspel.',
  'Ongeldige vraag': 'Ogiltig fråga',
  'Herstelsleutel': 'Återställningsnyckel',
  'Bewaar deze herstelsleutel op een veilige plek — bijvoorbeeld in je wachtwoordkluis. Het is de enige manier om dezelfde identiteit op een ander apparaat te herstellen; zonder deze sleutel begin je daar als een nieuw, nog niet geverifieerd apparaat. Deel hem met niemand.':
      'Förvara den här återställningsnyckeln på ett säkert ställe — till exempel i ditt lösenordsvalv. Det är det enda sättet att återställa samma identitet på en annan enhet; utan den här nyckeln börjar du där som en ny, ännu inte verifierad enhet. Dela den inte med någon.',
  'Herstelsleutel gekopieerd.': 'Återställningsnyckeln kopierad.',
  'Identiteit herstellen': 'Återställ identitet',
  'Plak de herstelsleutel die je eerder bewaarde. Dit apparaat neemt dan dezelfde identiteit over — mede-auteurs die je eerder verifieerden herkennen je vingerafdruk weer.':
      'Klistra in återställningsnyckeln du sparade tidigare. Den här enheten övertar då samma identitet — medförfattare som tidigare verifierade dig känner igen ditt fingeravtryck igen.',
  'Identiteit & herstelsleutel': 'Identitet och återställningsnyckel',
  'Je apparaat heeft een eigen samenwerkingsidentiteit — dat is wat mede-auteurs verifiëren. Bewaar de herstelsleutel om diezelfde identiteit later op een ander apparaat terug te zetten; zonder die sleutel begin je daar opnieuw.':
      'Din enhet har en egen samarbetsidentitet — det är den som medförfattare verifierar. Spara återställningsnyckeln för att senare återställa samma identitet på en annan enhet; utan den nyckeln börjar du om där.',
  'Herstelsleutel tonen': 'Visa återställningsnyckel',
  'De herstelsleutel kon niet worden gelezen.':
      'Det gick inte att läsa återställningsnyckeln.',
  'Identiteit hersteld.': 'Identitet återställd.',
  'Deze herstelsleutel klopt niet — controleer of je hem volledig en foutloos hebt overgenomen.':
      'Den här återställningsnyckeln är inte korrekt — kontrollera att du kopierade den fullständigt och felfritt.',
  'Dit lijkt geen geldige herstelsleutel.':
      'Detta ser inte ut som en giltig återställningsnyckel.',
  'Deze herstelsleutel komt uit een nieuwere versie van OciDeck.':
      'Den här återställningsnyckeln kommer från en nyare version av OciDeck.',
  'Afbeeldingsrechten': 'Bildrättigheter',
  'Afbeeldingsrechten controleren…': 'Kontrollera bildrättigheter...',
  'Afdoening': 'Lösning',
  'Afdoening vastleggen': 'Rekorduppgörelse',
  'Bijvoorbeeld een factuur-, licentie- of dossierverwijzing':
      'Till exempel en faktura, licens eller filreferens',
  'Controleert afbeeldingen lokaal op mogelijke auteursrechtelijke risico’s. Nieuwe repositoryafbeeldingen en de volledige assetpool kunnen worden gescand; een beheerder handelt waarschuwingen af. Dit is een signalering, geen juridisch oordeel, en er worden geen afbeeldingen naar derden gestuurd.':
      'Kontrollerar bilder lokalt för eventuella upphovsrättsrisker. Nya arkivbilder och hela tillgångspoolen kan skannas; en administratör hanterar varningar. Detta är en varning, inte en juridisk åsikt, och inga bilder kommer att skickas till tredje part.',
  'De afdoening kon niet worden opgeslagen. Scan opnieuw en probeer het nogmaals.':
      'Bosättningen gick inte att rädda. Skanna om och försök igen.',
  'Dit is een technische signalering, geen juridisch oordeel. Een beheerder beoordeelt de aanwijzingen.':
      'Detta är en teknisk varning, inte en juridisk åsikt. En administratör granskar instruktionerna.',
  'Geen openstaande aanwijzingen.': 'Inga enastående ledtrådar.',
  'Geldige rechten aangetoond': 'Giltiga rättigheter uppvisade',
  'Mogelijke auteursrechtelijke risico’s': 'Möjliga upphovsrättsliga risker',
  'Niet gebruiken': 'Använd inte',
  'Notitie (optioneel)': 'Obs (valfritt)',
  'Onterechte signalering': 'Felaktig signalering',
  'afbeeldingen vragen om beoordeling': 'bilder kräver granskning',
  'bestanden konden niet veilig worden beoordeeld':
      'filer kunde inte granskas säkert',
  'nieuw gescand': 'nyskannade',
  'Realtime samenwerken': 'Samarbete i realtid',
  'Manieren van verbinden': 'Anslutningssätt',
  'Werk live samen aan een presentatie via een versleuteld doorgeefluik. Standaard uit. De inhoud wordt end-to-end versleuteld met OciDecks eigen sleutels; de server ziet alleen versleutelde gegevens.':
      'Samarbeta live på en presentation via ett krypterat relä. Av som standard. Innehållet krypteras änd-till-änd med OciDecks egna nycklar; servern ser bara krypterade data.',
  'Samenwerken via een Matrix-homeserver als doorgeefluik. Stel het account in bij het tabblad Samenwerken. (Jitsi en XMPP volgen.)':
      'Samarbete via en Matrix-homeserver som relä. Ställ in kontot på fliken Samarbete. (Jitsi och XMPP kommer.)',
  'Chat': 'Chatt',
  'Chat openen': 'Öppna chatten',
  'Chat sluiten': 'Stäng chatten',
  'Bericht…': 'Meddelande…',
  'Versturen': 'Skicka',
  'Nog geen berichten. Zeg iets tegen je mede-auteurs.':
      'Inga meddelanden än. Säg något till dina medförfattare.',
  'Vergelijk de vingerafdruk van elk apparaat via een vertrouwd kanaal — lees hem elkaar voor, of stuur hem langs een weg die je vertrouwt. Komt hij overeen, markeer het apparaat dan als geverifieerd; het blijft dan geverifieerd, ook in een volgende sessie. Wijkt hij af, verbreek dan de samenwerking.':
      'Jämför varje enhets fingeravtryck via en betrodd kanal — läs upp det för varandra, eller skicka det via en väg du litar på. Om det stämmer, markera enheten som verifierad; den förblir då verifierad, även i en senare session. Om det avviker, avbryt samarbetet.',
  'De identiteit van dit apparaat wijkt af van wat je eerder verifieerde — mogelijk zit er iemand tussen. Verbreek de samenwerking, tenzij je zeker weet dat dit apparaat opnieuw is ingesteld.':
      'Den här enhetens identitet avviker från den du verifierade tidigare — någon kan sitta i mitten. Avbryt samarbetet, om du inte är säker på att enheten har konfigurerats om.',
  'Geverifieerd': 'Verifierad',
  'Wijkt af': 'Avviker',
  'Niet geverifieerd': 'Inte verifierad',
  'Markeer als geverifieerd': 'Markera som verifierad',
  'Verificatie intrekken': 'Återkalla verifiering',
  'Toch opnieuw vertrouwen': 'Lita på den igen ändå',
  'Nog niet elk apparaat in deze samenwerking is geverifieerd. Vergelijk de vingerafdrukken om zeker te weten met wie je werkt.':
      'Alla enheter i det här samarbetet är inte verifierade ännu. Jämför fingeravtrycken för att vara säker på vem du arbetar med.',
  'Tabelcel-bewerkingen worden niet gesynchroniseerd naar medebewerkers. De titel en andere velden wel.':
      'Tabelcellsredigeringar synkroniseras inte till medförfattare. Titeln och andra fält gör det.',
  'Verifiëren': 'Verifiera',
  'Deelnemers verifiëren': 'Verifiera deltagare',
  '(dit apparaat)': '(den här enheten)',
  'CVSS': 'CVSS',
  'Dat is geen geldige uitnodigingslink.':
      'Det här är inte en giltig inbjudningslänk.',
  'De Matrix-homeserver is niet bereikbaar.':
      'Matrix-homeservern går inte att nå.',
  'De gastheer reageerde niet op tijd. Controleer de link en of de gastheer nog online is.':
      'Värden svarade inte i tid. Kontrollera länken och om värden fortfarande är online.',
  'Deel deze link met wie je mee wil laten werken. Wie de link heeft, kan de sessie binnenkomen — deel hem dus alleen met mensen die je vertrouwt. De inhoud blijft end-to-end versleuteld; de homeserver ziet alleen versleutelde gegevens.':
      'Dela den här länken med dem du vill samarbeta med. Alla som har länken kan gå in i sessionen — dela den därför bara med personer du litar på. Innehållet förblir änd-till-änd-krypterat; homeservern ser bara krypterade data.',
  'Deelnemen': 'Gå med',
  'Deelnemen via een link': 'Gå med via en länk',
  'Je Matrix-account wordt geweigerd — controleer het access-token bij Instellingen.':
      'Ditt Matrix-konto avvisas — kontrollera åtkomsttoken i Inställningar.',
  'Je doet nu live mee aan de samenwerking.': 'Du samarbetar nu live.',
  'Nodig mede-auteurs uit': 'Bjud in medförfattare',
  'Open eerst een presentatie om aan samen te werken.':
      'Öppna först en presentation för att samarbeta.',
  'Plak de uitnodigingslink die de gastheer je stuurde. Je opent daarmee dezelfde presentatie en werkt live mee.':
      'Klistra in inbjudningslänken som värden skickade till dig. Då öppnar du samma presentation och samarbetar live.',
  'Realtime samenwerken is mislukt.': 'Samarbete i realtid misslyckades.',
  'Realtime samenwerken starten': 'Starta samarbete i realtid',
  'Stel eerst een Matrix-account in bij Instellingen → Samenwerken.':
      'Ställ först in ett Matrix-konto under Inställningar → Samarbete.',
  'Uitnodigingslink': 'Inbjudningslänk',
  'Uitnodigingslink gekopieerd.': 'Inbjudningslänk kopierad.',
  'Uitnodigingslink kopiëren': 'Kopiera inbjudningslänk',
  'Verbinden met de samenwerking…': 'Ansluter till samarbetet…',
  'Access-token': 'Åtkomsttoken',
  'Apparaat-id': 'Enhets-id',
  'Gebruikers-id': 'Användar-id',
  'De homeserver gaf een fout. Probeer het later opnieuw.':
      'Homeservern returnerade ett fel. Försök igen senare.',
  'De homeserver is niet bereikbaar, of het certificaat wordt niet vertrouwd.':
      'Homeservern går inte att nå, eller så är certifikatet inte betrott.',
  'De homeserver stuurt door naar een ander adres — dat wordt om veiligheidsredenen niet gevolgd. Vul het uiteindelijke adres rechtstreeks in.':
      'Homeservern omdirigerar till en annan adress — av säkerhetsskäl följs det inte. Ange den slutliga adressen direkt.',
  'De homeserver vraagt om even te wachten. Probeer het zo opnieuw.':
      'Homeservern ber dig vänta ett ögonblick. Försök igen strax.',
  'De homeserver weigert dit token.': 'Homeservern avvisar detta token.',
  'Dit adres antwoordt niet als een Matrix-homeserver. Klopt de URL?':
      'Den här adressen svarar inte som en Matrix-homeserver. Stämmer URL:en?',
  'Een homeserver moet https zijn: het access-token reist bij elk verzoek mee.':
      'En homeserver måste vara https: åtkomsttoken följer med varje begäran.',
  'Het access-token wordt geweigerd — controleer of je het goed hebt overgenomen en of het niet is ingetrokken.':
      'Åtkomsttoken avvisas — kontrollera att du kopierat det rätt och att det inte återkallats.',
  'Maak een access-token aan in je Matrix-client (bijvoorbeeld in Element onder Alle instellingen → Hulp & info), of op je homeserver. "Verbinding testen" bevestigt het token en vult je gebruikers-id en apparaat-id in.':
      'Skapa en åtkomsttoken i din Matrix-klient (till exempel i Element under Alla inställningar → Hjälp och info) eller på din homeserver. "Testa anslutning" bekräftar token och fyller i ditt användar-id och enhets-id.',
  'Nodig wanneer de homeserver op een privé- of thuisnetwerk draait. Zonder deze vlag weigert de beveiliging een privé-adres.':
      'Behövs när homeservern körs på ett privat nätverk eller hemnätverk. Utan denna flagga avvisar säkerhetskontrollen en privat adress.',
  'Realtime samenwerken (Matrix)': 'Samarbete i realtid (Matrix)',
  'Samenwerken': 'Samarbete',
  'Verbinding gelukt — gebruikers-id en apparaat-id ingevuld':
      'Anslutning lyckades — användar-id och enhets-id ifyllda',
  'Verbinding gelukt, maar de homeserver gaf geen apparaat-id terug — vul die zelf in, anders komen sleutels van mede-auteurs niet aan.':
      'Anslutning lyckades, men homeservern returnerade inget enhets-id — fyll i det själv, annars kommer nycklar från medförfattare inte fram.',
  'Vul een access-token in': 'Ange en åtkomsttoken',
  'Vul een geldige homeserver-URL in': 'Ange en giltig homeserver-URL',
  'Werk live samen aan een presentatie via een Matrix-homeserver als versleutelde doorgeefluik. De inhoud wordt end-to-end versleuteld met OciDecks eigen sleutels; de server ziet alleen versleutelde gegevens. Vul een homeserver en een elders aangemaakt access-token in — OciDeck vraagt nooit om je wachtwoord. Het token wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.':
      'Samarbeta live på en presentation via en Matrix-homeserver som krypterat relä. Innehållet krypteras änd-till-änd med OciDecks egna nycklar; servern ser bara krypterade data. Ange en homeserver och en åtkomsttoken som skapats någon annanstans — OciDeck ber aldrig om ditt lösenord. Token lagras krypterad i nyckelringen, inte tillsammans med övriga inställningar.',
  'wordt door de test ingevuld': 'fylls i av testet',
  'Meer documentatie op de repository': 'Mer dokumentation i repositoryt',
  'De volledige documentatie — ook architectuur, bouw, broncode en ontwerp — staat op de repository.':
      'Den fullständiga dokumentationen — inklusive arkitektur, bygge, källkod och design — finns i repositoryt.',
  'Zoeken in document': 'Sök i dokument',
  'Zoeken in dit document…': 'Sök i det här dokumentet…',
  'Geen treffers': 'Inga träffar',
  'Vorige treffer': 'Föregående träff',
  'Volgende treffer': 'Nästa träff',
  'Zoeken sluiten': 'Stäng sökning',
  'Alleen de eigenaar bewaart het deck in een gedeelde sessie; jouw wijzigingen blijven in de sessie tot de eigenaar opslaat.':
      'Endast ägaren sparar decket i en delad session; dina ändringar stannar i sessionen tills ägaren sparar.',
  'De eigenaar is weg — jij houdt de samenwerking nu gaande; jouw wijzigingen worden pas bewaard als de eigenaar terugkomt.':
      'Ägaren har gått — nu är det du som håller samarbetet igång; dina ändringar sparas först när ägaren kommer tillbaka.',
  'De eigenaar is terug en neemt de samenwerking weer over.':
      'Ägaren är tillbaka och tar över samarbetet igen.',
  'Samenwerking starten': 'Starta samarbete',
  'Deelnemen aan samenwerking': 'Gå med i samarbete',
  'Samenwerking verlaten': 'Lämna samarbete',
  'Samenwerking gestart.': 'Samarbete startat.',
  'Deelgenomen aan de samenwerking.': 'Gick med i samarbetet.',
  'Nog geen samenwerking gestart voor dit deck.':
      'Inget samarbete har startats för det här decket ännu.',
  'Samenwerking mislukt.': 'Samarbete misslyckades.',
  'Samenwerking beëindigd.': 'Samarbete avslutat.',
  'Authentieke cockpit': 'Autentisk cockpit',
  'Klassiek': 'Klassisk',
  'Bord': 'Anslagstavla',
  'Projectcharter': 'Projektcharta',
  'CTQ-boom': 'CTQ-träd',
  'Visgraat (Ishikawa)': 'Fiskbensdiagram (Ishikawa)',
  'Proceskaart': 'Processkarta',
  'Impact / Inspanning': 'Effekt / Insats',
  'Vier lijsten — één per kwadrant.': 'Fyra listor — en per kvadrant.',
  'Eén blad, zeven vakken — kort en leesbaar houden.':
      'En sida, sju rutor — håll varje kort och läsbar.',
  'RPN = S×O×D wordt berekend — typ hem niet zelf.':
      'RPN = S×O×D beräknas — skriv inte in det själv.',
  'Eén R per rij.': 'Ett R per rad.',
  'Vul rechts naar links in — begin bij de klant.':
      'Fyll i höger-till-vänster — börja med kunden.',
  'Kolommen zijn statussen; kaarten zijn taken.':
      'Kolumner är statusar; kort är uppgifter.',
  'Scope en succescriteria eerst — daarna pas het hoe.':
      'Scope och framgångskriterier först — hur kommer senare.',
  'Van klantwens (Y) naar meetbare CTQ\'s.':
      'Från kundbehov (Y) till mätbara CTQs.',
  'Vijf niveaus diep — eindig met een X-id.':
      'Fem nivåer djupt — sluta med ett X-id.',
  'Zes M\'s als botten — oorzaken eronder.': 'Sex M som ben — orsaker under.',
  'Stappen als titel :: soort :: kenmerken.':
      'Steg som titel :: typ :: attribut.',
  'Zet de rol in het lane=… kenmerk.': 'Sätt rollen i lane=… attributet.',
  'PT/LT per stap — totalen worden berekend, niet opgeslagen.':
      'PT/LT per steg — totaler beräknas, lagras inte.',
  'Lijst per kwadrant — geen coördinaten tekenen.':
      'En lista per kvadrant — rita inte koordinater.',
  'Intern': 'Intern',
  'Negatief': 'Negativ',
  'Positief': 'Positiv',
  'Weinige inspanning': 'Låg insats',
  'Veel inspanning': 'Hög insats',
  'Lage impact': 'Låg effekt',
  'Hoge impact': 'Hög effekt',
  'Sterktes': 'Styrkor',
  'Zwaktes': 'Svagheter',
  'Kansen': 'Möjligheter',
  'Bedreigingen': 'Hot',
  'Achtergrond': 'Bakgrund',
  'Huidige situatie': 'Nuvarande situation',
  'Oorzaakanalyse': 'Rotorsaksanalys',
  'Tegenmaatregelen': 'Motåtgärder',
  'Opvolging': 'Uppföljning',
  'Bezig': 'Pågående',
  'Probleem': 'Problem',
  'Succescriteria': 'Framgångskriterier',
  'Snelle winst': 'Snabba vinster',
  'Grote projecten': 'Stora projekt',
  'Opvullers': 'Utfyllnader',
  'Ondankbaar': 'Tacklös',
  'Processtap': 'Processsteg',
  'Faalwijze': 'Felfunktion',
  'Oorzaak': 'Orsak',
  'Beheersing': 'Kontroll',
  'Activiteit': 'Aktivitet',
  'Leverancier': 'Leverantör',
  'Klant': 'Kund',
  'Plan': 'Plan',
  'Team': 'Team',
  'Input': 'Input',
  'Output': 'Output',
  'Effect': 'Effekt',
  'Businesscase / investeringsvoorstel': 'Businesscase / investeringsförslag',
  'Aanleiding, opties met kosten en baten, risico\'s en het gevraagde besluit.':
      'Bakgrund, alternativ med kostnader och nytta, risker och det begärda beslutet.',
  'Begroting / budgetpresentatie': 'Budgetpresentation',
  'Uitgangspunten, posten met vergelijking, keuzeruimte, risico\'s en beslispunten.':
      'Utgångspunkter, poster med jämförelse, valutrymme, risker och beslutspunkter.',
  'Besluitvormend overleg': 'Beslutsmöte',
  'Agenda, toelichting per punt, besluitenlijst en acties met eigenaar.':
      'Dagordning, förklaring per punkt, beslutslista och åtgärder med ägare.',
  'Ledenvergadering (ALV)': 'Årsmöte (föreningsstämma)',
  'Agenda, jaarverslag, kascommissie, begroting en stemmingen voor vereniging of VvE.':
      'Dagordning, årsberättelse, revisorer, budget och omröstningar för förening eller bostadsrättsförening.',
  'Ouderavond / informatieavond': 'Föräldramöte / informationskväll',
  'Jaarprogramma, aanpak, praktische afspraken en hoe ouders kunnen helpen.':
      'Årsprogram, arbetssätt, praktiska överenskommelser och hur föräldrar kan hjälpa till.',
  'Familiegesprek zorg en mantelzorg':
      'Familjesamtal om vård och anhörigomsorg',
  'Scenario\'s, wensen, taakverdeling en afspraken voor een zwaar familiegesprek.':
      'Scenarier, önskemål, uppgiftsfördelning och överenskommelser inför ett svårt familjesamtal.',
  'Raads- / collegevoorstel': 'Förslag till fullmäktige / styrelse',
  'Aanleiding, beslispunten, argumenten én kanttekeningen, dekking en vervolg.':
      'Bakgrund, beslutspunkter, argument och förbehåll, finansiering och nästa steg.',
  'Bewonersavond / participatiebijeenkomst': 'Boendemöte / medborgardialog',
  'Wat vaststaat en wat openligt, cijfers, reactiemogelijkheden en vervolg.':
      'Vad som är bestämt och vad som är öppet, siffror, möjligheter att reagera och nästa steg.',
  'Sprint review / demo': 'Sprint review / demo',
  'Sprintdoel, opgeleverd werk, demo, metrieken en vooruitblik.':
      'Sprintmål, levererat arbete, demo, mätetal och utblick.',
  'Brandweerbriefing (inzet en oefening)':
      'Briefing för räddningstjänsten (insats och övning)',
  'Object, bereikbaarheid, gevaren, kwadranten, waterwinning en taakverdeling.':
      'Objekt, framkomlighet, faror, kvadranter, vattenförsörjning och uppgiftsfördelning.',
  'Adviesaanvraag OR / medezeggenschap':
      'Begäran om yttrande från personalrådet',
  'Voorgenomen besluit, beweegredenen, personele gevolgen en het adviestraject.':
      'Avsett beslut, motiv, konsekvenser för personalen och samrådsprocessen.',
  'Stagepresentatie': 'Praktikpresentation',
  'Bedrijf, opdracht, aanpak, resultaat, leerdoelen en reflectie.':
      'Företag, uppdrag, arbetssätt, resultat, lärandemål och reflektion.',
  'Debriefing / after-action review': 'Debriefing / utvärdering efter insats',
  'Wat was gepland, wat gebeurde er, waarom — en welke afspraken maken we.':
      'Vad som var planerat, vad som hände, varför — och vilka överenskommelser vi gör.',
  'Threat modeling-sessie': 'Threat modeling-session',
  'Scope, datastromen, vertrouwensgrenzen, dreigingen per STRIDE-categorie en maatregelen.':
      'Omfattning, dataflöden, förtroendegränser, hot per STRIDE-kategori och åtgärder.',
  'Casuïstiekbespreking sociaal domein':
      'Ärendegenomgång inom det sociala området',
  'Geanonimiseerde casus: leefdomeinen, veiligheid, wettelijk kader en regie.':
      'Anonymiserat ärende: livsområden, säkerhet, rättslig ram och samordning.',
  'Gesprek voorbereiden': 'Förbered ett samtal',
  'Doel, de ander, opbouw, vragen en afspraken voor elk gesprek dat je goed wilt voorbereiden.':
      'Mål, den andra parten, upplägg, frågor och överenskommelser för varje samtal du vill förbereda väl.',
  'Cruciaal gesprek voorbereiden': 'Förbered ett avgörande samtal',
  'Hoge belangen en sterke emoties, volgens de aanpak voor cruciale gesprekken.':
      'Mycket på spel och starka känslor, enligt metoden för avgörande samtal.',
  'Vluchtdebriefing': 'Flygdebriefing',
  'Zelfevaluatie, verloop per fase, TEM-terugblik en leerpunten na een vlucht of les.':
      'Självutvärdering, förlopp per fas, TEM-återblick och lärdomar efter en flygning eller lektion.',
  'Passagiersbriefing (kleine luchtvaart)': 'Passagerarbriefing (allmänflyg)',
  'Gordels, deuren, noodprocedures en afspraken aan boord vóór het taxiën.':
      'Bälten, dörrar, nödprocedurer och överenskommelser ombord före taxning.',
  'Vat de huidige stand, gebruikte metingen en belangrijkste aandachtspunten samen.':
      'En bred men saklig förvaltningsöversikt med spårbara mätmoment.',
  'Laat zien waar de meeste en minste findings zijn gevonden; ontbrekende metingen staan apart.':
      'Rangordnas utan totalpoäng och visar saknade mått separat.',
  'Laat zien hoe aantallen findings veranderden en welke organisaties daaraan bijdroegen.':
      'Visar allvarlighetsräkningar, bidragsgivare och överförda mätningar per ögonblick.',
  'Laat zien welke soorten problemen bij de meeste organisaties en systemen voorkomen.':
      'Organiserar hitta typer efter berörda organisationer, system och observationer.',
  'Laat per organisatie zien hoeveel findings critical of high zijn.':
      'Visar kritiska/höga siffror utan någon uttänkt vägning.',
  'Laat per control zien welk deel voldoet, maar alleen als het totaal bekend is.':
      'Visar täljare, nämnare och endast pålitliga procentsatser.',
  'Bundelt de aanbevelingen uit OpenKAT zonder er zelf prioriteit aan te geven.':
      'Grupperar bokstavliga rekommendationer från OpenKAT utan egen prioritet.',
  'Laat zien welke findings nieuw, terug of niet meer gezien zijn.':
      'Utmärker nytt, nytt och inte längre observerat.',
  'Laat zien welke findings het langst openstaan als de begindatum bekend is.':
      'Använder endast tillförlitliga första observationsdatum.',
  'Laat zien op welke systemen de meeste en ernstigste findings staan.':
      'Rangordnar system med separata allvarlighetsräknare.',
  'Laat per systeem zien of het aantal findings steeg of daalde.':
      'Visar individuella deltavärden utan viktad poäng.',
  'Vergelijkt controls alleen als beide metingen dezelfde reikwijdte hebben.':
      'Jämför täljare och nämnare med bevisligen jämförbar täckning.',
  'Geeft de systemen, hostnamen en IP-adressen uit de gekozen meting weer.':
      'Inventerar källbeprövade system, värdnamn och IP-adresser.',
  'Laat alleen monitoringveranderingen zien die de bron bewijst.':
      'Visar endast explicit bevisade övervakningsmutationer.',
  'Laat zien bij welke organisaties en systemen deze CVE is aangetroffen.':
      'Visar organisationer och system runt en pålitlig CVE-länk.',
  'Laat zien welke CVE’s bij de meeste organisaties en systemen voorkomen.':
      'Rangordnar CVE:er med explicit deduplicering.',
  'Laat zien welke CVE’s nieuw, terug of niet meer gezien zijn.':
      'Skiljer på nya, nya och inte längre observerade CVE.',
  'Toont de gebruikte meetdatums, bronbestanden en technische bronkenmerken.':
      'Justerar nyckeldatum, källfiler, adaptrar och källhashar.',
  'Vergelijk organisaties en breng portfolio-aandachtspunten in beeld.':
      'Jämför organisationer och identifiera portföljpunkter av intresse.',
  'Bekijk de actuele stand of aantoonbare veranderingen bij één organisatie.':
      'Visa aktuell status eller påvisbara ändringar i en organisation.',
  'Onderzoek betrouwbare CVE-koppelingen in de gekozen metingen.':
      'Undersök tillförlitliga CVE-länkar i de valda mätningarna.',
  'Leg vast welke metingen en bronbestanden het rapport werkelijk gebruikt.':
      'Registrera vilka mätningar och källfiler som rapporten faktiskt använder.',
  'Wat is het managementbeeld over de gekozen organisaties?':
      'Vilken är ledningens syn på de valda organisationerna?',
  'Waar worden de meeste en minste findings waargenomen?':
      'Var observeras flest och minst fynd?',
  'Hoe ontwikkelt het portfolio zich over de tijd?':
      'Hur utvecklas portföljen över tid?',
  'Welke problemen komen bij de meeste organisaties voor?':
      'Vilka problem uppstår i de flesta organisationer?',
  'Waar concentreren de ernstigste findings zich?':
      'Var är de allvarligaste fynden koncentrerade?',
  'Welke controls lopen achter?': 'Vilka kontroller släpar efter?',
  'Welke maatregelen adviseert OpenKAT het vaakst?':
      'Vilka åtgärder rekommenderar OpenKAT oftast?',
  'Hoe staat deze organisatie er nu voor?':
      'Vad är den aktuella statusen för denna organisation?',
  'Wat veranderde er sinds de vorige meting?':
      'Vad har förändrats sedan föregående mätning?',
  'Welke findings zijn nieuw of niet meer waargenomen?':
      'Vilka fynd är nya eller observeras inte längre?',
  'Welke findings staan het langst open?': 'Vilka fynd har varit öppna längst?',
  'Op welke systemen worden de meeste findings waargenomen?':
      'På vilka system observeras flest fynd?',
  'Welke systemen verbeterden of verslechterden?':
      'Vilka system har förbättrats eller försämrats?',
  'Welke controls verbeterden of verslechterden?':
      'Vilka kontroller förbättrades eller försämrades?',
  'Welke systemen zijn in de metingen opgenomen?':
      'Vilka system ingår i mätningarna?',
  'Welke assets zijn aantoonbaar in monitoring?':
      'Vilka tillgångar är påvisbara vid övervakning?',
  'Welke monitoringstatussen veranderden?':
      'Vilka övervakningsstatusar har ändrats?',
  'Wie is geraakt door deze CVE?': 'Vem påverkas av denna CVE?',
  'Welke CVE’s raken de meeste organisaties?':
      'Vilka CVEs påverkar de flesta organisationer?',
  'Welke CVE’s zijn nieuw of niet meer waargenomen?':
      'Vilka CVE är nya eller observeras inte längre?',
  'Welke meetgegevens ontbreken of zijn verouderd?':
      'Vilka mätdata saknas eller är inaktuella?',
  'Op welke gegevens is dit rapport gebaseerd?':
      'Vilken data är den här rapporten baserad på?',
  'Een gericht actueel beeld van één organisatie en haar meetdatum.':
      'En riktad aktuell bild av en organisation och dess mätningsdatum.',
  'Vergelijkt twee gekozen meetmomenten binnen één organisatie.':
      'Jämför två valda mätmoment inom en organisation.',
  'Scheidt gemonitord, niet gemonitord en onbekend.':
      'Separerar övervakade, oövervakade och okända.',
  'Toont ontbrekende, verouderde en werkelijk gebruikte metingen.':
      'Visar saknade, föråldrade och faktiskt använda mått.',
  'Nog niet beschikbaar: de bron bewijst geen monitoringstatus voor alle assets.':
      'Inte tillgänglig ännu: källan bevisar inte övervakningsstatus för alla tillgångar.',
  'Nog niet beschikbaar: niet iedere finding heeft een betrouwbare eerste waarnemingsdatum.':
      'Inte tillgängligt ännu: inte alla fynd har ett tillförlitligt första observationsdatum.',
  'Nog niet beschikbaar: de bron bewijst geen stabiele identiteit voor alle findings.':
      'Inte tillgänglig ännu: källan bevisar inte en stabil identitet för alla fynd.',
  'Nog niet beschikbaar: vergelijkbare meetdekking is niet aangetoond.':
      'Ej tillgängligt ännu: jämförbar mättäckning har inte visats.',
  'Nog niet beschikbaar: betrouwbare controlnoemers ontbreken.':
      'Inte tillgängligt ännu: pålitliga kontrollnämnare saknas.',
  'Nog niet beschikbaar: stabiele assetidentiteit is niet aangetoond.':
      'Inte tillgänglig ännu: stabil tillgångsidentitet har inte visats.',
  'Dit rapport ondersteunt de gekozen organisatiescope niet.':
      'Denna rapport stöder inte den valda organisatoriska omfattningen.',
  'De gekozen bron bevat niet genoeg betrouwbare gegevens voor dit rapport.':
      'Den valda källan innehåller inte tillräckligt med tillförlitlig data för den här rapporten.',
  'Kerncijfers en gemeten bereik': 'Nyckeltal och uppmätt räckvidd',
  'Organisaties vergelijken': 'Jämför organisationer',
  'Concentratie van critical/high findings':
      'Koncentration av kritiska/höga fynd',
  'Portfolioverloop per meetmoment': 'Portföljöversikt per mätmoment',
  'Meest voorkomende findingtypen': 'De vanligaste fyndtyperna',
  'Bron- en meetverantwoording': 'Käll- och mätansvar',
  'Nieuwe en niet meer waargenomen findings':
      'Nya och inte längre observerade fynd',
  'Langst waargenomen findings': 'Längsta observerade fynd',
  'Systemen met de meeste findings': 'System med flest fynd',
  'Veranderingen per systeem': 'Ändringar per system',
  'Blootstelling aan één CVE': 'Exponering för en CVE',
  'CVE’s over organisaties': 'CVEs om organisationer',
  'Nieuwe en niet meer waargenomen CVE’s':
      'Nya och inte längre observerade CVEs',
  'Controldekking': 'Kontrolltäckning',
  'Controlveranderingen': 'Kontrollförändringar',
  'Aanbevelingen uit OpenKAT': 'Rekommendationer från OpenKAT',
  'Assetinventaris': 'Tillgångsinventering',
  'Monitoringdekking': 'Övervakning av täckning',
  'Actueel organisatiebeeld': 'Aktuell organisationsbild',
  'Kies eerst het onderwerp en daarna de vraag die het rapport moet beantwoorden.':
      'Välj först ämnet och sedan frågan som rapporten ska besvara.',
  'Onderwerp': 'Ämne',
  'Welk rapport beantwoordt uw vraag?': 'Vilken rapport svarar på din fråga?',
  'Meer rapportvragen': 'Fler rapportfrågor',
  'Kwetsbare systemen': 'Sårbara system',
  'Kritiek/hoog': 'Kritisk/hög',
  'Dit bestaande rapport kan niet veilig worden bijgewerkt. Maak het rapport als nieuw; het bestaande deck blijft ongewijzigd.':
      'Den här befintliga rapporten kan inte uppdateras på ett säkert sätt. Skapa rapporten som ny; det befintliga däcket förblir oförändrat.',
  '{reports} rapportages gevonden voor {organizations} organisaties. De metingen lopen van {firstDate} tot en met {lastDate}. {skipped} bestanden zijn overgeslagen.':
      '{reports} rapporter hittades för {organizations} organisationer. Mätningarna sträcker sig från {firstDate} till och med {lastDate}. {skipped} filer hoppades över.',
  'Dubbel bestand overgeslagen': 'Dubblettfil hoppades över',
  'Conflicterende meting overgeslagen': 'Motstridig mätning hoppades över',
  'Geen ondersteunde OpenKAT-rapportage': 'OpenKAT-rapport som inte stöds',
  'Bestand kon niet worden gelezen': 'Filen kunde inte läsas',
  'Aanbevolen': 'Rekommenderad',
  'Alleen wat nodig is': 'Bara det som är nödvändigt',
  'Alles blijft op dit apparaat': 'Allt finns kvar på den här enheten',
  'Als nieuw rapport maken': 'Skapa som ny rapport',
  'Andere map kiezen': 'Välj en annan mapp',
  'Bekijk importverslag': 'Visa importrapport',
  'Bekijk verslag': 'Visa rapport',
  'Bijvoorbeeld CVE-2026-12345': 'Till exempel CVE-2026-12345',
  'Bruikbaar': 'Användbar',
  'CVE zoeken': 'CVE-sökning',
  'Critical/high': 'Kritisk/hög',
  'De gekozen rapportages bevatten niet genoeg betrouwbare gegevens voor dit onderdeel.':
      'De valda rapporterna innehåller inte tillräckligt med tillförlitlig data för denna del.',
  'De inhoud verschijnt zodra alle noodzakelijke keuzes zijn gemaakt.':
      'Innehållet kommer att visas när alla nödvändiga val har gjorts.',
  'De meetdekking verschilt tussen de gekozen meetmomenten; veranderingen zijn daardoor beperkt vergelijkbaar.':
      'Mättäckningen skiljer sig mellan de valda mätmomenten; förändringar är därför endast i begränsad omfattning jämförbara.',
  'Dekking en actualiteit van metingen': 'Täckning och aktualitet av mätningar',
  'Deze CVE is niet aangetroffen in de gekozen metingen.':
      'Denna CVE hittades inte i de valda mätningarna.',
  'Deze map bevat geen bruikbare rapportages':
      'Den här mappen innehåller inga användbara rapporter',
  'Deze selectie bevat te veel gegevens om veilig in één rapport te verwerken.':
      'Det här urvalet innehåller för mycket data för att säkert inkludera i en rapport.',
  'Dit onderdeel kan niet volledig uit de gekozen rapportages worden opgebouwd.':
      'Det här avsnittet kan inte byggas helt utifrån de valda rapporterna.',
  'Dit rapport bevat': 'Denna rapport innehåller',
  'Een of meer metingen zijn ouder dan de gekozen actualiteitsgrens.':
      'En eller flera mätningar är äldre än den valda tidsgränsen.',
  'Eerdere bruikbare meting': 'Tidigare användbar mätning',
  'Engels': 'engelska',
  'Er zijn geen bruikbare metingen gevonden.': 'Inga användbara mått hittades.',
  'Feitelijke gegevens': 'Faktadata',
  'Geen bruikbare meetdatum': 'Inget användbart mätdatum',
  'Gegenereerde dia’s worden vernieuwd. Uw eigen dia’s en kopieën blijven behouden.':
      'Genererade bilder uppdateras. Dina egna bilder och kopior behålls.',
  'Getroffen systemen': 'Berörda system',
  'Het rapport kon niet worden gemaakt. Uw keuzes zijn behouden; controleer de waarschuwingen en probeer het opnieuw.':
      'Rapporten kunde inte skapas. Dina val är bevarade; kontrollera varningarna och försök igen.',
  'Import': 'Importera',
  'Importverslag bekijken': 'Visa importrapport',
  'Kerncijfers en aandachtspunten': 'Nyckeltal och intressepunkter',
  'Keuzes wijzigen…': 'Ändra val...',
  'Kies de map waarin OpenKAT de rapportages heeft geplaatst. OciDeck leest deze map alleen; er wordt niets gewijzigd of verstuurd.':
      'Välj i vilken mapp OpenKAT har placerat rapporterna. OciDeck läser bara denna mapp; ingenting ändras eller skickas.',
  'Kies een CVE die in de rapportages is aangetroffen.':
      'Välj en CVE som finns i rapporterna.',
  'Laatste bruikbare meting': 'Sista användbara mått',
  'Live voorvertoning van de rapportopbouw':
      'Live förhandsvisning av rapportstrukturen',
  'Meer instellingen': 'Fler inställningar',
  'Nederlands': 'holländska',
  'Niet iedere gekozen organisatie heeft een meting voor deze periode.':
      'Inte varje vald organisation har ett mått för denna period.',
  'Nog niet beschikbaar: deze rapportages bevatten geen betrouwbare CVE-nummers.':
      'Inte tillgänglig ännu: dessa rapporter innehåller inte tillförlitliga CVE-nummer.',
  'OciDeck gebruikt dezelfde bron en keuzes en neemt de nieuwste geschikte metingen. Uw eigen dia’s en kopieën blijven behouden.':
      'OciDeck använder samma källa och val och tar de senaste lämpliga mätningarna. Dina egna bilder och kopior behålls.',
  'OciDeck kon geen bruikbare OpenKAT-metingen vinden. Kies een andere map of bekijk het importverslag om te zien welke bestanden zijn overgeslagen.':
      'OciDeck kunde inte hitta några användbara OpenKAT-mätningar. Välj en annan mapp eller visa importrapporten för att se vilka filer som hoppades över.',
  'OpenKAT-importverslag': 'OpenKAT-importrapport',
  'OpenKAT-rapport': 'OpenKAT-rapport',
  'OpenKAT-rapport bijwerken': 'Uppdatera OpenKAT-rapport',
  'OpenKAT-rapport bijwerken…': 'Uppdatera OpenKAT-rapport...',
  'OpenKAT-rapport kon niet worden gemaakt.':
      'Det gick inte att skapa OpenKAT-rapporten.',
  'OpenKAT-rapport maken': 'Skapa OpenKAT-rapport',
  'OpenKAT-rapport maken…': 'Skapa OpenKAT-rapport...',
  'Organisaties': 'Organisationer',
  'Organisaties kiezen': 'Att välja organisationer',
  'Rapport bijgewerkt. Uw eigen dia’s zijn behouden.':
      'Rapport uppdaterad. Dina egna bilder har behållits.',
  'Rapport bijwerken': 'Uppdatera rapport',
  'Rapport gemaakt.': 'Rapport skapad.',
  'Rapport maken': 'Skapa rapport',
  'Rapportages controleren…': 'Kolla rapporter...',
  'Rapportages voorbereiden': 'Förbered rapporter',
  'Rapporttitel': 'Rapportens titel',
  'Stap': 'Steg',
  'Taal': 'Språk',
  'Terug': 'Tillbaka',
  'Veranderingen in monitoring': 'Förändringar i övervakningen',
  'Voor een of meer organisaties ontbreekt een bruikbare eerdere meting.':
      'En användbar tidigare mätning saknas för en eller flera organisationer.',
  'Voor een of meer organisaties ontbreekt een bruikbare huidige meting.':
      'En användbar strömmätning saknas för en eller flera organisationer.',
  'Voor een vergelijking zijn twee meetmomenten nodig. Er is nu één meting gevonden.':
      'Två mätmoment krävs för en jämförelse. En mätning har nu hittats.',
  'Waar staan de OpenKAT-rapportages?': 'Var finns OpenKAT-rapporterna?',
  'Wat veranderde er bij één organisatie?':
      'Vad förändrades i en organisation?',
  'Wat wilt u laten zien?': 'Vad vill du visa?',
  'Welke organisaties vragen aandacht?':
      'Vilka organisationer kräver uppmärksamhet?',
  'Werkelijke meetdatums': 'Faktiska mätdatum',
  'Wie is geraakt door een CVE?': 'Vem påverkas av en CVE?',
  'Zijn de metingen compleet en actueel?':
      'Är mätningarna kompletta och uppdaterade?',
  'bruikbaar': 'användbar',
  'metingen': 'mätningar',
  'organisaties': 'organisationer',
  'rapportages gebruikt': 'rapporter som används',
  'systemen': 'system',
  'Nog geen specificatielimiet': 'Ingen specifikationsgräns ännu',
  'USL (bovengrens)': 'USL (övre gräns)',
  'LSL (ondergrens)': 'LSL (nedre gräns)',
  'Optionele Y-01-velden': 'Valfria Y-01-fält',
  'Procesdoel (target)': 'Processmål (target)',
  'Specificatielimieten van Y-01 (deck)': 'Y-01-specifikationsgränser (deck)',
  'Dit deck heeft Y-01-limieten. Schakel bovenstaande schakelaar in om die te gebruiken in plaats van lokale waarden.':
      'Detta deck har Y-01-gränser. Slå på växeln ovan för att använda dem i stället för lokala värden.',
  'USL (bovengrens, optioneel)': 'USL (övre gräns, valfritt)',
  'LSL (ondergrens, optioneel)': 'LSL (nedre gräns, valfritt)',
  'Procesdoel (optioneel)': 'Processmål (valfritt)',
  'Fasepoort': 'Fasgrind',
  'Berekenen': 'Beräkna',
  'Gegevens': 'Data',
  'Hellingscoëfficiënt': 'Lutning',
  'Hypothesetoets': 'Hypotestest',
  'Hypothesetoets…': 'Hypotestest…',
  'Hypothetisch gemiddelde': 'Hypotetiskt medelvärde',
  'Lineaire regressie': 'Linjär regression',
  'Regressie…': 'Regression…',
  'Meetdata': 'Mätdata',
  'Toets': 'Test',
  'Tolerantie (optioneel)': 'Tolerans (valfritt)',
  'Eénsteeks t-toets': 'Enstickprov-t-test',
  'Twee-steeks t-toets (Welch)': 'Två stickprov-t-test (Welch)',
  'Één kolom getallen (minimaal 2 waarnemingen).':
      'En kolumn med tal (minst 2 observationer).',
  'Twee kolommen gescheiden door een lege regel (minimaal 2 per groep).':
      'Två kolumner åtskilda av en tom rad (minst 2 per grupp).',
  'Meerdere groepen, elke groep een kolom, gescheiden door een lege regel (minimaal 2 groepen, 2 waarnemingen per groep).':
      'Flera grupper, varje grupp en kolumn, åtskilda av en tom rad (minst 2 grupper, 2 observationer per grupp).',
  'Plak Part, Operator en Value (tab of komma). Herhaal rijen voor replicaten. Minimaal 2 parts, 2 operators, 2 metingen per cel.':
      'Klistra in Part, Operator och Value (tabb eller komma). Upprepa rader för replikat. Minst 2 parts, 2 operatörer, 2 mätningar per cell.',
  'Plak X en Y (één getal per regel). Minimaal 3 paren; de engine weigert bij te weinig waarnemingen.':
      'Klistra in X och Y (ett tal per rad). Minst 3 par; motorn vägrar vid för få observationer.',
  'Part × Operator interaction pooled into repeatability':
      'Part × Operator-interaktion sammanslagen med repeterbarhet',
  'Part × Operator interaction kept separate':
      'Part × Operator-interaktion hållen separat',
  'Te weinig gegevens voor een probability plot':
      'För lite data för ett sannolikhetsdiagram',
  'Met dank aan': 'Med tack',
  'Automatisch oplosbare problemen aangepakt. Wat overblijft vraagt om een keuze.':
      'Problemen som kunde åtgärdas automatiskt är klara. Det som återstår kräver ett val.',
  'Niets dat zich vanzelf laat oplossen — dit vraagt om een keuze.':
      'Inget som löser sig av sig självt — det här kräver ett val.',
  'Probleem op deze dia oplossen': 'Åtgärda problemet på den här bilden',
  'Deze dia is geredigeerd en wordt niet aangepast.':
      'Den här bilden är maskad och ändras inte.',
  'Geen probleem om hier op te lossen.':
      'Det finns inget problem att åtgärda här.',
  'SBAR-overdracht': 'SBAR-överlämning',
  '(A)MIST traumaoverdracht': '(A)MIST-traumaöverlämning',
  'Multidisciplinair overleg (MDO)': 'Multidisciplinärt teammöte (MDT)',
  'Chirurgische veiligheidscheck (WHO)':
      'Checklista för kirurgisk säkerhet (WHO)',
  'Verpleegkundige dienstoverdracht': 'Omvårdnadsöverlämning vid skiftbyte',
  'Inwerkplan (30-60-90 dagen)': 'Introduktionsplan (30-60-90 dagar)',
  'Eerste dag / introductie': 'Första dagen / introduktion',
  'Buddy- / mentorafspraak': 'Buddy-/mentorplan',
  'Uitdiensttreding / offboarding': 'Offboarding / avslut',
  'IMSAFE fit-to-fly-check': 'IMSAFE kontroll av flygduglighet',
  'Crew- / departurebriefing': 'Besättnings-/avgångsbriefing',
  'Voorvalmelding (just culture)': 'Händelserapport (just culture)',
  'Toolbox / LMRA veiligheidscheck': 'Toolbox / LMRA-säkerhetskontroll',
  'Evenement- en crowd-safetybriefing': 'Evenemangs- och crowd-safety-briefing',
  'Ontruimings- en BHV-oefening': 'Utrymnings- och BHV-övning',
  'Werkvergunning (permit to work)': 'Arbetstillstånd (permit to work)',
  'METHANE grootschalig-incidentmelding':
      'METHANE-rapport om storskadehändelse',
  'GRIP-opschaling': 'GRIP-upptrappning',
  'Maritieme passage-/brugbriefing': 'Maritim passage-/bryggbriefing',
  'Draag een patiënt of situatie gestructureerd over: Situatie, Achtergrond, Beoordeling en Aanbeveling.':
      'Överlämna en patient eller situation strukturerat: Situation, Bakgrund, Bedömning och Rekommendation.',
  'Prehospitale overdracht naar de SEH met leeftijd, mechanisme, letsels, symptomen en behandeling.':
      'Prehospital överlämning till akutmottagningen med ålder, mekanism, skador, tecken och behandling.',
  'Bespreek een casus met alle disciplines: beeld, behandeldoel, besluiten en afspraken.':
      'Diskutera ett fall över disciplinerna: bild, behandlingsmål, beslut och åtgärder.',
  'Sign in, time-out en sign out rond een ingreep volgens de WHO-checklist.':
      'Sign in, time-out och sign out kring ett ingrepp enligt WHO-checklistan.',
  'Draag de zorg per patiënt over: toestand, aandachtspunten en openstaande taken.':
      'Överlämna vården per patient: tillstånd, uppmärksamhetspunkter och öppna uppgifter.',
  'Zet verwachtingen, mijlpalen en begeleiding uit over de eerste 30, 60 en 90 dagen.':
      'Fastställ förväntningar, milstolpar och stöd för de första 30, 60 och 90 dagarna.',
  'Mensen, systemen, huisregels en de veiligheids- en privacybasis voor een nieuwe medewerker.':
      'Människor, system, husregler och grunderna för säkerhet och integritet för en ny medarbetare.',
  'Doelen, ritme en checkpoints tussen nieuwkomer en buddy of mentor.':
      'Mål, takt och avstämningar mellan den nya och buddy eller mentor.',
  'Kennisoverdracht, intrekken van toegang en een net exitgesprek bij vertrek.':
      'Kunskapsöverföring, återkallande av behörigheter och ett ordentligt avslutssamtal vid avgång.',
  'Persoonlijke go/no-go: ziekte, medicatie, stress, alcohol, vermoeidheid en gemoed.':
      'Personligt go/no-go: sjukdom, medicin, stress, alkohol, trötthet och sinnesstämning.',
  'Taakverdeling, bedreigingen en fouten (TEM) en afwijkingen vóór vertrek met de bemanning.':
      'Uppgiftsfördelning, hot och fel (TEM) och avvikelser före avgång med besättningen.',
  'Meld een voorval feitelijk en zonder schuldvraag: wat, factoren, risico en verbetering.':
      'Rapportera en händelse sakligt och utan skuldbeläggning: vad, faktorer, risk och förbättring.',
  'Taak, gevaren, maatregelen en akkoord vlak voordat het werk begint.':
      'Uppgift, faror, åtgärder och godkännande strax innan arbetet börjar.',
  'Capaciteit, risico\'s, in- en uitstroom en incidentrollen voor een evenement.':
      'Kapacitet, risker, personflöden och roller vid incident för ett evenemang.',
  'Scenario, taken, verzamelplaats, waarnemingen en evaluatie van een ontruiming.':
      'Scenario, uppgifter, uppsamlingsplats, observationer och utvärdering av en utrymning.',
  'Werk, isolaties, controles en vrijgave voor risicovol werk vastleggen.':
      'Dokumentera arbete, isoleringar, kontroller och godkännande för högriskarbete.',
  'Eerste melding bij een groot incident: melding, locatie, type, gevaren, toegang, aantal en diensten.':
      'Första rapporten vid en storskadehändelse: storskadehändelse, exakt plats, typ, faror, tillträde, antal och tjänster.',
  'Bepaal het GRIP-niveau, de crisisstructuur, rollen en op- en afschalingsbesluiten.':
      'Fastställ GRIP-nivån, krisstrukturen, rollerna och beslut om upp- och nedtrappning.',
  'Reisplan en brugafspraken (appraisal, planning, execution, monitoring) met kritieke routepunten.':
      'Färdplan och bryggöverenskommelser (appraisal, planning, execution, monitoring) med kritiska ruttpunkter.',
  'Afbeelding of media': 'Bild eller media',
  'Dia-inhoud': 'Bildinnehåll',
  'kon niet worden gelezen en is overgeslagen':
      'kunde inte läsas och hoppades över',
  'ontbrak in het bestand en is overgeslagen':
      'saknades i filen och hoppades över',
  'Hoofdeffecten': 'Huvudeffekter',
  'Interactie': 'Interaktion',
  'Te weinig gegevens voor een hoofdeffectenplot':
      'För lite data för ett huvudeffektsdiagram',
  'Te weinig gegevens voor een interactieplot':
      'För lite data för ett interaktionsdiagram',
  'DOE-proefopzet…': 'DOE-design…',
  'DOE-proefopzet': 'DOE-design',
  'Genereert een ontwerptabel met gecodeerde factoren (−1/+1) en een lege Y-kolom in het raster.':
      'Skapar en designtabell med kodade faktorer (−1/+1) och en tom Y-kolumn i rutnätet.',
  'Aantal factoren': 'Antal faktorer',
  'Volledig factorial (2^k)': 'Full faktoriell (2^k)',
  'Fractioneel (2^(k−p))': 'Fraktionell (2^(k−p))',
  'Fractie p': 'Fraktion p',
  'runs in standaard Yates-volgorde': 'körningar i standard Yates-ordning',
  'In raster zetten': 'Fyll rutnätet',
  'Eén reeks per factor met gecodeerde niveaus −1 en +1; laatste reeks is de respons (Y). Rijen zijn proefruns.':
      'En serie per faktor med kodade nivåer −1 och +1; sista serien är responsen (Y). Rader är försökskörningar.',
  'Golden-thread-id': 'Golden-thread-id',
  'wordt ergens genoemd maar staat niet op een boom-dia — definieer hem op een CTQ- of Ishikawa-boom.':
      'nämns någonstans men finns inte på ett träd-slide — definiera den på ett CTQ- eller Ishikawa-träd.',
  'staat op een boom-dia maar wordt nergens anders gebruikt — koppel hem aan een matrix, stroom of andere dia.':
      'finns på ett träd-slide men används inte någon annanstans — koppla den till en matris, flöde eller annat slide.',
  'Nieuw verbeteringsproject': 'Nytt förbättringsprojekt',
  'Kader': 'Ramverk',
  'Primaire Y-metriek (Y-01)': 'Primär Y-metrik (Y-01)',
  'Bijvoorbeeld: doorlooptijd orderintake in werkdagen':
      'Till exempel: orderintake ledtid i arbetsdagar',
  'Project starten': 'Starta projekt',
  'Procesverbetering: DMAIC-project': 'Processförbättring: DMAIC-projekt',
  'DMAIC-skelet met charter, CTQ-boom (Y-01), SIPOC en fase-secties.':
      'DMAIC-skelett med charter, CTQ-träd (Y-01), SIPOC och fasavsnitt.',
  'Een fasepoort-checklist: bevestig scope, stakeholders en go/no-go voordat je naar de volgende fase gaat.':
      'En fasport-checklista: bekräfta scope, intressenter och go/no-go innan du går vidare till nästa fas.',
  'Stroom': 'Flöde',
  'Zwembanen': 'Simbanor',
  'Een processtroom, zwembanen of VSM. Stappen als titel :: soort :: pt=…; lt=…. Totalen (PCE, bottleneck) worden berekend, niet opgeslagen.':
      'Ett processflöde, simbanor eller VSM. Steg som titel :: typ :: pt=…; lt=…. Totaler (PCE, bottleneck) beräknas och sparas inte.',
  'Boom': 'Träd',
  'Visgraat': 'Fiskben',
  'Lay-out': 'Layout',
  'Punten': 'Punkter',
  'Inspringen': 'Öka indrag',
  'Uitspringen': 'Minska indrag',
  'Punt toevoegen': 'Lägg till punkt',
  'Punt verwijderen': 'Ta bort punkt',
  'Een boom of visgraat (5× Why, CTQ, Ishikawa). Diepte met tabs; markeer oorzaken als **X-01** inline.':
      'Ett träd eller fiskben (5× Why, CTQ, Ishikawa). Djup med tabbar; markera orsaker som **X-01** inline.',
  'Canvas': 'Canvas',
  'Een canvas van regio\'s (A3, charter, SWOT, bord). Kies een sjabloon; de ##-koppen op schijf zijn de vakken.':
      'En canvas av regioner (A3, charter, SWOT, tavla). Välj en mall; ##-rubrikerna på disken är rutorna.',
  'Matrix': 'Matris',
  'Een getypeerd raster (SIPOC, FMEA, RACI, …). Kies een sjabloon; afgeleide kolommen zoals RPN worden berekend en niet opgeslagen.':
      'Ett typat rutnät (SIPOC, FMEA, RACI, …). Välj en mall; härledda kolumner som RPN beräknas och sparas inte.',
  'Regelkaart': 'Styrdiagram',
  'Histogram': 'Histogram',
  'Pareto': 'Pareto',
  'Run chart': 'Förloppsdiagram',
  'Boxplot': 'Lådagram',
  'Plakken uit klembord': 'Klistra in från urklipp',
  'Te weinig gegevens voor een regelkaart': 'För lite data för ett styrdiagram',
  'Te weinig gegevens voor een histogram': 'För lite data för ett histogram',
  'Te weinig gegevens voor een boxplot': 'För lite data för ett lådagram',
  'Procesverbetering': 'Processförbättring',
  'Deze presentatie bevat onderdelen van de Procesverbetering-module. Zet de module aan om ze te bewerken.':
      'Den här presentationen innehåller delar av modulen Processförbättring. Aktivera modulen för att redigera dem.',
  'Online media staat uit — aanzetten': 'Onlinemedier är av — slå på',
  '{bestand} bevat uitvoerbare inhoud en wordt niet geïmporteerd.':
      '{bestand} innehåller körbart innehåll och importeras inte.',
  'Aanzetten in instellingen': 'Aktivera i inställningarna',
  'Online media werkt niet in de webversie':
      'Onlinemedia fungerar inte i webbversionen',
  'De browser blokkeert media van een externe bron. Open deze presentatie in de app om online media te tonen.':
      'Webbläsaren blockerar medier från en extern källa. Öppna den här presentationen i appen för att visa onlinemedia.',
  'Bron niet toegestaan': 'Källan tillåts inte',
  'Deze URL is door de beveiliging geweigerd.':
      'Den här URL:en avvisades av säkerheten.',
  'Alinea': 'Stycke',
  'Audio "{bestand}"': 'Ljud "{bestand}"',
  'Deck opbouwen…': 'Bygger deck…',
  'Dia bevat meerdere audiofragmenten; OciDeck ondersteunt er maar één per dia.':
      'Bilden innehåller flera ljudklipp; OciDeck stöder bara ett per bild.',
  'Dia bevat meerdere grafieken; OciDeck ondersteunt er maar één per dia.':
      'Bilden innehåller flera diagram; OciDeck stöder bara ett per bild.',
  'Dia bevat meerdere tabellen; OciDeck ondersteunt er maar één per dia.':
      'Bilden innehåller flera tabeller; OciDeck stöder bara en per bild.',
  'Dia bevat meerdere video\'s; OciDeck ondersteunt er maar één per dia.':
      'Bilden innehåller flera videor; OciDeck stöder bara en per bild.',
  'Dia {n} overgeslagen': 'Bild {n} överhoppad',
  'Dia {n}: alleen de afbeelding overgenomen':
      'Bild {n}: endast bilden behölls',
  'Een niet-tekstuele vorm, lijn of ander object kon niet worden omgezet.':
      'En icke-textuell figur, linje eller annat objekt kunde inte konverteras.',
  'Footerrijen worden in Markdown niet ondersteund.':
      'Sidfotsrader stöds inte i Markdown.',
  'Formaat herkennen…': 'Identifierar format…',
  'Gegroepeerde objecten zijn uitgeklapt; groepering en volgorde binnen de groep gaan verloren.':
      'Grupperade objekt har delats upp; gruppering och ordning inom gruppen går förlorade.',
  'Groepering': 'Gruppering',
  'Headerkolommen worden in OciDeck niet ondersteund.':
      'Rubrikkolumner stöds inte i OciDeck.',
  'IWA-objecten inlezen…': 'Läser IWA-objekt…',
  'IWA-structuur gedeeltelijk geparseerd — de vormgeving (thema, kleuren, posities) is niet overgenomen; tekst, slide-volgorde, notities en, waar de structuren herkend werden, tabellen, grafieken en media wel':
      'IWA-strukturen tolkades delvis — utformningen (tema, färger, positioner) överfördes inte; text, bildordning, anteckningar och, där strukturerna kändes igen, tabeller, diagram och media överfördes.',
  'IWA-structuur niet volledig geparseerd — opmaak, tabellen, grafieken, media en slide-volgorde niet overgenomen':
      'IWA-strukturen tolkades inte fullständigt — formatering, tabeller, diagram, media och bildordning överfördes inte',
  'IWA-tekst salvage…': 'Räddar IWA-text…',
  'Keynote IWA-intern': 'Keynote IWA internt',
  'Keynote IWA-intern (~{n} dia’s)': 'Keynote IWA internt (~{n} bilder)',
  'Keynote tabel footer': 'Keynote-tabellsidfot',
  'Keynote tabel header': 'Keynote-tabellrubrik',
  'Keynote tabel headerkolommen': 'Keynote-tabellrubrikkolumner',
  'Klaar.': 'Klar.',
  'Koppeling “{tekst}”': 'Länk "{tekst}"',
  'Meerdere audio': 'Flera ljudfiler',
  'Meerdere grafieken': 'Flera diagram',
  'Meerdere headerrijen worden in Markdown niet ondersteund; alleen de eerste rij wordt als tabelheader gebruikt.':
      'Flera rubrikrader stöds inte i Markdown; endast den första raden används som tabellrubrik.',
  'Meerdere tabellen': 'Flera tabeller',
  'Meerdere video\'s': 'Flera videor',
  'Metadata uitlezen…': 'Läser metadata…',
  'Niet overgenomen van dit document': 'Överfördes inte från detta dokument',
  'Niet overgenomen van slide {n}': 'Överfördes inte från bild {n}',
  'Ondersteund grafiektype': 'Diagramtyp som stöds',
  'Samengevoegde cellen': 'Sammanslagna celler',
  'Samengevoegde tabelcellen worden in GFM-tabellen niet ondersteund; de tabel is platgeklapt.':
      'Sammanslagna tabellceller stöds inte i GFM-tabeller; tabellen har plattats ut.',
  'Scatter x-as': 'Punktdiagrammets x-axel',
  'Scatter-grafiek met aparte x-waardes per serie kan niet volledig worden weergegeven.':
      'Ett punktdiagram med separata x-värden per serie kan inte visas fullständigt.',
  'Slides classificeren…': 'Klassificerar bilder…',
  'Slides reconstrueren…': 'Rekonstruerar bilder…',
  'Tabel naast grafiek': 'Tabell bredvid diagram',
  'Voorbeeldafbeelding zoeken…': 'Söker efter förhandsgranskningsbild…',
  'Vorm of object': 'Figur eller objekt',
  'de tekst blijft staan, de verwijzing niet':
      'texten är kvar, referensen inte',
  'deels overgenomen': 'delvis överförd',
  'doel onschadelijk gemaakt; het wees naar {url}':
      'målet oskadliggjort; det pekade på {url}',
  'eerste audio overgenomen': 'första ljudet behölls',
  'eerste grafiek overgenomen': 'första diagrammet behölls',
  'eerste rij als header': 'första raden som rubrik',
  'eerste tabel overgenomen': 'första tabellen behölls',
  'eerste video overgenomen': 'första videon behölls',
  'gedeelde x-as gebruikt': 'gemensam x-axel användes',
  'niet overgenomen (OciDeck heeft geen audio-slides)':
      'överfördes inte (OciDeck har inga ljudbilder)',
  'niet overgenomen (deze dia werd een {type})':
      'överfördes inte (den här bilden blev en {type})',
  'niet overgenomen (deze dia werd een {type}, en die draagt geen opsomming)':
      'överfördes inte (den här bilden blev en {type}, som inte har någon punktlista)',
  'niet overgenomen (een {type}-dia toont er {aantal})':
      'överfördes inte (en {type}-bild visar {aantal})',
  'niet overgenomen (een {type}-dia toont geen losse alineatekst)':
      'överfördes inte (en {type}-bild visar ingen fristående brödtext)',
  'niet overgenomen (één grafiek of tabel per slide)':
      'överfördes inte (ett diagram eller en tabell per bild)',
  'objecten apart overgenomen': 'objekt överförda var för sig',
  'samengevoegd in leesvolgorde': 'sammanfogade i läsordning',
  'tekst, volgorde, notities en herkende tabellen, grafieken en media':
      'text, ordning, anteckningar och igenkända tabeller, diagram och media',
  '{n} afbeelding': '{n} bild',
  '{n} afbeeldingen': '{n} bilder',
  '{n} alinea’s': '{n} stycken',
  '{n} opsommingspunt': '{n} punkt',
  '{n} opsommingspunten': '{n} punkter',
  '{n} vrij geplaatste tekstvakken': '{n} fritt placerade textrutor',
  'voorbeeldafbeelding en tekst': 'förhandsgranskningsbild och text',
  'voorbeeldafbeelding': 'förhandsgranskningsbild',
  'tekst': 'text',
  '{bestand} is groter dan de limiet van {limiet} en wordt niet geïmporteerd.':
      '{bestand} är större än gränsen på {limiet} och importeras inte.',
  '{bestand} is geen herkende presentatie. OciDeck leest PowerPoint (.pptx), OpenDocument (.odp) en Keynote (.key).':
      '{bestand} är inte en igenkänd presentation. OciDeck läser PowerPoint (.pptx), OpenDocument (.odp) och Keynote (.key).',
  '{bestand} lijkt beschadigd: het archief kan niet volledig worden uitgepakt.':
      '{bestand} verkar vara skadad: arkivet kan inte packas upp helt.',
  'Het {formaat}-formaat wordt nog niet ondersteund ({bestand}).':
      'Formatet {formaat} stöds inte ännu ({bestand}).',
  'Geen dia’s gevonden in {bestand} — is dit een geldig {formaat}-bestand?':
      'Inga bilder hittades i {bestand} — är detta en giltig {formaat}-fil?',
  'Kon {bestand} niet lezen als {formaat}-presentatie.':
      '{bestand} kunde inte läsas som en {formaat}-presentation.',
  'Wat doen we met deze dia’s?': 'Vad gör vi med de här bilderna?',
  'Deze dia’s konden niet volledig worden omgezet. Kies per dia wat er moet gebeuren; wat u niet aanraakt wordt zo volledig mogelijk overgenomen, met een notitie erbij over wat er ontbreekt.':
      'De här bilderna kunde inte konverteras helt. Välj för varje bild vad som ska hända; det du inte rör tas över så komplett som möjligt, med en notering om vad som saknas.',
  'Voor alle dia’s:': 'För alla bilder:',
  'Dia': 'Bild',
  'Zo volledig mogelijk': 'Så komplett som möjligt',
  'Alleen de afbeelding': 'Endast bilden',
  'Import afbreken': 'Avbryt import',
  'Niet meer vragen': 'Fråga inte igen',
  'Voortaan alles zo volledig mogelijk overnemen.':
      'Från och med nu tas allt över så komplett som möjligt.',
  'De checklist-index: per test het stabiele id, de canonieke titel en de categorie. De inhoud van de gids zelf is niet gebundeld.':
      'Checklisteindexet: per test det stabila id:t, den kanoniska titeln och kategorin. Själva guidens innehåll ingår inte.',
  'De test-index van v2.0.0: per test het stabiele id, de canonieke titel, de MASVS-categorie en de MASWE-zwakheid. De ingetrokken v1-tests en de placeholders zitten er niet in; de inhoud van de gids evenmin.':
      'Testindexet för v2.0.0: per test det stabila id:t, den kanoniska titeln, MASVS-kategorin och MASWE-svagheten. Tillbakadragna v1-test och platshållare ingår inte; inte heller guidens innehåll.',
  'De volledige lijst (id, naam, beschrijving) plus een eigen geselecteerde kern met onze remediatie-notities.':
      'Hela listan (id, namn, beskrivning) plus en egen utvald kärna med våra åtgärdsanteckningar.',
  'Het volledige EIS-schema (88 toetsbare eisen).':
      'Hela EIS-schemat (88 testbara krav).',
  'Aandoeningsnamen in negen talen als gezondheidslexicon voor de privacycontrole (assets/privacy/health_lexicon.json).':
      'Sjukdomsnamn på nio språk som hälsolexikon för integritetskontrollen (assets/privacy/health_lexicon.json).',
  'Een eigen Dart-implementatie van de publieke specificatie, inclusief de MacroVector-tabel en de gepubliceerde bandindeling.':
      'En egen Dart-implementation av den offentliga specifikationen, inklusive MacroVector-tabellen och de publicerade allvarlighetsbanden.',
  'Specificatie van FIRST.Org — attributie':
      'Specifikation från FIRST.Org — erkännande',
  'Ctrl/Cmd': 'Ctrl/Cmd',
  'Shift': 'Shift',
  'Presentaties importeren…': 'Importera presentationer…',
  'Presentaties importeren': 'Importera presentationer',
  'Presentatie importeren': 'Importera presentation',
  'Presentatie kiezen': 'Välj presentation',
  'Importeren mislukt.': 'Importen misslyckades.',
  'Presentatie geïmporteerd.': 'Presentationen importerad.',
  'Bewaar de presentatie onder een eigen naam. Je kunt de titel nu aanpassen.':
      'Spara presentationen under ditt eget namn. Du kan justera titeln nu.',
  'Openen': 'Öppna',
  'Presentatie geïmporteerd; controleer de aandachtspunten.':
      'Presentationen importerad; kontrollera anmärkningarna.',
  'Presentaties geïmporteerd.': 'Presentationerna importerade.',
  'Niet meer tonen': 'Visa inte igen',
  'met verlies': 'med förlust',
  'dia’s': 'bilder',
  'dia’s vragen aandacht': 'bilder behöver uppmärksamhet',
  'Doelmap': 'Målmapp',
  'Nog geen doelmap gekozen': 'Ingen målmapp vald ännu',
  'Uit de rij halen': 'Ta bort ur kön',
  'Stoppen': 'Stoppa',
  'Bezig met importeren…': 'Importerar…',
  'Resultaat': 'Resultat',
  'Opgeslagen in': 'Sparat i',
  'geslaagd': 'lyckades',
  'mislukt': 'misslyckades',
  'niet meer aan de beurt gekomen': 'kom inte i tur',
  'Importeren is best-effort en geen één-op-één-kopie: OciDeck heeft een eenvoudiger diamodel dan PowerPoint. Wat niet past, komt op een “niet overgenomen”-notitie te staan; controleer het resultaat na afloop.':
      'Importen görs så gott det går och är ingen ett-till-ett-kopia: OciDeck har en enklare bildmodell än PowerPoint. Det som inte får plats hamnar på en anteckning ”inte överfört”; kontrollera resultatet efteråt.',
  'Tip: bewaar geïmporteerde presentaties in een aparte map. De kwaliteit verschilt per bron, en zo blijft geïmporteerd materiaal gescheiden van uw eigen werk.':
      'Tips: spara importerade presentationer i en egen mapp. Kvaliteten varierar mellan källor, och så hålls importerat material skilt från ditt eget arbete.',
  'Elk bestand wordt apart omgezet en als eigen presentatie in de doelmap opgeslagen. Gaat er één mis, dan loopt de rij gewoon door.':
      'Varje fil konverteras separat och sparas som en egen presentation i målmappen. Om en går fel fortsätter kön ändå.',
  'Meerdere presentaties tegelijk importeren schrijft ze als bestanden naar een map; in de browserversie kan dat niet.':
      'Att importera flera presentationer samtidigt skriver dem som filer till en mapp; det går inte i webbläsarversionen.',
  'Het overzicht staat klaar in een nieuw tabblad.':
      'Översikten är klar i en ny flik.',
  'De import leest alleen; er wordt niets in deze map gewijzigd of verstuurd. Bestanden die geen OpenKAT-rapportage blijken, worden overgeslagen en in het importverslag benoemd.':
      'Importen läser bara; ingenting i den här mappen ändras eller skickas. Filer som visar sig inte vara OpenKAT-rapporter hoppas över och nämns i importrapporten.',
  'Integraties': 'Integrationer',
  'Map kiezen…': 'Välj mapp…',
  'Map wissen': 'Rensa mapp',
  'Map met OpenKAT-rapportages kiezen': 'Välj mapp med OpenKAT-rapporter',
  'Geen OpenKAT-rapportages gevonden in deze map.':
      'Inga OpenKAT-rapporter hittades i den här mappen.',
  'rapportages': 'rapporter',
  'overgeslagen': 'överhoppade',
  'niet elk gekoppeld bestand kon mee (onleesbaar of buiten het project)':
      'inte alla länkade filer kunde tas med (oläsliga eller utanför projektet)',
  'punten': 'punkter',
  'regels': 'rader',
  'categorieën': 'kategorier',
  'In de data': 'I data',
  'getoond': 'visas',
  'De sorteerkolom bevat geen getallen; hoogste/laagste en samenvoegen werken dan niet zinvol.':
      'Sorteringskolumnen innehåller inga tal; högsta/lägsta och sammanslagning är då inte meningsfulla.',
  'Weergave beperken': 'Begränsa visning',
  'Beperk het aantal getoonde items': 'Begränsa antalet visade objekt',
  'Maximaal aantal items': 'Maximalt antal objekt',
  'Welke items': 'Vilka objekt',
  'Laatste': 'Sista',
  'Hoogste': 'Högsta',
  'Laagste': 'Lägsta',
  'Sorteerkolom of reeks': 'Sorteringskolumn eller serie',
  'Niet-getoonde items': 'Objekt som inte visas',
  'Verbergen, wel bewaren': 'Dölj, men behåll',
  'Samenvoegen tot Overig': 'Slå ihop till Övrigt',
  'Toon hoeveel items verborgen zijn': 'Visa hur många objekt som är dolda',
  'Toon alleen een deel van de bullets, tabel of grafiek. De oorspronkelijke data blijft in het bestand bewaard.':
      'Visa bara en del av punkterna, tabellen eller diagrammet. Originaldata finns kvar i filen.',
  'Voor tabellen: kolomindex of naam om op te sorteren. Voor grafieken: naam van de reeks.':
      'För tabeller: kolumnindex eller kolumnnamn att sortera efter. För diagram: seriens namn.',
  'Online opslag is alleen beschikbaar in de desktopversie.':
      'Onlinelagring är endast tillgänglig i skrivbordsversionen.',
  'Online opslag': 'Onlinelagring',
  'Presentaties openen uit en opslaan naar WebDAV, S3 en git-repository’s, met versiebeheer en samenwerken via een forge. Een deel van deze paden is tot nu toe vooral tegen testomgevingen beproefd; kies dit bewust. Zonder de module werkt alles lokaal gewoon: mappen, bestanden en pakketten.':
      'Öppna presentationer från och spara till WebDAV, S3 och git-repositories, med versionshantering och samarbete via en forge. Hittills har en del av dessa vägar mest prövats mot testmiljöer; välj detta medvetet. Utan modulen fungerar allt lokalt som vanligt: mappar, filer och paket.',
  'Er staan al online verbindingen ingesteld; die blijven werken, net als wachtend werk in de wachtrij. Uit betekent alleen: geen nieuwe online verbindingen toevoegen.':
      'Det finns redan onlineanslutningar inställda; de fortsätter att fungera, liksom väntande arbete i kön. Av betyder bara: inga nya onlineanslutningar kan läggas till.',
  'De module AI-assistentie staat uit, dus hier gebeurt niets. Zet hem aan bij Uitbreidingen. Wat je hieronder hebt ingesteld blijft staan.':
      'Modulen AI-assistans är avstängd, så här händer ingenting. Slå på den under Tillägg. Det du har ställt in nedan finns kvar.',
  'Hulp bij alt-teksten, beschrijvingen en formuleringen. Aanzetten verstuurt nog niets: dat gebeurt pas nadat je zelf een backend hebt gekozen en, bij een clouddienst, uitdrukkelijk hebt bevestigd. Een lokale backend verlaat je computer niet.':
      'Hjälp med alt-texter, beskrivningar och formuleringar. Att slå på skickar ännu ingenting: det sker först när du själv har valt en backend och, vid en molntjänst, uttryckligen har bekräftat. Med en lokal backend lämnar ingenting din dator.',
  'Kies de backend op het tabblad AI-assistentie. Zolang daar niets staat, gebeurt er niets.':
      'Välj backend på fliken AI-assistans. Så länge inget är valt där händer ingenting.',
  'De voorbeelddia\'s van een sjabloon staan in het Engels. Naam en omschrijving volgen je eigen taal; de inhoud pas je na het aanmaken aan.':
      'En malls exempelbilder är på engelska. Namn och beskrivning följer ditt eget språk; innehållet anpassar du efter att du har skapat den.',
  'Meer': 'Mer',
  'Leesbaarheid van dit profiel': 'Läsbarhet för den här profilen',
  'Alle onderdelen halen de norm.': 'Alla delar uppfyller normen.',
  'Deze verhoudingen gaan over de app zelf, niet over je dia\'s.':
      'De här förhållandena gäller appen själv, inte dina bilder.',
  'Tekst op kaarten en dialogen': 'Text på kort och dialogrutor',
  'Tekst op de schermachtergrond': 'Text på skärmbakgrunden',
  'Tekst en pictogrammen in de zijbalk': 'Text och ikoner i sidofältet',
  'Titel in de bovenbalk': 'Titel i det översta fältet',
  'Tekstknoppen en links': 'Textknappar och länkar',
  'Selectievakjes, schakelaars en de tekstcursor':
      'Kryssrutor, reglage och textmarkören',
  'Het vinkje in een aangevinkt vakje': 'Bocken i en ikryssad ruta',
  'Label op de primaire knop': 'Etiketten på primärknappen',
  'Bevindingen die je hebt beoordeeld en hebt laten staan. Ze worden niet meer gemeld, maar de scan blijft ze vinden en ze tellen niet als opgelost. Tik om er een terug te zetten.':
      'Iakttagelser som du har bedömt och låtit stå kvar. De rapporteras inte längre, men skanningen hittar dem fortfarande och de räknas inte som åtgärdade. Tryck för att återställa en.',
  'Deze is beoordeeld en mag blijven': 'Granskad, den här får stanna',
  'Mogelijk gemaakt door': 'Möjliggjort av',
  'De export is gestopt tijdens het voorbereiden.':
      'Exporten stoppade under förberedelsen.',
  'Het bestand kon niet worden opgebouwd of weggeschreven. Controleer of er schijfruimte is en of de exportmap beschrijfbaar is.':
      'Filen kunde inte byggas eller skrivas. Kontrollera att det finns diskutrymme och att exportmappen är skrivbar.',
  'Het renderen van de dia\'s naar beeld is mislukt. Dit ligt aan een dia, niet aan het bestandsformaat: de HTML-export komt hier niet langs en werkt in dit geval meestal wel.':
      'Renderingen av bilderna till bild misslyckades. Det beror på en bild, inte på filformatet: HTML-exporten passerar inte här och fungerar oftast i det här fallet.',
  'Technische melding:': 'Tekniskt meddelande:',
  'presentaties': 'presentationer',
  '/Presentaties': '/Presentationer',
  'De export is mislukt.': 'Exporten misslyckades.',
  'Presenteer vanaf hier': 'Presentera härifrån',
  'Traffic Light Protocol: hoe breed mag dit materiaal gedeeld worden?':
      'Traffic Light Protocol: hur brett får det här materialet delas?',
  'Wat betekenen deze niveaus?': 'Vad betyder de här nivåerna?',
  'het classificatiebeleid bewaakt wat er uit mag.':
      'klassificeringspolicyn bevakar vad som får lämna.',
  'de markering reist mee, maar er is geen drempel: zet het classificatiebeleid aan onder Instellingen → Algemeen.':
      'markeringen följer med, men det finns ingen spärr: slå på klassificeringspolicyn under Inställningar → Allmänt.',
  'Dit document bestaat alleen in het Engels.':
      'Det här dokumentet finns bara på engelska.',
  'Dit bestand bestaat niet meer op deze plek.':
      'Den här filen finns inte längre på den här platsen.',
  'Dit bestand is te groot om te openen.':
      'Den här filen är för stor för att öppna.',
  'Deze presentatie is beschadigd of half opgeslagen.':
      'Den här presentationen är skadad eller bara till hälften sparad.',
  'Dit bestand is geen leesbare tekst. OciDeck opent Markdown.':
      'Den här filen är inte läsbar text. OciDeck öppnar Markdown.',
  'Deze dia is leeg: hij toont niets op het scherm en in de export.':
      'Den här bilden är tom: den visar ingenting på skärmen eller i exporten.',
  'Export geblokkeerd door classificatiebeleid: stel een TLP-niveau in voor deze presentatie.':
      'Export blockerad av klassificeringspolicyn: ange en TLP-nivå för den här presentationen.',
  'Export geblokkeerd door classificatiebeleid: dit deck is {deck}, lager dan het vereiste minimum {limit}.':
      'Export blockerad av klassificeringspolicyn: den här presentationen är {deck}, under den miniminivå som krävs {limit}.',
  'Export geblokkeerd door classificatiebeleid: dit deck is {deck}, hoger dan het toegestane vrijgaveniveau {limit}.':
      'Export blockerad av klassificeringspolicyn: den här presentationen är {deck}, över det tillåtna frisläppningstaket {limit}.',
  'niet geclassificeerd': 'inte klassificerad',
  'Regels die nu uit staan. Deze worden niet gemeld en niet geredigeerd. Drie ervan staan standaard uit — hun trefwoorden komen op gewone zakelijke slides te vaak voor. Tik om er een aan te zetten.':
      'Regler som är avstängda just nu. De rapporteras inte och maskas inte. Tre av dem är avstängda som standard — deras nyckelord förekommer för ofta på vanliga affärsbilder. Tryck för att slå på en.',
  'Bekende beperkingen': 'Kända begränsningar',
  'naam@example.org\nexample.org': 'namn@example.org\nexample.org',
  'Een laag naast dit deck was te groot en is niet ingelezen; het bestand zelf is ongewijzigd:':
      'Ett lager bredvid detta deck var för stort och lästes inte in; själva filen är oförändrad:',
  'Deze tijdstempel hoort niet bij het laatste verzoek':
      'Den här tidsstämpeln hör inte till den senaste begäran',
  'Vermeld dit versienummer wanneer u een beveiligingsprobleem meldt.':
      'Ange detta versionsnummer när du rapporterar ett säkerhetsproblem.',
  'Video niet ingesloten': 'Videon är inte inbäddad',
  'Afbeelding niet ingesloten': 'Bilden är inte inbäddad',
  'Dit diagram kon niet worden getekend': 'Det här diagrammet kunde inte ritas',
  'Brontekst van het diagram': 'Diagrammets källtext',
  'Jouw antwoord': 'Ditt svar',
  'nodig': 'krävs',
  'Bij een vergrendeld deck verschijnt het overzicht nooit; deze schakelaar doet dan niets.':
      'Med en låst presentation visas översikten aldrig; det här reglaget gör då ingenting.',
  'De twee afbeeldingen': 'De två bilderna',
  'Goed gerekende antwoorden': 'Svar som räknas som rätt',
  'Afbeelding 1': 'Bild 1',
  'Afbeelding 2': 'Bild 2',
  'Alleen een letterlijk gelijk antwoord telt.':
      'Bara ett ordagrant identiskt svar räknas.',
  'De kijker typt het antwoord. Elk antwoord dat je hier aanvinkt telt als goed; hoofdletters en extra spaties maken niet uit.':
      'Åskådaren skriver svaret. Varje svar du kryssar i här räknas som rätt; versaler och extra mellanslag spelar ingen roll.',
  'De kijker wijst de juiste afbeelding aan. Bij presenteren wisselt links/rechts per ronde, dus benoem ze niet als "linker" en "rechter".':
      'Åskådaren pekar ut rätt bild. Vid presentation byter vänster och höger plats varje runda, så kalla dem inte "vänster" och "höger".',
  'Een tikfout telt nog als goed; een ander woord niet.':
      'Ett skrivfel räknas fortfarande som rätt; ett annat ord gör det inte.',
  'Getypt antwoord': 'Skrivet svar',
  'Goed gerekend antwoord:': 'Svar som räknas som rätt:',
  'Kies twee afbeeldingen en markeer de juiste.':
      'Välj två bilder och markera den rätta.',
  'Nog geen goed antwoord opgegeven.': 'Inget rätt svar har angetts ännu.',
  'Overeenkomst': 'Överensstämmelse',
  'Tik de juiste afbeelding aan': 'Tryck på rätt bild',
  'Twee afbeeldingen': 'Två bilder',
  'Typ je antwoord': 'Skriv ditt svar',
  'Typ je antwoord en bevestig': 'Skriv ditt svar och bekräfta',
  'Vereiste overeenkomst met het juiste antwoord':
      'Krävd överensstämmelse med rätt svar',
  'Vink minstens één goed gerekend antwoord aan.':
      'Kryssa i minst ett svar som räknas som rätt.',
  'Vragen': 'Frågor',
  'antwoorden, alle getoond in willekeurige volgorde':
      'svar, alla visas i slumpmässig ordning',
  'fout': 'fel',
  'goed': 'rätt',
  'goed vanaf': 'rätt från',
  'links en rechts wisselen per ronde':
      'vänster och höger byter plats varje runda',
  'overeenkomst': 'överensstämmelse',
  'Deze tekst bevat hoofdstukken. Opknippen levert':
      'Den här texten innehåller kapitel. Uppdelningen ger',
  'dia\'s op.': 'bilder.',
  'Splits op hoofdstukken': 'Dela upp efter kapitel',
  'Er staat AI-tekst in dit deck die je nog niet hebt nagekeken. Exporteren kan; het bestand meldt dat dan zelf en krijgt "-ai-concept" in de naam.':
      'Den här presentationen innehåller AI-text som du inte har granskat än. Du kan exportera ändå; filen anger det själv och får "-ai-concept" i namnet.',
  'Concept: hier staat AI-tekst die nog niemand heeft nagekeken':
      'Utkast: innehåller AI-text som ingen har granskat än',
  'Rond deze presentatie af en leg een SHA-512-zegel vast over het opgeslagen bestand. Daarna is het vergrendeld en niet meer te bewerken; elke latere wijziging wordt zichtbaar. Wie het rapport ontvangt, rekent het zegel zelf na met sha512sum. Dit kan in de app niet ongedaan worden gemaakt.':
      'Slutför den här presentationen och fastställ ett SHA-512-sigill över den sparade filen. Den låses sedan och kan inte längre redigeras; varje senare ändring blir synlig. Den som tar emot rapporten kontrollerar själv sigillet med sha512sum. Detta kan inte ångras i appen.',
  'Zegel en handtekening': 'Sigill och signatur',
  'Zegel nog niet vastgelegd': 'Sigill ännu inte fastställt',
  'Er is nog geen opgeslagen bestand om het zegel tegen na te rekenen. Sla het deck op.':
      'Det finns ännu ingen sparad fil att kontrollera sigillet mot. Spara decket.',
  'Weglaten staat aan: wat de controle als persoonsgegeven aanmerkt wordt zwart gemaakt, en álle afbeeldingen, video en audio van deze dia gaan niet mee naar het scherm of de export. Je markdown-bestand houdt alles.':
      'Utelämnande är på: det som kontrollen bedömer som en personuppgift svärtas, och alla bilder, all video och allt ljud på den här bilden följer inte med till skärmen eller exporten. Din markdown-fil behåller allt.',
  'Bestand': 'Arkiv',
  'Venster': 'Fönster',
  'Help': 'Hjälp',
  'Alles selecteren': 'Markera allt',
  'Plakken': 'Klistra in',
  'Opnieuw': 'Gör om',
  'Eigenschappen': 'Egenskaper',
  'Opdrachten…': 'Kommandon…',
  'Opslaan…': 'Sparar…',
  'Uploaden naar WebDAV…': 'Laddar upp till WebDAV…',
  'Uploaden naar S3…': 'Laddar upp till S3…',
  'Vastleggen in git…': 'Committar till git…',
  'Bezig met opslaan. Nog een keer opslaan doet niets tot dit klaar is.':
      'Sparar. Att spara igen gör ingenting förrän det här är klart.',
  'Klaar — privacy niet gecontroleerd': 'Klar — integritet inte kontrollerad',
  'Er is niet gekeken naar persoonsgegevens, bijzondere gegevens en geheimen: de privacycontrole staat uit bij Beveiliging.':
      'Ingen sökning har gjorts efter personuppgifter, känsliga uppgifter och hemligheter: integritetskontrollen är avstängd under Säkerhet.',
  'Presentaties die gewone Markdown-bestanden blijven: leesbaar, doorzoekbaar en te openen met elke editor.':
      'Presentationer som förblir vanliga Markdown-filer: läsbara, sökbara och går att öppna med vilken editor som helst.',
  'Mijn tekst': 'Min text',
  'Wat zij zien': 'Vad de ser',
  'Presentatiegegevens': 'Presentationsuppgifter',
  'Open presentatiegegevens': 'Öppna presentationsuppgifter',
  'Motivering van een uitsluiting': 'Motivering av ett undantag',
  'Motivering van een bevestiging': 'Motivering av en bekräftelse',
  'Tabel koprij, kolom {kolom}': 'Tabell rubrikrad, kolumn {kolom}',
  'Tabel rij {rij}, kolom {kolom}': 'Tabell rad {rij}, kolumn {kolom}',
  'Via deze website ophalen?': 'Hämta via den här webbplatsen?',
  'De server van deze presentatie liet de browser het bestand niet rechtstreeks lezen. OciDeck kan het adres doorgeven aan de website waar OciDeck zelf vandaan komt, en die haalt het dan op. Die website ziet daarmee het volledige adres — staat er een sleutel of code in de link, dan ziet die website die ook.':
      'Servern för den här presentationen lät inte webbläsaren läsa filen direkt. OciDeck kan skicka adressen vidare till den webbplats som OciDeck självt kommer från, och den hämtar filen. Därmed ser den webbplatsen hela adressen — finns det en nyckel eller kod i länken ser webbplatsen även den.',
  'In de browser kan dit niet worden bewaard':
      'Det här kan inte sparas i webbläsaren',
  'Een browser heeft geen sleutelbos zoals een computer die heeft: wat OciDeck hier zou opslaan, kan elk script op deze pagina meelezen. Gebruik de desktopversie — daar gaat het geheim wél in de sleutelbos van het besturingssysteem.':
      'En webbläsare har ingen nyckelring som en dator har: det OciDeck skulle spara här kan vilket skript som helst på den här sidan läsa. Använd skrivbordsversionen — där hamnar hemligheten faktiskt i operativsystemets nyckelring.',
  'Licenties van derden': 'Tredjepartslicenser',
  'Alle licentieteksten tonen': 'Visa alla licenstexter',
  'OciDeck zelf staat onder de EUPL-1.2. Daarnaast bundelt het software van derden: de Dart- en Flutter-pakketten, twee gevendorde pakketten, vijf lettertypefamilies, het gezichtsmodel voor de privacycontrole en de JavaScript die in een HTML-export meegaat. Elk daarvan houdt zijn eigen licentie.':
      'OciDeck självt ges ut under EUPL-1.2. Dessutom paketerar det programvara från tredje part: Dart- och Flutter-paketen, två medföljande paket, fyra teckensnittsfamiljer, ansiktsmodellen för integritetskontrollen och den JavaScript som följer med en HTML-export. Var och en behåller sin egen licens.',
  'Dit bestand bevat software van derden en soms een lettertype. Hieronder staan de volledige licentieteksten die daarbij horen; stuur ze mee als je dit bestand doorgeeft.':
      'Den här filen innehåller programvara från tredje part och ibland ett teckensnitt. Nedan finns de fullständiga licenstexterna som hör till; skicka med dem när du för filen vidare.',
  'Sporen op dit apparaat': 'Spår på den här enheten',
  'OciDeck bewaart naast je instellingen ook een recente lijst en, bij een crash, een herstelbestand met de volledige inhoud van je presentatie. Niets daarvan verlaat dit apparaat, maar het staat er wel — in platte tekst, beschermd door je account op dit besturingssysteem en niet meer dan dat.':
      'Förutom dina inställningar sparar OciDeck också en lista över senaste filer och, vid en krasch, en återställningsfil med hela innehållet i din presentation. Inget av det lämnar den här enheten, men det ligger här — i klartext, skyddat av ditt konto i det här operativsystemet och inte mer än så.',
  'Recent geopende presentaties': 'Senast öppnade presentationer',
  'De lijst bewaart het volledige pad en de classificatie van elk deck dat open is geweest — samen een gegeven over waar je aan werkt en voor wie.':
      'Listan sparar hela sökvägen och klassificeringen för varje presentation som har varit öppen — tillsammans en uppgift om vad du arbetar med och för vem.',
  'Recente lijst wissen': 'Radera listan över senaste filer',
  'De recente lijst was al leeg.': 'Listan över senaste filer var redan tom.',
  'vermelding(en) uit de recente lijst gewist.':
      'post(er) raderade från listan över senaste filer.',
  'Crash-herstelbestanden bevatten de volledige inhoud van je presentaties in platte tekst. Ze worden na 7 dagen automatisch opgeruimd, en bij een nette afsluiting meteen.':
      'Återställningsfiler innehåller hela innehållet i dina presentationer i klartext. De rensas automatiskt efter 7 dagar, och direkt vid en normal avslutning.',
  'Alles terugzetten': 'Återställ allt',
  'Wist elke instelling, de recente lijst, de herstelbestanden, de git-werkkopieën en de wachtwoorden in je sleutelbos. Je presentaties blijven staan: die zijn van jou, niet van OciDeck.':
      'Raderar alla inställningar, listan över senaste filer, återställningsfilerna, git-arbetskopiorna och lösenorden i din nyckelring. Dina presentationer blir kvar: de är dina, inte OciDecks.',
  'Zet alles terug naar de begintoestand': 'Återställ allt till ursprungsläget',
  'Alles terugzetten naar de begintoestand?':
      'Återställa allt till ursprungsläget?',
  'Je instellingen, de recente lijst, de herstelbestanden, de git-werkkopieën en de opgeslagen wachtwoorden worden gewist. Dit kan niet ongedaan worden gemaakt. Je presentaties blijven staan.':
      'Dina inställningar, listan över senaste filer, återställningsfilerna, git-arbetskopiorna och de sparade lösenorden raderas. Det går inte att ångra. Dina presentationer blir kvar.',
  'wijziging(en) zijn nog niet naar een git-server gestuurd en bestaan alleen op dit apparaat. Ook die gaan weg.':
      'ändring(ar) har ännu inte skickats till en git-server och finns bara på den här enheten. De försvinner också.',
  'Alles is teruggezet naar de begintoestand.':
      'Allt har återställts till ursprungsläget.',
  'Terugzetten is niet gelukt.': 'Återställningen misslyckades.',
  'Er wacht nog werk dat niet verstuurd is':
      'Det finns arbete som inte har skickats',
  'Deze git-verbinding heeft wijzigingen die nog niet naar de server zijn gestuurd. Verwijder je de verbinding, dan gaat ook de werkkopie op dit apparaat weg — en bestaat dit werk nergens meer.':
      'Den här git-anslutningen har ändringar som ännu inte har skickats till servern. Tar du bort anslutningen försvinner även arbetskopian på den här enheten — och då finns arbetet ingenstans.',
  'Verbinding behouden': 'Behåll anslutningen',
  'Toch verwijderen': 'Ta bort ändå',
  'esc': 'esc',
  'Enter': 'Enter',
  'OK': 'OK',
  'min': 'min',
  '# Bedankt\n\nVragen?': '# Tack\n\nFrågor?',
  'P {pitch}  B {bank}': 'T {pitch}  R {bank}',
  'ACT {value}°': 'AKT {value}°',
  'TGT {heading}°': 'MÅL {heading}°',
  'Presentatietitel': 'Presentationstitel',
  'Sectienaam': 'Avsnittsnamn',
  'Optionele toelichting': 'Valfri förklaring',
  'Scope': 'Omfattning',
  'Sinds de vorige rapportage': 'Sedan föregående rapport',
  'Ons aanvalsoppervlak': 'Vår attackyta',
  'Webapplicaties': 'Webbapplikationer',
  'Webapplicatie': 'Webbapplikation',
  'Wat we niet wisten te hebben': 'Det vi inte visste att vi hade',
  'Tekst onder de afbeeldingen': 'Text under bilderna',
  'Titel boven de video': 'Titel ovanför videon',
  'Titel over de afbeelding': 'Titel över bilden',
  'Team Betalen': 'Betalningsteamet',
  'betaalportaal-acc.example.nl': 'betalportal-acc.example.com',
  'https://app.voorbeeld': 'https://app.example',
  'bijv. hertest 2026-07-20, patch toegepast':
      't.ex. omtest 2026-07-20, patch installerad',
  'Titel (H1)': 'Titel (H1)',
  'Subtitel (H2)': 'Underrubrik (H2)',
  'Tussentitel (H1)': 'Avsnittsrubrik (H1)',
  'Ondertitel / toelichting': 'Underrubrik / förklaring',
  'Ondertitel (optioneel)': 'Underrubrik (valfritt)',
  'Titel overlay (optioneel)': 'Titelöverlägg (valfritt)',
  'Tekst (links)': 'Text (vänster)',
  'Bullets links': 'Punkter till vänster',
  'Bullets rechts': 'Punkter till höger',
  'Titeltekstkleur': 'Färg på titeltexten',
  'Knippen': 'Klippning',
  'Geen achtergrondafbeelding': 'Ingen bakgrundsbild',
  'Bijv. 1.0': 'T.ex. 1.0',
  'Datum': 'Datum',
  'Komma-gescheiden, bijv. OWASP WSTG@4.2':
      'Kommaseparerade, t.ex. OWASP WSTG@4.2',
  'Titel van de presentatie': 'Presentationens titel',
  'F-03 · SQL-injectie in het loginformulier':
      'F-03 · SQL-injektion i inloggningsformuläret',
  'https://app.voorbeeld/login': 'https://app.example/login',
  'Deze afbeelding naar het AI-model sturen?':
      'Skicka den här bilden till AI-modellen?',
  'De afbeelding gaat ongewijzigd naar': 'Bilden skickas oförändrad till',
  'OciDeck lakt niets weg in een afbeelding: gezichten, tekst op een schermafdruk en gegevens in beeld gaan mee.':
      'OciDeck maskar ingenting i en bild: ansikten, text i en skärmbild och synliga uppgifter följer med.',
  'De beeldcontrole vond hier een of meer herkenbare gezichten.':
      'Bildkontrollen hittade här ett eller flera igenkännbara ansikten.',
  'Naast de export komen twee bestanden te staan waarmee een ontvanger de redacties kan natrekken.':
      'Bredvid exporten skapas två filer som mottagaren kan använda för att kontrollera maskningarna.',
  'somt op wat er is weggelaten, zonder de waarden zelf. Dit bestand mag met het rapport mee.':
      'räknar upp vad som har utelämnats, utan värdena själva. Den här filen får följa med rapporten.',
  'bevat de sleutels waarmee elke weggelakte waarde is terug te rekenen. Stuur dit bestand niet mee: dan is de redactie ongedaan gemaakt. Bewaar het bij de bron.':
      'innehåller nycklarna som varje maskat värde kan räknas tillbaka med. Skicka inte med den här filen: då är maskningen upphävd. Förvara den vid källan.',
  'slides': 'bilder',
  'Achtergehouden': 'Undanhållen',
  'Achtergehouden: strenger geclassificeerd dan de presentatie':
      'Undanhållen: klassificerad strängare än presentationen',
  '1 slide achtergehouden door haar TLP': '1 bild undanhållen av sin TLP',
  'slides achtergehouden door hun TLP': 'bilder undanhållna av sin TLP',
  'Deze slides gaan niet mee bij presenteren, exporteren of in het pakket. Verhoog het TLP-niveau van de presentatie bij Presentatie-info om ze mee te nemen.':
      'De här bilderna följer inte med vid presentation, export eller i paketet. Höj presentationens TLP-nivå under Presentationsinfo för att få med dem.',
  'Alle slides zijn achtergehouden door hun TLP-classificatie — niets om te tonen.':
      'Alla bilder är undanhållna av sin TLP-klassificering, så det finns inget att visa.',
  'Alle slides zijn achtergehouden door hun TLP-classificatie — niets om te exporteren.':
      'Alla bilder är undanhållna av sin TLP-klassificering, så det finns inget att exportera.',
  'Alle slides zijn overgeslagen of achtergehouden door hun TLP-classificatie — niets om te tonen.':
      'Alla bilder är överhoppade eller undanhållna av sin TLP-klassificering, så det finns inget att visa.',
  'Alle slides zijn overgeslagen of achtergehouden door hun TLP-classificatie — niets om te exporteren.':
      'Alla bilder är överhoppade eller undanhållna av sin TLP-klassificering, så det finns inget att exportera.',
  'Grafiekcijfers zijn niet opgeslagen — ze staan alleen nog in dit venster:':
      'Diagramsiffrorna sparades inte — de finns bara kvar i det här fönstret:',
  'In de browser is er geen crashherstel: sluit je dit tabblad, dan is niet-opgeslagen werk weg. Sla je presentatie zelf op.':
      'I webbläsaren finns ingen kraschåterställning: stänger du den här fliken är osparat arbete borta. Spara din presentation själv.',
  '•  De lokale CVE-database (je start de download zelf): OciDeck haalt de bulkgegevens op via api.github.com en het releasebestand waar dat adres naar wijst.':
      '•  Den lokala CVE-databasen (du startar hämtningen själv): OciDeck hämtar massdata via api.github.com och den utgåvefil som adressen pekar på.',
  '•  CVE opzoeken (staat standaard uit): staat het aan, dan gaat je zoekterm naar de ingestelde CVE-spiegel en, als die niets vindt, naar de Europese database van ENISA en naar MITRE.':
      '•  CVE-sökning (av som standard): när den är på skickas din sökterm till den inställda CVE-spegeln och, om den inte hittar något, till ENISA:s europeiska databas och till MITRE.',
  '•  Een ingesloten YouTube- of Vimeo-video laadt de speler bij die dienst.':
      '•  En inbäddad YouTube- eller Vimeo-video hämtar spelaren från den tjänsten.',
  '•  In de browser: weigert de browser een adres rechtstreeks op te halen, dan probeert OciDeck het via de server waar de app vandaan komt; dat adres komt dan bij die server terecht.':
      '•  I webbläsaren: om webbläsaren vägrar hämta en adress direkt försöker OciDeck igen via den server appen kom från; adressen når då den servern.',
  'Intrekken is niet vastgelegd. Bij de volgende start geldt uw toestemming weer.':
      'Återkallelsen sparades inte. Vid nästa start gäller ditt samtycke igen.',
  'Een tussenkop die een nieuw deel van de presentatie aankondigt. Houd het kort. Voeg via de afbeeldingsbibliotheek een achtergrondbeeld toe.':
      'En mellanrubrik som aviserar en ny del av presentationen. Håll den kort. Lägg till en bakgrundsbild via bildbiblioteket.',
  'Bronnen doorzoeken…': 'Söker i källor…',
  'Niet doorzocht': 'Inte genomsökt',
  'Deze controle draait niet in de webversie: gezichtsherkenning vergt een systeembibliotheek die de browser niet heeft. Gebruik de desktopversie om afbeeldingen op gezichten na te kijken.':
      'Den här kontrollen körs inte i webbversionen: ansiktsigenkänning kräver ett systembibliotek som webbläsaren saknar. Använd skrivbordsversionen för att kontrollera ansikten i bilder.',
  'Het token heeft lees- en schrijfrechten op de repository nodig. Gitea en Forgejo kennen geen server-side zoeken; OciDeck zoekt lokaal.':
      'Token behöver läs- och skrivåtkomst till förvaret. Gitea och Forgejo har ingen sökning på servern; OciDeck söker lokalt.',
  'Het token heeft de repo-scope nodig (of fijnmazig: Contents lezen en schrijven).':
      'Token behöver repo-omfånget (eller finkornigt: Contents läsa och skriva).',
  'Het token heeft read_repository, write_repository en read_api nodig. Server-side zoeken vereist Advanced- of Exact Search.':
      'Token behöver read_repository, write_repository och read_api. Sökning på servern kräver Advanced eller Exact Search.',
  'Snelle server-zoekopdracht — door indexeringsvertraging kan een net gewijzigd deck ontbreken.':
      'Snabb serversökning — på grund av indexeringsfördröjning kan ett nyss ändrat deck saknas.',
  'Media blijft niet bewaard in een los .md-bestand':
      'Media bevaras inte i en vanlig .md-fil',
  'Afbeeldingen, video en audio die je in dit tabblad koos, leven alleen in het geheugen. Een los .md-bestand bewaart ze niet — bij heropenen zijn ze weg. Exporteer als .ocideck-pakket om het beeld mee te nemen.':
      'Bilder, video och ljud som du valde i den här fliken finns bara i minnet. En vanlig .md-fil bevarar dem inte — de är borta när du öppnar den igen. Exportera som ett .ocideck-paket för att ta med dig media.',
  'Media verwijderd om privacyredenen': 'Media borttaget av integritetsskäl',
  'Afbeeldingen door AI laten taggen?': 'Låt AI tagga dessa bilder?',
  'afbeeldingen gaan naar': 'bilder skickas till',
  'een model op dit apparaat': 'en modell på den här enheten',
  'Doorgaan': 'Fortsätt',
  'Ontdekkingen': 'Fynd',
  'Wat is gevonden': 'Vad som hittades',
  'Soort': 'Typ',
  'Dagen onopgemerkt': 'Dagar obemärkt',
  'Ontdekking toevoegen': 'Lägg till fynd',
  'Ontdekking verwijderen': 'Ta bort fynd',
  'Kop van de slide': 'Bildens rubrik',
  'dagen onopgemerkt': 'dagar obemärkt',
  'Nog geen blootstelling ingevuld — de slide toont dan geen kop, alleen de lijst.':
      'Ingen exponering är ifylld ännu — bilden visar då ingen rubrik, bara listan.',
  'Zes ontdekkingen is het maximum; wie er meer noemt maakt een bijlage in plaats van een slide.':
      'Sex fynd är maximum; den som räknar upp fler gör en bilaga i stället för en bild.',
  'Laat de dagen leeg als de eerste blootstelling onbekend is; de slide zegt dan "onbekend" in plaats van nul. Een lege eigenaar leest als "geen eigenaar" en valt rood op.':
      'Lämna dagarna tomma om den första exponeringen är okänd; bilden säger då "okänt" i stället för noll. En tom ansvarig läses som "utan ansvarig" och sticker ut i rött.',
  'Wat de scan vond dat niemand wist te hebben. Per ontdekking hoe lang die onopgemerkt bereikbaar was en wie hem nu bezit; de langste blootstelling is de kop.':
      'Vad skanningen hittade som ingen visste att de hade. Per fynd, hur länge det var nåbart obemärkt och vem som ansvarar nu; den längsta exponeringen är rubriken.',
  'dag': 'dag',
  'maand': 'månad',
  'maanden': 'månader',
  'eigenaar': 'ansvarig',
  'langst onopgemerkt bereikbaar': 'längst nåbar obemärkt',
  'onbekend': 'okänt',
  'onopgemerkt': 'obemärkt',
  'ontdekking': 'fynd',
  'ontdekkingen': 'fynd',
  'Norm en prestatie': 'Mål och utfall',
  'Norm per rij (optioneel)': 'Mål per rad (valfritt)',
  'Bandgrenzen (optioneel)': 'Bandgränser (valfritt)',
  'Open bevindingen': 'Öppna fynd',
  'dagen': 'dagar',
  'was': 'var',
  'Cijfers': 'Nyckeltal',
  'Cijfer': 'Nyckeltal',
  'Niet alles kon worden hersteld. Wat onleesbaar was, is bewaard gebleven.':
      'Allt kunde inte återställas. Det som inte gick att läsa har sparats.',
  'Verdieping': 'Fördjupning',
  'Hoeveel detail?': 'Hur mycket detalj?',
  'Met verdieping': 'Med fördjupning',
  'Beknopt': 'Kortfattat',
  'Het detail achter het verhaal. Deze slide gaat mee in de volledige export en valt weg in de beknopte — los van wie hem mag zien.':
      'Detaljen bakom berättelsen. Den här bilden följer med i den fullständiga exporten och faller bort ur den kortfattade — oberoende av vem som får se den.',
  'Bekijk de foto op ware grootte': 'Visa fotot i full storlek',
  'Azure-sleutel of SAS-token': 'Azure-nyckel eller SAS-token',
  'wachtwoordhash': 'lösenordshash',
  'TOTP-seed (tweede factor)': 'TOTP-frö (andra faktorn)',
  'mogelijk een sleutel of wachtwoord': 'möjligen en nyckel eller ett lösenord',
  'oud btw-nummer (bevat een BSN)':
      'gammalt momsnummer (innehåller personnummer)',
  'vreemdelingennummer (V-nummer)': 'utlänningsnummer (V-nummer)',
  'administratienummer (A-nummer)': 'administrationsnummer (A-nummer)',
  'BIG-nummer van een zorgverlener':
      'registreringsnummer för vårdpersonal (BIG)',
  'AGB-code': 'kod för vårdgivare (AGB)',
  'proces-verbaalnummer': 'diarienummer för polisanmälan',
  'Openen uit…': 'Öppna från…',
  'Opslaan naar…': 'Spara till…',
  'Stel eerst een verbinding in bij Instellingen → Opslag.':
      'Ställ först in en anslutning under Inställningar → Lagring.',
  'Verlopen datums markeren': 'Markera passerade datum',
  'Datums gemarkeerd': 'Datum markerade',
  'Kleurt een cel met een datum van vóór vandaag rood. OciDeck kijkt naar de dag waarop u presenteert, dus een deck dat maanden later terugkomt markeert zichzelf. Alleen jjjj-mm-dd telt als datum. Staat standaard uit.':
      'Färgar en cell med ett datum före i dag rött. OciDeck utgår från dagen du presenterar, så en presentation som återkommer månader senare markerar sig själv. Endast åååå-mm-dd räknas som datum. Av som standard.',
  'Standaarden en methodieken': 'Standarder och metoder',
  'Aanvalsoppervlak': 'Attackyta',
  'Soort toevoegen': 'Lägg till typ',
  'Soort verwijderen': 'Ta bort typ',
  'Soort object': 'Objekttyp',
  'Gevonden': 'Hittade',
  'Kost werk': 'Kräver arbete',
  'werk': 'arbete',
  'nieuw': 'nya',
  'Geen eigenaar': 'Utan ansvarig',
  'geen eigenaar': 'utan ansvarig',
  'objecten in beeld': 'objekt i sikte',
  'Een overzicht draagt hoogstens acht soorten; meer is een inventarislijst en geen overzicht.':
      'En översikt bär högst åtta typer; fler är en inventarielista och ingen översikt.',
  'Een deelgetal is groter dan het totaal van zijn soort. De slide toont het zoals ingevuld — controleer de bron.':
      'En delsumma överstiger totalen för sin typ. Bilden visar den som angiven — kontrollera källan.',
  'De drie laatste zijn deelverzamelingen van het gevonden aantal; OciDeck telt niets zelf, de cijfers komen uit uw scan.':
      'De tre sista är delmängder av det funna antalet; OciDeck räknar inget själv, siffrorna kommer från din skanning.',
  'Het aanvalsoppervlak per soort object: hoeveel er zijn, hoeveel er werk kosten, wat nieuw is en wat niemand bezit. Dat laatste is meestal het gesprek.':
      'Attackytan per objekttyp: hur många det finns, hur många som kräver arbete, vad som är nytt och vad ingen äger. Det sista är oftast samtalet.',
  'Acties en besluiten': 'Åtgärder och beslut',
  'Actie': 'Åtgärd',
  'Deadline': 'Deadline',
  'Stand': 'Status',
  'geen datum': 'inget datum',
  'Besluit gevraagd': 'Beslut krävs',
  'Escalatie': 'Eskalering',
  'Open': 'Öppen',
  'Loopt': 'Pågår',
  'Afgerond': 'Klar',
  'Scorecard': 'Nyckeltalskort',
  'Cijfer toevoegen': 'Lägg till nyckeltal',
  'Cijfer verwijderen': 'Ta bort nyckeltal',
  'Richting': 'Riktning',
  'ongewijzigd': 'oförändrat',
  'Lager is beter': 'Lägre är bättre',
  'Hoger is beter': 'Högre är bättre',
  'Neutraal': 'Neutral',
  'Nu': 'Nu',
  'Vorige rapportage': 'Föregående rapport',
  'Een scorecard toont hoogstens vijf cijfers; meer leest niet meer als een oordeel.':
      'Ett nyckeltalskort visar högst fem tal; fler läses inte längre som ett omdöme.',
  'Laat de vorige rapportage leeg als er nog geen meting was; de slide toont dan geen verandering.':
      'Lämna föregående rapport tom om det ännu inte fanns en mätning; bilden visar då ingen förändring.',
  'Bepaalt of een stijging groen of rood kleurt. De pijl volgt altijd de cijfers.':
      'Avgör om en ökning färgas grön eller röd. Pilen följer alltid siffrorna.',
  'Een paar kerncijfers met het cijfer van de vorige rapportage ernaast, zodat de verandering het verhaal vertelt. Geef per cijfer aan of stijgen goed of slecht nieuws is.':
      'Några nyckeltal med talet från föregående rapport bredvid, så att förändringen berättar historien. Ange för varje tal om en ökning är goda eller dåliga nyheter.',
  'Zekere vondsten als fout behandelen': 'Behandla säkra fynd som fel',
  'Normaal is een zekere vondst — een BSN, een IBAN, een e-mailadres — een waarschuwing die je kunt negeren. Aan maakt er een fout van, en dan kan de export erop blokkeren als je die instelling ook aan hebt staan. Bedoeld voor omgevingen waar zulke gegevens er echt niet doorheen mogen. Onzekere vondsten blijven een waarschuwing.':
      'Normalt är ett säkert fynd — ett personnummer, ett IBAN, en e-postadress — en varning som du kan ignorera. På gör det till ett fel, och då kan exporten blockeras av det om du även har den inställningen på. Avsett för miljöer där sådana uppgifter verkligen inte får slippa igenom. Osäkra fynd förblir en varning.',
  'Medicare-nummer — een zorggegeven': 'Medicare-nummer — en hälsouppgift',
  'bedrijfsnummer': 'företagsnummer',
  'zorgverzekeringsnummer (RAMQ) — een zorggegeven':
      'sjukförsäkringsnummer (RAMQ) — en hälsouppgift',
  'zorgverzekeringsnummer (OHIP) — een zorggegeven':
      'sjukförsäkringsnummer (OHIP) — en hälsouppgift',
  'bedrijfsnummer (BN)': 'företagsnummer (BN)',
  'zorgverlenersnummer (NPI)': 'vårdgivarnummer (NPI)',
  'Medicare-nummer (MBI) — een zorggegeven':
      'Medicare-nummer (MBI) — en hälsouppgift',
  'wacht op verbinding': 'väntar på anslutning',
  'Opgeslagen op deze computer, nog niet in de repository. Gaat mee zodra er weer verbinding is — of nu, met "Wachtrij legen".':
      'Sparat på den här datorn, ännu inte i repositoryt. Det följer med så snart det finns anslutning igen — eller nu, med "Töm kö".',
  'Branch (optioneel)': 'Gren (valfritt)',
  'let op: de standaardbranch is': 'obs: standardgrenen är',
  'jij werkt op': 'du arbetar på',
  'werkgeversnummer (EIN)': 'arbetsgivarnummer (EIN)',
  'laatste vier cijfers van een SSN': 'sista fyra siffrorna i ett SSN',
  'geboortedatum, postcode en geslacht samen — die drie wijzen meestal één persoon aan, ook zonder naam':
      'födelsedatum, postnummer och kön tillsammans — de tre pekar oftast ut en enda person, även utan namn',
  'Het certificaat van deze server wordt niet vertrouwd. Bij een zelf gehoste server kun je het bekijken en vertrouwen bij Instellingen → Opslag.':
      'Certifikatet för denna server är inte betrott. På en egen server kan du visa det och välja att lita på det under Inställningar → Lagring.',
  'Het certificaat van de forge wordt niet vertrouwd. Bij een zelf gehoste forge kun je het bekijken en vertrouwen bij Instellingen → Opslag.':
      'Certifikatet för denna forge är inte betrott. På en egen forge kan du visa det och välja att lita på det under Inställningar → Lagring.',
  'Het certificaat van het endpoint wordt niet vertrouwd. Bij een zelf gehost endpoint kun je het bekijken en vertrouwen bij Instellingen → Opslag.':
      'Certifikatet för denna endpoint är inte betrott. På en egen endpoint kan du visa det och välja att lita på det under Inställningar → Lagring.',
  'Het certificaat van de forge wordt niet vertrouwd — zelfondertekend, verlopen, of op een andere naam gesteld.':
      'Certifikatet för forge är inte betrott — självsignerat, utgånget eller utfärdat till ett annat namn.',
  'Het certificaat van het endpoint wordt niet vertrouwd — zelfondertekend, verlopen, of op een andere naam gesteld.':
      'Certifikatet för endpoint är inte betrott — självsignerat, utgånget eller utfärdat till ett annat namn.',
  'creditcardnummer': 'kreditkortsnummer',
  'beveiligingscode van een creditcard': 'kortets säkerhetskod (CVV)',
  'gegevens in de sprekersnotities — onzichtbaar op de slide, wél in de export':
      'data i anteckningarna — osynliga på bilden, men med i exporten',
  'Certificaat vertrouwen?': 'Lita på det här certifikatet?',
  'Het certificaat van deze server is niet ondertekend door een erkende uitgever. Dat is gewoon bij een zelf gehoste server, maar het is ook hoe een afgeluisterde verbinding eruitziet.':
      'Serverns certifikat är inte signerat av en erkänd utfärdare. Det är normalt för en egen server, men det är också så en avlyssnad anslutning ser ut.',
  'Vergelijk de vingerafdruk hieronder met wat je server zelf toont. Komen ze overeen, dan praat je met de juiste machine.':
      'Jämför fingeravtrycket nedan med det som din server själv visar. Stämmer de överens pratar du med rätt maskin.',
  'Uitgegeven aan': 'Utfärdat till',
  'Uitgegeven door': 'Utfärdat av',
  'Geldig tot': 'Giltigt till',
  'Vingerafdruk (SHA-256)': 'Fingeravtryck (SHA-256)',
  'Alleen dit ene certificaat wordt vertrouwd. Vervangt de server het later, dan vraagt OciDeck het opnieuw.':
      'Endast just detta certifikat betros. Byter servern ut det senare frågar OciDeck igen.',
  'Vertrouwen': 'Lita på',
  'Certificaat bekijken': 'Visa certifikat',
  'De plekken waar je presentaties bewaart en doorzoekt — mappen op deze computer, WebDAV-servers, S3-buckets en git-repositories door elkaar. Sleep ze in de volgorde die jij wilt: de bovenste van een soort geldt als standaard.':
      'Platserna där du sparar och söker dina presentationer — mappar på den här datorn, WebDAV-servrar, S3-buckets och git-repositories om vartannat. Dra dem i den ordning du vill: den översta av ett slag gäller som standard.',
  '•  S3-opslag: verbind je met een bucket, dan worden het endpoint, de bucketnaam en je toegangssleutel bewaard (de geheime sleutel veilig in de sleutelbos van je systeem) en worden de presentaties die je opent of opslaat naar die opslagdienst verstuurd.':
      '•  S3-lagring: när du ansluter till en bucket sparas endpointen, bucketnamnet och din åtkomstnyckel (den hemliga nyckeln säkert i systemets nyckelring) och de presentationer du öppnar eller sparar skickas till den lagringstjänsten.',
  '•  Git-opslag: verbind je met een repository, dan wordt je toegangstoken bewaard (veilig in de sleutelbos van je systeem) en worden de presentaties die je opslaat als commits naar die server verstuurd. Een werkkopie van de repository blijft onversleuteld op dit apparaat staan.':
      '•  Git-lagring: när du ansluter till ett repository sparas din åtkomsttoken (säkert i systemets nyckelring) och de presentationer du sparar skickas till den servern som commits. En arbetskopia av repositoryt ligger kvar okrypterad på den här enheten.',
  'Voor de taal van dit deck ontbreken de ziekte- en aandoeningsnamen. Religie, politieke overtuiging en vakbondstermen worden wel herkend, en controlegetallen (BSN, IBAN, paspoort) werken altijd — maar reken er niet op dat een diagnose gevonden wordt.':
      'Sjukdomsnamn saknas för det här däckets språk. Religion, politisk uppfattning och fackliga termer känns igen, och mönster med kontrollsiffra (personnummer, IBAN, pass) fungerar alltid — men räkna inte med att en diagnos hittas.',
  'niet getest': 'inte testad',
  'Werkte op': 'Fungerade den',
  'Je bent aangemeld, maar hebt hier geen toegang. Je wachtwoord is niet het probleem — vraag de beheerder om rechten op deze map.':
      'Du är inloggad, men har ingen åtkomst här. Ditt lösenord är inte problemet — be administratören om rättigheter till den här mappen.',
  'Je token is geldig, maar mag dit niet. Geef het meer rechten, of wacht als de forge een limiet oplegt.':
      'Din token är giltig, men får inte göra detta. Ge den fler rättigheter, eller vänta om forgen tillämpar en gräns.',
  'Het token is geldig, maar mag dit niet — geef het meer rechten op de repository.':
      'Token är giltig, men får inte göra detta — ge den fler rättigheter till repositoryt.',
  'Aangemeld, maar geen toegang — je wachtwoord is niet het probleem. Vraag rechten op deze map.':
      'Inloggad, men ingen åtkomst — ditt lösenord är inte problemet. Be om rättigheter till den här mappen.',
  'Dit lijkt een volledige DAV-URL. Bij Nextcloud leidt OciDeck dat pad zelf af — hier hoort alleen de server te staan.':
      'Det här ser ut som en fullständig DAV-URL. För Nextcloud härleder OciDeck den sökvägen själv — här hör bara servern hemma.',
  'Overnemen': 'Tillämpa',
  'WebDAV is niet (goed) ingesteld — controleer de servergegevens bij Instellingen → Opslag.':
      'WebDAV är inte (rätt) konfigurerat — kontrollera serveruppgifterna under Inställningar → Lagring.',
  'De git-repository is niet (goed) ingesteld — controleer server, eigenaar en repository bij Instellingen → Opslag.':
      'Git-repositoryt är inte (rätt) konfigurerat — kontrollera server, ägare och repository under Inställningar → Lagring.',
  'De servernaam van de forge bestaat niet, of is niet op te zoeken. Controleer de server-URL op een typefout.':
      'Forgens servernamn finns inte eller går inte att slå upp. Kontrollera server-URL:en för ett skrivfel.',
  'Deze forge heeft een privé- of LAN-adres. Markeer hem als vertrouwd intern bij Instellingen → Opslag.':
      'Den här forgen har en privat adress eller LAN-adress. Markera den som betrodd intern under Inställningar → Lagring.',
  'De forge is niet bereikbaar — controleer je verbinding en de server-URL.':
      'Forgen går inte att nå — kontrollera din anslutning och server-URL:en.',
  'Aanmelden bij de forge mislukt. Controleer je token: het heeft leesrechten op de repository nodig, en schrijfrechten om op te slaan.':
      'Inloggningen till forgen misslyckades. Kontrollera din token: den behöver läsbehörighet till repositoryt och skrivbehörighet för att spara.',
  'Niet gevonden in de repository — of je token mag het niet zien.':
      'Hittades inte i repositoryt — eller så får din token inte se det.',
  'De forge gaf een fout. Probeer het later opnieuw.':
      'Forgen returnerade ett fel. Försök igen senare.',
  'Dit adres antwoordt niet als een forge. Klopt de soort forge bij Instellingen → Opslag?':
      'Den här adressen svarar inte som en forge. Stämmer forge-typen under Inställningar → Lagring?',
  'Stel eerst een WebDAV-server in bij Instellingen → Opslag.':
      'Konfigurera först en WebDAV-server under Inställningar → Lagring.',
  'Nodig wanneer de forge op een privé- of thuisnetwerk draait. Zonder deze vlag weigert de beveiliging een privé-adres.':
      'Behövs när forgen körs på ett privat nätverk eller hemnätverk. Utan denna flagga avvisar säkerhetskontrollen en privat adress.',
  'Vul server-URL, eigenaar en repository in':
      'Fyll i server-URL, ägare och repository',
  'de standaardbranch heet': 'standardgrenen heter',
  'die wordt voortaan gebruikt': 'den används hädanefter',
  'de repository is nog leeg; de eerste opslag vult hem':
      'repositoryt är fortfarande tomt; den första sparningen fyller det',
  'let op: dit token mag alleen lezen, dus opslaan zal mislukken':
      'obs: denna token får bara läsa, så det kommer inte att gå att spara',
  'Aanmelden mislukt — controleer het token. Het heeft leesrechten op de repository nodig, en schrijfrechten om te kunnen opslaan.':
      'Inloggningen misslyckades — kontrollera token. Den behöver läsbehörighet till repositoryt och skrivbehörighet för att kunna spara.',
  'Repository niet gevonden — of je token mag hem niet zien. Controleer eigenaar en repositorynaam.':
      'Repositoryt hittades inte — eller så får din token inte se det. Kontrollera ägare och repository-namn.',
  'Dit adres antwoordt niet als een forge. Klopt de soort forge die je hebt gekozen?':
      'Den här adressen svarar inte som en forge. Stämmer den forge-typ du valt?',
  'kenteken': 'registreringsnummer',
  'Voor de taal van dit deck is er geen trefwoordenlijst voor bijzondere persoonsgegevens. Patronen met een controlegetal (BSN, IBAN, paspoort) werken wel; woorden als "diagnose" of "verdachte" worden niet herkend.':
      'Det finns ingen nyckelordslista för särskilda kategorier av personuppgifter på det här däckets språk. Mönster med kontrollsiffra (personnummer, IBAN, pass) fungerar; ord som "diagnos" eller "misstänkt" känns inte igen.',
  'Landpakketten voor identificatienummers':
      'Landspaket för identifikationsnummer',
  'Nummers als het BSN of het PESEL zijn landgebonden. Heel Europa staat aan omdat de meeste van die nummers een controlegetal hebben: die aanzetten kost vrijwel geen valse meldingen. IBAN, e-mail, geheimen en paspoortstroken staan hier los van en worden altijd nagekeken.':
      'Nummer som nederländska BSN eller polska PESEL är landsspecifika. Hela Europa är på eftersom de flesta av de numren har en kontrollsiffra: att slå på dem kostar nästan inga falska larm. IBAN, e-post, hemligheter och passrader är oberoende av detta och kontrolleras alltid.',
  'strafrechtelijk gegeven (verdachte)': 'straffrättslig uppgift (misstänkt)',
  'strafrechtelijk gegeven (aangever of slachtoffer)':
      'straffrättslig uppgift (anmälare eller offer)',
  'strafrechtelijk gegeven (getuige)': 'straffrättslig uppgift (vittne)',
  'diagnosecode (ICD-10)': 'diagnoskod (ICD-10)',
  'geneesmiddelcode (ATC)': 'läkemedelskod (ATC)',
  'geboortedatum': 'födelsedatum',
  'locatiecoördinaten': 'platskoordinater',
  'MAC-adres van een apparaat': 'MAC-adress för en enhet',
  'IMEI van een toestel': 'IMEI för en telefon',
  'ICCID van een simkaart': 'ICCID för ett SIM-kort',
  'IMSI van een abonnee': 'IMSI för en abonnent',
  'sociale-mediaprofiel': 'profil i sociala medier',
  'advertentie- of apparaat-ID': 'annons- eller enhets-id',
  'IP-adres': 'IP-adress',
  'machineleesbare zone van een paspoort of ID':
      'maskinläsbar zon i ett pass eller id-kort',
  'De endpoint-naam bestaat niet, of is niet op te zoeken. Controleer het endpoint op een typefout.':
      'Ändpunktsnamnet finns inte eller går inte att slå upp. Kontrollera ändpunkten för ett skrivfel.',
  'De endpoint-naam bestaat niet. Controleer het endpoint op een typefout.':
      'Ändpunktsnamnet finns inte. Kontrollera ändpunkten för ett skrivfel.',
  'De servernaam bestaat niet, of is niet op te zoeken. Controleer de server-URL op een typefout.':
      'Servernamnet finns inte eller går inte att slå upp. Kontrollera server-URL:en för ett skrivfel.',
  'Deze server heeft een privé- of LAN-adres. Markeer hem als vertrouwd intern bij Instellingen → Opslag.':
      'Den här servern har en privat adress eller LAN-adress. Markera den som betrodd intern under Inställningar → Lagring.',
  'De server stuurt door naar een ander adres. Vul dat adres rechtstreeks in — een omleiding volgen we niet, want die kan de veiligheidscontrole omzeilen.':
      'Servern omdirigerar till en annan adress. Ange den adressen direkt — vi följer inte omdirigeringar, eftersom de kan kringgå säkerhetskontrollen.',
  'De servernaam bestaat niet. Controleer de server-URL op een typefout.':
      'Servernamnet finns inte. Kontrollera server-URL:en för ett skrivfel.',
  'Het certificaat van de server wordt niet vertrouwd — zelfondertekend, verlopen, of op een andere naam gesteld.':
      'Serverns certifikat är inte betrott — självsignerat, utgånget eller utfärdat till ett annat namn.',
  'De server stuurt door naar een ander adres. Vul dat adres hier in.':
      'Servern omdirigerar till en annan adress. Ange den adressen här.',
  'Opslaan in de sleutelhanger is mislukt. De verbinding blijft om je wachtwoord vragen tot dit lukt.':
      'Det gick inte att spara i nyckelringen. Anslutningen fortsätter att fråga efter ditt lösenord tills det lyckas.',
  'Sla de presentatie op om een kopie te maken.':
      'Spara presentationen för att skapa en kopia.',
  ': ligt buiten de presentatie en gaat niet mee (':
      ': ligger utanför presentationen och följer inte med (',
  'Bestand niet gevonden': 'Filen hittades inte',
  'Weg na herladen': 'Borta efter omladdning',
  'Nog niet opgeslagen': 'Inte sparat ännu',
  'Buiten de presentatie': 'Utanför presentationen',
  'Van internet': 'Från internet',
  'Alleen in deze sessie': 'Endast i den här sessionen',
  'Dit bestand is al gekopieerd en staat veilig. Het krijgt zijn plek in de presentatiemap zodra u opslaat.':
      'Den här filen är redan kopierad och ligger säkert. Den får sin plats i presentationsmappen så snart du sparar.',
  'Dit bestand ligt buiten de presentatiemap en gaat niet mee. Wie de presentatie van u krijgt, ziet hier niets. Sla op om een kopie te maken.':
      'Den här filen ligger utanför presentationsmappen och följer inte med. Den som får presentationen av dig ser ingenting här. Spara för att skapa en kopia.',
  'Dit bestand staat op internet en hoort niet bij de presentatie. Zonder verbinding, of als de bron verdwijnt, is het weg.':
      'Den här filen ligger på internet och hör inte till presentationen. Utan uppkoppling, eller om källan försvinner, är den borta.',
  'In de webversie blijft dit bestand alleen in het geheugen van deze sessie. Na het herladen van de pagina is het weg.':
      'I webbversionen finns den här filen bara i den här sessionens minne. När sidan laddas om är den borta.',
  'Open en bewaar presentaties in een S3-bucket: AWS S3, of een S3-compatible dienst zoals een eigen MinIO. De secret access key wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.':
      'Öppna och förvara presentationer i en S3-hink: AWS S3 eller en S3-kompatibel tjänst som en egen MinIO. Den hemliga åtkomstnyckeln sparas krypterad i nyckelringen, inte tillsammans med övriga inställningar.',
  'Openen vanuit S3': 'Öppna från S3',
  'Afbeelding kiezen in S3': 'Välj en bild i S3',
  'Opslaan naar S3': 'Spara till S3',
  'Opgeslagen in S3:': 'Sparad i S3:',
  'Hier staat niets': 'Här finns ingenting',
  'Endpoint niet bereikbaar — controleer je verbinding en het endpoint.':
      'Slutpunkten kan inte nås — kontrollera anslutningen och slutpunkten.',
  'Aanmelden mislukt. Controleer de access key, de secret key en de regio — een verkeerde regio geeft dezelfde fout als een verkeerde sleutel.':
      'Inloggningen misslyckades. Kontrollera åtkomstnyckeln, den hemliga nyckeln och regionen — fel region ger samma fel som fel nyckel.',
  'Het endpoint gaf een fout. Probeer het later opnieuw.':
      'Slutpunkten returnerade ett fel. Försök igen senare.',
  'Dit endpoint kan niet voorwaardelijk schrijven, dus je werk is niet beschermd tegen dat van een ander. Sla op onder een nieuwe naam als er iemand anders aan dit deck werkt.':
      'Den här slutpunkten kan inte skriva villkorligt, så ditt arbete skyddas inte mot någon annans. Spara under ett nytt namn om någon annan arbetar med den här presentationen.',
  'Stel eerst een S3-bucket in bij Instellingen → Opslag.':
      'Ställ först in en S3-hink under Inställningar → Lagring.',
  'De S3-bucket is niet (goed) ingesteld — controleer endpoint, bucket en sleutels bij Instellingen → Opslag.':
      'S3-hinken är inte (rätt) konfigurerad — kontrollera slutpunkt, hink och nycklar under Inställningar → Lagring.',
  'Dit endpoint is niet toegestaan. Markeer een privé/LAN-endpoint eerst als vertrouwd bij Instellingen → Opslag.':
      'Den här slutpunkten är inte tillåten. Markera först en privat/LAN-slutpunkt som betrodd under Inställningar → Lagring.',
  'Niet gevonden in de bucket. Klopt de bucketnaam, probeer dan de andere adressering bij Instellingen → Opslag.':
      'Hittades inte i hinken. Om namnet stämmer, prova den andra adresseringen under Inställningar → Lagring.',
  'S3-bucket': 'S3-hink',
  'Een S3-bucket, bijvoorbeeld AWS S3 of een eigen MinIO-server.':
      'En S3-hink, till exempel AWS S3 eller en egen MinIO-server.',
  'Endpoint': 'Slutpunkt',
  'Bucket': 'Hink',
  'Adressering': 'Adressering',
  'Bucket in de hostnaam (AWS S3)': 'Hink i värdnamnet (AWS S3)',
  'Bucket in het pad (MinIO en andere)': 'Hink i sökvägen (MinIO och andra)',
  'Regio': 'Region',
  'Access key ID': 'Åtkomstnyckel-ID',
  'Secret access key': 'Hemlig åtkomstnyckel',
  'Prefix (optioneel)': 'Prefix (valfritt)',
  'Vertrouwd intern endpoint': 'Betrodd intern slutpunkt',
  'Nodig wanneer het endpoint op een privé- of thuisnetwerk (LAN) draait, zoals een eigen MinIO. Sta alleen verbindingen toe naar servers die je zelf vertrouwt.':
      'Behövs när slutpunkten körs på ett privat eller hemnätverk (LAN), som en egen MinIO. Tillåt bara anslutningar till servrar du själv litar på.',
  'Vul endpoint, bucket en access key ID in':
      'Fyll i slutpunkt, hink och åtkomstnyckel-ID',
  'Aanmelden mislukt — controleer de access key, de secret key en de regio. Een verkeerde regio geeft dezelfde fout als een verkeerde sleutel.':
      'Inloggningen misslyckades — kontrollera åtkomstnyckeln, den hemliga nyckeln och regionen. Fel region ger samma fel som fel nyckel.',
  'Het endpoint staat op een privé-adres. Vink "Vertrouwd intern endpoint" aan om verbinding toe te staan.':
      'Slutpunkten ligger på en privat adress. Kryssa i "Betrodd intern slutpunkt" för att tillåta anslutningen.',
  'Bucket niet gevonden. Bij een eigen MinIO helpt het vaak om "Bucket in het pad" te kiezen.':
      'Hinken hittades inte. Med en egen MinIO hjälper det ofta att välja "Hink i sökvägen".',
  'Ongeldig endpoint': 'Ogiltig slutpunkt',
  'Dit endpoint ondersteunt geen voorwaardelijk schrijven; gelijktijdig bewerken is hier slechter beschermd.':
      'Den här slutpunkten stöder inte villkorliga skrivningar; samtidig redigering är sämre skyddad här.',
  'Naar de slide': 'Gå till bilden',
  'De git-verbinding van dit deck bestaat niet meer.':
      'Git-anslutningen för den här presentationen finns inte längre.',
  'Stel eerst een git-repository in bij Instellingen → Opslag.':
      'Ställ först in ett git-arkiv under Inställningar → Lagring.',
  'Deze afbeelding toont minstens één herkenbaar gezicht.':
      'Den här bilden visar minst ett igenkännbart ansikte.',
  'Deze afbeelding toont minstens {count} herkenbare gezichten.':
      'Den här bilden visar minst {count} igenkännbara ansikten.',
  'Deze afbeelding kon niet worden nagekeken op gezichten. Het formaat wordt niet ondersteund (HEIC bijvoorbeeld). Dat betekent niet dat er niemand op staat — er is niet gekeken.':
      'Den här bilden kunde inte kontrolleras efter ansikten. Formatet stöds inte (till exempel HEIC). Det betyder inte att ingen finns på den — det betyder att ingen har tittat.',
  'Een afbeelding waarop iemand herkenbaar staat is een persoonsgegeven, ook zonder naam erbij.':
      'En bild där någon är igenkännbar är en personuppgift, även utan namn.',
  'herkenbaar gezicht op een afbeelding': 'igenkännbart ansikte på en bild',
  'Afbeeldingen nakijken op herkenbare gezichten':
      'Kontrollera bilder efter igenkännbara ansikten',
  'Een afbeelding waarop iemand herkenbaar staat is een persoonsgegeven, ook zonder naam erbij. Dit is de zwaarste controle: elke afbeelding wordt lokaal doorgerekend. Er wordt geteld of er een gezicht op staat — nooit wie het is, en er wordt niets opgeslagen.':
      'En bild där någon är igenkännbar är en personuppgift, även utan namn. Det här är den tyngsta kontrollen: varje bild bearbetas lokalt. Det räknas om ett ansikte finns — aldrig vems, och ingenting sparas.',
  'Geen meldingen meer op deze slide.':
      'Inga meddelanden kvar på den här bilden.',
  'Kwaliteitsproblemen geaccepteerd': 'Kvalitetsproblem accepterade',
  'Mogelijk persoonsgegevens': 'Möjligen personuppgifter',
  'Persoonsgegevens geaccepteerd': 'Personuppgifter accepterade',
  'Persoonsgegevens gevonden': 'Personuppgifter hittades',
  'Organisatie': 'Organisation',
  'Welke verbinding?': 'Vilken anslutning?',
  'Bestandsverbindingen': 'Filanslutningar',
  'Een git-repository; elke opgeslagen versie blijft bewaard.':
      'Ett git-arkiv; varje sparad version bevaras.',
  'Een map op de schijf van deze computer.': 'En mapp på den här datorns disk.',
  'Een map op een WebDAV-server, bijvoorbeeld Nextcloud.':
      'En mapp på en WebDAV-server, till exempel Nextcloud.',
  'Instellingen tonen': 'Visa inställningar',
  'Instellingen verbergen': 'Dölj inställningar',
  'Map op deze computer': 'Mapp på den här datorn',
  'Naam van deze verbinding': 'Namn på den här anslutningen',
  'Nog geen verbinding — voeg er hieronder een toe.':
      'Ingen anslutning ännu — lägg till en nedan.',
  'Sleep om de volgorde te wijzigen': 'Dra för att ändra ordningen',
  'Verbinding toevoegen': 'Lägg till anslutning',
  'Verbinding verwijderen': 'Ta bort anslutning',
  'WebDAV-server': 'WebDAV-server',
  'Iemand anders heeft dit bestand gewijzigd':
      'Någon annan har ändrat den här filen',
  'Sinds je dit deck opende is de versie op de server veranderd. Overschrijven maakt het werk van de ander ongedaan.':
      'Versionen på servern har ändrats sedan du öppnade den här presentationen. Att skriva över kastar bort den andras arbete.',
  'Overschrijven': 'Skriv över',
  'Openen vanaf WebDAV': 'Öppna från WebDAV',
  'Opslaan naar WebDAV': 'Spara till WebDAV',
  'Opgeslagen op WebDAV:': 'Sparad till WebDAV:',
  'Afbeelding kiezen op WebDAV': 'Välj bild på WebDAV',
  'Servertype': 'Servertyp',
  'Nextcloud of ownCloud': 'Nextcloud eller ownCloud',
  'Andere WebDAV-server': 'Annan WebDAV-server',
  'WebDAV-bron': 'WebDAV-källa',
  'Open en bewaar presentaties in een map op een WebDAV-server. Het wachtwoord wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.':
      'Öppna och spara presentationer i en mapp på en WebDAV-server. Lösenordet lagras krypterat i nyckelringen, inte tillsammans med de övriga inställningarna.',
  'Open en bewaar presentaties in een map op een WebDAV-server.':
      'Öppna och spara presentationer i en mapp på en WebDAV-server.',
  'Het pad in de server-URL is de WebDAV-wortel.':
      'Sökvägen i server-URL:en är WebDAV-roten.',
  'Repareer slide': 'Åtgärda bild',
  'Voortzetting van vorige slide': 'Fortsättning på föregående bild',
  'Deze slide hoort bij de lijst van de vorige slide en deelt daarmee één lettergrootte: die van de volste pagina.':
      'Den här bilden hör till föregående bilds lista och delar därför en teckenstorlek: den från den fylligaste sidan.',
  'Deze slide rendert op {klein} van de ontwerpgrootte in plaats van {eigen}, omdat hij een gesplitste reeks deelt met de veel vollere slide {pagina}.':
      'Den här bilden visas i {klein} av designstorleken i stället för {eigen}, eftersom den delar en uppdelad serie med den mycket fylligare bilden {pagina}.',
  'Niet de tekst op deze slide is het probleem, maar de reeks.':
      'Det är inte texten på den här bilden som är problemet, utan serien.',
  'Haal volle pagina uit de reeks': 'Ta bort full sida ur serien',
  'Opslag': 'Lagring',
  'Opslagwijzen': 'Lagringssätt',
  'Ingesteld': 'Konfigurerad',
  'Niet ingesteld': 'Inte konfigurerad',
  'MASWE-zwakheid kiezen': 'Välj en MASWE-svaghet',
  'Zoek op naam, id of categorie': 'Sök på namn, id eller kategori',
  'Geen zwakheid gevonden': 'Ingen svaghet hittades',
  'Getalnotatie herkennen': 'Känn igen talformatet',
  'In dit bestand staan getallen waarvan de komma op twee manieren te lezen is:':
      'Den här filen innehåller tal där kommatecknet kan läsas på två sätt:',
  'Duizendtalscheiding': 'Tusentalsavgränsare',
  'Decimaalteken': 'Decimaltecken',
  'Grafiekdata kon niet worden gelezen; die grafieken blijven leeg:':
      'Diagramdata kunde inte läsas; de diagrammen förblir tomma:',
  'Bijlage hulpmiddelen invoegen…': 'Infoga bilaga med verktyg…',
  'Gebruikte hulpmiddelen': 'Använda verktyg',
  'Hulpmiddel': 'Verktyg',
  'Referentie': 'Referens',
  'Eén per regel, bijv. Burp Suite@2026.4 | https://portswigger.net | Webproxy':
      'Ett per rad, t.ex. Burp Suite@2026.4 | https://portswigger.net | Webbproxy',
  'Nog geen hulpmiddelen vastgelegd — vul ze in bij Presentatie-info.':
      'Inga verktyg registrerade än — ange dem under Presentationsinfo.',
  'Bijlage met hulpmiddelen toegevoegd.': 'Bilaga med verktyg tillagd.',
  'Bijlage toegevoegd, maar niet elk hulpmiddel heeft beschrijving, versie én referentie:':
      'Bilaga tillagd, men alla verktyg har inte beskrivning, version och referens:',
  'Meegeleverde versies invullen': 'Fyll i medföljande versioner',
  'vastgelegd': 'registrerad',
  'nu beschikbaar': 'nu tillgänglig',
  'Er is inmiddels een nieuwere versie van een standaard waartegen is getoetst:':
      'En standard som testats mot har nu en nyare version:',
  'Dat hoeft niet fout te zijn — het onderzoek is uitgevoerd toen die versie gold. Het rapport legt vast wat er echt is gebruikt.':
      'Det behöver inte vara fel — testet gjordes när den versionen gällde. Rapporten registrerar vad som faktiskt användes.',
  'geen versienummer': 'inget versionsnummer',
  'Bron': 'Källa',
  'De versies die in dit exemplaar zitten. Een pentestrapport hoort te vermelden waartegen is getoetst — en welke versie dat was.':
      'Versionerna i detta exemplar. En pentestrapport ska ange vad som testats mot — och vilken version det var.',
  'waarde(n) uit de CSV zijn niet als getal gelezen en staan nu op 0:':
      'värde(n) från CSV-filen lästes inte som tal och är nu 0:',
  'Zoeken in alle decks…': 'Sök i alla decks…',
  'Zoeken in alle decks': 'Sök i alla decks',
  'Zoekterm': 'Sökterm',
  'Niets gevonden.': 'Inget hittades.',
  'vindplaatsen': 'förekomster',
  'deck-eigenschappen': 'deckegenskaper',
  'Er zijn meer treffers dan hier passen; verfijn de zoekterm.':
      'Det finns fler träffar än vad som får plats här; förfina söktermen.',
  'Niet doorzocht, want onleesbaar:': 'Inte genomsökt, eftersom oläsbar:',
  'Afbeeldingen in de repository…': 'Bilder i repositoryt…',
  'Afbeeldingen in de repository': 'Bilder i repositoryt',
  'afbeeldingen in de gedeelde pool': 'bilder i den delade poolen',
  'De pool is nog leeg.': 'Poolen är fortfarande tom.',
  'alleen nog in een uitgebrachte versie:': 'bara i en utgiven version nu:',
  'nergens meer gevonden': 'hittas inte längre någonstans',
  'Niet te zeggen wat ongebruikt is: dit kon niet gelezen worden —':
      'Kan inte avgöra vad som är oanvänt: detta gick inte att läsa —',
  'Elke afbeelding wordt ergens gebruikt.': 'Varje bild används någonstans.',
  'afbeeldingen worden nergens meer aangehaald — ook niet in een uitgebrachte versie. Dit is een voorstel, geen oordeel: op een andere branch kunnen ze nog in gebruik zijn.':
      'bilder refereras inte längre någonstans — inte ens i en utgiven version. Det är ett förslag, inte en dom: de kan fortfarande användas på en annan gren.',
  'Soort forge': 'Typ av forge',
  'Forgejo of Gitea': 'Forgejo eller Gitea',
  'Iemand anders had dit deck ook bewerkt — samengevoegd en opgeslagen.':
      'Någon annan hade också redigerat det här decket — sammanfogat och sparat.',
  'Keuzes toegepast — sla op om ze vast te leggen.':
      'Valen tillämpade — spara för att registrera dem.',
  'Allebei bewerkt — kies per slide': 'Båda har redigerat — välj per bild',
  'Iemand anders bewerkte dit deck tegelijk met jou. Alles wat vanzelf kon is al samengevoegd; deze slides niet.':
      'Någon annan redigerade det här decket samtidigt som du. Allt som kunde sammanfogas automatiskt har redan sammanfogats; inte de här bilderna.',
  'Mijn versie': 'Min version',
  'Hun versie': 'Deras version',
  'Vergelijken…': 'Jämför…',
  'Versies vergelijken': 'Jämför versioner',
  'Kies twee versies; de oudste van de twee is het vertrekpunt.':
      'Välj två versioner; den äldre av de två är utgångspunkten.',
  'Vergelijken': 'Jämför',
  'Deze twee versies zijn inhoudelijk gelijk.':
      'De här två versionerna har samma innehåll.',
  'verwijderd': 'borttagen',
  'gewijzigd': 'ändrad',
  'verplaatst': 'flyttad',
  '(zonder titel)': '(utan titel)',
  'Concept mergen…': 'Slå ihop utkast…',
  'Versie vastleggen…': 'Registrera version…',
  'Concept gemerged naar de hoofdbranch.':
      'Utkastet sammanfogades med huvudgrenen.',
  'Nog geen review — breng het concept eerst uit ter review.':
      'Ingen granskning ännu — skicka först utkastet för granskning.',
  'Er is geen concept om te mergen.': 'Det finns inget utkast att slå ihop.',
  'Mergen mislukt:': 'Sammanfogning misslyckades:',
  'Versie vastgelegd:': 'Version registrerad:',
  'Vastleggen geblokkeerd door het classificatiebeleid.':
      'Registrering blockerad av klassificeringspolicyn.',
  'Ongeldige versie — gebruik vX, bijvoorbeeld v1.0.':
      'Ogiltig version — använd vX, till exempel v1.0.',
  'Geen deck om vast te leggen.': 'Inget deck att registrera.',
  'Vastleggen mislukt:': 'Registrering misslyckades:',
  'Concept mergen': 'Slå ihop utkast',
  'Voegt de review-PR van dit concept samen met de hoofdbranch.':
      'Slår ihop det här utkastets gransknings-PR med huvudgrenen.',
  'Concept-branch opruimen na het mergen':
      'Ta bort utkastgrenen efter sammanfogning',
  'Mergen': 'Slå ihop',
  'Versie vastleggen': 'Registrera version',
  'Zet een release-tag op de kop van de hoofdbranch — de versie die je hebt gepresenteerd.':
      'Sätter en utgåvetagg på huvudgrenens spets — versionen du presenterade.',
  'Gebruik vX, bijvoorbeeld v1.0.': 'Använd vX, till exempel v1.0.',
  'Vastleggen': 'Registrera',
  'Uitbrengen ter review…': 'Skicka för granskning…',
  'Uitbrengen ter review': 'Skicka för granskning',
  'Opent een pull request van je concept naar de hoofdbranch, zodat het beoordeeld kan worden vóór het uitkomt.':
      'Öppnar en pull request från ditt utkast till huvudgrenen, så att den kan granskas innan den publiceras.',
  'Toelichting': 'Detaljer',
  'Wat is er veranderd en waarom?': 'Vad ändrades och varför?',
  'Uitbrengen': 'Skicka',
  'Uitgebracht ter review:': 'Skickad för granskning:',
  'Uitbrengen geblokkeerd door het classificatiebeleid.':
      'Publicering blockerad av klassificeringspolicyn.',
  'Er is nog geen concept om uit te brengen — sla eerst een wijziging op.':
      'Det finns inget utkast att skicka ännu — spara en ändring först.',
  'Uitbrengen mislukt:': 'Inlämning misslyckades:',
  'Overzicht': 'Översikt',
  'Veelgestelde vragen': 'Vanliga frågor',
  'Probleemoplossing': 'Felsökning',
  'Begrippenlijst': 'Ordlista',
  'Prestaties': 'Prestanda',
  'Beveiligingsontwerp': 'Säkerhetsdesign',
  'Hosting en uitrol': 'Värdtjänst och driftsättning',
  'Bijdragen': 'Bidra',
  'Migratiegids': 'Migreringsguide',
  'Versies…': 'Versioner…',
  'Versies:': 'Versioner:',
  'Nog geen uitgebrachte versies van dit deck.':
      'Inga utgivna versioner av detta deck än.',
  'Horizontale gestapelde staaf': 'Liggande staplad stapel',
  'Git-geschiedenis…': 'Git-historik…',
  'Git-geschiedenis:': 'Git-historik:',
  'Nog geen commits voor dit deck.': 'Inga commits för detta deck än.',
  'Gepusht': 'Pushad',
  'Nog niet gepusht': 'Inte pushad än',
  'Gesynchroniseerd met git.': 'Synkroniserat med git.',
  'Nog geen verbinding — het gaat later mee.':
      'Ingen anslutning än — det skickas senare.',
  'De branch is verzet; je commits staan lokaal klaar.':
      'Grenen har flyttats; dina commits är klara lokalt.',
  'Synchroniseren mislukt.': 'Synkroniseringen misslyckades.',
  'Native git gevonden:': 'Native git hittat:',
  'Native git: bezig met detecteren…': 'Native git: identifierar…',
  'Native git: niet gevonden — het REST-pad wordt gebruikt':
      'Native git: hittades inte — REST-vägen används',
  'echte offline-historie mogelijk': 'äkta offlinehistorik möjlig',
  'Nu synchroniseren': 'Synkronisera nu',
  'Gesynchroniseerd:': 'Synkroniserade:',
  'nog in de wachtrij:': 'fortfarande i kö:',
  'Niets in de wachtrij.': 'Inget i kön.',
  'Opgeslagen — gaat mee zodra er weer verbinding is.':
      'Sparat — synkroniseras så snart du är online igen.',
  'Deknaam': 'Decknamn',
  'Wordt de map decks/<naam> in de repository':
      'Blir mappen decks/<namn> i repot',
  'Alleen letters, cijfers, punt, streep en liggend streepje':
      'Endast bokstäver, siffror, punkt, bindestreck och understreck',
  'Commitboodschap': 'Commit-meddelande',
  'Wat is er veranderd?': 'Vad har ändrats?',
  'Opslaan naar git': 'Spara till git',
  'Opgeslagen in git:': 'Sparat till git:',
  'De branch is verplaatst; herlaad het deck en sla opnieuw op.':
      'Grenen har flyttats; ladda om decket och spara igen.',
  'Bijgewerkt met OciDeck': 'Uppdaterad med OciDeck',
  'Git-repository': 'Git-repository',
  'Open presentaties uit een git-repository. Elke opgeslagen versie blijft bewaard. Het token wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.':
      'Öppna presentationer från ett Git-repository. Varje sparad version bevaras. Token lagras krypterad i nyckelringen, inte tillsammans med övriga inställningar.',
  'Eigenaar': 'Ägare',
  'Repository': 'Repository',
  'Personal access token': 'Personlig åtkomsttoken',
  'Presentatie openen uit git': 'Öppna en presentation från Git',
  'Geen presentaties in deze repository.':
      'Inga presentationer i detta repository.',
  'Rapportagetaal': 'Rapportspråk',
  'Niet vastgelegd': 'Inte angivet',
  'Rapportageslides en referentiedata voor informatieveiligheid: bevindingen, checklists, scope-matrices en ondertekening. Gestructureerd volgens MIAUW en breed inzetbaar voor pentests, audits en veiligheidsonderzoek. De referentiegegevens zitten in de app zelf, dus de module werkt meteen en volledig offline.':
      'Rapporteringsslides och referensdata för informationssäkerhet: fynd, checklistor, scope-matriser och godkännande. Strukturerad enligt MIAUW och brett användbar för pentester, revisioner och säkerhetsundersökningar. Referensdata finns i själva appen, så modulen fungerar direkt och helt offline.',
  'Optionele modules. Standaard uit; ze blijven verborgen tot u ze inschakelt.':
      'Valfria moduler. Av som standard; de förblir dolda tills du aktiverar dem.',
  'Dit project is bijvangst van de Pilot Informatieautonomie.':
      'Det här projektet är en biprodukt av Pilot Informatieautonomie.',
  'Stijlprofiel exporteren': 'Exportera stilprofil',
  'Stijlprofiel importeren': 'Importera stilprofil',
  'Profiel exporteren': 'Exportera profil',
  'Profiel importeren': 'Importera profil',
  'Stijlprofiel geëxporteerd': 'Stilprofilen exporterades',
  'Stijlprofiel geëxporteerd — het eigen logo kon niet worden meegenomen':
      'Stilprofilen exporterades — den egna logotypen kunde inte tas med',
  'Stijlprofiel exporteren mislukt': 'Det gick inte att exportera stilprofilen',
  'Stijlprofiel importeren mislukt': 'Det gick inte att importera stilprofilen',
  'Stijlprofiel geïmporteerd': 'Stilprofilen importerades',
  'Dit is geen geldig stijlprofiel-bestand':
      'Detta är inte en giltig stilprofilfil',
  'Dit bestand is te groot voor een stijlprofiel':
      'Den här filen är för stor för en stilprofil',
  'Dit stijlprofiel komt uit een nieuwere versie van OciDeck':
      'Den här stilprofilen kommer från en nyare version av OciDeck',
  'die naam bestond al, bewaard als': 'det namnet fanns redan, sparades som',
  'het ingesloten logo kon niet worden teruggezet':
      'den inbäddade logotypen kunde inte återställas',
  'Maak een tussenkop': 'Skapa en mellanrubrik',
  'Maak er weer een bullet van': 'Gör om till en punkt igen',
  'Tussenkop (leeg = alleen een scheidingslijn)':
      'Mellanrubrik (tom = endast en avgränsningslinje)',
  'Tussenkop toevoegen': 'Lägg till mellanrubrik',
  'Uitleg naar notities': 'Förklaring till anteckningar',
  'adres': 'adress',
  'postcode': 'postnummer',
  'persoonsnaam': 'personnamn',
  'Deze presentatie bevat onderdelen van de Informatieveiligheidsmodule. Zet de module aan om ze te bewerken.':
      'Den här presentationen innehåller delar av modulen Informationssäkerhet. Aktivera modulen för att redigera dem.',
  'Inschakelen': 'Aktivera',
  'Bevestigen': 'Bekräfta',
  'Onderbouwing van de bevestiging': 'Motivering för bekräftelsen',
  'De eigenaar staat insluiten niet toe': 'Ägaren tillåter inte inbäddning',
  'Deze video is alleen op de bron zelf te bekijken.':
      'Den här videon kan bara ses på själva källan.',
  'Video niet gevonden': 'Videon hittades inte',
  'De video is verwijderd, privé of de link klopt niet.':
      'Videon har tagits bort, är privat eller så är länken fel.',
  'Ongeldige video-link': 'Ogiltig videolänk',
  'Controleer de URL van de video op deze slide.':
      'Kontrollera videons URL på den här bilden.',
  'Geen verbinding met de videobron': 'Ingen anslutning till videokällan',
  'Controleer de internetverbinding en probeer opnieuw.':
      'Kontrollera internetanslutningen och försök igen.',
  'Privacy blokkeert export': 'Integriteten blockerar exporten',
  'privacybevinding(en) zonder keuze': 'integritetsfynd utan gjort val',
  'Persoonsgegevens, bijzondere gegevens en geheimen in de tekst':
      'Personuppgifter, särskilda uppgifter och hemligheter i texten',
  'Slides, notities, tabellen, code, bestandspaden en URL\'s worden op dit apparaat doorzocht op identificerende nummers, financiële gegevens, contactgegevens, digitale identificatoren, geheimen, bijzondere persoonsgegevens (AVG art. 9/10), massagegevens en metadatalekken.':
      'Bilder, anteckningar, tabeller, kod, filsökvägar och URL:er genomsöks på den här enheten efter identifierande nummer, finansiella uppgifter, kontaktuppgifter, digitala identifierare, hemligheter, särskilda kategorier av personuppgifter (GDPR art. 9/10), massuppgifter och metadataläckor.',
  'Alleen een zekere treffer waarschuwt; waarschijnlijk en mogelijk blijven informatief. Een uitgezette regel vuurt nergens.':
      'Bara en säker träff varnar; sannolik och möjlig förblir informativa. En avstängd regel slår inte till någonstans.',
  'Niet gecontroleerd: persoonsgegevens, bijzondere gegevens en geheimen. De privacycontrole staat uit bij Beveiliging.':
      'Inte kontrollerat: personuppgifter, särskilda uppgifter och hemligheter. Integritetskontrollen är avstängd under Säkerhet.',
  'Op deze slide': 'På den här bilden',
  'Tijdens presenteren': 'Under presentationen',
  'Classificatie en privacy': 'Klassificering och integritet',
  'Logo tonen': 'Visa logotyp',
  'Footer tonen': 'Visa sidfot',
  'Tabel bewerkbaar': 'Tabell redigerbar',
  'Laat je de tabel tijdens het presenteren voor de zaal aanpassen. Staat standaard uit.':
      'Låter dig ändra tabellen inför publiken under presentationen. Av som standard.',
  'Automatisch doorgaan': 'Gå vidare automatiskt',
  'Persoonsgegevens': 'Personuppgifter',
  'Wijzigen': 'Ändra',
  'Automatisch afspelen': 'Spela upp automatiskt',
  'Melden': 'Rapportera',
  'Geaccepteerd': 'Accepterad',
  'Gewaarschuwd': 'Varnad',
  'Weggelaten': 'Utelämnad',
  'Bewerkbaar': 'Redigerbar',
  'De privacycontrole': 'Integritetskontrollen',
  'OciDeck leest je dia\'s na op gegevens die privacygevoelig kunnen zijn: identificatienummers, contactgegevens, telefoonnummers, bankrekeningen, sleutels en wachtwoorden, en bijzondere persoonsgegevens. Dat gebeurt volledig op dit apparaat: er wordt niets verstuurd, en de gevonden waarde zelf komt in geen enkele melding te staan.':
      'OciDeck läser igenom dina bilder efter uppgifter som kan vara integritetskänsliga: identifikationsnummer, kontaktuppgifter, telefonnummer, bankkonton, nycklar och lösenord samt särskilda kategorier av personuppgifter. Allt sker på den här enheten: ingenting skickas iväg, och det funna värdet syns inte i något meddelande.',
  'De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat er persoonsgegevens onbedoeld uitlekken.':
      'Kontrollen garanterar inte att allt hittas; den minskar risken för att personuppgifter oavsiktligt läcker ut.',
  'Tekst in afbeeldingen blijft buiten beeld, gelinkte bestanden worden niet geopend, en gegevens zonder herkenbaar patroon herkent geen enkele scanner. Een dia zonder meldingen is een dia waarin wíj niets hebben gevonden, niet een dia waarvan vaststaat dat er niets in staat. Wat je deelt, blijft jouw beslissing en jouw verantwoordelijkheid.':
      'Text i bilder förblir osynlig, länkade filer öppnas inte, och uppgifter utan igenkännbart mönster känner ingen skanner igen. En bild utan anmärkningar är en bild där *vi* inte hittade något — inte en bild där det är bevisat att inget finns. Vad du delar förblir ditt beslut och ditt ansvar.',
  'telefoonnummer': 'telefonnummer',
  'Voor wie is deze export?': 'Vem är den här exporten till?',
  'Volledig': 'Fullständig',
  'Geredigeerd': 'Maskad',
  'Voor de opdrachtgever of auditor: alleen wat je zelf op "weglaten" hebt gezet, gaat eruit. De rest blijft leesbaar, zodat een derde partij de bevindingen kan controleren.':
      'För uppdragsgivaren eller revisorn: bara det du satt till "utelämna" tas bort. Resten förblir läsbart, så att en tredje part kan kontrollera fynden.',
  'Voor de bredere kring: alles wat de controle vindt gaat eruit, ook op slides die je hebt geaccepteerd. Het bestand krijgt "-geredigeerd" in de naam.':
      'För en bredare krets: allt kontrollen hittar tas bort, även på bilder du accepterat. Filen får "-geredigeerd" i namnet.',
  'tabel met persoonsgegevens (rijen×kolommen)':
      'tabell med personuppgifter (rader×kolumner)',
  'massa-persoonsgegevens op één slide':
      'massvis av personuppgifter på en bild',
  'gebruikerspad met een naam erin': 'användarsökväg med ett namn i',
  'toegangstoken in een link': 'åtkomsttoken i en länk',
  'persoonsgegeven in een link': 'personuppgift i en länk',
  'deellink met ingebakken toegang': 'delningslänk med inbyggd åtkomst',
  'e-mailadres in een link': 'e-postadress i en länk',
  'ingesloten afbeelding — wij kunnen er niet in kijken':
      'inbäddad bild — vi kan inte titta in i den',
  'Je eigen gegevens': 'Dina egna uppgifter',
  'Eén per regel: je naam, e-mailadres, telefoonnummer of het domein van je organisatie. Wat hier staat wordt niet gemeld en niet geredigeerd — het is de afzender, geen bevinding. Een domein (example.org) dekt elk adres eronder.':
      'Ett per rad: ditt namn, din e-postadress, ditt telefonnummer eller din organisations domän. Det som står här rapporteras inte och maskas inte — det är avsändaren, inte ett fynd. En domän (example.org) täcker varje adress under den.',
  'Bij onafgehandelde persoonsgegevens': 'Vid ohanterade personuppgifter',
  'Export afgebroken vanwege privacybevindingen.':
      'Exporten avbröts på grund av integritetsfynd.',
  'Export blokkeren': 'Blockera export',
  'Export geblokkeerd': 'Exporten blockerad',
  'Export geblokkeerd: er staan persoonsgegevens in dit deck waarvoor nog geen keuze is gemaakt.':
      'Exporten blockerad: den här presentationen innehåller personuppgifter du ännu inte tagit ställning till.',
  'Kies per slide wat er moet gebeuren, of exporteer bewust zoals het is.':
      'Välj per bild vad som ska hända, eller exportera medvetet som det är.',
  'Maak per slide een keuze (accepteren, waarschuwen of weglaten) voordat je exporteert. Dit is zo ingesteld bij Beveiliging.':
      'Gör ett val per bild (acceptera, varna eller utelämna) innan du exporterar. Det ställs in under Säkerhet.',
  'Niets doen': 'Gör ingenting',
  'Persoonsgegevens in dit deck': 'Personuppgifter i den här presentationen',
  'Verder in dit deck:': 'I övrigt i den här presentationen:',
  'Waarschuwen vóór export': 'Varna före export',
  'bevinding(en) zonder keuze.': 'fynd utan gjort val.',
  'geaccepteerd': 'accepterade',
  'geredigeerd': 'maskade',
  'met waarschuwing': 'med varning',
  'Deze regel nooit meer melden': 'Rapportera aldrig den här regeln igen',
  'politieke opvatting': 'politisk åsikt',
  'etnische afkomst': 'etniskt ursprung',
  'seksuele geaardheid': 'sexuell läggning',
  ' Op deze slide staat ook een identificerend gegeven, dus dit is herleidbaar tot een persoon.':
      ' På den här bilden finns även en identifierande uppgift, så detta kan kopplas till en person.',
  'Bijzonder persoonsgegeven (AVG art. 9/10)':
      'Särskild kategori av personuppgifter (GDPR art. 9/10)',
  'gezondheidsgegeven': 'hälsouppgift',
  'strafrechtelijk gegeven': 'straffrättslig uppgift',
  'religie of levensovertuiging': 'religion eller övertygelse',
  'vakbondslidmaatschap': 'fackligt medlemskap',
  'biometrisch gegeven': 'biometrisk uppgift',
  'genetisch gegeven': 'genetisk uppgift',
  'parketnummer': 'åklagarens ärendenummer',
  'nationaal identificatienummer': 'nationellt identifikationsnummer',
  'Mogelijk geheim': 'Möjlig hemlighet',
  'sleutel of token': 'nyckel eller token',
  'private sleutel': 'privat nyckel',
  'toegangstoken (JWT)': 'åtkomsttoken (JWT)',
  'databaseverbinding met wachtwoord': 'databasanslutning med lösenord',
  'wachtwoord in klare tekst': 'lösenord i klartext',
  'Afbreken': 'Avbryt',
  'Afgebroken. Er is niets half achtergebleven.':
      'Avbrutet. Ingenting blev halvfärdigt kvar.',
  'Bijwerken': 'Uppdatera',
  'Binnenhalen…': 'Hämtar…',
  'CVE\'s': 'CVE:er',
  'Database ophalen': 'Hämta databas',
  'De CVE-lijst kon niet worden opgehaald. Controleer je verbinding en probeer het opnieuw; een half binnengehaalde lijst is weggegooid.':
      'CVE-listan kunde inte hämtas. Kontrollera din anslutning och försök igen; en halvhämtad lista har kastats.',
  'De nieuwste uitgave opzoeken…': 'Söker efter den senaste utgåvan…',
  'Dit is een grote download: ruim 500 MB binnenhalen, tijdelijk zo\'n 1,5 GB schijfruimte, en afhankelijk van je verbinding en apparaat al gauw tien tot dertig minuten werk. Daarna blijft er een index van enkele honderden megabytes staan. Op een verbinding die per megabyte betaalt, doe je dit liever niet.':
      'Det här är en stor nedladdning: över 500 MB att hämta, tillfälligt runt 1,5 GB diskutrymme och, beroende på din anslutning och enhet, lätt tio till trettio minuters arbete. Sedan blir ett index på några hundra megabyte kvar. På en anslutning som betalas per megabyte gör du helst inte det här.',
  'Er was te weinig schijfruimte. De opbouw vraagt tijdelijk ruim 1,5 GB.':
      'Det fanns för lite diskutrymme. Uppbyggnaden kräver tillfälligt över 1,5 GB.',
  'Het opgehaalde archief was niet wat we verwachtten en is geweigerd. Er is niets geïnstalleerd.':
      'Det hämtade arkivet var inte det vi förväntade oss och avvisades. Ingenting har installerats.',
  'Indexeren…': 'Indexerar…',
  'Lokaal beschikbaar — opzoeken gebeurt offline, er gaat geen zoekterm naar buiten.':
      'Tillgänglig lokalt — uppslag sker offline, ingen sökterm lämnar enheten.',
  'Lokale CVE-database': 'Lokal CVE-databas',
  'Met de CVE-lijst op je eigen apparaat blijft het opzoeken hier: er gaat geen zoekterm meer naar een server, en niemand kan zien welk lek je onderzoekt.':
      'Med CVE-listan på din egen enhet stannar uppslagen här: ingen sökterm går längre till en server, och ingen kan se vilken sårbarhet du undersöker.',
  'Uitpakken…': 'Packar upp…',
  'Zet de volledige CVE-lijst op dit apparaat, zodat opzoeken offline gebeurt en je zoekterm nergens heen gaat. De database komt van CVE List V5 (het officiële CVE-programma, via GitHub).':
      'Lägg hela CVE-listan på den här enheten, så att uppslag sker offline och din sökterm inte går någonstans. Databasen kommer från CVE List V5 (det officiella CVE-programmet, via GitHub).',
  'Wat er lokaal beschikbaar is': 'Vad som finns tillgängligt lokalt',
  'Nu bijwerken': 'Uppdatera nu',
  'Gegevens lokaal beschikbaar — het opzoeken gebeurt op dit apparaat, er gaat niets naar buiten.':
      'Data finns tillgängliga lokalt — sökningar sker på den här enheten; ingenting lämnar den.',
  'Zwakheden (CWE)': 'Svagheter (CWE)',
  'Testgevallen (WSTG)': 'Testfall (WSTG)',
  'MIAUW-eisen': 'MIAUW-krav',
  'CVSS-scoretabel': 'CVSS-poängtabell',
  'Bevindingsjablonen': 'Fyndmallar',
  'Zoek een instelling': 'Sök en inställning',
  'Geen instelling gevonden': 'Ingen inställning hittades',
  'Je zoekterm gaat naar de ingestelde CVE-mirror, en als die niets vindt ook naar ENISA en MITRE. Wie die servers beheert, kan daaruit afleiden naar welk specifiek lek je zoekt — en dus welk lek je onderzoekt.':
      'Din sökterm skickas till den konfigurerade CVE-spegeln och, om den inte hittar något, även till ENISA och MITRE. De som driver dessa servrar kan sluta sig till vilken specifik sårbarhet du söker — och därmed vilken sårbarhet du undersöker.',
  'Accepteren': 'Acceptera',
  'Accepteren + waarschuwen': 'Acceptera + varna',
  'Accepteren: de gegevens horen hier en de melding verdwijnt. Accepteren + waarschuwen: de ontvanger ziet een badge dat er persoonsgegevens op de slide staan. Weglaten: de gevonden gegevens worden onleesbaar gemaakt op het scherm en in de export — je markdown-bestand houdt de oorspronkelijke tekst.':
      'Acceptera: uppgifterna hör hemma här och meddelandet försvinner. Acceptera + varna: mottagaren ser en märkning om att bilden innehåller personuppgifter. Utelämna: de funna uppgifterna görs oläsliga på skärmen och i exporten — din Markdown-fil behåller originaltexten.',
  'Alleen melden': 'Rapportera bara',
  'PERSOONSGEGEVENS': 'PERSONUPPGIFTER',
  'Volg de presentatie': 'Följ presentationen',
  'Weglaten uit tonen en exporteren': 'Utelämna från visning och export',
  ' Overweeg dit te redigeren met [[dubbele blokhaken]].':
      ' Överväg att maska det med [[dubbla hakparenteser]].',
  ' Zonder context in de tekst is dit mogelijk geen persoonsgegeven.':
      ' Utan sammanhang i texten är detta kanske inte en personuppgift alls.',
  'Leest je dia\'s na op identificatienummers, contactgegevens en andere privacygevoelige gegevens, en meldt ze bij de kwaliteitscontrole. Dit gebeurt volledig op dit apparaat; er wordt niets verstuurd. Het is een hulpmiddel, geen garantie: tekst in afbeeldingen en gegevens zonder herkenbaar patroon blijven buiten beeld.':
      'Granskar dina bilder efter identifikationsnummer, kontaktuppgifter och andra integritetskänsliga uppgifter och rapporterar dem i kvalitetskontrollen. Det sker helt på den här enheten; ingenting skickas. Det är ett hjälpmedel, inte en garanti: text i bilder och uppgifter utan igenkännbart mönster förblir osynliga.',
  'Mogelijk persoonsgegeven': 'Möjlig personuppgift',
  'Privacycontrole': 'Integritetskontroll',
  'Waarschuw bij mogelijke persoonsgegevens':
      'Varna för möjliga personuppgifter',
  'burgerservicenummer (BSN)': 'medborgarnummer (BSN)',
  'bankrekeningnummer (IBAN)': 'bankkontonummer (IBAN)',
  'e-mailadres': 'e-postadress',
  'De TSA-handtekening is niet in-app geverifieerd; alleen de hash komt overeen.':
      'TSA-signaturen verifieras inte i appen; endast hashen stämmer.',
  'Extern': 'Extern',
  'Van een externe URL opgehaald; het openen heeft die server benaderd.':
      'Hämtad från en extern URL; öppningen kontaktade den servern.',
  'AI-assistentie (staat standaard uit): kies je een zelf-gehoste of cloud-backend, dan worden de teksten of afbeeldingen die je laat verwerken naar dat adres gestuurd. Wat je hebt geredigeerd, gaat er eerst uit. Een lokaal AI-model op dit apparaat verstuurt niets.':
      'AI-assistans (av som standard): väljer du en självhostad backend eller molnbackend skickas texterna eller bilderna du låter bearbeta till den adressen. Det du har maskat tas bort först. En lokal AI-modell på den här enheten skickar ingenting.',
  'Gegevens weglaten (redactie)': 'Utelämna uppgifter (maskning)',
  'Zet je tekst tussen dubbele blokhaken, zoals [[het adres]], dan laat OciDeck die weg uit alles wat je toont en exporteert. Op de dia, in de presentatie, in de PDF, de PowerPoint en de HTML verschijnen alleen blokken.':
      'Sätt text inom dubbla hakparenteser, som [[adressen]], så utelämnar OciDeck den från allt du visar och exporterar. På bilden, i presentationen, i PDF:en, PowerPointen och HTML:en syns bara block.',
  'Weggelaten is écht weggelaten, niet afgedekt. De tekst zit niet als onzichtbare laag onder een zwart balkje in de PDF, niet in de sprekersnotities van de PowerPoint, en niet in de broncode van de HTML. Wie het bestand openmaakt, kan er niets uit terughalen.':
      'Utelämnat betyder verkligen utelämnat, inte övertäckt. Texten ligger inte som ett osynligt lager under ett svart streck i PDF:en, inte i PowerPointens anteckningar och inte i HTML:ens källkod. Den som öppnar filen kan inte få fram något.',
  'Je eigen bestand verandert niet. De oorspronkelijke tekst blijft in je markdown staan; redactie geldt alleen voor wat je deelt. Zo houd je je eigen gegevens.':
      'Din egen fil ändras inte. Originaltexten blir kvar i din markdown; maskningen gäller bara det du delar. Så behåller du dina egna uppgifter.',
  'map/presentatie': 'mapp/presentation',
  'Gekoppelde test': 'Länkad test',
  'Maak eerst een checklist voor dit scope-object.':
      'Skapa först en checklista för det här scope-objektet.',
  'Bewerken': 'Redigera',
  'Checklist-sjabloon': 'Checklistmall',
  'Eigen checklists': 'Egna checklistor',
  'Laad een eigen checklist-sjabloon': 'Läs in en egen checklistmall',
  'Leeg laten': 'Lämna tom',
  'Maak herbruikbare testlijsten die je per scope-object in een checklist kunt laden, naast de gebundelde WSTG-lijst.':
      'Skapa återanvändbara testlistor som du kan läsa in i en checklista per scope-objekt, vid sidan av den inbyggda WSTG-listan.',
  'Nieuw sjabloon': 'Ny mall',
  'Nog geen eigen checklists.': 'Inga egna checklistor ännu.',
  'Sjabloon laden…': 'Läs in mall…',
  'Sjabloon voor overige objecten': 'Mall för övriga objekt',
  'Testen': 'Tester',
  'Genereer checklists voor scope-objecten':
      'Generera checklistor för scope-objekt',
  'checklists toegevoegd': 'checklistor tillagda',
  'Alle scope-objecten hebben al een checklist':
      'Alla scope-objekt har redan en checklista',
  'Maakt per scope-object een checklist (WSTG voor web/API); bestaande blijven staan.':
      'Skapar en checklista per scope-objekt (WSTG för webb/API); befintliga behålls.',
  'CVE opzoeken': 'Slå upp CVE',
  'CVE opzoeken (online)': 'Slå upp CVE (online)',
  'CVE opzoeken is niet beschikbaar in de webversie.':
      'CVE-uppslag är inte tillgängligt i webbversionen.',
  'CVE-mirror (basis-URL)': 'CVE-spegel (bas-URL)',
  'Geen CVE gevonden.': 'Ingen CVE hittades.',
  'Kon de CVE-bron niet bereiken.': 'Kunde inte nå CVE-källan.',
  'Sta toe om in de bevinding-editor online in CVE\'s te zoeken via een NVD-mirror. Standaard uit; vereist ook je toestemming en werkt alleen op desktop.':
      'Tillåt sökning efter CVE:er online i fyndeditorn via en NVD-spegel. Avstängt som standard; kräver också ditt samtycke och fungerar endast på skrivbordet.',
  'Typ een (deel van een) CVE-id en zoek.':
      'Skriv (en del av) ett CVE-id och sök.',
  'Typ minstens 3 tekens.': 'Skriv minst 3 tecken.',
  'Zet CVE opzoeken (online) aan in Instellingen → Beveiliging om online in CVE\'s te zoeken.':
      'Aktivera CVE-uppslag (online) i Inställningar → Säkerhet för att söka CVE:er online.',
  'Zoek CVE…': 'Sök CVE…',
  'Zoek op CVE-id, bijv. 2021-44228': 'Sök efter CVE-id, t.ex. 2021-44228',
  'Zoeken': 'Sök',
  'Hertest': 'Omtest',
  'Niet hertest': 'Inte omtestad',
  'Opgelost': 'Löst',
  'Nog aanwezig': 'Kvarstår',
  'Deels opgelost': 'Delvis löst',
  'na hertest': 'efter omtest',
  'Opgelost na hertest': 'Löst efter omtest',
  'Hertest-notitie': 'Omtestanteckning',
  'Zonder bevinding-id maken we er automatisch een aan bij het eerste bewijs.':
      'Utan ett fynd-id skapas ett automatiskt vid det första beviset.',
  'Niet gedefinieerd': 'Ej definierad',
  'Netwerk': 'Nätverk',
  'Aangrenzend': 'Angränsande',
  'Lokaal': 'Lokal',
  'Fysiek': 'Fysisk',
  'Aanwezig': 'Närvarande',
  'Passief': 'Passiv',
  'Actief': 'Aktiv',
  'Aanvalsvector': 'Attackvektor',
  'Aanvalscomplexiteit': 'Attackkomplexitet',
  'Aanvalsvereisten': 'Attackkrav',
  'Vereiste rechten': 'Nödvändiga behörigheter',
  'Gebruikersinteractie': 'Användarinteraktion',
  'Vertrouwelijkheid (kwetsbaar systeem)': 'Konfidentialitet (sårbart system)',
  'Integriteit (kwetsbaar systeem)': 'Integritet (sårbart system)',
  'Beschikbaarheid (kwetsbaar systeem)': 'Tillgänglighet (sårbart system)',
  'Vertrouwelijkheid (vervolgsysteem)':
      'Konfidentialitet (efterföljande system)',
  'Integriteit (vervolgsysteem)': 'Integritet (efterföljande system)',
  'Beschikbaarheid (vervolgsysteem)': 'Tillgänglighet (efterföljande system)',
  'PTES-fasen laden': 'Läs in PTES-faser',
  'Voegt de zeven PTES-fasen toe; bestaande gebeurtenissen blijven staan.':
      'Lägger till de sju PTES-faserna; befintliga händelser behålls.',
  'Basis': 'Bas',
  'Context': 'Kontext',
  'CVSS-wizard': 'CVSS-guide',
  'Kies uit de scope': 'Välj från scope',
  'Bepaalt de contextscore van bevindingen op dit object; laat leeg als de weging niet bekend is.':
      'Bestämmer kontextpoängen för fynd på detta objekt; lämna tomt om viktningen är okänd.',
  'De contextscore is gewogen met de CIA-rating van het gekozen scope-object.':
      'Kontextpoängen viktas med CIA-klassningen för det valda scope-objektet.',
  'WSTG-testen laden': 'Läs in WSTG-tester',
  'testen': 'tester',
  'Voegt ontbrekende WSTG-testen toe; bestaande blijven staan.':
      'Lägger till de saknade WSTG-testerna; befintliga behålls.',
  'Bewijs': 'Bevis',
  'Screenshot toevoegen': 'Lägg till skärmbild',
  'Video toevoegen': 'Lägg till video',
  'Bewerk deze slide': 'Redigera denna bild',
  'Bewijs verwijderen': 'Ta bort bevis',
  '(nog leeg)': '(fortfarande tom)',
  'Voeg screenshots of video\'s toe als bewijs. Elk stuk bewijs komt als eigen slide direct na de bevinding en telt mee in de export.':
      'Lägg till skärmbilder eller videor som bevis. Varje bevis blir en egen bild direkt efter fyndet och kommer med i exporten.',
  'Uitvoering testen conform standaard': 'Tester enligt standard',
  'Te weinig contrast met de achtergrond — mogelijk onleesbaar.':
      'För lite kontrast mot bakgrunden — kan bli oläsligt.',
  // Nieuwe strings hier toevoegen via `make add-l10n` (tool/add_l10n.dart).
  'LibrePlan-connector': 'LibrePlan-koppling',
  'De LibrePlan-connector is alleen beschikbaar in de desktopversie.':
      'LibrePlan-kopplingen är endast tillgänglig i skrivbordsversionen.',
  'LibrePlan-connector is optioneel en staat standaard uit. Er wordt niets opgehaald totdat u dit inschakelt en zelf een server configureert. Alleen-lezen: de connector schrijft niets terug naar LibrePlan. Het wachtwoord wordt in de sleutelhanger van uw besturingssysteem opgeslagen, niet in het deck.':
      'LibrePlan-kopplingen är valfri och avstängd som standard. Inget hämtas förrän du slår på den och själv ställer in en server. Skrivskyddad: kopplingen skriver inget tillbaka till LibrePlan. Lösenordet sparas i operativsystemets nyckelring, inte i decket.',
  'Opgeslagen in de sleutelhanger': 'Sparat i nyckelringen',
  'Alleen voor servers op het eigen netwerk (LAN). Staat plain-HTTP toe en staat privé-adressen door de NetGuard. Uitgeschakeld: HTTPS verplicht.':
      'Endast för servrar i det egna nätverket (LAN). Tillåter vanlig HTTP och släpper igenom privata adresser genom NetGuard. Avstängt: HTTPS krävs.',
  'Verbinding succesvol.': 'Anslutningen lyckades.',
  'Onverwachte fout.': 'Oväntat fel.',
  'Importeren uit LibrePlan': 'Importera från LibrePlan',
  'LibrePlan importeren': 'Importera från LibrePlan',
  'Kies welke slides u uit het LibrePlan-project wilt halen. De import is alleen-lezen en schrijft niets terug.':
      'Välj vilka bilder du vill hämta från LibrePlan-projektet. Importen är skrivskyddad och skriver inget tillbaka.',
  'Gantt-planning': 'Gantt-planering',
  'WBS (hiërarchie)': 'WBS (hierarki)',
  'Projectstatus (cockpit)': 'Projektstatus (cockpit)',
  'Milestones (tijdlijn)': 'Milstolpar (tidslinje)',
  'Kritieke pad (flow)': 'Kritisk linje (flöde)',
  'Resources (tabel)': 'Resurser (tabell)',
  'Timesheet (tabel)': 'Tidrapport (tabell)',
  'Resourcebelasting (grafiek)': 'Resursbelastning (diagram)',
  'Ophalen uit LibrePlan…': 'Hämtar från LibrePlan…',
  'Geen slides gevonden.': 'Inga bilder hittades.',
  "dia's geïmporteerd.": 'bilder importerade.',
  'Import mislukt: ': 'Importen misslyckades: ',
  'Checklists': 'Checklistor',
  'Configureer de server op het tabblad LibrePlan-connector. Zolang daar niets staat, gebeurt er niets.':
      'Ställ in servern på fliken LibrePlan-koppling. Så länge inget står där händer ingenting.',
  'Importeer een projectsnapshot van een LibrePlan-instantie als slides: Gantt, WBS, resourcebelasting, timesheet en meer. Alleen-lezen, op verzoek — er gaat niets naar buiten tot u een server configureert en een import start.':
      'Importera en ögonblicksbild av ett projekt från en LibrePlan-instans som bilder: Gantt, WBS, resursbelastning, tidrapport och mer. Skrivskyddad, på begäran — inget lämnar enheten förrän du ställer in en server och startar en import.',
  'Vul server-URL en gebruikersnaam in.': 'Fyll i server-URL och användarnamn.',
  'https://libreplan.example.org/libreplan/':
      'https://libreplan.example.org/libreplan/',
  'wsreader': 'wsreader',
  'Centreren': 'Centrera',
  'Getalnotatie': 'Talformat',
  'Kolom naar links': 'Kolumn åt vänster',
  'Kolom naar rechts': 'Kolumn åt höger',
  'Kolom rechts invoegen': 'Infoga kolumn till höger',
  'Koprij': 'Rubrikrad',
  'Links uitlijnen': 'Vänsterjustera',
  'Rechts uitlijnen': 'Högerjustera',
  'Rij onder invoegen': 'Infoga rad under',
  'Splits tabel': 'Dela tabell',
  'De documentstijl (thema, paginaformaat, marges) gaat niet mee.':
      'Dokumentstilen (tema, sidstorlek, marginaler) följer inte med.',
  'Documentvelden (kop- en voettekst) gaan niet mee.':
      'Dokumentfält (sidhuvud och sidfot) följer inte med.',
  'Voetnoten worden platte tekst; een presentatie kent geen noten.':
      'Fotnoter blir till vanlig text; en presentation har inte noter.',
  'Pins': 'Pins',
  'Gebieden': 'Områden',
  'bv. "de controller board met display"':
      't.ex. "kontrollerkortet med display"',
  'Afbeeldingsverwijzingen': 'Bildreferenser',
};
