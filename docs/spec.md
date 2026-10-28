# Gierka – spec gry

Co-opowy survival horror dla 2–5 graczy ze stałymi kamerami jak w starym Resident Evil: zbieracie monety w proceduralnym kompleksie, polują na was potwory, a na koniec trzeba wyjść windą i podzielić łup.

## Pitch i filary

Drużyna schodzi do opuszczonego kompleksu, zbiera monety i próbuje wyjść windą, zanim dopadną ją potwory. Wyróżnikiem jest kamera: każdy gracz widzi świat przez własne, stałe ujęcia jak w Resident Evil 1, więc nie widzi tego, co kolega, i informacje trzeba przekazywać głosem.

1. **Gameplay ponad grafikę.** Prosty, retro wygląd (greybox, ciemność, światło), działa na słabym sprzęcie. Punkt odniesienia: Lethal Company.
2. **Niepewność.** Nigdy nie wiesz na pewno, czy potwór jest obok: otoczenie celowo robi fałszywe alarmy.
3. **Współpraca kontra chciwość.** Razem bezpieczniej, ale łup dzieli się między ocalałych.
4. **Ślady zamiast cutscenek.** Historia zostaje na podłodze: krew, rozbryzgi, wleczone ciała.

## Runda

Runda trwa, dopóki ktokolwiek jest na mapie: kończy się, gdy każdy gracz zginął albo wyszedł. Nie ma limitu czasu, jest za to rosnąca trudność.

1. Host wybiera liczbę pokoi (3–60), mapa składa się z seeda. Wszyscy startują w hali.
2. Gracze rozchodzą się po kompleksie i zbierają monety: kupki na meblach oraz w kątach i pod ścianami. Wartość łupu jest losowa, niezależna od miejsca.
3. W najdalszym pokoju budzi się pierwszy potwór (Łowca). Co etap (3 min + 15 s na pokój, czyli ok. 5 min przy 8 pokojach) dochodzi kolejny, maks. 4, a wszystkie mają ostrzejsze zmysły (+10% na etap).
4. Ranni krwawią i zostawiają ślad, po którym idą koledzy i potwory. Powalonego można podnieść, porwanego odbić.
5. Gdzieś na mapie jest winda: stalowe drzwi w zielonej futrynie, w losowym miejscu (blisko albo daleko, czasem za zakluczonymi drzwiami albo w ciemnym pokoju). Kto ją znajdzie, może od razu wyjść (trzymaj E); reszta drużyny nie wie, gdzie jest, dopóki ktoś im nie powie. Wyniesione monety są bezpieczne. Wydostany albo martwy gracz ogląda kamery kolegów.
6. Gdy nikogo nie ma na mapie: ekran podsumowania z wynikiem rundy i sumą sesji. Host wciska R i startuje nowa runda na nowej mapie.

## Monety i punktacja

Punktacja jest zero-sum: połowę wyniesionych monet zatrzymujesz, a drugą połowę dzielą po równo ty i ocalałi, którzy wyszli po tobie. Kto wychodzi pierwszy, nie korzysta z ryzyka reszty; kto zostaje najdłużej, zbiera najwięcej. Przykład: A wychodzi pierwszy ze 100, B później ze 100, więc A ma 75, a B 125.

```math
wynik_i = 0{,}5 \cdot W_i + \sum_{k:\ wyszedł\ przed\ i\ lub\ to\ i} \frac{0{,}5 \cdot W_k}{liczba\ ocalałych,\ którzy\ wyszli\ nie\ wcześniej\ niż\ k}
```

- **Gdzie leży łup:** na meblach (stoły, półki, prycze), w kątach i pod ścianą, nigdy na środku przejścia ani w drzwiach. Każda kupka, bateria i klucz da się zebrać z podłogi, do której prowadzi droga z hali: nie siedzi w meblu i nie leży wyżej niż ok. 1,35 m nad miejscem, w którym się stoi. Kupki warte 20–55 monet.
- Kto zginął, dostaje 0, a jego niesione monety wypadają kupką na ziemię: koledzy (albo on sam w następnym życiu) mogą je zgarnąć.
- Pełna kieszeń hałasuje: przy 300 monetach kroki słychać 2× dalej. Chciwość kosztuje.
- Proporcję 50/50 zmienia jedna stała (`SHARED_FRACTION`).
- To celowy dylemat: samemu można zarobić więcej, ale trudniej przetrwać, bo nikt cię nie podniesie, nie opatrzy ani nie odbije z rąk Porywacza. Wcześniejsza dziura (wyjście od razu i czekanie na pulę od reszty) jest załatana zasadą „twoja część puli idzie do ciebie i do tych po tobie”.

