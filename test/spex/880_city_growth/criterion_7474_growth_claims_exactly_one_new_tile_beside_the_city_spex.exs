defmodule BrokenOathsSpex.Story880.Criterion7474Spex do
  @moduledoc """
  Story 880 — City Growth
  Criterion 7474 — each population point gained claims exactly one
  adjacent, previously unclaimed workable tile.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "growth claims exactly one new tile beside the city" do
    scenario "a size-1 city grows to size 2" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-1 city with its founding seven tiles", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city_before, city)}
      end

      when_ "it grows to size 2", context do
        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city_before.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city_after] =
          for cc <- Fixtures.player_cities(context.world, context.user),
              cc.id == context.city_before.id,
              do: cc

        {:ok, Map.put(context, :city_after, city_after)}
      end

      then_ "its territory gains exactly one adjacent previously-unclaimed tile", context do
        before_set = MapSet.new(context.city_before.territory)
        after_set = MapSet.new(context.city_after.territory)
        gained = MapSet.difference(after_set, before_set)

        assert MapSet.size(gained) == 1
        [new_tile] = MapSet.to_list(gained)

        assert Enum.any?(
                 context.city_before.territory,
                 &(new_tile in Fixtures.adjacent_tiles(context.world, &1))
               )

        {:ok, context}
      end

      then_ "no other tiles change hands", context do
        before_set = MapSet.new(context.city_before.territory)
        after_set = MapSet.new(context.city_after.territory)

        assert MapSet.subset?(before_set, after_set)
        assert MapSet.size(after_set) == MapSet.size(before_set) + 1
        {:ok, context}
      end
    end
  end
end
