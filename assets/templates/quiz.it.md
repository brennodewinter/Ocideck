---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Quiz interattivo
language: it
---

<!-- _class: title -->

# Quiz interattivo

---

# A proposito di questo quiz

- Tre domande, tre formati di domanda
- Prima rispondi da solo, poi ne discutiamo insieme
- Hai sbagliato? È esattamente così che impariamo

---

<!-- _class: question -->

# Domanda 1: scelta multipla

```question
{
  "kind": "multipleChoice",
  "prompt": "Sostituisci questo con la tua domanda a scelta multipla.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "La risposta corretta",
      "correct": true
    },
    {
      "text": "Una risposta sbagliata",
      "correct": false
    },
    {
      "text": "Un'altra risposta sbagliata",
      "correct": false
    },
    {
      "text": "Ancora un'altra risposta sbagliata",
      "correct": false
    }
  ]
}
```

---

# Spiegare la risposta

- Perché questa è la risposta corretta:…
- Idea sbagliata comune:...

---

<!-- _class: question -->

# Domanda 2: vero o falso

```question
{
  "kind": "trueFalse",
  "prompt": "Sostituisci questo con un'affermazione vera o falsa.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Domanda 3: più risposte corrette

```question
{
  "kind": "multipleCorrect",
  "prompt": "Sostituisci questo con una domanda con più risposte corrette.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Risposta corretta 1",
      "correct": true
    },
    {
      "text": "Risposta corretta 2",
      "correct": true
    },
    {
      "text": "Risposta sbagliata 1",
      "correct": false
    },
    {
      "text": "Risposta sbagliata 2",
      "correct": false
    }
  ]
}
```

---

# Riflessione e discussione

- Quale domanda è stata la più difficile e perché?
- Cosa porterai via da questo?

---

<!-- _class: section -->

# Chiusura
