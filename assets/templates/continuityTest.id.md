---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Kesinambungan usaha/uji DR
language: id
---

<!-- _class: title -->

# Kesinambungan usaha/uji DR

---

# Skenario pengujian

- Skenario: … (misalnya pemadaman pusat data, ransomware)
- Asumsi sebelumnya: …
- Jenis pengujian: meja / sebagian / penuh

---

# Tujuan dan kriteria keberhasilan

- Tujuan tes:…
- Kriteria keberhasilan 1: …
- Kriteria keberhasilan 2: …

---

<!-- _class: table table-editable -->

# Proses kritis

| Proses | Prioritas | Tergantung pada |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Ikhtisar RTO / RPO

| Proses atau sistem | RTO | RPO | Bertemu? |
| --- | --- | --- | --- |
| … | … | … | Ya / tidak |
| … | … | … | … |

---

<!-- _class: timeline -->

# Garis waktu pengujian

- T+0 :: Tes dimulai :: Skenario diumumkan.
- T+… :: Failover dimulai
- T+… :: Pemulihan terverifikasi
- T+… :: Ujian berakhir

---

<!-- _class: table table-editable -->

# Temuan

| Menemukan | Keparahan | Komponen |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Penyimpangan dan pemblokir

- Penyimpangan dari pedoman: …
- Pemblokir selama pengujian: …
- Solusi yang digunakan: …

---

# Poin perbaikan
<!-- ocideck_list_style: checklist -->

- [ ] Perbarui pedoman yang tepat: …
- [ ] Sesuaikan pengaturan teknis: …
- [ ] Jadwalkan latihan atau olah raga:…

---

# Kemampuan pemulihan go / no-go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Proses penting dipulihkan dalam RTO
- [ ] Kehilangan data tetap berada dalam RPO
- [ ] Playbook terbukti dapat digunakan
- [ ] Putusan: kemampuan pemulihan ditunjukkan
