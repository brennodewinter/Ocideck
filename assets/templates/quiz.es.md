---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Quiz interactivo
language: es
---

<!-- _class: title -->

# Quiz interactivo

---

# Sobre este quiz

- Tres preguntas, tres formatos de pregunta
- Responde primero por tu cuenta, luego lo discutimos juntos
- ¿Te equivocaste? Así es exactamente como se aprende

---

<!-- _class: question -->

# Pregunta 1: opción múltiple

```question
{
  "kind": "multipleChoice",
  "prompt": "Sustituye esto por tu propia pregunta de opción múltiple.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "La respuesta correcta",
      "correct": true
    },
    {
      "text": "Una respuesta incorrecta",
      "correct": false
    },
    {
      "text": "Otra respuesta incorrecta",
      "correct": false
    },
    {
      "text": "Una respuesta más incorrecta",
      "correct": false
    }
  ]
}
```

---

# Explicación de la respuesta

- Por qué esta es la respuesta correcta: …
- Error común: …

---

<!-- _class: question -->

# Pregunta 2: verdadero o falso

```question
{
  "kind": "trueFalse",
  "prompt": "Sustituye esto por una afirmación que sea verdadera o falsa.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Pregunta 3: varias respuestas correctas

```question
{
  "kind": "multipleCorrect",
  "prompt": "Sustituye esto por una pregunta que tenga varias respuestas correctas.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Respuesta correcta 1",
      "correct": true
    },
    {
      "text": "Respuesta correcta 2",
      "correct": true
    },
    {
      "text": "Respuesta incorrecta 1",
      "correct": false
    },
    {
      "text": "Respuesta incorrecta 2",
      "correct": false
    }
  ]
}
```

---

# Reflexión y discusión

- ¿Qué pregunta fue la más difícil — y por qué?
- ¿Qué te llevas de esto?

---

<!-- _class: section -->

# Cierre
