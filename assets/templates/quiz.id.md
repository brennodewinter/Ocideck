---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Kuis interaktif
language: id
---

<!-- _class: title -->

# Kuis interaktif

---

# Tentang kuis ini

- Tiga pertanyaan, tiga format pertanyaan
- Jawab sendiri dulu, baru kita diskusikan bersama
- Apakah salah? Itulah cara kita belajar

---

<!-- _class: question -->

# Pertanyaan 1: pilihan ganda

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

# Menjelaskan jawabannya

- Mengapa ini adalah jawaban yang benar: …
- Kesalahpahaman umum:…

---

<!-- _class: question -->

# Pertanyaan 2: benar atau salah

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

# Pertanyaan 3: beberapa jawaban benar

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

# Refleksi dan diskusi

- Pertanyaan mana yang paling sulit — dan mengapa?
- Apa yang bisa Anda ambil dari ini?

---

<!-- _class: section -->

# Penutupan
