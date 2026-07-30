---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Fenyegetés modellezési munkamenet
language: hu
---

<!-- _class: title -->

# Fenyegetés modellezési munkamenet
## Rendszer · Dátum · Lebonyolító · Résztvevők

---

# Hatókör és cél

- Melyik rendszert vagy alkatrészt modellezzük ma?
- Ami kifejezetten a hatályon kívül esik: …
- Feltételezések, amelyekkel dolgozunk:…
- Eredmény: súlyozott fenyegetés mérsékléssel és tulajdonossal

---

<!-- _class: table table-editable -->

# A rendszer feltérképezése

| Elem | Kedves | Megjegyzések |
| --- | --- | --- |
| … | Összetevő | … |
| … | Adatfolyam | … |
| … | Külső párt | … |

---

# A bizalom határai

- Hol lépnek át az adatok megbízhatóról nem megbízhatóra?
- Milyen határokat látunk: hálózat, folyamat, felhasználó, ellátási lánc?
- Hol történik a hitelesítés és a bemenet érvényesítése?
- Rajzoljon meg minden határt a rendszervázlaton: …

---

<!-- _class: table -->

# STRIDE hivatkozás

| Kategória | Jelentése |
| --- | --- |
| Hamisítás | Másik felhasználónak vagy szolgáltatásnak kiadva magát |
| Hamisítás | Adatok vagy kódok jogosulatlan módosítása |
| Elutasítás | Tagadja, hogy valaha is történt akció |
| Információ közzététel | Az információ eljut azokhoz, akik nem láthatják |
| Szolgáltatás megtagadása | A rendszer használhatatlanná vagy elérhetetlenné tétele |
| A privilégium emelése | Több kiváltság megszerzése, mint amennyi biztosított |

---

<!-- _class: table table-editable -->

# A fenyegetések gyűjtése

| Fenyegetés | STRIDE kategória | Összetevő | Kockázat |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Rangsorolás: valószínűség × hatás

- Valószínűség: mennyire valószínű a visszaélés (alacsony, közepes, magas)?
- Hatás: mekkora a kár, ha megtörténik?
- Kockázat = valószínűség × hatás; magas-magas megy előbb
- Kétségei vannak: válassza a magasabb becslést, és jegyezze meg, miért

---

<!-- _class: table table-editable -->

# Enyhítések és intézkedések

| Enyhítés | Tulajdonos | Állapot |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Amit tudatosan elfogadunk

- Mely fenyegetésekkel nem foglalkozunk szándékosan:…
- Miért indokolt ez (valószínűség, költség, kontextus): …
- Kié ez a döntés: Szerep
- Mikor nézzük ezt újra:…

---

# A munkamenet befejeződött
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Terjedelem és feltételezések rögzítve
- [ ] Összetevők, adatfolyamok és külső felek feltérképezve
- [ ] Meghúzták a bizalom határait
- [ ] Mind a hat STRIDE kategória végigment
- [ ] A valószínűség × hatás szerint rangsorolt veszélyek
- [ ] Tulajdonoshoz rendelt enyhítések
- [ ] Az elfogadott kockázatok rögzítve és birtokolva
