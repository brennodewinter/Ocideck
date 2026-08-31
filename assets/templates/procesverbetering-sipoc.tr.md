---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SIPOC süreç genel görünümü
language: tr
---

<!-- _class: title -->

# SIPOC süreç genel görünümü
## Tedarikçi · Girdi · Süreç · Çıktı · Müşteri

---

<!-- skip -->

# Bu şablonla bu şekilde çalışırsınız

- Her eylemi kaydetmek için değil, tek bir sürecin kapsamını ve bağımlılıklarını anlamak için SIPOC'u kullanın.
- Yardımı ve örnek satırını kontrol listesi olarak kullanın; Cevaplarınızı **Süreç sınırlarına** ve boş **SIPOC** matrisine girin.
- Tercihen müşteriden tedarikçiye, girdi ve çıktı için isimler ve süreç adımları için fiiller ile çalışın.
- Yalnızca **Atlandı** etiketli slaytlar sunumun ve dışa aktarmanın dışında bırakılacaktır. Hedef kitlenizin ihtiyaç duyabileceği veya duymayabileceği açıklamalar için **Atla**'yı açın veya kapatın.

---

# SIPOC haritası nedir?

- **Tedarikçi:** sürecin ihtiyaç duyduğu bilgi veya kaynakları sağlar.
- **Girdi:** sürecin gerektirdiği veriler, materyaller veya diğer koşullar.
- **Süreç:** Girdiyi dönüştüren 4 ila 7 yüksek düzey etkinlik.
- **Çıktı:** Sürecin ürettiği ürün, hizmet veya bilgi.
- **Müşteri:** Çıktının dahili veya harici alıcısı.

---

<!-- _class: table table-editable -->

# Süreç sınırlarını belirleyin

| Sınır | Değer |
| --- | --- |
| İşlem adı |  |
| Başlangıç ​​noktası |  |
| Bitiş noktası |  |

---

<!-- skip -->

# Kontrol Listesi — Sınırlar ne zaman yeterince net olur?

- **Süreç:** Fiil ve konuyu içeren tanınabilir bir ad verin; örneğin "Siparişi kaydet".
- **Başlangıç ​​noktası:** Gözlemlenebilir bir olayı adlandırın; örneğin "İstek alındı".
- **Uç nokta:** kanıtlanabilir bir sonucu belirtin; örneğin "Sipariş onayı gönderildi".
- Ekibin anlamlı anlaşmalar yapabileceği sınırları seçin.
- İstisnaları ve bitişik süreçleri matrisin dışına taşıyın; bunları ayrı ayrı yazın.

---

<!-- skip -->

# Kontrol Listesi — Sağdan sola doğru tamamlayın

1. Süreç için net başlangıç ​​ve bitiş noktaları belirleyin.
2. Sonuca bağlı olan müşterileri adlandırın.
3. Aldıkları çıktıları açıklayın.
4. Süreci 4 ila 7 üst düzey aktiviteyle özetleyin.
5. Bu faaliyetlerin hangi girdilere ihtiyaç duyduğunu belirleyin.
6. Her girdiyi onu kullanıma sunan tedarikçiye bağlayın.

---

<!-- skip -->
<!-- _class: table -->

# Kontrol listesi - Bağlantılı bir satır örneği

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Satış | Onaylanan istek | Siparişi kontrol et → kayıt ol → onayla | Sipariş onayı | Başvuru sahibi |

- Satırı tek bir zincir olarak okuyun: Tedarikçi girdiyi sağlar, süreç ise bunu müşteri için çıktıya dönüştürür.
- Yalnızca zincir önemli ölçüde farklıysa yeni bir satır ekleyin.
- Önemli bir tedarikçinin, girdinin, çıktının veya müşterinin eksik olmadığından emin olmak için ilgili kişilerle görüşün.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# SIPOC mu yoksa ayrıntılı bir akış şeması mı?

| karakteristik | SIPOC | Ayrıntılı akış şeması |
| --- | --- | --- |
| Amaç | Kapsamı ve ilişkileri tanımlayın | Belge çalışması ve kararlar |
| Detay | 4 ila 7 üst düzey aktivite | Onlarca adım içerebilir |
| Odak | Tedarikçiler, girdiler, çıktılar ve müşteriler | Sıra, devretmeler ve karar noktaları |
| Kullanmak | İyileştirme çabasının başlangıcı | Uygulama ve hata analizi |
