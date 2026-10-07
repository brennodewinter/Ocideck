---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SAFARI digisuveräänsuse hindamine
language: et
standards: SAFARI@0.9, ECSF
---

<!-- _class: title -->

# SAFARI digisuveräänsuse hindamine

---
# Nii seda kasutatakse selle tööraamistiku kohta

- Mõõdu, väide, soovitud tasemed ja soovitud kindel usutase esmalt kindlaks määratud.
- Igal kontrollküsimusele sisestage leidmine, jälitamine lähtekäiguga ja tõendusaste.
- Puuduvad või keelanud tõendid käsitlemiseks kasutage leidmist tõendusastmega 0.
- Rakendage kuus hinnangureegleid enne SOV-eesmärkide taseme määramist.
- Assurance otsust formuleerige alles pärast kvaliteedi kontrolli ja pealepeale sündmuste hindamist.
---

<!-- _class: table table-editable -->

# Dokumendihalduse ja määramise meeskond

|  Väli | Lõpetamine |
| --- | --- |
| Organisatsioon | … |
| Teenus või süsteem | … |
| Liver | … |
| Client | … |
|  Nõude eest vastutav | … |
| Tegevaudiitor või konsultant | … |
| Sõltumatu ülevaataja | … |
| Viitekuupäev ja hindamisperiood | … |
| Aruande versioon ja kuupäev | … |
| TLP klassifikatsioon ja leviloend | … |

---
<!-- _class: table table-editable -->

# Objekt ja ulatus

| Ulatusekomponent | Tähendus |
| --- | --- |
| Hindamine rakendused, platvormid ja infrastruktuur | … |
| Otse tarnijad | … |
| Relevantsed allatarnijad ja riiklikud osapooled | … |
| Andide tüüp | Isikuandmeid / ettevõtteandmeid / valitsuseandmeid / klassifitseeritud teavet |
| Osapartnerite õigusnormid | … |
| Administratsiooni-, tugi-, ehituse- ja allkirjatsioonikeskused | … |
| Ekslikud erandid põhjendusega | … |
| Normatiivse raami versioon | SAFARI v0.9 (konsept; vabatahtlik meetod), ISO 27001:2022 ja ECSF-i 8 eesmärki |
---
<!-- _class: table table-editable -->

# Organisatsiooni väide

| Komponent | Täheldamine |
| --- | --- |
| Objekt | [Organisatsioon] on hinnanud [teenuse] sovetuspositsiooni, mille [pakkuja] on pakkunud. |
| Ajavaik | Hinnang puudub [kuupäev] ulatuses, mis on kindlaks tehtud [kuupäev]. |
| Rahastamine | Hinnang on tehtud ISO 27001:2022 ja ECSF-i 8 eesmärki alusel, SAFARI v0.9 vabatahtlik konseptmeetod. |
| Tulemus | Organisatsioon väidab, et see vastab valitud tasemele [0-4] [SOV-kood või kõik eesmärgid]. |
| Mõistetus | Tulemus põhineb pealepeale tõendusmaterjalidel; muutused võivad tulemust mõjutada. |
| Omamees ja ametlik kinnitamine | … |
---
<!-- _class: table table-editable -->

# Soovitavad tasemed ja keskmeesmärgid

| Kood | Eesmärk | Keskmeesmärk | Soovitav min. | Soovitav | Põhjendus erinevuste korral |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Strateegiline | Jah | 2 | … | … |
| SOV-2 | Juridiline ja õiguslik | Jah | 2 | … | … |
| SOV-3 | Data ja AI | Jah | 3 (2 ainult madala tundlikkusel ja ilma isikuandmete abil) | … | … |
| SOV-4 | Operatiivne | Jah | 3 (2 ainult madala tundlikkusel, asendatav ja ilma isikuandmete abil) | … | … |
| SOV-5 | Riiklik | Jah | 3 (2 ainult madala tundlikkusel ja ilma isikuandmete abil) | … | … |
| SOV-6 | Tehnoloogia | Jah | 3 (2 ainult madala tundlikkusel ja ilma isikuandmete abil) | … | … |
| SOV-7 | Turvallisuus ja compliance | Jah | 2 | … | … |
| SOV-8 | Kestevus | Jah | 1 | … | … |
---

<!-- _class: table table-editable -->

# Akindluse lähenemisviis

| Part | Valik ja põhjendus |
| --- | --- |
| Käsu tüüp |  Nõustamine / piiratud kindlus / mõistlik kindlus |
| Eesmärgid kindluse väites | … |
| Materiaalsus ja riskile orienteeritud valik | … |
| Tegevused tõendite liikide kaupa | Kontroll / vaatlus / uuesti teostamine / kinnitamine / analüüs |
| Samplemise lähenemisviis ja populatsioonid | … |
| Eksperdid on kasutusele võetud | Juriidiline / tehniline / jätkusuutlikkus / muu: … |
| Sõltumatus ja huvide konfliktid | … |
|  Juurdepääsu või tegevuste piirangud | … |

---
<!-- _class: table table-editable -->

# Tehtestamisehe rakendamine formaalselt kindlustamisel

