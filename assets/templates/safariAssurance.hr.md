---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SAFARI procjena digitalnog suvereniteta
language: hr
standards: SAFARI@0.9, ECSF
---
<!-- _class: title -->

# SAFARI procjena digitalnog suvereniteta

---
# Kako se ovo radno zadiranje koristi

- Prvo utvrdite opseg, tvrdnju, željeni nivo i namjerenu razinu sigurne.
- Popunite svaki upitni bod, nalaze, povratnički izvor i razinu dokaza.
- Obradite nedostajuće ili odbijene dokaze kao nalaz s razinom dokaza 0.
- Primijenite šest pravila rangiranja prije utvrđivanja razine po cilju SOV.
- Formulirajte mišljenje o osiguravanju tek nakon što su se proveli kvalitativni nadzor i događaji nakon referentnog datuma.
---
<!-- _class: table table-editable -->

#  Tim za upravljanje dokumentima i dodjelu

| Polje | Dovršetak |
| --- | --- |
| Organizacija | … |
| Servis ili sustav | … |
| Leliver | … |
| Klijent | … |
| Odgovoran za zahtjev | … |
| Izvršni revizor ili konzultant | … |
| Nezavisni recenzent | … |
|  Referentni datum i razdoblje ocjenjivanja | … |
|  Verzija i datum izvješća | … |
| TLP klasifikacijski i distribucijski popis | … |

---
<!-- _class: table table-editable -->

# Objekt i opseg

| Komponenta opsega | Implementacija |
| --- | --- |
| Procjenjene aplikacije, platforme i infrastruktura | … |
| Direkte dobavljači | … |
| Relevantni poddobavljači i lančani partneri | … |
| Vrste podataka | Lični podaci / poslovni podaci / državni podaci / kodificirana informacija |
| Zakonodavni propisi po stranci | … |
| Lokacije upravljanja, podrške, izgradnje i potpisivanja | … |
| Eksplicitni isključenja s objašnjenjem | … |
| Verzija okvirnog okvira | SAFARI v0.9 (koncept; slobodna metodologija) |
---
<!-- _class: table table-editable -->

# Tvrdnja organizacije

| Komponenta | Tekst implementacije |
| --- | --- |
| Objekt | [Organizacija] je procijenila suverenost u pogledu [služba], isporučenu od strane [dobavljač]. |
| Razdoblje | Procjena se odnosi na situaciju prema [datum] unutar opsega koji je utvrđen na [datum]. |
| Okvir | Procjena je provedena sukladno SAFARI v0.9, slobodnoj konceptnoj metodologiji vezanoj uz ISO 27001:2022 i osam ciljeva ECSF. |
| Rezultat | Organizacija navodi da ispunjava odabrani razinu [0-4] za [SOV-kod ili sve ciljeve]. |
| Rezervacija | Rezultat je baziran na dostupnim dokazima prema referentnom datumu; promjene mogu utjecati na rezultat. |
| Vlasnik i formalno potvrđenje | … |
---
<!-- _class: table table-editable -->

# Željeni nivoi i ključni ciljevi

| Kod | Cilj | Ključni cilj | Preporučena minimalna razina | Željeno | Objašnjenje odstupanja |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Strategijski | Da | 2 | … | … |
| SOV-2 | Pravni i pravni | Da | 2 | … | … |
| SOV-3 | Podaci i AI | Da | 3 (2 samo niske osjetljivosti i bez osobnih podataka) | … | … |
| SOV-4 | Operativni | Da | 3 (2 samo niske osjetljivosti, zamjenjiv i bez osobnih podataka) | … | … |
| SOV-5 | Lanac | Da | 3 (2 samo niske osjetljivosti i bez osobnih podataka) | … | … |
| SOV-6 | Tehnologija | Da | 3 (2 samo niske osjetljivosti i bez osobnih podataka) | … | … |
| SOV-7 | Sigurnost i usklađenost | Da | 2 | … | … |
| SOV-8 | P održivost | Da | 1 | … | … |
---
<!-- _class: table table-editable -->

# Apristup osiguranja

| Part | Izbor i utemeljenje |
| --- | --- |
|  Vrsta naredbe | Savjetovanje / ograničeno jamstvo / razumno jamstvo |
| Ciljevi unutar tvrdnje s uvjerenjem | … |
|  Materijalnost i selekcija usmjerena na rizik | … |
| Aktivnosti po vrsti dokaza | Inspekcija / promatranje / ponovno izvršenje / potvrda / analiza |
|  Pristup uzorkovanju i populacije | … |
| Raspoređeni stručnjaci | Pravni / tehnički / održivost / ostalo: … |
| Neovisnost i sukobi interesa | … |
| Ograničenja pristupa ili aktivnosti | … |

---
<!-- _class: table table-editable -->

# Formalno osiguranje upita

