defmodule BrokenOathsSpex.Story894.Criterion7558Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7558 — a military unit standing adjacent to a barbarian
  camp can attack it, and the camp never strikes back: the camp loses
  HP, but the attacker's own HP is untouched, no matter how many times
  it swings.

  Surface note: attacking a camp is inferred to reuse the same
  `"attack"` hook story 891 established for unit-vs-unit combat
  (criterion 7533), swapping `target_unit_id` for `target_camp_id`
  since a camp is not a `Game.Unit` — `BrokenOaths.Game.Camps` doesn't
  exist yet, so this is this spec's judgment call for the event shape,
  the same status story 892's `"game:camps"` push inference carries.
  Combat resolution is likewise assumed to reuse the `"game:combat"`
  push criterion 7540 established (`damage_dealt`/`damage_taken`
  keys) — `combat.spec.md` names "flat-strength damage against camps"
  and "combat-result reporting" as the same `Game.Combat` module's
  responsibility, so the same result event is the natural fit.

  The target camp is one of the 1-2 in-region camps guaranteed visible
  immediately on founding the first city (story 892, criterion 7543)
  — no march through fog is needed here, unlike story 892's discovery
  criteria.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "free hits on the tents" do
    scenario "attacking a camp costs the camp HP but never the attacker's" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to an already-visible barbarian camp", context do
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

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:camp, camp)}
      end

      when_ "I order my warrior to attack the camp", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        {:ok, context}
      end

      then_ "the camp loses HP but my warrior takes no counter-damage", context do
        assert_push_event(context.play_live, "game:combat", %{
          damage_dealt: dealt,
          damage_taken: taken
        })

        assert is_integer(dealt) and dealt > 0
        assert taken == 0

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.hp == context.warrior_hp0

        assert_push_event(context.play_live, "game:camps", %{camps: camps_after})
        camp_after = Enum.find(camps_after, &(&1.id == context.camp.id))

        assert camp_after != nil
        assert camp_after.hp < context.camp.hp
        {:ok, context}
      end
    end
  end
end
