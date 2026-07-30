---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktivní kvíz
language: cs
---

<!-- _class: title -->

# Interaktivní kvíz

---

# O tomto kvízu

- Tři otázky, tři formáty otázek
- Nejprve si odpovězte sami, pak to probereme společně
- Máš to špatně? Přesně tak se učíme

---

<!-- _class: question -->

# Otázka 1: výběr z více možností

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

# Vysvětlení odpovědi

- Proč je tato odpověď správná: …
- Častá mylná představa:…

---

<!-- _class: question -->

# Otázka 2: pravda nebo nepravda

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

# Otázka 3: více správných odpovědí

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

# Reflexe a diskuse

- Která otázka byla nejtěžší – a proč?
- Co si z toho odnesete?

---

<!-- _class: section -->

# Zavírání
