---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktywny quiz
language: pl
---

<!-- _class: title -->

# Interaktywny quiz

---

# O tym quizie

- Trzy pytania, trzy formaty pytań
- Najpierw odpowiedz samodzielnie, a potem omówimy to wspólnie
- Źle zrozumiałeś? Właśnie tak się uczymy

---

<!-- _class: question -->

# Pytanie 1: wielokrotny wybór

```question
{
  "kind": "multipleChoice",
  "prompt": "Zastąp to własnym pytaniem wielokrotnego wyboru.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Prawidłowa odpowiedź",
      "correct": true
    },
    {
      "text": "Błędna odpowiedź",
      "correct": false
    },
    {
      "text": "Kolejna błędna odpowiedź",
      "correct": false
    },
    {
      "text": "I jeszcze jedna błędna odpowiedź",
      "correct": false
    }
  ]
}
```

---

# Wyjaśnienie odpowiedzi

- Dlaczego to jest prawidłowa odpowiedź:…
- Często spotykany błędny pogląd:…

---

<!-- _class: question -->

# Pytanie 2: prawda czy fałsz

```question
{
  "kind": "trueFalse",
  "prompt": "Zastąp to stwierdzeniem, które jest prawdziwe lub fałszywe.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Pytanie 3: wiele poprawnych odpowiedzi

```question
{
  "kind": "multipleCorrect",
  "prompt": "Zastąp to pytaniem z kilkoma prawidłowymi odpowiedziami.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Prawidłowa odpowiedź 1",
      "correct": true
    },
    {
      "text": "Prawidłowa odpowiedź 2",
      "correct": true
    },
    {
      "text": "Błędna odpowiedź 1",
      "correct": false
    },
    {
      "text": "Błędna odpowiedź 2",
      "correct": false
    }
  ]
}
```

---

# Refleksja i dyskusja

- Które pytanie było najtrudniejsze i dlaczego?
- Co z tego wyniesiesz?

---

<!-- _class: section -->

# Zamknięcie
