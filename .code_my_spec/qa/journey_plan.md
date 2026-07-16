# Qa Journey Plan

## Journeys

### new_player_settles

Role: Gem-Weary Wes, brand new — first ten minutes in the game.

Steps:
1. Visit `/users/register`, register a fresh email, follow the magic
   link from `/dev/mailbox` (Swoosh local adapter) to land logged in.
2. Visit `/play`, see the world picker; click the Join button for
   "QA World" (`[data-test='join-world-6']`).
3. Land on `/play/6`: the cloud-wrapped globe renders with one clear
   bubble around the spawn — a lord and a settler visible, gold badge
   shows 50.
4. Left-click the settler on its exact tile — the unit panel opens
   (type Settler, HP 50/50, Movement 2/2) with a Found City button.
5. Right-click a nearby land tile — the settler moves immediately
   (spending movement), the dashed path renders for any remainder.
6. Click Found City (walk out of range first if the spacing error
   toast appears — that toast is itself an expected outcome to note).
7. City appears on the settler's tile; the settler is gone; the city
   panel shows size 1, a default name, and the production catalog.
8. Queue a Warrior via the catalog button; the current-production row
   shows "Warrior 0/40" with a progress bar.

Expected outcome: a registered player has joined a world, moved a
unit, founded their first city, and set production — without any
console, refresh, or workaround. Crosses stories 873/875/876/877/878/879.

### returning_lord_manages_city

Role: Gem-Weary Wes, returning — the established QA account.

Steps:
1. Log in at `/users/log-in` with `qa@broken-oaths.test` /
   `qa-password-123!` (password form `#login_form_password`).
2. Visit `/play`; the joined world shows Enter (not Join); click into
   world 6 — the camera resumes on the civilization.
3. Left-click own city (Oakhaven) — city panel opens with name, size,
   food progress, per-turn production, worked-tile list (center marked
   Free), and assignable tiles with Work buttons.
4. Rename the city via the name form; the header updates and survives
   a page reload.
5. Queue two items (Warrior then Worker); click the Worker's move-up
   arrow — the queue order swaps, banked progress stays with items.
6. Click Abandon on the current item — it disappears, the next item
   becomes current at its own banked value.
7. Wait one 60s boundary: food and the current build's banked value
   both increase; the turn counter ticks in the top bar.

Expected outcome: full city management loop works with real buttons,
and one live turn boundary visibly advances the economy. Crosses
stories 873/874/879/880.

### worker_improves_the_land

Role: Gem-Weary Wes with a producing city.

Steps:
1. Log in as the QA account and enter world 6.
2. Select an idle worker (or queue one and wait for it to spawn).
3. The unit panel shows Build actions gated by terrain (Farm only on
   flat grassland/plains; Mine only on hills).
4. Move the worker to a flat grassland tile inside city territory;
   click Build Farm.
5. Wait three boundaries; verify the farm completes (improvement on
   the tile) and attempting a second build on that tile shows the
   "already has a completed improvement" error.
6. In the city panel, assign the farmed tile as a worked tile; the
   city's food income visibly rises on the next boundary.

Expected outcome: the worker economy loop — build, complete, refuse
duplicates, feed the city. Crosses stories 875/879/880/882.

### empire_expands

Role: Gem-Weary Wes expanding to a second city.

Steps:
1. Log in as the QA account, enter world 6, select a size-2+ city.
2. Queue a Settler (note: at size 1 the option is disabled with the
   "Needs a second citizen to spare" reason — verify on any size-1
   city if present).
3. When the settler spawns (city size drops by one at that boundary),
   select it and try Found City near the capital: the "Too close to an
   existing city." toast appears and the settler survives.
4. Right-click a spot 4+ hexes out (into fog is fine — orders into
   fog are legal); the settler marches across boundaries.
5. Found City at the destination: a new size-1 city with exactly its
   seven-tile founding ring; the old city's stats unchanged by the act.

Expected outcome: settler production pays its population cost, spacing
is enforced with a human reason, and a second city bootstraps exactly
like the first. Crosses stories 875/876/879/883/878.

## Prerequisites

- Dev server running at `http://localhost:4050` — started by the
  operator only, with the isolated build:
  `MIX_BUILD_PATH=_build/devserver nohup mix phx.server > /tmp/claude/devserver.log 2>&1 &`
  (never restart it from a QA session; never run any `mix`/`iex`
  command during execution — psql and the browser only, per
  `.code_my_spec/qa/plan.md`).
- Seeds: `mix run priv/repo/qa_seeds.exs` (idempotent; run by the
  operator before the session if state looks off). Provides the QA
  account and worlds.
- Credentials: `qa@broken-oaths.test` / `qa-password-123!` (password
  form). New-player journeys register fresh emails and confirm via
  `http://localhost:4050/dev/mailbox`.
- Worlds: "QA World" id 6 (seed 424242, frequency 54, ~104 spawnable
  regions — safe for new joins); "QA World (Fill Test)" id 10 has only
  two spawnable regions and both are taken — do NOT use it for
  new-player joins.
- Browser: vibium CLI (sandbox disabled); board interactions via
  PointerEvents on `#board-viewport` (left = select, right = move);
  panel interactions via real `[data-test=…]` buttons.

## Notes

- Turn boundaries are 60s wall-clock in dev; journeys that wait on
  boundaries should verify state via psql (`broken_oaths_dev`) between
  screenshots rather than idling in the browser.
- Combat, barbarians, roads' movement effects, and multi-player
  visibility journeys are out of scope — those systems are future
  stories (the road Build button exists but is a no-op; see issue
  9bf18133).
- World 6 accumulates state across QA sessions by design; journeys are
  written to be additive (new cities/units) rather than assuming a
  pristine world.
