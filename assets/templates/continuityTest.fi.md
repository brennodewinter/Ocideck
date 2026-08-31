---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Business continuity / DR-testi
language: fi
---

<!-- _class: title -->

# Business continuity / DR-testi

---

# Testi skenaario

- Skenaario: … (esim. palvelinkeskuksen katkos, kiristysohjelma)
- Oletus etukäteen:…
- Testityyppi: pöytä / osittainen / täysi

---

# Tavoitteet ja menestyskriteerit

- Testin tavoite:…
- Onnistumiskriteeri 1:…
- Onnistumiskriteeri 2:…

---

<!-- _class: table table-editable -->

# Kriittiset prosessit

| Prosessi | Prioriteetti | Riippuu |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO yleiskatsaus

| Prosessi tai järjestelmä | RTO | RPO | Tapasi? |
| --- | --- | --- | --- |
| … | … | … | Kyllä / ei |
| … | … | … | … |

---

<!-- _class: timeline -->

# Testaa aikajanaa

- T+0 :: Testin aloitus :: Skenaario julkistettu.
- T+… :: Failover aloitettu
- T+… :: Palautus varmistettu
- T+… :: Testin loppu

---

<!-- _class: table table-editable -->

# Havainnot

| Löytäminen | Vakavuus | Komponentti |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Poikkeamat ja estoaineet

- Poikkeama ohjekirjasta:…
- Esto testin aikana:…
- Käytetty ratkaisu:…

---

# Parannuspisteet
<!-- ocideck_list_style: checklist -->

- [ ] Päivitä pelikirja kohtaan:…
- [ ] Säädä teknisiä asetuksia:…
- [ ] Varaa harjoitus- tai harjoitusaikataulu:…

---

# Go / no-go palautusominaisuus
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kriittiset prosessit palautuivat RTO:ssa
- [ ] Tietojen menetys pysyi RPO:n sisällä
- [ ] Pelikirja osoittautui käyttökelpoiseksi
- [ ] Tuomio: palautumiskyky osoitettu
