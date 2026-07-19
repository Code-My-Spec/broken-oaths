# Qa Result — 911 Strategic Resources: Copper for Bronze Spearmen

## Status: partial

## Summary

The tech-gating and negative-access-path UI (the higher-risk half of this story, since it
involves a disabled-button-with-reason pattern that's easy to get subtly wrong) is fully verified
live and correct: before Bronze Working, the Bronze Spearman option doesn't exist in the Build
catalog at all; after, it appears but disabled with a clearly legible "Requires Copper" reason.
The positive-access path (a city that DOES have Copper) could not be verified live — after
researching Bronze Working for real (Mining then Bronze Working, ~26 turns of accrued science)
and searching every Hills tile in both players' combined fog windows (18 distinct tiles, 2 in
each existing city's own territory), no Copper deposit was found anywhere reachable in World 3.
This is a world-generation/exploration coverage gap specific to this seed, not a code defect —
noted rather than worked around (e.g. no new world was seeded specifically to force a Copper
placement, per this session's instructions to avoid inventing workarounds for capacity/seed gaps).

## Scenarios

- **7704 A city with Copper can queue a Bronze Spearman** — NOT VERIFIED LIVE. No Copper tile
  found within either player's explored territory or either city's own territory in World 3.
  Gap, not a bug — see Setup Notes.
- **7705 A city without Copper cannot train the Spearman** — PASS, fully live. City 9's Build
  catalog (post-Bronze-Working) shows "Bronze Spearman 60" visibly greyed/disabled with
  `data-copper-met="false"` and the requirement text rendered directly beneath it.
- **7706 Copper in the borders counts even when unworked** — NOT VERIFIED LIVE, same reason as
  7704 (the ACCESS check itself, `copper_access?/2`, is unworked-tile-inclusive by construction —
  `Enum.any?(city.territory, ...)` scans the whole territory array regardless of `worked_tiles` —
  confirmed by code review, not a live click).
- **7707 Copper appears once Bronze Working lands** — PARTIAL. The closely-related PRODUCTION-MENU
  gating was directly observed: the Bronze Spearman row was completely ABSENT from the Build
  catalog before Bronze Working (player 11's city 8, pre-research) and PRESENT (disabled, with
  reason) after (player 12's city 9, post-research) — same tech-gate, confirmed live. The specific
  RESOURCE-ICON reveal on the map itself (`visible_resource/3`) was not observed toggling, since
  no Copper tile was found in-session to watch reveal.
- **7708 The requirement is legible in the production menu** — PASS, fully live. "Requires
  Copper" renders in orange directly under the disabled Bronze Spearman build option, unambiguous.

## Evidence

Screenshots at `.code_my_spec/qa/911/screenshots/`:
- `re2_01_city9_requires_copper_disabled.png` — city 9 (post-Bronze-Working), Build catalog
  showing "Bronze Spearman 60" disabled with "Requires Copper" legible beneath it
- `.code_my_spec/qa/912/screenshots/re2_01_city8_panel.png` — city 8 (pre-Bronze-Working, same
  session), Build catalog showing NO Bronze Spearman row at all — the before/after pair proving
  the tech-gate

psql/eval verification: `game_player_research.completed_techs` gaining `mining` then
`bronze_working` for real via the Tech panel's confirm modal; `h.resources` (the client's own
fog-filtered resource list) and `h.tiles` decor scan confirming zero Copper among 18 distinct
known Hills tiles across both players.

## Issues Filed

None — the gap is an environment/world-seed limitation, not an application defect. Recommend a
future QA session either re-seed a dedicated small world with a guaranteed Copper placement near
spawn, or extend exploration significantly before concluding Copper is absent from this seed
entirely.
