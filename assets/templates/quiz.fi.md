---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktiivinen tietokilpailu
language: fi
---

<!-- _class: title -->

# Interaktiivinen tietokilpailu

---

# Tietoja tästä tietokilpailusta

- Kolme kysymystä, kolme kysymysmuotoa
- Vastaa ensin itse, sitten keskustellaan yhdessä
- Ymmärsitkö väärin? Juuri näin me opimme

---

<!-- _class: question -->

# Kysymys 1: Monivalinta

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

# Vastauksen selittäminen

- Miksi tämä on oikea vastaus:…
- Yleinen väärinkäsitys:…

---

<!-- _class: question -->

# Kysymys 2: totta vai tarua

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

# Kysymys 3: useita oikeita vastauksia

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

# Pohdintaa ja keskustelua

- Mikä kysymys oli vaikein – ja miksi?
- Mitä sinä otat tästä pois?

---

<!-- _class: section -->

# Sulkeminen
