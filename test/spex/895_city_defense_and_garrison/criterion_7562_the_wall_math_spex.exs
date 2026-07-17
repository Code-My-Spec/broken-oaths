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

  Setup-hardening (not in the original contract): a founding pop
  auto-works the best-scoring adjacent tile (`Yields.pick_worked_tile/2`,
  story 878), and 8 boundaries of a worked tile's food ON TOP OF the
  city center's own floor reliably crosses `Yields.threshold(1)` (20)
  well before the Warrior (40 production, exactly 8 turns at the flat
  5/turn base with the tile left unworked) finishes — silently growing
  the city to size 2 mid-`when_` and turning "20 + 5×1 + 10 = 35" into
  "20 + 5×2 + 10 = 40" for a reason this criterion's SUBJECT (the
  additive defense formula, not growth timing) never meant to
  exercise. The `given_` step now immediately un-works that one
  auto-assigned tile via the ordinary `assign_worked_tile` command
  (center-only food, well under threshold across the whole 8-turn
  wait) — a real in-game action, not a new fixture — so the size-1
  precondition this criterion's own name promises actually holds by
  the time `then_` reads it.
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

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        # See moduledoc's "Setup-hardening" note — keeps the city at
        # size 1 for the whole 8-turn wait ahead, which growing tile
        # production/food was never this criterion's concern.
        case city.worked_tiles do
          [worked | _] ->
            render_hook(play_live, "assign_worked_tile", %{
              "city_id" => to_string(city.id),
              "from_tile_id" => to_string(worked)
            })

          [] ->
            :ok
        end

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "a warrior finishes production and garrisons on the city's own tile", context do
        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        unless warrior.tile_id == context.city.tile_id do
          render_hook(context.play_live, "queue_move", %{
            "unit_id" => to_string(warrior.id),
            "to_tile" => context.city.tile_id
          })

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [w] =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.id == warrior.id,
                  do: u

            if w.tile_id == context.city.tile_id do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)
        end

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        {:ok, Map.put(context, :garrison_warrior, warrior)}
      end

      then_ "the city panel shows defensive strength 35 — base 20 + 5×1 plus the garrisoned warrior's defense 10",
            context do
        assert context.garrison_warrior.tile_id == context.city.tile_id

        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        assert has_element?(context.play_live, "[data-test='city-defense']", "35")
        {:ok, context}
      end
    end
  end
end
