---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Süreç iyileştirme: DMADV projesi"
language: tr
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Süreç iyileştirme: DMADV projesi

---

<!-- skip -->

# Bu şablonla bu şekilde çalışırsınız

- Yeni veya temelde yeniden tasarlanmış bir süreç için DMADV'yi kullanın ve ölçülebilir bir müşteri sonucu seçin (**Y-01**).
- Her kılavuz slaytındaki soruları bir kontrol listesi olarak kullanın; daha sonra yanıtlarınız için düzenli slaytlar ekleyin.
- Şarttaki ve CTQ ağacındaki açıklamayı proje bilgilerinizle değiştirin, SIPOC'u doldurun ve tasarımdan önce gereksinimleri test edilebilir hale getirin.
- Yardım slaytları sunulmuyor veya dışa aktarılmıyor. Bir slayt göstermek istiyorsanız o slayt için **Atla** seçeneğini kapatın.

---

<!-- _class: section -->

# Tanımlamak

---

<!-- skip -->

# Kontrol Listesi — Tanımlarken neyi kaydediyorsunuz?

- Hangi müşteri veya kullanıcının karşılanmamış ihtiyacı var?
- Yeni bir tasarım neden gerekli ve mevcut sürecin iyileştirilmesi neden yeterli değil?
- Tasarım hangi sonucu sağlamalı (**Y-01**) ve hangi kapsamda?
- Gereksinimlere, tasarım tercihlerine ve sürüme kim karar veriyor?
- Hangi planlama, ön koşullar ve başarı kriterleri geçerlidir?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Proje Şartı

## Sorun veya fırsat

Karşılanmayan ihtiyacı, hedef grubu ve kanıtlanabilir nedeni açıklayın.

## Amaç

İstenilen sonucu ölçülebilir ve zamana bağlı bir şekilde formüle edin.

## Kapsam

Başlangıç ​​noktasını, bitiş noktasını, temas noktalarını ve tasarımın dışında kalanları not edin.

## Takım

Müşterinin, tasarım sahibinin, kullanıcıların ve gerekli uzmanların adlarını belirtin.

## Zaman çizelgesi

Kilometre taşlarını, karar kapılarını ve amaçlanan dağıtımı kaydedin.

## Başarı kriterleri
Tasarım ne zaman müşteri ihtiyaçlarını kanıtlanabilir şekilde karşılıyor?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Ölçülebilir müşteri gereksinimleri (CTQ ağacı)

- Müşterinin hangi sonuca ihtiyacı var? — **Y-01**
  - Bu ihtiyacı ölçülebilir gereksinime dönüştürün 1
  - Bu ihtiyacı ölçülebilir gereksinime dönüştürün 2

---

<!-- skip -->

# Kontrol Listesi — SIPOC'u nasıl tamamlarsınız?

- **Müşteri** ile başlayın: yeni süreç sonucunu kim kullanıyor?
- Daha sonra gerekli **Çıktı** ve amaçlanan 4 ila 7 arası **Süreç** adımlarını tanımlayın.
- Gerekli **Giriş**'i ve her girişi kullanılabilir kılan **Tedarikçiyi** not edin.
- Genel bir bakış tutun; tasarım detayları daha sonra gelecek.
- Seçilen sınırların charter ve Y-01'e uygun olup olmadığını kontrol edin.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: section -->

# Ölçüm

---

<!-- skip -->

# Kontrol Listesi — Ölçerken neyi kaydediyorsunuz?

- Hangi müşteri ihtiyaçları ölçülebilir gereksinimlere ve önceliklere dönüştürüldü?
- Y-01'in hedef değeri, alt ve üst limiti, birimi ve ölçüm yöntemi nedir?
- Tasarım hangi kullanım durumlarını, hacimleri ve istisnaları ele almalıdır?
- Referans olarak hangi mevcut başarıları veya alternatifleri kullanıyorsunuz?
- Her bir gereksinimin karşılanıp karşılanmadığını objektif olarak nasıl test edeceksiniz?

---

<!-- _class: section -->

# Analiz et

---

<!-- skip -->

# Kontrol Listesi — Analiz ederken neyi kaydedersiniz?

- Süreç gereksinimleri karşılamak için hangi işlevleri yerine getirmelidir?
- Müşteri istekleri, riskler ve tasarım özellikleri arasında ne gibi ilişkiler ve ödünleşimler var?
- Hangi varsayımların hâlâ araştırılması veya test edilmesi gerekiyor?
- Hangi hata modları ve bağımlılıklar en önemlidir?
- Her çözümün hangi minimum tasarım kriterlerini karşılaması gerekir?

---

<!-- _class: section -->

# Tasarım

---

<!-- skip -->

# Kontrol Listesi — Tasarımda neyi kaydediyorsunuz?

- Hangi tasarım çeşitleri dikkate alındı ​​ve hangi kriterlere göre karşılaştırıldı?
- Roller, sistemler ve transferler de dahil olmak üzere seçilen süreç akışı neye benziyor?
- Tasarım ana arıza türlerini nasıl önlüyor veya kontrol ediyor?
- Bir prototip veya test, çalıştırma ve kullanım kolaylığı hakkında ne öğretir?
- Hangi değişken hangi açık noktalarla doğrulamaya gidiyor?

---

<!-- _class: section -->

# Doğrulamak

---

<!-- skip -->

# Kontrol Listesi — Doğrulama sırasında neyi kaydedersiniz?

- Hangi test her bir gereksinim için tasarımın gerçekçi koşullar altında çalıştığını kanıtlar?
- Hangi sonuçlara ulaşıldı ve hangi sapmalar kaldı?
- Kullanıcılar ve süreç sahipleri operasyon ve fizibilite hakkında ne düşünüyor?
- Devreye alma sonrasında hangi kontrol, talimat ve ölçüm gereklidir?
- Tasarımı kim, hangi kanıtlara dayanarak yayınlıyor?
