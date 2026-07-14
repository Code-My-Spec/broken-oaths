# Feudal MMO Strategy Game - MVP Requirements

## Game Concept

A persistent, browser-based strategy game combining Civilization-style hex-based gameplay with Europa Universalis-style feudal mechanics. Players build civilizations, but instead of being eliminated when conquered, they become vassals who continue playing under their conqueror's rule. The core tension comes from lords extracting tribute vs vassals coordinating rebellions.

---

## Architecture Summary

### Technology Stack
- **Backend:** Phoenix/Elixir web framework
- **Database:** PostgreSQL for game state persistence
- **Real-time Communication:** Phoenix Channels & PubSub for live multiplayer updates
- **Frontend:** Phoenix LiveView for server-rendered UI with real-time updates
- **Map Rendering:** HTML5 Canvas with JavaScript for hex grid visualization
- **Hex Math:** Honeycomb.js library or custom implementation for hex coordinate calculations

### Architecture Pattern
**Server-Authoritative Model:**
- All game logic executes on the server (Phoenix backend)
- Client (browser) is primarily a rendering and input layer
- Game state stored in PostgreSQL, never trusted from client
- Real-time updates pushed from server to all connected clients via WebSockets

### Key Architectural Components

**1. Turn Processing System**
- GenServer process manages turn timer (60-second intervals)
- On each turn: resolves movement orders, processes city production, calculates combat, handles tribute payments, spawns barbarians
- Broadcasts turn completion to all players via PubSub

**2. LiveView Game Interface**
- Single-page application experience without JavaScript framework
- Server maintains game state, pushes updates to browser
- User interactions (clicks, forms) send events to server
- Server processes events and re-renders only changed portions of UI

**3. Canvas Hex Map**
- JavaScript hook attached to HTML Canvas element
- Receives hex data from LiveView (terrain, units, cities, fog of war state)
- Renders hexes with color-coded terrain
- Converts mouse clicks to hex coordinates and sends to LiveView
- Updates in real-time when server pushes new map data

**4. Real-Time Multiplayer**
- Players subscribe to PubSub channels: personal channel, world channel, region channel
- Events broadcast to relevant players: combat results, city captures, rebellions, turn completions
- Chat messages delivered instantly via PubSub
- Multiple players see same world state updating simultaneously

**5. Data Model**
- Core entities: Users, Worlds, Hexes, Units, Cities, Chat Messages
- Relationships: Vassalization (User → User), City Occupation (City → User), Tribute Demands (Lord → Vassal)
- Fog of war tracked per-player (which hexes each player has explored/can currently see)

---

## User Stories

### 1. Player Onboarding

#### 1.1 Player Registration

> ✅ Covered — implemented directly via phx.gen.auth (magic link + password); no story record needed.

**As a** new user  
**I want to** create an account  
**So that** I can join the game and save my progress

**What happens:**
- User visits registration page and enters username, email, password
- System validates uniqueness and password strength
- Account created with secure password storage
- User automatically logged in after registration
- Redirected to main game view

#### 1.2 New Player Spawns in World

> ✅ Imported to CodeMySpec — story 873 "New Player Spawns in World" (batch 1, merged with stone_age.md §1.1). Region placement split out as story 877.

**As a** new player  
**I want to** start with a settler and lord in a new region  
**So that** I can begin building my civilization

**What happens:**
- System generates a new region (~75 hexes) with varied terrain
- Region includes grassland, plains, forests, hills, and mountains
- 2-3 barbarian camps placed randomly in the region
- Player spawns with a Settler unit and a Lord unit on a grassland hex
- Player starts with 50 gold
- Player sees the map centered on their starting position

---

### 2. Game Interface

#### 2.1 Main Game View
**As a** player  
**I want to** see the game world and my civilization status  
**So that** I can make strategic decisions

**What's displayed:**
- Top bar: Player name, current gold, turn number, countdown to next turn
- Left sidebar: List of your units (type, location, health)
- Right sidebar: List of your cities (name, size, current production)
- Main area: Hex map showing visible terrain, units, cities
- Bottom panel: Details of selected unit or city
- Chat button with unread message indicator

#### 2.2 Hex Map Display
**As a** player  
**I want to** see terrain, units, and cities on a hex grid  
**So that** I can navigate and plan my actions

**What's displayed:**
- Each hex shows terrain type (colored appropriately: green for grassland, brown for hills, etc.)
- Your units appear as icons on hexes
- Enemy units appear if visible (in your vision range)
- Cities shown with city icon and name
- Unexplored areas are black/hidden
- Previously explored but currently out-of-vision areas are greyed out
- Fog of war updates as units move

