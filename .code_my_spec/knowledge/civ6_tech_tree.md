# Civ VI Tech / Science System — design reference for the Stone Age tech batch

Source: Civ VI research session 2026-07-17 (civ-research agent). Grounded in
CivFanatics (civfanatics.com/civ6/info/technology), the Well of Souls Civ VI
Analyst (well-of-souls.com/civ), and civilization.fandom.com. Feeds the Three
Amigos decisions for **story 902 (Stone Age Technology Tree)**, **903
(Advancing to Bronze Age)**, and **904 (Progress Indicators)**. Companion to
`stone_age_yields.md` (yields/growth) and `lib/broken_oaths/game/combat.ex`
(the Civ VI damage curve, already shipped).

Broken Oaths deliberately borrows Civ VI conventions but ships a simpler MVP:
no gold/culture/faith, no districts, no specialists, a hard size-4 city cap in
the Stone Age, and a single combat strength per unit (no attack/defense split).

---

## TL;DR — recommended defaults + open PM decisions

| # | Question | Recommended default | Story |
|---|----------|---------------------|-------|
| 1 | Is 2 science/pop/turn reasonable? | **Keep 2/pop.** It is ~4x Civ's 0.5/pop base, but pop is our *only* science lever (no districts/buildings), so it correctly absorbs what Civ splits across Campus + Library. | 902 |
| 2 | Are the 50/50/75/100 tech costs reasonable? | **Keep, with a tweak.** Roughly 2x Civ's cheap Ancient techs and ~= Civ's Bronze Working (80). Gives a ~40-70 turn full-tree pace at 4-8 sci/turn. Suggest **50 / 50 / 60 / 90** to keep beelines snappy. | 902 |
| 3 | Adopt a Eureka/boost mechanic for MVP? | **Adopt ONE flagship boost — Bronze Working "kill 3 barbarians" (+40%)** — because it reuses combat/barbarian systems already shipped. Defer the other three boosts to a fast-follow. Reserve a `boost` data field now. | 903 (+ 902 schema) |
| 4 | Is the single-tech Bronze Age gate sound? | **Sound — keep it.** Civ VI itself flips your era the moment you finish *any* next-era tech, so a one-tech gate is Civ-authentic. Gating specifically on Bronze Working is clearer than Civ's "any of N". | 903 |
| 5 | Bronze Spearman + Swordsman stats? | **Keep it single-strength** (our model has no attack/defense split — "18/18" and "20/15" are ambiguous). Ship **Spearman str 16, HP 120, ~60** (defensive) and **Swordsman str 20, HP 110, ~70** (offensive). See §5 for the redundancy warning: with no cavalry in the game, the Spearman's anti-cavalry identity is empty. | 903 |
| 6 | Tech tree UI scope? | Compact node tree + current-research **progress bar** ("X / Y sci, ~N turns"), checkmarks on done nodes, one boost pip if the eureka ships. | 904 |

**Still needs a human PM call:**
- Decision 3: one flagship eureka vs none vs all four (scope vs depth for MVP).
- Decision 5: ship **both** Bronze melee units or just one? Without cavalry they overlap; recommend differentiating by strength-vs-HP (below) or cutting to one.
- Decision 5b: do we ever want a real attack/defense split? If yes, that is a combat-model change beyond this batch — flag it now so `combat.ex` isn't reworked twice.

---

## 1. Science generation

**What Civ VI does.** Science comes from three stacking sources:
- **Base population:** each Population point yields **0.5 science/turn**, everywhere, with or without a Campus.
- **Palace / city center:** the Palace grants a small flat **+2 science**.
- **Campus district + buildings:** a Campus specialist citizen yields **+2 science each**; the **Library** (needs Writing) adds **+2 science**; plus mountain/rainforest adjacency. This is where the real science comes from mid-game.

So a small Ancient-era Civ city (say size 4, no Campus yet) makes roughly `2 (palace) + 4*0.5 = 4 science/turn`. With an early Campus + a couple of specialists it climbs to ~8-10.

**Broken Oaths recommendation.** Our source doc proposes a flat **2 science/pop/turn** and nothing else — no palace flat bonus, no districts. That is **~4x Civ's 0.5/pop base**, but it is the *right* call because population is our only science source: the flat 2/pop rolls Civ's palace + specialists + Library into one number. At the Stone Age size-4 cap that is a hard ceiling of **8 science/turn**, ramping from ~2-4 while the city grows. That ceiling is a feature — it bounds how fast the 4-tech tree can be cleared.
- **Keep 2/pop.** If pacing feels too fast in playtest, drop to 1.5/pop rather than adding a second science source (keep the MVP single-lever).
- Do **not** add a palace flat bonus or per-tile science; it fights the "pop is everything" model in `stone_age_yields.md`.

## 2. Tech costs

**What Civ VI does** (base game, standard speed). Ancient-era costs are cheap and rise within the era:

