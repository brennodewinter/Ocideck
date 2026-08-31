---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sesi threat modeling
language: id
---

<!-- _class: title -->

# Sesi threat modeling
## Sistem · Tanggal · Fasilitator · Peserta

---

# Ruang lingkup dan tujuan

- Sistem atau komponen manakah yang kita modelkan hari ini?
- Apa yang secara eksplisit di luar cakupan: …
- Asumsi yang kami kerjakan: …
- Hasil: ancaman tertimbang dengan mitigasi dan pemilik

---

<!-- _class: table table-editable -->

# Memetakan sistem

| Elemen | Baik hati | Catatan |
| --- | --- | --- |
| … | Komponen | … |
| … | Aliran data | … |
| … | Pihak luar | … |

---

# Batasan kepercayaan

- Di manakah persilangan data dari tepercaya ke tidak tepercaya?
- Batasan manakah yang kita lihat: jaringan, proses, pengguna, rantai pasokan?
- Di mana autentikasi dan validasi masukan dilakukan?
- Gambarkan setiap batas pada sketsa sistem: …

---

<!-- _class: table -->

# Referensi LANGKAH

| Kategori | Artinya |
| --- | --- |
| Memalsukan | Berpura-pura menjadi pengguna atau layanan lain |
| Merusak | Modifikasi data atau kode yang tidak sah |
| Penolakan | Menyangkal bahwa suatu tindakan pernah terjadi |
| Keterbukaan informasi | Informasi menjangkau mereka yang tidak diperbolehkan melihatnya |
| Penolakan layanan | Membuat sistem tidak dapat digunakan atau tidak dapat dijangkau |
| Peningkatan hak istimewa | Mendapatkan lebih banyak hak istimewa daripada yang diberikan |

---

<!-- _class: table table-editable -->

# Mengumpulkan ancaman

| Ancaman | kategori LANGKAH | Komponen | Resiko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Memprioritaskan: kemungkinan × dampak

- Kemungkinan: seberapa besar kemungkinan terjadinya pelecehan (rendah, sedang, tinggi)?
- Dampak : seberapa besar kerugian jika terjadi?
- Risiko = kemungkinan × dampak; tinggi-tinggi pergi duluan
- Jika ragu: pilih perkiraan yang lebih tinggi dan catat alasannya

---

<!-- _class: table table-editable -->

# Mitigasi dan tindakan

| Mitigasi | Pemilik | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Apa yang secara sadar kami terima

- Ancaman manakah yang sengaja tidak kami atasi: …
- Mengapa hal tersebut dapat dibenarkan (kemungkinan, biaya, konteks): …
- Siapa yang memiliki keputusan ini: Peran
- Kapan kita meninjau kembali ini: …

---

# Sesi selesai
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Ruang lingkup dan asumsi dicatat
- [ ] Komponen, aliran data dan pihak eksternal dipetakan
- [ ] Batasan kepercayaan telah ditetapkan
- [ ] Keenam kategori STRIDE telah dilalui
- [ ] Ancaman diprioritaskan berdasarkan kemungkinan × dampak
- [ ] Mitigasi ditugaskan ke pemilik
- [ ] Risiko yang diterima dicatat dan dimiliki
