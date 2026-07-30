---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Интерактивна викторина
language: bg
---

<!-- _class: title -->

# Интерактивна викторина

---

# Относно този тест

- Три въпроса, три формата на въпроси
- Първо отговорете сами, а след това ще го обсъдим заедно
- Сбъркахте ли? Точно така се учим

---

<!-- _class: question -->

# Въпрос 1: множествен избор

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

# Обяснение на отговора

- Защо това е правилният отговор: …
- Често срещано погрешно схващане: …

---

<!-- _class: question -->

# Въпрос 2: вярно или невярно

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

# Въпрос 3: няколко верни отговора

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

# Рефлексия и дискусия

- Кой въпрос беше най-труден - и защо?
- Какво ще вземете от това?

---

<!-- _class: section -->

# Затваряне
