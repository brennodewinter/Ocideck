---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tehdit modelleme oturumu
language: tr
---

<!-- _class: title -->

# Tehdit modelleme oturumu
## Sistem · Tarih · Kolaylaştırıcı · Katılımcılar

---

# Kapsam ve amaç

- Bugün hangi sistemi veya bileşeni modelliyoruz?
- Açıkça kapsam dışı olan:…
- Üzerinde çalıştığımız varsayımlar:…
- Sonuç: hafifletici önlemler ve bir sahiple birlikte ağırlıklı tehditler

---

<!-- _class: table table-editable -->

# Sistemin haritalanması

| Öğe | Tür | Notlar |
| --- | --- | --- |
| … | Bileşen | … |
| … | Veri akışı | … |
| … | Harici taraf | … |

---

# Güven sınırları

- Veriler güvenilir durumdan güvenilmez duruma nerede geçiyor?
- Hangi sınırları görüyoruz: ağ, süreç, kullanıcı, tedarik zinciri?
- Kimlik doğrulama ve giriş doğrulama nerede gerçekleşir?
- Sistem çizimindeki tüm sınırları çizin: …

---

<!-- _class: table -->

# ADIM referansı

| Kategori | Anlam |
| --- | --- |
| Sahtecilik | Başka bir kullanıcı veya hizmetmiş gibi davranmak |
| Kurcalama | Veri veya kodda izinsiz değişiklik yapılması |
| Reddetme | Bir eylemin gerçekleştiğini inkar etmek |
| Bilgi ifşası | Görmesine izin verilmeyen kişilere ulaşan bilgiler |
| Hizmet reddi | Sistemi kullanılamaz veya erişilemez hale getirmek |
| Ayrıcalığın yükselmesi | Verilenden daha fazla ayrıcalık kazanmak |

---

<!-- _class: table table-editable -->

# Tehdit toplama

| Tehdit | ADIM kategorisi | Bileşen | Risk |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Önceliklendirme: olasılık × etki

- Olasılık: Kötüye kullanım ne kadar olasıdır (düşük, orta, yüksek)?
- Etki: Olursa ne kadar hasar olur?
- Risk = olasılık × etki; önce yüksek-yüksek gider
- Şüpheniz varsa: daha yüksek tahmini seçin ve nedenini not edin

---

<!-- _class: table table-editable -->

# Azaltmalar ve eylemler

| Azaltma | Mal sahibi | Durum |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# bilerek kabul ettiğimiz şey

- Hangi tehditleri bilinçli olarak ele almıyoruz: …
- Bu neden haklı (olasılık, maliyet, bağlam): …
- Bu kararın sahibi kim: Rol
- Bunu ne zaman tekrar gözden geçireceğiz:…

---

# Oturum tamamlandı
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kapsam ve varsayımlar kaydedildi
- [ ] Bileşenler, veri akışları ve harici taraflar eşlendi
- [ ] Güven sınırları çizildi
- [ ] Altı STRIDE kategorisinin tamamı geçti
- [ ] Olasılık × etkiye göre önceliklendirilen tehditler
- [ ] Bir sahibine atanan azaltıcı etkenler
- [ ] Kaydedilen ve sahiplenilen kabul edilen riskler
