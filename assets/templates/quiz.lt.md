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
  "prompt": "Pakeiskite tai savo klausimu su keliais atsakymų variantais.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Teisingas atsakymas",
      "correct": true
    },
    {
      "text": "Neteisingas atsakymas",
      "correct": false
    },
    {
      "text": "Dar vienas neteisingas atsakymas",
      "correct": false
    },
    {
      "text": "Ir dar vienas neteisingas atsakymas",
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
  "prompt": "Pakeiskite tai teiginiu, kuris yra teisingas arba klaidingas.",
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
  "prompt": "Pakeiskite tai klausimu, kuris turi kelis teisingus atsakymus.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Teisingas atsakymas 1",
      "correct": true
    },
    {
      "text": "Teisingas atsakymas 2",
      "correct": true
    },
    {
      "text": "Neteisingas atsakymas 1",
      "correct": false
    },
    {
      "text": "Neteisingas atsakymas 2",
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
