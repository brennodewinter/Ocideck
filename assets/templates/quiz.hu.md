---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktív kvíz
language: hu
---

<!-- _class: title -->

# Interaktív kvíz

---

# Erről a kvízről

- Három kérdés, három kérdésformátum
- Először válaszoljon egyedül, aztán megbeszéljük együtt
- Rosszul csináltad? Pontosan így tanulunk

---

<!-- _class: question -->

# 1. kérdés: feleletválasztós

```question
{
  "kind": "multipleChoice",
  "prompt": "Cseréld ezt saját feleletválasztós kérdésedre.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "A helyes válasz",
      "correct": true
    },
    {
      "text": "Egy rossz válasz",
      "correct": false
    },
    {
      "text": "Még egy rossz válasz",
      "correct": false
    },
    {
      "text": "És még egy rossz válasz",
      "correct": false
    }
  ]
}
```

---

# A válasz magyarázata

- Miért ez a helyes válasz:…
- Gyakori tévhit:…

---

<!-- _class: question -->

# 2. kérdés: igaz vagy hamis

```question
{
  "kind": "trueFalse",
  "prompt": "Cseréld ezt egy állításra, amely igaz vagy hamis.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# 3. kérdés: több helyes válasz

```question
{
  "kind": "multipleCorrect",
  "prompt": "Cseréld ezt egy kérdésre, amelynek több helyes válasza van.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Helyes válasz 1",
      "correct": true
    },
    {
      "text": "Helyes válasz 2",
      "correct": true
    },
    {
      "text": "Rossz válasz 1",
      "correct": false
    },
    {
      "text": "Rossz válasz 2",
      "correct": false
    }
  ]
}
```

---

# Reflexió és vita

- Melyik kérdés volt a legnehezebb – és miért?
- Mit veszel el ebből?

---

<!-- _class: section -->

# Bezárás
