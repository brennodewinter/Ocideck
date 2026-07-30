---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktívny kvíz
language: sk
---

<!-- _class: title -->

# Interaktívny kvíz

---

# O tomto kvíze

- Tri otázky, tri formáty otázok
- Najprv si odpovedzte sami, potom to spolu prediskutujeme
- Máš to zle? Presne tak sa učíme

---

<!-- _class: question -->

# Otázka 1: výber z viacerých možností

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

# Vysvetlenie odpovede

- Prečo je táto odpoveď správna: …
- Bežná mylná predstava:…

---

<!-- _class: question -->

# Otázka 2: pravda alebo nepravda

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

# Otázka 3: viacero správnych odpovedí

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

# Reflexia a diskusia

- Ktorá otázka bola najťažšia – a prečo?
- Čo si z toho odnesiete?

---

<!-- _class: section -->

# Zatváranie
