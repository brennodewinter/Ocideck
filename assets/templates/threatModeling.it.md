---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sessione di modellazione delle minacce
language: it
---

<!-- _class: title -->

# Sessione di modellazione delle minacce
## Sistema · Data · Facilitatore · Partecipanti

---

# Ambito e obiettivo

- Quale sistema o componente stiamo modellando oggi?
- Cosa è esplicitamente fuori campo:...
- Presupposti con cui stiamo lavorando: …
- Risultato: minacce ponderate con mitigazioni e un proprietario

---

<!-- _class: table table-editable -->

# Mappatura del sistema

| Elemento | Gentile | Note |
| --- | --- | --- |
| … | Componente | … |
| … | Flusso di dati | … |
| … | Partito esterno | … |

---

# Confini di fiducia

- Dove passano i dati da attendibili a non attendibili?
- Quali confini vediamo: rete, processo, utente, catena di fornitura?
- Dove avvengono l'autenticazione e la convalida dell'input?
- Disegna ogni confine sullo schizzo del sistema: …

---

<!-- _class: table -->

# Riferimento STRIDE

| Categoria | Significato |
| --- | --- |
| Spoofing | Fingere di essere un altro utente o servizio |
| Manomissione | Modifica non autorizzata di dati o codice |
| Ripudio | Negare che un'azione sia mai avvenuta |
| Divulgazione delle informazioni | Le informazioni raggiungono coloro a cui non è consentito vederle |
| Negazione del servizio | Rendere il sistema inutilizzabile o irraggiungibile |
| Elevazione dei privilegi | Ottenere più privilegi di quelli concessi |

---

<!-- _class: table table-editable -->

# Raccogliere minacce

| Minaccia | Categoria STRIDE | Componente | Rischio |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Definizione delle priorità: probabilità × impatto

- Probabilità: quanto è probabile l'abuso (basso, medio, alto)?
- Impatto: quanti danni se accade?
- Rischio = probabilità × impatto; l'alto-alto va per primo
- Nel dubbio: scegli la stima più alta e nota il motivo

---

<!-- _class: table table-editable -->

# Mitigazioni e azioni

| Mitigazione | Proprietario | Stato |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Ciò che accettiamo consapevolmente

- Quali minacce non affrontiamo deliberatamente: …
- Perché ciò è giustificato (probabilità, costo, contesto): …
- A chi appartiene questa decisione: Ruolo
- Quando lo rivisiteremo:...

---

# Sessione completata
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Ambito e ipotesi registrati
- [ ] Mappatura componenti, flussi dati e soggetti esterni
- [ ] Tracciati i confini della fiducia
- [ ] Hanno partecipato tutte e sei le categorie STRIDE
- [ ] Minacce classificate in base alla probabilità × all'impatto
- [ ] Mitigazioni assegnate a un proprietario
- [ ] Rischi accettati registrati e posseduti
