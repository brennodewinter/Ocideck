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

# A válasz magyarázata

- Miért ez a helyes válasz:…
- Gyakori tévhit:…

---

<!-- _class: question -->

# 2. kérdés: igaz vagy hamis

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

# 3. kérdés: több helyes válasz

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

# Reflexió és vita

- Melyik kérdés volt a legnehezebb – és miért?
- Mit veszel el ebből?

---

<!-- _class: section -->

# Bezárás
