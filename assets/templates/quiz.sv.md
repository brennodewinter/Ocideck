---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktiv frågesport
language: sv
---

<!-- _class: title -->

# Interaktiv frågesport

---

# Om detta frågesport

- Tre frågor, tre frågeformat
- Svara först på egen hand, sedan diskuterar vi det tillsammans
- Förstod du fel? Det är precis så vi lär oss

---

<!-- _class: question -->

# Fråga 1: Flerval

```question
{
  "kind": "multipleChoice",
  "prompt": "Ersätt detta med din egen flervalsfråga.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Det rätta svaret",
      "correct": true
    },
    {
      "text": "Ett felaktigt svar",
      "correct": false
    },
    {
      "text": "Ännu ett felaktigt svar",
      "correct": false
    },
    {
      "text": "Och ännu ett felaktigt svar",
      "correct": false
    }
  ]
}
```

---

# Förklara svaret

- Varför detta är rätt svar:...
- Vanlig missuppfattning: …

---

<!-- _class: question -->

# Fråga 2: sant eller falskt

```question
{
  "kind": "trueFalse",
  "prompt": "Ersätt detta med ett påstående som är sant eller falskt.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Fråga 3: flera korrekta svar

```question
{
  "kind": "multipleCorrect",
  "prompt": "Ersätt detta med en fråga som har flera rätta svar.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Rätt svar 1",
      "correct": true
    },
    {
      "text": "Rätt svar 2",
      "correct": true
    },
    {
      "text": "Fel svar 1",
      "correct": false
    },
    {
      "text": "Fel svar 2",
      "correct": false
    }
  ]
}
```

---

# Reflektion och diskussion

- Vilken fråga var svårast – och varför?
- Vad tar du med dig från detta?

---

<!-- _class: section -->

# Stängning
