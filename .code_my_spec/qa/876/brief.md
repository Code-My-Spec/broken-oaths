# Qa Story Brief

Story 876 — Fog of War and Exploration.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Primary account: `qa@broken-oaths.test` / `qa-password-123!` via
  `#login_form_password`. Units have moved well away from spawn this
  session (Lord at tile 14724, Settler at tile 14742 as of writing) —
  good for testing "terrain remembered after moving on."
- Second account: `qa877-throwaway2@example.test`, magic-link only
  (`#login_form_magic` → read the link from
  `http://localhost:4050/dev/mailbox`, `#login_form_magic_email`
  submit button). Its Lord (tile 23561) and Settler (tile 22712) have
  never moved this session — good stand-in for "fresh spawn" without
  needing a brand-new throwaway account.
- Driven with `mcp__plugin_codemyspec_vibium__*` browser MCP tools.

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent, already run. QA World id 6, frequency 54 (29,162 total
tiles) — both accounts are pre-existing members.

## What To Test

Fog truth surfaces per the board doctrine (no tile DOM on `/play/:id`):
read `hook.tiles` (known = visible ∪ explored, fog-filtered), `hook.visibleSet`
(currently visible), and `hook.units` (fog-filtered unit list) off the
client hook, reached via `window.liveSocket.owner(el, view => view.viewHooks[...])`
— see story 875's brief for the full pattern. Vision radii
(`BrokenOaths.Game.Visibility.vision_radius/1`: lord=3, settler=2) and
BFS vision-ball math were cross-checked with a **safe, pure** `mix run`
script (`Visibility.visible_tiles/2` + `Regions.adjacent_tiles/2` —
no `Game.*`/`WorldServer` calls; see story 875's brief for why that
matters).

- **A fresh spawn sees a cloud-wrapped planet with one clear bubble**
  (criterion 7431) — log in as `qa877-throwaway2@example.test`
  (unmoved since spawn), go to `/play/6`. Expect a small bright/lit
  cluster of tiles around the two unit markers, a slightly dimmer
  fringe ring, and nothing else rendered — the rest of the canvas is
  empty space, not a "cloud" texture (see Setup Notes: this is a
  softer finding, filed as part of issue `025e1905`). Screenshot:
  `.code_my_spec/qa/876/screenshots/7431_fresh_spawn_bubble.png`.
  Ground truth: `Visibility.visible_tiles/2` for this account's
  lord+settler positions computes a 50-tile combined vision ball
  (37 for the lord's radius-3 ball, 19 for the settler's radius-2
  ball, 6 tiles overlap) — the live client reported
  `hook.visibleSet.size === 50` and `hook.tiles.length === 58`
  (8 more explored-but-not-currently-visible tiles), an exact match.

- **The Lord out-scouts the Settler** (criterion 7432) — confirmed by
  the exact match above: `Visibility.vision_radius(:lord) == 3` vs
  `vision_radius(:settler) == 2` (source:
  `lib/broken_oaths/game/visibility.ex:33-34`), and the live
  `visibleSet` size matched the precomputed combined-ball size to the
  tile. No separate live action needed beyond the 7431 check.

- **Terrain stays on the map after the scout moves on** (criterion
  7433) — using the primary account (units long moved from their
  original 14741/14744 spawn), a safe BFS script identified original
  spawn-bubble tiles now out of both units' *current* vision range
  (e.g. tile 20589, lord-distance 7, settler-distance 4). Checked six
  such tiles against the live `hook.tiles`/`hook.visibleSet`: all six
  are `inTiles: true` (terrain still known/rendered) and
  `inVisible: false` (no longer currently visible, rendered at 0.45
  alpha per `play.ex:516`) — confirms explored history persists after
  a unit leaves.

- **A stranger in remembered territory is invisible** (criterion
  7434) — not independently browser-tested: the two seeded accounts'
  regions are far apart (disjoint tile sets, see below), so walking
  one account's unit through the other's remembered-but-not-visible
  territory isn't stageable in reasonable time. Verified via source
  read: `Visibility.filter/2`
  (`lib/broken_oaths/game/visibility.ex:63-66`) only includes another
  player's unit in the filtered result when
  `MapSet.member?(visible, unit.tile_id)` — i.e. the tile is in the
  *current* visible set, not merely `explored`. A stranger standing on
  remembered-but-not-currently-visible ground is excluded regardless
  of your exploration history there. Corroborated by
  `test/spex/876_fog_of_war_and_exploration/criterion_7434_a_stranger_in_remembered_territory_is_invisible_spex.exs`.

- **Two players see two different worlds** (criterion 7435) — compared
  the full known-tile id lists for both accounts: the primary
  account's 65 known tiles are all in the 14670–14783 / 20587–20589
  id range; the second account's 58 known tiles are all in the
  22631–23714 id range. Zero overlap between the two sets — the two
  players are looking at entirely disjoint regions of the same globe.

- **Hidden tiles never travel over the wire** (criterion 7436) —
  quantitative: both accounts' known-tile counts (58 and 65) are
  ~0.2% of the world's 29,162 total tiles (`Globe.tile_count(54)`),
  confirming aggressive server-side filtering rather than a
  client-side hide. Confirmed by source read:
  `Visibility.filter/2` constructs its return value as exactly
  `%{visible: ..., explored: ..., units: ...}` from the `visible`
  and `explored` sets only — there is no code path that includes an
  unknown tile id, so nothing to redact client-side; it's simply
  never in the payload.

- **Fog cloud and weather cloud read as different things** (criterion
  7438) — **FAILED browser verification**, filed as issue
  `025e1905-7467-4d6d-8729-28330ac9a9c0`. Neither a fog-cloud nor a
  weather-cloud visual exists on `/play/:id`: `.fog-layer` and
  `.weather-layer` (`play.ex:328-330`) have zero CSS anywhere in the
  codebase, and the `.Board` hook never registers a handler for the
  `globe3d:airspace` weather event it pushes (`play.ex:244`) — only
  `game:window/visibility/units/selected/path` are handled
  (`play.ex:387-394`). The *same* `globe3d:airspace` event is fully
  handled with working animation on `/worlds/:id`
  (`world_live/show.ex:1161`, `1186`), so the mechanism exists and
  works — it just isn't wired into the actual gameplay board.

## Result Path

Findings are filed via `create_issue` as discovered; the run concludes
with one `submit_qa_result` call against task id
`a4faaf41-466b-4e5c-b470-0e6e23693d2d`. Screenshots go in
`.code_my_spec/qa/876/screenshots/`.

## Setup Notes

- Same canvas-only board, no tile DOM, same `window.liveSocket` /
  hook-instance access pattern as story 875's brief.
- The 7431 "cloud-wrapped planet" wording in the story is a visual
  metaphor that isn't literally implemented: unexplored space is
  simply absent from `hook.tiles` and never drawn (plain
  `.space-bg` starfield background shows through), not rendered as a
  fog/cloud-textured sphere. The *behavioral* requirement (mostly
  hidden, one small clear bubble) is satisfied; the *visual* metaphor
  is not, and is the same root cause as the 7438 failure (dead
  `.fog-layer`/`.weather-layer` divs) — rolled into issue `025e1905`
  rather than filed separately.
