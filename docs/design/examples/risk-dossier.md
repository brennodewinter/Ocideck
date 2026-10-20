# Risicodossier drukinstallatie

Voorbeeldbestand bij `docs/design/RISK_FORMAT.md`. Alles hieronder is gewone
Markdown: de `<!-- ocideck:* -->`-regels zijn commentaar dat elke lezer mag
negeren; de tabellen zijn de enige inhoud die er toe doet.

## Beoordelingsschaal

<!-- ocideck:scale v1 id=sod-1-10 version=1 -->
| Waarde | Label | Betekenis |
|--------|-------|-----------|
| 1 | Verwaarloosbaar | Geen gevolg van betekenis |
| 5 | Matig | Herstelbaar binnen een dienst |
| 10 | Catastrofaal | Letsel of totaal productieverlies |

## Risicoregister (FMEA)

<!-- ocideck:risks v1 id=hoofd method=fmea scale=sod-1-10 rev=3 next=4 cols=id,step,failure,effect,s_b,cause,o_b,control,d_b,measures,s_n,o_n,d_n,netto_basis,netto_date,netto_by -->
| ID | Processtap | Faalwijze | Effect | S b | Oorzaak | O b | Beheersing | D b | Maatregelen | S n | O n | D n | Netto-basis | Netto-datum | Netto-door |
|----|------------|-----------|--------|-----|---------|-----|------------|-----|-------------|-----|-----|-----|-------------|-------------|------------|
| R-001 | Druk meten | Sensor valt uit | Geen drukbeeld | 7 | Kabelbreuk | 4 | Visuele check | 5 | M-001 | 7 | 2 | 3 | M-001 getoetst, redundantie werkt | 2026-10-15 | J. Jansen |
| R-002 | Druk meten | Afwijking display | Verkeerde beslissing | 5 | Kalibratiedrift | 3 | Jaarlijkse kalibratie | 6 | M-002 | | | | | | |
| R-003 | Ontlasten | Klep blijft hangen | Overdruk | 9 | Vuil in geleiding | 2 | Geen | 8 | M-003 | | | | | | |

## Maatregelen

<!-- ocideck:measures v1 id=mat rev=2 next=4 cols=id,type,description,owner,status,evidence,test_date,expires,risks -->
| ID | Type | Beschrijving | Eigenaar | Status | Bewijs | Toetsdatum | Vervalt | Risico's |
|----|------|--------------|----------|--------|--------|------------|---------|----------|
| M-001 | preventief | Redundante druksensor plaatsen | J. Jansen | working | testrapport-12 | 2026-10-10 | 2027-10-10 | R-001 |
| M-002 | detective | Halfjaarlijkse kalibratie ipv jaarlijks | P. Smit | implemented | werkorder-881 | | | R-002 |
| M-003 | preventive | Ontlastklep reinigen en testen | P. Smit | planned | | | | R-003 |

## Netto-weergave (gekoppeld)

<!-- ocideck:view v1 source=hoofd projection=netto gen=3 cols=id,failure,s_n,o_n,d_n -->
| ID | Faalwijze | S n | O n | D n |
|----|-----------|-----|-----|-----|
| R-001 | Sensor valt uit | 7 | 2 | 3 |
| R-002 | Afwijking display | | | |
| R-003 | Klep blijft hangen | | | |

## Overzicht (gekoppeld)

<!-- ocideck:view v1 source=hoofd projection=overview gen=3 cols=id,failure,s_b,o_b,d_b,s_n,o_n,d_n -->
| ID | Faalwijze | S b | O b | D b | S n | O n | D n |
|----|-----------|-----|-----|-----|-----|-----|-----|
| R-001 | Sensor valt uit | 7 | 4 | 5 | 7 | 2 | 3 |
| R-002 | Afwijking display | 5 | 3 | 6 | | | |
| R-003 | Klep blijft hangen | 9 | 2 | 8 | | | |

## Bowtie

<!-- ocideck:bowtie v1 id=bt1 rev=1 cols=path,side,role,element,measure,status,owner -->
| Pad | Zijde | Rol | Element | Maatregel | Status | Eigenaar |
|-----|-------|-----|---------|-----------|--------|----------|
| P-1 | links | threat | Vuil in klepgeleiding | | | |
| P-1 | links | barrier-preventive | Ontlastklep reinigen en testen | M-003 | planned | P. Smit |
| P-1 | links | escalation | Inspectiecapaciteit te kort | | | |
| P-1 | top | top-event | Overdruk in leiding | | | |
| P-1 | rechts | barrier-mitigating | Noodafsluiter | M-001 | working | J. Jansen |
| P-1 | rechts | consequence | Breuk en mediumvrijkomst | | | |
