---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: İş sürekliliği / DR testi
language: tr
---

<!-- _class: title -->

# İş sürekliliği / DR testi

---

# Test senaryosu

- Senaryo: … (ör. veri merkezi kesintisi, fidye yazılımı)
- Önceden varsayım:…
- Test türü: masa üstü / kısmi / tam

---

# Hedefler ve başarı kriterleri

- Testin amacı:…
- Başarı kriteri 1:…
- Başarı kriteri 2: …

---

<!-- _class: table table-editable -->

# Kritik süreçler

| İşlem | Öncelik | bağlıdır |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO'ya genel bakış

| Süreç veya sistem | RTO | RPO | Tanıştınız mı? |
| --- | --- | --- | --- |
| … | … | … | Evet / hayır |
| … | … | … | … |

---

<!-- _class: timeline -->

# Test zaman çizelgesi

- T+0 :: Test başlangıcı :: Senaryo açıklandı.
- T+… :: Yük devretme başladı
- T+… :: Kurtarma doğrulandı
- T+… :: Test sonu

---

<!-- _class: table table-editable -->

# Bulgular

| Bulma | Şiddet | Bileşen |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Sapmalar ve engelleyiciler

- Oyun kitabından sapma:…
- Test sırasında engelleyici:…
- Kullanılan geçici çözüm:…

---

# İyileştirme noktaları
<!-- ocideck_list_style: checklist -->

- [ ] Başucu kitabını güncelleyin:…
- [ ] Teknik kurulumu ayarlayın: …
- [ ] Eğitim veya egzersiz planlayın:…

---

# Devam eden/devam etmeyen kurtarma özelliği
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] RTO içerisinde kurtarılan kritik süreçler
- [ ] Veri kaybı RPO dahilinde kaldı
- [ ] Başucu Kitabının kullanışlı olduğu kanıtlandı
- [ ] Karar: kurtarma yeteneği kanıtlandı
