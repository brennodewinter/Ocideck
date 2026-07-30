---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktivni kviz
language: hr
---

<!-- _class: title -->

# Interaktivni kviz

---

# O ovom kvizu

- Tri pitanja, tri formata pitanja
- Prvo odgovorite sami, a onda ćemo zajedno razgovarati
- Jeste li krivo shvatili? Upravo tako učimo

---

<!-- _class: question -->

# Pitanje 1: višestruki izbor

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

# Obrazlažući odgovor

- Zašto je ovo točan odgovor: …
- Uobičajena zabluda: …

---

<!-- _class: question -->

# Pitanje 2: točno ili netočno

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

# Pitanje 3: više točnih odgovora

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

# Refleksija i rasprava

- Koje je pitanje bilo najteže — i zašto?
- Što ćeš oduzeti od ovoga?

---

<!-- _class: section -->

# Zatvaranje
