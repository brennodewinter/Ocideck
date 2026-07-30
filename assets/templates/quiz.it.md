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
  "prompt": "Replace this with your own multiple-choice question.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "The correct answer",
      "correct": true
    },
    {
      "text": "A wrong answer",
      "correct": false
    },
    {
      "text": "Another wrong answer",
      "correct": false
    },
    {
      "text": "Yet another wrong answer",
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
  "prompt": "Replace this with a statement that is true or false.",
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
  "prompt": "Replace this with a question that has multiple correct answers.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Correct answer 1",
      "correct": true
    },
    {
      "text": "Correct answer 2",
      "correct": true
    },
    {
      "text": "Wrong answer 1",
      "correct": false
    },
    {
      "text": "Wrong answer 2",
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
