# Feudal MMO - Stone Age MVP User Stories

## 1. Player Onboarding & World Generation

### 1.1 New Player Spawns in World

**As a** new player  
**I want to** spawn with a settler and lord unit in an unexplored region  
**So that** I can begin building my civilization in a safe starting position

**Acceptance Criteria:**
- Player registration creates account and logs them in automatically
- System finds an active world with available capacity (or creates World 1 if none exist)
- World generation uses procedural terrain from seed (Perlin noise: ocean, grassland, plains, forest, hills, mountains)
- Globe wraps around (spherical world, not flat map)
- New player assigned random coordinates on globe far from existing players
- Player spawns with 1 Settler unit and 1 Lord unit on grassland hex
- Player starts with 50 gold
- Map displays centered on player's starting position
- Fog of war hides all unexplored hexes (shown as black)
- No barbarians exist yet (they spawn after first city is founded)
- Player sees welcome message: "Welcome to the Stone Age. Found your first city to begin."

---

## 2. City Founding & Territory

### 2.1 Settler Founds First City

**As a** player  
**I want to** use my settler to found my first city  
**So that** I can begin producing resources and units, even though this will trigger barbarian threats

**Acceptance Criteria:**
- Select settler unit and click "Found City" button
- Button disabled if on invalid terrain (ocean, mountains, too close to another city)
- When founded: settler unit disappears, city appears on that hex
- City starts at size 1 with default name (player can rename)
- City claims 3-hex radius territory (37 hexes total become city territory)
- City can immediately begin production (shows production queue UI)
- Founding first city triggers barbarian spawning in fog of war
- Player notified: "Your city attracts attention. Barbarian camps are forming in the wilderness."

### 2.2 City Production Queue

**As a** player  
**I want to** set production in my cities  
**So that** I can build units and buildings over time

**Acceptance Criteria:**
- Click city to open city management screen
- See current production with progress bar (e.g., "Warrior 25/40")
- Available productions: Settler (100), Worker (60), Warrior (40), Monument (60)
- Click item to set as current production
- Each turn, city accumulates production based on size and worked tiles
- Base production: Size 1 city = 5 production/turn, increases with size
- When production completes, unit spawns at city (or adjacent hex if city occupied)
- Buildings provide bonuses (Monument: +2 culture per turn)
- Can queue multiple items (build warrior, then settler, then worker)

### 2.3 City Growth

**As a** player  
**I want to** my cities to grow larger over time  
**So that** they become more productive

**Acceptance Criteria:**
- Cities start at size 1
- Each turn, cities accumulate food based on worked tiles
- Food requirement increases with size (Size 2 needs 20 food, Size 3 needs 30)
- When food threshold reached, city grows by 1 population
- Each population point lets city work one additional hex
- Can manually assign which hexes citizens work (or use auto-assign)
- Worked hexes provide yields: food, production, gold
- Larger cities produce more but require more food
- Maximum city size in Stone Age: 4 (Bronze Age unlocks larger cities)

---

## 3. Barbarian Threat System

### 3.1 Barbarian Camps Spawn After First City

**As a** player  
**I want to** barbarian camps to spawn after I found my first city  
**So that** I face a meaningful PvE challenge that requires me to develop my civilization before expanding

**Acceptance Criteria:**
- When player founds their first city, system spawns 4-6 barbarian camps in unexplored hexes within their region
- Camps placed 8-15 hexes away from player's city (not too close, not too far)
- Camps concentrated at region boundaries (natural barriers between players)
- 1-2 camps also spawn within player's region (ongoing threat)
- Barbarian camps appear as red tent icons on map when discovered
- Camps have 100 HP and can be attacked
- Each camp spawns 1 Barbarian Warrior every 3 turns automatically
- Barbarian Warriors have superior stats: Strength 15, Defense 15, HP 120
- Barbarians are stronger than Stone Age Warriors (10/10/100) - players lose 1v1
- Destroying a camp gives 30 gold reward and stops warrior spawning from that camp
- Existing barbarian units continue roaming even if camp destroyed

### 3.2 Barbarian Unit Behavior

**As a** player  
**I want to** understand how barbarians move and attack  
**So that** I can defend my cities and plan my expansion

