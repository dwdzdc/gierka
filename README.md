# Gierka

Co-op survival horror z kamerą fixed (każdy gracz ma własne ujęcia). Godot 4.7.
Plan i postęp: [progress.md](progress.md).

## Uruchomienie

Potrzebny jest Godot **4.7** (wersja standardowa, nie .NET/Mono) i git. Każdy gracz musi mieć
tę samą wersję gry, czyli ten sam commit.

Na każdym systemie są te same trzy kroki: **pobierz repo → zaimportuj projekt → uruchom**.
Import trzeba powtórzyć po każdym pullu, który dodaje nowe skrypty. Bez niego gra wysypie się
na `Could not find type ...`, bo cache klas (`.godot/`) nie jest w repo. Otwarcie projektu w
edytorze Godota robi import automatycznie.

### macOS

```sh
brew install --cask godot          # instaluje Godot.app i polecenie `godot`
git clone git@github.com:dwdzdc/gierka.git
cd gierka
godot --headless --path . --import # raz po sklonowaniu / po pullu
godot --path .                     # gra
```

Przy pierwszym hostowaniu macOS zapyta o połączenia przychodzące dla Godota: „Zezwól”.

### Linux

```sh
# Arch:     sudo pacman -S godot   (albo z AUR: yay -S godot-bin)
# Flatpak:  flatpak install flathub org.godotengine.Godot
#           (wtedy zamiast `godot` pisz `flatpak run org.godotengine.Godot`)
# Inne:     binarka z https://godotengine.org/download/linux/ (rozpakuj, chmod +x)

git clone git@github.com:dwdzdc/gierka.git
cd gierka
godot --headless --path . --import
godot --path .
```

Host z firewallem: otwórz 7777/UDP (ufw: `sudo ufw allow 7777/udp`).

### Windows

1. Pobierz Godot 4.7 (standard, 64-bit) z https://godotengine.org/download/windows/ i rozpakuj
   np. do `C:\Godot`. W archiwum są dwa pliki: `Godot_v4.7.2-stable_win64.exe` (gra/edytor) i
   `..._console.exe` (to samo, ale z oknem konsoli i logami: użyj go do importu).
2. Zainstaluj git (https://git-scm.com/download/win) i w PowerShellu:

```powershell
git clone git@github.com:dwdzdc/gierka.git
cd gierka
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
C:\Godot\Godot_v4.7.2-stable_win64.exe --path .
```

Przy pierwszym hostowaniu Windows Defender zapyta o dostęp do sieci: zaznacz sieci prywatne
i zezwól.

### Bez terminala

Uruchom Godota, w Menedżerze projektów wybierz **Import**, wskaż `project.godot` z folderu gry,
otwórz projekt (import zrobi się sam) i wciśnij **F5**.

## Gra po sieci

Host klika **Hostuj grę**: w lewym górnym rogu pojawia się jego IP. Reszta wpisuje to IP
i klika **Dołącz**. Port 7777/UDP, do 5 graczy.

- Ta sama sieć lokalna: IP z HUD hosta (`192.168.x.x`).
- Przez internet: [Tailscale](https://tailscale.com) u wszystkich i IP hosta `100.x.x.x`,
  albo przekierowanie portu 7777/UDP na routerze hosta.
- Firewall hosta musi przepuszczać 7777/UDP (Linux z ufw: `sudo ufw allow 7777/udp`).

Bez menu, z terminala:

```sh
godot --path . -- --host --rooms=12 --seed=1234   # liczba pokoi i seed mapy opcjonalnie
godot --path . -- --join=192.168.1.23
```

## Sterowanie

WASD / strzałki: ruch (tank) · Shift: bieg · Q: obrót o 180° · F: latarka · Ctrl/C: kucanie · Spacja: skok · E (trzymaj): pomóż koledze / odbij porwanego / wyjdź windą / otwórz-zamknij drzwi (zakluczone: klucz) · E tuż po przebiegnięciu przez drzwi: zatrzaśnij je za sobą · stój przodem do zamkniętych drzwi: podgląd przez kratkę · H (trzymaj): bandaż · Tab (trzymaj): statystyki · Spacja po śmierci: następny kolega · F1: debug · R: następna runda (host) · ` (host, build deweloperski): menu testowe · Esc: wyjście

## Pokoje

Greyboxy pokoi generuje `python3 tools/gen_rooms.py` (nadpisuje `rooms/*.tscn`).
Kontrakt pokoju i drzwi: `rooms/room.gd`. Składanie mapy: `game/map_generator.gd`.

## Testy

```sh
godot --headless --path . -s tests/walk_test.gd        # przejście przez pokoje, log cięć kamery
godot --headless --path . -s tests/visibility_test.gd  # gdzie kamera nie widzi postaci
godot --headless --path . -s tests/map_test.gd -- --rooms=20  # generator: kolizje, determinizm, dostępność
godot --headless --path . -s tests/camera_rules_test.gd       # każde przejście widoczne z kamery swojej strefy
godot --headless --path . -s tests/stamina_test.gd            # bieg: zadyszka po ~6 s, dyszenie = hałas, regeneracja
godot --headless --path . -s tests/kite_test.gd [-- --off|--no-burst]  # łowca vs bieg w kółko wokół fontanny
godot --headless --path . -s tests/battery_test.gd            # bateria latarki: zużycie, migotanie, gaśnięcie, znajdźka
godot --headless --path . -s tests/container_test.gd          # skrzynie: przeszukanie E, zawartość, hałas
godot --headless --path . -s tests/monster_states_test.gd -- --scenario=walk_away  # też run_away, sidestep, dodge, escape, attack, noise, death
godot --headless --path . -s tests/door_test.gd               # drzwi: gracz, klucz, potwór otwiera/wyważa, kratka
godot --headless --path . -s tests/library_test.gd            # biblioteka: antresolę da się obejść dookoła
godot --headless --path . -s tests/lamps_test.gd              # zgaszone pokoje nie świecą, oprawy migoczą z żarówkami
godot --headless --path . -s tests/hiding_test.gd -- --case=blocked  # też unseen, seen, table; blocked = zajęte wyjście z szafki
godot --headless --path . -s tools/coverage_map.gd            # mapy pokrycia kamer -> docs/coverage/*.png
# sieć: dwa procesy
godot --headless --path . -s tests/net_test.gd -- --host
godot --headless --path . -s tests/net_test.gd -- --join=127.0.0.1
```
