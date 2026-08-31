---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Teknik açıklayıcı
language: tr
---

<!-- _class: title -->

# Teknik açıklayıcı

---

# Bağlam ve amaç

- Bu bileşen ne işe yarar:…
- Bu açıklama kimin için:…
- Sonunda ne anlayacaksınız: …

---

### Mimari genel bakış

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Bileşenler ve sorumluluklar

| Bileşen | Sorumluluk | Mal sahibi |
| --- | --- | --- |
| Müşteri | Sunum ve girdi | A Takımı |
| API'si | Doğrulama ve yönlendirme | Takım B |
| Hizmet | İş mantığı | Takım B |
| Veritabanı | Depolamak | Takım C |

---

# Veri akışı veya süreç akışı
<!-- ocideck_list_style: numbered -->

1. Kullanıcı bir istek gönderir
2. API isteği doğrular ve yönlendirir
3. Servis isteği işler ve saklar
4. Sonuç kullanıcıya döner

---

<!-- _class: code -->

# Kod örneği

```dart
/// Bu örneği açıklamak istediğiniz kodla değiştirin.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Riskler ve ödünleşimler

- Seçilen çözüm: … — çünkü: …
- Reddedilen alternatif: … — çünkü: …
- Bilinen risk:…

---

# Uygulama kontrol listesi
<!-- ocideck_list_style: checklist -->

- [ ] Tasarım ekiple tartışıldı
- [ ] Yazılan testler
- [ ] Dokümantasyon güncellendi
- [ ] İzleme kurulumu
