# Gierka – notatki dla agenta

Co-op survival horror ze stałymi kamerami, Godot 4.7 (GDScript), host-klient po ENet.

- **Roadmapa i decyzje: `progress.md`** – jedyne źródło prawdy. Każdy nowy pomysł użytkownika trafia tam od razu, z uwagą krytyczną, gdy kłóci się z czymś zaplanowanym lub zrobionym. Luźny pomysł („może…”, „fajnie by było…”) = wpis na listę, kod dopiero po „dawaj”/„zrób”.
- Uruchamianie, sterowanie, lista testów: `README.md`.

## Praca

- Commit po każdym małym kroku, zawsze `git commit --no-gpg-sign`; aktualizuj przy tym `progress.md`. Push, gdy użytkownik o to prosi albo kończymy blok pracy.
- Komentarze i teksty w grze po polsku; komentarz mówi *dlaczego*.
- Po każdym kroku: odpowiedni test headless + regresje, przy zmianach wizualnych zrzut ekranu (skrypt `-s` z `root.get_texture().get_image().save_png()`, bez `--headless`).

## Pułapki (nie widać ich w kodzie)

- **Import po nowej klasie:** nowy `class_name` → najpierw `godot --headless --path . --import`, inaczej „Could not find type”. Cache `.godot/` nie jest w repo.
- **Testy `-s`:** skrypty testowe kompilują się przed autoloadami (`Net`, `NoiseBus`), więc w testach nie używaj typów statycznych klas, które od nich zależą (`Player`, `Monster`, `CameraDirector`…): `var m` zamiast `var m: Monster`. Enum przez instancję: `m.State.keys()`.
- **`Transform3D` w `.tscn`** to WIERSZE bazy, potem pozycja. Obrót o yaw: `tf()` w `tools/gen_rooms.py`.
- **NavMesh:** wypiekać 2 klatki fizyki po złożeniu mapy (CSG buduje się później; wcześniejsze wypiekanie daje siatkę, której mapa nawigacji nie widzi). Duże mapy potrzebują jeszcze kilkudziesięciu klatek na synchronizację.
- **Pokoje** generuje `python3 tools/gen_rooms.py` i NADPISUJE `rooms/*.tscn`. Zmiany w pokojach rób w skrypcie; potem `camera_rules_test`, `visibility_test`, `tools/coverage_map.gd`.
- **Testy na stałej mapie:** `main.map_layout = Maps.CLASSIC` (`tests/test_maps.gd`): hala x=0, korytarz x=16,4, magazyn x=34,8. Zmiana wymiarów pokoi przesuwa współrzędne w testach.
- **Determinizm mapy:** wszystko, co wpływa na mapę (pokoje, rekwizyty, światła), losuje się z RNG `MapGenerator` – nigdy `randf()`, bo klienci złożą inną mapę. Test sieci porównuje podpis mapy hosta i klienta.
- **Autorytet:** stan gry (HP, monety, kryjówki, potwory) zmienia tylko host w `GameState`/`MonsterDirector`; klient prosi przez `request_*` RPC. Ruch postaci należy do jej właściciela, więc host przenosi gracza przez RPC (`respawn_at`) albo właściciel sam reaguje na stan (porwanie, szafka).
- **Nowe stany enumów** (`Monster.State`, `GameState.Life`, `MonsterProfile.*`) tylko na końcu: lecą przez sieć jako liczby.
- Audio z movie makera Godota (`--write-movie`) daje śmieci – dźwięku nie da się tak zweryfikować; sprawdzaj tylko, że odtwarzacze się uruchamiają.
