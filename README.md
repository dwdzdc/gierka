# Gierka

Co-op survival horror z kamerą fixed (każdy gracz ma własne ujęcia). Godot 4.7.
Plan i postęp: [progress.md](progress.md).

## Uruchomienie

Potrzebny Godot **4.7** (standardowy, nie .NET/Mono).

**Linux**

```sh
# Arch: sudo pacman -S godot   (albo z AUR: yay -S godot-bin)
# Flatpak (działa na większości dystrybucji)
flatpak install flathub org.godotengine.Godot
flatpak run org.godotengine.Godot --path /ścieżka/do/gierka

# albo binarka z https://godotengine.org/download/linux/ (rozpakuj, chmod +x)
./Godot_v4.7.2-stable_linux.x86_64 --path /ścieżka/do/gierka
```

**macOS**: `brew install --cask godot`, potem `godot --path /ścieżka/do/gierka`.

**Po sklonowaniu (i po pullu z nowymi skryptami) najpierw zaimportuj projekt**, inaczej
gra wysypie się na `Could not find type ...`: cache klas (`.godot/`) nie jest w repo.

```sh
godot --headless --path /ścieżka/do/gierka --import
```

Otwarcie projektu w edytorze robi to samo.

## Gra po sieci

Host klika **Hostuj grę**: w lewym górnym rogu pojawia się jego IP. Reszta wpisuje to IP
i klika **Dołącz**. Port 7777/UDP, do 4 graczy.

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

WASD / strzałki: ruch (tank) · Shift: bieg · Q: obrót o 180° · F: latarka · Ctrl/C: kucanie · Spacja: skok · E (trzymaj): pomóż koledze / odbij porwanego / wyjdź windą · H (trzymaj): bandaż · Tab: następny kolega (po śmierci) · R: następna runda (host) · F1: HUD · Esc: wyjście

## Pokoje

Greyboxy pokoi generuje `python3 tools/gen_rooms.py` (nadpisuje `rooms/*.tscn`).
Kontrakt pokoju i drzwi: `rooms/room.gd`. Składanie mapy: `game/map_generator.gd`.

## Testy

```sh
godot --headless --path . -s tests/walk_test.gd        # przejście przez pokoje, log cięć kamery
godot --headless --path . -s tests/visibility_test.gd  # gdzie kamera nie widzi postaci
godot --headless --path . -s tests/map_test.gd -- --rooms=20  # generator: kolizje, determinizm, dostępność
godot --headless --path . -s tests/camera_rules_test.gd       # każde przejście widoczne z kamery swojej strefy
godot --headless --path . -s tools/coverage_map.gd            # mapy pokrycia kamer -> docs/coverage/*.png
# sieć: dwa procesy
godot --headless --path . -s tests/net_test.gd -- --host
godot --headless --path . -s tests/net_test.gd -- --join=127.0.0.1
```