| Kriterij prihvaćanja | Procjena i izvor | Rezultat |
| --- | --- | --- |
| SAFARI je pogodan kao kriterij za tvrdnju i namijenjene korisnike | … | Da / ne |
| Odgovorna strana prepoznaje svoju odgovornost za tvrdnju | … | Da / ne |
| Razumljiv cilj, namijenjeni korisnici i krug raspodele su utvrđeni | … | Da / ne |
| Neovisnost, etika, stručnost i potrebni stručnjaci su osigurani | … | Da / ne |
| Uvjeti upita i željena razina sigurne su dogovorene | … | Da / ne |
| Umiješano je dovoljno odgovarajućih dokaza očekivano dostupno | … | Da / ne |
| Odlučka o prihvaćanju | Samo nastaviti ako su sva kriterija 'da' | Prihvatiti / odbiti |
---
<!-- _class: table -->

# Razine dokaza

| Razina | Ime | Aplikacija |
| --- | --- | --- |
| 0 | Nema dokaza |  Nema dokaza ili nedostaju ili su odbijeni dokazi |
| 1 | Izjava |  Usmena ili pisana izjava bez daljnjeg potkrepljivanja |
| 2 | Dokumentacija | Ugovor, politika, postupak ili izvješće bez neovisne provjere |
| 3 | Tehnički dokaz | Konfiguracija, zapisnik, test ili vanjski pravni savjet koji je korisnik dobio |
| 4 | Neovisni dokazi | Prikupila ili potvrdila neovisna strana za testiranje |

---
<!-- _class: table table-editable -->

# Centralni registar evidencije

|  ID izvora | Dokument ili registracija | Vlasnik | Datum i verzija | Podrijetlo | Cjelovitost i mjesto pohrane |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Interno / dobavljač / eksterno | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |

---
<!-- _class: table -->

# Pravilo rangiranja

| Pravilo | Posljedica za mišljenje |
| --- | --- |
| 0 · Pravovječnost | Pravovječni rizik čini da je cilj uvijek rascjepljen; preporučite pravni pregled. |
| 1 · Kritična pitanja | Razina dokaza 0 na kritičnom pitanju ograničava cilj na maksimalno razinu 1. |
| 2 · Dokaz nosi razinu | Dokaz ispod minimuma pitanja računa se kao 0. Ciljno dokaze je najniži dokaz na kritičnim pitanjima; razina 2, 3 i 4 zahtijevaju da barem onaj dokaz ima isti razinu dokaza. |
| 3 · Najslabija veza | Razina SEAL-a je najniža utvrđena razina ciljeva. |
| 4 · Uredno pravno stanje | Ako je obvezujuće strano pristupače zaštićeno samo punom tehničkom putanju; to ne mijenja SOV-2 i SEAL-ovu razinu. Služba koja treba čitati podatke ne treba ovu putanju. |
| 5 · Tehnička ruta | Ako je obvezujuće strano pristupače zaštićeno samo punom tehničkom putanju; to ne mijenja SOV-2 i SEAL-ovu razinu. Služba koja treba čitati podatke ne treba ovu putanju. |
---
<!-- _class: section -->

# SOV-1 · Strateški suverenitet

---
<!-- _class: table -->

# SOV-1 · Upitni bodovi

| Pitanje · tip/min. | Upitni bod | Zahtjevan dokaz |
| --- | --- | --- |
| 1.1 · K·2+ | Tko su konačni dioničar i pod redom su registrirani? | UBO registar, godišnji izvadak, registar dioničara |
| 1.2 · K·2+ | Može li vanzemni majstor izvan EU-a primijeniti stratešku promjenu? | Grupska struktura, statuti, pravila uprave |
| 1.3 · Change-of-control (K·2+) | Sadrži li ugovor klauzule o promjeni vlasti? | Tekst ugovora |
| 1.4 · Lokacija tehnologije i IP (O·1+) | Je li tehnologija i IP smještena u EU entitet ili vanzemalni majstor? | Registracija IP-a, ugovori o licenci |
| 1.5 · Zavisnost na razini uprave (O·2+) | Je li zavisnost od dobavljača izražena i dokumentirana na razini uprave? | Notiranje uprave, registar rizika |
| 1.6 · Izlaz kod promjene vlasništva (O·2+) | Je li postavljen scenarij izlaska ili kontinuiteta za promjenu vlasništva? | Plan kontinuiteta, strategija izlaska |
---
<!-- _class: table table-editable -->

# SOV-1 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Razina dokaza 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 1.1 · UBO-vi i redovni propisi (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Vanjski majstor može primijeniti promjenu (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Promjena vlasti (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Lokacija tehnologije i IP (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Zavisnost na razini uprave (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Izlaz kod promjene vlasništva (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-1 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Nema uvida | Nema uvida u vlasništvo ili strukturu moći | Ništa |
| 1 | Uvid | Insight dostupan, ali nema jamstva u slučaju promjene vlasništva | 1 |
| 2 | Ugovorno jamstvo | Promjena kontrole i transparentnost dogovoreni su ugovorom | 2 |
| 3 | Kontrola | EU upravljanje je odvojeno i provedivo; utjecaj izvan EU je jako ograničen | 3 |
| 4 | Strateška autonomija |  Održivo europski ugrađen; ovisnost je izričito odvagnuta u odluci odbora | 4 |

