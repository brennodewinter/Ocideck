---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Przegląd procesu SIPOC
language: pl
---

<!-- _class: title -->

# Przegląd procesu SIPOC
## Dostawca · Wejście · Proces · Wyjście · Klient

---

<!-- skip -->

# W ten sposób pracujesz z tym szablonem

- Użyj SIPOC, aby zrozumieć zakres i zależności jednego procesu, a nie rejestrować każdą akcję.
- Skorzystaj z pomocy i przykładowego wiersza jako listy kontrolnej; wpisz swoje odpowiedzi w **Granice procesu** oraz w pustej matrycy **SIPOC**.
- Najlepiej pracować od klienta do dostawcy, używając rzeczowników określających dane wejściowe i wyjściowe oraz czasowników opisujących etapy procesu.
- Tylko slajdy oznaczone etykietą **Pominięte** zostaną pominięte w prezentacji i eksporcie. Włącz lub wyłącz opcję **Pomiń**, aby uzyskać wyjaśnienia, których odbiorcy mogą potrzebować lub nie.

---

# Co mapuje SIPOC?

- **Dostawca:** zapewnia informacje lub zasoby potrzebne w procesie.
- **Wkład:** dane, materiały lub inne warunki wymagane w procesie.
- **Proces:** 4–7 działań wysokiego poziomu, które przekształcają dane wejściowe.
- **Wyjście:** produkt, usługa lub informacja wytworzona w wyniku procesu.
- **Klient:** wewnętrzny lub zewnętrzny odbiorca produktu.

---

<!-- _class: table table-editable -->

# Ustaw granice procesu

| Granica | Wartość |
| --- | --- |
| Nazwa procesu |  |
| Punkt początkowy |  |
| Punkt końcowy |  |

---

<!-- skip -->

# Lista kontrolna – Kiedy granice są wystarczająco jasne?

- **Proces:** nadaj mu rozpoznawalną nazwę zawierającą czasownik i temat, na przykład „Zarejestruj zamówienie”.
- **Punkt wyjścia:** nazwij jedno obserwowalne zdarzenie, na przykład „Otrzymano żądanie”.
- **Punkt końcowy:** podaj jeden możliwy do wykazania wynik, na przykład „Wysłano potwierdzenie zamówienia”.
- Wybierz granice, wokół których zespół może zawierać znaczące porozumienia.
- Przenieś wyjątki i sąsiednie procesy poza macierz; zapisz je osobno.

---

<!-- skip -->

# Lista kontrolna — uzupełnij od prawej do lewej

1. Ustaw jasne punkty początkowe i końcowe procesu.
2. Wymień klientów, którym zależy na wyniku.
3. Opisz otrzymane wyniki.
4. Podsumuj proces w 4 do 7 działań na wysokim poziomie.
5. Określ, jakich danych wejściowych wymagają te działania.
6. Połącz każde dane wejściowe z dostawcą, który je udostępnia.

---

<!-- skip -->
<!-- _class: table -->

# Lista kontrolna — przykład jednego połączonego wiersza

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Sprzedaż | Zatwierdzony wniosek | Sprawdź zamówienie → zarejestruj się → potwierdź | Potwierdzenie zamówienia | Petent |

- Odczytaj ten wiersz jako jeden łańcuch: dostawca dostarcza dane wejściowe, proces zamienia je w dane wyjściowe dla klienta.
- Dodaj nowy wiersz tylko wtedy, gdy łańcuch znacznie się różni.
- Skontaktuj się z zaangażowanymi osobami, aby upewnić się, że nie brakuje żadnego ważnego dostawcy, materiału wejściowego, produktu lub klienta.

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

# SIPOC czy szczegółowy schemat blokowy?

| Charakterystyczny | SIPOC | Szczegółowy schemat blokowy |
| --- | --- | --- |
| Zamiar | Zdefiniuj zakres i relacje | Dokumentuj pracę i decyzje |
| Szczegół | 4 do 7 działań na wysokim poziomie | Może zawierać dziesiątki kroków |
| Centrum | Dostawcy, wejścia, wyjścia i klienci | Sekwencja, przekazania i punkty decyzyjne |
| Używać | Początek wysiłków zmierzających do poprawy | Analiza wykonania i błędów |
