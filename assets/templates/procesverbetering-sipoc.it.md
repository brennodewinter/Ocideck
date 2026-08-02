---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Panoramica del processo SIPOC
language: it
---

<!-- _class: title -->

# Panoramica del processo SIPOC
## Fornitore · Input · Processo · Output · Cliente

---

<!-- skip -->

# Ecco come lavori con questo modello

- Utilizza SIPOC per comprendere l'ambito e le dipendenze di un processo, non per registrare ogni azione.
- Utilizzare la guida e la riga di esempio come lista di controllo; inserisci le tue risposte nei **Confini del processo** e nella matrice vuota **SIPOC**.
- Lavorare preferibilmente dal cliente al fornitore, con sostantivi per input e output e verbi per le fasi del processo.
- Solo le diapositive etichettate **Saltate** verranno escluse dalla presentazione e dall'esportazione. Attiva o disattiva **Salta** per le spiegazioni di cui il tuo pubblico potrebbe aver bisogno o meno.

---

# Cosa mappa SIPOC?

- **Fornitore:** fornisce le informazioni o le risorse necessarie al processo.
- **Input:** dati, materiali o altre condizioni richieste dal processo.
- **Processo:** da 4 a 7 attività di alto livello che trasformano l'input.
- **Output:** il prodotto, il servizio o l'informazione prodotta dal processo.
- **Cliente:** il destinatario interno o esterno dell'output.

---

<!-- _class: table table-editable -->

# Stabilire i confini del processo

| Confine | Valore |
| --- | --- |
| Nome del processo |  |
| Punto di partenza |  |
| Punto finale |  |

---

<!-- skip -->

# Lista di controllo: quando i confini sono sufficientemente chiari?

- **Processo:** assegnagli un nome riconoscibile con verbo e oggetto, ad esempio "Registra ordine".
- **Punto di partenza:** nominare un evento osservabile, ad esempio "Richiesta ricevuta".
- **Endpoint:** nominare un risultato dimostrabile, ad esempio “Conferma ordine inviata”.
- Scegli i confini attorno ai quali il team può stipulare accordi significativi.
- Spostare eccezioni e processi adiacenti all'esterno della matrice; scriverli separatamente.

---

<!-- skip -->

# Lista di controllo: completa da destra a sinistra

1. Stabilisci punti di inizio e fine chiari per il processo.
2. Nomina i clienti che dipendono dal risultato.
3. Descrivi gli output che ricevono.
4. Riassumere il processo in 4-7 attività di alto livello.
5. Determinare di quali input hanno bisogno tali attività.
6. Collegare ogni input al fornitore che lo rende disponibile.

---

<!-- skip -->
<!-- _class: table -->

# Lista di controllo: esempio di una riga connessa

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Vendita | Richiesta approvata | Controlla l'ordine → registrati → conferma | Conferma dell'ordine | Richiedente |

- Leggi la riga come una catena: il fornitore fornisce input, il processo lo trasforma in output per il cliente.
- Aggiungi una nuova riga solo se la catena è notevolmente diversa.
- Verificare con le persone coinvolte per garantire che non manchi alcun fornitore, input, output o cliente importante.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# SIPOC o un diagramma di flusso dettagliato?

| Caratteristica | SIPOC | Diagramma di flusso dettagliato |
| --- | --- | --- |
| Scopo | Definire ambito e relazioni | Documentare il lavoro e le decisioni |
| Dettaglio | Da 4 a 7 attività di alto livello | Può contenere decine di passaggi |
| Messa a fuoco | Fornitori, input, output e clienti | Sequenza, passaggi di consegne e punti decisionali |
| Utilizzo | Inizio di uno sforzo di miglioramento | Esecuzione e analisi dei guasti |
