---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktiivinen tietovisa
language: fi
---

<!-- _class: title -->

# Interaktiivinen tietovisa

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
  "prompt": "Korvaa tämä omalla monivalintakysymykselläsi.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Oikea vastaus",
      "correct": true
    },
    {
      "text": "Väärä vastaus",
      "correct": false
    },
    {
      "text": "Toinen väärä vastaus",
      "correct": false
    },
    {
      "text": "Vielä yksi väärä vastaus",
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
  "prompt": "Korvaa tämä väittämällä, joka on tosi tai epätosi.",
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
  "prompt": "Korvaa tämä kysymyksellä, jossa on useita oikeita vastauksia.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Oikea vastaus 1",
      "correct": true
    },
    {
      "text": "Oikea vastaus 2",
      "correct": true
    },
    {
      "text": "Väärä vastaus 1",
      "correct": false
    },
    {
      "text": "Väärä vastaus 2",
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
