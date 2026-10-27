class_name MonsterProfile
extends Resource
## Typ potwora jako dane. Nowy potwór to głównie nowy plik .tres w monster/profiles/
## (edytowalny w inspektorze Godota), a nie nowy kod. Kod dochodzi tylko wtedy,
## gdy potwór potrzebuje zupełnie nowego zachowania.

## HUNTER: reżyser kieruje go w okolicę graczy. PATROLLER: chodzi losowo po mapie.
## GUARD: pilnuje rewiru wokół gniazda. WATCHER: stoi w miejscu, wypatruje i krzyczy.
enum Behavior { HUNTER, PATROLLER, GUARD, WATCHER }
## HIT_AND_RETREAT: cios i odejście. EXECUTE: natychmiastowa śmierć bez powalenia.
## ABDUCT: porywa żywego gracza do gniazda. HIT_AND_RECOVER: cios, chwila bezruchu, potem wolniejszy pościg.
enum AttackStyle { HIT_AND_RETREAT, EXECUTE, ABDUCT, HIT_AND_RECOVER }

const DIRECTORY := "res://monster/profiles/%s.tres"

@export var id := "hunter"
@export var display_name := "Łowca"
@export var behavior := Behavior.HUNTER

@export_group("Wygląd")
@export var body_color := Color(0.08, 0.06, 0.06)
@export var eye_color := Color(1, 0.15, 0.1)
@export var height_scale := 1.0

@export_group("Prędkości")
@export var patrol_speed := 1.5
@export var investigate_speed := 2.4
## Chód gracza to 2.2, bieg 4.6: pościg wolniejszy niż bieg daje szansę ucieczki kosztem hałasu.
@export var hunt_speed := 3.8
@export var retreat_speed := 3.4
## Zryw (47g): na początku pościgu szybciej niż bieg gracza, żeby zauważenie z bliska było
## groźne, a nie tylko hałaśliwe. 0 = bez zrywu. Odnawia się po `burst_cooldown`.
@export var burst_speed := 0.0
@export var burst_time := 3.0
@export var burst_cooldown := 10.0

@export_group("Zmysły")
## 0 = ślepy. `sight_range_dark`: gracz w zgaszonym pokoju bez latarki (i bliska strefa, w której
## potwór zauważa od razu). `sight_range_flashlight`: gracz z latarką albo w oświetlonym pokoju;
## dalej niż bliska strefa potwór potrzebuje chwili, żeby go zauważyć.
@export var sight_range_dark := 6.0
@export var sight_range_flashlight := 14.0
@export_range(0.0, 360.0) var sight_angle_deg := 120.0
## Mnożnik zasięgu hałasu: 1.0 = słyszy tak daleko, jak hałas "niesie". 0 = głuchy.
@export var hearing := 1.0
## Z jakiej odległości wyczuwa krew (0 = nie tropi).
@export var smell_radius := 5.0

@export_group("Atak")
@export var attack_style := AttackStyle.HIT_AND_RETREAT
@export var attack_damage := 35
@export var attack_windup := 0.6
@export var attack_range := 1.4
@export var attack_reach := 2.0
## Porywanie: ile HP na sekundę traci porwany w drodze i w gnieździe.
@export var carry_damage_per_second := 3
@export var feed_damage_per_second := 6
## HIT_AND_RECOVER: ile stoi po ciosie i jak długo potem goni wolniej (ułamek prędkości).
@export var recover_time := 2.5
@export var slowed_time := 4.0
@export var slowed_factor := 0.6

@export_group("Dźwięk")
## Rozpoznawalna pętla typu (47g.6): słychać ją, zanim potwór pojawi się w kadrze, więc gracz
## wie, CO jest blisko, ale nie dokładnie gdzie. Bez niej zostaje wspólny oddech.
@export var presence_sound: AudioStream
## Z jakiej odległości słychać pętlę (m). Wzrok łowcy to 14 m: usłyszeć trzeba wcześniej.
@export var presence_range := 16.0

@export_group("Ruch")
@export var can_use_vents := false

@export_group("Strażnik")
## Promień rewiru wokół gniazda i jak daleko od gniazda najwyżej goni (smycz). Gracza, którego
## zgubi, nie szuka, tylko wraca do gniazda; smycz jest długa, żeby nie wyglądał, jakby bał się
## wyjść z pokoju.
@export var territory_radius := 9.0
@export var leash := 35.0


static func load_by_id(profile_id: String) -> MonsterProfile:
	return load(DIRECTORY % profile_id) as MonsterProfile
