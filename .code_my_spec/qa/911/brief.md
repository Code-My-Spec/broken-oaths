# Qa Story Brief — 911 Strategic Resources: Copper for Bronze Spearmen (re-QA round 4)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) + dev QA control surface
(`/dev/qa/worlds/:id/step` to accrue science).

## Auth

- `qa@broken-oaths.test` / `qa-password-123!` — user 1, has existing civilizations in World 6
  ("QA Copper Hunt 911", player 17 / city 16) and World 5 ("QA Density Dense 905", player 15 /
  city 15), both already past Bronze Working from prior sessions.
- `qa-901-a@broken-oaths.test` / `qa-password-123!` — player 11 in World 3 ("QA World
  (Multiplayer)"), started this session with ZERO completed techs — used for a true live
  before/after Bronze Working reveal check.
- Password-form login only (`#login_form_password`); switching accounts requires an explicit
  "Log out" click first — the password-form email input goes `readonly` and silently keeps the
  previous session's address if you just re-fill it without logging out first (filed as a QA
  script/tooling nit below, not an app bug — no create_issue needed, it's a one-line note for
  future sessions).

## Seeds

No new seeds needed — reused existing QA worlds/players. Context:

- World 6 (dense, seed 644595483): city 16 already has Bronze Working + a Copper tile (14851)
  inside its 12-tile territory, confirmed via `SELECT territory FROM game_cities WHERE id=16`.
- World 3 (standard, seed 901901): player 11 (city 8, tile 505 center) and player 12 (city 9)
  both gained a reachable Copper tile under the fixed placement (505 itself for player 11 — the
  guarantee placed Copper directly on the city's own founding tile; 106 for player 12).
- World 5 (dense, seed 850471216): city 15 has NO Copper in its 12-tile territory even though a
  Copper tile (19708) exists nearby and revealed — good natural negative-path fixture.

To fast-track research: open Tech panel (`toggle_tech_panel` / click "Tech"), select `mining`,
`POST /dev/qa/worlds/:id/step` in a loop until `[data-test='tech-completed-mining']`/DB
`completed_techs` shows it, then select `bronze_working`, confirm the "advance to Bronze Age"
modal, and step again until it lands.

## What To Test

- **7704 (city with Copper can queue)**: select a city whose territory contains a revealed
  Copper tile (World 6 city 16), open its Build panel, confirm "Bronze Spearman … Requires
  Copper ✓" (satisfied, green), click it, confirm it enters the queue client-side AND persists
  server-side (`SELECT * FROM game_production_items WHERE city_id=16`).
- **7705 (city without Copper stays gated)**: select a city whose territory does NOT contain a
  Copper tile even though Copper is revealed and visible nearby (World 5 city 15), confirm
  "Bronze Spearman" renders disabled/greyed with "Requires Copper" in orange, no checkmark, no
  queue button interaction possible.
- **7706 (unworked Copper still counts)**: on the World 6 city, check the "Worked Tiles" list —
  confirm the Copper tile (14851) shows "Work" (i.e. NOT currently worked) while "Requires
  Copper ✓" is still satisfied and the build still succeeds.
- **7707 (reveal gated on Bronze Working)**: log in as a player with ZERO completed techs
  (qa-901-a, World 3), dump `h.resources` from the board hook BEFORE any research — confirm no
  `copper` entries anywhere in the fog window. Research Mining then Bronze Working for real via
  the Tech panel + turn-stepping. Dump `h.resources` again — confirm new `copper` entries appear
  (same tiles now revealed), and click one to confirm the tile-info panel now reads "… Copper".
- **7708 (legible in the production menu)**: screenshot both the positive ("Requires Copper ✓",
  teal/green) and negative ("Requires Copper", orange, no checkmark) renderings side by side.
- Also spot-check the Copper sprite is now visually distinct from Stone (`priv/static/images/
  game/decor/copper.png` vs `stone.png` — different MD5, different hue: warm copper-orange vs
  neutral grey) — this was the other half of the two paired issues from the prior round.

## Result Path

Findings filed via `create_issue` as found (none this round — full pass). Verdict via
`submit_qa_result` (task_id from `start_task`). Screenshots at
`.code_my_spec/qa/911/screenshots/` (numbered 00-26 this round).

## Setup Notes

Both blocking issues from the prior round are now resolved:

- `a250ddab-0517-42f3-b032-812847e4a314` (Copper sprite byte-identical to Stone) — resolved via
  ImageMagick recolor; confirmed this round via direct MD5 diff + in-game pixel sampling
  (Copper renders as a warm orange/peach dome, Cattle/Stone render neutral grey-tan).
- `78e938bb-d984-46a2-b445-508d8eb27e3b` (Copper unreachable from small starting islands) —
  resolved via `Resources.guarantee_copper_near_spawns/2` (independent `@copper_rate` + a
  deterministic per-region fallback placement within 6 hex-steps of every spawn anchor).
  Confirmed live this round on THREE independent worlds/players (World 6 dense, World 3
  standard ×2 players) — every one of them now has a genuinely reachable, in-territory Copper
  tile post-Bronze-Working. The positive access path (7704, 7706, 7707) is fully verified live
  for the first time this story has been QA'd.