| Kriteerium vastuvõetmine | Ühildamine ja allikas | Järeldus |
| --- | --- | --- |
| SAFARI on sobiv kriteerium väite kinnitamiseks ja mõttelehe kasutajatele | … | Jah / Ei |
| Vastutav osapool tunnustab oma vastutust väite eest | … | Jah / Ei |
| Loomulik eesmärk, mõttelehe kasutajad ja levitamiskogud on kindlalt määratud | … | Jah / Ei |
| Isikupärasus, eetika, pädevus ja vajalikud eksperdid on tagatud | … | Jah / Ei |
| Tehtestamise tingimused ja soovitatud kindlustustase on kokku lepitud | … | Jah / Ei |
| Piisavalt sobivad tõendid on oodata | … | Jah / Ei |
| Tehtestamise otsus | Ühtsete kriteeriumide puhul ainult jätkamine | Vastuvõtta / Mitte vastuvõtta |
---

<!-- _class: table -->

# Tõendite tasemed

| Level | Name | Rakendus |
| --- | --- | --- |
| 0 | Tõendeid pole | Põhjendus puudub või tõendid puuduvad või neist keeldutakse |
| 1 |  avaldus | Suuline või kirjalik avaldus ilma täiendava põhjenduseta |
| 2 | Dokumentatsioon | Leping, poliitika, protseduur või aruanne ilma sõltumatu kontrollita |
| 3 | Tehniline tõestus | Konfiguratsioon, logi, test või väline juriidiline nõustamine, mille klient on saanud |
| 4 | Sõltumatuid tõendeid | Sõltumatu testija poolt kogutud või kontrollitud |

---

<!-- _class: table table-editable -->

# Keskne tõendite register

| Allika ID | Dokument või registreerimine | Omanik | Kuupäev ja versioon | Päritolu | Terviklikkus ja ladustamiskoht |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Sisemine / tarnija / väline | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |

---
<!-- _class: table -->

# Obligaatorlikud hinnangureeglid

| Reegel | Tagajärjed hinnangule |
| --- | --- |
| 0 · Seaduslikkus | Seaduslikkusriski tähendab, et iga seotud eesmärk on alati puudu; soovitada õigusanalüüsi. |
| 1 · Kriitilised küsimused | Hinnanguhind 0 kriitilise küsimuse puhul piirab eesmärk maksimaalse hinnanguga 1. |
| 2 · Hinnang on toetav | Hinnang alla minimaalse küsimuse tasemele on 0. Eesmardehinnangud on madalaima hinnanguga kriitiliste küsimuste puhul; hinnangud 2, 3 ja 4 nõuavad seda minimaalse tasemega. |
| 3 · Hea osa | SEAL-tähtis tase on kõige madalemate kinnitatud eesmärkide tasemest. |
| 4 · Toimiv õigusriik | Kui sundimine on jõustatav ja isärane õigusruum või suhtlusvõimalus puudub, loetakse 2.3, 2.5 ja 2.6 hinnanguks 0; SOV-2 on maksimaalselt 1, ja SOV-1 ka, kui kontrollijuht on selles. |
| 5 · Tekhniline tee | Kui sundimine on jõustatav välismaisel juurdepääsul, kaitseb ainult kogu tehniline tee; see ei muuda SOV-2 ega SEAL-taset. Teenus, mis peab töötlema loetavat andmeid, ei saa seda kasutada. |
---

<!-- _class: section -->

# SOV-1 · Strateegiline suveräänsus

---
<!-- _class: table -->

# SOV-1 · Peamised küsimused

| Küsimus · tüüp/min. | Peamine küsimus | Nõutav tõendus |
| --- | --- | --- |
| 1.1 · K·2+ | Kes on lõppjuhtid ja millise õigusruumi järgi nad on registreeritud? | UBO registreerimine, aastaaruanded, juhatuse registreerimine |
| 1.2 · K·2+ | Kas väljaspool EL asuva emaettevõtja saab kohustada strateegilist suunamuutusse? | Grupi struktuur skeem, põhikirjad, juhatuse käsutus |
| 1.3 · K·2+ | Sisaldab leping muudatusjuhtum-kontrolli klausule? | Kontrakt tekst |
| 1.4 · O·1+ | Kas tehnoloogia ja IP on asukohtunud EL-i ühte või välismaisele emasse ettevõtja? | IP registreerimine, litsents lepingud |
| 1.5 · O·2+ | Kas tarnijafhankelijkus on avaldatud ja fikseeritud juhatuse tasandil? | Juhatuse protokollid, riski registreerimine |
| 1.6 · O·2+ | Kas on väljapääs- või jätkuse skenaarium omanike muutmise korral? | Jätkuse planeering, väljapääs strateegia |
---
<!-- _class: table table-editable -->

# SOV-1 · Järeldused ja tõendid

