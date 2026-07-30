---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sesja modelowania zagrożeń
language: pl
---

<!-- _class: title -->

# Sesja modelowania zagrożeń
## System · Data · Facylitator · Uczestnicy

---

# Zakres i cel

- Który system lub komponent dzisiaj modelujemy?
- Co wyraźnie wykracza poza zakres: …
- Założenia, według których pracujemy:…
- Wynik: zagrożenia ważone z środkami zaradczymi i właścicielem

---

<!-- _class: table table-editable -->

# Mapowanie systemu

| Element | Uprzejmy | Notatki |
| --- | --- | --- |
| … | Część | … |
| … | Przepływ danych | … |
| … | Strona zewnętrzna | … |

---

# Granice zaufania

- W którym miejscu dane przechodzą od zaufanych do niezaufanych?
- Jakie granice widzimy: sieć, proces, użytkownik, łańcuch dostaw?
- Gdzie odbywa się uwierzytelnianie i sprawdzanie poprawności danych wejściowych?
- Narysuj każdą granicę na szkicu systemu: …

---

<!-- _class: table -->

# Odniesienie do STRIDE

| Kategoria | Oznaczający |
| --- | --- |
| Podszywanie się | Udawanie innego użytkownika lub usługi |
| Manipulowanie | Nieautoryzowana modyfikacja danych lub kodu |
| Odrzucenie | Zaprzeczanie, jakoby jakiekolwiek działanie kiedykolwiek miało miejsce |
| Ujawnianie informacji | Informacje docierają do osób, którym nie wolno ich zobaczyć |
| Odmowa usługi | Sprawianie, że system staje się bezużyteczny lub nieosiągalny |
| Podniesienie przywilejów | Uzyskanie większej liczby przywilejów niż przyznano |

---

<!-- _class: table table-editable -->

# Zbieranie zagrożeń

| Zagrożenie | Kategoria STRIDE | Część | Ryzyko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Ustalanie priorytetów: prawdopodobieństwo × wpływ

- Prawdopodobieństwo: jak prawdopodobne jest nadużycie (niskie, średnie, wysokie)?
- Wpływ: jakie szkody, jeśli tak się stanie?
- Ryzyko = prawdopodobieństwo × wpływ; wysoki-wysoki idzie pierwszy
- Wątpliwości: wybierz wyższą wartość szacunkową i zapisz dlaczego

---

<!-- _class: table table-editable -->

# Środki łagodzące i działania

| Łagodzenie | Właściciel | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Co świadomie akceptujemy

- Jakimi zagrożeniami celowo nie zajmujemy się:…
- Dlaczego jest to uzasadnione (prawdopodobieństwo, koszt, kontekst): …
- Kto jest właścicielem tej decyzji: Rola
- Kiedy to powtórzymy:…

---

# Sesja zakończona
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Zarejestrowano zakres i założenia
- [ ] Mapowane komponenty, przepływy danych i podmioty zewnętrzne
- [ ] Wyznaczone granice zaufania
- [ ] Wszystkie sześć kategorii STRIDE przeszło
- [ ] Zagrożenia uporządkowane według prawdopodobieństwa × wpływu
- [ ] Ograniczenia przypisane do właściciela
- [ ] Akceptowane ryzyko jest zarejestrowane i posiadane
