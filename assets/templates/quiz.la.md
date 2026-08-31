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
  "prompt": "Substitue hoc tua quaestione multiplicis electionis.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Responsum rectum",
      "correct": true
    },
    {
      "text": "Responsum falsum",
      "correct": false
    },
    {
      "text": "Aliud responsum falsum",
      "correct": false
    },
    {
      "text": "Adhuc aliud responsum falsum",
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
  "prompt": "Substitue hoc enuntiatione quae vera aut falsa est.",
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
  "prompt": "Substitue hoc quaestione cum pluribus responsis rectis.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Responsum rectum 1",
      "correct": true
    },
    {
      "text": "Responsum rectum 2",
      "correct": true
    },
    {
      "text": "Responsum falsum 1",
      "correct": false
    },
    {
      "text": "Responsum falsum 2",
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