---
<!-- _class: table table-editable -->

# SOV-1 · Ciljano Zaključje

| Podloga za centralni pokaznik performanse | Uvrstite |
| --- | --- |
| Stvarno stanje i odgovarajući karakter iz ljestvice razine | … |
| Najniži dokaz o kritičnim pitanjima, s ID-ovima izvora | … |
| Primijenjeni pravila i eventualni ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# SOV-2 · Pravni i jurisdikcijski suverenitet

---
<!-- _class: table -->

# SOV-2 · Kritična pitanja za provjeru

| Pitanje · tip/min. | Pitanje za provjeru | Zahtijevani dokaz |
| --- | --- | --- |
| 2.1 · K·2+ | Koja prava vrijede za ugovor i koji sud je ovlašten da odlučuje? | Ugovorni tekst s pravnim i sudskim odabirima |
| 2.2 · K·3+ | Može li EU izvan EU-a tražiti pristup ili suradnju i postoji li nezavisna zaštita prava? | Pravni savjet, grupna struktura i analiza po pravnom sustavu |
| 2.3 · K·2+ | Postoji li obaveza prijavljivanja zbog zahtjeva vlade za pregledom podataka? | Ugovorni klauzula, izvještaj o transparentnosti |
| 2.6 · K·2+ | Postoje li postupci za odbijanje stranih pravnih zahtjeva ugovornim načinom? | Ugovorna klauzula, politika ponuditelja |
| 2.7 · K·2+ | Je li pravovornošću podataka podržana s obzirom na sve relevantne pravne sustave? | DPIA, prenos podataka, mjere Data Act-a, klasifikacija i sektorski propisi |
---
<!-- _class: table -->

# SOV-2 · Podrske pitanja za provjeru

| Pitanje · tip/min. | Pitanje za provjeru | Zahtijevani dokaz |
| --- | --- | --- |
| 2.4 · O·2+ | Postoji li escrow kod izvora i pod kojim uvjetima je on dostupan? | Ugovori o escrowu, notarski dokument |
| 2.5 · O·2+ | Mogu li se ugovorne ovlasti učinkovito ospolovati kod suda u EU? | Pravni savjet, analiza ugovora |
---
<!-- _class: table table-editable -->

# SOV-2 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 2.1 · Pravo i ovlašten sud (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Strana objava i zaštita prava (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Obaveza prijavljivanja zbog zahtjeva vlade (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Escrow kod izvora (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Učinkovitost kod suda u EU (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Odbijanje stranih zahtjeva (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Pravovornošću podataka (K·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-2 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Nema uvida |  Primjenjivi zakon i nadležnost nisu jasni | Ništa |
| 1 | Svijest | Pravna analiza bez ugovornog jamstva | 1 |
| 2 | Ugovorno sidrenje | Odabir prava, izbor foruma i utvrđene obveze izvješćivanja; analizirana je rezidualna izloženost | 2 |
| 3 | Praktično upravljanje |  Postupci sporova i escrow su postavljeni i dokazivo izvedivi | 3 |
| 4 | Učinkovita provedivost | Prava su učinkovito provediva, a izvanteritorijalni rizici se povremeno procjenjuju | 4 |

---
<!-- _class: table table-editable -->

# SOV-2 · Ciljano Zaključje

| Podloga za centralni pokaznik performanse | Uvrstite |
| --- | --- |
| Stvarno stanje i odgovarajući karakter iz ljestvice razine | … |
| Najniži dokaz o kritičnim pitanjima, s ID-ovima izvora | … |
| Primijenjeni pravila 0 i 4 i eventualni ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# SOV-3 · Suverenitet podataka i umjetne inteligencije

---
<!-- _class: table -->

# SOV-3 · Pitanja za provjeru

| Pitanje · tip/min. | Pitanje za provjeru | Zahtijevani dokaz |
| --- | --- | --- |
| 3.1 · K·3+ | Tko upravlja ključevima za šifriranje: korisnik, ponuditelj ili treća strana? | Arhitektura, politika ključeva, konfiguracija BYOK ili HYOK |
| 3.2 · K·3+ | Je li evidentirano tko, kada i s kojeg lokacije je pristupa bio pod određenim uvjetima podacima? | Logovi, auditni trag, izvještaji SIEM |
| 3.3 · K·2+ | Ostaje li pohrana i obrada, uključujući podatke za pohranu, telemetriju i podršku, u EU? | DPIA, arhitektura, podprocesori, lokacije datacentra |
| 3.4 · O·2+ | Je li korištenje podataka za obuku AI ili poboljšanje modela zabranjeno ugovornim načinom? | Ugovor, ugovor o obradniku |
| 3.5 · O·2+ | Mogu li se podatci očistiti na kraju, uključujući podatke za pohranu i izvedene podatke? | Certifikat za brisanje, procedura, ugovor |
| 3.6 · O·2+ | Je li pristup podršci reguliran i bilježen? | Politika podrške, logovi, ugovor |
---
<!-- _class: table table-editable -->

