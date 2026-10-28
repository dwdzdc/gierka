# Progress

Legenda: `[x]` zrobione · `[~]` częściowo / czeka na decyzję · `[ ]` do zrobienia · ~~przekreślone~~ odrzucone

## Decyzje

- [x] Silnik: Godot 4 (4.7, renderer Mobile)
- [x] Sieć: host-client po ENet (później Steam lobby przez GodotSteam). Ruch gracza z autorytetem klienta; potwór, HP, krew i punkty z autorytetem hosta. Kamera, UI i audio feedback lokalnie.
- [x] Kontrakt pokoju: `Geometry`, `Doorways`, `CameraZones` (Area3D + Camera), `LootSpawns`, `AmbientPoints` (patrz `rooms/room.gd`)
- [x] Potwory jako typy: wspólna baza + wymienne części. Dwie warstwy AI: **reżyser** (zgrubna nawigacja: dokąd iść, wspólny dla wszystkich typów) i **zmysły** (lokalne szukanie gracza, inne dla każdego typu). Szczegóły w „Potwory: abstrakcja” (faza 8). Interfejsy części do potwierdzenia przed refaktorem
- [~] Liczba graczy: teraz maks. 5 (`MAX_CLIENTS := 4` w `net/network.gd`, 5 spawnów w hali; podniesione z 4 na prośbę 23.10, bez zmian w balansie). Pomysł (23.10): nawet 10. Technicznie łatwe (stała + więcej spawnów), ale balans jest pod 2–4: liczba potworów (maks. 4), monet i tempo etapów; przy 10 ocalałych udział w puli zero-sum jest znikomy. Rekomendacja: 6–8 i skalowanie trudności z liczbą graczy (do decyzji)
- [x] Sterowanie: tank (camera-relative odrzucone po playteście)
- [ ] Pomysł (25.10, hipotetyczny): wersja przeglądarkowa, gracze łączą się kodem pokoju zamiast IP. Bez przepisywania: eksport Web z Godota (WebAssembly). Do zmiany: renderer Mobile → Compatibility (w przeglądarce tylko WebGL2), ENet → WebRTC (`WebRTCMultiplayerPeer`) plus mały serwer sygnalizacyjny z kodami pokoi i STUN/TURN. RPC i synchronizacja zostają, bo sieć jest tylko w `net/network.gd`. Szacunek: 2–3 tygodnie
  - Uwaga: kłóci się z planem Steam lobby (GodotSteam nie działa w przeglądarce): albo jedno, albo warstwa „lobby” z dwiema implementacjami. Największe ryzyko to wydajność: dużo świateł z cieniami na WebGL2 przy mapie z 60 pokoi. Desktop dołączający do gry z przeglądarki potrzebuje wtyczki webrtc-native

## Kolejność prac

Zrobione 24.10: 47c9 wzrok, 47c10 strażnik, 16h siatka i pętle, 15i/15j korytarze, 15l–15n drzwi, 15k nowe pokoje.

Zrobione 25.10: 15w, 15o, 15r, 15q, 15p, 15t, 15s, 15u, 15v (cała lista z 24.10).

Było ustalone 24.10 (zrobione 25.10):
1. 15w meble rozjechane przez skalowanie siatki (bug) → 2. 15o głowa w podglądzie przez kratkę (bug) →
3. 15r antresola biblioteki dookoła bez skakania → 4. 15q zgaszone lampy nie świecą →
5. 15p dźwięki wyważania drzwi → 6. 15t zamykanie drzwi za sobą w biegu → 7. 15s limity wystąpień typów pokoi →
8. 15u nowe unikalne typy pokoi → 9. 15v warianty pokoi (drobiazgi opcjonalne, potem warianty układu).
Potem: 33b łup w pojemnikach i 41c bateria (zrobione 25.10), 36c sklep, 37 MVP.
Nowe z playtestu 25.10: 15x dźwięk wyważania drzwi (zrobione 25.10), 47g potwory za słabe (1–4 zrobione 25.10; 6–7 zrobione 27.10, 5 odrzucone), 34b winda losowo na mapie (zrobione 27.10).

Zrobione 27.10 (sesja ~1 h): 15y, 34b, 47g.6, 47g.7, 47f nauka pięter, 48 glitch, porządki w testach. Następnie: playtest tego wszystkiego (25.10 + 27.10), potem 36c sklep (szkielet do potwierdzenia), 37 MVP. Otwierane kraty w lochach: odłożone (24.10).

Szkielet potwierdzony 24.10:
- Siatka 2 m w kontrakcie pokoju: wymiary i pozycje przejść w wielokrotnościach 2 m
- Drzwi jako część przejścia (`Doorways`), wstawiane przez generator, nie na sztywno w scenie pokoju
- Stan drzwi (otwarte / zamknięte / zakluczone / wyłamane) w `GameState`, autorytet hosta

## Faza 0: setup

- [x] 1. Projekt Godot, git, struktura folderów

## Faza 1: PoC fixed camera

- [x] 2. Szary pokój, kapsuła gracza, sterowanie tank
- [x] 3. Statyczna kamera na pokój
- [x] 4. Strefy (Area3D) i przełączanie kamery
- [x] 5. Histereza i priorytety stref (`camera_priority`, nakładające się strefy)
- [x] 6. Test sterowania względem kamery: odrzucone, zostaje tank
- [x] 7. Kamery „żywe” (`follow`: lekkie śledzenie gracza obrotem)
- [x] 8. Render 1920×1080 (natywna rozdzielczość), kwantyzacja kolorów, dithering Bayera, winieta
- [x] 9. Światło i ciemność: latarka, światło postaci, mgła, migoczące żarówki
- [x] 10. Checkpoint: 3 pokoje (Hall, Corridor, Storage). Playtest: łażenie jest super

### Kamera: usprawnienia (strefy zostają główną logiką)

- [x] 10a. Bezpiecznik widoczności: postać zasłonięta w bieżącym ujęciu (raycast kamera → postać) dłużej niż ~0,5 s → przełącz na najlepszą inną kamerę z sąsiednich stref, w której ją widać
- [x] 10b. Stożek widoku jako tie-breaker: w nakładających się strefach wygrywa kamera, która lepiej pokrywa stożek przed postacią. Liczone tylko przy wejściu/wyjściu ze strefy, nie co klatkę (obrót w miejscu nie tnie)
- [x] 10c. Narzędzie: mapy pokrycia kamer (`tools/coverage_map.gd` → `docs/coverage/*.png`, zielony/żółty/czerwony) zamiast wtyczki edytora. Wizualizacja martwych pól (miejsca bez pokrycia kamer, miejsca, gdzie postać byłaby zasłonięta)
  - Stan po pierwszym przebiegu (poprawiona kamera skrzyżowania z 15% do 6% martwego pola):
    - hall       zielony  99%  żółty   0%  czerwony   0%
    - corridor   zielony  98%  żółty   1%  czerwony   0%
    - storage    zielony  99%  żółty   0%  czerwony   0%
    - turn       zielony  95%  żółty   0%  czerwony   4%
    - junction   zielony  93%  żółty   0%  czerwony   6%
    - closet     zielony  99%  żółty   0%  czerwony   0%
    - ramp       zielony 100%  żółty   0%  czerwony   0%
    - stairwell  zielony  85%  żółty  10%  czerwony   4%
- [~] 10d. Przewidywalność cięć. Naprawione: ujęcie z bezpiecznika „przyklejało się” (środkowa alejka magazynu pokazywana z narożnika przy wejściu). Teraz wraca do kamery własnej strefy, gdy ta znów widzi gracza. Dalej obserwować w playtestach

## Faza 2: modularne pokoje

- [x] 11. Scena bazowa pokoju według kontraktu (NavMesh liczony dla całej mapy, nie per pokój)
- [x] 12. Generator: pokoje doklejane po `Doorways` (obrót o 90°, test kolizji AABB), deterministyczny z seeda, przy zablokowaniu próbuje kolejnych wariantów seeda. 8 typów pokoi, w tym rampa i klatka schodowa (piętra co 3 m)
- [x] 13. Zaślepki niepołączonych drzwi, hala jako strefa startowa (PlayerSpawns), potwór startuje w najdalszym płaskim pokoju
- [x] 14. Nawigacja wypiekana w runtime dla wygenerowanej mapy (2 klatki po złożeniu)
- [~] 15. Modyfikacje z seeda: loot (losowy, host), światła (20% pokoi ciemnych, w jasnych 20% lamp migocze). Zablokowanych przejść brak: zablokowanie zwykłego połączenia mogłoby odciąć część mapy, ma sens dopiero przy pętlach (16h)
  - Uwaga (27.10, konflikt z 16g/16h): pętle już są, ale gruz można postawić tylko na krawędzi pętli (inaczej odcina część mapy), a pętla jest jedna na 10 pokoi. Każdy gruz kasuje więc pętlę, czyli drogę ucieczki, którą 16h celowo dokłada. Nie robię. Sensowna alternatywa (do decyzji): gruz z prześwitem, przez który przejdzie tylko kucający gracz (potwór musi obejść albo wybrać szyb), czyli skrót dla graczy zamiast ślepego zaułka

### Po playteście generatora (23.10)

Problemy: mapa wydaje się ciasna nawet przy 30 pokojach, kamery w małych pokojach często
skaczą, filar zasłania postać, drzwi trudno zauważyć (zwłaszcza z kamer prawie
równoległych do ściany, np. nowe drzwi na południu hali).

- [x] 15a. Większa skala pokoi: korytarze 4 m szerokości, pokoje 6–20 m, sufity 4–6 m, drzwi 2,0×2,6 m, piętro co 5 m. Twardych wymiarów z LC nie znalazłem, skala dobrana względem postaci (1,7 m)
- [x] 15b. Limit pokoi 60. Mapa 60 pokoi: składanie ~0,13 s, NavMesh ~0,05 s, 60 FPS (vsync) na M1; światła wygaszane z odległością. 10/10 seedów daje pełne 60 pokoi, do 9 poziomów
- [x] 15c. Małe pokoje (zakręt, skrzyżowanie, schowek) mają jedno ujęcie; skrzyżowanie bez filara
- [x] 15d. Rzadsze cięcia: mniej i większe strefy (15a/15c) + minimalny czas ujęcia 1,2 s (wyjątek: postaci nie widać). Losowe błądzenie: ~7 cięć/min, najkrótsze ujęcie 2,6 s (`tests/camera_churn_test.gd`)
- [x] 15e. Futryna w kontrastowym kolorze (lekko świeci) + lampka nad przejściem, po obu stronach każdego połączonego przejścia. Zamurowane przejścia nie mają futryny
- [x] 15f. Zasada kamer: każde przejście widoczne z kamery strefy, w której leży, pod kątem < 70° do normalnej ściany. Pilnuje tego `tests/camera_rules_test.gd`
- [x] 15g. Po uwagach: futryny przyciemnione (zostaje lekka poświata + mała lampka), pokoje wyposażone (szafki, regały z towarem, beczki, stoły, krzesła, stół warsztatowy, rury pod sufitem), więcej lamp w dużych pokojach z widocznymi oprawami, wszystkie światła +30% (`LIGHT_SCALE` w `tools/gen_rooms.py`)
- [x] 15h. Drobne rekwizyty z seeda: 2–5 skrzyń/beczek przy ścianach każdego płaskiego pokoju, z dala od drzwi, wyjścia, spawnów i szafek; identyczne u wszystkich (test sieci porównuje podpis mapy)

### Różnorodność pokoi (playtest 24.10)

Problem: pokoje są powtarzalne, łatwo się zgubić. Zakręt (6×6) i skrzyżowanie (10×10) to
kwadratowe pokoje z 2–3 drzwiami, a nie korytarze, więc mapa wygląda jak pokój na pokoju.
Według wag losowania korytarzopodobne typy to już ~75%, ale wyglądają jak pokoje.

