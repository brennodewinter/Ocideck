---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interactive quiz
language: la
---

<!-- _class: title -->

# Interactive quiz

---

# De hoc quiz

- Tres quaestiones, tres interrogationes
- Responde primum de tuo, deinde de ea simul disseremus
- Obtinuit iniuriam? Id prorsus quomodo discimus

---

<!-- _class: question -->

# Quaestio I: multiplex electio

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

# Explicans responsum

- Quare hoc est rectam responsum: …
- Communis deceptio: ...

---

<!-- _class: question -->

# Quaestio II: verum vel falsum

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

# Quaestio III, multa recta responsa

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

# Meditatio et disceptatio

- Quae quaestio durissima fuit, et quare?
- Quid inde auferes?

---

<!-- _class: section -->

# Claudendo
