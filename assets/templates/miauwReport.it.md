---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Rapporto pentest MIAUW
language: it
---

<!-- _class: title -->

# Rapporto pentest MIAUW

---

<!-- _class: section -->

# 1. Generale

---

# Gestione dei documenti

- Consegna digitale di questo report, con hash di verifica (SHA-256).
- Reporter e certificazione richiesta (OSCP/OSEP/OSCE/OSWE/eWPTX).
- Versione del report e data di pubblicazione.
- Riservatezza e classificazione TLP.
- Lista di distribuzione: chi riceve questo rapporto.

---

<!-- _class: sign-off -->

# Reporting veritiero


---

<!-- _class: section -->

# 2. Piano di approccio

---

# Compito e ambito

- Aspirazione e motivo dell'indagine.
- Obiettivo e domande di ricerca.
- Proprietà, giurisdizione e approvazione dell'ambito.
- Linguaggio di segnalazione.
- Indennizzo e condizioni legali.

---

<!-- _class: scope-matrix -->

# Ambito e standard

| Oggetto | Digitare | Norma | Stato | Nota | C | Io | A |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  | Rete | WSTG |  |  |  |  |  |

---

<!-- _class: section -->

# 3. Esecuzione

---

# Attività di esecuzione

- Assumere la violazione come punto di partenza.
- Qualificazione con CVSS 4.0 (punteggio + stringa vettoriale).
- Prove: hash del materiale probatorio (SHA1/SHA-256).
- Convalida dei risultati della scansione (nessuna fiducia cieca nello scanner).
- Documentare i percorsi di accesso utilizzati.

---

<!-- _class: section -->

# 4. Reporting

---

<!-- _class: findings-summary -->

# Riepilogo esecutivo

| Gravità | Conte |
| --- | --- |
| Critico | 0 |
| Alto | 0 |
| Medio | 0 |
| Basso | 0 |
| Nessuno | 0 |
| Risolto | 0 |

---

<!-- _class: timeline -->

# Cronologia dell'indagine

- Assunzione :: Kickoff :: Ambito e accordi stabiliti.
- Test :: Esecuzione :: Periodo di test dell'indagine.
- Rapporto :: Consegna :: Bozza e rapporto finale.

---

<!-- _class: finding -->

# F-01 · Esempio di ricerca

**Scope object:** `<scope-object>`

## Descrizione

Describe here, factually and technically, what the security issue is.

## Conferma (riproduzione)

Describe, in a reproducible way (with evidence), how the finding was established.

## Possibile impatto

Describe the possible technical and business impact.

## Raccomandazione

Describe the concrete, achievable mitigation.

---

<!-- _class: checklist -->

# Lista di controllo per standard

| ID | Prova | Stato | Trovare | Nota |
| --- | --- | --- | --- | --- |
|  |  |  | — |  |
|  |  |  | — |  |

---

# Appendici

- Glossario.
- Strumenti utilizzati.
- Documenti e file ricevuti (con SHA1).
- Conti utilizzati.
- Risultati della scansione.
- Materiale probatorio (con SHA1).
- Liste di controllo per standard.
- Oggetti irraggiungibili.

