---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktiv quiz
language: da
---

<!-- _class: title -->

# Interaktiv quiz

---

# Om denne quiz

- Tre spørgsmål, tre spørgsmålsformater
- Svar først på egen hånd, så diskuterer vi det sammen
- Forstod det forkert? Det er præcis sådan, vi lærer

---

<!-- _class: question -->

# Spørgsmål 1: multiple choice

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

# Forklarer svaret

- Hvorfor dette er det rigtige svar: …
- Almindelig misforståelse: …

---

<!-- _class: question -->

# Spørgsmål 2: sandt eller falsk

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

# Spørgsmål 3: flere rigtige svar

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

# Refleksion og diskussion

- Hvilket spørgsmål var sværest - og hvorfor?
- Hvad vil du tage væk fra dette?

---

<!-- _class: section -->

# Lukning