#### 2.3 Selecting and Inspecting

> ✅ Partially imported — the unit-selection substrate landed in story 875 "Queue Movement Orders" (batch 1). City/hex inspection arrives with the city stories (878-880).

**As a** player  
**I want to** click units and cities to see details  
**So that** I can manage them

**What happens:**
- Click on your unit: highlights it, shows details in bottom panel (type, HP, movement remaining)
- Click on your city: opens city management screen
- Click on enemy unit/city: shows basic info (type, owner)
- Click on hex: shows terrain type, resources (if any), ownership

---

### 3. Turn System

#### 3.1 Automatic Turn Processing

> ✅ Imported to CodeMySpec — story 874 "Automatic Turn Processing" (batch 1, merged with stone_age.md §5.1).

**As a** player  
**I want to** turns to process automatically every 60 seconds  
**So that** the game progresses continuously

**What happens:**
- Timer counts down from 60 seconds, displayed at top of screen
- At turn boundary, all queued orders execute simultaneously
- Unit movements resolve
- Cities produce resources and build items
- Combat resolves
- Units heal if in friendly territory
- Tribute payments transfer from vassals to lords
- Barbarians spawn from camps
- All players see updates in real-time
- Timer resets to 60 seconds

#### 3.2 Queue Movement Orders

> ✅ Imported to CodeMySpec — story 875 "Queue Movement Orders" (batch 1, merged with stone_age.md §5.2).

**As a** player  
**I want to** queue movement for my units between turns  
**So that** they move when the turn processes

**What happens:**
- Select a unit
- Click destination hex on map (must be adjacent)
- System validates: unit has movement, destination is valid terrain, path not blocked
- If valid: yellow path shows queued movement
- If invalid: error message explains why
- Can change orders by selecting new destination
- When turn processes, unit moves to destination
- If destination becomes invalid (enemy moves there), movement fails gracefully

---

### 4. Units

#### 4.1 Lord Unit
**As a** player  
**I want to** control a powerful lord unit  
**So that** I can lead my armies and maintain my empire

**How it works:**
- Every player spawns with one Lord unit at game start
- Lord has superior combat stats (Strength 15, Defense 15, HP 150)
- Lord provides +2 strength bonus to adjacent friendly units in combat
- Lord unit has special crown icon on map
- Cannot be disbanded or rebuilt (one per player permanently)
- **Critical:** If your lord dies, ALL your vassals immediately rebel with high success chance
- Must protect your lord or risk losing your entire vassal empire

#### 4.2 Settler Founds City

> ✅ Imported to CodeMySpec 2026-07-14 — story 878 "Settler Founds City" (batch 2, merged with stone_age.md §2.1).

**As a** player  
**I want to** use my settler to found a city  
**So that** I can produce resources and more units

**What happens:**
- Select settler unit
- Click "Found City" button (appears when settler selected)
- Button disabled if location invalid (ocean, mountains, too close to another city)
- When clicked: settler disappears, new city appears on that hex
- City starts at size 1 with default name (can be renamed)
- City claims surrounding hexes (1-hex radius becomes city territory)
- City can immediately begin production

#### 4.3 Worker Improves Terrain

> ✅ Imported to CodeMySpec 2026-07-14 — story 882 "Worker Improves Terrain" (batch 2, merged with stone_age.md §4.3).

**As a** player  
**I want to** build workers to improve hexes  
**So that** my cities generate more resources

