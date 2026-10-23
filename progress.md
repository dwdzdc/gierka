# Progress

Legenda: `[x]` zrobione · `[~]` częściowo / czeka na decyzję · `[ ]` do zrobienia

## Decyzje

- [x] Silnik: Godot 4 (4.7, renderer Mobile)
- [x] Sieć: host-client po ENet (później Steam lobby przez GodotSteam). Ruch gracza z autorytetem klienta; potwór, HP, krew i punkty z autorytetem hosta. Kamera, UI i audio feedback lokalnie.
- [x] Kontrakt pokoju: `Geometry`, `Doorways`, `CameraZones` (Area3D + Camera), `LootSpawns`, `AmbientPoints` (patrz `rooms/room.gd`)
- [x] Potwory jako typy: wspólna baza (percepcja, nawigacja, stany) + wymienne zachowania
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

## Faza 2: modularne pokoje

- [x] 11. Scena bazowa pokoju według kontraktu (NavMesh liczony dla całej mapy, nie per pokój)
- [ ] 12. Generator: graf pokoi doklejanych po `Doorways`, test kolizji AABB, seed
- [ ] 13. Zaślepki niepołączonych drzwi, strefa startowa
- [~] 14. Nawigacja wypiekana w runtime. Działa na ręcznie złożonej mapie, generator jeszcze nie istnieje
- [ ] 15. Modyfikacje z seeda: loot, zablokowane przejścia, światła

## Faza 3: sieć

- [x] 16. Menu host/join po IP (ENet), port 7777, do 4 graczy
- [~] 17. Spawn graczy i synchronizacja pozycji, obrotu i latarki. Animacji jeszcze nie ma (brak modelu)
- [x] 18. Kamera tylko dla lokalnego gracza
- [~] 19. Host rozsyła seed, klienci składają tę samą mapę. Na razie mapa stała, wróci razem z generatorem (12)
- [x] 20. GameState z autorytetem hosta (HP, życie graczy), host rozsyła pełną kopię przez RPC. Żądania klient→host dojdą, gdy będzie co żądać (np. bandaż)

## Faza 4: potwór (baza)

- [x] 21. Potwór-kapsuła u hosta, patrol po NavMesh (losowe punkty na poziomie podłogi), replikowana pozycja i stan, wykrywanie utknięcia
- [x] 22. Noise bus (autoload `NoiseBus`, tylko u hosta). Kroki 4 m, bieg 10 m, liczone przez hosta z replikowanej pozycji. Drzwi dojdą, gdy będą drzwi
- [x] 23. Percepcja: słuch (promień hałasu) + wzrok (stożek 120°, raycast). Zasięg wzroku 6 m w ciemności, 14 m na gracza z włączoną latarką
- [ ] 24. Maszyna stanów patrol → trop → polowanie → atak → wycofanie
- [ ] 25. Atak i obrażenia u hosta, feedback u klienta
- [ ] 26. Sygnały obecności w 3D audio
- [ ] 27. Wariant „niewidzialny” z mignięciem przed atakiem

## Faza 5: krew i ranni

- [ ] 28. Krwawienie i timer bleed-out
- [ ] 29. Bandaż: tamowanie siebie lub kolegi
- [ ] 30. Powalenie, podnoszenie, śmierć
- [ ] 31. Ślady krwi trwałe w rundzie, widoczne przez cięcia kamer
- [ ] 32. Potwór idzie po krwi

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
- [ ] 47. Kolejne typy potworów
- [ ] 48. Shader glitcha
- [ ] 49. Drugi setting

## Faza 9: wykończenie

- [ ] 50. Menu, ustawienia, rebinding, zapis opcji
- [ ] 51. Assety: modele, dźwięki, animacje (Mixamo)
- [ ] 52. Profilowanie na słabym sprzęcie
- [ ] 53. Buildy, Steamworks, zamknięte playtesty
