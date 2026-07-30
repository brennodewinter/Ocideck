---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktīva viktorīna
language: lv
---

<!-- _class: title -->

# Interaktīva viktorīna

---

# Par šo viktorīnu

- Trīs jautājumi, trīs jautājumu formāti
- Vispirms atbildiet pats, tad apspriedīsim to kopā
- Vai sapratāt nepareizi? Tieši tā mēs mācāmies

---

<!-- _class: question -->

# 1. jautājums: vairākas izvēles iespējas

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

# Atbildes skaidrošana

- Kāpēc šī ir pareizā atbilde:…
- Izplatīts nepareizs priekšstats:…

---

<!-- _class: question -->

# 2. jautājums: patiess vai nepatiess

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

# 3. jautājums: vairākas pareizas atbildes

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

# Pārdomas un diskusija

- Kurš jautājums bija grūtākais - un kāpēc?
- Ko tu no šī atņemsi?

---

<!-- _class: section -->

# Noslēgšana
