---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SAFARI-arviointi digitaalisesta suvereniteetista
language: fi
standards: SAFARI@0.9, ECSF
---

<!-- _class: title -->

# SAFARI-arviointi digitaalisesta suvereniteetista

---
# Näin käytetään tätä työkorttia

- Määritä ensin laajuus, väite, haluttu taso ja tavoitteellinen varmuustaso.
- Täytä jokainen kyselykohta löytön, jäljitettävän lähdeviitteen ja todistustason kanssa.
- Käsittele puuttuva tai hylätty todiste löytönä todistustasolla 0.
- Sovella kuusi pisteytysääntöä ennen SOV-tavoitteen tasoittamista.
- Muotoile vakuutusarvio vasta kun laaduntarkistus ja tapahtumat peilipäivän jälkeen on arvioitu.
---

<!-- _class: table table-editable -->

# Asiakirjojen hallinta- ja toimeksiantotiimi

|  Kenttä | Valmis |
| --- | --- |
| Organisaatio | … |
| Palvelu tai järjestelmä | … |
| Liver | … |
| Client | … |
| Vastaa vaatimuksesta | … |
| QToimiva tilintarkastaja tai konsultti | … |
| Riippumaton arvioija | … |
| Viitepäivämäärä ja arviointijakso | … |
| Raportti versio ja päivämäärä | … |
| TLP-luokitus ja jakeluluettelo | … |

---
<!-- _class: table table-editable -->

# Kohde ja laajuus

| Laajuuden osa | Täyttö |
| --- | --- |
| Arvioidut sovellukset, alustat ja infrastruktuuri | … |
| Suorat toimittajat | … |
| Olennaiset alatoimittajat ja ketjupolut | … |
| Tietotyypit | Henkilötiedot / yritystiedot / hallitustiedot / luokiteltu tieto |
| Oikeudelliset määräykset osapuolen mukaan | … |
| Hallinta-, tuki-, rakennus- ja allekirjoituspaikat | … |
| Ilmoitetut poikkeukset perusteluineen | … |
| Normatiivisen kehyksen versio | SAFARI v0.9 (konsepti; valinnainen menetelmä) |
---
<!-- _class: table table-editable -->

# Organisaation väite

| Osa | Täyttöteksti |
| --- | --- |
| Kohde | [Organisaatio] on arvioinut sovevuutensa [palveluun], toimitettu [anturilla], arvioinut. |
| Aikaväli | Arviointi koskee tilannetta [päivämäärä] sisällä määritetystä laajuudesta [päivämäärä]. |
| Kehys | Arviointi on suoritettu ISO 27001:2022:n mukaisesti, valinnaisen konseptimenetelmän mukaisesti, joka on kytketty ECSF:n kahdeksaan tavoitteeseen. |
| Tulos | Organisaatio väittää täyttävänsä valitun tason [0-4] [SOV-koodi tai kaikki tavoitteet]. |
| Huomautus | Tulos perustuu peilipäivän saatavilla olevaan todistukseen; muutokset voivat vaikuttaa tulokseen. |
| Omistaja ja virallinen vahvistus | … |
---
<!-- _class: table table-editable -->

# Haluamattomat tasot ja ydintavoitteet

| Koodi | Tavoite | Ydintavoite | Suositeltu minimi | Haluettu | Poikkeaman perustelu |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Strateginen | Kyllä | 2 | … | … |
| SOV-2 | Juridiset ja oikeudelliset | Kyllä | 2 | … | … |
| SOV-3 | Data ja AI | Kyllä | 3 (2 vain matala-herkät ja ilman henkilötietoja) | … | … |
| SOV-4 | Operatiivinen | Kyllä | 3 (2 vain matala-herkät, korvattavissa ja ilman henkilötietoja) | … | … |
| SOV-5 | Ketju | Kyllä | 3 (2 vain matala-herkät ja ilman henkilötietoja) | … | … |
| SOV-6 | Teknologia | Kyllä | 3 (2 vain matala-herkät ja ilman henkilötietoja) | … | … |
| SOV-7 | Turvallisuus ja säännökset | Kyllä | 2 | … | … |
| SOV-8 | Kestävyys | Kyllä | 1 | … | … |
---

<!-- _class: table table-editable -->

# Avarmuutta koskeva lähestymistapa

| Osa | Valinta ja perustelut |
| --- | --- |
| Komentotyyppi | Neuvonta / rajoitettu varmuus / kohtuullinen varmuus |
| Tavoitteet varmuuden sisällä | … |
| Olellisuus ja riskilähtöinen valinta | … |
| Toiminnot todistetyypin mukaan | Tarkastus / havainnointi / uudelleensuoritus / vahvistus / analyysi |
| Otantotapa ja populaatiot | … |
| Asiantuntijat käyttöön | Laki / tekninen / kestävä kehitys / muu: … |
| Riippumattomuus ja eturistiriidat | … |
| Pääsyä tai toimintoja koskevat rajoitukset | … |

---
<!-- _class: table table-editable -->

# Vahvistuspyyntö virallinen varmennus

| Vahvistuskriteeri | Arviointi ja lähde | Tulos |
| --- | --- | --- |
| SAFARI on sopiva kriteeri väitteelle ja tavoitteelliset käyttäjät | … | Kyllä / ei |
| Vastuullinen osapuoli tunnustaa vastuunsa väitteelle | … | Kyllä / ei |
| Rationaalinen tavoite, tavoitteelliset käyttäjät ja jakelukohde on määritetty | … | Kyllä / ei |
| Riippumattomuus, etiikka, asiantuntemus ja tarvittavat asiantuntijat on varmistettu | … | Kyllä / ei |
| Vahvistuspyyntö ja haluttu varmennustaso on sovittu | … | Kyllä / ei |
| Riittävä todiste on odotettavissa saatavilla | … | Kyllä / ei |
| Vahvistuspäätös | Vain jatketaan, jos kaikki kriteerit ovat "kyllä" | Hyväksy / ei hyväksy |
---