| Tech | Civ VI cost | Eureka condition (+50%) | Key unlocks |
|------|------------:|--------------------------|-------------|
| Pottery | 25 | — (no boost) | Granary |
| Animal Husbandry | 25 | — (no boost) | Pasture, Camp |
| Mining | 25 | — (no boost) | Mine, Quarry |
| Sailing | 50 | Found a coastal city | Galley, Fishing Boats |
| Astrology | 50 | Find a Natural Wonder | Holy Site, Shrine |
| Irrigation | 50 | Farm a resource | Plantation |
| Writing | 50 | Meet another civ | Library, Campus |
| Archery | 50 | Kill a unit with a Slinger | Archer |
| Masonry | 80 | Build a Quarry | Walls, Battering Ram |
| **Bronze Working** | **80** | **Kill 3 barbarians** | **Spearman, Encampment, Barracks** |
| The Wheel | 80 | Build a Mine | Heavy Chariot, Water Mill |
| Iron Working (Classical) | 120 | Build an Encampment district | **Swordsman** |

Scaling: Ancient 25-80, Classical ~120-200, Medieval ~275-355, escalating per era.

**Broken Oaths recommendation.** Our proposed **50 / 50 / 75 / 100** (Pottery / Animal Husbandry / Mining / Bronze Working) is a reasonable "roughly double Civ's cheap techs, keep Bronze Working near Civ's 80". Pacing math at our 4-8 sci/turn:
- Full tree = 275 science ≈ **35-70 turns** depending on city growth.
- Beeline to Bronze Working (100 alone) ≈ **13-25 turns** — a satisfying mid-game milestone.

That is solid. One small tweak: **50 / 50 / 60 / 90** flattens the Mining bump and shaves the Bronze Working beeline so the "power spike" tech doesn't feel like a slog against the size-4 science ceiling. Either set works; present 50/50/75/100 as the safe default and 50/50/60/90 as the "snappier" option.

## 3. Eureka / boosts

**What Civ VI does.** Every tech (except a few tier-1s like Pottery/Mining/Animal Husbandry) has a **Eureka**: perform a thematically-linked action and instantly bank **50% of that tech's science** for free (modifiable up/down by policies like *Natural Philosophy*). It is Civ VI's signature "learn by doing" hook — it rewards playing toward the tech you want and makes the tree feel reactive. The UI shows an unlit lightbulb on each boostable node that lights up when earned. Examples above; the archetypal one is Archery ("kill a unit with a Slinger").

