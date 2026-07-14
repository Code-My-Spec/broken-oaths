# BDD Specs in Broken Oaths

How the sealed-spec discipline applies to *this* project. The framework
docs (philosophy, boundaries, writing_a_spex) cover the generic rules;
this file names the concrete surfaces, fixtures, and traps for a
persistent hex-globe strategy game.

## The spec boundary

Declared in `test/support/broken_oaths_spex.ex`:

```elixir
use Boundary, top_level?: true,
  deps: [BrokenOathsTest, BrokenOathsWeb, BrokenOathsSpex.Fixtures]
```

Specs use `BrokenOathsSpex.Case` (ConnTest + LiveViewTest + SexySpex
DSL + DB sandbox). Anything outside those deps is denied — enforced by
Boundary at compile time and by two Credo checks on `_spex.exs` files:
the framework function-level denies (`CMS0002`) and the project
whole-module denies (`BROKEN0001`: `File`, `Port`, `:file`,
`BrokenOaths.Repo`, `BrokenOaths.Game`, `BrokenOaths.Worlds`,
`BrokenOaths.Users`, `BrokenOaths.Accounts`, `BrokenOaths.Integrations`).

## Public surfaces a spec may drive

| Surface | Module(s) | Drive with |
|---|---|---|
| The game board (default, 3D globe) | `BrokenOathsWeb.WorldLive.Show` — soon `BrokenOathsWeb.GameLive.Play` / `.Join` | `live/2` + `render_hook/3` for hook-mediated events (`select_at`, `view_sync`, `viewport_resize`), `render_click` for buttons |
| The classic DOM board | same LiveViews with `?mode=classic` | selectors — every tile is a real element (`[phx-value-id='42']`); use `GlobeHelpers.camera_on/2` + `click_tile/2` |
| World list | `BrokenOathsWeb.WorldLive.Index` | `live/2` + element clicks |
| Auth | `BrokenOathsWeb.UserLive.{Registration,Login,Confirmation}` | forms; or skip via the session-token fixture below |
| Accounts / invitations | `BrokenOathsWeb.AccountLive.*`, `InvitationsLive.*` | forms + clicks |

The globe doctrine matters here: **the canvas renderer has no tile
DOM by design.** Gameplay facts travel as `push_event` payloads —
assert them with `assert_push_event/3` (`globe3d:window`,
`globe3d:selected`, `globe3d:airspace`). Camera state is URL params
(`?yaw=&pitch=&zoom=`), so a spec can mount at any exact view. Use
`test/support/globe_helpers.ex` (`camera_on/2`, `click_tile/2`,
`select_tile_at/3`, `look_at/4`) instead of hand-rolling geometry.

## Fixture inventory (`BrokenOathsSpex.Fixtures`)

| Function | State it represents |
|---|---|
| `user_fixture/1` | A confirmed registered player |
| `user_scope_fixture/0,1` | A player wrapped in the auth Scope |
| `generate_user_session_token/1` | A logged-in browser session (put in conn session as `:user_token`) |
| `world_fixture/1` | A provisioned world (seed/frequency) — worlds are server-provisioned, not player-created, so seeding one is sanctioned |

Nothing gameplay-derived is on the bridge on purpose: units, orders,
turns, exploration, region claims are all state a player creates *by
playing*, and specs must create them by playing (drive GameLive).

## Legal observable surfaces in `then_`

- Rendered HTML: `render(view)`, `has_element?/2` — sidebar facts
  (`"#42"`, `"Pentagon (impassable)"`, terrain labels, turn number).
- Pushed board data: `assert_push_event(view, "globe3d:window", %{tiles: tiles})`
  and friends — this is the canvas board's equivalent of the DOM.
- Patched URLs: `assert_patch/2` for camera/mode changes;
  `assert_redirect/2` for world switching.
- HTTP responses: `response/2` etc. for controller surfaces
  (`/worlds/:id/texture.png`, `/health`).

Not legal: `BrokenOaths.Game.get_*`, `Repo.all/1`, reading schema rows
to "prove" an outcome. A `then_` proves what the player sees.

## Project anti-patterns

- **Do not seed `BrokenOaths.Game` state in `given_`.** A unit exists
  because a player spawned; an order exists because a player queued it
  through `GameLive.Play`. If a scenario needs a mid-game position,
  the `given_` is a sequence of real plays (or a shared given that
  performs them), not a fixture.
- **Do not call `BrokenOaths.Worlds.Generator`/`Globe` to predict
  terrain.** If a scenario depends on terrain ("settler can't found on
  ocean"), mount at a known seed + camera where the fact is visible
  and assert through the surface. Known-good anchor: tile 0 is always
  the north-pole pentagon (impassable mountains) for any seed.
- **Do not `Process.sleep` for turn boundaries.** When the turn system
  lands, specs trigger ticks through whatever test-tick surface
  `WorldServer` exposes — never wall-clock waits.
- **Do not assert canvas pixels.** The canvas is paint; the pushed
  payloads and the classic-mode DOM are the truth.
