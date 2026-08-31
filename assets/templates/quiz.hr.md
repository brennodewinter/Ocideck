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
  "prompt": "Zamijenite ovo vlastitim pitanjem s višestrukim izborom.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Točan odgovor",
      "correct": true
    },
    {
      "text": "Netočan odgovor",
      "correct": false
    },
    {
      "text": "Još jedan netočan odgovor",
      "correct": false
    },
    {
      "text": "I još jedan netočan odgovor",
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
  "prompt": "Zamijenite ovo tvrdnjom koja je točna ili netočna.",
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
  "prompt": "Zamijenite ovo pitanjem s više točnih odgovora.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Točan odgovor 1",
      "correct": true
    },
    {
      "text": "Točan odgovor 2",
      "correct": true
    },
    {
      "text": "Netočan odgovor 1",
      "correct": false
    },
    {
      "text": "Netočan odgovor 2",
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
