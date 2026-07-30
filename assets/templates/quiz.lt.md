---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktyvi viktorina
language: lt
---

<!-- _class: title -->

# Interaktyvi viktorina

---

# Apie šią viktoriną

- Trys klausimai, trys klausimų formatai
- Pirmiausia atsakykite patys, tada aptarsime kartu
- Supratote neteisingai? Būtent taip mes mokomės

---

<!-- _class: question -->

# 1 klausimas: keli pasirinkimai

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

# Atsakymo paaiškinimas

- Kodėl tai teisingas atsakymas:…
- Dažnas klaidingas supratimas:…

---

<!-- _class: question -->

# 2 klausimas: tiesa ar klaidinga

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

# 3 klausimas: keli teisingi atsakymai

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

# Apmąstymas ir diskusija

- Kuris klausimas buvo sunkiausias – ir kodėl?
- Ką tu iš to atimsi?

---

<!-- _class: section -->

# Uždarymas
