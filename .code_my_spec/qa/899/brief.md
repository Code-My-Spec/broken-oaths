# Qa Story Brief — Story 899: Discovering Other Players

## Tool

web (Vibium CLI driving the shared Chrome instance) + psql for ground-truth state + curl for
the compiled JS bundle. No `mix`/`iex` at any point (dev server must not be restarted).

## Auth

Two existing, already-confirmed World 2 players from prior story-891 QA (reused, no
re-registration needed):

- `qa891pvpC@test.local` — player_id 4 in world 2, has founded a city (tile 42), has a lord +
  2 warriors (lord hp 113/150 from earlier barbarian combat).
- `qa891pvpD@test.local` — player_id 3 in world 2, **zero units** (lord + settler both died to
  barbarians in a prior retreat maneuver) — still useful for verifying the Known Players panel
  persists even with no living units.

World 1 alive/undiscovered players used for the toast substitute: `qa-892-a@broken-oaths.test`
(player_id 5, has a founded city at tile 4527).

Authenticate via the magic-link flow (all these accounts have no known password):

1. `vibium go "http://localhost:4050/users/log-in"`
2. `vibium fill "#login_form_magic_email" "<email>"`
3. `vibium click "#login_form_magic button"`
4. `vibium go "http://localhost:4050/dev/mailbox"`, open the newest message addressed to that
   email (mailbox lists ALL accounts' mail — check the "Hi <email>," line to confirm you have
   the right one before using the link), extract the
   `http://localhost:4050/users/log-in/<token>` link.
5. `vibium go` that link, then `vibium click "button[name='user[remember_me]']"` to complete
   login.

