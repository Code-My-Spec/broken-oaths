defmodule BrokenOathsSpex.Story952.Criterion2770Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2770 — a Scout attacking a barbarian camp deals its flat
  effective strength (5), with no random roll — camp damage is the
  attacker's flat strength every time
  (`BrokenOathsSpex.Story894.Criterion7559Spex`'s own established "no
  random roll" fact for camps, there demonstrated for Warrior (10) and
  Lord (12); this is the same fact for the Scout's own base strength).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout attacks a barbarian camp at strength 5" do
    scenario "a Scout's blow against the tents lands at exactly its own strength" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my Scout stands adjacent to an already-visible barbarian camp", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps}, 500)

        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "scout"})

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :scout)) do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :scout, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, scout.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        clear_tile(context.world, target)
        :ok = Fixtures.relocate_unit(context.world, scout.id, target)

        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == scout.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:scout, scout)
         |> Map.put(:camp, camp)}
      end

      when_ "my Scout attacks the camp", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.scout.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        {:ok, context}
      end

      then_ "the hit deals exactly 5 damage", context do
        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
        assert dealt == 5
        {:ok, context}
      end
    end
  end

  defp clear_tile(world, tile_id) do
    occupant =
      world
      |> Fixtures.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        Fixtures.adjacent_tiles(world, tile_id)
        |> Enum.filter(&(Fixtures.tile_class(world, &1) == :land and &1 != tile_id))

      _relocated =
        Enum.find_value(parking, fn t -> Fixtures.relocate_unit(world, occupant.id, t) == :ok end)
    end

    :ok
  end
end
