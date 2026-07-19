# Qa Result — 911 Strategic Resources: Copper for Bronze Spearmen (re-QA, round 3)

## Status: partial

## Summary

Made a genuine, extensive effort to verify the POSITIVE access path (a city WITH Copper
can queue a Bronze Spearman) across THREE separate worlds this session, on top of the
prior session's already-thorough negative-path verification:

1. **World 3** (standard density, existing established map) — re-confirmed several of
   the 18 previously-found Hills tiles directly, now with correct icon knowledge (see
   below) — still zero Copper.
2. **World 5** "QA Density Dense 905" (dense density, frequency 54, existing world) —
   founded a fresh city, researched Mining + Bronze Working for real via the Tech panel
   (fast-forwarded via the dev QA `/step` endpoint), grew the city to size 6 / 12
   territory tiles. Only 5 Hills tiles existed on the entire starting island (2 Sheep,
   3 bare) — zero Copper.
3. **World 6** "QA Copper Hunt 911" (freshly created via `/worlds/new`, dense density,
   fresh random seed) — same full research + growth cycle. The whole starting island
   (visually richer, ~14 resource tiles) had zero Hills tiles at all bearing Sheep OR
   Copper/Stone — every resource on it was Cattle (Grassland) or Wheat (Plains).

Both dense-world cities' Build panels showed "Bronze Spearman ⬤ 60 / Requires Copper"
(disabled) even after territory growth — server-authoritative confirmation
(`copper_access?/2`) that neither city's territory ever contained a Copper tile.

**A genuine bug surfaced along the way**: `priv/static/images/game/decor/copper.png` and
`.../stone.png` are byte-for-byte identical files (same MD5). This doesn't break the
gating logic (the tile-info click panel still correctly labels "Copper" vs "Stone" from
the underlying data), but it means Copper is visually indistinguishable from Stone on the
map — defeating the "distinct strategic-resource icon" convention the story is built on,
and it's part of why the early parts of this hunt mis-identified icons. Filed as an issue.

Given three separate worlds (two of them fresh DENSE seeds with real Bronze Working
research and real territory growth) all failed to surface a single reachable Copper
tile, this is filed as a genuine placement-rarity/reachability finding, per this
session's own instructions ("If, after a genuine effort with a dense world + Bronze
Working, no Copper is reachable, that's a real placement-rarity finding — file
create_issue and mark 911 partial").

## Scenarios

- **7704 A city with Copper can queue a Bronze Spearman** — NOT VERIFIED LIVE. No Copper
  tile reachable within any founded city's territory across 3 worlds this session (12
  dense-world territory tiles × 2 attempts + the pre-existing standard-world map).
- **7705 A city without Copper cannot train the Spearman** — PASS, fully live (re-confirmed
  this session on World 6's city: "Bronze Spearman" visibly disabled with "Requires
  Copper" directly beneath it, post-Bronze-Working).
- **7706 Copper in the borders counts even when unworked** — NOT VERIFIED LIVE (same reason
  as 7704). Code-level: `copper_access?/2` scans `city.territory` (the full owned-tile
  array) rather than `worked_tiles`, so this is unworked-tile-inclusive by construction —
  confirmed by code review, not a live click, same as the prior session's assessment.
- **7707 Copper appears once Bronze Working lands** — PARTIAL. Watched the SAME hills
  tiles before/after Bronze Working in World 5 (screenshots 03/12/15) — no NEW resource
  icon appeared post-research on any of them, consistent with "these hills tiles are
  genuinely bare, not hidden Copper" rather than a reveal-mechanism failure (the
  mechanism itself — `visible_resource/3`'s `Research.copper_revealed?/1` gate — was
  exercised correctly: the client's `game:resources` push is Bronze-Working-gated for
  the `:copper` kind specifically, confirmed by code read). The specific "a real Copper
  tile flips from hidden to visible" moment was never observed because no Copper tile
  was ever found in-session to watch.
- **7708 The requirement is legible in the production menu** — PASS, fully live
  (re-confirmed this session, World 6 city Build panel: "Requires Copper" in orange
  directly under the disabled Bronze Spearman option).

## Evidence

Screenshots at `.code_my_spec/qa/911/screenshots/`:
- `29_world6_build_panel.png` — World 6 city post-Bronze-Working, "Bronze Spearman"
  disabled with "Requires Copper", territory grown to 12 tiles
- `27_world6_city_panel_post_bronze.png` — same for World 5's city
- `crop4_big.png`-equivalent full-island scans (`31_world6_full_island_medium_zoom.png`,
  `32_world6_high_zoom_full.png`) — the whole starting island, methodically scanned tile
  by tile for a Copper icon
- `34_world3_player12_initial.png` / `35_world3_zoomed_out.png` — World 3's known map,
  re-scanned with corrected icon knowledge (Sheep = white sheep silhouette, Hills decor =
  green double-mound, Copper/Stone = grey dome — confirmed via direct `priv/static`
  sprite comparison and `md5`)

psql verification: `game_cities.territory` arrays for both dense-world cities (12 tiles
each, confirmed grown); `game_player_research.completed_techs` gaining `mining` then
`bronze_working` for real via the Tech panel's confirm modal on both dense worlds.

## Issues Filed

- `a250ddab-0517-42f3-b032-812847e4a314` — Copper resource sprite is a byte-identical
  duplicate of the Stone sprite (medium, scope: app)
- `78e938bb-d984-46a2-b445-508d8eb27e3b` — Copper deposits appear unreachable from small
  starting islands even at DENSE resource density, across 3 independently-tested worlds
  (medium, scope: app)
