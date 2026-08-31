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
  "prompt": "Nahraďte to vlastnou otázkou s výberom odpovedí.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Správna odpoveď",
      "correct": true
    },
    {
      "text": "Nesprávna odpoveď",
      "correct": false
    },
    {
      "text": "Ďalšia nesprávna odpoveď",
      "correct": false
    },
    {
      "text": "A ešte jedna nesprávna odpoveď",
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
  "prompt": "Nahraďte to tvrdením, ktoré je pravdivé alebo nepravdivé.",
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
  "prompt": "Nahraďte to otázkou s viacerými správnymi odpoveďami.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Správna odpoveď 1",
      "correct": true
    },
    {
      "text": "Správna odpoveď 2",
      "correct": true
    },
    {
      "text": "Nesprávna odpoveď 1",
      "correct": false
    },
    {
      "text": "Nesprávna odpoveď 2",
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
