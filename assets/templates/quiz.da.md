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
  "prompt": "Erstat dette med dit eget multiple choice-spørgsmål.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Det rigtige svar",
      "correct": true
    },
    {
      "text": "Et forkert svar",
      "correct": false
    },
    {
      "text": "Endnu et forkert svar",
      "correct": false
    },
    {
      "text": "Og endnu et forkert svar",
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
  "prompt": "Erstat dette med et udsagn, der er sandt eller falsk.",
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
  "prompt": "Erstat dette med et spørgsmål med flere rigtige svar.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Rigtigt svar 1",
      "correct": true
    },
    {
      "text": "Rigtigt svar 2",
      "correct": true
    },
    {
      "text": "Forkert svar 1",
      "correct": false
    },
    {
      "text": "Forkert svar 2",
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