| Küsimus · tüüp/min. | Tegus leidmine | Allikas-ID | Tõend 0-4 | Vaikkude / Riski tasem |
| --- | --- | --- | --- | --- |
| 1.1 · UBO ja õigusriik (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Üldkoosseid saab väljendada (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Kontrolli muudatus (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Asukoht tehnoloogia ja IP (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Tuginedes nõudmisel juhatusel (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Väljapääs omanike muutmise korral (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-1 · Taseme määramine

|  Tase | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 |  Puudub ülevaade | Pole ülevaadet omandi- või võimustruktuurist | Puudub |
| 1 | Insight | Insight on saadaval, kuid garantii puudub omanikuvahetuse korral | 1 |
| 2 | Lepinguline garantii | Juhtimise muutmine ja läbipaistvus on lepinguga kokku lepitud | 2 |
| 3 | Control | EU juhtimine on eraldiseisev ja jõustatav; mõju väljaspool ELi on tõsiselt piiratud | 3 |
| 4 | Strateegiline autonoomia | Säästlikult Euroopa manustatud; sõltuvust kaalutakse selgelt juhatuse otsuses | 4 |

---
<!-- _class: table table-editable -->

# SOV-1 · Peamine Järeldus

| Põhjus, millele tuginedakse peapõrgukirja kohta | Rakendamine |
| --- | --- |
| Faktuualine olukord ja sobiv tunnus skaalalt | … |
| Madalaim tõend kriitiliste küsimuste kohta, koos lähtekoodiga ID-dega | … |
| Rakendatud reeglid ja võimalik piirang | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# SOV-2 · Õiguslik ja jurisdiktsiooniline suveräänsus

---
<!-- _class: table -->

# SOV-2 · Kriitilised Testimisõiged

| Küsimus · tüüp/min. | Testimisõiged | Vajalik tõend |
| --- | --- | --- |
| 2.1 · K·2+ | Milline õigus kehtib kontraktsiooni jaoks ja milline kohtunik on pädev? | Kontrakttekst õigus- ja kohtupädevusvaliku kohta |
| 2.2 · K·3+ | Kas valitsus väljaspool EL-i võib nõuda juurdepääsu või koostööd ja kas on sõltumatu õigussõnum? | Juridiline nõustamine, rühmatruktuur ja analüüs iga õigusjärjekorra kohta |
| 2.3 · K·2+ | Kas on kohustus teatada, kui valitsuse päringu kohta andmete vaatamiseks? | Kontraktiklausul, läbipaequivuse aruke |
| 2.6 · K·2+ | Kas välismaise kohtu päringu vaidlustamine on kokku lepitud kontraktsiooni kohta? | Kontraktiklausul, pakkuja poliitika |
| 2.7 · K·2+ | Kas andmete legitiimsus on põhjendatud kõigi osalejate õigusjärjekordade kohta? | DPIA, edasiandekontroll, Data Act -meetmed, klassifitseerimis- ja sektorireeglid |
---
<!-- _class: table -->

# SOV-2 · Toetavad Testimisõiged

| Küsimus · tüüp/min. | Testimisõiged | Vajalik tõend |
| --- | --- | --- |
| 2.4 · O·2+ | Kas on olemas lähtekoodi hoiukontrakt ja millistel tingimustel on see saadaval? | Hoiukontrakt, notariaalne kinnitus |
| 2.5 · O·2+ | Kas kontraktsiooniõigusi saab tõhusalt jõustada ELi kohtus? | Juridiline nõustamine, kontraktsiaanalüüs |
---
<!-- _class: table table-editable -->

# SOV-2 · Leidmised ja Tõendid

| Küsimus · tüüp/min. | Faktuualine leidmine | Lähtekoodiga ID | Tõend 0-4 | Mõju / Risk |
| --- | --- | --- | --- | --- |
| 2.1 · Ühiku õigus ja pädev kohtunik (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Välismaise sundimine ja õigussõnum (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Teavitamiskohtutamine valitsuse päringu kohta (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Lähtekoodi hoiukontrakt (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Jõustatav ELi kohtus (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Välismaise päringu vaidlustamine (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Andmete legitiimsus (K·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-2 · Taseme määramine

|  Tase | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 |  Puudub ülevaade |  Kohaldatav seadus ja jurisdiktsioon on ebaselged | Puudub |
| 1 |  Teadvus | Juriidiline analüüs ilma lepingulise garantiita | 1 |
| 2 | Lepinguline ankurdamine | Õiguse valik, foorumi valik ja aruandluskohustused; jääkkokkupuudet analüüsiti | 2 |
| 3 | Praktiline juhtimine |  Vaidlusprotseduurid ja tingdeponeerimine on loodud ja on tõestatavalt teostatavad | 3 |
| 4 | Tõhus jõustatavus | Õigused on tõhusalt jõustatavad ja eksterritoriaalseid riske hinnatakse perioodiliselt | 4 |

---
<!-- _class: table table-editable -->

# SOV-2 · Peatükikehtestamine

| Põhjendus keskmise tulemuse jaoks | Tähtaotus |
| --- | --- |
| Faktualine olukord ja sobiv tunnusgraaf skaalast | … |
| Madalaim tõend kriitiliste küsimuste kohta, koos lähtekoodiga ID-dega | … |
| Määrelemine reeglite 0 ja 4 rakendamine ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# SOV-3 · Andmete ja tehisintellekti suveräänsus

---
<!-- _class: table -->

# SOV-3 · Testküsimused

| Küsimus · tüüp/min. | Testküsimus | Vajalik tõend |
| --- | --- | --- |
| 3.1 · K·3+ | Kes hallab krüptivõtmeid: ostja, müüja või kolmas pool? | Arhitektuur, võtmeeskond, BYOK- või HYOK-konfiguratsioon |
| 3.2 · K·3+ | Kas on näidatud kes, millal ja millisest kohast andmeid on lähenud? | Logid, auditi traidi, SIEM-raportid |
| 3.3 · K·2+ | Kas püsiv ja töötlemine, sealhulja taastused, telemeetria ja toetus on näidatud ELis? | DPIA, arhitektuur, allhankurid, andmesertifikaatide kohad |
| 3.4 · O·2+ | Kas andmete kasutamine AI-õppimiseks või mudelite parendamiseks on lepinguga keelatud? | Kontrakt, andmevahetuskokkumine |
| 3.5 · O·2+ | Kas andmeid saab näidatud kindlalt kustutada, sealhulja taastused ja tuletatud andmestikud? | Kindluse kinnitus, protseduur, leping |
| 3.6 · O·2+ | Kas toetusjuurde pääsemine on reguleeritud ja seda logitakse? | Toetuspoliitika, logid, leping |
---
<!-- _class: table table-editable -->

# SOV-3 · Leidmised ja tõendid

| Küsimus · tüüp/min. | Faktualine leidmine | Lähtekoodiga ID | Tõend 0-4 | Mõju / risk |
| --- | --- | --- | --- | --- |
| 3.1 · Krüptivõtmete haldus (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Taaskäidutav andmesõid (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Püsiv ja töötlemine ELis (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · AI-õpe andmetega keelatud (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Kindel kustutamine (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Reguleeritud toetusjuurde pääsemine (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-3 · Taseme määramine

|  Tase | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 |  Juhtimine puudub | Apakkujal on tegelik juurdepääs ja võtmekontroll | Puudub |
| 1 | EU salvestusruum | EU salvestusruum kokku lepitud; juurdepääsu või võtme juhtimine on jagatud või ebaselge | 1 |
| 2 | Tehniliselt tugevdatud | Kliendipõhine võtmehaldus ja juurdepääsupiirangud; teenusepakkuja pääseb endiselt juurde võtmetele või loetavatele andmetele | 2 |
| 3 | ASVarjestatud juhtimine | Ainult klient haldab võtmeid; pakkuja ei näe loetavaid andmeid; töötlemine jääb EL-i | 3 |
| 4 | Täielik juhtimine |  Täielik kontroll andmete, võtmete, AI mudelite ja töötlemise üle | 4 |

---
<!-- _class: table table-editable -->

# SOV-3 · Peatükikehtestamine

| Põhjendus keskmise tulemuse jaoks | Tähtaotus |
| --- | --- |
| Faktualine olukord ja sobiv tunnusgraaf skaalast | … |
| Madalaim tõend kriitiliste küsimuste kohta, koos lähtekoodiga ID-dega | … |
| Määrelemine reeglite 0 ja 5 rakendamine ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# SOV-4 · Operatiivne suveräänsus

---
<!-- _class: table -->

# SOV-4 · Vastavõtted

| Vraag · tüüp/min. | Vastavõtte küsimus | Vajalik tõendus |
| --- | --- | --- |
| 4.1 · K·2+ | Kas migratsioon on dokumenteeritud ja testitud ning on andmed ja konfiguratsioonid täielikult eksporditavad? | Migratsiooniprotseduur, eksporditest, Data Act klausulid |
| 4.2 · K·2+ | Voi juhtimiskirjandus ja igapäevane haldus toimuda täielikult EL-i töötajate poolt? | Personalijuhtumi ülevaade, toetuse asukoht, SLA |
| 4.3 · O·2+ | Kas operatsiooniteadmine on üle kantud ja mitte ainult tarnija poolt? | Kujundusplaan, teadmiste kinnitus, dokumentatsioon |
| 4.4 · O·2+ | On juhatuse täielik tehniline dokumentatsioon ja käsuread? | Dokumentatsioonide inventuur, käsuread |
| 4.5 · O·1+ | On kriitilised allhõljatavad teada ja realistiliselt asendatavad? | Allhõljatute loend, alternatiivianalüüs |
| 4.6 · O·2+ | On olemas väljapääsist strateegia realistliku ülekasutamisajaga ja kuluga? | Väljapääsist strateegia, migratsioonibüronäide |
---
<!-- _class: table table-editable -->

# SOV-4 · Järeldused ja tõendid

| Vraag · tüüp/min. | Faktualine järeldus | Allikas ID | Tõendus 0-4 | Mõju / risk |
| --- | --- | --- | --- | --- |
| 4.1 · Testitud migratsioon ja ekspordi (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Haldus toimub täielikult EL-i töötajate poolt (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Üle kantav operatsiooniteadmine (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Dokumentatsioon ja käsuread (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Asendatavad allhõljatavad (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Realistne väljapääs (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-4 · Taseme määramine

|  Tase | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 | Asõltuv | Operatsioon sõltub täielikult EL-i välisest tarnijast või personalist | Puudub |
| 1 | Muljetavaldav | EU toimimine paberil; kriitilisi tegevusi väljaspool ELi saab mõjutada | 1 |
| 2 | Kasutatav sõltuvustega | EU kasutamine võimalik; olulised sõltuvused või lukustus jäävad alles | 2 |
| 3 | Mõtekas juhtimine | EU osalejad kontrollivad operatsiooni; juurdepääs toele on ELiga seotud, logitud ja lubatud; väljapääs on realistlik | 3 |
| 4 | In juhtimine |  Täielik EL-i toimimine ilma kriitiliste ELi-väliste sõltuvusteta | 4 |

---
<!-- _class: table table-editable -->

# SOV-4 · Peamine järeldus

| Põhjustamine peamise hinnakaarti jaoks | Täitmine |
| --- | --- |
| Faktualine olukord ja vastav tunnus skaalast | … |
| Madalaim tõendus kriitsete küsimuste jaoks, koos allikas ID-dega | … |
| Rakendatud reeglid ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# SOV-5 · Keti suveräänsus

---
<!-- _class: table -->

# SOV-5 · Vastavõtted

| Vraag · tüüp/min. | Vastavõtte küsimus | Vajalik tõendus |
| --- | --- | --- |
| 5.1 · K·2+ | On saadaval ajakohane SBOM tarkvarale teenuses? | SBOM, tarnija avaldus |
| 5.2 · O·1+ | On teada tarkvara ja firmware pärinevate asjade ning mitte-EL-i sõltumatus? | Tarkvara inventuur, firmware ülevaade, avaldus |
| 5.3 · K·2+ | Välja töötatud uuendused enne laialdast kasutust, kinnitatud ja tagurdamisel? | Uuenduse poliitika, konfiguratsioon, testiprotseduur |
| 5.4 · O·1+ | On teada kohad ja jurisdiktsioon build- ja signatuur infrastruktuurile? | Tekniselt dokumenteeritud, arhitektuurskeem |
| 5.5 · K·2+ | On teada kõik allhõljatavad ja on muutmise avaldus lepinguga? | Allhõljatute loend, lepinguklausulid |
| 5.6 · O·2+ | On lepinguga kinnitatud allhõljatavate auditõigused? | Lepinguklausulid, auditiprotseduurid |
---
<!-- _class: table table-editable -->

# SOV-5 · Mõisted ja tõendid

| Küsimus · tüüp/min. | Tegus mõiste | Allikas-ID | Tõend 0-4 | Kohtumine / risk |
| --- | --- | --- | --- | --- |
| 5.1 · Praegune SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Värsti tarkvara ja firmware päritol (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Pätime kinnitamine ja tagastus (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Build- ja allkirjuskirjuse õiguste järgimine (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Allhankijad ja muudatusavaldus (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Allhankijate auditiõigused (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-5 · Taseme määramine

| Level | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 | Mõjuta |  Kriitiline ahel, mis on täielikult väljaspool ELi mõju | Puudub |
| 1 | läbipaistmatu | EU seadus kehtib formaalselt, kuid kett on läbipaistmatu | 1 |
| 2 | Insight koos sõltuvustega | Chain läbinägelik; säilivad olulised sõltuvused väljaspool ELi | 2 |
| 3 | Mõtestatud mõju | Kriitilised lingid on mitmekesised; uuendused on kontrollitavad; ehitus- ja allkirjastamisahel on teada | 3 |
| 4 | Läbipaistev ja kontrollitav | Täielik läbipaistvus ilma kriitiliste ELi-väliste sõltuvusteta | 4 |

---
<!-- _class: table table-editable -->

# SOV-5 · Peamine järemnäide

| Põhjus, miks peame järemnäite | Tähtaeg |
| --- | --- |
| Tegus olukord ja vastav tunnus skaalalt | … |
| Madalaim tõend kriitiliste küsimuste kohta, koos allikas-ID-dega | … |
| Reegli 5 rakendamine ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leid-ID | … |
---

<!-- _class: section -->

# SOV-6 · Tehnoloogiline suveräänsus

---
<!-- _class: table -->

# SOV-6 · Peamised küsimused

| Küsimus · tüüp/min. | Peamine küsimus | Nõutav tõend |
| --- | --- | --- |
| 6.1 · K·2+ | On kõik API-d põhjalised ja avalikud dokumentatsiooniga standardid? | API-dokumentatsioon, standardiregister |
| 6.2 · K·2+ | Kas kõik andmed saab ilma kaotusteta avatud formaati ekspordiks? | Eksporditest, tehnilised dokumentatsioon |
| 6.3 · O·2+ | Millised tarkvaralitsed ja piirangud kehtivad kohandamise või taaskasutamise jaoks? | Litsentsitekst, juridiline analüüs |
| 6.4 · O·2+ | On kasuks hankitud lähtekoodi auditõigus või escrow? | Escrow-leping, auditraport |
| 6.5 · O·1+ | On kogu süsteem dokumenteeritud, sealhulja suvise komponendid ja alternatiivid? | Arhitektuur, komponendiregister |
| 6.6 · O·2+ | Kas alternatiivide migratsioon on realistne ja testitud? | Migratsioonitest, väljapääsistrateegia, alternatiivianalüüs |
---
<!-- _class: table table-editable -->

# SOV-6 · Mõisted ja tõendid

| Küsimus · tüüp/min. | Tegus mõiste | Allikas-ID | Tõend 0-4 | Kohtumine / risk |
| --- | --- | --- | --- | --- |
| 6.1 · Avatud ja dokumenteeritud API-d (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Kaotamata avatud andmete ekspordi (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Litsentsid ja taaskasutus (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Lähtekoodi audit või escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Dokumenteeritud süsteem (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Testitud alternatiivide migratsioon (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-6 · Taseme määramine

| Level | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 | Suletud | Suletud ökosüsteem; ränne on praktiliselt võimatu | Puudub |
| 1 | Lukusta | Mõninga ühendatavus; lock-in jääb domineerivaks | 1 |
| 2 | Rändatav |  Koostalitlusvõime ja eksport on korraldatud; auditi ja tingdeponeerimise võimalused on olemas | 2 |
| 3 | Mõteliselt autonoomne | Asendatavust testitakse ja kriitilist tarkvara saab kontrollida auditi või avatud lähtekoodiga | 3 |
| 4 | In juhtimine | Täielik kontroll integratsiooni ja standardite üle ilma kriitiliste suletud sõltuvusteta | 4 |

---
<!-- _class: table table-editable -->

# SOV-6 · Peatükikehtestamine

| Põhjus peatsuse saamiseks | Rakendamine |
| --- | --- |
| Tegus olukord ja sobiv tunnus skaalast | … |
| Madalaim tõend kriitiliste küsimuste kohta, koos lähtekoodiga | … |
| Määrele 5 rakendamine ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# SOV-7 · Turvalisuse ja vastavuse suveräänsus

---
<!-- _class: table -->

# SOV-7 · Kontrollküsimused

| Küsimus · tüüp/min. | Kontrollküsimus | Vajalik tõend |
| --- | --- | --- |
| 7.1 · K·3+ | On pakett sertifititud vastavalt tunnetatud standardile ja on audit aldis EU-kontrollile? | Sertifikaat, auditraport, ulatus |
| 7.2 · K·2+ | On pakett asukohtel EU-s ja opereerib EU-jurisdiktsiooni alusel? | Paketi asukoht, leping, SLA |
| 7.3 · O·3+ | On kinnitatud NIS2, DORA, AVG ja CRA vastavus ja on seda väline kinnitus? | Vastavusraport, kontrollrühm, audit |
| 7.4 · K·2+ | Kes teostab haigekogumuse ja täienduse ning saab seda iseseisvalt EU-s? | Täienduse poliitika, SLA, tehniline dokumentatsioon |
| 7.5 · K·2+ | On auditõigused praktiliselt rakendatavad, sealhulja süsteemi- ja logi juurdepääsu korral? | Kontraktuaalne auditõigus, tehtud auditraport |
| 7.6 · O·2+ | On teadaolev teadaandmise protseduur andovkaopingu ja juhtumite jaoks AVG-vastavus ja on seda nähtavasti paigas? | Juhulplaan, andurlepingu leping, teadaanderegistrering |
---
<!-- _class: table table-editable -->

# SOV-7 · Leidmised ja tõendid

| Küsimus · tüüp/min. | Tegus leidmine | Lähtekoodiga | Tõend 0-4 | Mõju / risk |
| --- | --- | --- | --- | --- |
| 7.1 · Sertifikaat EU-kontrolli all (K·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · Pakett EU-s EU-õiguslikul alusel (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Väline kinnitatud vastavus (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU-haigekogumuse juhtimine (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Praktiliselt rakendatavad auditõigused (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · AVG-vastav teadaandmise protseduur (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-7 · Taseme määramine

| Level | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 | A sõltuv | Turvatoimingud on täielikult väljaspool ELi kontrolli all | Puudub |
| 1 | Muljetaval ühilduvusega | Formaalne vastavus; rakendamine väljaspool ELi jääb mõjutatavaks | 1 |
| 2 | Lepinguline garantii | EU jurisdiktsioon, auditi- ja aruandluskohustused on lepinguga reguleeritud | 2 |
| 3 | EU operatsioonid | EU turvatoimingud on tõhusad ja sõltumatud auditid on võimalikud | 3 |
| 4 | In juhtimine | Täielik kontroll seire, intsidentidele reageerimise, paikamise ja vastavuse üle | 4 |

---
<!-- _class: table table-editable -->

# SOV-7 · Peatükikehtestamine

| Põhjus peatsuse saamiseks | Rakendamine |
| --- | --- |
| Tegus olukord ja sobiv tunnus skaalast | … |
| Madalaim tõend kriitiliste küsimuste kohta, koos lähtekoodiga | … |
| Rakendatud reeglid ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# SOV-8 · Jätkusuutlikkuse suveräänsus

---
<!-- _class: table -->

# SOV-8 · Vastavõtted

| Küsimus · tüüp/min. | Vastavõtte küsimus | Vajalik tõendus |
| --- | --- | --- |
| 8.1 · K·2+ | Mis on mõõdetud PUE andmesaatkohtade kohta? | Andmesaatkohtade aruanded, isiklik mõõtmine |
| 8.2 · O·2+ | On energia mõjutavalt taastuv ja on sertifikaadid sõltumatult kontrollitud? | Energia sertifikaadid, isiklik aruandlus |
| 8.3 · O·2+ | On CO2-emissioon ja vee tarbimine läbipaelune ja väljastpoolt kontrollitud? | ESG-aruanded, audituuri avaldus, GRI |
| 8.4 · O·1+ | On seadme elutsükli ja e-jäätmeseeskiri dokumenteeritud ja kontrollitav? | Eeskiri, ISO 14001 sertifikaat |
| 8.5 · O·1+ | On hinnatud sõltuvust kriitilistest toodetest? | Riskianalüüs, tarnija avaldus |
| 8.6 · O·1+ | Vastutab pakkuja CSRD-s ja on aruanded avalikud; kui mitte, siis annab ta vabatahtliku aruande? | Aastaaruanded, CSRD või vabatahtliku aruandluse aruanded |
---
<!-- _class: table table-editable -->

# SOV-8 · Järeldused ja tõendid

| Küsimus · tüüp/min. | Faktualine järeldus | Allikas ID | Tõendus 0-4 | Mõju / risk |
| --- | --- | --- | --- | --- |
| 8.1 · Mõõdetud PUE andmesaatkohtades (K·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Mõjutav taastuv energia (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · CO2 ja vesi väljastpoolt kontrollitud (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Elutsükli ja e-jäätmeseeskiri (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Kriitilised tooted hinnatud (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD või vabatahtliku aruandluse aruanded (O·1+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-8 · Taseme määramine

| Level | Silt | Atribuut | Min. tõend |
| --- | --- | --- | --- |
| 0 | läbipaistmatu | Ei läbipaistvust; domineeriv ELi-väline sõltuvus energiast või materjalidest | Puudub |
| 1 | Põhiaruandlus | Põhiaruandlus on saadaval; säilivad suured struktuursed sõltuvused | 1 |
| 2 | Läbipaistev sõltuvustega | Läbipaistvus ja lepingunõuded on saadaval; materiaalsed sõltuvused jäävad | 2 |
| 3 | Mõju |  Märkimisväärne ELi mõju energiaallikale ja ringahelale | 3 |
| 4 | Jätkusuutlik | Q Täielikult jätkusuutlik, läbipaistev ja ELile ankurdatud koos struktuuriseirega | 4 |

---
<!-- _class: table table-editable -->

# SOV-8 · Peamine järeldus

| Põhjus, miks peetakse peamiseks | Rakendamine |
| --- | --- |
| Faktualine olukord ja sobiv tunnus skaalalt | … |
| Madalaim tõendus kriitsete küsimuste kohta, koos allikas ID-dega | … |
| Rakendatud reeglid ja võimalik piiramine | … |
| Olulisim põhjus, risk ja leidmise ID | … |
---

<!-- _class: section -->

# Järeldus ja kinnitus arvamus

---

<!-- _class: table table-editable -->

#  Legitiimsus andmetüübi kohta · Rida 0

| Andmetüüp | Testi raamistik | Põhjendus ja allika ID | Tulemus | Mõjutatud SOV sihtmärk |
| --- | --- | --- | --- | --- |
| Isikuandmed | AVG, sealhulgas üleandmine ja asjakohased meetmed | … | Põhjendatud / risk | … |
| Mitteisiklik ettevõtteteave | Andmeseaduse artikkel 32 | … |  Põhjendatud / risk | … |
| Valitsuse või salastatud teave | Kohaldatavad riiklikud ja ELi eeskirjad | … |  Põhjendatud / risk | … |
| Reguleeritud sektori andmed | NIS2, DORA või sektoripõhised reeglid | … |  Põhjendatud / risk | … |

---

<!-- _class: table table-editable -->

# Kohtumine juriidilistele korraldustele · Reegel 4

| Partei ja õiguskord | Kas valitsus saab jõuda? | Sõltumatu kohtuprotsess? | Kas klienti võib teavitada? | Tagajärg tõestuse ja taseme saavutamiseks |
| --- | --- | --- | --- | --- |
| … | Yes / ei / pole kindel | Yes / ei / pole kindel | Yes / ei / pole kindel | … |
| … | … | … | … | … |
| … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Reegel 4 · Oblikatoorne järeldus

| Nõue või tagajärged | Järeldus ja allikas ID |
| --- | --- |
| Valitsusel võib olla sundida juurdejuurde või koostööd | Jah / ei / ebaselge: … |
| Isiklik õigusruum puudub või teavitamine tarbijale on keelatud | Jah / ei / ebaselge: … |
| Kui kumbagi kehtivad: küsimused 2.3, 2.5 ja 2.6 on tõendusastme 0 | Rakendatud / ei rakendatud: … |
| Kui kumbagi kehtivad: SOV-2 on maksimaalselt tasemele 1 | Rakendatud / ei rakendatud: … |
| Kas kontrollitu on selles õigusruumis, siis on ka SOV-1 maksimaalselt tasemele 1 | Rakendatud / ei rakendatud: … |
| Jäädav kontrollitu | … |
---
<!-- _class: table table-editable -->

# Tehniline marsruut · Punkt 5

| Kriteerium | Juhm ja lähtekood ID |
| --- | --- |
| SOV-3 on vähemalt taseme 3: võtmed on ainult kliendi poolt; pakkuja ei näe loetavat andmeid | … |
| Ei ole administraator- või tugitoiminguid loetavate andmete juurde pääsemiseks | … |
| SOV-5 on vähemalt taseme 3: uuendused on eelkontrollitud ja tagasilükkimine võimalik; build- ja allkirjuskett on teada | … |
| SOV-6 on vähemalt taseme 3: kriitilise tarkvara toimimine on kontrollitav | … |
| Teenus ei pea andmeid loetaval kujul töötlema | Jah / Ei |
| Kõik kriteeriumid täidetud | Üksnes "jah", kui kõik eeltoodud juhmid on positiivsed: … |
| Tagajärjed | Saab toetada Punkt 0; ei muuda SOV-2 ega SEAL-i üldist tasemele |
---
<!-- _class: table table-editable -->

# SAFARI-score kaart

| Kood | Kaal | Mõõduvõtmine 0-4 | Põhjalikuks tõendiks mõõduvõtmine 0-4 | Oskuslikkus valitud normi kohta | Eesmärkide tõendamine |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | 15% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-2 | 10% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-3 | 10% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-4 | 15% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-5 | 20% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-6 | 15% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-7 | 10% | … | … | Vastab / puudub / ei ole saadaval | … |
| SOV-8 | 5% | … | … | Vastab / puudub / ei ole saadaval | … |
---
<!-- _class: table table-editable -->

# Kokkuvõte

| Komponent | Juhimeet ja põhjendus |
| --- | --- |
| SEAL-i üldine tasemele · madalaim kriitiline eesmärk | … |
| Kaalutud ECSF-score · Σ (mõõduvõtmine tasemele / 4 × kaal) | …% |
| Suurimad puudumised | … |
| Kriitilised sõltumatused | … |
| Soovitav tasemele allpool soovitamine | … |
| Seaduslikkusriski | … |
| Selles osas lahendatav | … |
| Tarvitaja koostöö nõutav | … |
---

<!-- _class: table table-editable -->

# Indikatiivne CADA positsioon

| Part | Tulemus ja allika ID |
| --- | --- |
| Asjakohasus | Avalik sektor / kriitiline tegevus / NIS2 sektor / n.a. |
| Target CADA tase | 1 / 2 / 3 / 4 / n.a. |
| Siitlik saavutatav tase | 1 / 2 / 3 / 4 / mitte ühtegi |
| Nõuded pole täidetud | … |
| Tõendite piirang | … |
| Kohustuslik sõnastus | Ettepanekul põhinev märge; ei mingit hinnangut vastavuse kohta. |

---

<!-- _class: table table-editable -->

# Tagamise hindamine eesmärgi kohta

| Target | Tõesta kriitilisi küsimusi | Legalitaarne risk |  Kohtuotsuse tüüp | Formulatsioon ja hoiatused |
| --- | --- | --- | --- | --- |
| SOV-… | Väikseim tase: … | Yes / ei | Puudub / piiratud / mõistlik | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |

---
<!-- _class: table -->

# Assurance kinnitusõppe abifunktsioon

| Tüüp | Kriteerium | Standard kinnitus |
| --- | --- | --- |
| Ei arvesta | Kriitiline küsimus on tõendustasemel 0 või 1 | Saadaval oleva tõendite põhjal ei ole võimalik teha hinnangut [eesmärk] kohta [teenus]. |
| Piiratud kindlus | Kõik kriitilised küsimused vähemalt 2; mitte kõik vähemalt 3 | Saadaval oleva tõendite põhjal meil ei ole mitte midagi, mis näitaks, et [väide] oleks vales. Me anname piiratud kindlusega. |
| Ühine kindlus | Kõik kriitilised küsimused vähemalt 3 | Saadaval oleva tõendite põhjal me leiame, et [väide]. Me anname ühise kindlusega. |
---

<!-- _class: table table-editable -->

# Leiud ja soovitused

| ID | SOV | Leidmine | Mõju | Asoovitus | Omanik | Term |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | … | … | Kõrge / keskmine / madal | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |

---

<!-- _class: table table-editable -->

# Kvaliteedikontroll ja sündmused pärast võrdluskuupäeva

| Control | Tulemus ja ülevaataja viide |
| --- | --- |
|  Ulatus ja väide kehtestati enne täitmist | … |
| Kõik kriitilised küsimused on kaetud või teatatud piirangutena | … |
| Allikate viited on jälgitavad ja tõendite tasemed on jälgitavad | … |
| Skoorimise reeglid 0–5 on tõendatavalt rakendatud | … |
| Aritmeetika ja teksti järjepidevus on kontrollitud | … |
| Sõltumatu ülevaade on lõpule viidud | … |
|  Võrdluskuupäevajärgseid sündmusi on hinnatud | … |
| Töödeldi silmapaistvaid eriarvamusi | … |

---
<!-- _class: table table-editable -->

# Väärtuse kinnitus organisatsioonile

| Väärtuse kinnitus | Rakendamine |
| --- | --- |
| Vastutava osapoole nimi ja ametitase | … |
| Kirjalik kinnitus | Väärtus, ulatus ja valitud normid on täies ulatuses ja ausalt kinnitatud. |
| Kuupäev | … |
| Sobivuse kinnitus | Jah / Ei |
---
<!-- _class: table table-editable -->

# Isikliku kvaliteedi kontroll |

| Kontroll | Rakendamine |
| --- | --- |
| Kontrollija nimi ja ametitase | … |
| Isikupärane | Jah / Ei |
| Kontrolli järeldus ja mahunäitajad | … |
| Kuupäev | … |
| Volitlus allkirjastamiseks | Jah / Ei |
---
<!-- _class: sign-off -->

# Väärtuse kinnituse allkirjastus
---
# Allikad ja litsents

- Meetod: SAFARI v0.9 (konstant), Brenno de Winter ja Stichting LibreKAT.
- Staatus: vabavaraline meetod. Minimaalnormid on nõuanded; eeskirjad 0 kuni 5 on kohustuslikud, kes SAFARI rakendavad.
- Põhiootmine: Euroopa Pilve Suvereniteedi Rahukogu, täiendatud ISO 27001:2022 ja ISAE 3000-assureerimisstruktuuriga.
- Kogu meetod: https://pawprint.vigilis.online/LibreKAT/Safari
- See mallisisu on SAFARI muudatus ja kuulub CC BY-SA 4.0 alla: https://creativecommons.org/licenses/by-sa/4.0/
- Täida alati uusim versioon, peilaaeg, professionaalsete standardite ja kohalike õigusnormide andmed.