<!-- _class: table -->

# Todisteiden tasot

| Taso | Name | Sovellus |
| --- | --- | --- |
| 0 | Ei todisteita | Ei näyttöä tai todisteita puuttuu tai niitä on evätty |
| 1 |  Lausunto | Suullinen tai kirjallinen lausunto ilman lisäperusteluja |
| 2 | Dokumentaatio | Sopimus, politiikka, menettely tai raportti ilman riippumatonta vahvistusta |
| 3 | Tekninen todiste | Konfiguraatio, loki, testi tai ulkoinen oikeudellinen neuvonta, jonka asiakas on saanut |
| 4 | Riippumaton todiste |  Riippumattoman testauspuolen keräämä tai vahvistama |

---

<!-- _class: table table-editable -->

# Keskitodistusrekisteri

| Source ID | Asiakirja tai rekisteröinti | Omistaja | Päivämäärä ja versio | Alkuperä | Eheys ja säilytyspaikka |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Sisäinen / toimittaja / ulkoinen | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |

---
<!-- _class: table -->

# Sitovat pisteytysäännöt

| Sääntö | Seuraus arviolle |
| --- | --- |
| 0 · Legitimiteetti | Legitimiteettiriski tekee kohdetta aina aukon; suositellaan oikeudellista tarkastusta. |
| 1 · Kriittiset kysymykset | Todistustaso 0 kriittisessä kysymyksessä rajoittaa kohteen enintään tasolle 1. |
| 2 · Todiste tukee tasoa | Todiste ei täytä kysymyksen minimiä, se lasketaan 0. Tavoitetodiste on alhaisin todiste kriittisissä kysymyksissä; taso 2, 3 ja 4 vaativat vähintään saman todistustason. |
| 3 · Heikkoin lenkki | SEAL:n kokonaistaso on alhaisin vahvistettu taso ydintavoitteille. |
| 4 · Toimiva oikeusjärjestys | Jos pakottava ulkomaalainen pääsy on suojattu ja ei ole riippumatonta oikeuskäsittelyä tai ilmoitusmahdollisuutta, lasketaan 2.3, 2.5 ja 2.6 todisteeksi 0; SOV-2 on enintään 1 ja SOV-1 myös, jos vallanpitäminen on siellä. |
| 5 · Tekninen reitti | Jos pakottava ulkomaalainen pääsy on suojattu vain koko tekninen reitti; se ei muuta SOV-2:ta tai SEAL:n kokonaistasoa. Palvelu, joka tarvitsee luettavaa dataa, ei käytä tätä reittiä. |
---

<!-- _class: section -->

# SOV-1 · Strateginen itsemääräämisoikeus

---
<!-- _class: table -->

# SOV-1 · Avaukset

| Kysymys · tyyppi/min. | Kysymys | Vaadittu todiste |
| --- | --- | --- |
| 1.1 · K·2+ | Keitä ovat lopulliset osakkeenomistajat ja millä oikeudellisella perusteella heidät on rekisteröity? | UBO-rekisteri, vuosikertomus, osakkeenomistajarekisteri |
| 1.2 · K·2+ | Voiko ulkomaalainen emoyhtiö EU:ssa pakottaa strategisen kurssimuutoksen? | Ryhmärakenteen kaavio, yhtiöjärjestys, hallintosääntö |
| 1.3 · K·2+ | Sisältääkö sopimus muutoskontrolli-lausekkeita? | Sopimuksen teksti |
| 1.4 · O·1+ | Onko teknologia ja IP sijoitettu EU:n entiteettiin vai ulkomaaliseen emoyhtiöön? | IP-rekisteröinti, lisenssisopimukset |
| 1.5 · O·2+ | Onko toimittajariippuvuutta käsitellyt ja dokumentoitu lautakunnassa? | Lautakuntamietoksia, riskiregistersi |
| 1.6 · O·2+ | Onko ulostulo- tai jatkuvuusskenaario omistusmuutokselle? | Jatkuvuussuunnitelma, ulostulosuunnitelma |
---
<!-- _class: table table-editable -->

# SOV-1 · Löydöt ja todisteet

