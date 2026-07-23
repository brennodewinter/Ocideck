---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interactieve quiz
language: nl
---

<!-- _class: title -->

# Interactieve quiz

---

# Uitleg van de quiz

- Drie vragen, drie vraagvormen
- Antwoord eerst zelf, dan bespreken we het samen
- Fout antwoord? Daar leren we juist van

---

<!-- _class: question -->

# Vraag 1: meerkeuze

```question
{
  "kind": "multipleChoice",
  "prompt": "Vervang dit door je eigen meerkeuzevraag.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Het juiste antwoord",
      "correct": true
    },
    {
      "text": "Een fout antwoord",
      "correct": false
    },
    {
      "text": "Nog een fout antwoord",
      "correct": false
    },
    {
      "text": "En nog een fout antwoord",
      "correct": false
    }
  ]
}
```

---

# Uitleg bij het antwoord

- Waarom dit het juiste antwoord is: …
- Veelgemaakte denkfout: …

---

<!-- _class: question -->

# Vraag 2: waar of onwaar

```question
{
  "kind": "trueFalse",
  "prompt": "Vervang dit door een stelling die waar of onwaar is.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Vraag 3: meerdere juiste antwoorden

```question
{
  "kind": "multipleCorrect",
  "prompt": "Vervang dit door een vraag met meerdere juiste antwoorden.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Juist antwoord 1",
      "correct": true
    },
    {
      "text": "Juist antwoord 2",
      "correct": true
    },
    {
      "text": "Fout antwoord 1",
      "correct": false
    },
    {
      "text": "Fout antwoord 2",
      "correct": false
    }
  ]
}
```

---

# Reflectie en nabespreking

- Welke vraag was het lastigst — en waarom?
- Wat neem je hiervan mee?

---

<!-- _class: section -->

# Afsluiting

