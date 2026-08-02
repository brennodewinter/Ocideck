---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Miglioramento dei processi: progetto DMADV"
language: it
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Miglioramento del processo: progetto DMADV

---

<!-- skip -->

# Ecco come lavori con questo modello

- Utilizza DMADV per un processo nuovo o radicalmente riprogettato e scegli un risultato misurabile per il cliente (**Y-01**).
- Utilizza le domande su ciascuna diapositiva della guida come una lista di controllo; quindi aggiungi diapositive regolari per le tue risposte.
- Sostituisci la spiegazione nella carta e nell'albero CTQ con le informazioni sul progetto, completa il SIPOC e rendi i requisiti verificabili prima della progettazione.
- Le diapositive della guida non vengono presentate o esportate. Se vuoi mostrarne una, disattiva **Salta** per quella diapositiva.

---

<!-- _class: section -->

# Definire

---

<!-- skip -->

# Lista di controllo: cosa registri durante la definizione?

- Quale cliente o utente ha un bisogno insoddisfatto?
- Perché è necessaria una nuova progettazione e perché migliorare il processo esistente non è sufficiente?
- Quale risultato dovrebbe fornire la progettazione (**Y-01**) e in quale ambito?
- Chi decide requisiti, scelte progettuali e rilascio?
- Quali pianificazione, precondizioni e criteri di successo si applicano?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Carta del progetto

## Problema o opportunità

Descrivere il bisogno insoddisfatto, il gruppo target e il motivo dimostrabile.

## Obiettivo

Formulare il risultato desiderato in modo misurabile e limitato nel tempo.

## Ambito

Nota il punto iniziale, il punto finale, i punti di contatto e ciò che non rientra nel disegno.

## Squadra

Nome del cliente, del proprietario del progetto, degli utenti e degli esperti richiesti.

## Cronologia

Registra le tappe fondamentali, i punti decisionali e l'implementazione prevista.

## Criteri di successo
Quando il progetto soddisfa in modo dimostrabile le esigenze del cliente?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Requisiti misurabili del cliente (albero CTQ)

- Di quale risultato ha bisogno il cliente? — **Y-01**
  - Tradurre tale esigenza in requisito misurabile 1
  - Tradurre tale esigenza in requisito misurabile 2

---

<!-- skip -->

# Lista di controllo: come si completa il SIPOC?

- Iniziamo dal **Cliente**: chi utilizza il nuovo risultato del processo?
- Quindi identificare l'**Output** richiesto e i 4-7 passaggi di **Processo** previsti.
- Annotare l'**Input** richiesto e il **Fornitore** che rende disponibile ciascun input.
- Mantenere una panoramica generale; i dettagli progettuali seguiranno in seguito.
- Controlla se i confini selezionati corrispondono a charter e Y-01.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: section -->

# Misurare

---

<!-- skip -->

# Lista di controllo: cosa registri quando misuri?

- Quali esigenze dei clienti sono state tradotte in requisiti e priorità misurabili?
- Quali sono il valore target, il limite inferiore o superiore, l'unità e il metodo di misurazione di Y-01?
- Quali casi d’uso, volumi ed eccezioni dovrebbe essere in grado di gestire il progetto?
- Quali risultati o alternative esistenti usi come riferimento?
- Come verificherete oggettivamente se ciascun requisito è stato soddisfatto?

---

<!-- _class: section -->

# Analizzare

---

<!-- skip -->

# Lista di controllo: cosa registri durante l'analisi?

- Quali funzioni deve svolgere il processo per soddisfare i requisiti?
- Quali relazioni e compromessi esistono tra desideri dei clienti, rischi e caratteristiche di progettazione?
- Quali ipotesi devono ancora essere esplorate o testate?
- Quali modalità di errore e dipendenze sono più importanti?
- Quali criteri minimi di progettazione deve soddisfare ogni soluzione?

---

<!-- _class: section -->

# Progetto

---

<!-- skip -->

# Lista di controllo: cosa registri in Design?

- Quali varianti progettuali sono state prese in considerazione e in base a quali criteri sono state confrontate?
- Come si presenta il flusso del processo scelto, inclusi ruoli, sistemi e trasferimenti?
- In che modo la progettazione previene o controlla le principali modalità di guasto?
- Cosa insegna un prototipo o un test sul funzionamento e sulla facilità d'uso?
- Quale variante va a verifica, con quali punti aperti?

---

<!-- _class: section -->

# Verificare

---

<!-- skip -->

# Lista di controllo: cosa registri durante la verifica?

- Quale test dimostra per ciascun requisito che il progetto funziona in condizioni realistiche?
- Quali risultati sono stati raggiunti e quali deviazioni rimangono?
- Cosa pensano gli utenti e i proprietari dei processi del funzionamento e della fattibilità?
- Quali controlli, istruzioni e misurazioni sono necessari dopo la messa in servizio?
- Chi rilascia il disegno e sulla base di quali evidenze?
