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

## Story 891 — Unit Combat

As a player, I want to attack adjacent enemy units with my military units, so that I can defend my territory and clear threats.

Source: .code_my_spec/stories/stone_age.md §10.1 plus combat clauses of §4.2: select a military unit or lord, attack an adjacent hostile unit; damage = strength − defense ± randomness (~20%); defender counter-attacks; both sides lose HP on the 100-HP scale; destruction at 0 HP removes the unit; combat result surfaced to the player; attacking exhausts the attacker's movement for the turn; retreating (moving away) is always an alternative. Lord grants +2 strength to adjacent friendly attackers (the aura itself is the Lord story; this story consumes it if present). Exact formula and randomness are Three Amigos decisions anchored to .code_my_spec/knowledge/stone_age_yields.md conventions.

- Warrior strikes the barbarian next door
- Two tiles is too far
- The blow lands now, not at the boundary
- Spent units cannot swing
- The stronger side hits harder
- The killing blow is not free
- Zero HP means gone
- The battle report
- Fighting beside the lord
- No friendly fire in the Stone Age
- A dying warrior swings soft

## Story 892 — Barbarian Camps Spawn

As a player, I want barbarian camps to form after I found my first city, so that I face a meaningful PvE challenge before I meet other players.

Source: .code_my_spec/stories/stone_age.md §3.1: founding a player's FIRST city spawns 4-6 camps in unexplored hexes 8-15 hexes out, concentrated toward region boundaries, with 1-2 inside the region; camps have 100 HP, render as a distinct camp marker once discovered, and spawn 1 Barbarian Warrior every 3 turns; barbarian warriors outclass Stone Age warriors (nominal 15/15/120 vs 10/10/100); destroying a camp stops its spawning and pays 30 gold (destruction mechanics live in Camp Assault); already-spawned units keep roaming. Founding ADDITIONAL cities spawns nothing (§4.4). Counts, radii, and cadence are Three Amigos decisions; the story owns the spawn trigger, placement, and spawn loop.

- The wilderness answers the first city
- Expansion is not punished twice
- A camp discovered is a camp marked
- Fog keeps its secrets
- The camp breeds on a cadence
- The cap holds overnight
- Born mean
- The attention warning

## Story 893 — Barbarian Behavior

As a player, I want barbarians to hunt, attack, and pillage on their own, so that the wilderness stays dangerous without another human involved.

Source: .code_my_spec/stories/stone_age.md §3.2: each turn boundary, barbarian units move 1 hex toward the nearest visible player unit or city; they attack player units on sight (no diplomacy), prioritize undefended cities over units, and never attack each other; moving onto a completed improvement pillages it (improvement removed from the tile); defeating a barbarian pays a small gold bounty (~10). City-attack resolution and garrison math belong to City Defense and Garrison; unit-vs-unit resolution belongs to Unit Combat — this story owns target selection, movement AI, and pillaging.

- The hunt closes in
- Out of sight, out of mind
- No parley
- They smell the undefended city
- Honor among savages
- The farm burns but the field remains
- The bounty

## Story 894 — Camp Assault

As a player, I want to destroy barbarian camps, so that they stop spawning warriors and I can claim the land.

Source: .code_my_spec/stories/stone_age.md §10.2: a military unit adjacent to a camp can attack it; the camp (100 HP) does not counter-attack; damage scales with unit strength, so clearing takes multiple turns; at 0 HP the camp is destroyed, the attacker's owner receives 30 gold, spawning stops, and the hex reverts to normal terrain (city founding and improvements allowed there); barbarian units already spawned remain. Depends on Unit Combat for the attack verb and Barbarian Camps Spawn for the target.

- Free hits on the tents
- Strength is the shovel
- The camp falls and the land opens
- Orphans keep fighting

## Story 895 — City Defense and Garrison

As a player, I want my cities to be defensive strongholds I can garrison, so that I survive barbarian attacks while my military grows.

Source: .code_my_spec/stories/stone_age.md §3.3 + §10.3 (one story, two angles): city defensive strength = base (20 + 5 × size) + garrisoned unit defense; units garrisoned in a city gain a +50% defensive bonus and can strike adjacent barbarians from inside; up to 3 units garrison one city; attackers take counter-attack damage from the garrison; city HP regenerates 5/turn when not under attack; at 0 HP the city is pillaged, not captured (loses 1 population, production halts 3 turns, HP resets to 50%); the player is alerted when barbarians close within 3 hexes and when the city is attacked. Depends on Unit Combat and Barbarian Behavior.

- The wall math
- Three fit in the keep
- The fourth sleeps outside
- Fighting from the walls
- The walls bite back
- Quiet nights mend walls
- Sacked but still mine
- The watchman's cry
- Room in the walls for the meek

