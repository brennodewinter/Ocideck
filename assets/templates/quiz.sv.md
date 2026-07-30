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

# Förklara svaret

- Varför detta är rätt svar:...
- Vanlig missuppfattning: …

---

<!-- _class: question -->

# Fråga 2: sant eller falskt

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

# Fråga 3: flera korrekta svar

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

# Reflektion och diskussion

- Vilken fråga var svårast – och varför?
- Vad tar du med dig från detta?

---

<!-- _class: section -->

# Stängning
