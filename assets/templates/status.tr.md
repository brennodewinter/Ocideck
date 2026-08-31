---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Durum brifingi
language: tr
---

<!-- _class: title -->

# Durum brifingi

---

# Durum özeti

- Genel durum: yolunda / dikkat edilmesi gerekiyor / kritik
- Önceki brifingden bu yana önemli gelişme:…
- Önümüzdeki döneme ilişkin görünüm:…

---

<!-- _class: cockpit -->

# Durum kontrol paneli

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Bütçe kullanımı",
      "unit": "%",
      "min": 0.0,
      "max": 100.0,
      "greenFrom": 0.0,
      "greenTo": 60.0,
      "redFrom": 85.0,
      "value": 58.0
    },
    {
      "type": "thermometer",
      "label": "Risk düzeyi",
      "unit": "/10",
      "min": 0.0,
      "max": 10.0,
      "greenFrom": 0.0,
      "greenTo": 3.0,
      "redFrom": 7.0,
      "value": 4.5
    },
    {
      "type": "voltmeter",
      "label": "Plana güven",
      "unit": "%",
      "min": 0.0,
      "max": 100.0,
      "greenFrom": 75.0,
      "greenTo": 100.0,
      "redFrom": 50.0,
      "value": 80.0
    },
    {
      "type": "climbDescent",
      "label": "Açık maddelerin eğilimi",
      "min": -10.0,
      "max": 10.0,
      "neutralFrom": -2.0,
      "neutralTo": 2.0,
      "value": 3.0
    }
  ]
}
```

---

<!-- _class: table -->

# İş akışı başına ilerleme

| İş akışı | Durum | Açıklama |
| --- | --- | --- |
| İş Akışı A | 🟢 Yolda | Planlandığı gibi ilerliyor |
| İş Akışı B | 🟠 Dikkat | Karar bekleniyor |
| İş Akışı C | 🔴 Kritik | Kapasite eksikliği |

---

# Riskler ve engelleyiciler

- Risk 1: … (olasılık: yüksek, etki: büyük)
- Risk 2: … (olasılık: düşük, etki: büyük)
- Engelleyici: … — yardıma ihtiyaç var…

---

# Kararlar ve eylemler

- Gereken karar:…
- Eylem: … (sahip, tarih)
- Eylem: … (sahip, tarih)
