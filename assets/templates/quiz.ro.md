---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Test interactiv
language: ro
---

<!-- _class: title -->

# Test interactiv

---

# Despre acest test

- Trei întrebări, trei formate de întrebări
- Răspundeți mai întâi singur, apoi discutăm împreună
- Ați înțeles greșit? Exact așa învățăm

---

<!-- _class: question -->

# Întrebarea 1: alegere multiplă

```question
{
  "kind": "multipleChoice",
  "prompt": "Înlocuiește aceasta cu propria ta întrebare cu variante multiple.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Răspunsul corect",
      "correct": true
    },
    {
      "text": "Un răspuns greșit",
      "correct": false
    },
    {
      "text": "Alt răspuns greșit",
      "correct": false
    },
    {
      "text": "Și încă un răspuns greșit",
      "correct": false
    }
  ]
}
```

---

# Explicarea răspunsului

- De ce acesta este răspunsul corect:...
- Concepție greșită comună:...

---

<!-- _class: question -->

# Întrebarea 2: adevărat sau fals

```question
{
  "kind": "trueFalse",
  "prompt": "Înlocuiește aceasta cu o afirmație adevărată sau falsă.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Întrebarea 3: mai multe răspunsuri corecte

```question
{
  "kind": "multipleCorrect",
  "prompt": "Înlocuiește aceasta cu o întrebare cu mai multe răspunsuri corecte.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Răspuns corect 1",
      "correct": true
    },
    {
      "text": "Răspuns corect 2",
      "correct": true
    },
    {
      "text": "Răspuns greșit 1",
      "correct": false
    },
    {
      "text": "Răspuns greșit 2",
      "correct": false
    }
  ]
}
```

---

# Reflecție și discuție

- Care întrebare a fost cea mai grea - și de ce?
- Ce vei scoate din asta?

---

<!-- _class: section -->

# Închidere
