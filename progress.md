# Progress

Legenda: `[x]` zrobione · `[~]` częściowo / czeka na decyzję · `[ ]` do zrobienia · ~~przekreślone~~ odrzucone

## Decyzje

- [x] Silnik: Godot 4 (4.7, renderer Mobile)
- [x] Sieć: host-client po ENet (później Steam lobby przez GodotSteam). Ruch gracza z autorytetem klienta; potwór, HP, krew i punkty z autorytetem hosta. Kamera, UI i audio feedback lokalnie.
- [x] Kontrakt pokoju: `Geometry`, `Doorways`, `CameraZones` (Area3D + Camera), `LootSpawns`, `AmbientPoints` (patrz `rooms/room.gd`)
- [x] Potwory jako typy: wspólna baza + wymienne części. Dwie warstwy AI: **reżyser** (zgrubna nawigacja: dokąd iść, wspólny dla wszystkich typów) i **zmysły** (lokalne szukanie gracza, inne dla każdego typu). Szczegóły w „Potwory: abstrakcja” (faza 8). Interfejsy części do potwierdzenia przed refaktorem
- [~] Liczba graczy: teraz maks. 5 (`MAX_CLIENTS := 4` w `net/network.gd`, 5 spawnów w hali; podniesione z 4 na prośbę 23.10, bez zmian w balansie). Pomysł (23.10): nawet 10. Technicznie łatwe (stała + więcej spawnów), ale balans jest pod 2–4: liczba potworów (maks. 4), monet i tempo etapów; przy 10 ocalałych udział w puli zero-sum jest znikomy. Rekomendacja: 6–8 i skalowanie trudności z liczbą graczy (do decyzji)
- [x] Sterowanie: tank (camera-relative odrzucone po playteście)

## Kolejność prac (ustalona 24.10)

1. 47c9 wzrok potworów → 2. 47c10 strażnik goni poza rewir → 3. 16h siatka 2 m + domykanie pętli →
4. 15i/15j prawdziwe korytarze → 5. 15l–15n drzwi (zwykłe + kratka, potwory, klucze) → 6. 15k nowe pokoje (lochy, hol, biblioteka).
Potem 41c bateria, 36c sklep, 37 MVP.

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

- [ ] 15i. Prawdziwe korytarze: zakręt L, T i X w kształcie korytarzy 4 m szerokości (ramiona, nie kwadratowa sala z drzwiami); obecne kwadratowe zostają jako osobne pokoje
- [ ] 15j. Proporcje: wyraźnie więcej korytarzy niż pokoi, pokoje raczej „przechodnie” jak w Alone in the Dark. Mierzyć w teście (udział korytarzy w mapie), nie tylko wagami
- [ ] 15k. Nowe pokoje:
  - Biblioteka: okrągła rotunda, antresola z regałami, stoliki na dole, kolumny pod antresolą, duży świetlik (w stylu zamku Dimitrescu z RE Village)
  - Lochy: korytarz z celami po bokach (klimat Amnesii); cele jako kryjówki/ślepe zaułki, kraty przepuszczają wzrok
  - Wielki hol (jak w Amnesii, np. z fontanną)
  - Kandydaci z LC: serwerownia, magazyn z pomostami, maszynownia
- Uwaga (spójność): biblioteka, lochy i hol z Amnesii to klimat zamku, a obecne pokoje (magazyn, regały z towarem, rury) to zaplecze przemysłowe; w jednej mapie może to wyglądać przypadkowo
  - Ustalone 24.10: na razie wszystkie pokoje w jednej puli. Później zestawy pokoi wg motywu, motyw wybiera host w menu (łączy się z 49)
- Uwaga (kamery): kolumny pod antresolą to dokładnie problem „filar zasłania postać” z playtestu 23.10; antresola to drugi poziom w jednym pokoju (NavMesh, schody, pokrycie kamer z dwóch wysokości). Biblioteka będzie najdroższym pokojem do zrobienia, zacząć od korytarzy i lochów
- Uwaga: różnorodność pomaga orientacji tylko, jeśli pokoje są rozpoznawalne. Tani dodatek: charakterystyczne punkty orientacyjne w pokojach (kolor światła, unikalny rekwizyt)

### Drzwi (pomysł 24.10)

- [ ] 15l. Drzwi w > 50% przejść (z seeda): otwieranie/zamykanie (E), stan z autorytetem hosta, otwieranie robi hałas. Zamknięte drzwi tłumią hałas
  - Kratka (okienko) w drzwiach: wzrok przez nią działa, ale potwór zauważy gracza za zamkniętymi drzwiami tylko z bliska (np. ≤ 2–3 m od drzwi) i patrząc prosto na kratkę (wąski kąt)
  - Uwaga: gracze nie patrzą oczami postaci, tylko ze stałej kamery, więc „patrzenie przez kratkę” niczego im nie daje, jeśli kamera po drugiej stronie i tak pokazuje pokój dopiero po wejściu. Żeby kratka miała sens dla graczy: osobne ujęcie przez kratkę (jak szpara w szafce, 16f) po podejściu do drzwi i E/przytrzymaniu, albo kamera korytarza, która przez kratkę widzi kawałek pokoju
  - Ustalone 24.10: ujęcie przez kratkę takie samo jak szpara w szafce (16f), po podejściu do zamkniętych drzwi
