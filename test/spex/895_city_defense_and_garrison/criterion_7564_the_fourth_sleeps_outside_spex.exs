defmodule BrokenOathsSpex.Story895.Criterion7564Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7564 — once three friendly military units already garrison
  a city, a fourth is refused with a human-readable reason — the same
  `data-test="order-error"` channel every other occupied-tile move
  refusal in this codebase surfaces through (see criterion 7539's
  "tile becomes free for movement" check, and `world_server.ex`'s
  `occupied_by_own?`).

  Setup duplicates criterion 7563's three-warrior garrison exactly
  (same story, same fixture technique) — see that file's moduledoc for
  the military/civilian split this cap is scoped to. The player's own
  auto-spawned Lord (also `:lord`, a military type) stands in as the
  fourth, sparing a fourth Warrior production.

  This criterion is only meaningful once 7563's exception is real: the
  `given_` hard-asserts all three warriors actually reached the tile
  before testing the fourth. Without that check, today's code would
  already refuse the lord — via the pre-existing, unrelated
  `occupied_by_own?` single-stacking rule that blocks ANY second unit
  of mine on ANY occupied tile — and this spec would pass for the
  wrong reason instead of surfacing the missing cap.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the fourth sleeps outside" do
    scenario "a fourth military unit is turned away from an already-full city tile" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city already garrisoned by three warriors, with the player's lord standing free nearby",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        for _ <- 1..24, do: Fixtures.advance_turn(context.world)

        [w1, w2, w3] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        for warrior_id <- [w1.id, w2.id, w3.id] do
          garrison!(context.world, play_live, context.user, warrior_id, city.tile_id)
        end

        # This scenario is only meaningful once all three genuinely
        # stand on the tile — criterion 7563's own exception, not this
        # criterion's. Without this hard check, a world where only one
        # (or zero) warriors actually made it onto the tile would still
        # refuse the lord — via the pre-existing, unrelated
        # `occupied_by_own?` single-stacking rule — and this spec would
        # pass for the wrong reason.
        3 =
          for(
            u <- Fixtures.player_units(context.world, context.user),
            u.id in [w1.id, w2.id, w3.id],
            u.tile_id == city.tile_id,
            do: u.id
          )
          |> length()

        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:lord, lord)
         |> Map.put(:lord_tile0, lord.tile_id)}
      end

      when_ "the lord is ordered onto the already-full city tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.lord.id),
          "to_tile" => context.city.tile_id
        })

        {:ok, context}
      end

      then_ "the order is refused with a human-readable reason and the lord stays put", context do
        assert has_element?(context.play_live, "[data-test='order-error']")

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.lord.id, do: u

        assert lord.tile_id == context.lord_tile0
        refute lord.tile_id == context.city.tile_id
        {:ok, context}
      end
    end
  end

  defp garrison!(world, play_live, owner, unit_id, to_tile) do
    render_hook(play_live, "queue_move", %{"unit_id" => to_string(unit_id), "to_tile" => to_tile})

    Enum.reduce_while(1..10, :ok, fn _, :ok ->
      [u] = for uu <- Fixtures.player_units(world, owner), uu.id == unit_id, do: uu

      if u.tile_id == to_tile do
        {:halt, :ok}
      else
        Fixtures.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end
end