## Story 896 — Lord Leads the Fight

As a player, I want my lord to be a battlefield anchor, so that I can beat barbarians my plain warriors cannot.

Source: .code_my_spec/stories/stone_age.md §4.1, combat-facing slice: the lord's superior stats (nominal Strength 12 / Defense 12 / HP 150) make it able to win 1v1 against a Barbarian Warrior with retreat-and-heal tactics; the lord grants +2 strength to adjacent friendly units in combat; exactly one lord per player, never disbandable or rebuildable; distinct crown presentation on the board. Already shipped in earlier batches: the lord unit itself, its HP scale, and healing (15/turn in city, 10 in territory... per the healing rules from batch 2). Lord-death consequences (vassal rebellion) stay deferred to the vassalization stories; Three Amigos should decide the interim death behavior.

- Braver beside the crown
- The aura has an edge
- No second crown
- The heir takes the throne
- You always know the king

## Story 897 — Configurable Turn Length

As a player, I want each world to run at its own turn pace, so that QA worlds resolve in seconds while live worlds keep their 60-second rhythm.

PM directive 2026-07-16 (raised during batch-3 Three Amigos): turn_seconds is a per-world field, default 60, set at world creation and immutable after; QA seeds create fast worlds (e.g. 5-second turns) so boundary-dependent tests and QA sessions stop idling a wall-clock minute per turn. The in-game countdown simply reflects the world's own length. No player-facing UI to change it.

- A fast world and a slow world coexist
- The countdown tells the truth

## Story 899 — Discovering Other Players

As a player, I want to be notified when my units first gain sight of another player's civilization, so that I know I am no longer alone and can begin interacting with my neighbor.

Source: .code_my_spec/stories/stone_age.md §8.1. When a player's unit or city vision first reveals another player's unit or city, both players are notified ("You have discovered X's civilization!"), each is added to the other's "Known Players" list, and the pair becomes mutually visible where vision overlaps and unlocked for chat. No PvP in the Stone Age — friendly fire stays disabled; discovery is the gate that turns two strangers into potential collaborators. Depends on Fog of War and Exploration (876) for the vision substrate. Chat itself is the Player-to-Player Chat story; cooperative fighting is the Cooperative Barbarian Fighting story. Notification surfacing and the Known Players UI are Three Amigos decisions.

- A scout sighting a stranger triggers discovery
- Sighting a barbarian is not discovering a player
- Discovery notifies both sides
- A known player stays known after leaving sight
- Discovery opens the chat channel
- Discovered does not mean omniscient
- No attacking a discovered player
- Discovery is both flashed and logged
- The Known Players panel lists discovered civilizations

## Story 900 — Player-to-Player Chat

As a player, I want to exchange real-time messages with players I have discovered, so that I can coordinate, negotiate, and socialize without leaving the game.

Source: .code_my_spec/stories/stone_age.md §11.1, merged with more_stories.md §9.1 (In-Game Chat) and §9.2 (Chat Notifications). Chat unlocks between two players once they discover each other; a chat entry point in the main UI opens a panel listing known players; selecting one opens a conversation thread; messages send on enter and arrive in real time via Phoenix PubSub; history persists (last 50 messages per conversation) with sender and timestamp; text only, capped at 500 characters. Unread state surfaces as a badge with a total count and per-contact counts, clearing on open. Depends on Discovering Other Players (the unlock) and the per-world PubSub substrate. Persistence schema, the character limit, and badge behavior are Three Amigos decisions.

- Chat is available with a discovered player
- No chat with an undiscovered player
- Selecting a known player opens the thread
- A message arrives in real time
- History loads on open
- Over-long messages are rejected
- Unread badge tracks incoming messages
- Older messages page in on demand
- Chat is per-world
- Profanity is filtered before delivery
- Blocking mutes both directions

## Story 901 — Cooperative Barbarian Fighting

As a player, I want to team up with a discovered neighbor against barbarians, so that we can clear camps neither of us could take alone and open the border between us.

Source: .code_my_spec/stories/stone_age.md §8.2. Two players who have discovered each other can focus the same barbarian target; their attacks accumulate against a camp or warrior across turns, the barbarian's counter-attacks fall on whichever attacker it faces, and the gold bounty for a kill or camp destruction is shared among the participants. Clearing the barbarians that concentrate on a shared border lets both players expand into the reclaimed land. Depends on Unit Combat (891), Camp Assault (894), and Barbarian Behavior (893) for the fight itself, and on Player-to-Player Chat for the coordination channel. How the bounty splits, and whether cooperation is explicit or emergent from shared targeting, are Three Amigos decisions.

- Two allies strike one camp
- Combined damage fells a camp over two turns
- A barbarian counters only its attacker
- Bounty is split in proportion to damage
- Sole attacker keeps the whole bounty
- Cleared border opens for expansion
- Allies form up to coordinate
- Even undiscovered attackers share the bounty

