---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Questionário interativo
language: pt
---

<!-- _class: title -->

# Questionário interativo

---

# Sobre este teste

- Três perguntas, três formatos de perguntas
- Responda sozinho primeiro, depois discutiremos isso juntos
- Entendeu errado? É exatamente assim que aprendemos

---

<!-- _class: question -->

# Questão 1: múltipla escolha

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

# Explicando a resposta

- Por que esta é a resposta correta:…
- Equívoco comum:…

---

<!-- _class: question -->

# Pergunta 2: verdadeiro ou falso

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

# Pergunta 3: múltiplas respostas corretas

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

# Reflexão e discussão

- Qual pergunta foi mais difícil – e por quê?
- O que você vai tirar disso?

---

<!-- _class: section -->

# Fechando