Research: Lethal Company ma kilka „wnętrz” o spójnym klimacie zamiast mieszanki: Facility
(rury, pomosty, przepaście), Manor (duże otwarte pokoje, sklepienia, regały z książkami,
wielkie schody na starcie), Mineshaft (wąskie kamienne pokoje i jaskinie, dwie strefy).
Źródła: [lethalcompany.wiki.gg: Moons](https://lethalcompany.wiki.gg/wiki/Moons),
[itemlevel.net: Mineshaft](https://itemlevel.net/lethal-company-mineshaft-complete-guide-new-interior-v60/)

- [x] 15i. Prawdziwe korytarze: zakręt L, T i X w kształcie korytarzy 4 m szerokości (ramiona, nie kwadratowa sala z drzwiami); obecne kwadratowe zostają jako osobne pokoje
  - Zrobione: `CorridorL` (8×8), `CorridorT` (12×8), `CorridorX` (12×12), ramiona 4 m (wnętrze 3,6 m); to, co nie jest korytarzem, wypełniają pełne bloki ściany. W losowaniu są też gołe korytarze `Link8`/`Link12`
- [x] 15j. Proporcje: wyraźnie więcej korytarzy niż pokoi, pokoje raczej „przechodnie” jak w Alone in the Dark. Mierzyć w teście (udział korytarzy w mapie), nie tylko wagami
  - Zrobione: wagi korytarzy ~60%, pokoi ~30%, piętra ~10%; `map_test` wypisuje udział korytarzy: przy 20 pokojach 41–83% elementów mapy (z łącznikami pętli), zwykle ~70%
  - Uwaga: za dużo gołych korytarzy też nuży; do oceny w playteście, wagi w `MapGenerator.ROOM_TYPES`
- [x] 15k. Nowe pokoje:
  - Biblioteka: okrągła rotunda, antresola z regałami, stoliki na dole, kolumny pod antresolą, duży świetlik (w stylu zamku Dimitrescu z RE Village)
  - Lochy: korytarz z celami po bokach (klimat Amnesii); cele jako kryjówki/ślepe zaułki, kraty przepuszczają wzrok
  - Wielki hol (jak w Amnesii, np. z fontanną)
  - Kandydaci z LC: serwerownia, magazyn z pomostami, maszynownia
- Uwaga (spójność): biblioteka, lochy i hol z Amnesii to klimat zamku, a obecne pokoje (magazyn, regały z towarem, rury) to zaplecze przemysłowe; w jednej mapie może to wyglądać przypadkowo
  - Ustalone 24.10: na razie wszystkie pokoje w jednej puli. Później zestawy pokoi wg motywu, motyw wybiera host w menu (łączy się z 49)
- Uwaga (kamery): kolumny pod antresolą to dokładnie problem „filar zasłania postać” z playtestu 23.10; antresola to drugi poziom w jednym pokoju (NavMesh, schody, pokrycie kamer z dwóch wysokości). Biblioteka będzie najdroższym pokojem do zrobienia, zacząć od korytarzy i lochów
- Uwaga: różnorodność pomaga orientacji tylko, jeśli pokoje są rozpoznawalne. Tani dodatek: charakterystyczne punkty orientacyjne w pokojach (kolor światła, unikalny rekwizyt)
  - Zrobione (24.10): `Cells` (lochy 16×12: korytarz i po 3 cele z każdej strony za kratą z otwartymi drzwiczkami; kamera do każdej celi zza korytarza), `Atrium` (hol 20×24×8 m z fontanną, 6 kolumn, ławki, 2 szafki), `Library` (rotunda 20×20×8 m: ośmiokąt, antresola na 3,6 m z regałami i balustradą, rampa na górę, 9 kolumn, stoliki, chłodny świetlik). W jednej puli z resztą (wagi w `ROOM_TYPES`)
  - [~] Odłożone 24.10 (decyzja użytkownika). Pomysł: część krat w lochach otwarta, żeby dało się wejść do celi. Uwaga: dziś WSZYSTKIE cele mają otwarte drzwiczki (przerwa ~1 m w kracie przy ściance), tylko nie widać tego, bo nie ma skrzydła drzwiczek. Do zrobienia: widoczne skrzydło kraty (otwarte odchylone, zamknięte w ramie), losowo z seeda część cel zamknięta, część otwarta; ewentualnie zamknięte otwierane jak drzwi (E, potwór wyważa)
  - Nowa warstwa fizyki 4 „bars”: kraty zatrzymują graczy i potwory, ale nie zasłaniają wzroku ani kamer (potwór widzi gracza w celi)
  - Pokrycie kamer: lochy 96%, hol 88% (fontanna zasłania wąski pas), biblioteka 98% (mapa pokrycia liczy tylko parter)
  - Przy okazji: skrzynie z seeda nie trafiają już do korytarzy (w 3,6 m potrafiły je zatkać); `camera_rules_test` sprawdza, że geometria pokoju nie wystaje poza jego bryłę (tak ścięte narożniki biblioteki zatykały sąsiednie korytarze)
  - Nie zrobione: kamera z antresoli „pod kątem” (górne ujęcia patrzą z wysoka), wiele punktów orientacyjnych (unikalne rekwizyty / kolory świateł)

### Drzwi (pomysł 24.10)

- [x] 15l. Drzwi w > 50% przejść (z seeda): otwieranie/zamykanie (E), stan z autorytetem hosta, otwieranie robi hałas. Zamknięte drzwi tłumią hałas
  - Kratka (okienko) w drzwiach: wzrok przez nią działa, ale potwór zauważy gracza za zamkniętymi drzwiami tylko z bliska (np. ≤ 2–3 m od drzwi) i patrząc prosto na kratkę (wąski kąt)
  - Uwaga: gracze nie patrzą oczami postaci, tylko ze stałej kamery, więc „patrzenie przez kratkę” niczego im nie daje, jeśli kamera po drugiej stronie i tak pokazuje pokój dopiero po wejściu. Żeby kratka miała sens dla graczy: osobne ujęcie przez kratkę (jak szpara w szafce, 16f) po podejściu do drzwi i E/przytrzymaniu, albo kamera korytarza, która przez kratkę widzi kawałek pokoju
  - Ustalone 24.10: ujęcie przez kratkę takie samo jak szpara w szafce (16f), po podejściu do zamkniętych drzwi
- [x] 15m. Zakluczone drzwi: losowo od 0 do maks. 10% drzwi. Klucz to znalezisko, dowolny klucz otwiera dowolne zakluczone drzwi (jak w LC), zużywa się
  - Uwaga (odcięcie mapy): bez pętli (16h) zakluczone drzwi odcinają całą gałąź mapy. Generator musi pilnować, żeby klucz dało się zdobyć bez przechodzenia przez zakluczone drzwi, i żeby winda nigdy nie była za nimi. Liczba kluczy ≥ liczba zakluczonych drzwi w osiągalnej części
- [x] 15n. Potwory niszczą drzwi, gdy mają powód sądzić, że za nimi jest gracz: pościg, trop krwi albo hałas prowadzący za drzwi (stany HUNT / INVESTIGATE / TRACK). Wyważanie trwa kilka sekund i jest głośne (okno na ucieczkę)
  - Ustalone 24.10: potwór otwiera zwykłe drzwi, ale długo (np. 3–4 s, słychać szarpanie klamki); wyważenie jest szybsze (np. 1–1,5 s, głośne) i zostawia drzwi wyłamane na stałe. Otwiera, gdy tylko przechodzi (patrol), wyważa, gdy ma powód (pościg/trop/hałas) albo drzwi są zakluczone
  - Uwaga: przez to w pościgu zamknięcie drzwi za sobą daje tylko ~1 s i kosztuje drzwi (potem już nie zasłaniają). Zamykanie drzwi głównie chroni przed patrolem; czasy do strojenia w playteście
  - Potwierdzone 24.10: taki był zamysł (drzwi chronią przed patrolem, w pościgu dają chwilę)
  - Uwaga: NavMesh musi znać drzwi (przejście z kosztem, nie ściana), a szyby wentylacyjne (47c6) omijają drzwi; to dobrze, ale łowca nie powinien przez to ignorować ich całkiem
  - Kamery: drzwi nie mogą zasłaniać przejścia w ujęciu (15f), test zasad kamer do rozszerzenia
  - Zrobione (24.10): `props/door.gd` (węzeł Door w przejściu, stan w `GameState.doors`, rozsyłany jak gracze), plan drzwi w `MapGenerator._plan_doors`: drzwi w ~65% przejść (z 20 pokoi: 50–78%), 30% na start otwartych, zakluczonych losowo 0–10% (nigdy w hali), klucze (`loot/key_pickup`) tyle, ile zakluczonych, tylko w pokojach osiągalnych bez nich. Gracz: E (0,25 s; kluczem 1 s), hałas 5 m; podgląd przez kratkę po 0,6 s bez ruchu przodem do zamkniętych drzwi (ruch kończy). Potwór: otwiera 3,5 s (szarpanie klamki co 1 s, hałas 7 m), wyważa 1,2 s (hałas 16 m, drzwi wyłamane na stałe), patrol omija zakluczone; przez kratkę widzi z ≤ 2,6 m i ≤ 35° od osi; zamknięte drzwi tłumią hałas o połowę. Test: `tests/door_test.gd`
  - Uwaga: NavMesh nie zna drzwi (są poza regionem nawigacji), potwór reaguje dopiero przy drzwiach; reżyser nie wie o zakluczonych drzwiach i może wysłać patrol za nie (patrol wtedy wybiera inny cel)
  - Uwaga: otwarte skrzydło nie ma kolizji (przenika przez gracza i meble), tylko wygląd

### Po playteście 24.10: drzwi i znaleziska

- [x] 15o. Bug: podgląd przez kratkę zasłania głowa własnej postaci (kamera stoi 0,6 m za skrzydłem, postać między nią a kratką). Propozycja: na czas podglądu ukryć model własnej postaci przed tą kamerą (osobna warstwa renderu / cull mask), zamiast przysuwać kamerę do kratki (wtedy znika efekt „szpary”)
  - Zrobione: kamery podglądu nie rysują warstwy renderu 3 (`Door.PEEK_HIDDEN_LAYER`); na czas podglądu własna postać (`Body`, `Visor`) przechodzi na tę warstwę, kamery stref i inni gracze dalej ją widzą. Sprawdzone zrzutem z gracza 0,45 m od drzwi
- [x] 15p. Wyważanie drzwi słychać: seria uderzeń (np. 2–3 łomoty co ~0,4 s) i na końcu trzask wyłamania, u wszystkich graczy, każdy łomot też jako hałas dla innych potworów. Dziś jest tylko jeden dźwięk na końcu
  - Zrobione: przy wyważaniu łomot co 0,4 s (przy 1,2 s: trzy), u wszystkich graczy (`GameState.monster_rattle(..., pound)`), każdy łomot to hałas 12 m dla innych potworów; na końcu dotychczasowy trzask (16 m). Dźwięk łomotu: `assets/sfx/door_pound.tres` (Kenney impactSoft_heavy). `door_test` liczy łomoty przed wyłamaniem
- [x] 15q. Zgaszona lampa nie może świecić (24.10: „sam prostokąt świeci w ciemności”). Diagnoza: w ciemnych pokojach generator gasi światła i chowa oprawy `Fixture*`, ale (1) migocząca żarówka (`fx/flicker_light.gd`) przygasa samo światło, a jej oprawa świeci dalej równo, (2) lampki nad futrynami drzwi i świetlik w bibliotece to osobne świecące bryły, których nikt nie gasi. Do zrobienia: oprawa przygasa razem ze swoim światłem (emisja materiału ∝ energia), w ciemnym pokoju gasną też lampki futryn po jego stronie i świetlik
  - Uwaga: lampka nad drzwiami miała być znakiem „tu jest wyjście” (15e). Jeśli zgaśnie w ciemnym pokoju, drzwi będzie trudniej znaleźć; zostaje słaba poświata futryny, a latarka ma tam sens (zgodne z 41b)
  - Zrobione: `Room.switch_off_lamps()` w ciemnym pokoju podmienia materiał opraw, lampek nad drzwiami po jego stronie i świetlika na nieświecący `lamp_off.tres` (oprawy zostają widoczne jako zgaszone, zamiast znikać). Migocząca żarówka przygasa razem ze swoją oprawą (własna kopia materiału). Test `tests/lamps_test.gd`
  - Przy okazji znaleziony bug: lampy, którym generator losowo doklejał migotanie (20% w jasnych pokojach), nigdy nie migotały (skrypt doklejony po `_ready`: brak przetwarzania i energia bazowa 0). Naprawione; migotały tylko lampy oznaczone w `gen_rooms.py`
- [x] 15r. Biblioteka: po antresoli da się przejść dookoła bez skakania. Diagnoza: ścięte narożniki ośmiokąta (pełne bloki ściany do sufitu) zwężają antresolę w rogach do ~0,7 m między balustradą a ścianą, czyli węziej niż postać. Do zrobienia: mniejsze ścięcia (np. 3 m zamiast 5 m) albo balustrada w rogach przesunięta do środka; test: ścieżka NavMesh dookoła antresoli
  - Zrobione: ścięcia narożników 3 m zamiast 5 m, w rogu antresoli ~2,1 m przejścia. Test `tests/library_test.gd`: ścieżka NavMesh (promień potwora 0,5 m) między sąsiednimi pasami antresoli idzie przez narożnik (~15 m); przed poprawką nie było jej wcale. Pokrycie kamer bez zmian (98%)
- [x] 15s. Limit wystąpień typu pokoju (24.10: „bez sensu 5 bibliotek na 20 pomieszczeń”). Propozycja: limit na typ zależny od wielkości mapy (np. biblioteka i hol: 1 na każde 20 pokoi, co najmniej 1; lochy, magazyn: 1 na 10) plus malejąca waga po każdym wystąpieniu (np. ×0,5), żeby te same pokoje nie skupiały się obok siebie. Korytarze i łączniki bez limitu. Dane w `MapGenerator.ROOM_TYPES` (waga + limit na typ)
  - Uwaga: unikalne pokoje to też punkty orientacyjne („za biblioteką w lewo”), a przy 5 bibliotekach przestają nimi być. Limit nie może zablokować składania mapy: gdy limity wyczerpią pokoje, zostają korytarze bez limitu
  - Zrobione: `MapGenerator.ROOM_LIMITS` (1 na N pokoi mapy, co najmniej 1): biblioteka i hol 20, lochy, magazyn i schowek 10; zakręt, skrzyżowanie, piętra, korytarze bez limitu. Każde wystąpienie typu z limitem mnoży jego wagę ×0,5. `map_test` sprawdza limity; przy 20 i 60 pokojach mapy składają się jak wcześniej
  - Uwaga: przy dużych mapach (60) limity podnoszą udział korytarzy, bo charakterystycznych pokoi jest mało; to rozwiązuje dopiero 15u
- [x] 15t. Zamykanie drzwi za sobą w biegu (24.10). Dziś trzeba stać przodem do drzwi (≤ ~64°) i trzymać E 0,25 s, a uciekając, ma się drzwi za plecami. Propozycja: E (stuknięcie, bez trzymania, także w biegu) zamyka otwarte drzwi, przez które przeszedłeś w ostatnich ~1,5 s i które są ≤ 2,5 m za tobą, bez celowania; trzaśnięcie robi hałas. Zwykłe otwieranie zostaje jak jest
  - Uwaga: E ma już kilka znaczeń (podnieś, odbij, bandaż, szafka, winda). „Drzwi za mną” tylko wtedy, gdy nie ma innego celu, inaczej w pościgu zamiast drzwi można np. zacząć wchodzić do szafki. W pościgu drzwi i tak dają ~1,2 s (wyważenie), więc łatwe zamykanie nie psuje balansu
  - Zrobione: gracz zapamiętuje otwarte drzwi, przez które przeszedł (zmiana strony w świetle przejścia); stuknięcie E w ciągu 1,5 s, do 2,5 m od nich, zatrzaskuje je bez celowania, także w biegu, o ile E nie ma innego celu (kolega, wyjście, szafka). Host przyjmuje zatrzaśnięcie do 3,5 m (gracz zdążył odbiec), tylko zamyka, hałas 9 m (zwykłe zamknięcie 5 m). Podpowiedź „E - zatrzaśnij drzwi za sobą”. Test w `door_test`
  - Nie zrobione: osobny dźwięk trzaśnięcia (gra zwykłe skrzypnięcie zamykania)
- [x] 15u. Więcej unikalnych typów pokoi zamiast powtórek (24.10: orientacja jest dużo lepsza, wolę więcej różnych pokoi niż więcej sztuk tych samych). Razem z 15s: większość „pokoi” najwyżej raz na mapę. Kandydaci: serwerownia, kotłownia z rurami i piecem, kaplica, stołówka/kuchnia, prysznice/łazienka, gabinet, archiwum z regałami na akta (pasuje do łupu w pojemnikach, 33b), pralnia, maszynownia z pomostami
  - Uwaga: przy 20 pokojach i ~30% udziału pokoi potrzeba ok. 6–8 różnych typów, żeby żaden się nie powtórzył; dziś pokoi (nie korytarzy) jest 8, z czego zakręt i schowek są mało charakterystyczne. Mieszanie zamku i zakładu w jednej puli zostaje do czasu motywów (49)
  - Zrobione: 6 nowych pokoi, każdy najwyżej raz na 20 pokoi mapy (waga 0,5): `Boiler` kotłownia 16×12 (kocioł z pomarańczowym blaskiem paleniska, drugi mniejszy, hałda węgla, nisze za kotłami z osobnymi ujęciami), `Chapel` kaplica 12×20 (ławki, ołtarz z czerwonym suknem, świecące okno z krzyżem, konfesjonał = szafka), `Canteen` stołówka 16×16 (4 długie stoły z prześwitem, kuchnia, zielonkawe świetlówki), `Archive` archiwum 16×12 (3 rzędy szaf na akta, kamery wzdłuż alejek), `Showers` prysznice 12×12 (kafle, kabiny, 3 szafki w przebieralni), `Servers` serwerownia 12×16 (2 rzędy szaf, niebieskie światło, 4 ujęcia). Nowe materiały `tile`, `cloth`. Zasady kamer OK, pokrycie 89–100%
  - Przy 20 pokojach na mapie zwykle 2–4 z nowych, udział korytarzy 38–79% (wcześniej 41–83%)
  - Nie zrobione z listy: maszynownia z pomostami (drugi poziom jak antresola, droższa), gabinet, pralnia
- [x] 15v. Warianty istniejących pokoi (24.10: raz rampa tu, raz tam; beczka stoi albo nie; rura po ścianie albo nie; naturalność). Dziś zmienność z seeda to tylko ciemne pokoje, migotanie i 2–5 skrzyń/beczek przy ścianach (15h). Propozycja w dwóch warstwach:
  - drobne: w `gen_rooms.py` elementy oznaczone jako opcjonalne (rury, beczki, skrzynie, regały pod ścianą, kable), generator mapy włącza każdy z RNG mapy z jego szansą
  - układ: kilka wariantów sceny tego samego typu (np. biblioteka z rampą na wschodzie albo na zachodzie, magazyn z regałami wzdłuż albo w poprzek, lustrzane odbicie), generator losuje wariant; wariant liczy się do limitu swojego typu (15s)
  - Uwaga: każdy wariant układu musi przejść zasady kamer, mapę pokrycia i test dostępności (kamery stoją pod konkretny układ, przesunięta rampa może zasłonić drzwi). Opcjonalne drobiazgi nie mogą zatkać przejścia (jak skrzynie w korytarzach przy 3,6 m) ani stanąć w polu widzenia kamery na drzwi. Wszystko z RNG mapy (determinizm sieci)
  - Szkielet potwierdzony 25.10: drobiazgi jako `optional(szansa, ...)` w `gen_rooms.py` → węzeł `Geometry/Opt_N` (pod-kombinator CSG z `metadata/chance`), generator mapy usuwa go z RNG mapy; warianty układu przez lustrzane odbicie pokoju w generatorze (bez nowych scen, ten sam typ do limitów)
  - Zrobione (drobiazgi): rury, beczki, skrzynie, palety, kosze, kartony, korytka w 24 scenach, szansa 0,5–0,7 (na przykładowej mapie zostaje 34 z 54). W scenie stoją wszystkie, więc zasady kamer i pokrycie sprawdzają najgorszy przypadek. Nie oznaczone: meble z łupem i kryjówki. `map_test` (determinizm) i podpis mapy w `net_test` uwzględniają, które zostały
  - Zrobione (układ): `MapGenerator.mirror()` – połowa pokoi (poza halą) w lustrzanym odbiciu w osi X. Bez skali -1 (fizyka i kamery jej nie znoszą): każdy węzeł dostaje M·T·M, wielokątom CSG odbijamy profil, `look_target` kamer też; szafki obracają się jako całość. `camera_rules_test` sprawdza każdy pokój w obu wersjach, `map_test` dostępność na mapach z odbiciami, host i klient mają ten sam podpis mapy
  - Nie zrobione: ręczne warianty (np. regały magazynu w poprzek) – dopiero gdy odbicie okaże się za mało
- [x] 15w. Bug (potwierdzony 24.10): w skrzyżowaniu nogi stołu stoją obok blatu. Przyczyna: siatka 2 m (16h) skaluje pozycje wyposażenia, ale nie rozmiary, a każda część mebla jest skalowana osobno. W skrzyżowaniu (10 → 11,6 m, ×1,16) blat ma 3 m długości (±1,5), a nogi przesunęły się na ±1,65. To samo w zakręcie (×1,27); w pozostałych pokojach skala ~0,98, więc przesunięcia są niewidoczne. Dotyczy wszystkich mebli z kilku części (stoły, skrzynka na stole warsztatowym, towar na regałach). Naprawa: skalować tylko punkt zaczepienia mebla, a jego części przesuwać razem z nim; test: części mebla stykają się z blatem
  - Zrobione: `group(...)` w `tools/gen_rooms.py` – mebel z kilku części przesuwa się jako całość (skaluje się tylko pierwsza część, reszta zachowuje odstępy). Zgrupowane: stoły z prześwitem, stoły warsztatowe ze skrzynką, regały z towarem, palety i stos skrzyń. W skrzyżowaniu nogi stoją teraz na ±1,42 pod blatem ±1,5. Zasady kamer i widoczność bez zmian
- [x] 15x. Bug (playtest 25.10): wyważania drzwi nie słychać, powinno być „BUM… BUM… TRZASK” (15p miało to dać, a w grze nie wybrzmiewa). Podejrzani w `props/door.gd`:
  - dźwięk łomotu to Kenney `impactSoft_heavy` (miękkie, ciche puknięcia 0,5 s), a trzask wyłamania to te same metaliczne uderzenia co szyb wentylacyjny (`vent_bangs`), więc nie brzmi jak pękające drewno
  - jeden `AudioStreamPlayer3D` na drzwi: każdy łomot ucina poprzedni, a trzask ucina ostatni łomot
  - domyślne `unit_size` (10) i 0 dB przy `max_distance` 16 m: z sąsiedniego pokoju prawie nic; potwory „słyszą” łomot z 12 m, gracz praktycznie nie
  - łomoty co 0,4 s w 1,2 s zlewają się w jedno, nie ma rytmu „BUM… BUM…”
  - Propozycja: osobne, głośne próbki (ciężkie uderzenie w drewno + trzask drzazg; CC0 z freesound/Sonniss, bo Kenney nie ma takiego), osobny odtwarzacz na trzask, wyższy `unit_size`/`volume_db` i zasięg ~25 m, lekki wstrząs kamery i drgnięcie skrzydła przy każdym łomocie. Rytm: 3 łomoty co ~0,6 s + trzask (wyważenie 1,2 → ~1,8 s)
  - Uwaga: dłuższe wyważanie to więcej czasu na ucieczkę w pościgu, czyli potwór słabszy, a to kłóci się z 47g. Albo zostawić 1,2 s i zagęścić łomoty, ale wtedy „BUM BUM” zleje się w jeden; wolę 1,8 s i nadrobić szybkością potwora (47g)
  - Zrobione 25.10: rytm 3 łomoty co 0,6 s + trzask (wyważenie 1,8 s; nadrabiają to zryw i anty-kiting z 47g). Własne wygenerowane próbki (`tools/gen_sfx.py`: `door_thud` = niskie „bum” skrzydła + stuk desek + brzęk futryny, `door_splinter` = uderzenie, seria trzasków drzazg, upadek skrzydła) zamiast Kenney `impactSoft` i metalicznych `vent_bangs`. Osobny odtwarzacz uderzeń (`unit_size` 6, +4 dB, zasięg 28 m), skrzypienie go nie ucina. Przy łomocie skrzydło drga, a kamera trzęsie się, gdy jesteś do 10 m od drzwi. Do playtestu: czy próbki brzmią jak drewno, czy trzeba szukać CC0
- [x] 15y. Bug (playtest 25.10): przed szafką do chowania stał „klocek”; po wyjściu z szafki gracz utknął w nim i nie mógł się ruszyć. Zasada: tam, gdzie wychodzi się z szafki (`Front`, 1 m przed nią), nie może stać żaden mebel
  - Podejrzani: losowe skrzynie/beczki (15h, `MapGenerator._add_clutter`) raczej nie, bo trzymają 2,8 m od punktu przed szafką. Bardziej prawdopodobne: drobiazgi opcjonalne `Opt_` z `gen_rooms.py` (15v), których nikt nie sprawdza względem szafek, albo meble z samego układu pokoju po lustrzanym odbiciu (15v); skrzynie z łupem (33b) nie, bo nie mają kolizji. Ustalić, w którym pokoju to było (zrzut ekranu / seed z Tab)
  - Propozycja, dwie warstwy: (1) `check_lockers` w `gen_rooms.py` jak `check_grid`: żadna bryła (także `Opt_`) nie przecina strefy ~1×1 m przed szafką, generator nie przejdzie; (2) zabezpieczenie w grze: przy wyjściu z szafki `test_move` w punkcie `Front`, a gdy zajęty, najbliższy wolny punkt z NavMesh obok (tak jak potwór wyciąga gracza), żeby nigdy nie dało się utknąć, cokolwiek tam stanie
  - Zrobione 27.10: obie warstwy. (1) `check_lockers` w `gen_rooms.py`: żadna bryła (także `Opt_`) w kwadracie 1×1 m wokół punktu wyjścia, na wysokości 0,3–1,9 m; generator zbiera wszystkie kolizje i nie przechodzi. Znalazł winowajcę: opcjonalna skrzynka w schowku (Closet) stała w szafce i przed nią, ściśnięta przy ścianie (przeniesiona pod południową ścianę). Przy okazji stół w hali był 0,4 m od wyjścia dwóch szafek (płytszy o 0,2 m). (2) `Player._free_exit`: gdy punkt wyjścia zajęty, najbliższe wolne miejsce na pierścieniach 0,5–1,7 m. Test `hiding_test --case=blocked`
- [x] 33b. Monety lepiej schowane (24.10: „zbiera się jak w pacmanie, za tanie”). Dziś monety leżą na podłodze, a znaczniki na meblach są celowo zsuwane na podłogę (`main._spawn_loot`), plus losowe kupki w każdym pokoju (`coins_per_room`)
  - Propozycja: mniej kupek, ale cenniejszych; część w pojemnikach do przeszukania (szuflady, skrzynie, szafki na akta: E 1–2 s, hałas, czasem puste), część na meblach w zasięgu skoku (do ~1 m), mało na środku podłogi
  - Uwaga: pojemniki muszą być innym rekwizytem niż szafki do chowania (inaczej E przy szafce znaczy dwie rzeczy, a „zajęta” szafka z łupem myli). Przeszukiwanie z hałasem robi z łupu decyzję (czas i ryzyko), a nie spacer. Wartości do strojenia razem z punktacją zero-sum (mniej monet = większe różnice w wynikach)
  - Zrobione 25.10 (szkielet potwierdzony): `LootContainer` = niska skrzynia z wiekiem, spawnuje host przez `LootSpawner` (bez zmian w `gen_rooms.py`), bez kolizji (stawiana po wypieczeniu NavMesh). Stan `opened` synchronizowany na węźle, zawartość zna tylko host; gracz prosi `GameState.request_search`. E 1,5 s, hałas 6 m, komunikat w HUD („Znalazłeś N monet” / „baterię” / „Pusto”). 45% znaczników łupu to skrzynie: 65% monety (2× wartość kupki), 10% bateria, 25% puste. Znacznik na meblu do 1,1 m zostaje na meblu, wyżej spada na podłogę; losowych kupek 1 na pokój zamiast 2, wartości 8–25 zamiast 5–20 (nadal rosną z odległością od hali, do zmiany razem z 34b). Na mapie 20 pokoi: było 50–59 kupek (1180–1490 monet), jest 25–31 miejsc, w tym 9–11 skrzyń (1120–1360 monet). Test `container_test`
  - Przy okazji naprawione: na dużych mapach (20+ pokoi) w testach headless łup nie pojawiał się wcale, bo `navigation_ready` przychodziło po stałych 5 klatkach, zanim mapa nawigacji znała region (`map_get_closest_point` zwracał (0, 0, 0), wszystko odrzucone). Teraz `_bake_navigation` czeka, aż punkt w hali ma właściciela na mapie nawigacji (limit 600 klatek). Czy to dotykało gry z oknem, nie wiadomo (tam klatki są wolniejsze); w playteście sprawdzić, czy na dużej mapie jest łup
  - Do playtestu: czy skrzynie bez kolizji nie wyglądają źle (można przez nie przejść); czy 1,5 s + 6 m hałasu to dobra cena
- [x] 33c. Skrzynie z łupem po playteście 28.10: „rozrzucone byle jak, nie różnią się od mebli bez interakcji, stoją na środku pomieszczeń i można przez nie przechodzić”. Odpowiedź na pytanie z 33b: brak kolizji wygląda źle
  - Przyczyna środka pokoju: skrzynia stoi w punkcie NavMesha najbliższym znacznikowi albo losowemu miejscu z `coins_per_room` (`main._spawn_loot`), a losowe miejsca są w całym wnętrzu pokoju (margines 1,5 m), więc wypadają na środku
  - Propozycja: (1) miejsce: skrzynia dosuwana tyłem do najbliższej ściany albo boku mebla (raycast w 4 kierunkach do ~3 m, obrót wiekiem do pokoju), a gdy nic blisko, zostaje kupka monet zamiast skrzyni; (2) kolizja: `StaticBody3D` + `NavigationObstacle3D` (stawiana po wypieczeniu, więc bez dziury w NavMeshu; przy ścianie i tak prawie nie zawadza); da się na nią wskoczyć (16c); (3) wyróżnienie: inny wygląd niż skrzynie-dekoracje (np. metalowa skrzynka z kłódką/żółtym oznaczeniem), lekki połysk albo podpowiedź „E – przeszukaj” z bliska
  - Uwaga: kolizja na środku przejścia wróciłaby problem zatykania (15y, korytarze 3,6 m), dlatego (1) przed (2): bez dosuwania do ściany nie dawać kolizji. Dosunięcie musi trzymać się z dala od wyjść z szafek (`check_lockers` ich nie widzi, skrzynie są z gry) i od drzwi. Wszystko z RNG mapy, a pozycja liczona tak samo u hosta i klienta (skrzynie spawnuje host, więc i tak synchronizowane). Wygląd do uzgodnienia: sama inna barwa może nie wystarczyć przy stałych kamerach z daleka
  - Pomysł użytkownika (28.10), zamiast powyższego: w tej wersji zrezygnować z przeszukiwania; łup leży tam, gdzie się go szuka w REPO/Amnesii/Lethal Company: na istniejących meblach (półki, szafki, stoły), w kątach i pod ścianą na podłodze, nigdy na środku przejścia. W REPO otwiera się każdą szafkę, więc nie ma wątpliwości, gdzie szukać; u nas jeden mebel do otwarcia wśród identycznych dekoracji jest nieczytelny
  - Uwaga krytyczna: przeszukiwanie (33b) dawało cenę za łup: 1,5 s i 6 m hałasu, czyli decyzję zamiast „pacmana” (24.10). Bez niego tę cenę musi dać miejsce: łup wyżej na meblach (skok 16c), w ciasnych kątach, w ślepych zaułkach dalej od tras, mniej kupek, ale cenniejszych. Inaczej wraca zarzut z 24.10. Do usunięcia: `LootContainer`, `GameState.request_search` i `container_searched`, `container_test`; bateria z pojemników (10%) przechodzi na zwykłe baterie. Zmiana szkieletu (RPC, sceny), wymaga zgody. Wariant pośredni na później: w kolejnej wersji każda szafka/szuflada danego typu do otwarcia (jak w REPO), wtedy czytelność wraca sama
  - Narzędzia: znaczniki `LootSpawns` na meblach już są (`main._spawn_loot` zostawia na meblu do 1,1 m); losowe kupki `coins_per_room` zamienić na kąty/ściany: raycast od punktu w pokoju do najbliższych ścian, punkt ~0,4 m od ściany, preferowane narożniki; z RNG mapy
  - Zrobione 28.10 (wariant użytkownika): skrzynie i przeszukiwanie usunięte (`LootContainer`, `request_search`, `Help.SEARCH`, `container_test`). Łup na meblu ze znacznika (albo 0,35 m bliżej krawędzi, gdy ze środka szerokiego blatu nie sięgnie się z ziemi), a gdy mebel poza zasięgiem, na podłodze obok. Losowe kupki, baterie i klucze: punkt w pokoju dosunięty do najbliższej przeszkody (0,35 m od niej), a gdy w poprzek coś jest do 2 m, w kąt. Każde miejsce przechodzi `main._loot_reachable`: bryła kupki nie przecina świata i nie jest w środku bryły (kolizje CSG są puste w środku, więc osobny test promieniami), leży na czymś, ≥ 1,8 m od przejść, ≥ 1 m od innego łupu, a obok jest punkt NavMeshu z drogą z hali, z którego kapsuła gracza (podejście sprawdzane fizyką, bo NavMesh trzyma się 0,5 m od przeszkód, a gracz ma 0,35 m) sięga walca kupki (do 1,35 m w górę) i widzi łup. Kupki 20–55 (było 13–40 i skrzynie 2×). Na mapie 20 pokoi: 23–37 kupek, 4–7 baterii. Test `loot_reach_test` (3 seedy jako kolejne rundy) sprawdza to niezależnie prawdziwą fizyką i ma kontrolę: podrzucony łup w powietrzu, w podłodze i na środku pokoju musi zostać wykryty
  - Przy okazji naprawione: w kolejnej rundzie `navigation_ready` przychodziło, zanim mapa nawigacji przeliczyła nową siatkę (region miał jeszcze starą, więc sprawdzanie właściciela punktu przechodziło od razu). Łup liczył się na starej mapie: w teście 9 kupek zamiast 21, w tym 2 nie do zebrania. Teraz `_bake_navigation` czeka też na nową iterację mapy
  - Zostaje: łup w celach lochów spada na korytarz przy kracie (przejście do celi ma 1 m, a NavMesh z promieniem 0,5 m do niej nie wchodzi, choć gracz się mieści). Do playtestu: czy kupki w ciemnych kątach nie są za słabo widoczne (ze stałej kamery to kilka pikseli) i czy bez przeszukiwania łup nie jest znowu „za tani”
  - Uwaga: `map_test` nie kompiluje się już na HEAD (`NoiseBus` w `player.gd` przy kompilacji testu, pułapka z CLAUDE.md), niezależnie od tej zmiany

## Chowanie się i ruch (po playteście 23.10)

Problem: meble są za małe i jest mało kryjówek. Przed potworem da się tylko uciekać,
a osaczenie w kącie kończy grę.

Research (jak to robią inni):
- **R.E.P.O.**: chowanie się działa przez kucanie i wślizgnięcie się pod łóżka i długie stoły.
  Pod krzesłem, w szafce czy pod małym stołem potwór łatwo cię dosięgnie. Jeśli potwór już
  cię goni, kryjówka nie ratuje: niektóre potrafią sięgnąć pod mebel i wyciągnąć gracza.
  Najlepiej zerwać kontakt wzrokowy i dopiero wtedy się schować. Zmiana piętra często gubi pościg.
- **Lethal Company**: liczą się hałas i linia wzroku. Kucanie mocno ścisza kroki, a zasłonięcie
  linii wzroku zmniejsza to, co potwór słyszy. Niektóre potwory wypatrzą stojącego/idącego
  od razu, a kucającego i nieruchomego dopiero po czasie.
- **Alien: Isolation vs Outlast**: szafki w Alien nie dają gwarancji (potwór może znaleźć,
  trzeba wstrzymać oddech i nie ruszać się), a w Outlast szafki działały jak „tryb boga”
  i gracze krytykowali to jako przełamanie immersji. Krytyka gatunku: gdy schemat
  „ucieknij i schowaj się” jest zawsze ten sam, robi się nudno, zamiast strasznie.

Wnioski dla nas: kryjówka ma przerwać pościg tylko wtedy, gdy potwór nie widział, jak się
chowasz; kucanie = ciszej i trudniej cię zauważyć; zamiast ślepych kątów pętle wokół mebli.

- [x] 16a. Większe meble: wysokie szafy i regały do sufitu (zasłaniają linię wzroku), długie stoły i łóżka/prycze z prześwitem pod spodem (~0,7 m), „wyspy” mebli na środku pokoi, wokół których da się krążyć przed potworem
- [x] 16b. Kucanie (Ctrl albo C): niższa postać (mieści się pod stołem), wolniej, kroki ~2,5× ciszej, potwór zauważa kucającego z mniejszej odległości; stan synchronizowany po sieci
  - Zrobione: kapsuła 1,0 m (wstać się nie da, gdy nad głową przeszkoda), prędkość 1,1, kroki słychać z 35% odległości, potwór widzi z 60% zasięgu i celuje niżej
- [x] 16c. Skok (Spacja): niski skok na skrzynki i przez przeszkody do ~0,7 m; lądowanie robi hałas
  - Zrobione: skok ~1 m, lądowanie słychać z 7 m (klient zgłasza je hostowi). Uwaga o sterowaniu tank poniżej nadal aktualna: ocenić w playteście
  - Uwaga: swobodny skok kiepsko gra ze sterowaniem tank i stałą kamerą (trudno ocenić odległość, klasyczne RE skoku nie miały). Jeśli w playteście będzie toporny, zamienić na kontekstowe przeskakiwanie przeszkód (Spacja przy niskiej przeszkodzie)
- [x] 16d. Kryjówki: szafki/szafy do wejścia (E), pod stołami i pryczami (kucając). Schowany gracz jest niewidoczny dla wzroku potwora, ale wejście do szafki robi hałas
- [x] 16e. AI vs kryjówki: jeśli potwór widział, jak się chowasz, sprawdza kryjówkę i wyciąga gracza; jeśli nie, przy tropieniu może z pewną szansą zajrzeć do pobliskich kryjówek (bez gwarancji bezpieczeństwa, jak w Alien: Isolation)
- [x] 16f. Kamera przy chowaniu: osobne ujęcie z wnętrza szafki (szpara), a pod stołem zwykłe ujęcie bez „uciekania” kamery (bezpiecznik ma wiedzieć, że gracz jest schowany celowo)
  - Zrobione: szafki (`props/locker.tscn`, 8 sztuk w 5 typach pokoi), stoły z prześwitem 1,1 m (hala, skrzyżowanie, magazyn) jako wyspy do krążenia i kryjówki dla kucającego. Wejście do szafki: E 0,5 s, skrzypnięcie słychać z 5 m. W środku widok przez szpary. Potwór, który widział/słyszał gracza przy chowaniu, otwiera szafkę i atakuje. Inne przy przeszukiwaniu zaglądają do szafki w promieniu 7 m z szansą 10% + 15% za każdą udaną ucieczkę przez schowanie (maks. 70%)
  - Nie zrobione: prycze/łóżka i szafy do sufitu (stoły i szafki na razie wystarczą); ujęcie spod stołu (zostaje zwykła kamera, bezpiecznik może przełączyć)
- [~] 16g. Projekt poziomów pod ucieczkę: mniej ślepych zaułków, częściej pokoje z 2+ wyjściami, pętle przez sąsiednie pokoje; sprawdzić, czy zmiana piętra gubi pościg
  - Zrobione: schowek (ślepy zaułek) losowany rzadziej, skrzyżowanie częściej; generator łączy dwa wolne przejścia w tym samym miejscu w pętlę zamiast je zamurować. Mapa 20 pokoi: 3–6 ślepych zaułków
  - Problem: pętle prawie nie powstają (0 na 10 testowych map), bo wymiary pokoi nie leżą na wspólnej siatce i przejścia rzadko trafiają w ten sam punkt
- [x] 16h. Wymiary pokoi (ze ścianami) jako wielokrotności 2 m, żeby przejścia leżały na wspólnej siatce i pętle mogły powstawać; ewentualnie aktywne domykanie pętli (dobieranie korytarza łączącego dwa bliskie wolne przejścia)
  - Playtest 24.10: pętli dalej w praktyce nie ma, priorytet w górę. Cel do sprawdzenia testem: każda mapa ≥ 20 pokoi ma co najmniej 1–2 pętle (liczone w grafie połączeń), a nie „jest szansa”
  - Uwaga: sama siatka 2 m tylko zwiększy szansę na przypadkowe trafienie. Żeby pętle były gwarantowane, potrzebne jest aktywne domykanie (po złożeniu drzewa szukać par wolnych przejść blisko siebie i dobierać łączący korytarz/zakręt). Siatka ułatwia to domykanie, więc obie rzeczy razem. Zmiana wymiarów pokoi przesuwa współrzędne w testach (`Maps.CLASSIC`) i wymaga ponownego `camera_rules_test`/`coverage_map`
  - Pętle odblokowują zablokowane przejścia z 15 (dopiero wtedy zablokowanie nie odcina części mapy)
  - Zrobione: siatka 2 m w `tools/gen_rooms.py` (`snap_room`, `check_grid`): zewnętrzne wymiary parzyste, przejścia jednego pokoju różnią się o wielokrotność 2 m, wyposażenie skaluje się z pokojem (wnętrza zmalały o 0,4 m, zakręt urósł do 8×8, skrzyżowanie do 12×12). Domykanie pętli w `MapGenerator._close_loops`: łącznik z prostych korytarzy (`Link4`–`Link16`) i do dwóch narożników (`Bend` 4×4), planowany na siatce, wstawiany w trakcie budowy drzewa (wtedy wolnych przejść jest dużo), pętla musi obejmować ≥ 3 przejścia w drzewie. Wariant mapy bez pętli jest odrzucany (od 12 pokoi)
  - Wynik: 10/10 map po 20 pokoi ma 1–2 pętle (wcześniej 0/10), 40 pokoi: 1–4, 60 pokoi: 3–5. Łączniki nie liczą się do liczby pokoi (mapa „20 pokoi” ma ~23–32 elementy). Determinizm sprawdzony testem sieci
  - Ograniczenia: pętle tylko na jednym piętrze; najkrótszy łącznik 4 m (szczelina 2 m zostaje zamurowana)

Źródła: [itemlevel.net: R.E.P.O. hiding guide](https://itemlevel.net/repo-how-to-hide-from-monsters-guide/),
[gfinityesports.com: R.E.P.O. monsters](https://www.gfinityesports.com/article/repo-all-monsters-and-best-strategies-against-them),
[progameguides.com: R.E.P.O. monsters](https://progameguides.com/r-e-p-o/all-monsters-in-r-e-p-o-and-how-to-avoid-them/),
[twinfinite.net: Eyeless Dogs w Lethal Company](https://twinfinite.net/guides/survive-eyeless-dogs-lethal-company/),
[Steam: Forest Keeper w Lethal Company](https://steamcommunity.com/app/1966720/discussions/0/4034727620345009511),
[Steam: kryjówki w Alien: Isolation](https://steamcommunity.com/app/214490/discussions/0/619568192950980912),
[Exploring the Games: hide-and-seek gameplay](https://exploringthegames.substack.com/p/horror-games-hide-and-seek-gameplay)

## Faza 3: sieć

- [x] 16. Menu host/join po IP (ENet), port 7777, do 4 graczy
- [~] 17. Spawn graczy i synchronizacja pozycji, obrotu i latarki. Animacji jeszcze nie ma (brak modelu)
- [x] 18. Kamera tylko dla lokalnego gracza
- [x] 19. Host rozsyła seed i liczbę pokoi, klient składa identyczną mapę i dopiero wtedy dostaje postać. Liczba pokoi ustawiana w menu hosta (3–30)
- [x] 20. GameState z autorytetem hosta (HP, życie graczy), host rozsyła pełną kopię przez RPC. Żądania klient→host dojdą, gdy będzie co żądać (np. bandaż)

## Faza 4: potwór (baza)

- [x] 21. Potwór-kapsuła u hosta, patrol po NavMesh (losowe punkty na poziomie podłogi), replikowana pozycja i stan, wykrywanie utknięcia
- [x] 22. Noise bus (autoload `NoiseBus`, tylko u hosta). Kroki 4 m, bieg 10 m, liczone przez hosta z replikowanej pozycji. Drzwi dojdą, gdy będą drzwi
- [x] 23. Percepcja: słuch (promień hałasu) + wzrok (stożek 120°, raycast). Zasięg wzroku 6 m w ciemności, 14 m na gracza z włączoną latarką
- [x] 24. Maszyna stanów patrol → trop → polowanie → atak → wycofanie (atak na razie bez obrażeń)
- [x] 25. Atak i obrażenia u hosta (35 HP, unik możliwy w czasie zamachu), feedback u klienta (czerwony błysk, wstrząs kamery, oczy potwora rozbłyskują przy zamachu). Tymczasowo: śmierć → respawn po 8 s, do czasu fazy 5
- [x] 26. Sygnały obecności w 3D audio: ciężkie kroki potwora (16 m), oddech z bliska (7 m, głośniejszy w pościgu), warczenie przy starcie pościgu, świst zamachu, kroki graczy, dźwięk trafienia. Słuchacz przy postaci, obrócony jak kamera. Dźwięki: Kenney (CC0) + oddech/warczenie generowane (`tools/gen_sfx.py`, placeholder)
- [x] ~~27. Wariant „niewidzialny” z mignięciem przed atakiem~~ (odrzucone)

## Faza 5: krew i ranni

- [x] 28. Krwawienie: 60% trafień otwiera krwawienie, −2 HP/s aż do zatamowania albo śmierci (timer bleed-out po powaleniu w 30)
- [x] 29. Bandaż: 2 na start, H (trzymaj 2 s) opatruje siebie, E przy krwawiącym koledze opatruje jego (zużywa bandaż pomagającego). Klient prosi, host sprawdza
- [x] 30. Powalenie (0 HP), wykrwawienie po 30 s, podnoszenie przez kolegę (trzymaj E 3 s, wstaje z 30 HP), potwór dobija powalonych. Tymczasowo: gdy zginą wszyscy, reset po 5 s (do fazy 6)
- [x] 31. Ślady krwi: krople co 0,7 m za krwawiącym, kałuża przy powalonym, rozbryzg przy trafieniu. Host decyduje i rozsyła, każdy rysuje decale (widoczne z każdej kamery, lekko świecą). Nowy gracz dostaje dotychczasowe ślady, reset rundy je czyści
- [x] 32. Potwór idzie po krwi: wyczuwa krople do 90 s wstecz w promieniu 5 m, idzie od kropli do coraz świeższych (stan TRACK), na końcu śladu się rozgląda; zobaczenie gracza przerywa tropienie

## Faza 6: pętla rundy

Ustalenia (23.10):
- Znaleziska to monety. Każdy gracz ma licznik monet niesionych w tej rundzie.
- Śmierć = utrata niesionych monet (wypadają na ziemię, koledzy mogą je zgarnąć).
- Punktacja zero-sum: wynik ocalałego = 50% monet, które sam wyniósł + równy udział
  w 50% wspólnej puli wszystkich ocalałych. Jedna osoba, która się wydostanie, bierze
  całą pulę. Proporcja to jedna stała (`SHARED_FRACTION`).
- Runda kończy się, gdy każdy gracz zginie albo się wydostanie. Bez twardego limitu czasu.
- Zamiast limitu: narastająca trudność. Co kilka minut (dłużej na większych mapach) nowy
  potwór z własnym gniazdem daleko od graczy, a dotychczasowe mają ostrzejsze zmysły.
- Intencja (23.10): zero-sum ma być dylematem. Samemu można zarobić więcej, ale trudniej
  przetrwać (nikt cię nie podniesie, nie opatrzy, nie odbije z rąk Porywacza).
- Uwaga (dziura w obecnej formule): kto wyjdzie wcześnie, i tak dostaje udział w monetach
  wyniesionych później przez innych, więc najbezpieczniej jest wyjść od razu i czekać na pulę.
  To psuje dylemat. Propozycja: udział w puli tylko z monet wyniesionych do chwili twojego
  wyjścia (kto wychodzi pierwszy, nie korzysta z ryzyka reszty).
- [x] 35b. Podział puli: każdy oddaje 50% wyniesionych, a jego część dzielą po równo on i ci, którzy wyszli PO nim. Kto wychodzi pierwszy, nie korzysta z ryzyka reszty; kto zostaje najdłużej, zbiera najwięcej. Zaokrąglanie zachowuje sumę (`tests/score_test.gd`)
- Uwaga (ryzyko): przy zero-sum śmierć kolegi zwiększa twój udział, więc podnoszenie
  powalonego jest ekonomicznie wbrew twojemu interesowi. To zgodne z filarem
  „współpraca vs chciwość”, ale może premiować porzucanie drużyny. Jeśli w playteście tak
  wyjdzie: bonus do puli za wyjście całą drużyną.
- Uwaga: czas między kolejnymi potworami trzeba stroić playtestem; start 3 min + 15 s
  na pokój (8 pokoi = 5 min).

- [x] 33. Monety: kupki na znacznikach i w losowych miejscach pokoi (cenniejsze dalej od hali), podnoszenie wejściem, licznik w HUD, kroki do 2x głośniejsze przy 300 monetach. Śmierć = monety wypadają kupką na ziemię
- [x] 34. Ekstrakcja: winda w hali (zielona futryna, trzymaj E 2 s), wydostany/martwy gracz ogląda kamery żyjącego kolegi (Tab = następny)
- [x] 34b. Winda nie w hali, tylko losowo na mapie zamiast drzwi (pomysł 25.10): gracze muszą ją znaleźć, żeby w ogóle się uratować. Hala zostaje strefą startową
  - Propozycja: winda jako rodzaj przejścia (jak drzwi, 15l), wstawiana przez generator w wolne przejście, które dziś dostaje zaślepkę (ślepy zaułek). Warunki: daleko od hali (np. ≥ 60% najdłuższej drogi), osiągalna bez kluczy (już zapisane w 15m), nie w ciemnym pokoju jako jedyna droga (41b), z RNG mapy (determinizm sieci)
  - Szkielet (do potwierdzenia przed implementacją): winda przestaje być częścią sceny hali, staje się elementem `Doorways` wybieranym przez generator; zmienia kontrakt pokoju i `MapGenerator`
  - Uwaga (pętla rundy): dziś pętla to „wyjdź z hali, zbierz, wróć” jak w LC; po zmianie to „szukaj wyjścia, zbierając po drodze”. Lepiej pasuje do horroru, ale zmienia kilka rzeczy naraz: (a) monety są cenniejsze dalej od hali (33), więc najlepszy łup leży koło windy i problemu „ryzyko powrotu z łupem” już nie ma; trzeba wartość liczyć od windy albo od obu końców; (b) kto pierwszy trafi na windę, może od razu wyjść, a reszta nie wie, gdzie jest (bez mapy i przy stałych kamerach); potrzebna poszlaka: dźwięk windy (dzwonek co ~30 s, słyszalny z daleka), światło widoczne przez drzwi albo odliczanie, gdy ktoś do niej wejdzie; (c) bez limitu czasu i z rosnącą liczbą potworów (36b) mapa, na której nikt nie znajduje windy, kończy się wybiciem drużyny; zabezpieczenie: po kilku etapach winda zaczyna dzwonić głośniej albo pojawia się druga
  - Uwaga: potwór startuje w najdalszym pokoju (13), czyli często obok windy; to może być fajne (ostatni odcinek najgroźniejszy), ale trzeba to świadomie zdecydować. Test menu „teleport do windy” zadziała bez zmian
  - Ustalone 25.10: winda w dowolnym wolnym przejściu (nie musi być daleko od hali), może być za zakluczonymi drzwiami i za ciemnymi pokojami. Bez poszlak i bez zabezpieczeń: znalezienie windy ma być trudne, a to, że reszta drużyny nie wie, gdzie jest, to zaleta („pikanteria”). Potwór startujący obok windy: zostaje. Monety totalnie losowo po mapie, wartość niezależna od odległości (zmiana w 33)
  - Uwaga: „za kluczami” wymaga, żeby kluczy osiągalnych bez przechodzenia przez zakluczone drzwi wystarczyło na drogę do windy (dziś generator liczy klucze tylko dla osiągalnej części mapy), inaczej mapa jest nie do przejścia. Winda tuż obok hali zdarzy się czasem i da łatwą rundę; skoro losowo, to akceptujemy. Bez zabezpieczenia runda, w której nikt nie znajdzie windy, kończy się wybiciem przez kolejne potwory (36b); obserwować w playteście, czy to frustruje
  - Ustalone 25.10 (monety): „losowo” znaczy bez reguły „im dalej od hali, tym gęściej i cenniej”. Miejsca dalej jak w 33b: czasem podłoga, czasem meble, schowki/pojemniki, stoły. Bez konfliktu z 33b
  - Zrobione 27.10: winda to już nie element sceny hali. Generator (`MapGenerator._place_elevator`) wybiera z RNG mapy pokój z wolnym przejściem (poza halą; hala tylko w ostateczności), potem jego przejście, i stawia tam windę zamiast zaślepki (`Room.add_elevator`: zaślepka + stalowe drzwi w zielonej futrynie + znacznik `ExitPoint/Exit` 0,8 m przed nimi). Losowanie najpierw pokoju: przy losowaniu samych przejść winda w 9 na 10 map lądowała w skrzyżowaniu korytarzy. Monety: 13–40 bez mnożnika odległości (średnio tyle co dawniej). Klucz, który nie znalazł miejsca w 10 próbach, ląduje przy środku pokoju (winda za zakluczonymi drzwiami nie może zostać bez klucza). `map_test` sprawdza, że winda jest i da się do niej dojść; spec zaktualizowany
  - Uwaga: zielona futryna świeci też w ciemnym pokoju, więc windę widać z daleka, gdy już jest w kadrze. To nie poszlaka na odległość (nie słychać jej, nie ma jej na HUD), ale jeśli ma być trudniej, futryna może gasnąć razem z pokojem
  - Przy okazji: `container_test` bywał czerwony (łup losował się z losowego seeda; czasem 0 skrzyń). Naprawione: stały seed, a gdy brak skrzyni, test stawia ją sam. `debug_menu_test` zapisuje zrzut do katalogu tymczasowego systemu (miał na sztywno ścieżkę ze starej sesji)
- [x] 35. Punktacja zero-sum (`GameState.SHARED_FRACTION`) i ekran podsumowania (wynik rundy + suma sesji)
- [x] 36. Następna runda z nowym seedem (host: R albo przycisk); suma sesji zostaje. Reset po wybiciu wszystkich zastąpiony końcem rundy
- [x] 36b. Narastająca trudność: co etap (3 min + 15 s na pokój) nowy potwór w pokoju najdalszym od graczy (maks. 4), wszystkie zmysły +10% na etap; ryk i napis w HUD
- [ ] 36d. Pomysł (28.10): kolejność kolejnych potworów losowa, ale pierwszy zawsze Łowca. Dziś stała: `MonsterDirector.SPAWN_ORDER` = Łowca, Strażnik, Rzeźnik, Porywacz, Obserwator (`stage % 5`)
  - Uwaga: losować bez powtórzeń (przetasować 4 pozostałe typy na początku rundy), inaczej przy maks. 4 potworach mogą wyjść dwa Rzeźniki, a jakiegoś typu nie będzie wcale. Wtedy przy 4 potworach jeden typ z pięciu zawsze odpada, co rundę inny: to raczej plus (runda czuje się inaczej)
  - Uwaga: kolejność dziś działa jak krzywa trudności (Strażnik jako drugi jest łagodny, bo pilnuje gniazda, a Obserwator na końcu tylko wzywa resztę). Losowo drugim potworem może być od razu Rzeźnik albo Porywacz, czyli skok trudności w 2. etapie. Jeśli to za dużo: losować w obrębie „łagodnych” i „groźnych” albo zakazać Obserwatora jako jedynego obok Łowcy
  - Technicznie: tylko host losuje (potwory spawnuje host, klienci dostają je przez sieć), więc `randf()` wystarczy; dla powtarzalności testów lepiej RNG z seeda mapy. Testy `monster_types_test` i `debug_menu_test` zakładają dziś konkretną kolejność, trzeba je dostosować
- [ ] 36c. Sklep między rundami (pomysł 23.10): za zebrane monety powerupy, np. mocniejsza latarka / dłuższa bateria, więcej bandaży na start, szybsza postać. Etap ma zostać elastyczny na przyszłość
  - Szkielet (do potwierdzenia): przedmiot sklepu = plik danych (id, nazwa, cena, efekt, wartość), efekty = modyfikatory gracza; nowy powerup to nowy plik, nie nowy kod (jak profile potworów)
  - Ustalone 23.10: dwa liczniki. Punkty (ranking) = monety rozdzielone zasadami zero-sum, tylko rosną. Portfel = te same zdobyte monety do wydania w sklepie; wydawanie nie zmniejsza punktów
  - Uwaga: przez to zawsze opłaca się wydać wszystko (znika dylemat „wydać czy trzymać”), a lider ma i więcej punktów, i więcej ulepszeń
  - Otwarte: kula śnieżna. Rosnące ceny odrzucone (rosną wszystkim albo karzą tylko lidera, co nie ma sensu przy proporcjonalnych wydatkach). Opcje do przemyślenia: ulepszenia jednorazowe na następną rundę (nie kumulują się; faworyt), limit ulepszeń na rundę, zniżka/bonus dla ostatniego w rankingu, wspólna kasa drużyny
  - Na horyzoncie (23.10): może kula śnieżna to po prostu cecha (więcej monet = więcej punktów i mocniejszy gracz). Ryzyko: w długich sesjach ostatni w rankingu tracą motywację po kilku rundach; przy krótkich może nie przeszkadzać. Decyzja po playtestach sklepu
  - Uwaga: szybkość jest krucha (bieg 4,6 m/s vs pościg 3,8 m/s); już +15% robi z ucieczki formalność, więc małe kroki albo wcale
  - Ulepszenia na razie tylko w obrębie sesji (nie ma zapisu postępu między uruchomieniami)
- [ ] 37. Checkpoint MVP: playtest we dwóch

## HUD (po playteście 23.10)

- [x] Menu testowe (klawisz `, `game/debug_menu.gd`) zamiast klawiszy F (łatwo dokładać kolejne narzędzia: jedna linia w `_build_actions`). Tylko host, tylko build deweloperski albo `-- --cheats`. Na start: spawn każdego typu potwora w pokoju obok, następny etap, zamrożenie i usunięcie potworów, nieśmiertelność, leczenie, +100 monet, teleport do windy

- [x] Stały status w lewym górnym rogu: tylko HP, monety, bandaże i bieżące komunikaty, mniejsza czcionka z obrysem
- [x] Statystyki pod przytrzymanym Tab: sekcje Gracze (tabela), Runda, Sieć, Sterowanie; debug (ujęcie, stany potworów) tylko po F1. Uwaga: stany potworów graczom zdradzałyby za dużo, więc są tylko w debugu
- [x] Konflikt klawiszy: Tab przełączał podgląd kolegi po śmierci, teraz robi to Spacja (martwy i tak nie skacze)
- [x] Debug potworów (Tab + F1): tabela typ / stan / dystans / pokój / wzrok / słuch / zagrożenie / cel reżysera oraz dane reżysera (etap, czas do następnego potwora, szansa sprawdzania szafek, gniazdo strażnika). Część danych tylko u hosta. Na prośbę użytkownika debug domyślnie włączony (F1 chowa)

## Światło, latarka, krwawienie (pomysły 23.10, do zrobienia)

- [x] 41a. Krwawienie widać na ekranie: pulsująca czerwona winieta w rytmie utraty HP (1/s), intensywność rośnie, gdy HP spada; przy każdym ubytku bardzo lekki wstrząs, wyraźnie słabszy niż po ciosie potwora
  - Uwaga: ciągłe trzęsienie przy stałych kamerach męczy i utrudnia czytanie kadru, dlatego wstrząs tylko przy ubytku i słaby
  - Potwierdzone 23.10: pulsowanie OK
- [x] 41b. Ciemniej: ~20% pomieszczeń całkiem ciemnych (losowane z seeda, zamiast obecnych 10% zgaszonych lamp), reszta jak teraz
  - Zrobione: `MapGenerator.DARK_ROOM_CHANCE = 0.2` (hala zawsze jasna), w jasnych pokojach 20% lamp migocze. Pomiar na 10 mapach × 20 pokoi: 25% ciemnych. Nie pilnuje jeszcze, żeby ciemny pokój nie był jedyną drogą do windy
  - Potwierdzone 23.10: 20% ciemnych pokoi (pustość wynikała z ciemności wszędzie, teraz kontrast); proporcja do strojenia po testach, jedna stała
  - Uwaga: kłóci się częściowo z 15g (pokoje wyglądały na puste, bo w ciemności nie było widać mebli; światło podbite o 30%). Dlatego kontrast między pokojami zamiast równego przyciemnienia wszystkiego. Ciemny pokój nie powinien być jedyną drogą do windy, a przynajmniej nie bez baterii w zasięgu
- [x] 41c. Bateria latarki: ograniczony czas świecenia (np. 4–5 min), migotanie przy słabej baterii, baterie do znalezienia na mapie (nowy typ znaleziska obok monet), podniesienie doładowuje
  - Uwaga: rozładowana latarka + ciemny pokój = ślepota, która frustruje zamiast straszyć; liczba baterii i ciemnych pokoi do strojenia razem. Wzmacnia istniejący dylemat (latarka = potwory widzą cię z 14 m zamiast 6 m). Naturalny kandydat do podawania przedmiotów (43)
  - Zrobione 25.10: 270 s świecenia (4,5 min), liczy host w `GameState` (`battery`, jak HP), zużycie tylko przy włączonej latarce. Poniżej 20% latarka przygasa i rwie się coraz częściej, pusta gaśnie i nie da się jej włączyć. Baterie na mapie (`BatteryPickup`, jak klucz): jedna na 4 pokoje, +135 s, gracz z pełną baterią jej nie podnosi (zostaje dla kolegi). W HUD „bateria N%”. Menu testowe: „Bateria latarki: 15 s”. Test `battery_test`. Strojenie (czas, liczba baterii vs 20% ciemnych pokoi) w playteście

## Faza 7: napięcie i niepewność

- [x] 38. Rozmyty „poziom zagrożenia” (`fx/tension_audio.gd`): ambient gaśnie, wchodzą serce (szybsze przy większym zagrożeniu) i oddech. Liczony z odległości do potworów (pościg i szyb nad głową liczą się mocniej), z falującym mnożnikiem i opóźnieniem, żeby nie był radarem
- [x] 39. Fałszywe alarmy z `AmbientPoints` (`game/fake_alarms.gd`): co 12–28 s skrzypnięcie / łomot / metaliczny stuk / kroki jak potwora, 6–20 m od losowego gracza, u wszystkich w tym samym miejscu; bliski alarm podbija serce
- [~] 40. Strojenie proporcji: parametry wystawione (`FakeAlarms.weights`, interwały, promienie w `TensionAudio`), prawdziwe strojenie wymaga playtestu

## Faza 8: po MVP

- [ ] 41. Steam lobby (GodotSteam)
- [ ] 42. Proximity voice chat, hałas z głosu dla potwora
- [ ] 43. Podawanie przedmiotów, role w ekwipunku
- [ ] 44. Wleczenie ciał przez potwora + ślad
- [ ] 45. Punktacja co-op vs solo
- [x] 46. Spectator przez kamery żyjących graczy (było już zrobione przy pętli rundy: `main._update_spectating`, martwy albo wydostany gracz ogląda kamery żyjących; status poprawiony 27.10)
- [ ] 47. Kolejne typy potworów (patrz niżej)

### Potwory: abstrakcja

Różne potwory = kombinacja wymiennych części zamiast jednej klasy z flagami.
Skeleton (interfejsy części) do potwierdzenia przed refaktorem `Monster`.

Ustalone: dwie warstwy AI dla wszystkich typów. **Reżyser** (host) decyduje zgrubnie,
dokąd potwór ma iść (rewir, okolica graczy, odesłanie daleko). **Zmysły** potwora szukają
gracza lokalnie i każdy typ ma je inne. Nie każdy potwór poluje: reżyser może też tylko
przydzielić rewir do pilnowania.

- [x] 47a. Reżyser (`game/monster_director.gd`) + profile danych (`MonsterProfile`, `monster/profiles/*.tres`). Ruch/zmysły/zachowanie/atak to na razie pola profilu i gałęzie w `monster.gd`, nie osobne węzły; rozbić na komponenty, gdy dojdzie zachowanie, które się w to nie mieści (np. chodzenie po ścianach)
- [ ] 47b. Ruch: po podłodze (NavMesh, jest) i po ścianach/suficie
- [x] 47c. Zachowania: patrol i „Obserwator” (stoi, rozgląda się, krzyczy przy zobaczeniu gracza: hałas ściąga inne potwory, bliskiego atakuje)
- [x] 47c2. Zachowanie „strażnik”: pilnuje swojego rewiru (przydziela go reżyser) i zajmuje się swoimi sprawami, dopóki gracz nie podejdzie blisko; wtedy reaguje, a po ucieczce gracza wraca na rewir
  - Pomysł (23.10): strażnik zmienia miejsce, robi gniazda w różnych pokojach. Uwaga: jego sens to przewidywalny rewir; częste przenosiny zrobiłyby z niego wolnego patrolowca. Zrobione jako kompromis: przenosi gniazdo co 3–4 min do pokoju 12–40 m dalej i ≥15 m od graczy, nowe gniazdo zostawia ślad krwi na podłodze (poszlaka dla graczy)
- [x] 47c3. Typ potwora = zestaw właściwości (profil danych, np. Resource w Godocie), nie osobna klasa. Na start: prędkości (patrol, pościg), sposób poruszania (podłoga / ściany / sufit / wentylacja), czy porywa, obrażenia przy porwaniu (na sekundę), obrażenia zwykłego ataku, strategia ataku, ostrość wzroku i słuchu (zasięg i czułość, 0 = brak zmysłu). Nowy potwór to głównie nowy profil + model. Nie kopiujemy potworów 1:1 z innych gier (np. ślepy pies z LC to tylko przykład kombinacji „bez wzroku, świetny słuch”)
- [x] 47c5. Atak egzekucyjny jako opcja profilu (Rzeźnik: ślepy, świetny słuch, zabija od razu, rozbryzg na podłodze i ścianie): natychmiastowe zabicie bez powalenia i bez możliwości odratowania, z dużą plamą krwi na ścianie/podłodze (np. potwór ślepy, ale zabija od jednego trafienia)
- [x] 47c7. Polowanie na słuch: z bliska (7 m × słuch) potwór rozpoznaje, kto hałasuje, i goni go jak widzianego. Bez tego ślepy potwór nigdy by nie zaatakował
- [x] 47c8. Po ciosie łowca nie ucieka (playtest 23.10: wycofanie wygląda bez sensu). Zamiast tego „odzyskiwanie”: stoi ~2,5 s (otrząsa się po zamachu), potem przez kilka sekund goni wolniej. Jako opcja profilu (styl ataku HIT_AND_RECOVER), żeby inne typy mogły zostać przy swoim
  - Zrobione: styl ataku HIT_AND_RECOVER (Łowca): stan RECOVER 2,5 s bez ruchu, potem 4 s pościgu z prędkością ×0,6. Inne typy bez zmian
  - Uwaga: wycofanie dawało trafionemu okno na reakcję (60% ciosów otwiera krwawienie, pościg 3,8 m/s vs chód 2,2 m/s). Odzyskiwanie musi to okno zachować, inaczej jeden cios = śmierć
  - Zostaje: ucieczka spłoszonego Porywacza po odbiciu ofiary
- [x] 47c6. Wentylacja (jak w Alien: Isolation): sieć szybów nad pokojami z kratkami w ścianach/sufitach. Potwory z tą umiejętnością przemieszczają się nią poza wzrokiem graczy i wychodzą z kratek. Słychać je w szybach (dudnienie nad głową = poszlaka). Generator dokłada kratki do modułów i łączy je w sieć; reżyser używa szybów do szybkiego przerzucania potwora
  - Zrobione w wersji uproszczonej: kratka w suficie każdego pokoju, a szyby to abstrakcyjna sieć (prosta linia między kratkami, 6 m/s), bez modelowanych kanałów. Reżyser przerzuca szybami łowcę i porywacza przy dystansie > 20 m. W szybie potwór jest niewidoczny, słychać metaliczne dudnienie (do 14 m), wychodzi zeskokiem z kratki
  - Po playteście: wejście do szybu jest widoczne (stan VENT_CLIMB: potwór przez 1,2 s podchodzi pod kratkę i wciska się w sufit), nie znika już w miejscu
  - Bug z playtestu (naprawiony): potwór wchodził do kratki w innym pokoju. Teraz zawsze bierze kratkę pokoju, w którym stoi, wspina się tylko spod niej (≤ 1,3 m), a gdy nie może dojść, rezygnuje z szybu i idzie normalnie
- [x] 47c9. Lepszy wzrok potworów (playtest 24.10: potwór patrzy na gracza w linii prostej i go nie widzi). Podejrzani w `can_see`: zasięg w ciemności 6–10 m przy pokojach do 20 m (bez latarki gracz na drugim końcu pokoju jest niewidzialny), jeden raycast oko → klatka piersiowa (zasłania go byle skrzynia/krawędź stołu; lepiej kilka punktów: głowa, tors, nogi, widać którykolwiek = widzi), maska `sight_blockers` = warstwa 1 (rekwizyty też blokują), test tylko 10×/s. Najpierw zdiagnozować na konkretnej sytuacji (debug: rysować promień wzroku), dopiero potem stroić
  - Uwaga: nie podnosić po prostu zasięgów. Ciemność i latarka (6 m vs 14 m) to dylemat, na którym stoi 41b/41c; lepiej stopniowe zauważanie z bliska (jak w LC: stojącego od razu, dalej po chwili) niż ślepy potwór albo radar
  - Diagnoza (test na stałej mapie, 288 ustawień gracza w stożku): główna przyczyna to zasięg. W oświetlonym pokoju gracz bez latarki był traktowany jak w ciemności (6 m), więc w jasnym pokoju 10 m przed potworem był niewidzialny. Zasłanianie przez regały/stoły było w większości prawdziwe
  - Zrobione: (1) gracz w oświetlonym pokoju albo z latarką jest widoczny z dalekiego zasięgu (`sight_range_flashlight`), w zgaszonym pokoju bez latarki tylko z bliska (`Room.dark` z generatora); dylemat latarki zostaje w ciemnych pokojach. (2) Stopniowe zauważanie: w bliskiej strefie (zasięg „ciemno”) od razu, dalej potwór musi widzieć gracza 0,1–0,8 s (im dalej, tym dłużej); goniony cel widzi od razu. (3) Trzy punkty ciała (głowa, tors, nogi; kucając dwa) zamiast jednego promienia do klatki piersiowej: wystarczy, że widać którykolwiek
- [x] 47c10. Strażnik goni gracza poza rewir, aż go zgubi, potem wraca do gniazda (teraz po 16 m od gniazda (`leash`) przerywa pościg i wraca, wygląda jakby bał się wyjść z pokoju)
  - Uwaga: to zaciera różnicę strażnik vs łowca. Sens strażnika (47c2) to przewidywalny rewir: wiesz, którędy nie iść. Jeśli goni bez limitu, staje się łowcą, który dodatkowo ma bazę. Propozycja: smycz zostaje, ale długa (np. 30–40 m) albo liczona w czasie pościgu, a po zgubieniu gracza strażnik nie bada śladu (INVESTIGATE), tylko od razu wraca. Do tego wolniej przestaje gonić w rewirze niż poza nim
  - Prawdziwa przyczyna „strachu”: strażnik jest 1,25× wyższy, jego kolizja miała 2,63 m, a drzwi 2,6 m, więc fizycznie utykał w progu własnego pokoju (to też psuło przenosiny gniazda). Teraz kolizja potworów rośnie najwyżej do 2,4 m; wygląd zostaje wyższy (głowa przenika przez nadproże, do poprawy przy modelach/animacjach)
  - Zrobione: smycz 35 m (było 16 m), po zgubieniu gracza strażnik nie bada śladu, tylko wraca do gniazda. Test: goni 33 m od gniazda, po zgubieniu wraca do rewiru (`monster_types_test --case=guard`)
- [ ] 47c4. (może kiedyś) Potwór stacjonarny w stylu barnacle z Half-Life: nie rusza się, łapie gracza, który wejdzie w zasięg
- [ ] 47d. Atak: wręcz (jest), zdalny (pocisk albo efekt na odległość)
- [x] 47e. Atak: porwanie gracza żywcem (jak smoker, jockey i charger w Left 4 Dead 2). Potwór chwyta gracza i zabiera go do swojego gniazda na uboczu (np. najdalszy pokój albo ślepy zaułek). Porwany powoli traci życie już w czasie porwania, a w gnieździe jest powoli zjadany. Koledzy mogą go jeszcze odbić, ale to ciężki moment. Wleczenie zostawia ślad krwi (powiązane z 44)
  - Zrobione: „Porywacz” (profil abductor). Niesie do gniazda −3 HP/s, w gnieździe −7 HP/s, porwany nie ma powalenia. Odbicie: kolega trzyma E przy porwanym 1,5 s, potwór puszcza ofiarę i ucieka na ~11 s
- [~] 47f. Typ „Łowca” (wzorowany na Alien: Isolation). Dwie warstwy AI:
  - **Reżyser** (host, osobny węzeł): zawsze wie, gdzie są gracze, ale nie podaje potworowi ich pozycji. Co jakiś czas tylko kieruje go w okolicę graczy (pokój obok, piętro), a resztę potwór musi znaleźć sam, zmysłami.
  - **Wskaźnik zagrożenia**: rośnie, gdy potwór jest blisko graczy, długo przy nich i może ich szybko dosięgnąć. Po przekroczeniu progu reżyser odsyła potwora daleko (oddech dla graczy), potem znów go przybliża. W co-opie liczony dla grupy, nie dla jednego gracza.
  - **Odblokowywane zachowania**: część zachowań startuje wyłączona i włącza się, gdy gracze często uciekają tą samą metodą (np. po kilku udanych ukryciach w szafkach zaczyna je sprawdzać; po ucieczkach na inne piętro zaczyna tam zaglądać). Daje wrażenie, że potwór się uczy.
  - Reżyser jest wspólny dla wszystkich typów (ustalone); Łowca używa go najaktywniej.
  - Źródła: [Game Developer: The Perfect Organism – The AI of Alien: Isolation](https://www.gamedeveloper.com/design/the-perfect-organism-the-ai-of-alien-isolation), [Game Developer: Revisiting the AI of Alien: Isolation](https://www.gamedeveloper.com/design/revisiting-the-ai-of-alien-isolation)
  - Stan 27.10: reżyser (polecenia co 12 s, odsyłanie), wskaźnik zagrożenia i nauka szafek były już zrobione. Doszła nauka pięter: potwór gubi gracza, który zmienił piętro (> 2,5 m różnicy) → `MonsterDirector.floor_escapes` +1; szansa, że przeszuka okolicę gracza na jego piętrze (do 9 m od niego) zamiast miejsca zgubienia: 0, 25, 50, 75% (maks.). Test `floor_learning_test` (rampa: pierwsza ucieczka się udaje, potem potwór wchodzi na górę i znajduje gracza)
  - Playtest 27.10: „reżyser ociąga się, potwór 40 m ode mnie, za często daleko”. Przyczyny: polecenia tylko co 12 s i tylko dla łowcy/porywacza; po dojściu do celu potwór losował punkt na CAŁEJ mapie i odchodził; po odesłaniu 35 s „oddechu”. Poprawka: reżyser sprawdza co 3 s, a potwór daleko (> 25 m) idący też daleko od graczy dostaje cel od razu; cel 6–16 m od gracza (było 8–22, brak = najbliższy pokój); po dojściu potwór krąży 3 punkty do 8 m od celu; reżyser kieruje też Rzeźnikiem (z wskaźnikiem zagrożenia); oddech 20 s. Test `director_goal_test`
  - Uwaga: to wyraźnie zwiększa nacisk (Rzeźnik dotąd tylko błąkał się po mapie). Jeśli za dużo: dłuższy oddech albo FAR_DISTANCE większe, a nie powrót do losowego patrolu
  - Uwaga: „okolica gracza na jego piętrze” to wiedza reżysera (potwór nie widział, dokąd gracz poszedł). Celowo, jak w Alien: Isolation, ale przy 75% może wyglądać jak oszustwo; stroić w playteście. Zostaje otwarte: inne „nauki” (np. bieg w kółko już jest anty-kitingiem 47g.3, zatrzaskiwanie drzwi 15t)
- [~] 47g. Potwory za słabe (playtest 25.10: łowcę łatwo zgubić, np. biegając wokół fontanny w atrium). Diagnoza z liczb: łowca w pościgu 3,8 m/s, gracz biega 4,6 m/s bez limitu (nie ma wytrzymałości), więc ucieczka zawsze się udaje; pętla wokół przeszkody to klasyczny „kiting”, bo potwór idzie za graczem po NavMesh i nigdy nie skraca drogi.
  - Co robi Alien: Isolation: (1) obcy jest szybszy od biegnącego gracza i zabija od jednego ciosu, więc bieg to ostateczność, a podstawą jest chowanie się; (2) słyszy każdy hałas i od razu idzie prosto na jego źródło; (3) po zgubieniu gracza nie odpuszcza, tylko długo przeszukuje okolicę (zagląda do szafek, pod biurka); (4) reżyser trzyma go blisko graczy, a wskaźnik zagrożenia daje oddech (47f); (5) odblokowywane zachowania: „uczy się” ulubionych sposobów ucieczki; (6) losowość ruchów, nie da się wyuczyć schematu
  - Co robi R.E.P.O.: każdy potwór ma jeden wyraźny „haczyk” i jedną zasadę przeżycia (Huntsman słyszy wszystko, także głos, i strzela z daleka: rozwiązanie to cisza; Robe skrada się, przyspiesza i wpada w szał, gdy patrzysz mu w maskę, pamięta, gdzie się schowałeś, i przeszukuje stoły, łóżka, szafki), a gracz zwykle niesie ciężki łup, który go spowalnia, więc ucieczka ma koszt
  - Co robi Amnesia: The Dark Descent (dopisane 25.10: „jak cię zauważyły, to już było przejebane”): w pościgu potwór jest zwykle szybszy od gracza, więc wybiegać się nie da; ucieczka to zerwać kontakt wzrokowy (drzwi, zakręt, beczka między wami) i schować się, a potwór po kilku sekundach bez kontaktu odpuszcza i znika. Strach robi też to, że nie wolno na niego patrzeć (patrzenie zjada poczytalność: zniekształcenia obrazu), więc nigdy nie wiesz dokładnie, gdzie jest, a muzyka pościgu gra, dopóki cię goni
    - Uwaga: „przejebane” to w dużej mierze wrażenie: w Amnesii ucieczka była możliwa, ale wymagała schowania się, a nie biegu w kółko. To ten sam wniosek co wyżej: potwór szybszy w pościgu, ratunek = zerwanie kontaktu + kryjówka. Zakaz patrzenia nie przeniesie się 1:1 przy stałej kamerze (gracz patrzy kamerą, nie oczami postaci); odpowiednik: zniekształcenie obrazu, gdy potwór jest w kadrze i blisko
  - Propozycje (od najtańszej):
    1. Wytrzymałość na bieg (np. 5–6 s biegu, regeneracja wolniejsza niż zużycie, zadyszka słyszalna dla potworów). Bez tego żadne strojenie prędkości nie pomoże. Pasek w HUD albo tylko dyszenie i zwolnienie
       - Zrobione 25.10: 6 s biegu, odnowa 0,6 s/s po 1 s odpoczynku; po wyczerpaniu zadyszka (tylko marsz, dyszenie słychać z 12 m, dla potworów hałas 5 m co 1 s) do 40%. Liczy właściciel postaci, `winded` synchronizowane. W HUD liczba „kondycja N%” (bez paska; HUD jeszcze do przerobienia). Test `stamina_test`
    2. Łowca w pościgu ≥ prędkość biegu (np. 4,8 m/s) przez pierwsze sekundy pościgu, potem zwalnia (zryw), albo skok/doskok na 3–4 m z krótkim ostrzeżeniem
    3. Anty-kiting: gdy cel krąży wokół przeszkody (droga potwora do celu > 1,6× odległość w linii prostej przez kilka sekund), potwór zawraca i idzie drugą stroną albo staje i czeka, aż gracz wybiegnie mu naprzeciw; ewentualnie celuje w przewidywaną pozycję gracza za 1 s, nie w obecną
       - Zrobione 25.10 (2 i 3): zryw z profilu (`burst_speed`): łowca 4,9 m/s i porywacz 4,8 m/s przez 3 s na początku pościgu, odnowa po 10 s. Anty-kiting inaczej niż w propozycji: przewidywanie w linii prostej nie działało (potwór idzie tuż za graczem, droga ≈ prosta). Potwór pamięta ślad gracza (co 0,25 s, 12 s); gdy gracz wraca w miejsce sprzed ≥ 3 s (pętla), wybiera punkt śladu, do którego zdąży przed graczem, i tam czeka; gracz zawraca = zwykły pościg. Działa też na pętlach korytarzy (16h). Test `kite_test` (bieg wokół fontanny 4,6 m/s bez limitu): bez niczego 30 s bez złapania, sam anty-kiting 6,7 s, z zrywem 2,7 s
    4. Pamięć i przeszukiwanie: po zgubieniu gracza 20–40 s szukania wokół ostatniej pozycji (szafki, nisze, za meblami), a nie powrót do patrolu; reżyser podsuwa pokój obok (47f)
       - Zrobione 25.10: po zgubieniu żywego gracza (z pościgu albo po ciosie) potwór 20–35 s chodzi po losowych punktach do 9 m od miejsca zgubienia, przy każdym rozgląda się 1,5 s i z szansą co najmniej 35% zagląda do pobliskiej szafki; potem patrol. Strażnik bez zmian (wraca do gniazda). Reżyser (47f) jeszcze nie. Test `monster_states_test --scenario=escape`
    5. Ładunek spowalnia: niesione łupy (33b) obniżają bieg (np. −10% na sztukę ponad pierwszą), a upuszczenie robi hałas; ucieczka = wybór między łupem a życiem
       - Odrzucone na razie (27.10): monety to licznik, nie przedmioty w rękach, więc nie ma czego nieść ani upuszczać. Wróci, jeśli łup stanie się fizyczny (np. ciężkie przedmioty jak w LC/R.E.P.O.)
    6. Zapowiedź obecności zamiast zaskoczenia: wyraźny, rozpoznawalny dźwięk każdego typu (kroki, oddech, sapanie) słyszalny zanim go zobaczysz, plus „stinger” muzyczny przy wykryciu. Strach bierze się z czekania, nie tylko z pościgu
       - Zrobione 27.10: w profilu `presence_sound` + `presence_range`; pętla zastępuje wspólny oddech (słyszalny tylko z 7 m). Wygenerowane (`tools/gen_sfx.py`, osobny RNG, stare próbki bez zmian): łowca klekot owada 16 m, rzeźnik zgrzyt wleczenia + łańcuch 18 m (ślepy, więc ma być go słychać), strażnik niskie mruczenie 12 m, obserwator rozstrojony pisk + szept 14 m, porywacz węszenie 14 m. Akcent (`TensionAudio`, lokalnie): potwór do 20 m zaczyna pościg → uderzenie klastra + skok serca, cooldown 15 s. Test `tension_test` (35 m: cisza, 6 m: gra)
       - Uwaga: akcent mówi „ktoś obok został zauważony”, nawet gdy potwora nie widać. To trochę przeciw „niepewności” (pętla 10a/serce celowo rozmyte), ale nie podaje kierunku ani odległości. Jeśli w playteście za dużo zdradza: tylko dla celu pościgu (wymaga synchronizacji celu) albo tylko gdy potwór jest w kadrze. Placeholdery z numpy: do playtestu, czy typy da się rozróżnić z zamkniętymi oczami; jeśli nie, szukać CC0
    7. Każdy typ z jedną czytelną zasadą przeżycia (jak R.E.P.O.): łowca = nie biegaj, chowaj się; rzeźnik = cisza; obserwator = nie wchodź w jego światło; porywacz = trzymajcie się razem
       - Zrobione 27.10: łowca, rzeźnik i strażnik już mieli swoją zasadę w mechanice (kondycja + zryw + przeszukiwanie; ślepota + słuch; smycz i gniazdo); doszły dwie nowe. Obserwator: `searchlight` w profilu: reflektor (SpotLight z cieniami) z oczu, widzi tylko w stożku 70° (było 160°), za to w nim do 20 m także po ciemku. Porywacz: `avoids_groups`: gracza, przy którym stoi żywy kolega (do 5 m, nie w szafce), tylko śledzi z ~7 m (cofa się, patrząc na niego), porywa samotnego. Kolumna „Jak przeżyć” w spec. Testy `monster_types_test --case=searchlight`, `abduct_test --group`
       - Uwaga: porywacz czekający 7 m od pary to czytelne, ale może wyglądać głupio, gdy para stoi w miejscu długo (stoi i patrzy). Jeśli w playteście nudzi: po ~20 s odchodzi i wraca później. Reflektor obserwatora to jedno więcej światło z cieniami na potwora; przy 4 potworach naraz bez znaczenia, ale do 52 (profilowanie)
       - Przy okazji: `monster_states_test --scenario=dodge` kończył się hp=0 (też przed tą sesją): test odskakiwał tylko przy pierwszym zamachu, a przez 20 s potwór bił stojącego gracza. Unik działa; test kończy się teraz po pierwszym ciosie i loguje trafienia jak `sidestep`
  - Uwaga (konflikty): a) Alien jest straszny, bo bieg prawie nie działa, ale tam jest kamera z oczu i pełna kontrola widoku; przy stałej kamerze gracz często nie widzi potwora za plecami, więc potwór zawsze szybszy + zabija na raz będzie frustrujący, nie straszny. Dlatego wolę wytrzymałość (1) i zryw (2) niż stałą przewagę prędkości. b) 47c8 celowo zostawia okno po ciosie (HIT_AND_RECOVER, 2,5 s + wolniejszy pościg); przy szybszym łowcy to okno zostaje, ale trzeba je skrócić, inaczej po ciosie gracz i tak ucieka. c) Wskaźnik zagrożenia z 47f odsyła potwora po dłuższym kontakcie, czyli osłabia go jeszcze bardziej; najpierw 1–4, wskaźnik dopiero gdy potwory będą naprawdę groźne. d) Szybsze potwory + 15t (zatrzaskiwanie drzwi) + 15x (dłuższe wyważanie): stroić razem, w jednym playteście
  - Źródła: [Game Developer: The Perfect Organism](https://www.gamedeveloper.com/design/the-perfect-organism-the-ai-of-alien-isolation), [TechRadar: how smart is Alien Isolation's monster](https://www.techradar.com/news/gaming/design-nightmare-just-how-smart-is-alien-isolation-s-monster-1268919), [R.E.P.O. wiki: Robe](https://repo-2025horror.fandom.com/wiki/Robe), [R.E.P.O. wiki: Monsters](https://repo-2025horror.fandom.com/wiki/Monsters), [Gfinity: R.E.P.O. monsters and strategies](https://www.gfinityesports.com/article/repo-all-monsters-and-best-strategies-against-them), [Wikipedia: Amnesia: The Dark Descent](https://en.wikipedia.org/wiki/Amnesia:_The_Dark_Descent)
- [x] 47h. Cios nie trafia uciekającego (playtest/uwaga 25.10: po wyczerpaniu kondycji łowca podchodzi, zaczyna atak, a gracz i tak wychodzi z zasięgu przed końcem zamachu, bo potwór atakuje w miejscu). Liczby: zamach łowcy 0,6 s, potwór staje (ATTACK zwraca prędkość 0), cios sięga 2 m; gracz idzie 2,2 m/s, więc w czasie zamachu oddala się o ~1,3 m, a atak zaczyna się z 1,4 m: 1,4 + 1,3 > 2,0, czyli zwykły marsz zawsze ucieka. Kondycja (47g.1) tego nie naprawia, bo zadyszka nadal pozwala iść
  - Propozycja: doskok w czasie zamachu: potwór dalej sunie za celem (np. 70–100% prędkości pościgu) i obraca się za nim, a zasięg liczony w chwili ciosu. Wtedy marsz prosto od potwora nie wystarcza; unik nadal działa, ale musi być bokiem/skokiem (zejście z linii: kąt ≥ 70°) albo za przeszkodę/drzwi
  - Uwaga (konflikt): spec obiecuje „widoczny zamach, można odskoczyć” (47c, `monster_states_test --scenario=dodge`) i 47c8 celowo daje okno po ciosie. Doskok nie może zabić uniku, tylko ucieczkę prosto w tył; test dodge musi dalej przechodzić. Stroić razem z 47g (zryw + kondycja): przy zbyt skutecznym doskoku każdy kontakt z bliska = trafienie
  - Zrobione 25.10: na początku zamachu potwór od razu staje przodem do celu, potem sunie w tym kierunku z 90% prędkości pościgu (stop 0,8 m przed celem) i obraca się 10× wolniej niż zwykle; gdy gracz przejdzie przez niego na plecy (potwory i gracze się nie zderzają), obraca się normalnie. Cios to pas przed potworem (zasięg 2 m × szerokość 1,8 m) zamiast stożka 70°, bo stożek z doskokiem łapał też unik bokiem. Wynik (`monster_states_test`, łowca): marsz w tył = trafiony, bieg w tył = pudło, krok w bok = pudło, odskok (dodge) = pudło. Rzeźnik dalej zabija gracza, który na niego wchodzi. Do strojenia w playteście razem z 47g
  - Przy okazji: `monster_types_test --case=nest` bywa niedeterministyczny (strażnik czasem zauważa gracza w hali i idzie za nim, zamiast do nowego gniazda); było tak też przed 47h
- [x] 48. Shader glitcha
  - Zrobione 27.10 (razem z odpowiednikiem „nie patrz na potwora” z Amnesii, 47g): uniform `glitch` w `fx/retro_post.gdshader` (rwanie poziomych pasów, rozjazd RGB, bloki szumu; zmienia się skokowo 14×/s). `fx/monster_glitch.gd` liczy lokalnie: potwór do 8 m od postaci, w kadrze bieżącej kamery i niezasłonięty ścianą (raycast z kamery); siła 1 − odległość/8, narasta szybko, opada wolniej; w szybie wentylacji nie działa. Test `glitch_test`
  - Uwaga: to też poszlaka (glitch = potwór blisko, nawet gdy w ciemności go nie widać). Pasuje do horroru, ale razem z sercem i dźwiękiem obecności może być za dużo podpowiedzi; jeśli tak, liczyć tylko, gdy potwór jest oświetlony
- [ ] 49. Drugi setting

## Faza 9: wykończenie

- [ ] 50. Menu, ustawienia, rebinding, zapis opcji
- [ ] 51. Assety: modele, dźwięki, animacje (Mixamo)
- [ ] 52. Profilowanie na słabym sprzęcie
- [ ] 53. Buildy, Steamworks, zamknięte playtesty
- [ ] 53a. Pomysł (27.10): małe CI na GitHub Actions budujące grę pod Windows, macOS i Linux, do pobrania z GitHuba bez instalowania Godota. Plan: `export_presets.cfg` w repo (teraz go nie ma) z trzema presetami; workflow na push taga `v*` eksportuje headless Godotem 4.7 z szablonami eksportu i wrzuca paczki do **GitHub Release** (Windows `.exe` w zipie, macOS `.app` w zipie, Linux binarka w `.tar.gz`). Szacunek: pół dnia do dnia
  - Uwaga: „artefakty” z Actions to nie to: wygasają (domyślnie 90 dni), do pobrania tylko dla zalogowanych z dostępem do repo, zawsze w zipie. Do rozdawania znajomym służą Releases (stały link, bez logowania przy publicznym repo). Przy prywatnym repo znajomi i tak muszą mieć dostęp
  - Ustalone 27.10: chodzi o Releases, repo jest publiczne (link działa bez logowania). Na razie odłożone, do zrobienia później
  - Uwaga: prawdziwe instalatory (MSI, DMG, AppImage) to osobna robota bez zysku na tym etapie; Godot eksportuje samodzielną aplikację, rozpakuj i graj wystarczy. Pytał o to znajomy z playtestów: do zrobienia na później, nie w pierwszej wersji CI
  - Uwaga (macOS): build niepodpisany i bez notaryzacji (wymaga Apple Developer, 99 USD/rok) Gatekeeper oznaczy jako „uszkodzony”; obejście: `xattr -cr Gierka.app` albo PPM → Otwórz. Windows SmartScreen też ostrzeże. Dla playtestów ze znajomymi do przeżycia, przed 53 (Steam) do rozwiązania
  - Uwaga: eksport może ujawnić rzeczy, które w edytorze działają: pliki ładowane po ścieżce (`load()` ze sklejonego stringa) nie trafią do paczki, jeśli nie są w filtrze eksportu; do sprawdzenia przy pierwszym buildzie
- [x] 54. Łowca nie dobija powalonego (28.10, użytkownik). Profil `finishes_downed` (domyślnie tak, Łowca nie): potwór nie widzi i nie słyszy powalonego, nie trafia go, gdy padł w trakcie zamachu, i ignoruje krew do 2 m od powalonych (bez tego wracał po świeżej kałuży i stał nad ciałem). Test `no_finish_test` (+ `--case=control`: z `finishes_downed` dobija)
  - Uwaga krytyczna: zmienia 30 („potwór dobija powalonych”) dla najczęstszego potwora. Powalenie przez Łowcę przestaje być prawie-śmiercią: kolega ma czas podnieść, a samotny gracz i tak wykrwawia się w 30 s. Ryzyko: mniej strachu przed Łowcą; jeśli tak wyjdzie w playteście, wariant pośredni to dobijanie dopiero po kilku sekundach albo tylko, gdy w pobliżu nie ma nikogo innego do gonienia. Rzeźnik, Porywacz i reszta bez zmian
- [x] 55. Pomysł (28.10, „zrób od razu”): potwory znajdują gracza pod stołem tylko wtedy, gdy wykonają konkretną akcję szukania pod tym stołem. Dziś pod stołem nie ma kryjówki: potwór widzi kucającego normalnie (promienie wzroku na 0,5 i 0,85 m przechodzą pod blatem), nie wchodzi tylko pod blat (16d, 148 w spec)
  - Propozycja: stół jako kryjówka jak szafka: kucający pod blatem jest niewidoczny dla wzroku, chyba że potwór widział, jak tam wchodzi (wtedy wie i szuka). Szukanie: potwór przy przeszukiwaniu (po zgubieniu gracza) czasem schyla się przy stole, 1–1,5 s, czytelna animacja/dźwięk; trafienie = wyciąga albo atakuje. Szansa z tej samej nauki co szafki (47f: każda udana kryjówka podnosi szansę)
  - Uwaga krytyczna: stołów jest dużo więcej niż szafek, a wejście pod stół jest ciche (szafka skrzypi), więc stół byłby najlepszą kryjówką w grze. Potrzebna cena: np. hałas przy wchodzeniu na czworakach, albo szukanie pod stołem częstsze niż w szafkach. Bez reguły „widział, jak wchodzisz” chowanie się w trakcie pościgu przed nosem potwora by działało, a to psuje strach. Wykrycie „pod stołem”: promień w górę z kucającego trafia blat niżej niż 1,2 m
  - Zrobione 28.10: `Player.under_cover()` = kuca i promień w górę trafia coś do 1,3 m. Takiego `can_see` nie widzi, a słuch nie rozpoznaje (hałas nadal przyciąga potwora na miejsce). Nowy stan `Monster.State.PEEK_UNDER` (na końcu enuma): podchodzi do najbliższego punktu NavMeshu, schyla się 1,3 s (pochylenie ciała w biodrach liczone ze stanu, więc klienci też je widzą), gracz pod przykryciem do 1,8 m od zaglądanego miejsca = znaleziony: widzi go do 4 m (blat zasłania promienie z wysokości oczu) i atakuje; wyjście spod stołu kasuje „znalezienie”. Kiedy zagląda: (a) traci z oczu gonionego, który właśnie wszedł pod przykrycie (do 0,5 s, „widział, jak wchodzi”), (b) przy przeszukiwaniu, gdy nie wybrał szafki: najbliższe miejsce pod stołem do 6 m z szansą `hiding_check_chance` (wspólna z szafkami). Miejsca pod stołami liczy reżyser raz na mapę (`cover_points`, siatka 0,75 m, ~15 ms na 20 pokoi). Test `table_peek_test`
  - Nie zrobione z propozycji: hałas przy wchodzeniu pod stół i osobna nauka dla stołów (ucieczka pod stół nie podnosi `hiding_escapes`). Do playtestu: czy stół nie jest teraz za dobrą kryjówką (cicho, wszędzie), czy 1,3 s schylania jest czytelne ze stałej kamery