| Kysymys · tyyppi/min. | Faktinen löytö | Lähtö-ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 1.1 · UBO:t ja oikeudellinen peruste (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Ulkomaalainen emoyhtiö voi pakottaa kurssin (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Muutoskontrolli (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Teknologia ja IP sijainti (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Riippuvuus lautakunnassa (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Ulostulo omistusmuutoksessa (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-1 · Tason määritys

| Level | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | No insight | Ei tietoa omistus- tai valtarakenteesta | Ei mitään |
| 1 | Insight | Insight saatavilla, mutta ei takuuta omistajan vaihtuessa | 1 |
| 2 | Sopimustakuu | Hallinnan vaihtamisesta ja läpinäkyvyydestä on sovittu sopimuksella | 2 |
| 3 | Control | EU:n hallinto on erillistä ja täytäntöönpanokelpoista; vaikutusvalta EU:n ulkopuolella on erittäin rajoitettu | 3 |
| 4 | Strateginen autonomia | Kestävästi eurooppalainen sulautettu; riippuvuus on nimenomaisesti punnittu hallituksen päätöksessä | 4 |

---
<!-- _class: table table-editable -->

# SOV-1 · Keskeisaranto

| Perustelu keskeiselle pisteytykselle | Toteutus |
| --- | --- |
| Faktuaal tilanne ja sopiva ominaisuus asteikosta | … |
| Alin todiste kriittisille kysymyksille, lähde-ID:t mukana | … |
| Käytetyt säännöt ja mahdolliset rajoitukset | … |
| Tärkein syy, riski ja löydön tunnus | … |
---

<!-- _class: section -->

# SOV-2 · Oikeudellinen ja toimivaltainen suvereniteetti

---
<!-- _class: table -->

# SOV-2 · Kriittiset tarkastuskohtia

| Kysymys · tyyppi/min. | Tarkastus | Vaadittu todiste |
| --- | --- | --- |
| 2.1 · K·2+ | Mikä oikeus koskee sopimusta ja mikä tuomioistuin on pätevä? | Sopimuksen teksti, oikeudellinen ja tuomioistuimen valinta |
| 2.2 · K·3+ | Voiko EU:n ulkopuolella oleva valtio pakottaa pääsyn tai yhteistyön ja onko olemassa riippumatonta oikeussuojaa? | Juridiset neuvot, ryhmärakenteet ja analyysi per oikeusjärjestelmä |
| 2.3 · K·2+ | Onko olemassa ilmoitusvelvollisuutta hallituksen tiedustelupyyntöihin datan tarkasteluun? | Sopimuksen ehtoja, läpinäkyvyysraportti |
| 2.6 · K·2+ | Onko sopimuksessa määritelty menettelyjä ulkomaisten oikeudellisten pyyntöjen kiistämiseen? | Sopimuksen ehtoja, tarjoajan politiikka |
| 2.7 · K·2+ | Onko tietojen oikeellisuus perusteltu kaikissa asiaankuuluvissa oikeusjärjestelmissä? | DPIA, siirtotietojen arviointi, Data Act -toimenpiteet, luokittelusäännökset ja toimialakohtaiset säännökset |
---
<!-- _class: table -->

# SOV-2 · Tukitarkastuskohtia

| Kysymys · tyyppi/min. | Tarkastus | Vaadittu todiste |
| --- | --- | --- |
| 2.4 · O·2+ | Onko olemassa lähdekoodin escrow ja millä ehdoilla se on saatavilla? | Escrow-sopimus, notaarijulkaisu |
| 2.5 · O·2+ | Voidaanko sopimusoikeuksia tehokkaasti lunastaa EU:n tuomioistuimessa? | Juridiset neuvot, sopimusanalyysi |
---
<!-- _class: table table-editable -->

# SOV-2 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktuaalinen löydös | Lähde-ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 2.1 · Oikeus ja pätevä tuomioistuin (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Ulkomaalainen pakottaminen ja oikeussuoja (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Ilmoitusvelvollisuus hallituksen pyynnöistä (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Lähdekoodin escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Lunastettavissa EU:n tuomioistuimessa (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Ulkomaalaisen pyynnön kiistaminen (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Tietojen oikeellisuus (K·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-2 · Tason määritys

| Taso | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Ei tietoa | Sovellettava laki ja toimivalta ovat epäselviä | Ei mitään |
| 1 | Consciousness | Lakianalyysi ilman sopimustakuuta | 1 |
| 2 | Sopimusankkurointi | Lain valinta, foorumin valinta ja raportointivelvollisuudet; jäännösaltistus analysoitiin | 2 |
| 3 | Käytännöllinen ohjaus | Kiistamenettelyt ja sulkutili on perustettu ja todistettavasti toteutettavissa | 3 |
| 4 | Tehokas täytäntöönpanokelpoisuus | QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQOikeet ovat tehokkaasti täytäntöönpanokelpoisia ja eksterritoriaaliset riskit arvioidaan säännöllisesti | 4 |

---
<!-- _class: table table-editable -->

# SOV-2 · Keskeinen johtopäätös

| Perustelu keskeiselle pisteytykselle | Toteutus |
| --- | --- |
| Faktuaalinen tilanne ja sopiva ominaisuus asteikosta | … |
| Alin todiste kriittisille kysymyksille, lähde-ID:t mukana | … |
| Käytettyjen sääntöjen ja mahdollisten rajoitusten soveltaminen | … |
| Tärkein riski ja löydön tunnus | … |
---

<!-- _class: section -->

# SOV-3 · Tietojen ja tekoälyn suvereniteetti

---
<!-- _class: table -->

# SOV-3 · Arviointikysymykset

| Kysymys · tyyppi/min. | Arviointikysymys | Vaadittu todiste |
| --- | --- | --- |
| 3.1 · K·3+ | Ken hallinnoivat salausavaimia: tilaaja, tarjoaja vai kolmas osapuoli? | Arkkitehtuuri, avaimeluokitus, BYOK- tai HYOK-konfiguraatio |
| 3.2 · K·3+ | Onko todistettavissa, kuka, milloin ja mistä sijainnista on päässyt käsiksi dataan? | Lokit, auditoitava jälki, SIEM-raportointi |
| 3.3 · K·2+ | Säilyvätkö ja prosessoidetaanko tiedot, mukaan lukien varmuuskopiot, telemetria ja tuki, pysyvästi EU:ssa? | DPIA, arkkitehtuuri, alihankkijat, datakeskusten sijainnit |
| 3.4 · O·2+ | Onko datan käyttöä tekoälyharjoitteluun tai mallin parantamiseen säännelty sopimuksella? | Sopimus, käsittelysopimus |
| 3.5 · O·2+ | Voidaanko data todistettavasti poistaa pysyvästi, mukaan lukien varmuuskopiot ja johdettavat datasetit? | Poistotodistus, menettely, sopimus |
| 3.6 · O·2+ | Onko tuetun pääsyn järjestetty ja rekisteröity? | Tukiperiaate, lokit, sopimus |
---
<!-- _class: table table-editable -->

# SOV-3 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktuaalinen löydös | Lähde-ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 3.1 · Avainten hallinta (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Todistettava datan lähestyminen (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Säilytys ja käsittely EU:ssa (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · Ei AI-koulutusta datalla (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Lopullinen poisto (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Hallittu tuki pääsy (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-3 · Tason määritys

| Taso | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Ei ohjausta | Aproviderilla on todellinen pääsy ja avainhallinta | Ei mitään |
| 1 | EU tallennustila | EU varastointi sovittu; pääsy- tai avainhallinta on jaettu tai epäselvä | 1 |
| 2 | Teknisesti vahvistettu | Asiakaslähtöinen avainten hallinta ja pääsyrajoitukset; palveluntarjoaja voi silti käyttää avaimia tai luettavia tietoja | 2 |
| 3 | ASuojattu ohjaus | Vain asiakas hallitsee avaimia; palveluntarjoaja ei näe luettavissa olevia tietoja; käsittely jää EU:hun | 3 |
| 4 | Täysi ohjaus | Tiedon, avainten, tekoälymallien ja käsittelyn täysi hallinta | 4 |

---
<!-- _class: table table-editable -->

# SOV-3 · Keskeinen johtopäätös

| Perustelu keskeiselle pisteytykselle | Toteutus |
| --- | --- |
| Faktuaalinen tilanne ja sopiva ominaisuus asteikosta | … |
| Alin todiste kriittisille kysymyksille, lähde-ID:t mukana | … |
| Käytettyjen sääntöjen ja mahdollisten rajoitusten soveltaminen | … |
| Tärkein riski ja löydön tunnus | … |

Here's the translated Markdown slide blocks from Dutch to professional Finnish, preserving all markers and identifiers as requested:
---

<!-- _class: section -->

# SOV-4 · Toiminnallinen itsemääräämisoikeus

---
# SOV-4 · Kyselykset

| Kysymys · tyyppi/min. | Kyselykset | Vaadittu todiste |
| --- | --- | --- |
| 4.1 · K·2+ | Onko migraatio dokumentoitu ja testattu ja ovatko tiedot ja konfiguraatiot täysin siirrettävissä? | Migraatioprosessi, vientitesti, Data Act -säännökset |
| 4.2 · K·2+ | Voiko toiminnanohjaus ja päivittäinen hallinta suorittaa kokonaan EU:n henkilöstön toimesta? | Henkilöstöluettelo, tukupaikka, SLA |
| 4.3 · O·2+ | Onko toiminnan tietopohja siirrettävissä eikä sitä ole ainoastaan toimittajan hallussa? | Koulutussuunnitelma, tietotesti, dokumentaatio |
| 4.4 · O·2+ | Onko organisaatiolla täydellistä teknistä dokumentaatiota ja toimintaohjeita? | Dokumentaatiolistaus, toimintaohjeet |
| 4.5 · O·1+ | Ovatko kriittiset alihankkijat tunnettuja ja realistisesti korvattavissa? | Alihankkijaluettelo, vaihtoehtoanalyysi |
| 4.6 · O·2+ | Onko olemassa poistoprosessi realistisilla siirtymäajoilla ja kustannuksilla? | Poistostrategia, migraatiokustannuslaskelma |
---
# SOV-4 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktinen löydös | Lähteiden ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 4.1 · Testattu migraatio ja vienti (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Hallinta EU:n henkilöstön toimesta (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Siirrettävä toimintatiedot (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Dokumentaatio ja toimintaohjeet (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Korvattavat alihankkijat (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Realistinen poisto (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-4 · Tason määritys

| Taso | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Ariippuvainen | Toiminta on täysin riippuvainen EU:n ulkopuolisista toimittajista tai henkilöstöstä | Ei mitään |
| 1 | Vaikuttava | EU toiminta paperilla; kriittisiin toimiin EU:n ulkopuolella voidaan vaikuttaa | 1 |
| 2 | Käytettävissä riippuvuuksien kanssa | EU hyväksikäyttö mahdollista; tärkeitä riippuvuuksia tai lukittumista | 2 |
| 3 | Merkittävä ohjaus | EU toimijoiden valvontaa; tuki on EU:hun sidottu, kirjattu ja sallittu; poistuminen on realistista | 3 |
| 4 | In ohjaus |  Täysi EU:n toiminta ilman kriittisiä EU:n ulkopuolisia riippuvuuksia | 4 |

---
# SOV-4 · Tavoitepäätelmä

| Perustelu keskeiselle tuloskortille | Toteutus |
| --- | --- |
| Faktinen tilanne ja sopiva ominaisuus asteikolta | … |
| Alin todiste kriittisillä kysymyksillä, lähteiden ID:illä | … |
| Käytetyt säännöt ja mahdolliset rajoitukset | … |
| Tärkein syy, riski ja löydöksen ID | … |
---

<!-- _class: section -->

# SOV-5 · Ketjun itsemääräämisoikeus

---
# SOV-5 · Kyselykset

| Kysymys · tyyppi/min. | Kyselykset | Vaadittu todiste |
| --- | --- | --- |
| 5.1 · K·2+ | Onko ajantasainen SBOM saatavilla ohjelmistolle palvelussa? | SBOM, toimittajan ilmoitus |
| 5.2 · O·1+ | Onko laitteiston ja firmwaren alkuperä ja EU:n ulkopuoliset riippuvuudet tiedossa? | Laitteistolistaus, firmware-näkymä, ilmoitus |
| 5.3 · K·2+ | Voidaanko päivitykset suorittaa vaiheittain, validoida ja peruuttaa laajamittaisen käyttöönoton edellä? | Päivityspolitiikka, konfiguraatio, testiraportti |
| 5.4 · O·1+ | Onko rakennus- ja allekirjoitusinfrastruktuurin sijainti ja oikeusjärjestelmä tiedossa? | Tekninen dokumentaatio, arkkitehtuurikaavio |
| 5.5 · K·2+ | Ovatko kaikki alihankkijat tunnettuja ja onko muutosehtaus säännöksellisesti järjestetty? | Alihankkijaluettelo, sopimusehto |
| 5.6 · O·2+ | Onko alihankkijoiden tarkastus-oikeuksia säännöksellisesti vahvistettu? | Sopimusehdot, tarkastusraportit |
---
# SOV-5 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktinen löydös | Lähteiden ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 5.1 · Ajantasainen SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Laitteiston ja firmwaren alkuperä (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Päivitykset validoidaan ja peruutetaan (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Rakennus- ja allekirjoitusoikeudet (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Alihankkijat ja muutosehtaus (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Alihankkijoiden tarkastus-oikeudet (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-5 · Tason määritys

| Level | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Ei vaikutusta | Kriittinen ketju täysin EU:n vaikutusvallan ulkopuolella | Ei mitään |
| 1 | Päivystämätön | EU-lakia sovelletaan muodollisesti, mutta ketju on läpinäkymätön | 1 |
| 2 | Insight riippuvuuksilla | Chain oivaltavaa; merkittäviä riippuvuuksia EU:n ulkopuolelta | 2 |
| 3 | Merkittävä vaikutus | Kriittiset linkit ovat monipuolisia; päivitykset ovat tarkistettavissa; rakentamis- ja allekirjoitusketju tunnetaan | 3 |
| 4 | Läpinäkyvä ja hallinnassa | QTäysi läpinäkyvyys ilman kriittisiä EU:n ulkopuolisia riippuvuuksia | 4 |

---
# SOV-5 · Tavoitepäätelmä

| Perustelu keskeiselle tuloskortille | Toteutus |
| --- | --- |
| Faktinen tilanne ja sopiva ominaisuus asteikolta | … |
| Alin todiste kriittisillä kysymyksillä, lähteiden ID:illä | … |
| Käytetyt säännöt ja mahdolliset rajoitukset | … |
| Tärkein syy, riski ja löydöksen ID | … |
---

<!-- _class: section -->

# SOV-6 · Tekninen suvereniteetti

---
# SOV-6 · Kyselykset

| Kysymys · tyyppi/min. | Kyselykset | Vaadittu todiste |
| --- | --- | --- |
| 6.1 · K·2+ | Onko kaikki API:t perustuvat avoimiin ja julkisiin dokumentoituun standardeihin? | API-dokumentaatio, standardien rekisteri |
| 6.2 · K·2+ | Voidaanko kaikki tiedot siirtää ilman keskeistä toiminnallisuuden menetystä avoimeen muotoon? | Vie testi, tekninen dokumentaatio |
| 6.3 · O·2+ | Mitkä ohjelmistolisenssit ja rajoitukset mukauttamiselle tai uudelleenkäytölle koskevat? | Lisenssin teksti, oikeudellinen analyysi |
| 6.4 · O·2+ | Onko lähdekoodin tarkastus-oikeus tai escrow sopimuksessa? | Escrow-sopimus, tarkastusraportti |
| 6.5 · O·1+ | Onko koko stack dokumentoitu, mukaan lukien suljetut komponentit ja vaihtoehdot? | Arkkitehtuuri, komponenttien rekisteri |
| 6.6 · O·2+ | Onko migraatio vaihtoehtoon realistinen ja testattu? | Migraatiotesti, poistostrategia, vaihtoehtoanalyysi |
---
# SOV-6 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktinen löydös | Lähteiden ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 6.1 · Avoimet ja dokumentoidut API:t (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Tiedot avoimeen muotoon (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Lisenssit ja mukauttaminen (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Lähdekoodin tarkastus tai escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Dokumentoitu stack (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Testattu migraatio vaihtoehtoon (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-6 · Tason määritys

| Level | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Suljettu | Suljettu ekosysteemi; maahanmuutto on käytännössä mahdotonta | Ei mitään |
| 1 | Lukitse sisään | Jokin linkitettävyys; lock-in pysyy hallitsevana | 1 |
| 2 | Siirrettävä | Yhteentoimivuus ja vienti on järjestetty; tarkastus- ja escrow-vaihtoehdot ovat olemassa | 2 |
| 3 | Merkittävän itsenäinen | Vaihdettavuus on testattu ja kriittiset ohjelmistot voidaan varmentaa auditoinnin tai avoimen lähdekoodin avulla | 3 |
| 4 | In ohjaus | Täysi integroinnin ja standardien hallinta ilman kriittisiä suljettuja riippuvuuksia | 4 |

---
<!-- _class: table table-editable -->

# SOV-6 · Keskeisaranto

| Keskeisen perustelut pisteytykseen | Toteutus |
| --- | --- |
| Faktuaalinen tilanne ja sopiva ominaisuus asteikosta | … |
| Alimmat todisteet kriittisille kysymyksille, lähde-ID:t mukana | … |
| Säännön 5 soveltaminen ja mahdolliset rajoitukset | … |
| Tärkein syy, riski ja löydön-ID | … |
---

<!-- _class: section -->

# SOV-7 · Turvallisuus ja vaatimustenmukaisuuden riippumattomuus

---
<!-- _class: table -->

# SOV-7 · Arviointikysymykset

| Kysymys · tyyppi/min. | Arviointikysymys | Vaadittu todiste |
| --- | --- | --- |
| 7.1 · K·3+ | Onko tarjoaja sertifioitu tunnetulla standardilla ja kuuluuko auditoinnin valvonta EU:n alaisuudessa? | Sertifikaatti, audittrakti, laajuus |
| 7.2 · K·2+ | Onko tarjoajan SOC sijaitsee EU:ssa ja toimii EU:n lainsäädännön alaisuudessa? | SOC-sijainti, sopimus, SLA |
| 7.3 · O·3+ | Onko NIS2, DORA, GDPR ja CRA noudattaminen todistettu ja ulkopuolisesti vahvistettu? | Noudattamisraportti, valvontaviranomainen, audit |
| 7.4 · K·2+ | Kuka suorittaa haavoittuvuuksien hallinnan ja päivitykset ja pystyykö se toimimaan itsenäisesti EU:ssa? | Päivityspolitiikka, SLA, tekninen dokumentaatio |
| 7.5 · K·2+ | Ovatko auditoinnin oikeudet käytännössä toteutettavissa, mukaan lukien järjestelmä- ja lokitunnukset? | Sopimuksellinen auditoinnin oikeus, suoritettu audittrakti |
| 7.6 · O·2+ | Onko ilmoitusmenettely tietovuodoille ja tapahtumille GDPR-yhteensopiva ja todistettavasti toteutettu? | Tapahtumasuunnitelma, käsittösopimus, ilmoitusrekisteri |
---
<!-- _class: table table-editable -->

# SOV-7 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktuaalinen löydös | Lähde-ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 7.1 · Sertifiointi EU:n valvonnassa (K·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · SOC EU:ssa EU:n lainsäädännön alaisuudessa (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Ulkopuolisesti vahvistettu noudattaminen (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU:n haavoittuvuuksien hallinta (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Käytännössä toteutettavat auditoinnin oikeudet (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · GDPR-yhteensopiva ilmoitusmenettely (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-7 · Tason määritys

| Level | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Ariippuvainen | Turvallisuustoiminta on täysin EU:n ulkopuolisen valvonnan alainen | Ei mitään |
| 1 | Vaikuttava yhteensopiva | Muodollinen noudattaminen; täytäntöönpano EU:n ulkopuolella on edelleen vaikutuksen alainen | 1 |
| 2 | Sopimustakuu | EU lainkäyttöalue, tilintarkastus- ja raportointivelvoitteet ovat sopimuksilla säänneltyjä | 2 |
| 3 | EU toimintaa | EU-turvatoimet ovat tehokkaita ja riippumattomat auditoinnit ovat mahdollisia | 3 |
| 4 | In ohjaus | Täydellinen valvonta, häiriötilanteisiin reagointi, korjaus ja vaatimustenmukaisuus | 4 |

---
<!-- _class: table table-editable -->

# SOV-7 · Keskeisaranto

| Keskeisen pisteytyksen perustelut | Toteutus |
| --- | --- |
| Faktuaalinen tilanne ja sopiva ominaisuus asteikosta | … |
| Alimmat todisteet kriittisille kysymyksille, lähde-ID:t mukana | … |
| Sovelletut säännöt ja mahdolliset rajoitukset | … |
| Tärkein syy, riski ja löydön-ID | … |
---

<!-- _class: section -->

# SOV-8 · Kestävän kehityksen suvereniteetti

---
<!-- _class: table -->

# SOV-8 · Arviointikysymykset

| Kysymys · tyyppi/min. | Arviointikysymys | Vaadittu todiste |
| --- | --- | --- |
| 8.1 · K·2+ | Mikä on mitattu PUE datakeskuksittain? | Datakeskusraportointi, itsenäinen mittaus |
| 8.2 · O·2+ | Onko energia todistettavasti uusiutuvaa ja onko sertifikaatit ulkopuolisesti vahvistettu? | Energiasertifikaatit, itsenäinen raportti |
| 8.3 · O·2+ | Onko CO2-päästö ja vesihuolto läpinäkyvää ja ulkopuolisesti vahvistettu? | ESG-raportti, tilintarkastuskertomus, GRI |
| 8.4 · O·1+ | Onko laitteiden käyttöikäs- ja e-jätteenkäsittelypolitiikka dokumentoitu ja tarkistettavissa? | Politiikka, ISO 14001-sertifikaatti |
| 8.5 · O·1+ | Onko riippuvuutta kriittisistä raaka-aineista arvioitu? | Riskianalyysi, toimittajaseloste |
| 8.6 · O·1+ | Onko tarjoaja alainen CSRD:lle ja ovatko raportit julkisia; eivätkä, raportoi se vapaaehtoisesti? | Vuosikertomus, CSRD- tai vapaaehtoinen raportointi |
---
<!-- _class: table table-editable -->

# SOV-8 · Löydökset ja todisteet

| Kysymys · tyyppi/min. | Faktuaalinen löydös | Lähde-ID | Todiste 0-4 | Vaikutus / riski |
| --- | --- | --- | --- | --- |
| 8.1 · Mitattu PUE paikkakunnittain (K·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Vahvistettu uusiutuva energia (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · CO2 ja vesihuolto ulkopuolisesti vahvistettu (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Laitteiden käyttöikäs- ja e-jätteenkäsittelypolitiikka (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Kriittisten raaka-aineiden arviointi (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD tai vapaaehtoinen raportointi (O·1+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-8 · Tason määritys

| Taso | Label | Attribuutti | Min. todiste |
| --- | --- | --- | --- |
| 0 | Päivystämätön | Ei läpinäkyvyyttä; hallitseva EU:n ulkopuolinen riippuvuus energiasta tai materiaaleista | Ei mitään |
| 1 | Perusraportointi | Perusraportointi saatavilla; merkittäviä rakenteellisia riippuvuuksia | 1 |
| 2 | Läpinäkyvä riippuvuuksilla | Avoimuus ja sopimusvaatimukset saatavilla; aineelliset riippuvuudet säilyvät | 2 |
| 3 | Vaikutus | Mertävä EU:n vaikutus energialähteeseen ja kiertoketjuun | 3 |
| 4 | Kestävä | QTäysin kestävä, läpinäkyvä ja EU-ankkuroitu rakenneseurannalla | 4 |

---
<!-- _class: table table-editable -->

# SOV-8 · Keskeisaranto

| Keskeisen pisteytyksen perustelut | Toteutus |
| --- | --- |
| Faktuaalinen tilanne ja sopiva ominaisuus asteikosta | … |
| Alimmat todisteet kriittisille kysymyksille, lähde-ID:t mukana | … |
| Sovelletut säännöt ja mahdolliset rajoitukset | … |
| Tärkein syy, riski ja löydön-ID | … |
---

<!-- _class: section -->

# Päätelmä ja varmennuslausunto

---

<!-- _class: table table-editable -->

# Laitius tietotyypin mukaan · Rivi 0

| Tietotyyppi | Test-kehys |  Perusteet ja lähdetunnus | Tulos | Vaikutettu SOV-kohteeseen |
| --- | --- | --- | --- | --- |
| Henkilötiedot | AVG, mukaan lukien siirto ja asianmukaiset toimenpiteet | … |  Perusteltu / riski | … |
| Ei-henkilökohtaiset yritystiedot | Datalain 32 artikla | … |  Perusteltu / riski | … |
| Hallituksen tai turvaluokiteltuja tietoja | Sovellettavat kansalliset ja EU:n säännöt | … |  Perusteltu / riski | … |
| Säännellyt sektoritiedot | NIS2, DORA tai alakohtaiset säännöt | … |  Perusteltu / riski | … |

---

<!-- _class: table table-editable -->

# Altistuminen oikeudellisille määräyksille · Sääntö 4

|  Puolue ja oikeusjärjestys | Voiko hallitus voimia? | Riippumaton oikeusprosessi? | Voidaanko asiakkaalle tehdä ilmoitus? | Seuraus todisteeksi ja tasolle |
| --- | --- | --- | --- | --- |
| … | Kyllä / ei / epävarma | Kyllä / ei / epävarma | Kyllä / ei / epävarma | … |
| … | … | … | … | … |
| … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Kohtaus 4 · Pakollinen tulos

| Ehdoitus tai seuraus | Varmistus-ID ja vahvistus |
| --- | --- |
| Hallitus voi määrätä pääsyn tai yhteistyön | Kyllä / ei / epäselvä: … |
| Riippumaton oikeudenkäynti puuttuu tai kuluttajalle ilmoittamista on kielletty | Kyllä / ei / epäselvä: … |
| Jos molemmat pätevät: kysymykset 2.3, 2.5 ja 2.6 lasketaan todistustasolla 0 | Soveltunut / ei soveltuva: … |
| Jos molemmat pätevät: SOV-2 on enintään taso 1 | Soveltunut / ei soveltuva: … |
| Jos hallinto-oikeus on olemassa kyseisessä oikeusjärjestelmässä, myös SOV-1 on enintään taso 1 | Soveltunut / ei soveltuva: … |
| Jäljelle jäänyt altistuminen | … |
---
<!-- _class: table table-editable -->

# Tekninen reitti · Sääntö 5

| Ehdotus | Lopputulos ja lähde-ID |
| --- | --- |
| SOV-3 on vähintään taso 3: avaimet yksinasi asiakkaalla; toimittajalla ei ole luettavissa dataa | … |
| Ei hallinto- tai tukituloa luettavaan dataan | … |
| SOV-5 on vähintään taso 3: päivitykset valtuutettu ja peruuttamiskelpoinen; build- ja allekirjoitusketju tiedossa | … |
| SOV-6 on vähintään taso 3: kriittisen ohjelmiston toiminta tarkistettavissa | … |
| Palvelulla ei tarvitse käsitellä dataa luettavassa muodossa | Kyllä / ei |
| Kaikki ehdot täyttyvät | Vain "kyllä", jos kaikki edelliset tulokset ovat positiivisia: … |
| Lopputulos | Voi tukea Sääntöä 0; ei muuta SOV-2:ta tai SEAL:in kokotasoa. |
---
<!-- _class: table table-editable -->

# SAFARI-tulostaulu

| Koodi | Painoarvo | Asettelu 0-4 | Todiste 0-4 | Arvio valitun normin mukaan | Kohdekonklusion lähde |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | 15% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-2 | 10% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-3 | 10% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-4 | 15% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-5 | 20% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-6 | 15% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-7 | 10% | … | … | Vastaa / aukko / ei ole saatavilla | … |
| SOV-8 | 5% | … | … | Vastaa / aukko / ei ole saatavilla | … |
---
<!-- _class: table table-editable -->

# Kokonaistulos

| Osa | Lopputulos ja perustelu |
| --- | --- |
| SEAL:in kokotasot · alin ydintavoite | … |
| Painotettu ECSF-pisteet · Σ (asettunut taso / 4 × painoarvo) | …% |
| Suurimmat aukot | … |
| Kriittiset riippuvuudet | … |
| Toivotut tasot suosituksen mukaan | … |
| Oikeudellinen riskit | … |
| Ratkaistavissa sisäisesti | … |
| Toimittajan yhteistyö tarvitaan | … |
---

<!-- _class: table table-editable -->

# Viaava CADA-asema

| Osa | Tulos ja lähdetunnus |
| --- | --- |
| Relevanssi | Julkinen sektori / kriittinen toiminta / NIS2-sektori / n.a. |
| Target CADA-taso | 1 / 2 / 3 / 4 / n.a. |
| Osaatava saavutettavissa oleva taso | 1 / 2 / 3 / 4 / ei mitään |
| Edellytykset eivät täyty | … |
| Näyttörajoitus | … |
| Pakollinen sanamuoto |  Ehdotukseen perustuva merkintä; ei tuomiota vaatimustenmukaisuudesta. |

---

<!-- _class: table table-editable -->

# Varmuusarvio tavoitetta kohti

| Target | Todista kriittiset kysymykset | Legalitaarinen riski | Tuomion tyyppi | Formulaatio ja varoitukset |
| --- | --- | --- | --- | --- |
| SOV-… | Alin taso: … | Kyllä / ei | Ei / rajoitettu / kohtuullinen | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |

---
<!-- _class: table -->

# Varmennusmuodostuksen apu

| Tyyppi | Ehdotus | Oletusmuodostus |
| --- | --- | --- |
| Ei arviointia | Kriittinen kysymys on todistusasteella 0 tai 1 | Todisteiden perusteella ei ole mahdollista tehdä arviointia [tavoitteesta] [palvelulle]. |
| Rajoitettu varmuus | Kaikki kriittiset kysymykset vähintään 2; ei kaikki vähintään 3 | Todisteidemme perusteella emme ole havainneet mitään, mikä osoittaisi [väitettä] olevan epätosi. Annamme rajatun määrän varmuutta. |
| Kohtuullinen varmuus | Kaikki kriittiset kysymykset vähintään 3 | Todisteidemme perusteella olemme sitä mieltä, että [väite]. Annamme kohtuullisen määrän varmuutta. |
---

<!-- _class: table table-editable -->

# Havainnot ja suositukset

| ID | SOV | Löytää | Impact | Asuositus | Omistaja | Term |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | … | … | Korkea / keski / matala | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |

---

<!-- _class: table table-editable -->

# Laadunvalvonta ja viitepäivämäärän jälkeiset tapahtumat

| Control | Tulos ja arvioijan viite |
| --- | --- |
| Scope ja väite määritetty ennen toteuttamista | … |
| Kaikki kriittiset kysymykset on käsitelty tai raportoitu rajoituksina | … |
| Lähdeviitteet ovat jäljitettävissä ja todisteiden tasot ovat jäljitettävissä | … |
| Pisteytyssääntöjä 0–5 on todistettavasti sovellettu | … |
| Aritmeettinen ja tekstin johdonmukaisuus on tarkistettu | … |
| Riippumaton tarkistus on saatu päätökseen | … |
| Viitepäivän jälkeiset tapahtumat on arvioitu | … |
| Loistavia mielipide-eroja on käsitelty | … |

---
<!-- _class: table table-editable -->

# Organisaation väitteen vahvistaminen

| Vahvistus | Täyttö |
| --- | --- |
| Vastuullisen osapuolen nimi ja tehtävä | … |
| Vakuutus | Väite, laajuus ja valitut normit on vahvistettu täysin ja totuudenmukaisesti. |
| Päivämäärä | … |
| Hyväksyntä | Kyllä / ei |
---
<!-- _class: table table-editable -->

# Riippumaton laaduntarkastus

| Tarkastus | Täyttö |
| --- | --- |
| Vastuullisen tarkastajan nimi ja tehtävä | … |
| Riippumaton suorituksesta | Kyllä / ei |
| Tarkastustulos ja mahdolliset avoimet kohdat | … |
| Päivämäärä | … |
| Hyväksyntä allekirjoittamiseen | Kyllä / ei |
---
<!-- _class: sign-off -->

# Varmennusarvion allekirjoitus
---
# Lähteet ja lisenssit

- Metodi: SAFARI v0.9 (konsepti), Brenno de Winter ja Stichting LibreKAT.
- Tila: Vapaaehtoinen metodi. Pienimmät normit ovat neuvoja; säännöt 0 - 5 ovat sitovia niille, jotka toteuttavat SAFARIn.
- Peruslähtökohta: Euroopan pilviomisteisuuden kehys, täydennetty ISO 27001:2022:lla ja ISAE 3000 -varmennusrakenteella.
- Koko metodi: https://pawprint.vigilis.online/LibreKAT/Safari
- Tämä mallipohja sisältö on SAFARIn muunnelma ja on CC BY-SA 4.0 -lisenssin alainen: https://creativecommons.org/licenses/by-sa/4.0/
- Täytä aina nykyinen versio, peilipäivämäärä, ammattimaiset standardit ja paikalliset lainsäädännölliset vaatimukset.
