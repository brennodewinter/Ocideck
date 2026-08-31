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
  "prompt": "Ersetzen Sie dies durch Ihre eigene Multiple-Choice-Frage.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Die richtige Antwort",
      "correct": true
    },
    {
      "text": "Eine falsche Antwort",
      "correct": false
    },
    {
      "text": "Noch eine falsche Antwort",
      "correct": false
    },
    {
      "text": "Und noch eine falsche Antwort",
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
  "prompt": "Ersetzen Sie dies durch eine Aussage, die wahr oder falsch ist.",
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
  "prompt": "Ersetzen Sie dies durch eine Frage mit mehreren richtigen Antworten.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Richtige Antwort 1",
      "correct": true
    },
    {
      "text": "Richtige Antwort 2",
      "correct": true
    },
    {
      "text": "Falsche Antwort 1",
      "correct": false
    },
    {
      "text": "Falsche Antwort 2",
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
