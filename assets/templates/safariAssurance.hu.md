---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: A digitális szuverenitás SAFARI-értékelése
language: hu
standards: SAFARI@0.9, ECSF
---
<!-- _class: title -->

# A digitális szuverenitás SAFARI-értékelése
---
# Hogyan kell használni ezt a munkakörnyezetet

- Először határozzák meg a hatamot, a megállapítást, a kívánt szintet és a célzott bizonyíték szintet.
- Töltsék ki minden kérdésre a megállapítást, egy visszavehető forrásra hivatkozást és a bizonyítékszintet.
- Kezeljék az hiányos vagy elutasított bizonyítékot egy megállapítást 0 bizonyítékszinttel.
- Alkalmazzák a hatvan értékelési szabályt, mielőtt megállapítják a szintet minden szuverenitási cél érdekében.
- Formálják meg az asszurance ítéletet csak azután, hogy a minőségellenőrzés és az dátum után bekövetkező események értékeltek.
---
<!-- _class: table table-editable -->

# Dokumentumkezelés és feladatválla

| Terv | Megfelelő |
| --- | --- |
| Szervezet | … |
| Szolgáltatás vagy rendszer | … |
| Szállítónő | … |
| Megrendelő | … |
| A megállapításért felelős személy | … |
| Főbíró vagy tanácsadó | … |
| Független értékelő | … |
| Döntési időpont és értékelési időszak | … |
| Jeljelentés verzió és dátum | … |
| TLP-szabályozás és terítéksor | … |
---
# Objektum és hatókör

| Hatókör rész | Megfejtés |
| --- | --- |
| Vizsgált alkalmazások, platformok és infrastruktúra | … |
| Közvetlen beszállítók | … |
| Személyre szabott beszállítók és láncreakciók | … |
| Adattípusok | Személyi adatok / üzleti adatok / kormányzati adatok / kódolt információk |
| Jogszabályok az érintettek szerint | … |
| Kezelési, támogatási, építési és aláírási helyek | … |
| Explicit kizárások indoklással | … |
| Normatív keret verziója | SAFARI v0.9 (koncepció; önkéntes módszertan) |
---
# Az organizmus állítása

| Alszám | Megfejtés |
| --- | --- |
| Objektum | [Organizace] felvette a [szolgáltatás] szuverenitás helyzetét, amelyet [szállító] biztosított. |
| Időszak | A felülvizsgálat a [dátum] állapotára vonatkozik a megállapított hatókörön belül. |
| Keret | A felülvizsgálat a SAFARI v0.9, egy önkéntes koncepciós módszertan szerint történik, amely kapcsolódik az ISO 27001:2022 szabványhoz és az ECSF nyolca céljához. |
| Eredmény | Az organizmus állítása, hogy [SOV-kód vagy minden cél] megfelel a választott szintnek [0-4]. |
| Megjegyzés | Az eredmény a mérőszám alapján rendelkezésre álló bizonyítékok alapján készült; a változások befolyásolhatják az eredményt. |
| Tulajdonos és hivatalos jóválasztás | … |
---
# Kívánt szintek és kulcsfontosságú célok

| Kód | Cél | Kulcsfontosságú cél | Javasolt minimum | Kívánt | Eltérés indoklása |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Stratégiai | Igen | 2 | … | … |
| SOV-2 | Jogszabályi és jogi | Igen | 2 | … | … |
| SOV-3 | Adatok és AI | Igen | 3 (2 csak alacsony érzékenységű és nem személyi adatokkal) | … | … |
| SOV-4 | Üzemeltetés | Igen | 3 (2 csak alacsony érzékenységű, helyettesíthető és nem személyi adatokkal) | … | … |
| SOV-5 | Lánc | Igen | 3 (2 csak alacsony érzékenységű és nem személyi adatokkal) | … | … |
| SOV-6 | Technológia | Igen | 3 (2 csak alacsony érzékenységű és nem személyi adatokkal) | … | … |
| SOV-7 | Biztonság és megfelelés | Igen | 2 | … | … |
| SOV-8 | Fenntarthatóság | Igen | 1 | … | … |
---
# Bizalom-biztosítási megközelítés

| Alszám | Választás és indoklás |
| --- | --- |
| Feladat típusa | Tanácsadás / korlátozott bizalom / reális bizalom |
| Célok a bizalom-biztosítási állításban | … |
| Anyagosság és kockázati alapú válogatás | … |
| Munkafolyamatok bizonyítéktípusonként | Vizsgálat / megfigyelés / újbóli végrehajtás / megerősítés / elemzés |
| Mintavételi megközelítés és populációk | … |
| Bevonultat szakértők | Jogszabályi / technikai / fenntarthatóság / egyéb: … |
| Függetlenség és érdekellentétek | … |
|Hozzáférés vagy munkavégzés korlátozása | … |
---
<!-- _class: table table-editable -->

# Feladatelfogadás formális bizonyítékbiztosítás

| Elfogadási kritérium | Értékelés és forrás | Eredmény |
| --- | --- | --- |
| A Safari megfelelő kritériumként szolgál a megállapítás és a célzött felhasználók számára | … | Igen / nem |
| A felelős fél elismeri a felelősségét a megállapításért | … | Igen / nem |
| A racionális cél, a célzött felhasználók és a terjesztési kör meghatározott | … | Igen / nem |
| Biztosított függetlenség, etika, szakértelem és szükséges szakértők | … | Igen / nem |
| Elfogadott a feladatfeltételek és a kívánt bizonyítékbiztonsági szint | … | Igen / nem |
| Elvárható, hogy elegendő mennyiségű alkalmas bizonyíték áll rendelkezésre | … | Igen / nem |
| Elfogadási döntés | Csak akkor folytatódik, ha minden kritérium "igen" | Elfogadás / elutasítás |
---
<!-- _class: table -->

