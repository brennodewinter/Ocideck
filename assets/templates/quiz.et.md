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

# Vastuse selgitamine

- Miks see on õige vastus:…
- Levinud eksiarvamus:…

---

<!-- _class: question -->

# 2. küsimus: õige või vale

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

# 3. küsimus: mitu õiget vastust

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

# Mõtisklus ja arutelu

- Milline küsimus oli kõige raskem – ja miks?
- Mida sa sellest ära võtad?

---

<!-- _class: section -->

# Sulgemine
