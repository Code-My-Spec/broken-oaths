# psql ground-truth evidence — story 891 Unit Combat QA

All queries against `psql broken_oaths_dev`, world_id = 1 ("QA World").

## World fresh at session start

```
select id, player_id, type, tile_id, hp, max_hp, movement, max_movement, camp_id
from game_units where world_id = 1;
-- (0 rows)
select id, player_id, tile_id, name, size, hp from game_cities where world_id = 1;
-- (0 rows)
select id, tile_id, hp, spawn_counter, destroyed_at from game_camps where world_id = 1;
-- (0 rows)
```

## Criterion 7538 "the killing blow is not free" / 7539 "zero HP means gone"

Warrior (id 17) vs barbarian (id 18) — before the attack:

```
 id |       type        | hp | movement
----+--------------------+----+----------
 17 | warrior            | 33 |        1
 18 | barbarian_warrior  | 22 |        0
```

Immediately after the right-click attack (`board_click.sh 14724 right`
with warrior 17 selected, standing adjacent on the city tile):

```
 id |  type   | hp | movement
----+---------+----+----------
 17 | warrior |  5 |        0
```
(barbarian 18 row: 0 rows — the killed defender's `game_units` row was
deleted entirely, not left at `hp: 0`.)

The attacker (warrior 17) took 28 damage (33 -> 5) in the SAME
exchange that killed the defender (barbarian 18, which had only 22 HP
and could not have survived a strike that killed it) — confirms both
sides' damage is computed from the same pre-combat strengths per
`Combat.resolve/3`, and that a killing blow still costs the attacker.
Movement dropped 1 -> 0 on the attacker in the same exchange (7536,
"spent units cannot swing" — the movement-zeroing half).

## Criterion 7539 "zero HP means gone" — repeated confirmations

Over the session, the following player-owned and barbarian units each
disappeared from `game_units` entirely (not `hp: 0` rows) the moment
their HP reached 0, confirmed by immediate before/after `select`:
barbarian id 9, barbarian id 16, barbarian id 18, barbarian id 22,
warrior id 17, warrior id 26, lord id 1, lord id 20, lord id 32 (the
last several via the Lord/heir-succession cycle — story 896's
territory, not re-litigated here, but each death independently
reconfirms "destruction at 0 HP removes the unit").

## Criterion 7540 "the battle report" / 7575 "a dying warrior swings soft"

Screenshot `05_lord_instant_attack_battle_report.png`: Lord at 18/150
HP (wounded_multiplier = 0.5 + 0.5*(18/150) = 0.56) attacked camp 1
(no living barbarian was on the clicked tile at that moment, so the
client fell through to a camp-assault order per `orderMove`'s
fallthrough — `Combat.camp_damage/2`, flat, no counter). Flash read
"dealt 7 · took 0". Lord's base strength is 12; effective strength =
12 * 0.56 = 6.72, which rounds to 7 — an exact match, live, for the
`effective_strength/2` wounded-penalty formula documented in
`lib/broken_oaths/game/combat.ex`, and confirmed independently by the
camp's own HP dropping 100 -> 93 in the same window:

```
select id, tile_id, hp, spawn_counter, destroyed_at from game_camps where world_id=1;
 id | tile_id | hp | spawn_counter | destroyed_at
----+---------+----+---------------+--------------
  1 |   14724 | 93 |             0 |
```

## City / camp adjacency (filed as issue ebe8abf1)

`board_state.sh 14724`'s `neighborsOfTarget` (computed from the
server-pushed tile corner geometry, edge-sharing test) included
`14725` — the founding city's own tile — confirming camp 1 spawned
directly adjacent to the city rather than the documented 8-15 hexes
out.
