# Civ VI Tile Resources — design reference for the Tile Resources story (905)

Source: Civ VI research session 2026-07-17. Grounded in the Civilization Wiki
(civilization.fandom.com Resource / Cattle / Sheep / Deer / Pasture pages),
its civ6.fandom.com mirror, and gamepressure.com's Civ VI resources guide.
Feeds the Three Amigos decisions for **story 905 (Tile Resources)**, the
prerequisite substrate that gives **Animal Husbandry → Pasture** (story 902)
something to improve. Companion to `civ6_tech_tree.md` (the Stone Age tech
batch) and `stone_age_yields.md` (canonical terrain yields, growth, expansion).

Broken Oaths deliberately borrows Civ VI conventions but ships a simpler MVP:
food/production only (no gold/culture/faith economy), no amenities/housing, no
districts/specialists, a size-4 Stone Age city cap, seed-deterministic world
generation with **zero RNG**, and improvements limited to Farm / Mine / Road
(story 882). Story 905 introduces the **first tile-resource layer** — there is
none today.

---

## TL;DR — recommended default + open PM decisions

| # | Question | Recommended default | Notes |
|---|----------|---------------------|-------|
| 1 | Which resource categories ship in the MVP? | **Bonus resources only.** Defer luxury (amenities) and strategic (unit-gating) entirely. | §1, §6 |
| 2 | Minimal resource set? | **Four bonus resources: Cattle, Sheep, Wheat, Stone.** Cattle + Sheep are the animal resources Animal Husbandry needs; Wheat + Stone make the layer feel non-trivial and reuse Farm/Mine. | §2 |
| 3 | Include Deer (a production animal)? | **Defer, or fold into Pasture.** In Civ, Deer's improvement is a **Camp**, not a Pasture, and story 902's tech tree has no Camp. Options in §2. | §2 |
| 4 | Pasture yield + gate? | **Pasture = +2 Food, unlocked by Animal Husbandry** — exactly as story 902 already specifies. Built only on animal resources (Cattle, Sheep). | §4 |
| 5 | Placement model? | **Deterministic from the world seed**, terrain-constrained, ~one resource per ~12-15 land tiles (roughly Civ's density). Reuse the story-880 "zero RNG" pattern. | §3 |
| 6 | Resource base yield (before the improvement)? | **+1 to the resource's signature yield** (Cattle/Sheep/Wheat +1F, Stone +1P), stacking on the tile's terrain yield — Civ-authentic. | §2, §5 |

**Still needs a human PM call:**
- Decision 2/3: exact set — animal-only (Cattle + Sheep) vs the four-resource
  set (add Wheat + Stone) vs also adding Deer. Recommended default is the
  four-resource set; Deer deferred.
- Decision 5: target density number (one resource per N land tiles) and whether
  resources may co-locate with a city-center tile.

---

## 1. Civ VI resource categories

Civ VI has four resource classes (artifacts/antiquities are a late-game
archaeology mechanic and irrelevant here). The three that matter:

**Bonus resources.** Purely local yield boosts — extra **Food, Production, or
Gold** on the tile. They are visible from the start, cannot be traded, and gate
nothing. Their whole job is "this tile is a bit better." Each needs a specific
tech to be *improved* (and to be *harvested* for a one-time yield dump). This is
the simplest class and the only one an early MVP needs.

**Luxury resources.** Provide **+1 Amenity** (happiness) to the four neediest
cities that lack that luxury, plus a varied tile yield (often Gold/Faith/Culture/
Science). They can be traded diplomatically. Amenities are an entire subsystem
Broken Oaths does not have.

**Strategic resources.** Military-gating (Horses, Iron, Niter, Coal, Oil, etc.).
Improving them yields a per-turn **stockpile** consumed to build and maintain
specific units/buildings. Most are **invisible** until a specific tech reveals
them (e.g. Animal Husbandry reveals Horses; Bronze Working reveals Iron). This
is unit-gating machinery Broken Oaths' single-combat-strength MVP does not need.

**Recommendation for 905.** Ship **bonus resources only.** They map cleanly onto
our F/P yield model and our Farm/Mine/Pasture improvement set, and they need no
new subsystem. Luxury and strategic are on the explicit **defer list** (§6).

---

## 2. Minimal bonus-resource set for Broken Oaths

### What Civ VI does (early bonus resources)

| Resource | Terrain / placement | Base yield (unimproved) | Improvement | Unlocking tech |
|----------|---------------------|-------------------------|-------------|----------------|
| **Cattle** | flat **Grassland** | **+1 Food** | Pasture | **Animal Husbandry** |
| **Sheep** | unwooded **Hills** (any base except Snow Hills) | **+1 Food** | Pasture | **Animal Husbandry** |
| **Deer** | **Tundra** tiles, or tiles with **Woods** | **+1 Production** | **Camp** | Animal Husbandry |
| **Wheat** | flat **Plains** (and desert floodplains) | **+1 Food** | Farm | Pottery |
| **Rice** | **Grassland** / Grassland Marsh | **+1 Food** | Farm | Pottery |
| **Stone** | flat **Grassland/Plains** (and some hills) | **+1 Production** | Quarry | Masonry |
| **Bananas** | **Rainforest** | **+1 Food** | Plantation | Irrigation |
| **Copper** | **Hills** | **+2 Gold** | Mine | Mining |

The resource's base yield **stacks on top of the tile's terrain yield** (Civ's
additive model, same as our `base + relief + feature` in `stone_age_yields.md`),
and the improvement then adds more on top. So a Cattle-on-Grassland tile is
`2F (grassland) + 1F (cattle) = 3F` unworked, rising to `2 + 1 + 2 (pasture) =
5F` once improved.

### Recommendation for 905 — the four-resource MVP set

Ship these four bonus resources. Every terrain and improvement below already
exists in Broken Oaths, and the two animal resources are exactly what story
902's Animal Husbandry → Pasture needs to act on.

| # | Resource | Signature | Terrain constraint (BO terms) | Unworked bonus | Improvement (+yield) | Improvement gate |
|---|----------|-----------|-------------------------------|----------------|----------------------|------------------|
| 1 | **Cattle** | animal / food | flat **grassland**, no woods/marsh | **+1 F** | **Pasture (+2 F)** | **Animal Husbandry** (story 902) |
| 2 | **Sheep** | animal / food | **hills**, no woods | **+1 F** | **Pasture (+2 F)** | **Animal Husbandry** (story 902) |
| 3 | **Wheat** | crop / food | flat **plains**, no woods/marsh | **+1 F** | **Farm (+2 F)** | (already worked; Farm is baseline) |
| 4 | **Stone** | rock / prod | **hills**, no woods | **+1 P** | **Mine (+2 P)** | Mining (faster mines, story 902) |

Why this set:
- **Cattle + Sheep are non-negotiable** — they are the animal resources that
  give Animal Husbandry → Pasture a target. Both are +1 Food and both take the
  Pasture, which keeps the "Pasture = the animal improvement" story clean.
- **Wheat** reuses the existing Farm (+2 F) with no new gate — a food-plains
  resource that makes plains starts more interesting.
- **Stone** reuses the existing Mine (+2 P) — a production-hills resource, and a
  natural companion to the Mining tech.
- Terrain coverage spans grassland / plains / hills so most starts see at least
  one resource, and each of the three signature yields (food from Cattle/Sheep/
  Wheat, production from Stone) is represented.

### Decision 3 — Deer (the production animal)

Deer is the classic third animal resource, but in Civ it is a **+1 Production**
resource improved by a **Camp**, not a Pasture — and story 902's tech tree has
**no Camp improvement**. Three options, in order of preference:

- **(A, recommended) Defer Deer.** Ship Cattle + Sheep + Wheat + Stone. Add
  Deer + Camp in a fast-follow if the animal layer needs a production flavor.
- **(B) Fold Deer into the Pasture.** Add Deer on tundra/woods as a **+1 P**
  resource that the **Pasture** improves for **+2 P** (diverging from Civ, where
  Pasture is food). Gives Animal Husbandry a production reward too, at the cost
  of a slightly less clean "Pasture = food" story.
- **(C) Add a Camp improvement.** Full Civ fidelity, but that is new
  tech-tree/UI surface beyond story 905's scope — do not do this for the MVP.

Keep the set animal-only (Cattle + Sheep, drop Wheat/Stone) only if the PM wants
the tightest possible first slice. The four-resource set is the recommended
default because Wheat/Stone cost nothing new (they reuse Farm/Mine) and make the
resource layer visibly matter beyond the single AH unlock.

---

## 3. Placement / distribution

### What Civ VI does

- **All resources are placed once, at map generation**, before the game starts;
  one resource per tile; resources never appear on Ocean (bonus/luxury land
  resources are land-only, with separate sea resources like Fish/Crabs).
- Placement is **terrain-constrained**: each resource has a valid-terrain list
  (Cattle only on flat Grassland, Sheep only on non-snow Hills, Deer on Tundra/
  Woods, etc.). The generator only drops a resource where the terrain qualifies.
- Density is **percentage-driven** (internal params like `iStandardPercentage`
  ~28, `iLuxuryPercentage` ~20, `iStrategicPercentage` ~21) and scales with map
  size — small maps end up denser, large maps sparser. Luxuries cluster: each
  named continent gets ~4 luxury types unique to it, placed in small clumps.
  Bonus resources are scattered more evenly rather than clustered.

### Recommendation for 905

Match our existing **seed-deterministic, zero-RNG** worldgen (the story-880
expansion picker and worldgen already derive everything from the seed). Placement
is a pure function of `(seed, tile)`:

1. **Iterate tiles in a fixed order** (same canonical ordering worldgen already
   uses). For each land tile, compute a deterministic hash of `(world_seed,
   tile_id)` → a stable pseudo-random value in `[0,1)`. No live RNG; the same
   seed always yields the same resource map.
2. **Terrain gate first.** A tile is only a *candidate* for a resource if its
   terrain matches that resource's constraint (Cattle → flat grassland no
   woods/marsh; Sheep/Stone → hills no woods; Wheat → flat plains no woods/
   marsh). A tile may be a candidate for more than one resource; break ties by a
   fixed resource priority (e.g. Cattle > Wheat > Sheep > Stone) so the outcome
   is deterministic.
