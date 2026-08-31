---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Pengarahan status
language: id
---

<!-- _class: title -->

# Pengarahan status

---

# Ringkasan status

- Status keseluruhan: dalam jalur/butuh perhatian/kritis
- Perkembangan penting sejak pengarahan sebelumnya: …
- Prospek untuk periode mendatang: …

---

<!-- _class: cockpit -->

# Dasbor status

```cockpit
{
  "layout": "auto",
  "animateOnEnter": true,
  "meters": [
    {
      "type": "speedometer",
      "label": "Penggunaan anggaran",
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
      "label": "Tingkat risiko",
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
      "label": "Keyakinan pada jadwal",
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
      "label": "Tren item terbuka",
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

# Kemajuan per aliran kerja

| Aliran kerja | Status | Penjelasan |
| --- | --- | --- |
| Alur kerja A | 🟢 Sesuai jalur | Berlangsung sesuai rencana |
| Alur kerja B | 🟠 Perhatian | Menunggu keputusan |
| Alur kerja C | 🔴 Kritis | Kurangnya kapasitas |

---

# Risiko dan penghambat

- Risiko 1: … (kemungkinan: tinggi, dampak: besar)
- Risiko 2: … (kemungkinan: rendah, dampak: besar)
- Pemblokir: … — bantuan dibutuhkan dari …

---

# Keputusan dan tindakan

- Diperlukan keputusan: …
- Tindakan: … (pemilik, tanggal)
- Tindakan: … (pemilik, tanggal)
