---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Интерактивен куиз
language: bg
---

<!-- _class: title -->

# Интерактивен куиз

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
  "prompt": "Заменете това със собствен въпрос с избор от няколко отговора.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Правилният отговор",
      "correct": true
    },
    {
      "text": "Грешен отговор",
      "correct": false
    },
    {
      "text": "Още един грешен отговор",
      "correct": false
    },
    {
      "text": "И още един грешен отговор",
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
  "prompt": "Заменете това с твърдение, което е вярно или невярно.",
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
  "prompt": "Заменете това с въпрос с няколко верни отговора.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Верен отговор 1",
      "correct": true
    },
    {
      "text": "Верен отговор 2",
      "correct": true
    },
    {
      "text": "Грешен отговор 1",
      "correct": false
    },
    {
      "text": "Грешен отговор 2",
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