**Acceptance Criteria:**
- Barbarian units move 1 hex per turn toward nearest visible player unit or city
- Barbarians attack player units on sight (no diplomacy possible)
- Barbarians prioritize attacking undefended cities over units
- Barbarians don't attack each other
- Barbarians pillage improvements (farms, mines) when they move through them
- Pillaged improvements provide 10 gold to barbarians (removed from map)
- Barbarians attack cities: city has defensive strength 20 + (5 × city size)
- Cities can garrison units for extra defense
- If city HP reaches 0, barbarians pillage it (city loses 1 population, production halted for 3 turns)
- Barbarians don't capture cities, just pillage them
- Defeating barbarians gives small gold reward (10 gold per kill)

### 3.3 Defending Against Barbarians in Cities

**As a** player  
**I want to** use my cities as defensive positions  
**So that** I can survive early barbarian attacks while building up my military

**Acceptance Criteria:**
- Units inside cities gain +50% defensive bonus
- City defense calculated as: city base defense + garrisoned unit defense
- Garrisoned units can attack adjacent barbarians from city
- City regenerates 5 HP per turn if not under attack
- Barbarians attacking cities take counter-attack damage
- Player notified when barbarians approach within 3 hexes of city
- Alert shows: "Barbarians approaching [City Name]! 3 hexes away."
- Can see barbarian unit count and estimated threat level
- Multiple units can garrison in same city (max 3 units)

---

## 4. Military Units

### 4.1 Lord Unit - Permanent Leader

**As a** player  
**I want to** control a powerful lord unit  
**So that** I can lead my early military efforts and survive barbarian threats

**Acceptance Criteria:**
- Every player spawns with one Lord unit at game start
- Lord has superior combat stats (Strength 12, Defense 12, HP 150)
- Lord provides +2 strength bonus to adjacent friendly units in combat
- Lord unit has special crown icon on map
- Cannot be disbanded or rebuilt (one per player permanently)
- Lord can defeat Barbarian Warriors 1v1 with proper tactics (retreat to heal)
- Lord heals 15 HP per turn when in friendly city
- Lord heals 5 HP per turn when in friendly territory (not in city)
- If lord dies: severe penalty (future feature: vassals rebel)

### 4.2 Stone Age Warrior Production

**As a** player  
**I want to** build warrior units  
**So that** I can defend my cities and eventually push back barbarians

**Acceptance Criteria:**
- Cities can produce Warrior units (costs 40 production)
- Warriors have stats: Strength 10, Defense 10, HP 100
- Warriors lose 1v1 against Barbarian Warriors (15/15/120)
- Warriors can win if: fighting from city (+50% defense), multiple warriors attack together, or lord provides +2 bonus
- Warriors can move one hex per turn
- Warriors can attack adjacent enemy units or barbarian camps
- Take damage when attacking, can be destroyed if HP reaches 0
- Warriors heal 10 HP per turn when stationary in friendly territory
- Warriors heal 15 HP per turn when garrisoned in city

### 4.3 Worker Unit Production

**As a** player  
**I want to** build workers to improve hexes  
**So that** my cities generate more resources

**Acceptance Criteria:**
- Cities can produce Worker units (costs 60 production)
- Workers can move like military units
- Select worker, choose "Build Improvement" action
- Available improvements: Farm (on plains/grassland), Mine (on hills), Road (on any land)
- Improvements take multiple turns: Farm (3 turns), Mine (5 turns), Road (2 turns)
- Worker shows progress while building
- Completed improvements provide yield bonuses to owning city
- Farm: +2 food, Mine: +2 production, Road: +1 movement (units move faster)
- Workers are vulnerable: barbarians can kill them (workers have 1 HP, no combat ability)
- Player warned when worker is threatened by barbarians

### 4.4 Settler Unit Production

**As a** player  
**I want to** build additional settlers  
**So that** I can found more cities and expand my civilization

