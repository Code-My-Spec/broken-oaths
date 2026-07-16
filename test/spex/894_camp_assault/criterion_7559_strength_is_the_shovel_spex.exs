defmodule BrokenOathsSpex.Story894.Criterion7559Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7559 — damage against a camp is the attacker's flat
  effective strength, with no random roll: a Warrior deals exactly 10
  per hit, a Lord exactly 12, every time — unlike unit-vs-unit combat,
  which rolls a ±25% Civ VI curve around a strength-derived band
  (story 891, criterion 7537).

  Surface note: see `BrokenOathsSpex.Story894.Criterion7558Spex`'s
  moduledoc for the inferred `"attack"` + `target_camp_id` surface and
  the `"game:combat"` push (`damage_dealt`/`damage_taken`) this spec
  reads the exact per-hit number from.

  "No random roll" is demonstrated by striking the same camp with the
  same warrior three separate times (with a turn boundary between each
  to recharge its spent movement, per story 891 criterion 7536) and
  showing every single hit lands the identical number — a ±25% roll
  could not produce three identical results.

  Structure note: the Warrior and Lord facts are independently
  verifiable claims, so each gets its own `spex`/`scenario` pair rather
  than two `scenario` blocks sharing one `spex`. `SexySpex.DSL.spex/2`
  compiles to exactly one `ExUnit` `test`, and `scenario/1` only
  resets the step context inside that same test — it does not start a
  new one. A second `scenario` nested in the same `spex` therefore
  never runs as its own test: if the first scenario's first step
  raises (as it does here, since `"game:camps"` isn't implemented
  yet), the exception propagates straight out of the enclosing `spex`
  test and the second scenario's body never executes at all, silently
  losing that coverage. Two `spex` blocks avoid that trap and give each
  fact its own independently-reported pass/fail.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "strength is the shovel: a warrior's blows are always exactly its strength" do
    scenario "a warrior's blows against the tents are always exactly its strength" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my full-HP warrior stands adjacent to an already-visible barbarian camp", context do
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
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(play_live, "queue_move", %{"unit_id" => warrior.id, "to_tile" => target})

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id,
              do: u

          if w.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:camp, camp)}
      end

      when_ "my warrior strikes the camp three separate times, recharging between each",
            context do
        damages =
          Enum.map(1..3, fn i ->
            render_hook(context.play_live, "attack", %{
              "unit_id" => to_string(context.warrior.id),
              "target_camp_id" => to_string(context.camp.id)
            })

            assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
            if i < 3, do: Fixtures.advance_turn(context.world)
            dealt
          end)

        {:ok, Map.put(context, :damages, damages)}
      end

      then_ "every single hit deals exactly 10 damage", context do
        assert context.damages == [10, 10, 10]
        {:ok, context}
      end
    end
  end

  spex "strength is the shovel: the lord's blows land at its own strength" do
    scenario "the lord's blows land at its own strength, not the warrior's" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my lord stands adjacent to an already-visible barbarian camp", context do
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

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => target})

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [l] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if l.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:lord, lord)
         |> Map.put(:camp, camp)}
      end

      when_ "my lord attacks the camp", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.lord.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        {:ok, context}
      end

      then_ "the hit deals exactly 12 damage", context do
        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
        assert dealt == 12
        {:ok, context}
      end
    end
  end
end