# SOV-3 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 3.1 · Upravljanje ključevima za šifriranje (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Prilagodljivi pristup podacima (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Pohrana i obrada u EU (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · Bez obuke AI s podacima (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Očistite podatke na kraju (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Regulirana pristup podrškom (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-3 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Nema kontrole | Apružatelj ima stvarni pristup i kontrolu ključeva | Ništa |
| 1 | EU pohrana | EU skladištenje dogovoreno; kontrola pristupa ili ključa je podijeljena ili nejasna | 1 |
| 2 | Tehnički ojačan | Upravljanje ključem prema korisniku i ograničenja pristupa; pružatelj još uvijek može pristupiti ključevima ili čitljivim podacima | 2 |
| 3 | A Zaštićena kontrola | Ključevima upravlja samo korisnik; pružatelj ne vidi nikakve čitljive podatke; obrada ostaje u EU | 3 |
| 4 | Puna kontrola |  Potpuna kontrola nad podacima, ključevima, AI modelima i obradom | 4 |

---
<!-- _class: table table-editable -->

# SOV-3 · Ciljano Zaključje

| Podloga za centralni pokaznik performanse | Uvrstite |
| --- | --- |
| Stvarno stanje i odgovarajući karakter iz ljestvice razine | … |
| Najniži dokaz o kritičnim pitanjima, s ID-ovima izvora | … |
| Primijenjeni pravila 0 i 5 i eventualni ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |

Okay, here's the translated version of the Markdown slide blocks from Dutch to professional Croatian, preserving all markers, identifiers, numbers, `…`, URLs, SAFARI, ECSF, ISO 27001:2022, ISAE 3000 and CC BY-SA 4.0 exactly.
---
<!-- _class: section -->

# SOV-4 · Operativni suverenitet

---
<!-- _class: table -->

# SOV-4 · Testne pitanja

| Pitanje · tip/min. | Testno pitanje | Zahtjevani dokaz |
| --- | --- | --- |
| 4.1 · K·2+ | Je migracija dokumentirana i testirana, i su li podaci i konfiguracije potpuno dostupni za eksport? | Postupak migracije, test eksportiranja, Klauzule o Podacima |
| 4.2 · K·2+ | Mogu li incidenti i dnevni rad potpuno obavljati EU djelatnici? | Pregled osoblja, lokacija podrške, SLA |
| 4.3 · O·2+ | Je znanje o operaciji preneseno i nije li prisutno isključivo kod dobavljača? | Plan obuke, potvrda znanja, dokumentacija |
| 4.4 · O·2+ | Ima li organizacija potpunu tehničku dokumentaciju i runbookove? | Inventar dokumentacije, runbookovi |
| 4.5 · O·1+ | Jesu li kritični podizvođači poznati i realno zamjenjivi? | Svrha podizvođača, analiza alternativa |
| 4.6 · O·2+ | Postoji li scenarij za napuštanje s realnim vremenom prelaska i troškovima? | Strategija napuštanja, poslovni slučaj migracije |
---
<!-- _class: table table-editable -->

# SOV-4 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 4.1 · Testirana migracija i eksport (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Rad potpuno obavlja EU djelatnik (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Preneseno znanje o operaciji (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Dokumentacija i runbookovi (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Zamjenjivi podizvođači (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Realan izlaz (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-4 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Aovisno |  Rad u potpunosti ovisi o dobavljaču ili osoblju izvan EU | Ništa |
| 1 |  Impresivno | EU operacija na papiru; može se utjecati na kritične radnje izvan EU | 1 |
| 2 |  Može se iskoristiti s ovisnostima | EU moguća eksploatacija; ostaju važne ovisnosti ili zaključavanje | 2 |
| 3 |  Smislena kontrola | EU akteri kontroliraju rad; pristup podršci vezan je za EU, evidentiran je i dopušten; izlaz je realan | 3 |
| 4 | U kontroli | Potpuni EU rad bez kritičnih ovisnosti izvan EU | 4 |

---
<!-- _class: table table-editable -->

# SOV-4 · Ciljna konkluzija

| Temelj za centralnu bilježnicu | Implementacija |
| --- | --- |
| Stvarna situacija i odgovarajući karakter iz škale razine | … |
| Najniži dokaz na kritičnim pitanjima, s ID-ovima izvora | … |
| Primijenjeni pravila i eventualno ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# SOV-5 · Suverenost lanca

---
<!-- _class: table -->

# SOV-5 · Testne pitanja