- [ ] 15m. Zakluczone drzwi: losowo od 0 do maks. 10% drzwi. Klucz to znalezisko, dowolny klucz otwiera dowolne zakluczone drzwi (jak w LC), zużywa się
  - Uwaga (odcięcie mapy): bez pętli (16h) zakluczone drzwi odcinają całą gałąź mapy. Generator musi pilnować, żeby klucz dało się zdobyć bez przechodzenia przez zakluczone drzwi, i żeby winda nigdy nie była za nimi. Liczba kluczy ≥ liczba zakluczonych drzwi w osiągalnej części
- [ ] 15n. Potwory niszczą drzwi, gdy mają powód sądzić, że za nimi jest gracz: pościg, trop krwi albo hałas prowadzący za drzwi (stany HUNT / INVESTIGATE / TRACK). Wyważanie trwa kilka sekund i jest głośne (okno na ucieczkę)
  - Ustalone 24.10: potwór otwiera zwykłe drzwi, ale długo (np. 3–4 s, słychać szarpanie klamki); wyważenie jest szybsze (np. 1–1,5 s, głośne) i zostawia drzwi wyłamane na stałe. Otwiera, gdy tylko przechodzi (patrol), wyważa, gdy ma powód (pościg/trop/hałas) albo drzwi są zakluczone
  - Uwaga: przez to w pościgu zamknięcie drzwi za sobą daje tylko ~1 s i kosztuje drzwi (potem już nie zasłaniają). Zamykanie drzwi głównie chroni przed patrolem; czasy do strojenia w playteście
  - Potwierdzone 24.10: taki był zamysł (drzwi chronią przed patrolem, w pościgu dają chwilę)
  - Uwaga: NavMesh musi znać drzwi (przejście z kosztem, nie ściana), a szyby wentylacyjne (47c6) omijają drzwi; to dobrze, ale łowca nie powinien przez to ignorować ich całkiem
  - Kamery: drzwi nie mogą zasłaniać przejścia w ujęciu (15f), test zasad kamer do rozszerzenia

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
- [ ] 16h. Wymiary pokoi (ze ścianami) jako wielokrotności 2 m, żeby przejścia leżały na wspólnej siatce i pętle mogły powstawać; ewentualnie aktywne domykanie pętli (dobieranie korytarza łączącego dwa bliskie wolne przejścia)
  - Playtest 24.10: pętli dalej w praktyce nie ma, priorytet w górę. Cel do sprawdzenia testem: każda mapa ≥ 20 pokoi ma co najmniej 1–2 pętle (liczone w grafie połączeń), a nie „jest szansa”
  - Uwaga: sama siatka 2 m tylko zwiększy szansę na przypadkowe trafienie. Żeby pętle były gwarantowane, potrzebne jest aktywne domykanie (po złożeniu drzewa szukać par wolnych przejść blisko siebie i dobierać łączący korytarz/zakręt). Siatka ułatwia to domykanie, więc obie rzeczy razem. Zmiana wymiarów pokoi przesuwa współrzędne w testach (`Maps.CLASSIC`) i wymaga ponownego `camera_rules_test`/`coverage_map`
  - Pętle odblokowują zablokowane przejścia z 15 (dopiero wtedy zablokowanie nie odcina części mapy)

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
- [x] 35. Punktacja zero-sum (`GameState.SHARED_FRACTION`) i ekran podsumowania (wynik rundy + suma sesji)
- [x] 36. Następna runda z nowym seedem (host: R albo przycisk); suma sesji zostaje. Reset po wybiciu wszystkich zastąpiony końcem rundy
- [x] 36b. Narastająca trudność: co etap (3 min + 15 s na pokój) nowy potwór w pokoju najdalszym od graczy (maks. 4), wszystkie zmysły +10% na etap; ryk i napis w HUD
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
- [ ] 41c. Bateria latarki: ograniczony czas świecenia (np. 4–5 min), migotanie przy słabej baterii, baterie do znalezienia na mapie (nowy typ znaleziska obok monet), podniesienie doładowuje
  - Uwaga: rozładowana latarka + ciemny pokój = ślepota, która frustruje zamiast straszyć; liczba baterii i ciemnych pokoi do strojenia razem. Wzmacnia istniejący dylemat (latarka = potwory widzą cię z 14 m zamiast 6 m). Naturalny kandydat do podawania przedmiotów (43)

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
- [ ] 46. Spectator przez kamery żyjących graczy
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
- [ ] 47c9. Lepszy wzrok potworów (playtest 24.10: potwór patrzy na gracza w linii prostej i go nie widzi). Podejrzani w `can_see`: zasięg w ciemności 6–10 m przy pokojach do 20 m (bez latarki gracz na drugim końcu pokoju jest niewidzialny), jeden raycast oko → klatka piersiowa (zasłania go byle skrzynia/krawędź stołu; lepiej kilka punktów: głowa, tors, nogi, widać którykolwiek = widzi), maska `sight_blockers` = warstwa 1 (rekwizyty też blokują), test tylko 10×/s. Najpierw zdiagnozować na konkretnej sytuacji (debug: rysować promień wzroku), dopiero potem stroić
  - Uwaga: nie podnosić po prostu zasięgów. Ciemność i latarka (6 m vs 14 m) to dylemat, na którym stoi 41b/41c; lepiej stopniowe zauważanie z bliska (jak w LC: stojącego od razu, dalej po chwili) niż ślepy potwór albo radar