For "barbarians never trigger discovery": `qa@broken-oaths.test` / `qa-password-123!` via
`#login_form_password`, on World 1 (~70 roaming barbarians, now 8 real players spread across
the map after this session's 2 throwaway registrations).

To swap identities in the SAME browser tab (session cookie shared across tabs): visit `/`, click
`a[href='/users/log-out']`, then log in as the other user. Prefer sequential single-tab identity
switching over `vibium page new` — a second tab's LiveView socket unreliably reconnects after
logout+relogin (noted in the prior session).

## Seeds

No new seeds needed. `priv/repo/qa_seeds.exs` (already applied) provides World 1 and World 2.
Confirm ground truth via:

    psql broken_oaths_dev -c "select * from game_known_players where world_id in (1,2);"
    psql broken_oaths_dev -c "select id,player_id,type,tile_id,hp from game_units where world_id=2;"

## What To Test

- **A scout sighting a stranger triggers discovery** (7597): the mechanism was proven live in
  the original session (turn-boundary march → two `game_known_players` rows → live panel
  update with no reload). Re-verify by loading `/play/2` as C and confirming
  `[data-test='known-player-4']` still renders with D's email.
- **Sighting a barbarian is not discovering a player** (7598): log in as `qa@broken-oaths.test`
  on World 1, confirm `[data-test='known-players-empty']` still present; cross-check
  `select count(*) from game_known_players where world_id=1;` = 0.
- **Discovery notifies both sides** (7599): record half — confirm both directional
  `game_known_players` rows still present at the original `inserted_at`. Flash half — see the
  toast-pipeline verification described in Setup Notes; verified via the shared `showToast()`
  pipeline (`game:lineage` substitute) plus source + compiled-bundle confirmation that
  `game:discovery` is wired identically.
- **A known player stays known after leaving sight** (7600): confirm both C's and D's live
  Known Players panels still show each other despite D having zero units.
- **Discovery opens the chat channel** (7601): assert `[data-test='known-player-<id>']
  [data-test='chat-link']` renders as a real `phx-click='open_chat'` button on both sides.
- **Discovered does not mean omniscient** (7602): could not cleanly restage live (World 2 is a
  spent fixture; World 1 pairs are too far apart to stage quickly — see Setup Notes). Rests on
  the passing spex (`criterion_7602_*_spex.exs`) plus source review of
  `BrokenOaths.Game.Visibility.filter/2` (per-unit, currently-visible-tile gate, not a blanket
  reveal) — carried forward as `partial`, per explicit scope agreement for this retest.
- **No attacking a discovered player** (7603): D has no units left this session, so the exact
  live attack-rejection scenario could not be restaged. Carried forward from the prior session's
  solid live proof (direct `attack` push rejected with `[data-test='combat-error']`, HP
  unchanged in `game_units`) — the fix in this session touched only client-side toast
  `handleEvent` wiring, not server-side combat/attack authorization, so this is not expected to
  have regressed.
- **Discovery is both flashed and logged** (7617): logged half — reload `/play/2` fresh, confirm
  the panel survives remount. Flashed half — see the toast-pipeline verification in Setup Notes
  (`game:lineage` substitute).
- **The Known Players panel lists discovered civilizations** (7618): confirm
  `[data-test='known-players-empty']` is gone and `[data-test='known-player-<id>']` renders on
  both sides.

## Result Path

No `result.md` file — findings are filed via `create_issue` as discovered, and the session
concludes with one `submit_qa_result` call. Screenshots (evidence) are saved to
`.code_my_spec/qa/899/screenshots/`.

## Setup Notes

- **Retest context (2026-07-17, second pass)**: prior attempt `5998dbca` FAILED on one bug —
  `push_event(socket, "game:discovery", ...)` was sent server-side but had no client-side
  `handleEvent` listener, so the toast never rendered (issue `a22179a8`). That issue is now
  **resolved**: `GameLive.Play`'s colocated Board hook
  (`lib/broken_oaths_web/live/game_live/play.ex`, around line 1198-1219) adds a shared
  `showToast(message)` helper (auto-dismissing after 6s, `data-test="game-toast"`, appended to
  a `#game-toasts` container) and wires `handleEvent` for all three transient player-scoped
  pushes: `game:discovery` (story 899), `game:alert` (story 895), `game:lineage` (story 896).

- **World 2's C/D pair is a spent fixture** — they already mutually discovered each other in a
  prior session (`game_known_players` rows from 2026-07-17 23:28:16) and D has since lost all
  units (permanently lordless/cityless). World 2 has exactly 2 spawnable regions, both
  permanently claimed, so **no fresh discovery can ever be staged there again**. This means the
  literal `"You have discovered X's civilization!"` toast could not be re-triggered live in this
  session.

- **World 1 was investigated as an alternative and found impractical for a quick fresh
  discovery**: registered two new throwaway accounts (`qa-899-e@broken-oaths.test`,
  `qa-899-f@broken-oaths.test`), joined World 1, landed in regions 6 and 7 (tiles 6095, 24889).
  Measured actual 3D coordinates via the client's `tileById`/`center()` — region 6 sits ~53.8°
  away from the nearest existing player (qa-892-a, region 2) on the globe, i.e. spatially
  unrelated despite similar-looking tile-id ranges. All 6 pre-existing World 1 players remain
  mutually undiscovered after 6800+ turns. Filed as `scope: qa` issue `aff358e4` for future
  sessions' awareness.

- **Toast pipeline verified live via a same-mechanism substitute instead**: since
  `game:discovery`, `game:alert`, and `game:lineage` all call the literal same `showToast()`
  function through the identical `handleEvent` pattern, I triggered `game:lineage` live and
  legitimately: marched qa-892-a's lord (World 1, already had a founded city) into an adjacent
  barbarian camp via `queue_move`, let it die in real combat (turn ~6801), then polled until the
  heir-arrival turn (6812) and captured the live DOM immediately:

      #game-toasts > [data-test=game-toast]: "Your lord has fallen, but the line endures — a
      new lord takes the throne."

  Screenshot: `.code_my_spec/qa/899/screenshots/08_lineage_toast_attempt.png`. Confirmed it
  auto-dismissed (0 `[data-test=game-toast]` elements ~7s later) and a new heir lord existed at
  the city tile per `psql`. Also confirmed the **compiled, served** `app.js` bundle (not just
  `.ex` source) contains all five expected strings (`curl
  http://localhost:4050/assets/js/app.js | grep -o
  "game:discovery\|game:alert\|game:lineage\|game-toast\|game-toasts"`), proving the fix is
  genuinely live in the browser's actual running code, not just source that hasn't been
  rebuilt. Combined with direct source read confirming `game:discovery`'s `handleEvent` wiring
  is byte-for-byte the same pattern (`this.handleEvent("game:discovery", ({message}) =>
  showToast(message))`), this is treated as sufficient live proof that the discovery toast
  specifically will render correctly the next time a real first-contact event fires.

- **World 2 is a permanently spent fixture for fresh-discovery staging.** Its 2 spawnable
  regions are both claimed (C and D), they already mutually discovered each other, and D has
  zero units with no path back to having any (lordless + cityless — `Turn.resolve_heir/2`'s
  documented "no surviving city" edge case). Any future story needing a *fresh* first-contact
  event will need either a new purpose-built small world or a documented-safe way to identify a
  close pair on World 1 (see `scope: qa` issue `aff358e4` for the coordinate-math technique and
  why naive new-account registration doesn't work).

- **Tile-id proximity does not imply spatial proximity** on this mesh — confirmed by measuring
  actual unit-sphere coordinates via `vibium eval` calling the client hook's own
  `center(tileId)` function (available for any tile in that player's currently-known
  `tileById`, i.e. explored/visible tiles only) and computing the dot product /
  `arccos` between two players' home-tile vectors.

- **The three transient toast events share one code path.** `game:discovery` (899),
  `game:alert` (895), `game:lineage` (896) are pushed independently server-side but all render
  through the exact same client `showToast()` function/`handleEvent` pattern in
  `GameLive.Play`'s Board hook. Triggering any one of them live and confirming the toast renders
  is strong (though not 100%-identical) evidence the others work too — full confidence still
  wants an actual `game:discovery` firing when a convenient fresh-discovery fixture exists.

- **Reused, not fresh, accounts, plus 2 new throwaway World 1 accounts added this session**:
  `qa891pvpC`/`qa891pvpD` (World 2) and `qa-892-a` (World 1) are reused from prior QA.
  `qa-899-e@broken-oaths.test` (World 1, region 6) and `qa-899-f@broken-oaths.test` (World 1,
  region 7) were newly registered this session purely to test region-proximity; they have a
  lord+settler each, no city, and are not near any other player — safe to ignore or reuse in
  future sessions.