| Pitanje · tip/min. | Testno pitanje | Zahtjevani dokaz |
| --- | --- | --- |
| 5.1 · K·2+ | Je li trenutna SBOM dostupna za softver u usluzi? | SBOM, izjava dobavljača |
| 5.2 · O·1+ | Jesu li porijeklo hardvera i firmware te ovisnosti koje nisu u EU poznate? | Inventar hardvera, pregled firmwarea, izjava |
| 5.3 · K·2+ | Mogu li se ažuriranja provesti fazačno, validirati i povratiti? | Politika ažuriranja, konfiguracija, izvještaj o testiranju |
| 5.4 · O·1+ | Jesu li lokacija i jurisdikcija infrastrukture za izgradnju i potpisivanje poznate? | Tehnička dokumentacija, shema arhitekture |
| 5.5 · K·2+ | Jesu li svi podizvođači poznati i je li izmjena ugovorna obavezna? | Svrha podizvođača, klauzula ugovora |
| 5.6 · O·2+ | Je li audit pravilo podizvođača ugovorno zakorovano? | Ugovorne klauzule, izvještaji o auditima |
---
<!-- _class: table table-editable -->

# SOV-5 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 5.1 · Trenutna SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Porijeklo hardvera i firmware (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Ažuriranja validirati i povratiti (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Izgradnja i potpisivanje prava (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Podizvođači i izmjena ugovora (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Audit pravila podizvođača (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-5 · Potencijalna Razina Utjecaja

| Razina | Naziv | Karakteristika | Minimalni dokaz |
| --- | --- | --- | --- |
| 0 | Bez utjecaja | Kritična lanac potpuno izvan utjecaja EU-a | Nema |
| 1 | Netačna | Zakon EU-a je formalno primjenjiv, ali lanac je nejasno tumacen | 1 |
| 2 | Razumijevanje s ovisnostima | Lanac je razumljiv; materijalne ovisnosti izvan EU-a ostaju | 2 |
| 3 | Značaj utjecaja | Kritični elementi su diversificirani; ažuriranja su provjerljiva; lanac izgradnje i potpisivanja je poznat | 3 |
| 4 | Transparentan i pod kontroli | Punim transparentnost bez kritičnih ovisnosti izvan EU-a | 4 |
---
<!-- _class: table table-editable -->

# SOV-5 · Ciljna konkluzija

| Temelj za centralnu bilježnicu | Implementacija |
| --- | --- |
| Stvarna situacija i odgovarajući karakter iz škale razine | … |
| Najniži dokaz na kritičnim pitanjima, s ID-ovima izvora | … |
| Primijenjeni pravila i eventualno ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# SOV-6 · Tehnološki suverenitet

---
<!-- _class: table -->

# SOV-6 · Testne pitanja

| Pitanje · tip/min. | Testno pitanje | Zahtjevani dokaz |
| --- | --- | --- |
| 6.1 · K·2+ | Jesu li sve API-je temeljene na otvorenim i javno dokumentiranim standardima? | Dokumentacija API-ja, registar standarda |
| 6.2 · K·2+ | Mogu li se svi podaci iznijeti bez gubitka funkcionalnosti u otvorenom formatu? | Test eksportiranja, tehnička dokumentacija |
| 6.3 · O·2+ | Koje su licence i ograničenja za prilagodbu ili ponovno korištenje? | Tekst licence, pravna analiza |
| 6.4 · O·2+ | Je li dogovoreno audit pravilo koda ili escrow? | Ugovorna klauzula, izvještaj o auditima |
| 6.5 · O·1+ | Je li cijela steka dokumentirana, uključujući zatvorene komponente i alternative? | Arhitektura, registar komponenti |
| 6.6 · O·2+ | Je li migracija u alternativu realna i testirana? | Test migracije, strategija napuštanja, analiza alternativa |
---
<!-- _class: table table-editable -->

# SOV-6 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 6.1 · Otvorene i dokumentirane API-je (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Bez gubitka otvoren izvoz podataka (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Licence i ponovno korištenje (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Audit pravila koda ili escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Dokumentirana steka (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Testirana migracija u alternativu (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-6 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Zatvoreno |  Zatvoreni ekosustav; migracija je praktički nemoguća | Ništa |
| 1 | Zaključaj se |  Određena mogućnost povezivanja; lock-in ostaje dominantan | 1 |
| 2 |  Premještaj |  Interoperabilnost i izvoz su dogovoreni; postoje opcije revizije i depozita | 2 |
| 3 |  Značajno autonoman | Zamjenjivost je testirana i kritični softver se može provjeriti putem revizije ili otvorenog koda | 3 |
| 4 | U kontroli |  Potpuna kontrola nad integracijom i standardima bez kritičnih zatvorenih ovisnosti | 4 |

---
<!-- _class: table table-editable -->

# SOV-6 · Ciljna konkluzija

