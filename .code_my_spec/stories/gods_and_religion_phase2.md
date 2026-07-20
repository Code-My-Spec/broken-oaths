# Feudal MMO — Phase 2 Design: Gods & Religion

> ⏸️ **BACKLOG — Phase 2, DEFERRED build / not imported to CodeMySpec.**
> Authoritative design for the god layer (supersedes the earlier placeholder
> sketch). It is a **second parallel player type**, reached by ascension
> (research a religion → build the Grand Temple wonder → ascend), built on the
> existing tech / wonder / city / bank / lord-tension systems — NOT a new age.
> Lock via a Three Amigos pass and a Civ 6 numbers pass; gate the build behind
> first real-user feedback on the shipped rebellion loop. Related: the political
> ladder ([[political_systems_progression_backlog]]) and the deferred God-layer
> note in the feudal design bible.

## Concept Overview

Religion introduces a **second, parallel player type** that sits on top of the existing king layer. Kings control land, cities, and armies. Gods control faith, followers, missionaries, and miracles. The two systems are deliberately **orthogonal**: a god can have followers inside cities across many different kingdoms, and every king can be influenced by every god. Nobody "owns" religion the way they do in Civ VI — instead, faith becomes a web of soft power that overlays the whole political map, and gods become active participants in the intrigue: picking sides in wars, blessing armies, demanding tribute in temples, and pressuring kings through commandments.

The core fantasy: **kings fight over the ground, gods fight over the souls standing on it**, and each needs the other.

---

## How Gods Integrate — Systems Summary

**Second player type on the same world.** A world has some number of king slots and a smaller number of god slots (roughly 1/3–1/2 of the king count). God slots start empty ("latent") and are filled when a king chooses to ascend.

**Faith economy.** Faith is a per-god resource, generated from believing citizens, dedicated temples, and faith tiles. Gods spend faith on miracles and on unlocking new miracles via research. Faith accrues into a **bank** that must be manually collected (engagement mechanic, mirroring the gold bank).

**City-level religion.** Every city tracks the religious breakdown of its population as percentages. Whichever god is above 50% is the "majority" and unlocks the god's ability to act on that city. Religion is determined purely by follower counts per city — there is no separate "declared" religion.

**Communication layer.** A structured messaging system between kings and gods (prayer, commandment, covenant), backed by a favor metric — the religious analogue of the lord/vassal tension meter already in the MVP. Where possible these tie to **procedural conditions** so favor adjusts automatically when terms are met.

**The avatar.** Each god has one physical unit on the map that can fight, bless, and cast, and which enemy kings can kill (with no permanent consequence to the god).

**Persistence.** Gods can never be eliminated. A god always retains its holy city, guaranteeing it can rebuild followers and missionaries and re-enter the game.

---

## User Stories

### 1. Becoming a God (Ascension)

#### 1.1 Research and Found a Religion
**As a** king
**I want to** research the required technology and found a religion
**So that** I can establish a faith in the world

**How it works:**
- King researches the enabling technology (mirroring Civ — e.g. Monotheism)
- Founding a religion is a one-time action per king
- A king cannot otherwise "manage" a religion — founding is the only creative religious act available to the king role
- Founding unlocks the ability to build the Grand Temple

#### 1.2 Build the Grand Temple (Wonder)
**As a** king who founded a religion
**I want to** build a Grand Temple as a major wonder
**So that** my religion has a permanent home in the world

**How it works:**
- The Grand Temple is a wonder-level build — a serious, long-term commitment (well beyond a normal building; wonder-scale production cost)
- The Grand Temple becomes a **freestanding holy structure**, conceptually like Jerusalem or Mecca — it behaves like its own place on the map, not just a building inside an existing city
- The city that builds it (or the nearest city) becomes permanently anchored to this religion (see 3.2)

#### 1.3 Ascend to Godhood
**As a** king who founded a religion
**I want to** choose to ascend and become a god
**So that** I can play the faith layer instead of the territory layer

**How it works:**
- Only upon ascension does the player name the god and choose its domain/appearance
- If a king founds a religion but does **not** ascend, the religion still exists but its god slot remains latent (unclaimed) until someone ascends into it
- Once ascended, the player permanently switches from the king role to the god role — they no longer control cities or territory directly

#### 1.4 Ascended King's Kingdom Left Leaderless (Light AI)
**As** the game world
**I want to** leave an ascended king's kingdom under light AI until claimed
**So that** ascension has a real cost and opens opportunity for others

**How it works:**
- When a king ascends, their former kingdom becomes leaderless
- The kingdom stays in the world (cities, units persist) but has no active ruler
- **Light AI behavior:** the kingdom's units will attack any enemy unit that enters their territory, but otherwise take no action (no expansion, no production decisions, no diplomacy)
- A new player joining the world can take over that leaderless kingdom

