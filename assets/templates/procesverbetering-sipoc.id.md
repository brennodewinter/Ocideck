---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Ringkasan proses SIPOC
language: id
---

<!-- _class: title -->

# Ikhtisar proses SIPOC
## Pemasok · Masukan · Proses · Keluaran · Pelanggan

---

<!-- skip -->

# Beginilah cara Anda bekerja dengan templat ini

- Gunakan SIPOC untuk memahami ruang lingkup dan ketergantungan suatu proses, bukan untuk mencatat setiap tindakan.
- Gunakan bantuan dan baris contoh sebagai daftar periksa; masukkan jawaban Anda pada **Batas proses** dan pada matriks **SIPOC** yang kosong.
- Lebih disukai bekerja dari pelanggan ke pemasok, dengan kata benda untuk input dan output dan kata kerja untuk langkah-langkah proses.
- Hanya slide berlabel **Dilewati** yang tidak akan ditampilkan dan diekspor. Aktifkan atau nonaktifkan **Lewati** untuk penjelasan yang mungkin dibutuhkan atau tidak dibutuhkan oleh audiens Anda.

---

# Apa yang dipetakan SIPOC?

- **Pemasok:** menyediakan informasi atau sumber daya yang dibutuhkan proses.
- **Input:** data, material, atau kondisi lain yang diperlukan oleh proses.
- **Proses:** 4 hingga 7 aktivitas tingkat tinggi yang mengubah masukan.
- **Output:** produk, layanan, atau informasi yang dihasilkan proses.
- **Pelanggan:** penerima keluaran internal atau eksternal.

---

<!-- _class: table table-editable -->

# Tetapkan batasan proses

| Batas | Nilai |
| --- | --- |
| Nama proses |  |
| Titik awal |  |
| Titik akhir |  |

---

<!-- skip -->

# Daftar Periksa – Kapan batas-batasnya cukup jelas?

- **Proses:** beri nama yang dapat dikenali dengan kata kerja dan subjek, misalnya “Daftar pesanan”.
- **Titik awal:** Sebutkan satu peristiwa yang dapat diamati, misalnya “Permintaan diterima”.
- **Titik akhir:** sebutkan salah satu hasil yang dapat dibuktikan, misalnya “Konfirmasi pesanan terkirim”.
- Pilih batasan di mana tim dapat membuat kesepakatan yang bermakna.
- Memindahkan pengecualian dan proses yang berdekatan ke luar matriks; tuliskan secara terpisah.

---

<!-- skip -->

# Daftar Periksa — Lengkap dari kanan ke kiri

1. Tetapkan titik awal dan akhir yang jelas untuk proses tersebut.
2. Sebutkan pelanggan yang bergantung pada hasilnya.
3. Jelaskan keluaran yang mereka terima.
4. Ringkaslah proses dalam 4 hingga 7 aktivitas tingkat tinggi.
5. Tentukan input apa yang dibutuhkan aktivitas tersebut.
6. Tautkan setiap masukan ke pemasok yang menyediakannya.

---

<!-- skip -->
<!-- _class: table -->

# Daftar Periksa — Contoh satu baris yang terhubung

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Penjualan | Permintaan yang disetujui | Periksa pesanan → daftar → konfirmasi | Konfirmasi pesanan | Pemohon |

- Baca baris sebagai satu rantai: pemasok memberikan masukan, proses mengubahnya menjadi keluaran bagi pelanggan.
- Tambahkan baris baru hanya jika rantainya berbeda secara signifikan.
- Periksa dengan pihak-pihak yang terlibat untuk memastikan bahwa tidak ada pemasok, input, output, atau pelanggan penting yang hilang.

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

# SIPOC atau diagram alur detailnya?

| Ciri | SIPOC | Diagram alur terperinci |
| --- | --- | --- |
| Tujuan | Tentukan ruang lingkup dan hubungan | Dokumentasikan pekerjaan dan keputusan |
| Detil | 4 hingga 7 aktivitas tingkat tinggi | Mungkin berisi lusinan langkah |
| Fokus | Pemasok, input, output dan pelanggan | Urutan, serah terima, dan poin keputusan |
| Menggunakan | Mulai dari upaya perbaikan | Eksekusi dan analisis kesalahan |
