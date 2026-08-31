---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Threat-Modeling-Sitzig
language: gsw
---

<!-- _class: title -->

# Threat-Modeling-Sitzig
## System · Datum · Moderator · Teilnehmer

---

# Umfang und Ziel

- Welches System oder welche Komponente modellieren wir heute?
- Was ausdrücklich ausserhalb des Geltungsbereichs liegt: …
- Annahmen, mit denen wir arbeiten: …
- Ergebnis: gewichtete Bedrohungen mit Abhilfemassnahmen und einem Eigentümer

---

<!-- _class: table table-editable -->

# Kartierung des Systems

| Element | Freundlich | Notizen |
| --- | --- | --- |
| … | Komponente | … |
| … | Datenfluss | … |
| … | Externe Partei | … |

---

# Vertrauen Sie Grenzen

- Wo erfolgt der Übergang von vertrauenswürdigen zu nicht vertrauenswürdigen Daten?
- Welche Grenzen sehen wir: Netzwerk, Prozess, Benutzer, Lieferkette?
- Wo finden Authentifizierung und Eingabevalidierung statt?
- Zeichnen Sie jede Grenze in die Systemskizze ein: …

---

<!-- _class: table -->

# STRIDE-Referenz

| Kategorie | Bedeutung |
| --- | --- |
| Spoofing | Vorgeben, ein anderer Benutzer oder Dienst zu sein |
| Manipulation | Unbefugte Änderung von Daten oder Code |
| Ablehnung | Leugnen, dass jemals eine Aktion stattgefunden hat |
| Offenlegung von Informationen | Informationen, die diejenigen erreichen, die sie nicht sehen dürfen |
| Dienstverweigerung | Das System unbrauchbar oder unerreichbar machen |
| Erhöhung der Privilegien | Mehr Privilegien erhalten als gewährt |

---

<!-- _class: table table-editable -->

# Drohungen sammeln

| Bedrohung | Kategorie STRIDE | Komponente | Risiko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Priorisierung: Wahrscheinlichkeit × Auswirkung

- Wahrscheinlichkeit: Wie wahrscheinlich ist Missbrauch (gering, mittel, hoch)?
- Auswirkung: Wie hoch ist der Schaden, wenn es passiert?
- Risiko = Wahrscheinlichkeit × Auswirkung; Hoch-Hoch geht zuerst
- Im Zweifelsfall: Wählen Sie den höheren Kostenvoranschlag und notieren Sie den Grund

---

<!-- _class: table table-editable -->

# Abhilfemassnahmen und Massnahmen

| Schadensbegrenzung | Besitzer | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Was wir wissentlich akzeptieren

- Auf welche Bedrohungen gehen wir bewusst nicht ein: …
- Warum ist das gerechtfertigt (Wahrscheinlichkeit, Kosten, Kontext): …
- Wem gehört diese Entscheidung: Rolle
- Wann schauen wir uns das noch einmal an: …

---

# Sitzung abgeschlossen
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Umfang und Annahmen erfasst
- [ ] Komponenten, Datenflüsse und externe Parteien abgebildet
- [ ] Vertrauensgrenzen gezogen
- [ ] Alle sechs STRIDE-Kategorien wurden durchlaufen
- [ ] Bedrohungen, priorisiert nach Wahrscheinlichkeit × Auswirkung
- [ ] Einem Eigentümer zugewiesene Abhilfemassnahmen
- [ ] Akzeptierte Risiken erfasst und übernommen
