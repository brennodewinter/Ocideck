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
  "prompt": "Nahraďte to vlastní otázkou s výběrem odpovědí.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Správná odpověď",
      "correct": true
    },
    {
      "text": "Špatná odpověď",
      "correct": false
    },
    {
      "text": "Další špatná odpověď",
      "correct": false
    },
    {
      "text": "A ještě jedna špatná odpověď",
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
  "prompt": "Nahraďte to tvrzením, které je pravdivé nebo nepravdivé.",
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
  "prompt": "Nahraďte to otázkou s více správnými odpověďmi.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Správná odpověď 1",
      "correct": true
    },
    {
      "text": "Správná odpověď 2",
      "correct": true
    },
    {
      "text": "Špatná odpověď 1",
      "correct": false
    },
    {
      "text": "Špatná odpověď 2",
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
