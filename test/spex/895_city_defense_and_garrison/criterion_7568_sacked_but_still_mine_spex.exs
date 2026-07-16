defmodule BrokenOathsSpex.Story895.Criterion7568Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7568 — a city reduced to 0 HP is pillaged, not captured:
  it loses one population, its production queue freezes for three
  turn boundaries, and its HP resets to 50 (not 0). The frozen
  production resumes on the fourth boundary from wherever it was
  banked — it does not restart from zero.

  Reuses criterion 7566's `"target_city_id"` attack surface and
  `data-test="city-hp"` element. Grows the city to size 2 first (the
  `City` changeset floors `size` at 1 —
  `lib/broken_oaths/game/city.ex` — so "-1 population" needs a size-2
  starting point to land on an unambiguous, schema-legal size 1
  afterward). No garrison: an undefended city means every attack
  damages the city and none bounces back onto the barbarian, keeping
  the attacker alive across the whole softening loop.

  A Worker (cost 60, no "second citizen to spare" gating unlike
  Settler — see `GameLive.CityPanel.catalog_option/1`) is queued as
  the in-flight production so there is real banked progress for the
  pillage to freeze and later resume. The exact number of hits needed
  to reach 0 HP isn't knowable without `Game.CityDefense` actually
  existing, so the softening loop is bounded generously (25 attacks)
  rather than counted precisely — a documented uncertainty, not a
  fabricated number.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "sacked but still mine" do
    scenario "repeated barbarian attacks pillage the city instead of capturing it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a size-2 city with a worker mid-build, and an adjacent barbarian ready to attack",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, other_join_live, _html} = live(context.other_conn, ~p"/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(other_settler.id)})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => to_string(other_city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(other_play_live, "queue_move", %{
          "unit_id" => to_string(barbarian.id),
          "to_tile" => barbarian_target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == barbarian.id,
                do: u

          if b.tile_id == barbarian_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        # Let the city grow to size 2 before anything is queued, so no
        # production accrues until the item under test is deliberately
        # queued next.
        Enum.reduce_while(1..120, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == city.id, do: c

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "worker"
        })

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:city, city)
         |> Map.put(:city_size0, city.size)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "repeated barbarian attacks whittle the city down to 0 HP", context do
        {city_after, hp_at_pillage, banked_at_pillage} =
          Enum.reduce_while(1..25, :ok, fn _, :ok ->
            render_hook(context.other_play_live, "attack", %{
              "unit_id" => to_string(context.barbarian.id),
              "target_city_id" => to_string(context.city.id)
            })

            [c] =
              for cc <- Fixtures.player_cities(context.world, context.user),
                  cc.id == context.city.id,
                  do: cc

            if c.size < context.city_size0 do
              render_hook(context.play_live, "select_city", %{
                "city_id" => to_string(context.city.id)
              })

              {:halt, {c, city_hp(context.play_live), banked_progress(context.play_live)}}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)

        {:ok,
         context
         |> Map.put(:city_after, city_after)
         |> Map.put(:hp_at_pillage, hp_at_pillage)
         |> Map.put(:banked_at_pillage, banked_at_pillage)}
      end

      then_ "the city loses one population", context do
        assert context.city_after.size == context.city_size0 - 1
        {:ok, context}
      end

      then_ "the city's HP resets to 50, not 0", context do
        assert context.hp_at_pillage == 50
        {:ok, context}
      end

      then_ "production makes no progress for the next three turn boundaries", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        assert banked_progress(context.play_live) == context.banked_at_pillage
        {:ok, context}
      end

      then_ "a fourth boundary resumes production from the banked progress, not from zero", context do
        Fixtures.advance_turn(context.world)

        assert banked_progress(context.play_live) > context.banked_at_pillage
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Worker")
        {:ok, context}
      end
    end
  end

  defp city_hp(play_live) do
    html = render(play_live)
    [_, hp] = Regex.run(~r/data-test="city-hp"[^>]*>(\d+)/, html)
    String.to_integer(hp)
  end

  defp banked_progress(play_live) do
    html = render(play_live)

    [_, banked, _cost] =
      Regex.run(~r/data-test="city-production-current"[^>]*>\D*(\d+)\/(\d+)/, html)

    String.to_integer(banked)
  end
end
