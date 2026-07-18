# QA Result — Story 903 (Advancing to Bronze Age) — Re-run

Re-run following the CityPanel fix for issue 846e0c96 (Bronze Spearman
never appeared in the Build list — hardcoded catalog). Issue is
resolved. This session re-confirms the fix live and lightly
re-confirms the rest of the story.

## Status: PASS

## Scenarios

### Bronze Spearman renders and is buildable through the real UI (the fix)

**PASS.** Logged in as `qa@broken-oaths.test` (player 1, World 1, city
1 — already Bronze Age from the prior 903 session, `completed_techs`
contains `bronze_working` per psql). Selected city 1 via the
`select_city` push. `[data-test='city-panel']` Build list now renders
5 options: `production-option-settler`, `-worker`, `-warrior`,
`-granary`, `-bronze_spearman` — all `data-disabled="false"`. Read the
live DOM for the Bronze Spearman button:

    <button data-test="production-option-bronze_spearman" data-disabled="false"
            phx-click="queue_production" phx-value-city_id="1" phx-value-item="bronze_spearman">
      Bronze Spearman 60
    </button>

Clicked it directly (the real Build button, not the pushEvent
workaround). City panel immediately showed "Bronze Spearman 0/60" in
the active production slot. Confirmed via psql:
`game_production_items` gained `id=42, city_id=1, type=bronze_spearman,
banked=0, cost=60`. Stepped the dev QA turn clock 6x — the item
completed (row removed from `game_production_items`) and a new unit
appeared: `game_units id=396, player_id=1, type=bronze_spearman,
hp=120, max_hp=120, tile_id=14741`. Did a fresh `/play/1` navigation
(new LiveView mount) afterward — the panel and age status persisted
correctly. **A real player can now build a Bronze Spearman entirely
through the actual UI — the story's core promise is fixed
end-to-end.**

Screenshots: `10_city_panel_bronze_spearman_and_granary_render.png`,
`11_bronze_spearman_queued_via_real_build_button.png`,
`12_bronze_spearman_spawned_fresh_reload.png`.

### Base build options still render (settler/worker/warrior)

**PASS.** Confirmed in the same DOM read above — `production-option-settler`,
`-worker`, `-warrior` all present and `data-disabled="false"` alongside
the two new gated options. No regression to the pre-existing catalog.

### Granary appears once Pottery is complete (902's half of the same fix)

**PASS** (bonus check — player 1 has Pottery completed too, so this
came free). `production-option-granary` rendered enabled
(`data-disabled="false"`, city 1 has `has_granary=false` in psql, so
correctly not yet built and not disabled).

### Bronze Spearman does NOT appear for a Stone Age player (gate holds)

**PASS.** Logged in as `qa891a@test.local` (player 2, World 1, city 2,
`completed_techs={}` per psql — pure Stone Age) via the real magic-link
flow (`/dev/mailbox`). `[data-test='age-panel']` read "Stone Age".
Selected city 2 — Build list rendered **only**
`production-option-settler`, `-worker`, `-warrior`. No
`production-option-bronze_spearman` or `-granary` anywhere in the DOM.
The dynamic, tech-gated catalog correctly withholds both gated items
for a Stone Age player. Screenshot:
`13_stone_age_player_no_bronze_spearman_or_granary.png`.

### Bronze Working flips the age (criterion 7632) — light re-confirmation

**PASS**, rests on the prior live pass (attempt d81ee10c) plus
incidental re-confirmation this session: player 1's
`[data-test='age-panel']` read "Bronze Age" on a fresh `/play/1`
mount, and player 2's read "Stone Age" — both live DOM reads, not
psql-only. Screenshot: `09_bronze_age_confirmed_before_test.png`. No
combat/notification code touched by this fix — not re-run.

### The Spearman outfights a barbarian (criterion 7633, combat mechanics) — resting on prior pass

**PASS**, resting on the prior live pass (attempt d81ee10c, which
fought a directly-queued spearman to a win against a Barbarian
Warrior, 4 exchanges, spearman survived at 47/120 hp). `Combat` module
is untouched by this session's fix (confirmed via the issue
resolution notes — only `CityPanel`/`Production.available_items/1`/
`Play` changed). The freshly UI-built spearman (unit 396) has the
identical stats (`hp=max_hp=120`) as the one already proven to win
that fight, so the backend result still applies to a UI-built unit.
Not re-fought this session — time-boxed per task instructions since
only the build-UI path changed.

### Cities grow past the Stone Age cap, to size 6 (criterion 7635) — light re-confirmation

**PASS.** City 1 (player 1, Bronze Age) confirmed at `size=6` via
psql this session. Growth-cap mechanics untouched by this fix.

### A Stone Age city still caps at 4 (criterion 7636) — light re-confirmation

**PASS.** City 2 (player 2, Stone Age) confirmed at `size=4` via
psql this session, corroborating the cap holds independent of the fix.

### Barbarians don't scale up with the player (criterion 7637) — spot-check

**PASS.** Spawned a fresh barbarian via the dev QA endpoint after
player 1's Bronze Spearman build: `{"type":"barbarian_warrior",
"hp":120,"max_hp":120}` — same baseline as every prior spot-check,
confirming barbarians remain unaffected by the fix (which only touched
UI catalog rendering, never `Combat.base_strength/1`). Barbarian
deleted afterward to keep the world clean.

### Profile reflects the age (criterion 7638) — light re-confirmation

**PASS.** Player 1's `[data-test='age-panel']` read "Bronze Age" on a
brand-new `/play/1` mount this session (see 7632 above) — durable,
not a stale socket assign.

## Evidence

Screenshots in `.code_my_spec/qa/903/screenshots/`:
- `09_bronze_age_confirmed_before_test.png`
- `10_city_panel_bronze_spearman_and_granary_render.png`
- `11_bronze_spearman_queued_via_real_build_button.png`
- `12_bronze_spearman_spawned_fresh_reload.png`
- `13_stone_age_player_no_bronze_spearman_or_granary.png`

psql evidence (inline in scenarios above): `game_player_research`,
`game_production_items`, `game_units`, `game_cities` reads before/
during/after the build.

## Issues

None filed this session. The prior blocking issue (846e0c96) is
confirmed resolved live — no re-open needed.

## Session notes

- World 1 was left unpaused (turn 9494) at session start — paused it
  before making changes, resumed it (`POST /dev/qa/worlds/1/resume`)
  at the end. Turn was 9500 when resumed.
- `mcp__vibium__browser_*` MCP tools were not present in this session's
  tool list; used the documented CLI fallback (`vibium` with
  `dangerouslyDisableSandbox: true`) per the brief's own guidance.
- `vibium screenshot -o <path>` ignores the directory component and
  always writes to `~/Pictures/Vibium/<filename>` — this matches the
  QA plan's own documented behavior ("vibium screenshot # writes
  ~/Pictures/Vibium/screenshot.png"), not a new bug. Worked around by
  `cp`-ing into the story's screenshots directory after each capture.
- Cleared browser cookies between the player-1 and player-2 sessions
  to force a clean re-auth (the persisted Chrome profile carried a
  stale session from a different QA account at session start).