# Bizonyítékrendszerek szintjei

| Szint | Neves | Alkalmazás |
| --- | --- | --- |
| 0 | Nincs bizonyíték | Nincs indoklás, hiányos bizonyíték vagy elutasított |
| 1 | Magyarázat | Személyes vagy írásbeli magyarázat további indoklás nélkül |
| 2 | Dokumentáció | Szerződés, politika, eljárás vagy jelentés független ellenőrzés nélkül |
| 3 | Technikai bizonyíték | Konfiguráció, napló, teszt vagy külső jogi tanácsadás, amelyet a vevő szerez |
| 4 | Független bizonyíték | Független ellenőrző fél által gyűjtve vagy ellenőrzve |
---
<!-- _class: table table-editable -->

# Központi bizonyítékjegyzék

| Forrás-azonosító | Dokumentum vagy regisztráció | Tulajdonos | Dátum és verzió | Forrás | Integritás és tárolási hely |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Belső / beszállító / külső | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |
---
<!-- _class: table -->

# Kötelező pontozási szabályok

| Szabály | Eredmény a megítélésben |
| --- | --- |
| 0 · Jogosság | A jogosság kockázata mindig egyenlő űrt eredményez; javasoljon jogi vizsgálatot. |
| 1 · Kritikus kérdések | A 0 szintű bizonyíték egy kritikus kérdésen belül legfeljebb 1 szintet korlátozza a célpontban. |
| 2 · A bizonyíték tartja a szintet | A kérdés minimum alatt lévő bizonyíték 0-ként számít. A célpont bizonyítéka a legkisebb bizonyíték a kritikus kérdésekben; a 2., 3. és 4. szint elvárja legalább ugyanazt a bizonyíték szintet. |
| 3 · A gyengébb link | A SEAL teljes szintje a legkisebb meghatározott szint a kulcs célpontokban. |
| 4 · Működő jogrend | Ha a kötelező erővel rendelkező kényszer és nincs független jogi eljárás vagy jelzési lehetőség, a 2.3, 2.5 és 2.6 számok 0-ként számítanak; a SOV-2 legfeljebb 1, és a SOV-1 is, ha a befolyás a helyén van. |
| 5 · Technikai útvonal | Ha a kötelező külföldi hozzáférés védett, akkor csak a teljes technikai útvonal számít 2.3, 2.5 és 2.6 számok 0-ként; a SOV-2 legfeljebb 1, és a SOV-1 is, ha a befolyás a helyén van. |
---
<!-- _class: section -->

# SOV-1 · Stratégiai szuverenitás
---
<!-- _class: table -->

# SOV-1 · Ellenőrzési kérdések

| Kérdés · típus/min. | Ellenőrzési kérdés | Szükséges bizonyíték |
| --- | --- | --- |
| 1.1 · K·2+ | Kik az elvont tulajdonosok és milyen jogrendszer szerint regisztrálják őket? | UBO-regiszter, éves mérleg, tulajdonosregiszter |
| 1.2 · K·2+ | Lehet egy EU-n kívüli anyavállalat stratégiai újdonságokat követelni? | Csoportstruktúra-diagram, alapító okirat, igazgatói rendelet |
| 1.3 · K·2+ | Tartalmazza-e a megállapodás a változásvezérlési rendelkezéseket? | Szerzőleti szöveg |
| 1.4 · O·1+ | Van-e technológia és IP a EU entitáson vagy egy külföldi anyavállalaton? | IP regisztráció, licencszerződések |
| 1.5 · O·2+ | Az beszállítófüggőség explicitan megválaszolva és rögzítve-e a felügyelőtanács szintjén? | Felügyelőtanács jegyzetei, kockázati jegyzék |
| 1.6 · O·2+ | Van-e kilépési vagy folytonossági forgatókönyv egy tulajdonosi változás esetén? | Folyamatos tervezés, kilépési stratégia |
---
<!-- _class: table table-editable -->

# SOV-1 · Találdozatok és bizonyítékok