**How it works:**
- Cities can produce Worker units (costs 60 production)
- Workers can move like military units
- Select worker, choose "Build Improvement" action
- Available improvements: Farm (on plains/grassland), Mine (on hills), Road
- Improvements take multiple turns to complete (Farm: 3 turns, Mine: 5 turns)
- Worker shows progress while building
- Completed improvements provide yield bonuses to owning city
- Workers can be captured by enemy units (don't auto-delete in enemy territory)

#### 4.4 Warrior Military Unit

> ✅ Imported to CodeMySpec 2026-07-14 — story 881 "Stone Age Warrior Production" (batch 2, merged with stone_age.md §4.2). Attack mechanics deferred to the combat stories.

**As a** player  
**I want to** build warriors to defend and attack  
**So that** I can protect my territory and conquer others

**How it works:**
- Cities can produce Warrior units (costs 40 production)
- Warriors have attack strength 10, defense 10, HP 100
- Can move one hex per turn
- Can attack adjacent enemy units or cities
- Take damage when attacking, can be destroyed if HP reaches 0
- Heal slowly when stationary in friendly territory (10 HP per turn)

---

### 5. Cities

#### 5.1 City Production Queue

> ✅ Imported to CodeMySpec 2026-07-14 — story 879 "City Production Queue" (batch 2, merged with stone_age.md §2.2).

**As a** player  
**I want to** tell my cities what to build  
**So that** they produce units and buildings over time

**What happens:**
- Click city to open city management screen
- See current production with progress bar (e.g., "Warrior 25/40")
- See available things to build: Settler (100), Worker (60), Warrior (40), Monument (60)
- Click item to set it as current production
- Each turn, city accumulates production points based on size and worked tiles
- When production completes, unit spawns at city (or adjacent hex if city occupied)
- Buildings provide bonuses (Monument: +2 culture per turn)
- Can queue multiple items (build warrior, then settler, then worker)

#### 5.2 City Growth

> ✅ Imported to CodeMySpec 2026-07-14 — story 880 "City Growth" (batch 2, merged with stone_age.md §2.3).

**As a** player  
**I want to** my cities to grow larger over time  
**So that** they become more productive

**How it works:**
- Cities start at size 1
- Each turn, cities accumulate food based on worked tiles
- Food requirement increases with size (Size 2 needs 20 food, Size 3 needs 30, etc.)
- When food threshold reached, city grows by 1 population
- Each population point lets city work one additional hex
- Can manually assign which hexes citizens work (or use auto-assign)
- Worked hexes provide yields: food, production, gold
- Larger cities produce more but require more food

---

### 6. Combat

#### 6.1 Unit Attacks Unit
**As a** player  
**I want to** attack enemy units  
**So that** I can defeat their armies

**What happens:**
- Select your military unit
- Click adjacent enemy unit to attack
- Damage calculated: your strength minus their defense, plus randomness
- Enemy counter-attacks: their strength minus your defense
- Both units lose HP
- If unit reaches 0 HP, it's destroyed and removed from map
- Combat results shown in notification
- Attacker's movement exhausted for the turn
- Both players notified of combat outcome

#### 6.2 Unit Attacks City
**As a** player  
**I want to** attack enemy cities to capture them  
**So that** I can expand my territory and vassalize opponents

**What happens:**
- Select military unit adjacent to enemy city
- Click city to attack
- City has defensive strength based on size (base 20 + 5 per city size)
- City can be garrisoned with units for extra defense
- City takes damage and HP decreases
- City counter-attacks your unit
- When city HP reaches 0, capture occurs
- Capture dialog appears (for MVP just "Capture" button)
- City becomes occupied: original owner keeps city but you control it
- Original owner must pay you tribute from this city
- Check if this was their last free city → if yes, vassalization triggered

---

### 7. Vassalization System

#### 7.1 Automatic Vassalization
**As a** player who captures someone's last city  
**I want to** them to become my vassal automatically  
**So that** I benefit from their continued existence

**What happens:**
- When you capture a city, system checks if target player has any remaining free (non-occupied) cities
- If they have no free cities left, vassalization activates:
  - They become your vassal (marked in their UI with "Vassalized by [Your Name]")
  - They continue controlling all their cities but cities are "occupied"
  - Tribute demand created automatically: 25% of their gold income per turn
  - Both players notified
- Vassal can still move units, build things, research, play normally
- Vassal must pay tribute each turn
- You see them in your "Vassals" list with tribute settings

#### 7.2 Tribute Payments
**As a** lord  
**I want to** collect tribute from my vassals  
**So that** I benefit economically from my conquests

**What happens:**
- Each turn, tribute automatically calculated and transferred
- Calculation: vassal's gold income × tribute rate ÷ 100
- Gold deducted from vassal's treasury
- Gold added to your treasury
- Both players see transaction in their gold log
- If vassal has insufficient gold, they go into debt (negative balance)
- Tribute happens automatically, no action needed

#### 7.3 Adjust Tribute Rates
**As a** lord  
**I want to** change how much tribute each vassal pays  
**So that** I can balance extraction with keeping them content

**What happens:**
- Open "My Vassals" panel
- See list of vassals with current tribute rates
- Each vassal has slider or input (0-100%)
- Adjust rate as desired
- New rate takes effect next turn
- Vassal notified of change
- Higher rates = more income but higher rebellion risk
- Lower rates = less income but more stable vassals

#### 7.4 Voluntary Vassalization
**As a** player  
**I want to** voluntarily become someone's vassal  
**So that** I can gain protection from stronger players

**What happens:**
- Open diplomacy/chat with another player
- Click "Offer Vassalization" button
- Offer sent to target player
- Target sees notification with Accept/Decline buttons
- If accepted: vassalization relationship created (same as conquest)
- Default tribute rate: 25%
- Both players notified
- You're now their vassal and they're your lord
- Can declare independence at any time

---

### 8. Rebellion System

#### 8.1 City Flipping on Rebellion
**As a** vassal  
**I want to** my occupied cities to have a chance to flip to my side when I rebel  
**So that** I have armies and cities to fight with

**What happens:**
- Click "Declare Independence" button in your UI
- For each of your occupied cities, system calculates flip chance
- Base flip chance = tribute rate + (years vassalized × 5)
- Example: 40% tribute + 2 years = 50% flip chance per city
- Bonus if multiple vassals rebel together: +15% per additional rebel (max +45%)
- Roll dice for each city independently
- Cities that flip: occupation removed, garrisons defect to you, you control them again
- Cities that don't flip: remain occupied, must reconquer manually
- Rebellion army spawns: 2 warrior units per flipped city
- Warriors appear at flipped city locations
- If no cities flip, get 1 warrior at your capital as consolation
- Display results: "3 of 5 cities have joined your rebellion! 6 warriors rally to your cause!"

#### 8.2 Declare Independence
**As a** vassal  
**I want to** rebel against my lord  
**So that** I can stop paying tribute and regain freedom

**What happens:**
- Click "Declare Independence" in your UI (shows warning first)
- Vassalization relationship severed immediately
- Stop paying tribute
- War declared between you and former lord
- City flip mechanics trigger (see above)
- Lord notified: "[Your Name] has declared independence!"
- Occupied cities remain occupied unless they flipped
- Must reconquer occupied cities to fully liberate yourself

#### 8.3 Coordinated Multi-Vassal Rebellion
**As a** vassal  
**I want to** coordinate rebellion with other vassals via chat  
**So that** we have better odds of success

**What happens:**
- Vassals communicate via in-game chat
- Plan to all rebel on same turn (within 60-second window)
- Example chat: "Everyone rebel on turn 50!"
- When multiple vassals of same lord rebel on same turn, system detects it
- Coordination bonus applied: +15% flip chance per additional rebel
- If 3 vassals rebel together: each gets +30% flip chance (2 additional × 15%)
- All rebels notified: "3 vassals are rebelling together! Coordination bonus applied."
- Lord faces multiple simultaneous wars
- Combined armies make rebellion more viable

#### 8.4 Lord Death Triggers Massive Rebellion
**As a** player  
**I want to** understand the risk of losing my lord unit  
**So that** I protect it carefully

**What happens:**
- If your lord unit dies in combat:
  - ALL your vassals immediately rebel automatically
  - Each vassal gets +50% bonus to city flip chances
  - Massive empire collapse
  - You're notified: "Your lord has fallen! All vassals are rebelling!"
  - Each vassal processes rebellion independently (cities flip, armies spawn)
- Creates strategic target: enemies want to kill your lord to shatter your empire
- Must protect lord unit or risk catastrophic collapse
- Lord unit death is the ultimate empire-ending event

#### 8.5 Reconquer for Full Independence
**As a** vassal or former vassal  
**I want to** recapture my occupied cities  
**So that** I achieve full freedom

**What happens:**
- Attack your own occupied city (controlled by your former lord)
- Combat works normally (city has HP, defenders, etc.)
- When city HP reaches 0, you capture it
- Occupation status removed, city becomes fully yours again
- Special rule: If you recapture your original capital, gain immediate full independence even if other cities still occupied
- Notification sent to both players

---

### 9. Chat & Diplomacy

#### 9.1 In-Game Chat
**As a** player  
**I want to** send messages to other players  
**So that** I can negotiate, coordinate, and interact socially

**What's available:**
- Chat button in main UI (shows unread message count)
- Click to open chat panel
- See list of "known players" (players you've encountered - seen their units/cities)
- Click player name to open conversation thread
- Type message in text box, press enter to send
- Messages appear instantly for recipient (real-time)
- Chat history persists (loads last 50 messages per conversation)
- Each message shows sender and timestamp
- Text only, max 500 characters per message

**Example uses:**
- Negotiate alliances: "Let's not attack each other"
- Coordinate rebellions: "All vassals revolt on turn 50"
- Trade intel: "Player X is weak, attack now"
- Social interaction: "Good game!", "That was a close battle"
- Threats/diplomacy: "Pay me 100 gold or I attack your capital"

#### 9.2 Chat Notifications
**As a** player  
**I want to** know when someone messages me  
**So that** I don't miss important communications

**What happens:**
- Unread message badge appears on chat button
- Badge shows total unread count
- Individual players show unread count in contact list
- Opening conversation marks messages as read
- Badge updates in real-time when new messages arrive

---

### 10. Barbarians

#### 10.1 Barbarian Camps
**As a** new player  
**I want to** face barbarian threats early  
**So that** I have PvE content while building up

**What exists:**
- Each new region spawns with 2-3 barbarian camps
- Camps appear as red tent icons on map
- Camps have 50 HP
- Can attack camps to destroy them
- Destroying camp gives 20 gold reward
- Camps spawn barbarian warrior units periodically

#### 10.2 Barbarian Units
**As a** player  
**I want to** barbarians to threaten my territory  
**So that** I must maintain defenses

**What happens:**
- Barbarian camps spawn warrior units every 5 turns
- Barbarian warriors have same stats as player warriors (10/10 strength, 100 HP)
- Barbarians move randomly toward nearest player unit or city
- Barbarians attack on sight
- Barbarians attack undefended cities (but don't capture, just pillage for gold)
- Barbarians don't attack each other
- Defeating barbarians gives small experience (for future unit promotions)
- If camp destroyed, existing barbarian units continue roaming until killed

---

### 11. Fog of War

#### 11.1 Exploration and Vision

> ✅ Imported to CodeMySpec — story 876 "Fog of War and Exploration" (batch 1, merged with stone_age.md §7.1).

**As a** player  
**I want to** only see areas I've explored  
**So that** the game has discovery and scouting mechanics

**How it works:**
- Map starts completely black (unexplored)
- Units provide vision in 2-hex radius around them
- Cities provide vision in 2-hex radius
- Hexes within vision become explored
- Explored hexes remain visible (terrain shown) even when out of vision
- However, units/cities in explored-but-not-currently-visible hexes are hidden (greyed out)
- Must maintain vision to see current enemy positions
- Scouting is important for military intelligence
- Different players see different portions of map based on their unit/city positions

---

### 12. Testing Strategy

#### LiveView Testing Approach
**Why testing matters:**
- Game has complex multiplayer interactions (vassalization, rebellion, combat)
- Need confidence that rebellion mechanics work correctly
- Must ensure tribute calculations are accurate
- Combat damage and city capture logic must be reliable

**How LiveView enables testing:**
- Can simulate entire game flows in tests
- Click buttons, submit forms, verify outcomes
- Check database state after actions
- Verify real-time updates work correctly
- Test multiplayer scenarios (multiple players in same test)

**Example test scenarios:**
- New player registration → spawns with lord and settler
- Settler founds city → city appears in database correctly
- Warrior attacks enemy → damage calculated properly
- Capture last city → vassalization triggered
- Vassal rebels → cities flip based on tribute rate
- Lord dies → all vassals rebel immediately
- Chat message sent → recipient receives in real-time
- Turn processes → all queued orders execute
- Multiple vassals rebel together → coordination bonus applied

---

## Deferred to Phase 2 (Post-MVP)

**Features not in initial release:**
- Technology research tree
- Additional unit types (archers, cavalry, siege weapons)
- More building types beyond Monument
- Complex AI for barbarians (currently just random movement)
- Multiple worlds/servers with world generation
- Alliance system beyond informal chat coordination
- Production/research tribute demands (MVP only has gold tribute)
- Group chat rooms
- Trade between players
- Religion/culture mechanics
- Naval units and ocean exploration
- Diplomacy options like peace treaties, non-aggression pacts
- Leaderboards and rankings
- Player profiles and statistics

---

## Success Criteria for MVP

**MVP is successful if:**
1. Players can register, spawn, and see the game world
2. Players can move units and found cities
3. Cities produce units over time
4. Combat works (unit vs unit, unit vs city)
5. Capturing all cities vassalizes the player
6. Vassals pay tribute automatically each turn
7. Lords can adjust tribute rates
8. Vassals can rebel with city flipping mechanics
9. Multiple vassals can coordinate rebellions via chat
10. Lord death causes empire collapse (all vassals rebel)
11. Chat system allows real-time player communication
12. Turns process every 60 seconds automatically
13. All players see real-time updates (combat, rebellions, city captures)
14. Fog of war works correctly
15. Game is playable and fun for 5-10 concurrent players

**Key Gameplay Loop:**
1. Build cities and units
2. Expand territory
3. Conquer weaker players → they become vassals
4. Extract tribute from vassals
5. Protect your lord unit
6. Vassals coordinate rebellions to regain freedom
7. Political drama emerges from tribute/rebellion dynamics