| Podloga za centralnu skorjaču | Isprava |
| --- | --- |
| Stvarno stanje i odgovarajući karakter iz ljestice | … |
| Najniži dokaz na kritična pitanja, s ID-ovima izvora | … |
| Primjena pravila 5 i eventualno ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# SOV-7 · Suverenost sigurnosti i sukladnosti

---
<!-- _class: table -->

# SOV-7 · Ključni pitanja

| Pitanje · tip/min. | Ključno pitanje | Zahtijevani dokaz |
| --- | --- | --- |
| 7.1 · K·3+ | Je li pružatelj certificiran prema prepoznatoj normi i je li audit podvrgnut nadzoru EU? | Certifikat, izvještaj o auditu, opseg |
| 7.2 · K·2+ | Je li SOC u EU smješten i operiran pod EU jurisdikcijom? | Lokacija SOC-a, ugovor, SLA |
| 7.3 · O·3+ | Je li proveden provjereni nadzor nametanja NIS2, DORA, AVG i CRA i je li eksternim putem verificiran? | Izvještaj o provedenom nadzoru, nadzornik, audit |
| 7.4 · K·2+ | Tko provodi upravljanje ranjivostima i ispravljanje i može li to samostalno u EU? | Politika ispravljanja, SLA, tehnička dokumentacija |
| 7.5 · K·2+ | Jesu li prava na audit praktično izvedive, uključujući pristup sustavu i logovima? | Ugovorna prava na audit, proveden izvještaj o auditu |
| 7.6 · O·2+ | Je li procedura prijavljivanja datotkarnih prijava i incidenta u skladu s AVG i je li se ona demonstrabilno postavila? | Plan incidenta, ugovorna odredba, registracija prijava |
---
<!-- _class: table table-editable -->

# SOV-7 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 7.1 · Certifikacija pod EU nadzorom (K·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · SOC u EU pod EU zakonom (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Eksternim putem verificirani nameti (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU upravljanje ranjivostima (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Praktično izvedive prava na audit (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · AVG-surodba procedura prijava (O·2+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-7 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Aovisno | Sigurnosne operacije potpuno pod kontrolom izvan EU | Ništa |
| 1 | Impresivno kompatibilan |  Formalna usklađenost; implementacija izvan EU ostaje podložna utjecaju | 1 |
| 2 | Ugovorno zajamčeno | EU nadležnost, revizije i obveze izvješćivanja regulirane su ugovorom | 2 |
| 3 | EU operacije | EU sigurnosne operacije su učinkovite i moguće su neovisne revizije | 3 |
| 4 | U kontroli |  Potpuna kontrola nad nadzorom, odgovorom na incidente, krpanjem i usklađenošću | 4 |

---
<!-- _class: table table-editable -->

# SOV-7 · Ciljna konkluzija

| Podloga za centralnu skorjaču | Isprava |
| --- | --- |
| Stvarno stanje i odgovarajući karakter iz ljestice | … |
| Najniži dokaz na kritična pitanja, s ID-ovima izvora | … |
| Primijenjene pravila i eventualno ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# SOV-8 · Suverenost održivosti

---
<!-- _class: table -->

# SOV-8 · Ključna pitanja

| Pitanje · tip/min. | Ključno pitanje | Zahtijevani dokaz |
| --- | --- | --- |
| 8.1 · K·2+ | Koliki je mjeren PUE po lokaciji datacentra? | Izvještaj o lokaciji datacentra, nezavršena mjerenje |
| 8.2 · O·2+ | Je li energija demonstrabilno obnovljiva i su certifikati nezavisno verificirani? | Certifikati energije, nezavršena izvješća |
| 8.3 · O·2+ | Jesu li emisije CO2 i potrošnja vode transparentne i nezavisno verificirane? | Izvještaj o ESG, računovodstvena isprava, GRI |
| 8.4 · O·1+ | Je li životni cjelina i politika e-otpada dokumentirana i provjerena? | Politika, certifikat ISO 14001 |
| 8.5 · O·1+ | Je li ovisnost o kritičnim sirovinama procijenjena? | Analiza rizika, deklaracija o dobavljaču |
| 8.6 · O·1+ | Je li pružatelj podređen CSRD i su izvješća javna; ako ne, izvještava li slobodno? | Izvještaj o poslovanju, CSRD ili slobodni izvještaj |
---
<!-- _class: table table-editable -->

# SOV-8 · Nalazi i dokazi

