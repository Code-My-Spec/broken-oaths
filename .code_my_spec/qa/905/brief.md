# Qa Story Brief — 905 Tile Resources

## Tool

web (Vibium browser against `GameLive.Play` at `/play/:id`), supplemented by
`curl` against the dev-only QA control surface (`/dev/qa/worlds/1/units`) to
spawn a test worker, and `curl` + `magick` against `/worlds/:id/texture.png`
to get a full-globe terrain census (complete pixel coverage of the terrain
map, not a sample) for the relief/hills investigation.

## Auth

- Player 1: `qa@broken-oaths.test` / `qa-password-123!` via `#login_form_password`
  at `http://localhost:4050/users/log-in`. Has completed `animal_husbandry`,
  `mining`, `pottery`, `bronze_working` (confirmed via
  `psql broken_oaths_dev -c "select * from game_player_research where world_id=1"`).
- Player 2: `qa891a@test.local` has no password — magic link only. Submit
  `#login_form_magic`, then read the link from `http://localhost:4050/dev/mailbox`
  and follow it, then click "Log me in only this time". Has completed only
  `bronze_working` — no `animal_husbandry`, so Pasture must be gated off.
- Logout: `vibium click "a[href='/users/log-out']"` (phoenix_html
  `data-method="delete"` link; plain navigation to the href 404s/GETs
  instead of deleting the session).

## Seeds

No new seeds needed. World 1 ("QA World", seed 424242, freq 54, density
`standard`) already has both QA players with cities, units, and research
history. For the density-slider criterion, two new throwaway worlds were
created live through `/worlds/new` (`data-test="new-world-form"`,
`data-test="resource-density-slider"` is a `<select>` of
sparse/standard/dense, not a literal range slider): "QA Density Sparse 905"
(density=sparse) and "QA Density Dense 905" (density=dense), both frequency
54 (the creation form doesn't expose frequency). Left in place for
re-inspection (ids 4 and 5).

## What To Test

Board surface for resources is `GameLive.Play` (`/play/:id`) — NOT
`WorldLive.Show` (`/worlds/:id`, the public globe viewer, which has no
resource rendering at all). Canvas-only board; use
`.code_my_spec/qa/scripts/board_click.sh` for real clicks, and the
hook's own `pushEvent('select_tile', {tile_id})` / `h.resources` for
bulk/no-fog-restricted inspection (same server-side `handle_event` a real
click fires, just not restricted to the client's fog-filtered tile set —
used only for *locating* things to then confirm through the normal path).

- **Same seed, same resources (7644).** Dump `h.resources` (`{tile_id,
  kind}` pairs) on `/play/1`, full page reload, dump again. Expect an
  identical set.
- **Resources land on their eligible terrain (7645).** Click a resource
  tile (`board_click.sh <id> left`), read `[data-test=tile-terrain]` and
  `[data-test=tile-resource]`. Expect Cattle→Grassland (flat), Wheat→Plains
  (flat), Sheep/Stone→Hills.
- **An unworked Cattle tile already yields extra (7646).** Same tile click;
  read `[data-test=tile-yields]`. Expect base terrain food +1 (Cattle
  observed live: Grassland 2 food → 3 food unworked, no improvement).
- **A Pasture on Cattle stacks to five food (7647).** Cross-reference
  `game_improvements` for a `:pasture`/`:complete` row on a tile
  `h.resources` reports as Cattle/Sheep; confirm the improvement bonus
  (+2 food, `Yields.improvement_bonus/1`) stacks onto the already-observed
  unworked yield (3) for 5.
- **Pasture needs Animal Husbandry first (7648).** Select a worker (own
  or dev-QA-spawned via `POST /dev/qa/worlds/1/units -d player_id=<id>
  -d type=worker -d tile_id=<cattle/sheep tile>`) standing on a Cattle/Sheep
  tile; read `button[data-test^=build-]` in the unit panel. Player WITH
  Animal Husbandry → `build-pasture` present. Player WITHOUT → absent
  (only `build-farm`/`build-road`).
- **Resources are visible from the first look (7649).** No reveal-tech
  gate exists in code (`Resources.at/2` unconditional); confirm the board
  already shows resource billboards/tile labels on first load, no
  additional research/action required.
- **A city works its resource tile first (7650).** Cross-reference a
  city's `worked_tiles` (DB or `select_city` push) against `h.resources`;
  expect at least one worked tile to carry a resource.
- **A resource-rich world has more than a sparse one (7651).** Join both
  throwaway worlds; sweep `select_tile` across a wide tile-id sample in
  each, restrict to terrain eligible for a resource (Grassland flat /
  Plains flat / Hills), and compare the resource hit-rate between the two
  worlds. Expect dense rate meaningfully higher than sparse.

## Result Path

No `result.md` — findings are filed via `create_issue` as discovered, and
the session ends with a single `submit_qa_result` call carrying the
structured scenario list and every filed issue id. Screenshots and raw
`curl`/texture evidence live under
`.code_my_spec/qa/905/screenshots/` and `.code_my_spec/qa/905/responses/`.

## Setup Notes

**Relief/hills is rare in this generator.** `Generator.classify/4`
(`lib/broken_oaths/worlds/generator.ex`) assigns `:hills` for elevation in
`[0.74, 0.88)`, but a full-globe texture pixel census (`/worlds/:id/texture.png`
piped through `magick ... histogram:info:` — this samples every rendered
pixel, which is generated from the *same* `Generator.generate_terrain_map/2`
the live game uses, so it's an exhaustive read of that world's actual
terrain, not a guess) found **zero** hills-shaded pixels in World 1 (seed
424242) and the sparse throwaway (seed 402054609), and only ~420 out of
2,097,152 pixels (~0.02%) in the dense throwaway (seed 850471216) — the
two matching colors `#1DA54F` (Grassland·Hills) and `#126C33`
(Grassland·Hills·Woods) were both present there. Live `select_tile` sweeps
of several thousand tile ids across all three worlds never landed on a
Hills tile. Sheep/Stone placement logic is correct by code inspection
(`Resources.candidates/1`'s hills clause), and the terrain classifier
*can* produce hills (confirmed in the dense world's texture), but hills is
so rare a real player is very unlikely to ever see a Sheep or Stone
resource. Filed as an issue (see below) — likely a pre-existing
terrain-generation tuning gap (stories 878-881), not a defect in this
story's own `resources.ex`.