#### 1.5 Limited God Slots Per World
**As** the game world
**I want to** cap the number of gods relative to kings
**So that** each god always presides over multiple kingdoms

**How it works:**
- Total god slots ≈ 1/3 to 1/2 of the number of king players on that world
- This guarantees gods are "shared" across multiple kingdoms, forcing the political web
- Gods are only ever player-controlled; an unclaimed slot is simply latent and inactive

---

### 2. Faith Economy

#### 2.1 City Religion Tracking
**As** the game world
**I want to** track each city's religious breakdown as percentages
**So that** multiple gods can compete for the same population

**How it works:**
- Each city tracks what percentage of its citizens follow each god (and how many follow none)
- A god above 50% in a city is the **majority religion** there
- Majority unlocks the god's interactions with that city (production queue injection, etc.)
- Minority religions still exist in the city and still generate some faith for their gods
- Religion is entirely follower-driven — there is no separately "declared" religion at the city or kingdom level

#### 2.2 Faith Generation
**As a** god
**I want to** generate faith from my believers and temples
**So that** I can fuel missionaries and miracles

**How it works (starting model, numbers pending Civ 6 research pass):**
- **Per-believer base:** each citizen who follows a god generates faith for that god (applies to minority religions too)
- **Temples:** each dedicated temple generates base faith/turn for the god it's dedicated to
- **Faith tiles (majority only):** citizens a king assigns to faith-producing tiles generate faith that flows to the **city's majority god**
- A god's total faith = the sum of these across every city in the world where they have any presence
- Gods do **not** produce faith directly by any action — it comes entirely from believers, temples, and assigned faith work

#### 2.3 Faith Bank (Manual Collection)
**As a** god
**I want to** manually collect accrued faith from a bank
**So that** the game rewards active engagement

**How it works:**
- Faith accrues into a bank rather than landing directly in the god's spendable pool
- The god must click to collect banked faith before it can be spent
- Directly mirrors the existing gold bank engagement mechanic on the king side
- *(Open: whether uncollected faith caps out or overflows — align with however the gold bank handles this.)*

#### 2.4 Faith Tiles and Citizen Assignment
**As a** king
**I want to** assign citizens to faith-producing tiles and buildings
**So that** I can show favor to a god

**How it works:**
- Following Civ conventions: certain tiles/improvements produce faith
- Kings assign citizens to work those tiles (as they do for food/production/gold)
- The resulting faith **always routes to the city's current majority god**
- This is a key lever kings use to court gods — dedicating labor to faith is a tangible offering
- *(If majority flips, subsequent faith-tile output routes to the new majority from that point forward.)*

---

### 3. The Holy City & Home Temple

#### 3.1 Grand Temple as Freestanding Holy Site
**As a** god
**I want to** have a permanent holy city anchored by my Grand Temple
**So that** I always have a base of operations

**How it works:**
- The Grand Temple functions as the god's headquarters and the anchor of their faith
- It's the respawn point for the avatar (see 6.2)

#### 3.2 Guaranteed Majority (Restart Safety)
**As a** god
**I want to** always keep majority in my home city
**So that** I can never be fully wiped out

**How it works:**
- The home city (the one that built the Grand Temple, or nearest to it) is permanently locked to majority for that god
- Even if a god loses followers everywhere else, the home city guarantees they can still queue missionaries and re-enter the world
- This is why gods can never be eliminated — they always retain their original city and temple

---

### 4. Missionaries & Conversion

#### 4.1 God Inserts Missionaries into Majority City Queues
**As a** god
**I want to** add missionaries to the production queues of cities where I'm the majority
**So that** I can spread my faith outward

**How it works:**
- Gods cannot freely spawn missionaries and do not spend faith to make them
- Instead, a god **inserts a missionary at the end of the production queue** of any city where they are the majority religion
- The city then produces that missionary using its normal production over time
- This ties a god's expansion capacity to how many majority cities they hold

#### 4.2 Missionary Movement and Conversion
**As a** god
**I want to** send missionaries into other cities to convert citizens
**So that** I can grow my share of the population

**How it works:**
- Missionaries are map units (unarmed) that move toward target cities
- On arrival, a missionary converts individual citizens over time
- Conversion shifts the city's religion percentages toward the missionary's god
- Kings can kill enemy missionaries with military units

#### 4.3 Conversion Math (Unbelievers vs. Believers)
**As** the game world
**I want** conversion to be easier on unbelievers than on committed believers
**So that** contested cities are sticky and meaningful

