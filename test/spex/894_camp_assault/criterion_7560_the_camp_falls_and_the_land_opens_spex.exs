defmodule BrokenOathsSpex.Story894.Criterion7560Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7560 — reducing a camp to 0 HP destroys it: the destroying
  unit's owner receives a 30 gold reward, and the hex reverts to
  normal, buildable terrain (an improvement can be started there).

  Surface note: see `BrokenOathsSpex.Story894.Criterion7558Spex`'s
  moduledoc for the inferred `"attack"` + `target_camp_id` surface.
  Gold is read from the existing `data-test="player-gold"` badge
  `GameLive.Play` already renders (`{@gold}`, backed by `Game.gold/2`
  per the Fixtures/Play surface list) — no new read invented.

  Ten hits land the killing blow: criterion 7559 pins a full-HP
  Warrior's damage at exactly 10 per hit with no random roll, so ten
  consecutive hits against a 100 HP camp are the deterministic way to
  drive it to exactly 0 without a test-only HP setter (no such setter
  exists for camps — `Fixtures.set_unit_hp/3` is documented as a unit-
  only, narrow exception).

  Scope note: "reverts to normal terrain" is demonstrated here through
  the Worker/Improvement path only (a Road is legal on any land tile —
  `Improvement.allowed?(:road, _)` is unconditionally `true` — so it
  needs no terrain-specific setup). Founding a *second* city on the
  former camp hex is not separately exercised: it would additionally
  require producing and marching a Settler, and risks tripping the
  unrelated `:too_close` founding-distance rule (`Production.
  validate_founding/3` requires 4+ hexes from every existing city)
  for an in-region camp, which would fail the scenario for a reason
  unrelated to this criterion. Both paths are gated by the same "is
  this hex ordinary land" fact, so the Worker path stands in for both.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the camp falls and the land opens" do
    scenario "a camp reduced to 0 HP is destroyed, pays out gold, and frees its hex" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to an already-visible barbarian camp, and a worker is on the way",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps})

        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})

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

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        gold0 = player_gold(play_live)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:camp, camp)
         |> Map.put(:city, city)
         |> Map.put(:gold0, gold0)}
      end

      when_ "my warrior strikes the camp ten times, recharging between each hit", context do
        for i <- 1..10 do
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          if i < 10, do: Fixtures.advance_turn(context.world)
        end

        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the camp is gone from the board", context do
        assert_push_event(context.play_live, "game:camps", %{camps: camps_after})
        assert_push_event(context.play_live, "game:cities", %{cities: cities_after})

        # Anchor: the push pipeline itself is healthy (my own city still
        # renders) — not a stale/empty payload that would pass the
        # refute below vacuously.
        assert Enum.any?(cities_after, &(&1.id == context.city.id))
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))
        {:ok, context}
      end

      then_ "my gold increases by exactly 30", context do
        assert player_gold(context.play_live) == context.gold0 + 30
        {:ok, context}
      end

      then_ "the former camp hex now accepts a normal improvement", context do
        worker =
          Enum.reduce_while(1..20, nil, fn _, _ ->
            case for u <- Fixtures.player_units(context.world, context.user),
                     u.type == :worker,
                     do: u do
              [w | _] ->
                {:halt, w}

              [] ->
                Fixtures.advance_turn(context.world)
                {:cont, nil}
            end
          end)

        refute is_nil(worker)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => context.camp.tile_id
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id,
              do: u

          if w.tile_id == context.camp.tile_id do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_unit", %{"unit_id" => worker.id})
        assert has_element?(context.play_live, "[data-test='build-road']")
        {:ok, context}
      end
    end
  end

  # The gold badge renders the icon component (no digits) followed by
  # the plain integer — the last digit run in the fragment is always
  # the gold total, regardless of the icon's own markup.
  defp player_gold(play_live) do
    html = play_live |> element("[data-test='player-gold']") |> render()

    ~r/\d+/
    |> Regex.scan(html)
    |> List.last()
    |> List.first()
    |> String.to_integer()
  end
end
