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
  "prompt": "Aizstājiet to ar savu jautājumu ar atbilžu variantiem.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Pareizā atbilde",
      "correct": true
    },
    {
      "text": "Nepareiza atbilde",
      "correct": false
    },
    {
      "text": "Vēl viena nepareiza atbilde",
      "correct": false
    },
    {
      "text": "Un vēl viena nepareiza atbilde",
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
  "prompt": "Aizstājiet to ar apgalvojumu, kas ir patiess vai aplams.",
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
  "prompt": "Aizstājiet to ar jautājumu, kuram ir vairākas pareizas atbildes.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Pareiza atbilde 1",
      "correct": true
    },
    {
      "text": "Pareiza atbilde 2",
      "correct": true
    },
    {
      "text": "Nepareiza atbilde 1",
      "correct": false
    },
    {
      "text": "Nepareiza atbilde 2",
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
