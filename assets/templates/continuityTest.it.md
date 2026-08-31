---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Business continuity / test DR
language: it
---

<!-- _class: title -->

# Business continuity / test DR

---

# Scenario di prova

- Scenario: … (ad esempio interruzione del data center, ransomware)
- Presupposto in anticipo: …
- Tipo di test: tabletop/parziale/completo

---

# Obiettivi e criteri di successo

- Obiettivo del test: …
- Criterio di successo 1: …
- Criterio di successo 2: …

---

<!-- _class: table table-editable -->

# Processi critici

| Processo | Priorità | Dipende da |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Panoramica RTO/RPO

| Processo o sistema | RTO | RPO | Incontrato? |
| --- | --- | --- | --- |
| … | … | … | Sì/no |
| … | … | … | … |

---

<!-- _class: timeline -->

# Cronologia della prova

- T+0 :: Inizio test :: Scenario annunciato.
- T+… :: Failover avviato
- T+… :: Recupero verificato
- T+… :: Fine del test

---

<!-- _class: table table-editable -->

# Risultati

| Trovare | Gravità | Componente |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Deviazioni e bloccanti

- Deviazione dal playbook: …
- Bloccante durante il test: …
- Soluzione utilizzata: …

---

# Punti di miglioramento
<!-- ocideck_list_style: checklist -->

- [ ] Aggiorna il playbook sul punto: …
- [ ] Modificare la configurazione tecnica:...
- [ ] Pianificare l'allenamento o l'esercizio:...

---

# Funzionalità di ripristino “go/no-go”.
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Processi critici recuperati all'interno di RTO
- [ ] La perdita di dati è rimasta entro l'RPO
- [ ] Il Playbook si è rivelato utilizzabile
- [ ] Verdetto: capacità di recupero dimostrata