**Acceptance Criteria:**
- Cities can produce Settler units (costs 100 production)
- City producing settler loses 1 population when settler completes
- Cannot produce settler if city is size 1 (would destroy city)
- Settlers can move 2 hexes per turn (faster than military)
- Settlers are vulnerable: barbarians can capture them
- Captured settlers give barbarians 50 gold, settler is destroyed
- Settlers can found new cities (same rules as initial settler)
- New cities must be at least 4 hexes from existing cities
- Founding additional cities does NOT spawn more barbarian camps

---

## 5. Turn System

### 5.1 Automatic Turn Processing

**As a** player  
**I want to** turns to process automatically every 60 seconds  
**So that** the game progresses continuously

**Acceptance Criteria:**
- Timer counts down from 60 seconds, displayed at top of screen
- At turn boundary, all queued orders execute simultaneously
- Unit movements resolve
- Cities produce resources and accumulate toward current production
- Combat resolves (player vs barbarian, barbarian vs city)
- Units heal if in friendly territory
- Barbarian camps spawn new warriors (every 3 turns)
- Barbarians move toward nearest targets
- All players see updates in real-time
- Timer resets to 60 seconds
- Turn number increments (displayed in UI)

### 5.2 Queue Movement Orders

**As a** player  
**I want to** queue movement for my units between turns  
**So that** they move when the turn processes

**Acceptance Criteria:**
- Select a unit
- Click destination hex on map (must be adjacent)
- System validates: unit has movement, destination is valid terrain, path not blocked
- If valid: yellow path shows queued movement
- If invalid: error message explains why
- Can change orders by selecting new destination
- When turn processes, unit moves to destination
- If destination becomes invalid (barbarian moves there), movement fails gracefully
- Unit can attack if destination contains enemy (queued attack)

---

## 6. Technology Research

### 6.1 Stone Age Technology Tree

**As a** player  
**I want to** research technologies  
**So that** I can unlock new units, buildings, and advance to Bronze Age

**Acceptance Criteria:**
- Tech tree available from main UI
- Stone Age techs available: Animal Husbandry (50 science), Pottery (50 science), Mining (75 science), Bronze Working (100 science)
- Cities generate science based on population: 2 science per population per turn
- Science accumulates toward current research
- When research completes, unlock benefits:
  - Animal Husbandry: Enables pastures (+2 food on animal resources)
  - Pottery: Enables granary building (+2 food storage)
  - Mining: Workers can build mines faster (3 turns instead of 5)
  - Bronze Working: **Advances player to Bronze Age** (unlocks better units)
- Can only research one tech at a time
- Tech progress shown with progress bar
- Researching Bronze Working shows warning: "This will advance you to Bronze Age. Continue?"

### 6.2 Advancing to Bronze Age

**As a** player  
**I want to** advance to Bronze Age  
**So that** I can access better units and more easily defeat barbarians

**Acceptance Criteria:**
- Completing Bronze Working research advances player to Bronze Age
- Player notified: "You have entered the Bronze Age! New units and buildings unlocked."
- Bronze Age unlocks: Bronze Spearman (Strength 18, Defense 18, HP 120, costs 60 production)
- Bronze Spearmen can defeat Barbarian Warriors 1v1
- Bronze Age unlocks: Bronze Swordsman (Strength 20, Defense 15, HP 110, costs 70 production)
- Bronze Swordsmen excel at offense against barbarians
- Cities can now grow to size 6 (up from size 4)
- Barbarians remain same strength (Bronze Age tech advantage is the point)
- Player can now more easily clear barbarian camps and expand toward neighbors
- Bronze Age status shown in player profile

---

## 7. Fog of War & Exploration

### 7.1 Vision and Exploration

**As a** player  
**I want to** only see areas I've explored  
**So that** the game has discovery and scouting mechanics

**Acceptance Criteria:**
- Map starts completely black (unexplored)
- Units provide vision in 2-hex radius around them
- Cities provide vision in 2-hex radius
- Lord unit provides vision in 3-hex radius (better scouting)
- Hexes within vision become explored
- Explored hexes remain visible (terrain shown) even when out of vision
- Units/cities in explored-but-not-currently-visible hexes are hidden (greyed out)
- Must maintain vision to see current barbarian positions
- Scouting with lord or warriors reveals barbarian camps
- Different players see different portions of map based on their unit/city positions

---