**Broken Oaths recommendation.** **Adopt the mechanic, but wire only one boost for MVP.**
- **Ship the Bronze Working eureka** — *kill 3 barbarians* grants **+40%** (40 of 100 science). It reuses the combat system, barbarian warriors, and camps already in the codebase (stories 891-897); it costs almost nothing to implement; it teaches the mechanic; and it rewards exactly the military play this batch is about.
- **Defer the other three** to a fast-follow, but **reserve the data field now** (each tech gets an optional `boost: %{condition, amount}`) so 904+ can drop them in without a migration.
- Use **40%** (not Civ's 50%) so a boosted tech still takes a couple of turns of accrual — boosts should accelerate, not trivialize, at our low science numbers.

Suggested boosts if/when all four ship (chosen to reuse existing systems and avoid circular prereqs):

| Tech | Suggested boost (condition) | Amount | Why it fits |
|------|-----------------------------|-------:|-------------|
| Pottery | Grow a city to **size 2** | +40% | You feel the need to *store* food — thematically the Granary. |
| Animal Husbandry | **Kill 1 barbarian** (or build first improvement) | +40% | Reuses combat; avoids the pasture-needs-AH circularity. |
| Mining | A city **works a hills tile** | +40% | Hills are the mineable terrain (`stone_age_yields.md`). |
| **Bronze Working** | **Kill 3 barbarians** | +40% | Straight from Civ; the flagship, ship this one first. |

## 4. Era / age advancement

**What Civ VI does.** Civ VI does **not** gate an era on one specific tech. You advance to the next era when you either (a) research **any single tech OR civic** belonging to the next era, or (b) complete **all** techs/civics of your current era. So in practice the *first next-era tech you finish* flips your era. (Separately, the culture-driven "Golden/Dark Age" system uses Era Score — not relevant here.)

**Broken Oaths recommendation.** Gating the **Bronze Age behind the single tech Bronze Working is sound and Civ-authentic** — Civ itself flips eras on one tech. Designating *one specific* tech (rather than Civ's "any of N") is actually *clearer* for players in a 4-tech tree.
- **Keep the single-tech gate.** Tradeoffs to accept: no partial-credit era progress (fine — the boost gives the "almost there" feel), and a player can beeline Bronze Working and skip Pottery/AH/Mining. That skip is acceptable because the other three are economy techs the player will still want; if it becomes a problem, require **Bronze Working + any one other tech** as a v2 gate. Do not require all four — that removes player agency and slows the batch's payoff.

## 5. Unit unlocks around Bronze Working

**What Civ VI does.** Bronze Working (Ancient) unlocks the **Spearman** (melee **str 25**, ~65 prod), the **Encampment** district, and the **Barracks**. The Spearman is an **anti-cavalry** unit — cheap, with a big combat bonus *only vs cavalry*; against everything else it is a mediocre defender. The generalist melee upgrade, the **Swordsman** (**str 35**, ~90 prod, needs Iron), comes one era later at **Iron Working** and requires the Iron resource. Reference melee ladder: Warrior **20** → Spearman **25** → Swordsman **35** → Horseman **35**.

**Broken Oaths recommendation.** Broken Oaths compresses two Civ eras' worth of units (Spearman + Swordsman) onto the single Bronze Working tech. That is fine for MVP, but **two warnings**:

1. **No attack/defense split exists.** `combat.ex` uses a *single* `base_strength` per unit (`warrior: 10, barbarian_warrior: 15, lord: 12`) inside the damage curve `30 * e^(0.04 * (attacker_str - defender_str))`. The source's "18/18" and "20/15" notation implies separate attack/defense — **our model has no such split**. Adopting it is a combat-model change beyond this batch; if we don't want that, collapse each unit to one strength number. **Recommend staying single-strength.**

2. **The Spearman's anti-cavalry identity is empty** — Broken Oaths has no cavalry, so a Spearman and Swordsman at the same tech are near-redundant. Differentiate them by **strength vs HP** within the single-stat model, or cut to one Bronze unit.

Recommended stats (single-strength model; existing Warrior = str 10 / HP 100, Barbarian Warrior = str 15 / HP 120):

| Unit | Strength | HP | Cost | Identity |
|------|---------:|---:|-----:|----------|
| Warrior (existing) | 10 | 100 | — | Stone Age baseline |
| Barbarian Warrior (existing) | 15 | 120 | — | The threat to beat |
| **Bronze Spearman** (rec.) | **16** | **120** | **~60** | Defensive / garrison: tanky, out-lasts barbarians |
| **Bronze Swordsman** (rec.) | **20** | **110** | **~70** | Offensive: highest strength, the attacker |

vs the source's proposal (Spearman 18/18/120 @60, Swordsman 20/15/110 @70): the source numbers are **reasonable** — I only nudge the Spearman down to **str 16** so the Swordsman (20) is unambiguously the premium attacker while the Spearman leans on its 120 HP for the defensive role. Source's Swordsman str 20 / HP 110 / cost 70 I'd keep as-is.

Damage-curve sanity check (why these feel right against barbarians, str 15):
- Swordsman (20) striking barb (15): `30·e^(0.04·5) = 37` dmg dealt, takes `30·e^(-0.2) = 25` back — decisive.
- Spearman (16) striking barb (15): `30·e^(0.04·1) = 31` dealt, takes `29` back — even trade on strength, wins on its extra HP. Correct for a defensive unit.
- Both nearly **double the Warrior's str 10**. That is a bigger jump than Civ's Warrior→Spearman (+25%), but appropriate: Bronze Working is our *single* power-spike tech and a whole era gate, so the reward should feel decisive. If playtest shows it's oppressive, dial to str 14/16 for a Civ-like incremental feel.

> Note: because our strengths are compressed to ~half of Civ's but `combat.ex` keeps Civ's `0.04` coefficient, a given strength *gap* produces a smaller damage swing than in Civ. That is why the recommended Bronze strengths sit well above the Warrior — the compressed scale needs a wider gap to feel like a tier jump.

## 6. Tech tree UI conventions (light — for story 904)

**What Civ VI does.** A horizontal node graph: each tech is a card with cost, icon, and the units/buildings it unlocks; **prerequisite lines** connect nodes; the **currently-researching** node shows a filled progress ring/bar with accumulated/total science and **turns-remaining**; completed nodes are filled/checked; each boostable node shows a **lightbulb** that lights up when its Eureka is earned; hovering shows the full unlock list.

**Broken Oaths recommendation** (keep it minimal — 4 nodes):
- A compact node strip/tree of the four Stone Age techs with simple prereq links (Pottery/AH/Mining as early picks, Bronze Working as the capstone gate).
- **Current-research progress bar** in the main UI: `accumulated / total science` and `~N turns` at the current science/turn — this is the core of story 904.
- **Checkmark / filled state** on completed techs; a lock or dimmed state on Bronze Working until prereqs (if any) are met.
- If the eureka ships, a single **boost pip / lightbulb** on Bronze Working that lights when "3 barbarians killed" fires and visibly chops the bar.
- Show each tech's **unlock** inline (e.g. "Bronze Working → Bronze Age, Spearman, Swordsman") so the tree doubles as the "why research this" prompt.

---

## Sources
- CivFanatics — Technologies: https://civfanatics.com/civ6/info/technology/
- Well of Souls Civ VI Analyst — Technology: https://well-of-souls.com/civ/civ6_technology.html
- Well of Souls Civ VI Analyst — Units: https://www.well-of-souls.com/civ/civ6_units.html
- Well of Souls Civ VI Analyst — Cities (science): https://well-of-souls.com/civ/civ6_cities.html
- Science (Civ6), Eureka (Civ6), Era (Civ6), Bronze Working (Civ6), Spearman (Civ6) — civilization.fandom.com
