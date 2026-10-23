# Progress

Legenda: `[x]` zrobione · `[~]` częściowo / czeka na decyzję · `[ ]` do zrobienia · ~~przekreślone~~ odrzucone

## Decyzje

- [x] Silnik: Godot 4 (4.7, renderer Mobile)
- [x] Sieć: host-client po ENet (później Steam lobby przez GodotSteam). Ruch gracza z autorytetem klienta; potwór, HP, krew i punkty z autorytetem hosta. Kamera, UI i audio feedback lokalnie.
- [x] Kontrakt pokoju: `Geometry`, `Doorways`, `CameraZones` (Area3D + Camera), `LootSpawns`, `AmbientPoints` (patrz `rooms/room.gd`)
- [x] Potwory jako typy: wspólna baza (percepcja, nawigacja, stany) + wymienne zachowania. Szczegóły w „Potwory: abstrakcja” (faza 8), decyzja szkieletowa do potwierdzenia przed refaktorem
- [ ] Liczba graczy (2–4?)
- [x] Sterowanie: tank (camera-relative odrzucone po playteście)

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
- [ ] 10c. Narzędzie w edytorze: wizualizacja martwych pól (miejsca bez pokrycia kamer, miejsca, gdzie postać byłaby zasłonięta)
- [~] 10d. Przewidywalność cięć. Naprawione: ujęcie z bezpiecznika „przyklejało się” (środkowa alejka magazynu pokazywana z narożnika przy wejściu). Teraz wraca do kamery własnej strefy, gdy ta znów widzi gracza. Dalej obserwować w playtestach

## Faza 2: modularne pokoje

- [x] 11. Scena bazowa pokoju według kontraktu (NavMesh liczony dla całej mapy, nie per pokój)
- [x] 12. Generator: pokoje doklejane po `Doorways` (obrót o 90°, test kolizji AABB), deterministyczny z seeda, przy zablokowaniu próbuje kolejnych wariantów seeda. 8 typów pokoi, w tym rampa i klatka schodowa (piętra co 3 m)
- [x] 13. Zaślepki niepołączonych drzwi, hala jako strefa startowa (PlayerSpawns), potwór startuje w najdalszym płaskim pokoju
- [x] 14. Nawigacja wypiekana w runtime dla wygenerowanej mapy (2 klatki po złożeniu)
- [ ] 15. Modyfikacje z seeda: loot, zablokowane przejścia, światła

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
- [ ] 15h. Drobne rekwizyty losowane z seeda (część kroku 15): ten sam typ pokoju wygląda za każdym razem trochę inaczej

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

- [ ] 16a. Większe meble: wysokie szafy i regały do sufitu (zasłaniają linię wzroku), długie stoły i łóżka/prycze z prześwitem pod spodem (~0,7 m), „wyspy” mebli na środku pokoi, wokół których da się krążyć przed potworem
- [ ] 16b. Kucanie (Ctrl): niższa postać (mieści się pod stołem), wolniej, kroki ~2,5× ciszej, potwór zauważa kucającego z mniejszej odległości; stan synchronizowany po sieci
- [ ] 16c. Skok (Spacja): niski skok na skrzynki i przez przeszkody do ~0,7 m; lądowanie robi hałas
- [ ] 16d. Kryjówki: szafki/szafy do wejścia (E), pod stołami i pryczami (kucając). Schowany gracz jest niewidoczny dla wzroku potwora, ale wejście do szafki robi hałas
- [ ] 16e. AI vs kryjówki: jeśli potwór widział, jak się chowasz, sprawdza kryjówkę i wyciąga gracza; jeśli nie, przy tropieniu może z pewną szansą zajrzeć do pobliskich kryjówek (bez gwarancji bezpieczeństwa, jak w Alien: Isolation)
- [ ] 16f. Kamera przy chowaniu: osobne ujęcie z wnętrza szafki (szpara), a pod stołem zwykłe ujęcie bez „uciekania” kamery (bezpiecznik ma wiedzieć, że gracz jest schowany celowo)
- [ ] 16g. Projekt poziomów pod ucieczkę: mniej ślepych zaułków, częściej pokoje z 2+ wyjściami, pętle przez sąsiednie pokoje; sprawdzić, czy zmiana piętra gubi pościg

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

- [ ] 33. Znaleziska: podnoszenie, mało slotów
- [ ] 34. Wyjście i ekstrakcja ze strefy startowej
- [ ] 35. Prosta punktacja i ekran podsumowania
- [ ] 36. Restart rundy z nowym seedem
- [ ] 37. Checkpoint MVP: playtest we dwóch

## Faza 7: napięcie i niepewność

- [ ] 38. Rozmyty „poziom zagrożenia”: ambient gaśnie, wchodzą serce i oddech
- [ ] 39. Fałszywe alarmy z `AmbientPoints`
- [ ] 40. Strojenie proporcji sygnałów prawdziwych i fałszywych

## Faza 8: po MVP

- [ ] 41. Steam lobby (GodotSteam)
- [ ] 42. Proximity voice chat, hałas z głosu dla potwora
- [ ] 43. Podawanie przedmiotów, role w ekwipunku
- [ ] 44. Wleczenie ciał przez potwora + ślad
- [ ] 45. Punktacja co-op vs solo
- [ ] 46. Spectator przez kamery żyjących graczy
- [ ] 47. Kolejne typy potworów (patrz niżej)

### Potwory: abstrakcja

Różne potwory = kombinacja wymiennych części zamiast jednej klasy z flagami.
Skeleton (interfejsy części) do potwierdzenia przed refaktorem `Monster`.

- [ ] 47a. Rozbicie `Monster` na części: ruch, percepcja, zachowanie, atak
- [ ] 47b. Ruch: po podłodze (NavMesh, jest) i po ścianach/suficie
- [ ] 47c. Zachowanie: patrol (jest) i „obserwator” (stoi w miejscu i patrzy, nie patroluje)
- [ ] 47d. Atak: wręcz (jest), zdalny (pocisk albo efekt na odległość)
- [ ] 47e. Atak: porwanie gracza (chwyta i odciąga; powiązane z 44, wleczenie ciał)
- [ ] 48. Shader glitcha
- [ ] 49. Drugi setting

## Faza 9: wykończenie

- [ ] 50. Menu, ustawienia, rebinding, zapis opcji
- [ ] 51. Assety: modele, dźwięki, animacje (Mixamo)
- [ ] 52. Profilowanie na słabym sprzęcie
- [ ] 53. Buildy, Steamworks, zamknięte playtesty
