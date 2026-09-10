defmodule BrokenOathsSpex.Story953.Criterion2791Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2791 — a unit already at 0 movement takes no further step
  this tick: `Turn.move_now/2` still persists a freshly queued order,
  but `Turn.Movement.active_movers/1`'s own `movement_left > 0` gate
  keeps a spent unit from taking any step until the next turn
  boundary recharges it.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a unit with no movement left this turn is ordered to move again" do
    scenario "the order is queued but the unit stays put until the next boundary" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I have joined the world and opened the game board", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "my unit has already spent all its movement this turn", context do
        [settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        step1 =
          context.world
          |> Fixtures.adjacent_tiles(settler.tile_id)
          |> Enum.filter(land?)
          |> List.first() || raise "no adjacent land tile for this seed"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => step1
        })

        [settler_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id,
            do: u

        settler_now =
          if settler_now.movement > 0 do
            step2 =
              context.world
              |> Fixtures.adjacent_tiles(settler_now.tile_id)
              |> Enum.filter(land?)
              |> Enum.reject(&(&1 == settler.tile_id))
              |> List.first()

            if step2 do
              render_hook(context.play_live, "queue_move", %{
                "unit_id" => settler.id,
                "to_tile" => step2
              })

              [u] =
                for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id,
                  do: u

              u
            else
              settler_now
            end
          else
            settler_now
          end

        assert settler_now.movement == 0,
               "expected the settler's movement fully spent by up to two 1-hop moves for this seed"

        {:ok, Map.put(context, :settler, settler_now)}
      end

      when_ "I order the rested-out unit to move again", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        next_tile =
          context.world
          |> Fixtures.adjacent_tiles(context.settler.tile_id)
          |> Enum.filter(land?)
          |> List.first() || raise "no adjacent land tile for the next order for this seed"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.settler.id,
          "to_tile" => next_tile
        })

        {:ok, Map.put(context, :next_tile, next_tile)}
      end

      then_ "the order is accepted but the unit takes no step this tick", context do
        refute has_element?(context.play_live, "[data-test='order-error']")
        assert_push_event(context.play_live, "game:path", %{tiles: _})

        [settler] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.settler.id,
              do: u

        assert settler.tile_id == context.settler.tile_id
        assert settler.movement == 0
        assert settler.order.status == :pending
        assert settler.order.path == [context.next_tile]
        {:ok, context}
      end
    end
  end
end