## Kamera

Każdy gracz ma własne, nieruchome ujęcia, przecinane według tego, gdzie stoi; kamery są lokalne i nie idą przez sieć, więc dwóch graczy w różnych pokojach widzi zupełnie co innego.

- **Strefy.** Każdy pokój ma strefy z przypisaną kamerą. Wejdźesz w strefę, kamera tnie. Strefy nachodzą na siebie, więc stanie na granicy nie powoduje migania.
- **Minimalny czas ujęcia: 1,2 s.** Zwykłe cięcie czeka, chyba że postać zniknęła z kadru. Przy losowym błądzeniu wychodzi ok. 7 cięć na minutę.
- **Bezpiecznik.** Jeśli postaci nie widać przez 0,5 s (zasłonięta, pod kamerą), kamera przeskakuje na inną z tego pokoju, która ją widzi, i wraca do własnej, gdy tylko to możliwe.
- **Zasada drzwi.** Każde przejście widać z kamery strefy, w której leży, pod kątem < 70° do ściany. Pilnuje tego test automatyczny.
- **Sterowanie tank** (przód/tył względem postaci), więc cięcie kamery nigdy nie zmienia kierunku ruchu.
- **Dźwięk** słyszysz „uszami” postaci, obróconymi jak kamera: dźwięk z lewej strony ekranu jest z lewej.
- Retro look: kwantyzacja kolorów, dithering, winieta, mgła. Render w Full HD.

## Sterowanie