## 8. Player Interaction (Limited in Stone Age)

### 8.1 Discovering Other Players

**As a** player  
**I want to** be notified when I discover another player  
**So that** I know I'm no longer alone

**Acceptance Criteria:**
- When player's units gain vision of another player's unit or city, notification appears
- "You have discovered [Player Name]'s civilization!"
- Discovered player also notified: "[Your Name] has discovered your civilization!"
- Both players can now see each other's units/cities (when in vision)
- Chat unlocked between the two players (can now send messages)
- Discovered player shown in "Known Players" list
- Players can see each other's territory and cities
- No combat between players allowed in Stone Age (friendly fire disabled)
- Players can coordinate via chat to fight barbarians together

### 8.2 Cooperative Barbarian Fighting

**As a** player  
**I want to** coordinate with discovered neighbors to fight barbarians  
**So that** we can more easily clear barbarian camps together

**Acceptance Criteria:**
- Players who have discovered each other can chat
- Chat allows coordination: "Let's attack barbarian camp at (50, 75) together"
- Multiple players' units can attack same barbarian target
- Combined attacks deal cumulative damage
- Barbarian counter-attacks distributed among attackers
- Gold reward for killing barbarians/camps split among participants
- Players can plan coordinated attacks via chat
- Successfully clearing border barbarians allows both players to expand

---

## 9. Game Interface

### 9.1 Main Game View

**As a** player  
**I want to** see the game world and my civilization status  
**So that** I can make strategic decisions

**Acceptance Criteria:**
- Top bar: Player name, current gold, science, turn number, countdown to next turn
- Left sidebar: List of your units (type, location, health, movement remaining)
- Right sidebar: List of your cities (name, size, current production, science output)
- Main area: Hex map showing visible terrain, units, cities, barbarian camps
- Bottom panel: Details of selected unit or city
- Tech button opens technology tree
- Chat button (unlocked after discovering another player)
- Minimap showing explored world (optional for MVP)

### 9.2 Hex Map Display

**As a** player  
**I want to** see terrain, units, and cities on a hex grid  
**So that** I can navigate and plan my actions

**Acceptance Criteria:**
- Each hex shows terrain type: ocean (blue), grassland (green), plains (tan), forest (dark green), hills (brown), mountains (grey)
- Your units appear as icons on hexes
- Barbarian units appear as red skull icons if visible
- Barbarian camps appear as red tent icons
- Cities shown with city icon and name
- Your cities: blue border, enemy/neutral: grey border
- Unexplored areas are black
- Previously explored but out-of-vision areas are greyed out
- Fog of war updates as units move
- Hex grid lines visible for easy navigation
- Coordinates shown when hovering over hex

---

## 10. Combat System

### 10.1 Unit Attacks Unit

**As a** player  
**I want to** attack barbarian units  
**So that** I can defend my territory and clear threats

**Acceptance Criteria:**
- Select your military unit or lord
- Click adjacent barbarian unit to attack
- Damage calculated: your strength - their defense + randomness (±20%)
- Barbarian counter-attacks: their strength - your defense + randomness
- Both units lose HP
- If unit reaches 0 HP, it's destroyed and removed from map
- Combat results shown in notification: "Your Warrior dealt 25 damage, took 30 damage"
- Attacker's movement exhausted for the turn
- Can retreat (move away) instead of attacking
- Lord bonus applies if lord is adjacent to attacking unit (+2 strength)

### 10.2 Unit Attacks Barbarian Camp

**As a** player  
**I want to** destroy barbarian camps  
**So that** they stop spawning warriors

