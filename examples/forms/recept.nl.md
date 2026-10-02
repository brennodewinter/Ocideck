<!-- form id=recept version=1 lang=nl controller="Voorbeeld-redactie" contact="redactie@example.org" retain-unused="6 maanden na sluiting" overview="naam,gerecht" -->
# Receptinzending (voorbeeld)

Dit is een voorbeeldformulier om OciDeck mee uit te proberen. Vul het in, voeg een foto toe en sla de inzending op als zip.

<!-- notice -->
Je gegevens worden alleen gebruikt voor dit voorbeeld. De redactie bewaart ze tot 6 maanden na sluiting; ingezonden bijdragen die niet in het boek komen worden daarna verwijderd.
<!-- /notice -->

## A. Over jou

<!-- field id=naam type=text required max-chars=60 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=mail type=text required pattern=email -->
**E-mailadres**
<!-- answer -->
<!-- /field id=mail -->

<!-- field id=bio type=prose words=..80 -->
**Korte bio**
> Een paar zinnen over jezelf. Mag leeg.
<!-- answer -->
<!-- /field id=bio -->

## B. Het gerecht

<!-- field id=gerecht type=text required -->
**Naam van het gerecht**
<!-- answer -->
<!-- /field id=gerecht -->

<!-- field id=moeilijkheid type=choice options="Makkelijk|Gemiddeld|Gevorderd" required -->
**Hoe moeilijk is het?**
<!-- answer -->
<!-- /field id=moeilijkheid -->

<!-- field id=dieet type=multichoice options="Vegetarisch|Veganistisch|Halal|Glutenvrij" other -->
**Voor welk dieet is het geschikt?**
<!-- answer -->
<!-- /field id=dieet -->

<!-- field id=ingredienten type=table columns="Ingrediënt|Hoeveelheid" rows=1.. required -->
**Ingrediënten**
<!-- answer -->
<!-- /field id=ingredienten -->

<!-- field id=bereiding type=list ordered items=2..20 required -->
**Bereiding**
> Eén stap per punt.
<!-- answer -->
<!-- /field id=bereiding -->

## C. Het verhaal en de foto

<!-- field id=verhaal type=prose required words=50..150 -->
**Het verhaal achter het gerecht**
> Van wie heb je het geleerd? Wanneer maak je het? Waarom is het belangrijk voor je?
<!-- answer -->
<!-- /field id=verhaal -->

<!-- field id=datum type=date -->
**Wanneer maakte je het voor het eerst?**
<!-- answer -->
<!-- /field id=datum -->

<!-- field id=foto type=image count=0..3 min-width=1200 alt credit -->
**Foto's van het gerecht**
> Liefst een foto die je zelf hebt gemaakt. Locatiegegevens worden eruit gehaald.
<!-- answer -->
<!-- /field id=foto -->

## D. Toestemming

<!-- field id=akkoord type=consent required -->
Ik ga ermee akkoord dat mijn recept, verhaal en foto's worden gepubliceerd.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->

Bedankt voor je inzending!