**How it works (starting model, numbers pending Civ 6 research pass):**
- Converting a citizen who follows **no god** is cheap/fast
- Converting a citizen who **already follows a rival god** is harder (costs more of the missionary's capacity, or converts at a slower rate)
- Example framing: a missionary has a pool of conversion "effort"; unbelievers cost 1 unit of effort each, rival believers cost 2 — exact numbers TBD

#### 4.4 Competing Missionaries
**As a** god
**I want to** contest cities where rival missionaries are active
**So that** religious spread becomes a real competition

**How it works:**
- Multiple gods can push missionaries into the same city
- They pull the percentages in opposite directions
- Majority can flip back and forth as different gods invest

#### 4.5 King Controls Missionaries When God Is Offline
**As a** king
**I want to** control the missionaries of my official religion when its god is offline
**So that** my state religion keeps spreading even when its god isn't playing

**How it works:**
- When a god is offline, the king whose majority religion matches that god may direct that religion's missionaries
- This keeps the faith active during downtime and gives loyal kings a stake in their god's success

---

### 5. Temples & Religious Buildings

#### 5.1 King Builds Dedicated Temples
**As a** king
**I want to** build temples dedicated to specific gods
**So that** I can host and empower the faiths I favor

**How it works:**
- Temples are normal buildings inside cities (not placed on their own tiles), following Civ
- Each temple must be **dedicated to a specific god** when built
- A dedicated temple generates faith for that god and strengthens their presence in the city
- A god gains the ability to have a temple built either by (a) already being the majority in that city, or (b) issuing a commandment that the king obeys by building it

#### 5.2 Multiple Gods Per City
**As a** king
**I want to** host temples to several gods in one city
**So that** I can play multiple gods off each other

**How it works:**
- A single city can hold temples dedicated to three or four different gods
- Each temple feeds its own god's faith
- This reinforces the "all kings can serve all gods" political web
- *(A future "religious district" system, following Civ, may eventually organize these.)*

---

### 6. The Avatar

#### 6.1 Avatar Unit
**As a** god
**I want to** have an avatar on the map
**So that** I can physically intervene in the world

**How it works:**
- Each god has one avatar — a strong military unit visible to all players
- The avatar can fight, and can cast miracles / bless from the field
- Following the Lord precedent, the avatar can take a "Pray"-style stance or dedicated actions (the king-side equivalent is assigning their Lord to pray)

#### 6.2 Avatar Death and Respawn
**As a** king at war with a god
**I want to** be able to kill a god's avatar
**So that** intervening gods take a real risk

**How it works:**
- If a god joins a war on one king's side, the opposing king can kill the avatar in battle
- A killed avatar respawns at the god's Grand Temple (home holy city)
- Avatar death has **no effect on the god** — the god keeps acting normally, keeps its faith, and can respawn indefinitely
- *(Future: once a unit leveling system exists, the avatar can gain levels and simply respawns at a lower level after death — the only real penalty.)*

#### 6.3 Avatar Aura and Unit Religion
**As a** god
**I want** my avatar to empower units that share my religion
**So that** faith translates into battlefield presence

**How it works:**
- Units take on a religion based on the **majority religion of the city they were produced in**
- The avatar influences/boosts units of its own religion (aura effects, blessings)
- This lets a god meaningfully tip a battle by showing up

---

### 7. Miracles

#### 7.1 Casting Miracles
**As a** god
**I want to** spend faith to cast miracles
**So that** I can intervene dramatically in the world

**How it works:**
- Miracles cost faith; cost varies by miracle
- There is a cooldown between miracles
- The god casts from a menu (with the avatar and/or map targeting as appropriate)

#### 7.2 Miracle Types
**As a** god
**I want** a variety of miracle effects
**So that** I have meaningful strategic choices

**Example miracles (following Civ-style effects where possible):**
- Summon units
- Empower units (combat buffs / blessings)
- Empower cities (production, growth, or defensive boosts)
- Damage an enemy city
- Blight or blast terrain
- Create resources on tiles

#### 7.3 Miracle Research (Faith-Funded)
**As a** god
**I want to** unlock new miracles over time
**So that** my power grows as I invest

**How it works:**
- A long-term research tree unlocks additional miracles
- **Research draws from faith** — the same resource used for casting, forcing a strategic tradeoff between casting now and investing in future power
- *(Exact costs and tree structure pending Civ 6 research pass.)*

#### 7.4 Miracle Constraints
**As** the designer
**I want** belief to be won on the ground, not by fiat
**So that** missionaries remain central

**Hard rules:**
- **No conversion miracles** — all belief change comes from missionaries converting citizens
- **No belief-altering miracles** of any kind
- **No city-founding miracles**
- Gods influence the world through units, terrain, cities, and blessings — never by instantly rewriting faith

---

### 8. God–King Communication

All three communication types share a single underlying abstraction (a directed request/agreement with optional procedural conditions and favor effects). Where possible, terms tie to **procedural conditions** so favor adjusts automatically on fulfillment.

#### 8.1 Prayer (King → God)
**As a** king
**I want to** pray to a god to request something
**So that** I can ask for divine help

**How it works:**
- A king sends a prayer requesting an action (e.g., "bless my army," "aid my defense")
- The god may grant or decline
- A god only refuses to bless a specific unit in the context of declining a prayer for it

#### 8.2 Commandment (God → King)
**As a** god
**I want to** issue commandments to kings
**So that** I can direct the mortal world toward my ends

**How it works:**
- A god commands a king to do something (build a temple, go to war, make peace, even submit to another king)
- The king **always decides** whether to obey — commandments are socially binding, not mechanically forced
- **Procedural tie-in (preferred):** e.g. the god commands "build a temple to me in City X"; when the king completes that temple, favor rises automatically. Refusal or expiry moves favor the other way
- The god decides any further consequences

#### 8.3 Covenant (Both Ways)
**As a** king and a god
**I want to** form covenants
**So that** we can strike binding-feeling deals

**How it works:**
- A covenant is a negotiated two-way agreement built on the same abstraction as prayers/commandments
- Example: the king agrees to build temples in his cities; the god agrees to fight on the king's side in a war
- Each side's obligation should tie to procedural conditions where possible, so fulfillment and favor changes are tracked automatically

#### 8.4 Favor Metric
**As** the game world
**I want to** track favor between each god and each king
**So that** the relationship has memory and stakes

**How it works:**
- Mirrors the lord/vassal tension meter already built for the MVP
- Following/refusing commandments, honoring/breaking covenants, building temples, and answering/ignoring prayers all move favor
- Procedural conditions drive favor changes automatically wherever possible
- Consequences of favor are god-decided and social rather than hard-coded (at least to start)

---

### 9. Gods in War

#### 9.1 God Picks a Side
**As a** god
**I want to** join a war on a king's side
**So that** I can shape the political map

**How it works:**
- A god may choose to back one king in a war (blessings, avatar, miracles)
- Doing so exposes the avatar to being killed by the opposing king (see 6.2)

#### 9.2 Blessings Menu
**As a** god
**I want** a map-wide blessing menu
**So that** I can empower units I favor

**How it works:**
- The god sees the map and can bless units from a menu
- Gods generally bless freely; the one time a god withholds a blessing is when declining a king's prayer for it

#### 9.3 Commanding Peace or Submission
**As a** god
**I want to** command kings to make peace or submit
**So that** I can impose religious order

**How it works:**
- A commandment can order a king to make peace
- A commandment can even order one king to submit (vassalize) to another
- As always, the king chooses whether to obey, at a favor cost

---

### 10. Official Religion (King Side)

#### 10.1 Majority Religion Drives Kingdom Alignment
**As a** king
**I want** my kingdom's religious alignment to follow my cities' majorities
**So that** faith stays grounded in actual followers

**How it works:**
- There is no separately declared state religion — alignment is emergent from city-level majorities
- The religion a king can act on behalf of (e.g., controlling missionaries when that god is offline, per 4.5) is determined by majority following
- Units produced inherit the majority religion of their production city (see 6.3)

---

## Deferred to Later (Post–Phase 2)

- Unit leveling system (and avatar levels / lower-level respawn)
- Religious districts (Civ-style) organizing temples
- Additional god-on-city interactions beyond production-queue injection
- Richer covenant tooling (auto-enforced terms, breach detection)

---

## Open Questions to Resolve Before Building

1. **Faith tuning.** Lock down per-believer, per-temple, and faith-tile output, plus missionary conversion effort costs for unbelievers vs. rival believers — via the Civ 6 research pass.
2. **Faith bank overflow.** Confirm whether uncollected banked faith caps or overflows, matching the gold bank's behavior.
3. **Faith-tile flip timing.** Confirm the exact turn behavior when a city's majority flips while citizens are assigned to faith tiles.
4. **Miracle economy.** Finalize faith costs for casting vs. research-tree unlocks (both draw from faith).
5. **Offline-god missionary control edge cases.** What happens if majority flips while a king is controlling an offline god's missionaries, or if the god comes back online mid-mission.

---

## Resolved Decisions Log

- Abandoned kingdoms run **light AI**: units attack enemies entering their territory, nothing else.
- **7.4 (avatar-death-weakens-god) dropped** — deferred as possible long-term direction, not committed.
- Commandments/prayers **prefer procedural conditions** (god commands temple in City X → king builds → favor rises automatically).
- **No unofficial/declared religion** — city religion is purely follower-count driven.
- **Commandment = god→king, Prayer = king→god, Covenant = both ways**; all three share one abstraction.
- Numbers to be locked via a **Civ 6 research pass**.
- **Faith tiles always route to majority religion.**
- **Miracle research draws from faith.**
- **Faith uses a bank-and-collect mechanic**, mirroring the existing gold bank.