- [ ] 47c10. Strażnik goni gracza poza rewir, aż go zgubi, potem wraca do gniazda (teraz po 16 m od gniazda (`leash`) przerywa pościg i wraca, wygląda jakby bał się wyjść z pokoju)
  - Uwaga: to zaciera różnicę strażnik vs łowca. Sens strażnika (47c2) to przewidywalny rewir: wiesz, którędy nie iść. Jeśli goni bez limitu, staje się łowcą, który dodatkowo ma bazę. Propozycja: smycz zostaje, ale długa (np. 30–40 m) albo liczona w czasie pościgu, a po zgubieniu gracza strażnik nie bada śladu (INVESTIGATE), tylko od razu wraca. Do tego wolniej przestaje gonić w rewirze niż poza nim
- [ ] 47c4. (może kiedyś) Potwór stacjonarny w stylu barnacle z Half-Life: nie rusza się, łapie gracza, który wejdzie w zasięg
- [ ] 47d. Atak: wręcz (jest), zdalny (pocisk albo efekt na odległość)
- [x] 47e. Atak: porwanie gracza żywcem (jak smoker, jockey i charger w Left 4 Dead 2). Potwór chwyta gracza i zabiera go do swojego gniazda na uboczu (np. najdalszy pokój albo ślepy zaułek). Porwany powoli traci życie już w czasie porwania, a w gnieździe jest powoli zjadany. Koledzy mogą go jeszcze odbić, ale to ciężki moment. Wleczenie zostawia ślad krwi (powiązane z 44)
  - Zrobione: „Porywacz” (profil abductor). Niesie do gniazda −3 HP/s, w gnieździe −7 HP/s, porwany nie ma powalenia. Odbicie: kolega trzyma E przy porwanym 1,5 s, potwór puszcza ofiarę i ucieka na ~11 s
- [ ] 47f. Typ „Łowca” (wzorowany na Alien: Isolation). Dwie warstwy AI:
  - **Reżyser** (host, osobny węzeł): zawsze wie, gdzie są gracze, ale nie podaje potworowi ich pozycji. Co jakiś czas tylko kieruje go w okolicę graczy (pokój obok, piętro), a resztę potwór musi znaleźć sam, zmysłami.
  - **Wskaźnik zagrożenia**: rośnie, gdy potwór jest blisko graczy, długo przy nich i może ich szybko dosięgnąć. Po przekroczeniu progu reżyser odsyła potwora daleko (oddech dla graczy), potem znów go przybliża. W co-opie liczony dla grupy, nie dla jednego gracza.
  - **Odblokowywane zachowania**: część zachowań startuje wyłączona i włącza się, gdy gracze często uciekają tą samą metodą (np. po kilku udanych ukryciach w szafkach zaczyna je sprawdzać; po ucieczkach na inne piętro zaczyna tam zaglądać). Daje wrażenie, że potwór się uczy.
  - Reżyser jest wspólny dla wszystkich typów (ustalone); Łowca używa go najaktywniej.
  - Źródła: [Game Developer: The Perfect Organism – The AI of Alien: Isolation](https://www.gamedeveloper.com/design/the-perfect-organism-the-ai-of-alien-isolation), [Game Developer: Revisiting the AI of Alien: Isolation](https://www.gamedeveloper.com/design/revisiting-the-ai-of-alien-isolation)
- [ ] 48. Shader glitcha
- [ ] 49. Drugi setting

## Faza 9: wykończenie

- [ ] 50. Menu, ustawienia, rebinding, zapis opcji
- [ ] 51. Assety: modele, dźwięki, animacje (Mixamo)
- [ ] 52. Profilowanie na słabym sprzęcie
- [ ] 53. Buildy, Steamworks, zamknięte playtesty
