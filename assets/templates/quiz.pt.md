---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Quiz interativo
language: pt
---

<!-- _class: title -->

# Quiz interativo

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
  "prompt": "Substitua isto pela sua própria pergunta de escolha múltipla.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "A resposta certa",
      "correct": true
    },
    {
      "text": "Uma resposta errada",
      "correct": false
    },
    {
      "text": "Outra resposta errada",
      "correct": false
    },
    {
      "text": "E ainda outra resposta errada",
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
  "prompt": "Substitua isto por uma afirmação verdadeira ou falsa.",
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
  "prompt": "Substitua isto por uma pergunta com várias respostas certas.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Resposta certa 1",
      "correct": true
    },
    {
      "text": "Resposta certa 2",
      "correct": true
    },
    {
      "text": "Resposta errada 1",
      "correct": false
    },
    {
      "text": "Resposta errada 2",
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