| Pitanje · tip/min. | Stvaran nalaz | ID izvora | Dokaz 0-4 | Utjecaj / rizik |
| --- | --- | --- | --- | --- |
| 8.1 · Mjeren PUE po lokaciji (K·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Verificirana obnovljena energija (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · Verificirane emisije CO2 i potrošnja vode (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Životni cjelina i politika e-otpada (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Ovisnost o kritičnim sirovinama (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD ili slobodni izvještaji (O·1+) | … | … | … | L/M/H · J/O/S |
---
<!-- _class: table table-editable -->

# SOV-8 · Određivanje razine

| Razina | Oznaka | Atribut | Min. dokaz |
| --- | --- | --- | --- |
| 0 | Oneproziran | Nema prozirnosti; dominantna ne-EU ovisnost o energiji ili materijalima | Ništa |
| 1 | Osnovno izvješćivanje |  Dostupno osnovno izvješćivanje; glavne strukturne ovisnosti ostaju | 1 |
| 2 | Transparentno sa ovisnostima | Transparentnost i ugovorni zahtjevi dostupni; materijalne ovisnosti ostaju | 2 |
| 3 | Utjecaj |  Značajan utjecaj EU na izvor energije i kružni lanac | 3 |
| 4 |  Održivo |  Potpuno održiv, transparentan i utemeljen u EU sa strukturnim nadzorom | 4 |

---
<!-- _class: table table-editable -->

# SOV-8 · Ciljna konkluzija

| Podloga za centralnu skorjaču | Isprava |
| --- | --- |
| Stvarno stanje i odgovarajući karakter iz ljestice | … |
| Najniži dokaz na kritična pitanja, s ID-ovima izvora | … |
| Primijenjene pravila i eventualno ograničenja | … |
| Najvažniji razlog, rizik i ID nalaza | … |
---
<!-- _class: section -->

# Mišljenje o zaključku i uvjerenju

---
<!-- _class: table table-editable -->

# Legitimnost po vrsti podataka · Redak 0

|  Vrsta podataka | Test okvir | Podrška i ID izvora | Ishod |  Zahvaćeni SOV cilj |
| --- | --- | --- | --- | --- |
| Osobni podaci | AVG, uključujući prijenos i odgovarajuće mjere | … |  Potkrijepljeno / rizik | … |
|  Podaci o tvrtki koji nisu osobni | Zakon o podacima Članak 32 | … |  Potkrijepljeno / rizik | … |
|  Državni ili povjerljivi podaci |  Primjenjiva nacionalna i EU pravila | … |  Potkrijepljeno / rizik | … |
|  Podaci o reguliranom sektoru | NIS2, DORA ili pravila specifična za sektor | … |  Potkrijepljeno / rizik | … |

---
<!-- _class: table table-editable -->

# Izloženost pravnim nalozima · Pravilo 4

| Stranka i pravni poredak | Može li vlada prisiliti? | Neovisni pravni postupak? | Može li se obavijestiti kupca? | Posljedica za dokaz i razinu |
| --- | --- | --- | --- | --- |
| … | Da / ne / nesigurno | Da / ne / nesigurno | Da / ne / neizvjesno | … |
| … | … | … | … | … |
| … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Pravilnik 4 · Obavezni ishod

| Uvjet ili posljedica | Utvrđenje i ID izvora |
| --- | --- |
| Vlada može naložiti pristup ili suradnju | Da / ne / nesigurno: … |
| Njezavisna pravna rasprava je odsutna ili je zabranjeno obavijestiti korisnika | Da / ne / nesigurno: … |
| Ako obje vrijednosti vrijede: Pitanja 2.3, 2.5 i 2.6 se smatraju kao dokazni nivo 0 | Primijenjeno / n.v.t.: … |
| Ako obje vrijednosti vrijede: SOV-2 je maksimalno razina 1 | Primijenjeno / n.v.t.: … |
| Ako je vlasništvo nad pravnim sustavom, onda je i SOV-1 maksimalno razina 1 | Primijenjeno / n.v.t.: … |
| Ostala izloženost | … |
---
<!-- _class: table table-editable -->

# Tehnička ruta · Pravil 5

| Uvjet | Izlaz i ID izvora |
| --- | --- |
| SOV-3 je minimalno razina 3: ključevi isključivo kod klijenta; pružatelj ne vidi čitljivih podataka | … |
| Nema pristupa za upravljanje ili podršku za čitljive podatke | … |
| SOV-5 je minimalno razina 3: ažuriranja unaprijed verificirani i povratno djelujući; lanac izgradnje i potpisivanja je poznat | … |
| SOV-6 je minimalno razina 3: rad kritičkog softvera provjerljiv | … |
| Usluga ne mora obrađivati podatke u čitljivom obliku | Da / Ne |
| Svi uvjeti zajedno ispunjeni | Jedino ako su svi prethodni izlazi pozitivni: … |
| Posljedica | Može podržavati Pravil 0; ne mijenja SOV-2 i ukupnu razinu SEAL-a. |
---
<!-- _class: table table-editable -->

# SAFARI-mjernica

| Kod | Težina | Utvrđeno 0-4 | Dokaz 0-4 | Sudjeljivost prema odabranom standardu | Izvor ciljne zaključka |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | 15% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-2 | 10% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-3 | 10% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-4 | 15% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-5 | 20% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-6 | 15% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-7 | 10% | … | … | Odgovara / jaz / n.v.t. | … |
| SOV-8 | 5% | … | … | Odgovara / jaz / n.v.t. | … |
---
<!-- _class: table table-editable -->

# Ukupna izlaznost

| Komponenta | Izlaz i obrazloženje |
| --- | --- |
| SEAL-ukupna razina · najniži ključni cilj | … |
| Ponavljena ECSF-bodova · Σ (utvrđena razina / 4 × težina) | …% |
| Najveći jazovi | … |
| Kritične ovisnosti | … |
| Željeni razini pod preporukom | … |
| Pravilnost rizika | … |
| Rješavan u smislu internog | … |
| Potreban suglasaj dobavljača | … |
---
<!-- _class: table table-editable -->

#  Indikativna CADA pozicija

| Part | Rezultat i ID izvora |
| --- | --- |
| Relevantnost | Javni sektor / kritična aktivnost / NIS2 sektor / n.a. |
| Ciljna CADA razina | 1 / 2 / 3 / 4 / n.p. |
|  Indikativna dostižna razina | 1 / 2 / 3 / 4 / nijedan |
| Zahtjevi nisu ispunjeni | … |
| Ograničenje dokaza | … |
| Obvezna formulacija | Naznaka na temelju prijedloga; nema prosudbe o sukladnosti. |

---
<!-- _class: table table-editable -->

# Procjena sigurnosti po cilju

| Target |  Dokažite kritična pitanja | Pravni rizik | Vrsta presude |  Formulacija i upozorenja |
| --- | --- | --- | --- | --- |
| SOV-… | Najniža razina: … | Da / ne | Ništa / ograničeno / razumno | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |

---
<!-- _class: table -->

# Formulatorska pomoć za osiguravanje

| Tip | Uvjet | Standardna formulacija |
| --- | --- | --- |
| Bez sudačke odluke | Kritični zahtjev ima dokazni nivo 0 ili 1 | Na temelju raspoloživih dokaza, nije moguće donijeti sud o [cilju] u pogledu [uslužnog] . |
| Ograničena sigurnost | Svi kritični zahtjevi minimalno 2; ne svi minimalno 3 | Na temelju naših aktivnosti, nismo pronašli ništa što bi ukazivalo da [zahtjev] nije točan. Danosmo ograničenu razinu sigurnosti. |
| Razumljiva sigurnost | Svi kritični zahtjevi minimalno 3 | Na temelju naših aktivnosti, smatramo da [zahtjev]. Danosmo razumnu razinu sigurnosti. |
---
<!-- _class: table table-editable -->

#  Nalazi i preporuke

| ID | SOV | Pronalaženje | Utjecaj | Apreporuka | Vlasnik | Term |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | … | … |  Visoko / srednje / nisko | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Kontrola kvalitete i događaji nakon referentnog datuma

| Kontrola |  Ishod i referenca recenzenta |
| --- | --- |
| Scope i tvrdnja uspostavljeni prije izvršenja | … |
| Sva kritična pitanja su pokrivena ili prijavljena kao ograničenja | … |
|  Izvorne reference su sljedive i razine dokaza su sljedive | … |
|  Pravila bodovanja od 0 do 5 su dokazano primijenjena | … |
| Aritmetička i tekstualna dosljednost je provjerena | … |
| Neovisni pregled je dovršen | … |
| Događaji nakon referentnog datuma su procijenjeni | … |
| Izvanredne razlike u mišljenjima su obrađene | … |

---
<!-- _class: table table-editable -->

# Utvrđivanje zahtjeva od strane organizacije

| Utvrđenje | Ispunjavanje |
| --- | --- |
| Ime i funkcija odgovarajuće strane | … |
| Objašnjenje | Zahtjev, opseg i odabrani standardi su potpuno i iskreno utvrđeni. |
| Datum | … |
| Suglasnost | Da / Ne |
---
<!-- _class: table table-editable -->

# Neovisna kvalitetsna revizija

| Revizija | Ispunjavanje |
| --- | --- |
| Ime i funkcija preglednika | … |
| Neovisnost o izvođenju | Da / Ne |
| Revizijski zaključak i eventualni otvoreni točke | … |
| Datum | … |
| Odobrenje za potpis | Da / Ne |
---
<!-- _class: sign-off -->

# Potpis osiguranog mišljenja
---
# Izvori i licence

- Metodologija: SAFARI v0.9 (koncept), Brenno de Winter i Stichting LibreKAT.
- Status: Volonterska metodologija. Minimalni standardi su preporuka; pravila 0 do 5 su obvezujuća za one koji postavljaju SAFARI.
- Izlazište: Europski okriljni okvir, nadopunjeno ISO 27001:2022 i ISAE 3000-osiguranjska struktura.
- Cijela metodologija: https://pawprint.vigilis.online/LibreKAT/Safari
- Ovaj šablonski sadržaj je prilagođen SAFARI i podliježe CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
- Uvijek upotrijebite trenutnu verziju, polaznu točku, profesionalne standarde i lokalne zakonske zahtjeve.
