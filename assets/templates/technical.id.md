---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Penjelasan teknis
language: id
---

<!-- _class: title -->

# Penjelasan teknis

---

# Konteks dan tujuan

- Kegunaan komponen ini: …
- Untuk siapa penjelasan ini: …
- Apa yang akan Anda pahami pada akhirnya: …

---

### Ikhtisar arsitektur

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Komponen dan tanggung jawab

| Komponen | Tanggung jawab | Pemilik |
| --- | --- | --- |
| Klien | Presentasi dan masukan | Tim A |
| API | Validasi dan perutean | Tim B |
| Layanan | Logika bisnis | Tim B |
| Basis data | Penyimpanan | Tim C |

---

# Aliran data atau aliran proses
<!-- ocideck_list_style: numbered -->

1. Pengguna mengirim permintaan
2. API memvalidasi dan merutekannya
3. Layanan memproses dan menyimpannya
4. Hasilnya kembali ke pengguna

---

<!-- _class: code -->

# Contoh kode

```dart
/// Ganti contoh ini dengan kode yang ingin Anda jelaskan.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Risiko dan trade-off

- Solusi yang dipilih: … — karena: …
- Alternatif yang ditolak: … — karena: …
- Risiko yang diketahui:…

---

# Daftar periksa implementasi
<!-- ocideck_list_style: checklist -->

- [ ] Desain didiskusikan dengan tim
- [ ] Tes tertulis
- [ ] Dokumentasi diperbarui
- [ ] Pengaturan pemantauan
