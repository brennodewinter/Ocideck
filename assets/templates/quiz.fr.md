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
  "prompt": "Remplacez ceci par votre propre question à choix multiple.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "La bonne réponse",
      "correct": true
    },
    {
      "text": "Une mauvaise réponse",
      "correct": false
    },
    {
      "text": "Une autre mauvaise réponse",
      "correct": false
    },
    {
      "text": "Encore une autre mauvaise réponse",
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
  "prompt": "Remplacez ceci par une affirmation vraie ou fausse.",
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
  "prompt": "Remplacez ceci par une question à plusieurs bonnes réponses.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Bonne réponse 1",
      "correct": true
    },
    {
      "text": "Bonne réponse 2",
      "correct": true
    },
    {
      "text": "Mauvaise réponse 1",
      "correct": false
    },
    {
      "text": "Mauvaise réponse 2",
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
