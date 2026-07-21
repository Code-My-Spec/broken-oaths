# Convention: buildings

Companion to `unit_and_unlock_convention.md`. Buildings had the same latent trap
units did: the Granary shipped as a bare `has_granary` boolean on the city with
its Pottery gate and its effect wired in separate places, and no home for
properties a building needs (production cost, effect, tech gate, and — the thing
that was missing entirely — gold maintenance). Adding a second building would
have meant a second boolean and more scattered wiring.

## The convention

**1. A building is its own story, and it owns ALL of its properties in one
catalog.** `BrokenOaths.Cities.Buildings` is the single catalog: for each
building, its production cost, its effect, its tech gate, and its **gold
maintenance per turn**. A building is never a scattered set of flags. This is
the same "the thing owns its own definition" rule the unit convention uses.

**2. Guardrail — a building may not ship without declaring its maintenance.**
Every catalog entry states an upkeep (0 is allowed, but it must be explicit).
Almost every building in Civ 6 costs gold upkeep; a free building is a
deliberate, declared choice, not an omission. This mirrors the Research "no dead
unlocks" guardrail: the economy sink can't silently go missing.

**3. Maintenance feeds one settlement path.** Building upkeep and unit upkeep
(`BrokenOaths.Units.Maintenance`) net against city gold income at the turn
boundary through the same `Feudal.Bank` sweep, with the same disband-when-broke
consequence. There is one economy, not two.

## Storage vs catalog

For now a city still records which buildings it has via its own fields
(`has_granary`); the **catalog** owns the building's meaning
(cost/effect/tech/maintenance), and `Cities.Buildings` reads the city's fields
to answer "what does this city pay in upkeep." A future story can migrate the
per-building booleans to a `buildings` list without changing the catalog
contract.

## Applies to

Every future building (Library, Barracks, Temple, Walls, wonders, …). The
Granary (story 923) is the exemplar, retrofit into the catalog with upkeep 1.