| Klawisz | Akcja |
| --- | --- |
| W / S | przód / tył (względem postaci) |
| A / D | obrót |
| Shift | bieg (głośniejszy, ok. 6 s, potem zadyszka) |
| Ctrl albo C (trzymaj) | kucanie: ciszej, trudniej cię zauważyć, mieścisz się pod stołem |
| Spacja | skok (\~1 m), lądowanie hałasuje |
| Q | szybki obrót o 180° |
| F | latarka (widzisz więcej, ale potwory widzą cię z 14 m zamiast 6 m; zużywa baterię) |
| E (trzymaj) | podnieś powalonego, odbij porwanego, bandaż dla kolegi, wejdź do szafki, wyjdź windą, otwórz/zamknij drzwi (zakluczone: kluczem, 1 s); stuknięcie tuż po przebiegnięciu przez drzwi zatrzaskuje je za sobą |
| stój przodem do zamkniętych drzwi | po 0,6 s podgląd przez kratkę w drzwiach (ruch kończy) |
| E w szafce | wyjście z szafki |
| H (trzymaj) | bandaż dla siebie |
| Tab | statystyki (trzymaj): gracze, runda, sieć, sterowanie |
| R | host: następna runda |
| F1 | debug w panelu statystyk (ujęcie kamery, stany potworów); po śmierci Spacja przełącza oglądanego kolegę |
| Esc | wyjście z gry |
| \` (tylda) | host, build deweloperski: menu testowe (spawn potworów, następny etap, zamrożenie, nieśmiertelność, leczenie, monety, teleport do windy) |

## Mapa

Mapa składa się z modułów doklejanych drzwiami do drzwi, deterministycznie z seeda: host wysyła tylko seed i liczbę pokoi, a każdy komputer składa identyczną mapę (też losowe rekwizyty, światła i drzwi). Pokoje leżą na siatce 2 m, więc generator domyka pętle łącznikami z korytarzy: mapa z 20 pokoi ma 1–2 pętle, wokół których da się uciekać. Korytarze to ok. 70% elementów mapy, pokoje są raczej przechodnie.

| Pokój | Rozmiar | Wyjścia | Co w środku |
| --- | --- | --- | --- |
| Hala (start) | 16 × 12 m | 2 | spawn, 3 szafki, stół z prześwitem (winda jest gdzie indziej) |
| Korytarz | 16 × 4 m | 2 | szafka, beczki, rury |
| Korytarz L / T / X | 8 × 8, 12 × 8, 12 × 12 m | 2 / 3 / 4 | prawdziwe korytarze szerokości 4 m z ramionami |
| Łączniki | 4–16 × 4 m, narożnik 4 × 4 m | 2 | gołe korytarze, którymi generator domyka pętle |
| Magazyn | 20 × 20 m | 2 | dwa regały = trzy alejki, 2 szafki, stół warsztatowy |
| Skrzyżowanie | 12 × 12 m | 3 | stół-wyspa do krążenia, szafka |
| Zakręt | 8 × 8 m | 2 | skrzynia, beczka |
| Schowek | 8 × 8 m | 1 (ślepy zaułek) | regały, szafka, znaleziska |
| Lochy | 16 × 12 m | 2 | korytarz i 6 cel za kratą (przez kratę widać, przejść się nie da), prycze, znaleziska |
| Wielki hol | 20 × 24 m, 8 m wysokości | 3 | fontanna, 6 kolumn, ławki, 2 szafki |
| Biblioteka | 20 × 20 m, 8 m wysokości | 2 | rotunda z antresolą na 3,6 m (rampa), regały, kolumny, stoliki, świetlik |
| Kotłownia | 16 × 12 m | 2 | wielki kocioł z pomarańczowym blaskiem paleniska, drugi mniejszy, hałda węgla, nisze za kotłami, szafka |
| Kaplica | 12 × 20 m, 7 m wysokości | 2 | rzędy ławek, ołtarz z czerwonym suknem, świecące okno z krzyżem, konfesjonał (szafka) |
| Stołówka | 16 × 16 m | 3 | 4 długie stoły z prześwitem (kryjówki), kuchnia, zielonkawe świetlówki |
| Archiwum | 16 × 12 m | 2 | 3 rzędy szaf na akta z alejkami, biurko, katalog kartkowy |
| Prysznice | 12 × 12 m | 2 | kafle, kabiny, 3 szafki w przebieralni, ławka |
| Serwerownia | 12 × 16 m | 2 | 2 rzędy szaf serwerowych, boczne alejki, niebieskie światło |
| Rampa | 16 × 4 m | 2 | korytarz piętro w górę/dół (5 m) |
| Klatka schodowa | 10 × 8 m | 2 | dwa biegi z półpiętrem, piętro 5 m |

- Do 60 pokoi i nawet 9 poziomów. Mapa 60 pokoi składa się w ok. 0,13 s, gra trzyma 60 FPS.
- Każde przejście ma rdzawą futrynę z lampką, żeby było widoczne z każdego ujęcia; nieużywane są zamurowane.
- Każdy pokój ma kratkę wentylacji w suficie (dla potworów).
- Zmienność z seeda: 20% pokoi zgaszonych (gasną też oprawy, lampki nad drzwiami i świetliki), w jasnych 20% lamp migocze razem z oprawą, 2–5 losowych skrzyń i beczek przy ścianach, drobiazgi (rury, beczki, palety, kartony) stoją z szansą 50–70%, a co drugi pokój jest lustrzanym odbiciem (np. rampa w bibliotece raz po wschodniej, raz po zachodniej stronie).
- Pokoje charakterystyczne się nie powtarzają: biblioteka, hol, kotłownia, kaplica, stołówka, archiwum, prysznice i serwerownia najwyżej raz na 20 pokoi mapy, lochy, magazyn i schowek raz na 10. Korytarze bez limitu.

## Potwory

Każdy potwór ma dwie warstwy AI, wzorowane na Alien: Isolation: **reżyser** zawsze wie, gdzie są gracze, ale tylko kieruje potwora w ich okolicę, a **zmysły** potwora (wzrok, słuch, węch) muszą gracza znaleźć same.

- **Wskaźnik zagrożenia.** Rośnie, gdy Łowca długo kręci się przy graczach; po progu reżyser odsyła go daleko, żeby dać wam odetchnąć.
- **Nauka.** Im częściej gracze uciekają, chowając się w szafkach, tym częściej potwory je sprawdzają (od 10% do 70%).
- **Stany:** patrol → sprawdzanie hałasu → pościg → atak z widocznym zamachem (oczy rozbłyskują, można odskoczyć) → wycofanie. Do tego tropienie krwi, porywanie i przejścia wentylacją.
- **Doskok.** W czasie zamachu potwór sunie za tobą w kierunku, w którym zaczął cios, i prawie się nie obraca. Marsz w tył nie ucieka, bieg ledwo; ratuje krok w bok (ok. 1 m z linii ciosu) albo skok.
- **Zryw.** Łowca i Porywacz przez pierwsze 3 s pościgu biegną szybciej od ciebie (4,9 i 4,8 m/s, odnawia się po 10 s), potem zwalniają. Zauważenie z bliska jest groźne, ratunek to zerwać kontakt i się schować.
- **Bieganie w kółko nie działa.** Potwór pamięta twoją trasę; gdy krążysz wokół fontanny, regału albo pętli korytarzy, wychodzi ci naprzeciw drugą stroną i tam czeka.
- **Przeszukiwanie.** Gdy cię zgubi, przez 20–35 s chodzi po okolicy (do 9 m od miejsca, gdzie cię stracił), rozgląda się i często zagląda do szafek; dopiero potem wraca do patrolu. Strażnik od razu wraca do gniazda.
- **Potwory się uczą.** Im częściej uciekacie, chowając się w szafkach, tym częściej do nich zaglądają. Ucieczka na inne piętro (schody, rampa) za pierwszym razem zawsze działa; potem coraz częściej (do 75%) potwór szuka cię na twoim piętrze, a nie tam, gdzie cię stracił.
- **Zmysły:** wzrok w stożku 120°: gracza w zgaszonym pokoju bez latarki widzi z 6 m, w oświetlonym pokoju albo z latarką z 14 m; z bliska zauważa od razu, dalej potrzebuje chwili (do 0,8 s); patrzy na głowę, tors i nogi, więc skrzynia zasłania tylko część; słuch zależny od hałasu (chód 4 m, bieg 10 m, kucanie 1,4 m); z bliska poluje na słuch; czuje krew do 90 s wstecz.
- **Wentylacja:** kratki w suficie każdego pokoju. Łowca i Porywacz widocznie wspinają się do kratki i przemieszczają się szybami niewidoczni, słychać metaliczne dudnienie nad głową, zeskakują z kratki w innym pokoju.

| Typ | Zachowanie | Zmysły | Atak | Wentylacja | Jak przeżyć |
| --- | --- | --- | --- | --- | --- |
| Łowca | reżyser prowadzi go w okolicę graczy | wzrok 6/14 m, słuch ×1 | 35 HP i odchodzi | tak | nie uciekaj biegiem, zerwij kontakt i się schowaj |
| Strażnik | pilnuje rewiru wokół gniazda; goni gracza także poza rewir (do 35 m od gniazda), a gdy go zgubi, wraca do gniazda; co 3–4 min przenosi gniazdo (zostawia krew) | świetny wzrok 9/16 m, słaby słuch ×0,6 | 50 HP | nie | omijaj gniazdo (krew), zgubiony odpuszcza |
| Rzeźnik | chodzi losowo | ślepy, słuch ×1,8 | egzekucja: natychmiastowa śmierć, krew na ścianie | nie | cisza: stój albo skradaj się |
| Porywacz | reżyser prowadzi go w okolicę graczy, najszybszy (4,2 m/s) | wzrok 7/15 m, słuch ×1,1 | porywa żywcem do gniazda | tak | trzymajcie się razem: gracza, przy którym ktoś stoi (5 m), tylko śledzi z ok. 7 m |
| Obserwator | stoi i się rozgląda | wzrok 10/20 m | krzyk ściąga inne potwory, bliskiego atakuje | nie | nie wchodź w jego światło: widzi tylko w stożku reflektora (70°), za to w nim do 20 m także po ciemku |

Kolejność pojawiania się: Łowca na start, potem co etap Strażnik, Rzeźnik, Porywacz, Obserwator (maks. 4 naraz). Typ potwora to plik danych (`monster/profiles/*.tres`), więc nowy potwór to głównie nowe liczby, a nie nowy kod.

## Przetrwanie

Zero HP nie oznacza śmierci, tylko powalenie: masz 30 s, żeby kolega cię podniósł, inaczej się wykrwawiasz.

- **HP:** 100. Cios zwykłego potwora to 35, Strażnika 50.
- **Krwawienie:** 60% trafień otwiera ranę, która zabiera 2 HP/s, dopóki jej nie opatrzysz.
- **Kondycja:** bieg starcza na ok. 6 s, odnawia się wolniej (po 1 s odpoczynku). Po wyczerpaniu łapiesz zadyszkę: tylko marsz, aż wróci 40%, i głośne dyszenie, które słychać z 12 m, a potwory słyszą z 5 m. W HUD „kondycja N%”.
- **Bateria latarki:** 4,5 min świecenia, zużywa się tylko przy włączonej. Poniżej 20% latarka przygasa i rwie się, pusta gaśnie. Baterie leżą na mapie (jedna na 4 pokoje, +50%); z pełną baterią jej nie podniesiesz, zostaje dla kolegi. W HUD „bateria N%”.
- **Bandaże:** 2 na start. H (trzymaj 2 s) opatruje ciebie, E przy krwawiącym koledze opatruje jego twoim bandażem.
- **Powalenie:** leżysz, nie ruszasz się, 30 s do wykrwawienia. Kolega trzyma przy tobie E przez 3 s i wstajesz z 30 HP. Potwór może powalonego dobić, ale nie Łowca: powalony kończy jego pościg, Łowca go nie widzi i nie idzie po jego kałuży, tylko szuka reszty.
- **Ślady krwi:** krwawiący zostawia krople co 0,7 m, powalony kałużę. Widać je z każdej kamery, zostają do końca rundy, a potwory nimi idą.
- **Porwanie:** Porywacz niesie cię żywcem do gniazda (-3 HP/s), tam zjada (-7 HP/s). Porwany nie ma powalenia. Kolega trzyma przy tobie E 1,5 s, potwór cię puszcza i ucieka na ok. 11 s.
- **Egzekucja:** Rzeźnik zabija od razu, bez powalenia i bez szansy na ratunek.

## Chowanie się

Kryjówka ratuje tylko wtedy, gdy potwór nie widział, jak się chowasz: inaczej podchodzi, otwiera szafkę i atakuje (jak w R.E.P.O. i Alien: Isolation).

- **Szafki** (8 sztuk w 5 typach pokoi): E 0,5 s, skrzypnięcie drzwi słychać z 5 m. W środku kamera z wnętrza szafki z widokiem przez szpary.
- **Stoły z prześwitem** (1,1 m pod blatem): w kucki mieścisz się pod spodem, potwór nie. Na stojąco nie wstaniesz. Stoły to też wyspy, wokół których można krążyć przed pościgiem.
- **Pod stołem jesteś niewidoczny** (także pod pryczą czy niską półką): potwór nie widzi cię i nie rozpoznaje po dźwięku, dopóki nie zajrzy pod spód. Zaglądanie widać: podchodzi i schyla się na ok. 1,3 s, widzi wtedy do 1,8 m od miejsca, w które patrzy. Zagląda na pewno, jeśli widział, jak się tam chowasz, a przy przeszukiwaniu okolicy czasem (ta sama szansa co przy szafkach). Znalezionego atakuje.
- **Kucanie:** prędkość 1,1 m/s, kroki słychać z 35% odległości, potwór widzi cię z 60% zasięgu.
- **Skok:** ok. 1 m, lądowanie słychać z 7 m.
- **Potwory się uczą:** każda udana ucieczka do szafki podnosi szansę, że przy przeszukiwaniu zajrzą do szafek w pobliżu (10% + 15% za ucieczkę, maks. 70%).

## Drzwi i klucze

Drzwi stoją w ok. 65% przejść; zamknięte zatrzymują potwora na chwilę, ale w pościgu dają tylko ok. sekundy przewagi.

- **Gracz:** E otwiera i zamyka (słychać z 5 m). Uciekając, stuknij E do 1,5 s po przebiegnięciu przez otwarte drzwi: zatrzaśniesz je za sobą bez odwracania się (słychać z 9 m). W drzwiach jest kratka: stań przodem do zamkniętych drzwi, a po 0,6 s zobaczysz, co jest po drugiej stronie.
- **Zakluczone:** losowo od 0 do 10% drzwi, nigdy przy hali. Kluczy jest tyle, ile zakluczonych drzwi, i leżą tam, gdzie da się dojść bez nich, więc winda za zakluczonymi drzwiami jest zawsze osiągalna. Dowolny klucz otwiera dowolne drzwi i się zużywa.
- **Potwór otwiera powoli** (3,5 s, słychać szarpanie klamki), gdy tylko przechodzi. **Wyważa szybko** (1,8 s: „BUM… BUM… BUM… TRZASK”, łomoty co 0,6 s potwory słyszą z 12 m, a gracze z sąsiednich pokoi; skrzydło drga, kamera się trzęsie, gdy jesteś blisko; na końcu trzask drzazg z 16 m i drzwi zostają wyłamane), gdy goni, idzie po krwi albo sprawdza hałas. Patrol zakluczonych drzwi nie rusza.
- **Przez kratkę** potwór widzi tylko z bliska (do 2,6 m) i patrząc prosto na drzwi. Zamknięte drzwi tłumią hałas o połowę.

## Napięcie

Dźwięk to główne źródło poszlak: gdy potwór się zbliża, ambient cichnie, a wchodzi coraz szybsze bicie serca i przyspieszony oddech postaci.

- **Poziom zagrożenia** jest celowo rozmyty i opóźniony, żeby serce nie działało jak radar. Pościg i dudnienie w szybie nad głową liczą się mocniej.
- **Poszlaki potworów:** ciężkie kroki (do 16 m), warczenie na start pościgu, świst zamachu, metaliczne dudnienie w wentylacji. Każdy typ ma własny dźwięk, słyszalny, zanim wejdzie w kadr: Łowca klekocze jak owad (16 m), Rzeźnik wlecze coś po betonie i brzęczy łańcuchem (18 m), Strażnik nisko mruczy (12 m), Obserwator cienko piszczy i szepcze (14 m), Porywacz węszy (14 m). Wiesz, co jest blisko, ale nie dokładnie gdzie.
- **Akcent przy wykryciu:** gdy potwór do 20 m od ciebie zaczyna pościg (ciebie albo kolegę obok), gra ostre uderzenie muzyczne i podskakuje serce; najwyżej raz na 15 s.
- **Zakłócenie obrazu:** gdy potwór jest do 8 m od ciebie i widać go w twoim ujęciu, obraz się rwie (pasy, rozjazd kolorów, szum); im bliżej, tym mocniej.
- **Fałszywe alarmy:** co 12–28 s host puszcza wszystkim w tym samym miejscu skrzypnięcie, łomot, metaliczny stuk albo kroki brzmiące jak potwór, 6–20 m od któregoś gracza. Bliski alarm też podbija serce.
- **Nowy potwór** na następnym etapie: ryk z daleka i napis w HUD.
- Dźwięki to darmowe paczki Kenney (CC0) plus wygenerowane placeholdery (oddech, warczenie, dźwięki typów potworów, akcent wykrycia, serce, ambient).

## Sieć i technologia

Gra jest w Godot 4.7 (GDScript), multiplayer host–klient po ENet dla 2–5 graczy; host jest jednocześnie serwerem i decyduje o wszystkim, co ważne.

- **Host decyduje:** potwory i ich AI, HP, krwawienie, monety, punktacja, kryjówki, rundy. Klient tylko prosi (np. o bandaż) i dostaje stan.
- **Klient decyduje:** ruch własnej postaci, kamera, HUD, dźwięk napięcia.
- **Łączenie:** po IP w tej samej sieci albo przez Tailscale; port 7777/UDP. Steam lobby planowane na później.
- **Sprzęt:** 60 FPS na MacBooku M1 nawet na mapie z 60 pokojami; działa też na Linuksie (po pullu: `godot --headless --path gierka --import`).
- **Testy:** ok. 30 automatycznych testów headless (kamery, potwory, sieć, generator, kryjówki, porwanie) plus mapy pokrycia kamer w `docs/coverage/`.

## Stan prac

Cała pętla MVP działa i jest grywalna po sieci; brakuje głównie modeli, animacji, czatu głosowego i strojenia balansu w playtestach.

**Jeszcze nie ma:**

- modeli i animacji (postacie i potwory to kapsuły z oczami),
- wbudowanego czatu głosowego z zasięgiem (na razie Discord),
- Steam lobby,
- potworów chodzących po ścianach i sufitach, ataków zdalnych,
- przedmiotów poza monetami i bandażami (podawanie przedmiotów, sloty),
- drugiego settingu (kopalnia, młyn).

**Ryzyka i pytania do playtestu:**

- Czy zero-sum nie sprawi, że ludzie zaczną porzucać drużynę? Jeśli tak: bonus za wyjście razem.
- Czy skok przy sterowaniu tank i stałej kamerze nie jest toporny? Alternatywa: przeskakiwanie przeszkód kontekstowo.
- Czy bicie serca nie zdradza za dużo (radar)?
- Czy 3 min + 15 s na pokój to dobre tempo pojawiania się kolejnych potworów?
- Czy kamery w ciasnych miejscach (skrzyżowanie, klatka schodowa) nie skaczą za często?
