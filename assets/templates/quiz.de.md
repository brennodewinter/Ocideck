---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktives Quiz
language: de
---

<!-- _class: title -->

# Interaktives Quiz

---

# Über dieses Quiz

- Drei Fragen, drei Frageformate
- Antworten Sie zuerst alleine, dann besprechen wir es gemeinsam
- Hast du es falsch verstanden? Genau so lernen wir

---

<!-- _class: question -->

# Frage 1: Multiple Choice

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

# Erkläre die Antwort

- Warum das die richtige Antwort ist: …
- Häufiges Missverständnis: …

---

<!-- _class: question -->

# Frage 2: wahr oder falsch

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

# Frage 3: mehrere richtige Antworten

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

# Reflexion und Diskussion

- Welche Frage war am schwierigsten – und warum?
- Was werden Sie daraus mitnehmen?

---

<!-- _class: section -->

# Schließung