| Kérdés · típus/min. | Valós találdozatok | Forrás-azonosító | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 1.1 · UBO-k és jogrendszer (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Anyavállalat EU-n kívül követel stratégiai újdonság (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Változásvezérlés (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Technológia és IP helye (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Függőség a felügyelőtanács szintjén (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Kilépés a tulajdonosi változás esetén (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-1 · Szint meghatározása

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Nincs betekintés | Nincs látás az tulajdon és hatalmi struktúrára | Nincs |
| 1 | Bekezdés | Bekezdés jelen van, de nincs biztosítása a tulajdonosi változás esetén | 1 |
| 2 | Szerzői biztosítás | A változásvezérlés és a transzparencia szerződés szerint rögzítve | 2 |
| 3 | Végrehajtás | A EU-governance elválasztva és végrehajtható; a külföldi befolyás erősen korlátozott | 3 |
| 4 | Stratégiai autonómia | Fenntarthatóan európai bevonat; a függőség explicitan súlyozva van egy felügyelőtanácsi döntésben | 4 |
---
<!-- _class: table table-editable -->

# Fő Célkitűzés · SOV-1

| Közvetlen indíték a központi értékelési táblázat számára | Megvalósítás |
| --- | --- |
| A valós helyzet és a skálán található megfelelő jellemző | … |
| A kritikus kérdésekben talált legalapvetőbb bizonyíték, forrás-azonosítókkal | … |
| Alkalmazott szabályok és esetleges korlátozások | … |
| A legfontosabb ok, kockázat és megállapodás-azonosító | … |
---
<!-- _class: section -->

# SOV-2 · Jogosági és joghatósági szuverenitás
---
<!-- _class: table -->

# SOV-2 · Kritikus Ellenőrző Kérdések

| Kérdés · Típus/Min. | Ellenőrző Kérdés | Szükséges Bizonyíték |
| --- | --- | --- |
| 2.1 · K·2+ | Mely jog hatályos a szerződésben és mely bíróság illetékese? | Szerzőleti szöveg jogi és fóliaszabályokkal |
| 2.2 · K·3+ | Kényszerítheti-e az EU-n kívüli kormány jogi értelemben a hozzáférést vagy együttműködést, és létezik független jogi védelem? | Jogtanácsadás, csoportszervezet és elemzés minden jogrendszerben |
| 2.3 · K·2+ | Van-e adatigényre vonatkozó kötelezettség az állami kérés esetén? | Szerzői rendelkezés, átláthatósági jelentés |
| 2.6 · K·2+ | Vannak-e szerződésben rögzített eljárások külföldi jogi kérések vitatása érdekében? | Szerzői rendelkezés, beszélgető szabályzat |
| 2.7 · K·2+ | Alapozott-e a személyes adatok jogszerűsége minden releváns jogrendszerben? | DPIA, átadási teszt, Data Act intézkedések, besorolási- és szektorális szabályozások |
---
<!-- _class: table -->

# SOV-2 · Támogató Ellenőrző Kérdések

| Kérdés · Típus/Min. | Ellenőrző Kérdés | Szükséges Bizonyíték |
| --- | --- | --- |
| 2.4 · O·2+ | Van-e forráskód zárolás (escrow) és milyen feltételek mellett érhető el? | Escrow megállapodás, notáriális nyilatkozat |
| 2.5 · O·2+ | Lehet-e hatékonyan a szerződéses jogokat egy EU-bírósághoz bevonni? | Jogtanácsadás, szerződés elemzése |
---
<!-- _class: table table-editable -->

# SOV-2 · Megjegyzések és bizonyítékok

| Kérdés · Típus/Min. | Valódi megjegyzés | Forrás-ID | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 2.1 · Jogszabályszerű és bejáratott bíróság (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Külföldi erőfeszítés és jogi védelem (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Tájékozatal kötelezettség kormányzati kérés (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Forráskód-készlet (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Érvényesíthető EU-bírósághoz (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Külföldi kérés vitatása (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Jogtisztesség a adatfajtától függően (K·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-2 · Szintértékelés

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Nincs betekintés | A jogi szabályozás és a jogkör tisztázatlan | Nincs |
| 1 | Tényérzékelés | Jogorvosolt elemzés nem szerzői biztosítménnyel | 1 |
| 2 | Szerzői rögzítés | Jogszabályi választás, fórumválasztás és tájékoztatási kötelezettségek rögzítve; maradó kitettség elemzés | 2 |
| 3 | Prakiszabályozás | Vitás eljárások és készletkészlet beállított és bizonyíthatóan végrehajtható | 3 |
| 4 | Hatékony érvényesítés | Jogok hatékonyan érvényesíthetők és határoson kívüli kockázatok rendszeresen tesztelve | 4 |
---
<!-- _class: table table-editable -->

# SOV-2 · Célmegállapítás

| Alap a központi mérőszámhoz | Megvalósítás |
| --- | --- |
| Valódi helyzet és megfelelő jellemző a szintskála szintjeiből | … |
| Legalacsonyabb bizonyíték kritikus kérdéseknél, forrás-ID-kkel | … |
| Szabályok 0 és 4 alkalmazása és esetleges korlátozás | … |
| Legfontosabb ok, kockázat és megjegyzés-ID | … |
---
<!-- _class: section -->

# SOV-3 · Adat- és AI-szélsőségszabályozás
---
<!-- _class: table -->

# SOV-3 · Tesztekérdések

| Kérdés · típus/min. | Tesztekérdés | Szükséges bizonyíték |
| --- | --- | --- |
| 3.1 · K·3+ | Ki irányítja az titkosítási kulcsokat: a felvevő, a kínáló vagy egy harmadik fél? | Architektúra, kulcskonfiguráció, BYOK- vagy HYOK-konfiguráció |
| 3.2 · K·3+ | Lehet bizonyítani, hogy ki, mikor és honnan közelít meg adatokat? | Naplók, auditnyomozó, SIEM-jelentés |
| 3.3 · K·2+ | Megmarad-e az adat tárolása és feldolgozása, beleértve a biztonsági másolatokat, a telemetriát és a támogatást az EU-ban? | DPIA, architektúra, alvállalkozók, adat központ helyszínek |
| 3.4 · O·2+ | Szükséges-e a szerződésben kizárni az adatot az AI-képzéshez vagy modellfejlesztéshez? | Szerződés, alvállalkozói megállapodás |
| 3.5 · O·2+ | Lehet-e bizonyítani, hogy az adatokat véglegesen törlik, beleértve a biztonsági másolatokat és a származékos adatgyűjteményeket? | Törlési tanúsvány, eljárás, szerződés |
| 3.6 · O·2+ | Van-e támogatási hozzáférés, és ezt naplózják? | Támogatási politika, naplók, szerződés |
---
<!-- _class: table table-editable -->

# SOV-3 · Találdatok és bizonyítékok

| Kérdés · típus/min. | Valós tény | Forrás-azonosító | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 3.1 · Titkosítási kulcsok kezelése (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Visszavezhető adat hozzáférés (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Tárolás és feldolgozás az EU-ban (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · Nincs AI-képzés az adatokkal (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Végleges törlés (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Átengedett támogatási hozzáférés (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-3 · Szintértékelés

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Nincs ellenőrzés | A kínáló rendelkezik valós hozzáféréssel és kulcskontrollal | Nincs |
| 1 | EU-raktár | Az EU-raktár megállapodásban szerepel; a hozzáférés vagy a kulcskontroll közös vagy nem egyértelmű | 1 |
| 2 | Technológiai megerősítés | Ügyfalui kulcskezelési és hozzáférési korlátozások; a kínáló még hozzáférhet a kulvashoz vagy olvasható adatokhoz | 2 |
| 3 | Védetlen ellenőrzés | Csak a felvevő irányítja a kulvashoz; a kínáló nem lát olvasható adatokat; a feldolgozás továbbra is az EU-ban | 3 |
| 4 | Teljes kontroll | Teljes kontroll az adatok, kulcsok, AI-modellek és feldolgozás felett | 4 |
---
<!-- _class: table table-editable -->

# SOV-3 · Célkitűzési következtetés

| Alapozás a központi értékelési táblázat számára | Megvalósítás |
| --- | --- |
| Valós helyzet és megfelelő jellemző a szintskála alapján | … |
| A kritikus kérdések legalapúbb bizonyítéka, forrás-azonosítókkal | … |
| A szabályok 0 és 5 alkalmazása és esetleges korlátozása | … |
| A legfontosabb ok, kockázat és találdatos azonosító | … |
---
<!-- _class: section -->

# SOV-4 · Üzemeltel szuverenitás
---
<!-- _class: táblázat -->

# SOV-4 · Ellenőrző kérdések

| Kérdés · típus/min. | Ellenőrző kérdés | Szükséges bizonyíték |
| --- | --- | --- |
| 4.1 · K·2+ | Dokumentált és tesztelt a migrálás, és a data és konfigurációk teljes mértékben exportálhatók? | Migrálási eljárás, exportteszt, Adat-jog klauzulyok |
| 4.2 · K·2+ | Lehet-e az incidencselés és a napi adminisztráció teljes mértékben EU-s dolgozók által végezni? | Csapatfelügyeleti áttekintés, támogatási helyszín, SLA |
| 4.3 · O·2+ | Átörzítésre johtható az üzleti tudás, és nem kizárólag a beszállítóknál van? | Képzési terv, tudásbiztosítás, dokumentáció |
| 4.4 · O·2+ | Van-e az önálló szervezésben teljes mértékű technikai dokumentáció és runbooks? | Dokumentáció inventár, runbooks |
| 4.5 · O·1+ | Ismertek és reálisan helyettesíthetők a kritikus alvállalkozók? | Alvállalkozói lista, alternatív elemzési elemzés |
| 4.6 · O·2+ | Van-e egy kilépési forgatókönyv reális átköltéssel és költségekkel? | Kilépési stratégia, migrálási üzleti esettel |
---
<!-- _class: táblázat táblázható -->

# SOV-4 · Találdok és bizonyítékok

| Kérdés · típus/min. | Valós tény | Forrás-azonosító | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 4.1 · Tesztelt migrálás és export (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Adminisztráció teljes mértékben EU-s dolgozók által (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Átörzítésre johtható üzleti tudás (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Dokumentáció és runbooks (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Helyettesíthető alvállalkozók (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Reális kilépés (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: táblázat táblázható -->

# SOV-4 · Szint meghatározás

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Függő | Az üzleti tevékenység teljes mértékben függ nem-EU beszállítóktól vagy személyzetetől | Nincs |
| 1 | Hatott | EU-üzemeltetés papír alapú; kritikus tevékenységek a nem-EU-s működésben befolyásolhatók | 1 |
| 2 | Használható függőségekkel | EU-üzemeltetés lehetséges; fontos függőségek vagy elakadások továbbra is fennmaradnak | 2 |
| 3 | Jelentős kontroll | Az EU-s szereplők irányítják a működést; támogatási hozzáférés EU-s, naplóolva és engedélyezve; kilépés reális | 3 |
| 4 | Kontroll alatt | Teljes EU-üzemeltetés a kritikus nem-EU függőségek nélkül | 4 |
---
<!-- _class: table table-editable -->

# SOV-4 · Fő következtetés

| Központi pontszám alapja | Megvalósítás |
| --- | --- |
| Ténybeli helyzet és a skálán található megfelelő jellemző | … |
| Kritikus kérdésekre vonatkozó legalapvetőbb bizonyíték, forrás-azonosítókkal | … |
| Alkalmazott szabályok és esetleges korlátozások | … |
| Főbb ok, kockázat és találdozó-azonosító | … |
---
<!-- _class: section -->

# SOV-5 · Szolgáltatófüggetlenség
---
<!-- _class: table -->

# SOV-5 · Ellenőrző kérdések

| Kérdés · típus/min. | Ellenőrző kérdés | Szükséges bizonyíték |
| --- | --- | --- |
| 5.1 · K·2+ | Van-e aktuális SBOM (szoftverösszetevőlista) a szolgáltatásban található szoftverekhez? | SBOM, beszállói nyilatkozattal |
| 5.2 · O·1+ | Ismert a hardver és firmware eredete, valamint nem EU-függőségek? | Hardver-inventár, firmware áttekintés, nyilatkozattal |
| 5.3 · K·2+ | Lehet a frissítések széles körben történő felépülésének, validálásának és visszavonásának fázisosan történni? | Frissítési politika, konfiguráció, tesztjelentés |
| 5.4 · O·1+ | Ismert a build- és aláíró infrastruktúra helye és joga? | Technikai dokumentáció, architektúra diagram |
| 5.5 · K·2+ | Tudnak-e minden alvállalkozókról tájékozódni, és van-e szerződésben rögzített módja a változás értesítésének? | Alvállalkozói lista, szerződési rendelkezés |
| 5.6 · O·2+ | Van-e szerződésben rögzített auditjoga az alvállalkozók számára? | Szerződési rendelkezések, audit jelentések |
---
<!-- _class: table table-editable -->

# SOV-5 · Találdozatok és bizonyítékok

| Kérdés · típus/min. | Ténybeli találdozás | Forrás-azonosító | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 5.1 · Aktuális SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Hardver és firmware eredete (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Frissítések validálása és visszavonása (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Build- és aláírási jogok (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Alvállalkozók és változás értesítés (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Auditjogok alvállalkozók (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-5 · Műszaki Szint Felmérése

| Szint | Jelölés | Jellemző | Min. bizonyíték |
| --- | --- | --- | --- |
| 0 | Nincs hatás | Kritikus lánc teljes mértékben kívüláll a tagságság EU-s hatás körébe tartozásából | Nincs |
| 1 | Átláthatatlan | Az EU jogi szabályozása formálisan alkalmazható, de a lánc átláthatatlan | 1 |
| 2 | Érthetőség a függőségekkel | A lánc érthető; anyagi nem-EU függőségek továbbra is fennállnak | 2 |
| 3 | Jelentős hatás | A kritikus pontok diverzifikáltak; frissítések ellenőrizhetőek; a build- és aláíró lánc ismert | 3 |
| 4 | Átlátható és irányítása alatt | Teljes átláthatóság, anélkül, hogy kritikus nem-EU függőségek lennének | 4 |
---
<!-- _class: table table-editable -->

# SOV-5 · Fő Mérőszám Konklúziója

| A fő mérőszám alapja | Megoldás |
| --- | --- |
| A valós helyzet és a megfelelő jellemző a szintskála alapján | … |
| A kritikus kérdések legkisebb bizonyítéka, forrás-azonosítókkal | … |
| A szabály 5 alkalmazása és esetleges korlátozása | … |
| A legfontosabb ok, kockázat és megállapodás-azonosító | … |
---
<!-- _class: section -->

# SOV-6 · Technológiai Osztrácia
---
<!-- _class: table -->

# SOV-6 · Ellenőrző Kérdések

| Kérdés · Típus/Min. | Ellenőrző Kérdés | Szükséges Bizonyíték |
| --- | --- | --- |
| 6.1 · K·2+ | Az API-k alapvető szabványokon alapulnak, melyek nyíltan dokumentáltak? | API-dokumentáció, szabványok katalógusa |
| 6.2 · K·2+ | Milyen módon lehet az összes adatot a kulcsfontosságú funkciók elvesztése nélkül nyitott formátumúba exportálni? | Exportteszt, technikai dokumentáció |
| 6.3 · O·2+ | Milyen szoftverlicsek és korlátozások vonatkoznak az alkalmazásra vagy újrahasználandósságra? | Licencszövegek, jogi elemzés |
| 6.4 · O·2+ | Van-e szerződve forráskód-ellenőrzési joggal vagy eskrow-megállapodás? | Eskrow-megállapodás, ellenőrző jelentés |
| 6.5 · O·1+ | A teljes teknológia-csomag dokumentált, beleértve a zárt komponenseket és alternatívákat? | Architektúra, komponens katalógus |
| 6.6 · O·2+ | Lehetséges-e a technológia alternatívra való átvitele valós és tesztelt módon? | Átviteles teszt, kilépési stratégia, alternatívák elemzése |
---
# SOV-6 · Érdelemek és bizonyíték

| Kérdés · Típus/Min. | Valódi érdeklemény | Forrás-ID | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 6.1 · Nyitott és dokumentált API-k (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Végsősorú, nyitott adatexport (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Licenciák és újrahasznosítás (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Forráskód-felülvizsgálat vagy bérleti szerződés (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Dokumentált teknológia-csomópont (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Tesztelt migráció alternatívra (O·2+) | … | … | … | L/M/H · J/O/S |
---
# SOV-6 · Szintfelmérés

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Zárt | Zárt ökoszisztéma; a migráció gyakorlatilag nem lehetséges | Nincs |
| 1 | Kapcsolattartás | Egyes kapcsolhatóság; a kapcsolattartás dominál | 1 |
| 2 | Migrálható | Az interoperabilitás és az export biztosított; audit- és bérleti lehetőségek léteznek | 2 |
| 3 | Jelentős önálló | A helyettesíthetőség tesztelve; a kritikus szoftver ellenőrizhető audit vagy nyílt forrásból | 3 |
| 4 | Kontroll alatt | Teljes kontroll az integráció és a szabványok tekintetében kritikus zárt függőségek nélkül | 4 |
---
# SOV-6 · Célkitűzési következtetés

| Alap a központi értékelési táblázat számára | Megvalósítás |
| --- | --- |
| Valódi helyzet és megfelelő jellemző a szintskála alapján | … |
| Legalacsonyabb bizonyíték kritikus kérdésekre, forrás-ID-kkel | … |
| A szabály 5 alkalmazása és esetleges korlátozása | … |
| Legfontosabb ok, kockázat és érdeklemény-azonosító | … |
---
<!-- _class: section -->

# SOV-7 · Biztonsági és megfelelőségi szuverenitás
---
# SOV-7 · Tesztkérdések

| Kérdés · típus/min. | Tesztkérdés | Szükséges bizonyíték |
| --- | --- | --- |
| 7.1 · K·3+ | Az beszámolósor-nyújtó megfelelőségi tanúsítvánnyal rendelkezik, és az audit az EU felügyelete alá tartozik? | Tanúsítvány, auditjelentés, hatókör |
| 7.2 · K·2+ | A SOC az EU-ban van-e, és működésben az EU jogi szabályozása alá tartozik? | SOC helyszín, szerződés, SLA |
| 7.3 · O·3+ | A NIS2, DORA, GDPR és CRA követelményinek bizonyíthatósága és külső ellenőrzése? | Következtetésjelentés, felügyelő hatóság, audit |
| 7.4 · K·2+ | Kinek végzi a gyengésség-kezelést és a javításokat, és ez önállóan megtehető az EU-ban? | Javítási politika, SLA, technikai dokumentáció |
| 7.5 · K·2+ | A jogosultsági jogok gyakorlati jelleggel megvalósíthatók, beleértve a rendszer- és logolaszthatóságot? | Szerződéses jogosultsági jog, végrehajtott auditjelentés |
| 7.6 · O·2+ | A adatvédelmi incidensekre és eseményekre vonatkozó jelzésfolyamdolog GDPR-konform és bizonyíthatósága van? | Incidens terv, beszámoló felelősség szabályzat, jelzésregisztráció |
---
# SOV-7 · Találdatok és bizonyítékok

| Kérdés · típus/min. | Valós tény | Forrás-azonosító | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 7.1 · A megfelelőségi tanúsítvány az EU felügyelete alá tartozik (K·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · A SOC az EU-ban van-e, és működésben az EU jogi szabályozása alá tartozik (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Külső ellenőrzött megfelelőség (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU-gyengésség-kezelés (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Praktikusan megvalósítható jogosultsági jogok (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · GDPR-konform jelzésfolyamdolog (O·2+) | … | … | … | L/M/H · J/O/S |
---
# SOV-7 · Szintértékelés

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Függő | A biztonsági műveletek teljes mértékben nem EU-ellenőrzés alatt állnak | Nincs |
| 1 | Behatolható megfelelőség | Formális megfelelőség; a végrehajtás továbbra is behatolható az EU-n kívül | 1 |
| 2 | Szerződéses biztosítás | EU jogi szabályozása, az audit- és jelzési kötelezettségek szerződésben vannak rögzítve | 2 |
| 3 | EU-műveletek | Az EU-biztonsági műveletek hatékonyak és független auditok lehetségesek | 3 |
| 4 | Ellenőrzés alatt | Teljes ellenőrzés a felügyelet, incidencetek kezelése, javítások és megfelelőség | 4 |
---
# SOV-7 · Központi konklúzió

| A központi pontszámhoz tartozó indoklás | Összevonás |
| --- | --- |
| Valós helyzet és megfelelő jellemző a szintskála alapján | … |
| A kritikus kérdések legkisebb bizonyítéka, forrás-azonosítókkal | … |
| Használt szabályok és esetleges korlátozások | … |
| A legfontosabb ok, kockázat és találdok-azonosító | … |
---
<!-- _class: section -->

# SOV-8 · Fenntarthatóságbiztonság
---
<!-- _class: table -->

# SOV-8 · Ellenőrzési kérdések

| Kérdés · típus/min. | Ellenőrzési kérdés | Szükséges bizonyíték |
| --- | --- | --- |
| 8.1 · K·2+ | Milyen a mértek PUE a dáticentrum helyszínen? | Dáticentrum jelentése, független mérés |
| 8.2 · O·2+ | Az energia bizonyíthatóan megújuló és független módon vannak-e a tanúsítványok megerősítve? | Energia tanúsítványok, független jelentés |
| 8.3 · O·2+ | A CO2-kibocsátás és a vízfogyasztás átlátható és független módon van-e ellenőrizve? | ESG jelentés, könyvveljeszményi nyilatkozat, GRI |
| 8.4 · O·1+ | Van-e dokumentált és ellenőrizhető hardvertartó életciklusa és e-hulladékkezelési politikája? | Politika, ISO 14001 tanúsítvány |
| 8.5 · O·1+ | Értékelve van a kritikus természeti erőforrások függősége? | Kockázatértékelés, beszállító nyilatkozata |
| 8.6 · O·1+ | Van-e a beszállító CSRD- alá tartozó és a jelentései nyilvánosak; ha nem, akkor önkéntesen jelent? | Éves jelentés, CSRD vagy önkéntes jelentés |
---
<!-- _class: table table-editable -->

# SOV-8 · Találdok és bizonyítékok

| Kérdés · típus/min. | Valós tény | Forrás-azonosító | Bizonyíték 0-4 | Hatás / kockázat |
| --- | --- | --- | --- | --- |
| 8.1 · Mértek PUE a helyszínen (K·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Megerősített megújuló energia (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · CO2 és víz független ellenőrzése (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Életciklus és e-hulladék politika (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Kritikus természeti erőforrások értékelése (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD vagy önkéntes jelentés (O·1+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-8 · Szint meghatározása

| Szint | Jelölés | Jellemző | Minimális bizonyíték |
| --- | --- | --- | --- |
| 0 | Átláthatatlan | Nincs átláthatóság; domináns nem-EU függőség energia vagy anyagok tekintetében | Nincs |
| 1 | Alapjelentés | Alapjelentés jelen van; nagy szerkezetes függőség marad | 1 |
| 2 | Átlátható függőségekkel | Átláthatóság és szerződési követelmények jelen vannak; anyagi függőségek maradnak | 2 |
| 3 | Hatás | Jelentős EU hatás az energiaforrás és körforrásos ökoszisztéma tekintetében | 3 |
| 4 | Fenntartható | Teljesen fenntartható, átlátható és EU-ba épített strukturális felügyelet | 4 |
---
# Központi pontszám alapítványa · Végső következtetés

| Központi pontszám alapítványa | Teljesítés |
| --- | --- |
| Valódi helyzet és megfelelő jellemző a szintskála szinteiből | … |
| A kritikus kérdésekben talált legalapvetőbb bizonyíték, forrás-azonosítókkal | … |
| Alkalmazott szabályok és esetleges korlátozások | … |
| Főbb ok, kockázat és találdozó-azonosító | … |
---
# Konklúzió és asszurance ítélet
---
# Jogosság az adat típusok szerint · Szabály 0

| Adat típus | Ellenőrző keret | Alapítvány és forrás-azonosító | Eredmény | Tárgyalt SOV cél |
| --- | --- | --- | --- | --- |
| Személyes adatok | GDPR, beleértve az adattranszparencia és a megfelelő intézkedések | … | Alapozott / kockázat | … |
| Nem személyes üzleti adatok | Adat törvény 32. cikk | … | Alapozott / kockázat | … |
| Kormányzati vagy témájú információk | A vonatkozó nemzeti és EU szabályok | … | Alapozott / kockázat | … |
| Szabályozott szektor adatai | NIS2, DORA vagy szektorspecifikus szabályok | … | Alapozott / kockázat | … |
---
# Jogszabályi megfelelőséghez való kitettség · Szabály 4

| Személy/Jogszabály és jogrend | Tűz lehet a kormány által erőltetve? | Független bírósági eljárás? | Tájékoztatás adható a vevőnek? | Eredmény a bizonyítékok és a szintszint wzglęmban |
| --- | --- | --- | --- | --- |
| … | Igen / nem / bizonytalan | Igen / nem / bizonytalan | Igen / nem / bizonytalan | … |
| … | … | … | … | … |
| … | … | … | … | … |
---
# Szabály 4 · Kötelező következtetés

| Feltétel vagy következmény | Megállapítás és forrás-azonosító |
| --- | --- |
| Egy hatóság elállhat az hozzáférés követelése vagy együttműködés | Igen / nem / bizonytalan: … |
| Független jogi eljárás hiányos vagy az előállító figyelmeztetése tilos | Igen / nem / bizonytalan: … |
| Ha mindkettő igaz: kérdések 2.3, 2.5 és 2.6 bizonyítékként 0 szintű | Alkalmazott / nem alkalmazott: … |
| Ha mindkettő igaz: a SOV-2 maximum 1 szintű | Alkalmazott / nem alkalmazott: … |
| Ha a befolyás a jogrendszerben van, akkor a SOV-1 maximum 1 szintű | Alkalmazott / nem alkalmazott: … |
| Maradó kitettség | … |
---
# Technikai útvonal · Szabály 5

| Feltétel | Következtetés és forrás-azonosító |
| --- | --- |
| A SOV-3 minimum 3 szintű: kulcsok kizárólag az előállítóznál; az szolgáltató nem látja olvasható adatokat | … |
| Nincs adminisztratív vagy támogatási hozzáférés olvasható adatokhoz | … |
| A SOV-5 minimum 3 szintű: frissítések előzetesen ellenőrizve és visszavonható; építési és aláíró lánc ismerős | … |
| A SOV-6 minimum 3 szintű: a kritikus szoftver működése ellenőrizhető | … |
| A szolgáltatás nem kell olvasható formában feldolgozni az adatokat | Igen / nem |
| Minden feltétel teljesül | Csak "igen", ha az előző következtetések mind pozitívak: … |
| Következmény | Támogathatja a Szabály 0-t; nem változtatja meg a SOV-2 szintet vagy a SEAL teljes szintet. |
---
<!-- _class: table table-editable -->

# SAFARI-pontozó

| Kód | Súly | Megállapított 0-4 | Bizonyíték 0-4 | Értékelés a kiválasztott normához | Célkonziszencia forrása |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | 15% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-2 | 10% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-3 | 10% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-4 | 15% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-5 | 20% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-6 | 15% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-7 | 10% | … | … | Megfelel / szakadás / nem alkalmazott | … |
| SOV-8 | 5% | … | … | Megfelel / szakadás / nem alkalmazott | … |
---
<!-- _class: table table-editable -->

# Összesítés

| Alcsoport | Következtetés és indoklás |
| --- | --- |
| SEAL teljes szint – legalábbis kulcsfontosságú cél | … |
| Súlyozott ECSF pontszám – Σ (megállapított szint / 4 × súly) | …% |
| Legnagyobb szakadások | … |
| Kritikus függőségek | … |
| Szerzett szintek a javaslat alacsonyabb szintjén | … |
| Jogszabályossági kockázatok | … |
| Belső megoldható | … |
| Szolgáltató együttműködése szükséges | … |
---
# Javasolt CADA Pozíció

| Alapkomponens | Eredmény és Forrás-azonosító |
|---|---|
| Fontosság | Közszektor / kritikus tevékenység / NIS2-szektor / nem releváns |
| Célzott CADA Szint | 1 / 2 / 3 / 4 / nem releváns |
| Javasolt Elérhető Szint | 1 / 2 / 3 / 4 / nincs |
| Nem Eltartott Szükségszükségletek | … |
| Bizonylati Korlátozás | … |
| Kötelező Megfogalmazás | Javaslat alapján történő jelzés; nem ítélkezzük a megfelelőségről. |
---
# Biztonsági Értékelési Vélemény Célok szerint

| Cél | Bizonylati Kritikus Kérdések | Jogtalmasági Rizikó | Biztonsági Értékelési Típus | Megfogalmazás és Megjegyzés |
|---|---|---|---|---|
| SOV-… | Legalacsonyabb szint: … | Igen / nem | Nincs / korlátozott / megfelelő | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |
---
# Biztonsági Értékelési Segítő Megfogalmazás

| Típus | Feltétel | Standard Megfogalmazás |
|---|---|---|
| Nincs Értékelés | Egy kritikus kérdés bizonyítékkonyezse 0 vagy 1 | A rendelkezésre álló bizonyítékok alapján nem lehetséges [cél] tekintetében [szolgáltatás] megfelelőségéről ítélni. |
| Korlátozott Biztonság | Minden kritikus kérdés legalább 2; nem minden legalább 3 | Munkafolyamatok során nem találtunk bizonyítékot, hogy [állítmány] helytelen lenne. Korlátozott mértékben nyújtunk biztonságot. |
| Megbízható Biztonság | Minden kritikus kérdés legalább 3 | Munkafolyamatok során megítélésünk szerint [állítmány] igaz. Megbízható mértékben nyújtunk biztonságot. |
---
# Találdozatok és Javaslatok

| ID | SOV | Találdozat | Hatás | Javaslat | Tulajdonos | Időpont |
|---|---|---|---|---|---|---|
| F-01 | … | … | Magas / közepes / alacsony | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |
---
<!-- _class: table table-editable -->

# Minőségi Ellenőrzés és a Mérlegelő Dátum Miatti Események

| Ellenőrzés | Eredmény és értékelő hivatkozás |
| --- | --- |
| A hatókör és az állítás előzetesen meghatározott | … |
| Minden kritikus kérdés lefedve vagy korlátozásként jelentett meg | … |
| A forrásmegjelölések nyomon követhetők és a bizonyítékképviselési szintek követhetők | … |
| A 0-tól 5-ig terjedő pontozási szabályok bizonyítottan alkalmaztak | … |
| A számviteli és szöveges konzisztenciát ellenőrizték | … |
| Független értékelés befejeződött | … |
| A mérlegelő dátum utáni események értékeltek | … |
| Megnyílt értelmezési különbségek feldolgozva | … |
---
<!-- _class: table table-editable -->

# Szervezet Állításának Megállapítása

| Megállapítás | Teljesítés |
| --- | --- |
| Felelős szerepviselő neve és funkciója | … |
| Magyarázat | Az állítás, a hatókör és a kiválasztott szabványok teljeskörűek és igazak. |
| Dátum | … |
| Elfogadás | Igen / Nem |
---
<!-- _class: table table-editable -->

# Független Minőségi Ellenőrzés

| Ellenőrzés | Teljesítés |
| --- | --- |
| Ellenőr neve és funkciója | … |
| Független a végrehajtástól | Igen / Nem |
| Ellenőrzési megállapítás és esetleges megmaradt pontok | … |
| Dátum | … |
| Engedély a aláírásra | Igen / Nem |
---
<!-- _class: sign-off -->

# Garanciás ítélet aláírása
---
# Források és licenc

- Módszertan: SAFARI v0.9 (tervezet), Brenno de Winter és a LibreKAT Alapítvány.
- Állapot: önkéntes módszertan. A minimumszabályok javaslat jellegűek; a 0-tól 5-ös szabályok kötelezőek azok számára, akik a SAFARI alkalmazását teszik lehetővé.
- Alapelv: Az Európai Felhő Szuverenitás Keretrendszere, kiegészítve az ISO 27001:2022 és egy ISAE 3000-as biztosítási struktúrával.
- Teljes módszertan: https://pawprint.vigilis.online/LibreKAT/Safari
- Ez a sablon tartalom egy SAFARI-ból származó feldolgozás, és a CC BY-SA 4.0 licenc alatt áll: https://creativecommons.org/licenses/by-sa/4.0/
- Mindig töltse ki a legfrissebb verziót, a mérőszámot, a szakmai szabványokat és a helyi jogszabályi követelményeket.
