---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Kontinwità tan-negozju / test DR
language: mt
---

<!-- _class: title -->

# Kontinwità tan-negozju / test DR

---

# Xenarju tat-test

- Xenarju: … (eż. qtugħ taċ-ċentru tad-dejta, ransomware)
- Assunzjoni minn qabel: …
- Tip tat-test: mejda / parzjali / sħiħa

---

# Għanijiet u kriterji ta' suċċess

- Għan tat-test: …
- Kriterju ta' suċċess 1: …
- Kriterju ta' suċċess 2: …

---

<!-- _class: table table-editable -->

# Proċessi kritiċi

| Proċess | Prijorità | Jiddependi fuq |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Ħarsa ġenerali RTO / RPO

| Proċess jew sistema | RTO | RPO | Iltaqa? |
| --- | --- | --- | --- |
| … | … | … | Iva / le |
| … | … | … | … |

---

<!-- _class: timeline -->

# Kronoloġija tat-test

- T+0 :: Bidu tat-test :: Xenarju mħabbar.
- T+... :: Beda l-failover
- T+... :: L-irkupru ivverifikat
- T+... :: Tmiem tat-test

---

<!-- _class: table table-editable -->

# Sejbiet

| Tfittxija | Severità | Komponent |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Devjazzjonijiet u imblokkaturi

- Devjazzjoni mill-playbook:...
- Imblokkatur waqt it-test: …
- Soluzzjoni li tintuża:…

---

# Punti ta' titjib
<!-- ocideck_list_style: checklist -->

- [ ] Aġġorna l-playbook dwar il-punt:...
- [ ] Aġġusta s-setup tekniku:...
- [ ] Skeda taħriġ jew eżerċizzju:…

---

# Kapaċità ta 'rkupru Go / no-go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Proċessi kritiċi rkuprati fi ħdan RTO
- [ ] It-telf tad-dejta baqa' fi ħdan l-RPO
- [ ] Playbook wera li jista' jintuża
- [ ] Verdett: kapaċità ta' rkupru murija
