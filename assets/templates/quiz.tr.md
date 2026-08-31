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
  "prompt": "Bunu kendi çoktan seçmeli sorunuzla değiştirin.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Doğru cevap",
      "correct": true
    },
    {
      "text": "Yanlış bir cevap",
      "correct": false
    },
    {
      "text": "Başka bir yanlış cevap",
      "correct": false
    },
    {
      "text": "Bir yanlış cevap daha",
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
  "prompt": "Bunu doğru ya da yanlış olan bir ifadeyle değiştirin.",
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
  "prompt": "Bunu birden fazla doğru cevabı olan bir soruyla değiştirin.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Doğru cevap 1",
      "correct": true
    },
    {
      "text": "Doğru cevap 2",
      "correct": true
    },
    {
      "text": "Yanlış cevap 1",
      "correct": false
    },
    {
      "text": "Yanlış cevap 2",
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
