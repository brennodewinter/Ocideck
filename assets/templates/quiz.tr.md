---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: İnteraktif sınav
language: tr
---

<!-- _class: title -->

# İnteraktif sınav

---

# Bu sınav hakkında

- Üç soru, üç soru formatı
- Önce kendi başınıza cevaplayın, sonra birlikte tartışırız
- Yanlış mı anladın? Aynen böyle öğreniyoruz

---

<!-- _class: question -->

# Soru 1: çoktan seçmeli

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

# Cevabı açıklıyorum

- Neden doğru cevap bu:…
- Yaygın yanılgı:…

---

<!-- _class: question -->

# Soru 2: doğru mu yanlış mı

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

# Soru 3: Birden fazla doğru cevap

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

# Düşünme ve tartışma

- Hangi soru en zordu ve neden?
- Bundan ne çıkaracaksınız?

---

<!-- _class: section -->

# Kapanış
