---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Interaktiivne viktoriin
language: et
---

<!-- _class: title -->

# Interaktiivne viktoriin

---

# Selle viktoriini kohta

- Kolm küsimust, kolm küsimuste vormingut
- Esmalt vastake ise, siis arutame seda koos
- Said valesti aru? Täpselt nii me õpimegi

---

<!-- _class: question -->

# 1. küsimus: valikvastustega

```question
{
  "kind": "multipleChoice",
  "prompt": "Asenda see oma valikvastustega küsimusega.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Õige vastus",
      "correct": true
    },
    {
      "text": "Vale vastus",
      "correct": false
    },
    {
      "text": "Veel üks vale vastus",
      "correct": false
    },
    {
      "text": "Ja veel üks vale vastus",
      "correct": false
    }
  ]
}
```

---

# Vastuse selgitamine

- Miks see on õige vastus:…
- Levinud eksiarvamus:…

---

<!-- _class: question -->

# 2. küsimus: õige või vale

```question
{
  "kind": "trueFalse",
  "prompt": "Asenda see väitega, mis on tõene või väär.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# 3. küsimus: mitu õiget vastust

```question
{
  "kind": "multipleCorrect",
  "prompt": "Asenda see küsimusega, millel on mitu õiget vastust.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Õige vastus 1",
      "correct": true
    },
    {
      "text": "Õige vastus 2",
      "correct": true
    },
    {
      "text": "Vale vastus 1",
      "correct": false
    },
    {
      "text": "Vale vastus 2",
      "correct": false
    }
  ]
}
```

---

# Mõtisklus ja arutelu

- Milline küsimus oli kõige raskem – ja miks?
- Mida sa sellest ära võtad?

---

<!-- _class: section -->

# Sulgemine