**Acceptance Criteria:**
- Select military unit adjacent to barbarian camp
- Click camp to attack
- Camp has 100 HP, no attack value (doesn't counter-attack)
- Each attack deals damage based on unit strength: Warrior (10 damage), Lord (12 damage), Bronze units (18-20 damage)
- Camp takes multiple turns to destroy
- When camp HP reaches 0, camp destroyed
- Player receives 30 gold reward
- Camp stops spawning barbarians
- Existing barbarian units from that camp remain on map
- Destroyed camp hex becomes normal terrain
- Can build city or improvements on former camp hex

### 10.3 Barbarian Attacks City

**As a** player  
**I want to** see how barbarians attack my cities  
**So that** I can prepare defenses

**Acceptance Criteria:**
- Barbarian moves adjacent to city and attacks
- City defense = base (20 + 5 × city size) + garrisoned unit defense
- Example: Size 2 city with warrior garrisoned = 30 + 10 = 40 defense
- Barbarian deals damage to city HP
- City counter-attacks barbarian (garrisoned unit's strength)
- City HP shown in city panel
- If city HP reaches 0: city pillaged (loses 1 population, production halted 3 turns, HP resets to 50%)
- Barbarians don't capture cities, just damage them
- Player alerted: "Your city [Name] is under attack!"
- Can garrison additional units to strengthen defense

---

## 11. Chat System (Unlocked After Discovery)

### 11.1 Player-to-Player Chat

**As a** player  
**I want to** send messages to players I've discovered  
**So that** I can coordinate barbarian defense or negotiate

**Acceptance Criteria:**
- Chat unlocked when two players discover each other
- Chat button in main UI shows when chat available
- Click chat to open chat panel
- See list of "known players" (players you've discovered)
- Click player name to open conversation thread
- Type message in text box, press enter to send
- Messages appear instantly for recipient (real-time via Phoenix PubSub)
- Chat history persists (loads last 50 messages per conversation)
- Each message shows sender and timestamp
- Text only, max 500 characters per message
- Unread message badge appears on chat button
- Badge shows total unread count

---

## 12. Victory/Progress Tracking

### 12.1 Stone Age Progress Indicators

**As a** player  
**I want to** see my progress toward Bronze Age  
**So that** I understand how close I am to advancing

**Acceptance Criteria:**
- Progress panel shows: Current Age (Stone Age), Tech progress toward Bronze Working
- Shows: Total cities founded, Total barbarian camps destroyed, Total barbarians killed
- Shows: Science per turn, Estimated turns to Bronze Working
- Milestones shown: First city founded, First barbarian killed, First camp destroyed, First player discovered
- Achievements (optional): "Barbarian Hunter" (kill 10 barbarians), "City Builder" (found 3 cities), "Explorer" (discover another player)

---

## Deferred to Bronze Age / Later Phases

**Not in Stone Age MVP:**
- Player vs Player combat (disabled in Stone Age)
- Vassalization mechanics (requires PvP)
- Tribute systems
- Rebellion mechanics
- Trade between players
- Religion/culture systems
- Naval units and ocean exploration
- Advanced diplomacy (alliances, treaties)
- God game mechanics (much later)
- Mayor appointment system (later ages)
- Multiple worlds (single world for MVP)

---

## Technical Notes

**World Generation:**
- Use Perlin noise for terrain generation
- Globe topology (wraps east-west and north-south)
- ~250 hexes per player region (supports 6-8 cities each)
- Seed-based generation (deterministic, can regenerate)

**Database Schema Highlights:**
- `worlds` table: seed, status, turn_number, age
- `users` table: username, current_world_id, gold, science
- `units` table: type, owner_id, world_id, x, y, hp, strength, defense
- `cities` table: name, owner_id, world_id, x, y, size, hp, production_queue
- `barbarian_camps` table: world_id, x, y, hp, last_spawn_turn
- Hexes generated on-demand from world seed (not stored)

**Turn Processing:**
- GenServer manages 60-second turn timer per world
- Phoenix PubSub broadcasts turn completion to all players
- LiveView updates UI in real-time

---

## MVP Success Criteria

**Stone Age MVP is successful if:**
1. Players can register and spawn in a procedurally generated world
2. Players can found cities and produce units
3. Barbarians spawn and pose a credible threat
4. Players must defend cities and build up military
5. Technology research works (can advance to Bronze Age)
6. Bronze Age units are noticeably stronger against barbarians
7. Players can discover each other and chat
8. Cooperative barbarian fighting is possible
9. Turn system processes smoothly every 60 seconds
10. Fog of war works correctly
11. Game is playable and challenging for 5-10 concurrent players
12. Players feel progression from "hiding in cities" to "clearing barbarians" to "meeting neighbors"