3. **Density threshold.** Place a resource when the tile's hash value falls below
   a per-resource threshold. Target **roughly one resource per 12-15 land tiles**
   overall (Civ's early-game feel), i.e. a single-digit-percent chance per
   *eligible* tile. Tune per resource so food resources aren't overwhelmingly
   more common than production ones.
4. **Spacing (optional, nice-to-have).** To avoid clumps, reject a placement if
   another resource already sits within 1 hex (cheap deterministic check in the
   fixed iteration order). Civ scatters bonus resources fairly evenly, so light
   spacing reads as more Civ-like; skip it for the first slice if it complicates
   the generator.
5. **One resource per tile**, and resources are **visible from the start** (bonus
   resources have no reveal-tech in Civ). Whether a resource may sit on the
   eventual city-center tile is a PM call — Civ allows settling on resources;
   simplest MVP behavior is to allow it and let the city-center yield floor
   (`2F 1P`, story 880) still apply.

**Open number for the PM:** the target density (one per N land tiles) and the
per-resource split. Recommend starting at **~1 per 12 land tiles**, ~55% food
resources / ~45% production, then tune in playtest.

---

## 4. How resources interact with worked yields and improvements

### What Civ VI does

A worked resource tile contributes: **terrain yield + resource bonus +
improvement yield**, all additive. The resource bonus applies as soon as the
tile is worked (no tech needed to *see* the bonus for bonus resources); the
improvement's extra yield requires the unlocking tech and a Worker/Builder to
construct it. Bonus resources can alternatively be **harvested** for a one-time
lump (e.g. Cattle → 20 Food) that removes the resource — an optimization we
should **not** ship in the MVP (it's a micro-optimization layer).

### Recommendation for 905 (consistent with story 880/882)

- **Worked, unimproved resource tile** = terrain yield **+** resource bonus.
  Example: Cattle on grassland worked by a pop = `2F + 1F = 3F`.
- **Worked, improved resource tile** = terrain yield **+** resource bonus **+**
  improvement yield. Example: Cattle on grassland with a Pasture = `2F + 1F +
  2F = 5F`. Sheep on hills with a Pasture = `2F 1P (grassland hills) + 1F + 2F =
  5F 1P`, or on plains hills `1F 2P + 1F + 2F = 4F 2P`.
- **Stacking is additive**, matching `stone_age_yields.md`'s `base + relief +
  feature` rule — the resource is just another additive term, and the
  improvement another. Keep the existing **one improvement per tile** rule.
- The **citizen auto-assign** scorer (`2·food + 1·production`, story 880) needs
  no change: resource tiles simply score higher and get worked first, which is
  the intended pull. The **expansion tile-picker** (highest F+P) likewise favors
  resource tiles automatically — a nice emergent "cities grow toward resources"
  behavior with no special-casing.
- **Do NOT ship harvesting** (the one-time yield dump that deletes the resource)
  for the MVP — it's a min-max layer, not core to the AH → Pasture loop.

---

## 5. Per-resource yields and gates (implementation table)

Canonical numbers for spec writing. Improvement yields and gates match story 902
(Animal Husbandry → Pasture, Mining → faster mines) and story 882 (Farm/Mine).

| Resource | Terrain (BO) | Unworked bonus | Improvement | Improvement yield | Tech gate for improvement | Fully-worked example |
|----------|--------------|----------------|-------------|-------------------|---------------------------|----------------------|
| **Cattle** | flat grassland | +1 F | Pasture | +2 F | Animal Husbandry | grassland 2F + 1F + 2F = **5F** |
| **Sheep** | hills (no woods) | +1 F | Pasture | +2 F | Animal Husbandry | grassland hills 2F 1P + 1F + 2F = **5F 1P** |
| **Wheat** | flat plains | +1 F | Farm | +2 F | (Farm is baseline) | plains 1F 1P + 1F + 2F = **4F 1P** |
| **Stone** | hills (no woods) | +1 P | Mine | +2 P | Mining | grassland hills 2F 1P + 1P + 2P = **2F 4P** |
| *Deer (deferred)* | tundra / woods | +1 P | Pasture (opt. B) or Camp (opt. C) | +2 P | Animal Husbandry | tundra 1F + 1P + 2P = **1F 3P** |

Notes:
- **Pasture = +2 Food** and is gated by **Animal Husbandry** (story 902's exact
  spec). It builds only on animal resources (Cattle, Sheep) — a Pasture cannot
  be placed on a bare tile, unlike a Farm/Mine.
- **Wheat** needs no new gate: the baseline Farm (+2 F, story 882) already
  applies to flat grassland/plains. Wheat just adds its +1 F on top.
- **Stone** uses the baseline Mine (+2 P). The Mining tech's "faster mines"
  (story 902) speeds construction but the yield is unchanged.
- Keep every improvement bonus at the **+2** convention already established, so
  resources feel uniformly "one improvement = +2 of its yield."

---

## 6. Explicit defer list (with reasoning)

| Deferred | Why it waits | Prerequisite Broken Oaths lacks |
|----------|--------------|--------------------------------|
| **Luxury resources** | Their entire value is **+1 Amenity** to needy cities. Broken Oaths has **no amenities/happiness system** and no gold/culture/faith yields for their tile bonuses to feed. A luxury with no amenity is just a reflavored bonus resource. | Amenities/happiness subsystem; gold economy |
| **Strategic resources** | They exist to **gate units** (need Horses for cavalry, Iron for Swordsmen). Our units use a **single combat strength** with no resource cost, and story 902 explicitly has **no resource-gated units**. Iron/Horses would be inert. | Unit resource-cost/stockpile system; a unit roster that needs gating |
| **Resource reveal techs** | Strategic resources are invisible until a tech reveals them. Bonus resources are visible from the start, so the MVP needs no fog-of-resource mechanic. | (only relevant once strategics exist) |
| **Harvesting** (one-time yield dump that deletes the resource) | A min-max optimization layer, not part of the core AH → Pasture loop. Adds Worker-action UI and "did I just delete my resource?" footguns. | — (a scope choice, not a missing system) |
| **Sea resources** (Fish, Crabs, Pearls, Whales) | Need Fishing Boats + a coastal-tile working model; our coast/ocean tiles yield a flat 1F and we have no water improvements. | Water improvements; naval/coastal working |
| **Deer + Camp** | See §2 Decision 3 — Camp is a new improvement outside story 902's tech tree. Ship Cattle/Sheep on the Pasture first. | Camp improvement in the tech tree |

Bring luxuries in only alongside an amenities/happiness feature, and strategics
only alongside resource-gated units — each pairs with a subsystem that is itself
a separate future story, so both stay out of story 905.

---

## Sources

- Resource (Civ6), Civilization Wiki — https://civilization.fandom.com/wiki/Resource_(Civ6)
- List of resources in Civ6, Civilization Wiki — https://civilization.fandom.com/wiki/List_of_resources_in_Civ6
- Cattle (Civ6) — https://civilization.fandom.com/wiki/Cattle_(Civ6)
- Sheep (Civ6) — https://civilization.fandom.com/wiki/Sheep_(Civ6)
- Deer (Civ6) — https://civilization.fandom.com/wiki/Deer_(Civ6)
- Pasture (Civ6) — https://civilization.fandom.com/wiki/Pasture_(Civ6)
- Animal Husbandry (Civ6) — https://civilization.fandom.com/wiki/Animal_Husbandry_(Civ6)
- Civilization 6 Resources guide, gamepressure.com — https://www.gamepressure.com/sidmeierscivilization6/resources/z29342
- Resource distribution / density parameters, CivFanatics Forums — https://forums.civfanatics.com/threads/resource_distribution-table-anyone-figure-this-out.611568/
