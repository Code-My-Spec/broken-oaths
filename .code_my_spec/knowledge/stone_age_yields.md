# Stone Age Yields, Growth, and Expansion — canonical numbers

Source: Civ VI research session 2026-07-14 (civ-research agent; grounded
in civilization.fandom.com Terrain/Food/Borders pages, Civilopedia, and
CivFanatics formula threads). PM approved the approach; story 880
carries the governing rules. This file is the full reference table for
spec writing and implementation (Game.Yields / Game.Production).

## Yield composition

`yield = base + relief + feature` — modifiers STACK (Civ VI model).
Mountains and ice are unworkable (no yield, never claimable by the
expansion picker). All yields are food (F) / production (P); the game
has no gold/culture economy yet, so Civ's coast gold is dropped.

| base      | flat   | +hills     | +woods       | +rainforest | +marsh |
|-----------|--------|------------|--------------|-------------|--------|
| grassland | 2F     | 2F 1P      | 2F 1P (2F 2P on hills) | 3F | 3F     |
| plains    | 1F 1P  | 1F 2P      | 1F 2P (1F 3P on hills) | 2F 1P | —   |
| desert    | 0      | 0F 1P      | —            | —           | —      |
| tundra    | 1F     | 1F 1P      | 1F 1P (1F 2P on hills) | — | —      |
| snow      | 0      | 0F 1P      | —            | —           | —      |
| coast     | 1F     | —          | —            | —           | —      |
| ocean     | 1F     | —          | —            | —           | —      |

Modifier summary: hills +1P; woods +1P; rainforest +1F; marsh +1F.

**City center tile**: always worked free, guaranteed minimum **2F 1P**
(Civ's exact floor), upgraded if the terrain beats it. Keeps desert /
snow starts alive.

Improvements (story 882): farm +2F (flat featureless grassland/plains,
3 turns), mine +2P (hills, 5 turns). One improvement per tile.

## Growth

- **Gross accumulation, no pop food consumption** — Civ's 2F/pop eat
  rate would stall 0-3-scale yields; the threshold curve provides the
  slowdown instead.
- Thresholds: size 2 = **20**, size 3 = **30**, size 4 = **40** (clean
  +10 mental model; Civ's curve is near-linear here anyway).
- **Overflow carries** into the next basket (Civ behavior). Max one
  growth per turn. At the size-4 Stone Age cap, food still accrues but
  growth stops quietly.

## Expansion tile-pick (deterministic, on each growth)

From all unclaimed tiles adjacent to current territory, excluding
mountains/ice: pick by highest **total yield (F+P)**; ties broken by
(a) higher food, (b) smaller ring distance from the center, (c) fixed
compass order N, NE, SE, S, SW, NW. Zero RNG — same map always claims
the same tiles.

## Citizen auto-assign (deterministic)

Each pop works one owned, unworked, workable tile, assigned greedily
by score **2·food + 1·production**, highest first, same compass
tiebreak. Food doubled because growth is the Stone Age win condition.
Manual override in the city panel replaces the auto pick for that pop.

## Explicitly NOT copied from Civ VI

Pop food consumption; housing/amenities; culture-cost border math and
gold tile purchase; fractional thresholds (24/34/44); gold/culture/
faith/science yields; districts/specialists/appeal.
