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

# Wyjaśnienie odpowiedzi

- Dlaczego to jest prawidłowa odpowiedź:…
- Często spotykany błędny pogląd:…

---

<!-- _class: question -->

# Pytanie 2: prawda czy fałsz

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

# Pytanie 3: wiele poprawnych odpowiedzi

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

# Refleksja i dyskusja

- Które pytanie było najtrudniejsze i dlaczego?
- Co z tego wyniesiesz?

---

<!-- _class: section -->

# Zamknięcie
