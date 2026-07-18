defmodule BrokenOathsSpex.Story895.Criterion7562Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7562 — a city's defensive strength is base (20 + 5 ×
  size) plus the defense stat of whatever is garrisoned on its own
  tile. A freshly founded size-1 city with one garrisoned Warrior
  (Defense 10, per `.code_my_spec/stories/stone_age.md` §4.2) should
  show 20 + 5×1 + 10 = 35.

  Judgment call (no UI surface exists yet for this number): "City HP
  shown in city panel" is explicit story copy (§10.3), so this spec
  reads the defensive-strength number the same way — a new
  `data-test="city-defense"` element on `GameLive.CityPanel`, sibling
  to the existing `city-size`/`city-food` elements. Later criteria in
  this story (7566 on) reuse this same panel for a `city-hp` element;
  see that file's moduledoc for the HP-specific judgment call.

  Garrison, per stories 879/881 (criteria 7471, 7480), is simply "a
  unit standing on the city's own `tile_id`" — no new concept, just
  reused from the existing healing/landing rules.

  Root-caused and re-fixed for the v0.2.1 playtest issue 11500df6's
  own second half (`criterion_7562` reading "40" not "35",
  deterministically, on every run): the ORIGINAL "Setup-hardening"
  note below this paragraph un-worked the one auto-assigned tile to
  keep growth-food under `Yields.threshold(1)` (20) across the
  Warrior's 8-turn build, reasoning "center-only food, well under
  threshold" — true when it was written, but story 905 (tile
  resources, `BrokenOaths.Worlds.Resources`) landed AFTER it and gave
  `Yields.city_center_yield/2` its own bonus-resource term: a city
  founded on a food resource (Cattle/Sheep/Wheat) now yields 3
  food/turn from the center ALONE, not the assumed 2 — traced directly
  (this fixture's own fixed seed 424242 always lands the settler on a
  Cattle-grassland tile): 3/turn × 8 turns = 24 ≥ 20, crossing on turn
  7 regardless of the worked-tile fix, silently growing the city to
  size 2 before `then_` ever reads it. This isn't seed-specific bad
  luck to dodge with a different fixture seed — ANY city founded on a
  food resource hits the same 24 ≥ 20 arithmetic (a resource-free
  tile's 2/turn stays safely under at 16), and city placement has no
  "avoid resources" control. Un-working further can't help either: the
  center tile's own yield is unavoidable, existing regardless of what
  is or isn't worked.

  Fix: stop exposing the size-1 precondition to ANY turns passing at
  all. The Warrior's own 8-turn production race was always incidental
  to this criterion's actual subject (the additive defense FORMULA,
  not how a Warrior gets built) — `Fixtures.spawn_unit/4` places a
  real, correctly-statted Warrior directly on the city's own tile with
  zero intervening turns, so no food ever accrues and the size-1
  precondition can never race away underneath the assertion, on any
  seed, on any terrain.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the wall math" do
    scenario "founding a city then garrisoning a warrior shows the additive defense formula" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a freshly founded size-1 city with no garrison", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "a warrior garrisons on the city's own tile, no turns spent building or marching",
            context do
        {:ok, player} = Fixtures.join_world(context.world, context.user)
        warrior = Fixtures.spawn_unit(context.world, player.id, :warrior, context.city.tile_id)

        # `spawn_unit_for_test` (unlike `queue_production` + a real
        # `advance_turn` tick) is a raw state insert with no PubSub
        # broadcast of its own — `play_live`'s cached assigns would
        # otherwise still show the pre-garrison state. A fresh mount
        # reads everything straight from the server, same as any real
        # page load/reconnect.
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:garrison_warrior, warrior)}
      end

      then_ "the city panel shows defensive strength 35 — base 20 + 5×1 plus the garrisoned warrior's defense 10",
            context do
        assert context.garrison_warrior.tile_id == context.city.tile_id

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id,
            do: c

        assert city.size == 1

        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        assert has_element?(context.play_live, "[data-test='city-defense']", "35")
        {:ok, context}
      end
    end
  end
end
