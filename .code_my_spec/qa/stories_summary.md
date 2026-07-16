# Stories

## Story 873 — New Player Spawns in World

As a new player, I want to spawn with a settler and lord unit in an unexplored region of the hex globe, so that I can begin building my civilization from a safe starting position.

Source: .code_my_spec/stories/stone_age.md §1.1, trimmed to the pre-city substrate: joining an active world (or creating one), spawn placement far from existing players on valid terrain, the two starting units (Lord with crown icon, Settler), 50 starting gold, and the map centering on the spawn point. City founding, barbarians, and the welcome flow build on this in a later batch.

- Registered player picks a world and spawns
- Picking a world that just filled up fails gracefully
- Re-entering a joined world never re-spawns
- Returning player resumes where their civilization is
- Playing in two worlds at once
- Spawn delivers a Lord and a Settler on workable land
- Fresh spawn shows 50 gold
- A fourth world join is refused at the cap
- Abandoning wipes the civilization and reopens the region
- An abandoned region is a fresh start for its next claimant

## Story 874 — Automatic Turn Processing

As a player, I want turns to process automatically every 60 seconds, so that the game progresses continuously for everyone in the world without anyone having to press end-turn.

Source: .code_my_spec/stories/stone_age.md §5.1. The substrate version: a per-world turn timer (GenServer), a visible countdown and turn number in the UI, simultaneous execution of queued orders at the turn boundary, and real-time turn-completion updates to all connected players via PubSub. Production, combat, healing, and barbarian steps hook into this pipeline as they arrive in later batches.

- The countdown runs down and the turn advances by itself
- The world lives while everyone sleeps
- A server restart never loses or double-runs a turn
- Orders execute immediately and the boundary recharges movement
- Two connected players tick over together

## Story 875 — Queue Movement Orders

As a player, I want to select a unit and queue a movement order to an adjacent hex between turns, so that my units move when the turn processes.

Source: .code_my_spec/stories/stone_age.md §5.2 plus the selection substrate from more_stories.md §2.3: click a unit to select it and see its details (type, HP, movement remaining), click a destination hex to queue a validated move (terrain, movement points, blocking), see the queued path on the globe, change the order freely before the turn boundary, and have the move resolve — or fail gracefully — when the turn processes. Server-authoritative and LiveView-testable per the board doctrine.

