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

# Explicarea răspunsului

- De ce acesta este răspunsul corect:...
- Concepție greșită comună:...

---

<!-- _class: question -->

# Întrebarea 2: adevărat sau fals

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

# Întrebarea 3: mai multe răspunsuri corecte

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

# Reflecție și discuție

- Care întrebare a fost cea mai grea - și de ce?
- Ce vei scoate din asta?

---

<!-- _class: section -->

# Închidere
