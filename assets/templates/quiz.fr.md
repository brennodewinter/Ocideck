---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Quiz interactif
language: fr
---

<!-- _class: title -->

# Quiz interactif

---

# À propos de ce quiz

- Trois questions, trois formats de questions
- Répondez d'abord par vous-même, puis nous en discuterons ensemble
- Vous vous êtes trompé ? C'est exactement comme ça qu'on apprend

---

<!-- _class: question -->

# Question 1 : choix multiples

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

# Expliquer la réponse

- Pourquoi c’est la bonne réponse : …
- Idée fausse courante : …

---

<!-- _class: question -->

# Question 2 : vrai ou faux

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

# Question 3 : plusieurs bonnes réponses

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

# Réflexion et discussion

- Quelle question a été la plus difficile – et pourquoi ?
- Qu’allez-vous en retenir ?

---

<!-- _class: section -->

# Clôture