- Clicking your lord shows the unit panel
- A settler walks a three-hex path: two hexes now, the third after the recharge
- A path blocked mid-journey halts the unit without losing it
- Only the latest remaining path executes
- Ocean and mountains refuse a land unit
- Two units racing for the same hex resolve to one occupant
- You cannot path onto your own unit
- An order into the fog of war is legal: right-clicking an unexplored spot on the globe queues a move there (the client sends the clicked sphere point; the server resolves the tile, since the fog-filtered client can't name tiles it has never seen), and the unit travels through unexplored terrain to reach it.
- A queued order's remaining path renders from the unit to its destination and shrinks as the unit walks

## Story 876 — Fog of War and Exploration

As a player, I want to see only the areas of the globe I have explored, so that the game has discovery and scouting mechanics.

Source: .code_my_spec/stories/stone_age.md §7.1. Three per-player visibility states on the hex globe: unexplored (hidden), explored-but-out-of-vision (terrain remembered, greyed, no live units shown), and currently visible (vision radius around own units — Lord sees farther). The exploration mask is server-owned per player and never leaks hidden tiles to the client; each player sees a different world. Cities extend vision when they arrive in a later batch.

- A fresh spawn sees a cloud-wrapped planet with one clear bubble
- The Lord out-scouts the Settler
- Terrain stays on the map after the scout moves on
- A stranger in remembered territory is invisible
- Two players see two different worlds
- Hidden tiles never travel over the wire
- Fog cloud and weather cloud read as different things

## Story 877 — Region Placement with Room to Expand

As a new player, I want to be placed in a region that allows me space for territorial expansion, so that I can grow my civilization without being immediately boxed in by neighbors.

The globe is divided into player regions — bounded territories a player can spawn into and reasonably fill. Source: .code_my_spec/stories/stone_age.md technical notes (~250 hexes per region, supporting 6-8 cities each) and §3.1 (barbarian camps concentrate at region boundaries as natural barriers between players); more_stories.md §1.2 sketches the same idea smaller. This is the mechanism behind "spawn far from existing players" in the spawn story: world capacity = number of regions, each new player claims an open one, and region edges are where players eventually meet. Region shape/assignment is server-owned and deterministic from the world seed.

- Same seed always produces the same region partition
- Every land and coastal tile belongs to exactly one region; deep ocean belongs to none
- Two new players land in different regions
- Simultaneous joins never double-claim a region
- Undersized island regions are never offered for spawning
- A full world turns new players away
- Mountains and coastal water count as country space
- A claimed region has room for about seven cities

## Story 878 — Settler Founds City

As a player, I want to use my settler to found a city, so that I can begin producing resources and units.

Source: .code_my_spec/stories/stone_age.md §2.1 plus more_stories.md §4.2: select the settler and found a city on valid terrain (not ocean/mountains, not too close to another city); the settler is consumed and a size-1 city appears with a default, renameable name; the city claims surrounding territory and can immediately begin production. The stone_age source also triggers barbarian camp spawning on the FIRST city — that consequence belongs to the future barbarian stories, not this one.

- A settler founds a city on the grassland it stands on
- Founding too close to an existing city is refused with a reason
- Founding trades the settler for a working size-1 city on the spot
- A fresh city in open land claims exactly seven tiles
- A neighbor founded at minimum spacing never steals claimed tiles
- A new city is named by default and renameable

## Story 879 — City Production Queue

As a player, I want to set production in my cities, so that I can build units and buildings over time.

Source: .code_my_spec/stories/stone_age.md §2.2 plus more_stories.md §5.1: open a city to see current production with a progress bar; choose from Settler (100), Worker (60), Warrior (40), Monument (60); the city accumulates production each turn based on size and worked tiles (size-1 base 5/turn); completed units spawn at the city (or an adjacent hex if occupied); buildings grant bonuses (Monument +2 culture/turn); multiple items can be queued.

- The city panel offers exactly Settler, Worker, and Warrior with costs
- A warrior completes after eight turns of flat banking
- Progress reads as banked-over-cost mid-build
- The queue rolls into the next item and keeps the change
- A finished unit lands beside a occupied city tile
- A completely blocked city holds the finished unit without losing it
- Reordering is free but abandoning mid-build costs the investment

## Story 880 — City Growth

As a player, I want my cities to grow larger over time, so that they become more productive.

Source: .code_my_spec/stories/stone_age.md §2.3 plus more_stories.md §5.2: cities start at size 1 and accumulate food from worked tiles each turn; the food threshold rises with size (size 2 needs 20, size 3 needs 30); reaching it grows the city by one population; each population works one additional hex (manual assignment or auto-assign); worked hexes yield food/production/gold; Stone Age cap is size 4 (Bronze Age raises it).

- Growth claims exactly one new tile beside the city
- Twenty banked food turns a hamlet into a town
- Each citizen works one tile beyond the free center
- A size-4 city stops growing until the age turns
- Yields stack: forested grassland hills feed and build at once

## Story 881 — Stone Age Warrior Production

As a player, I want to build warrior units, so that I can defend my cities and eventually push back threats.

Source: .code_my_spec/stories/stone_age.md §4.2 plus more_stories.md §4.4: cities produce Warriors for 40 production; stats Strength 10 / Defense 10 / HP 100; one hex movement per turn (rides the existing movement/turn substrate); heal 10 HP/turn stationary in friendly territory, 15 HP/turn garrisoned in a city. Combat resolution itself (attacking units/camps) is the future combat stories — this story delivers the producible, movable, healing unit.

- A city turns 40 production into a warrior on the map
- A warrior walks one hex per turn while a settler walks two
- Resting at home heals; garrison heals faster; the road heals nothing

## Story 882 — Worker Improves Terrain

As a player, I want to build workers to improve hexes, so that my cities generate more resources.

Source: .code_my_spec/stories/stone_age.md §4.3 plus more_stories.md §4.3: cities produce Workers for 60 production; workers move like other units; a selected worker can build improvements — Farm on plains/grassland (3 turns, +2 food), Mine on hills (5 turns, +2 production), Road on any land (2 turns, +1 movement); progress shows while building; completed improvements feed the owning city's yields. Workers are fragile (1 HP, no combat) — vulnerability consequences arrive with the barbarian/combat stories.

- A worker is a builder, not a fighter
- Three turns of digging turns grassland into a farm
- A worker helps a friend by farming their land
- An abandoned dig waits patiently for the next shovel
- A finished mine pays its city and refuses a second improvement

## Story 883 — Settler Production and Expansion

As a player, I want to build additional settlers, so that I can found more cities and expand my civilization.

Source: .code_my_spec/stories/stone_age.md §4.4: cities produce Settlers for 100 production; completing one costs the city 1 population, and a size-1 city cannot produce a settler (it would destroy the city); settlers move 2 hexes per turn; new cities must be at least 4 hexes from existing cities; founding additional cities does NOT spawn more barbarian camps (the first-city trigger is one-time).

- A settler is paid for in people
- A hamlet may not empty itself onto the road
- The map remembers what the census forgets
- The second city is founded like the first, minus the drama