## Story 902 — Stone Age Technology Tree

As a player, I want to research technologies, so that I can unlock new units and buildings and advance toward the Bronze Age.

Source: .code_my_spec/stories/stone_age.md §6.1. A tech tree in the main UI with four Stone Age techs — Animal Husbandry (50 science), Pottery (50), Mining (75), Bronze Working (100). Cities generate science by population (2 per pop per turn), accumulating toward the ONE tech being researched at a time, shown with a progress bar. Completing a tech grants its benefit: Animal Husbandry → pastures (+2 food on animal resources), Pottery → granary (+2 food storage), Mining → workers build mines faster (3 turns not 5), Bronze Working → advances to the Bronze Age (guarded by a "This will advance you to Bronze Age. Continue?" confirm). The Bronze Age transition itself is the Advancing to Bronze Age story; per-turn science generation extends the city yield/growth systems (879/880). Exact science costs/rates and the pasture/granary yield hooks are Three Amigos decisions.

- Bigger cities research faster
- Science banks toward the chosen tech until it completes
- The tree lists the four Stone Age techs with costs
- Mining speeds up worker mines
- Pottery unlocks the granary
- Bronze Working asks before committing
- Research progress is visible
- Switching research and returning loses nothing
- Animal Husbandry unlocks pastures on animal resources

## Story 903 — Advancing to Bronze Age

As a player, I want completing Bronze Working to advance my civilization to the Bronze Age, so that I can field stronger units and more easily push back the barbarians.

Source: .code_my_spec/stories/stone_age.md §6.2. Completing Bronze Working research flips the player to the Bronze Age with a notification ("You have entered the Bronze Age! New units and buildings unlocked."), unlocks the Bronze Spearman (Strength 18 / Defense 18 / HP 120, 60 production — beats a Barbarian Warrior 1v1) and the Bronze Swordsman (20 / 15 / 110, 70 production — offense-focused), raises the city size cap from 4 to 6, and shows Bronze Age status in the player profile. Barbarians keep their Stone Age strength (the tech advantage is the point). Depends on Stone Age Technology Tree (the Bronze Working unlock) and rides the existing production/movement/combat/city-growth substrate (879/880/881/891). Exact stat/cost tuning is a Three Amigos decision.

- Bronze Working flips the age
- The Spearman outfights a barbarian
- Cities grow past the Stone Age cap
- A Stone Age city still caps at 4
- Barbarians don't scale up with the player
- Profile reflects the age

## Story 904 — Stone Age Progress Indicators

As a player, I want to see my progress toward the Bronze Age and my Stone Age milestones, so that I understand how close I am to advancing and what I have accomplished.

Source: .code_my_spec/stories/stone_age.md §12.1. A progress panel showing the current age (Stone Age), tech progress toward Bronze Working (science per turn, estimated turns to complete), and running totals — cities founded, barbarian camps destroyed, barbarians killed — plus first-time milestones (first city founded, first barbarian killed, first camp destroyed, first player discovered). Optional achievements ("Barbarian Hunter" = 10 barbarians, "City Builder" = 3 cities, "Explorer" = discover another player) are a stretch goal, decided at Three Amigos. Reads from the tech tree, combat, city, and discovery systems already shipped (879/880/891/894/899); the turns-to-Bronze estimate depends on the science-per-turn rate from Stone Age Technology Tree.

- Bronze Age progress at a glance
- Career totals so far
- Milestones mark on first achievement

## Story 905 — Tile Resources

As a player, I want special resources to sit on some tiles, so that certain terrain is worth settling near and improving.

Source: introduced as the substrate the tech tree's Animal Husbandry benefit lands on (story 902) and the foundation for future resource-based mechanics. Bonus resources (e.g. game/animals, and others) are placed deterministically from the world seed on suitable terrain, shown on the board, and grant a yield bonus when their tile is worked and/or improved — e.g. a Pasture built on an animal resource yields +2 food, gated by Animal Husbandry (story 902). Extends the existing terrain/yields/worker-improvement systems (878-882). This story is a PREREQUISITE for story 902's Animal Husbandry unlock and should be sequenced before the tech-tree batch. Exact resource set, placement density, per-resource yields, and which improvements/techs each requires are Three Amigos decisions informed by Civ 6 resource conventions (see the resource research to be written to .code_my_spec/knowledge/).

- Same seed, same resources
- Resources land on their eligible terrain
- An unworked Cattle tile already yields extra
- A Pasture on Cattle stacks to five food
- Pasture needs Animal Husbandry first
- Resources are visible from the first look
- A city works its resource tile first
- A resource-rich world has more than a sparse one