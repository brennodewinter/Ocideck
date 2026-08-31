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
  "prompt": "Ganti ini dengan pertanyaan pilihan ganda Anda sendiri.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Jawaban yang benar",
      "correct": true
    },
    {
      "text": "Jawaban yang salah",
      "correct": false
    },
    {
      "text": "Jawaban salah lainnya",
      "correct": false
    },
    {
      "text": "Satu lagi jawaban yang salah",
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
  "prompt": "Ganti ini dengan pernyataan yang benar atau salah.",
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
  "prompt": "Ganti ini dengan pertanyaan yang memiliki beberapa jawaban benar.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Jawaban benar 1",
      "correct": true
    },
    {
      "text": "Jawaban benar 2",
      "correct": true
    },
    {
      "text": "Jawaban salah 1",
      "correct": false
    },
    {
      "text": "Jawaban salah 2",
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
