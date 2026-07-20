defmodule BrokenOathsSpex.Story906.Criterion7652Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7652 — a military unit (a Warrior, per this criterion's own
  title) standing adjacent to a rival PLAYER's city can order it
  attacked: the city's HP drops, and the attacker sees the exchange's
  outcome (damage dealt/taken).

  This is "the first PvP in the game" narratively (Stone Age
  deliberately excludes player-vs-player UNIT combat —
  `Game.Combat.hostile?/2`, story 891 criterion 7542), but city assault
  was ALREADY cross-player capable before this story:
  `Game.CityDefense.validate_attack/3`'s own moduledoc is explicit that
  it "doesn't share `Combat.hostile?/2`'s 'no Stone Age PvP'
  restriction," and story 895's own specs already stand a second real
  player's unit in for what production code treats as a barbarian.
  This criterion is this story's own acceptance test for that
  already-real capability, not a new code path — it's expected to
  already be green, unlike this story's later capture-flow criteria
  (7657 on), which exercise genuinely new `BrokenOaths.Combat.Siege`
  behavior.

  Both players are real, driven through their own `GameLive.Play`
  mount (`BrokenOathsSpex.SharedGivens.join_and_found_rival_city/1`):
  `context.other_user` founds the target city; `context.user` (the
  attacker) also founds their own city so they can produce a real
  Warrior (mirrors `BrokenOathsSpex.Story891.Criterion7533Spex`'s own
  "found a city, queue a warrior, wait 8 turns" idiom), then marches it
  onto a land tile adjacent to the target city
  (`BrokenOathsSpex.SharedGivens.march_to/6`).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an adjacent warrior attacks a rival player's city" do
    scenario "a Warrior adjacent to a rival's city damages it and reports the exchange" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my Warrior stands adjacent to a rival player's city", context do
        context = join_and_found_rival_city(context)

        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(my_settler.id)})
        [my_city] = Fixtures.player_cities(context.world, context.user)

        # Both foundings (the defender's inside `join_and_found_rival_city/1`,
        # mine just above) have now seeded wilderness camps around EACH
        # city — see `clear_all_camps/1`'s own moduledoc for why an
        # 8-turn production wait plus a march need a camp-free world.
        :ok = clear_all_camps(context.world)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(my_city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target =
          adjacent_land_tile(context.world, context.other_city.tile_id, [
            my_city.tile_id,
            my_lord.tile_id,
            warrior.tile_id
          ])

        warrior = march_to(context.play_live, context.world, context.user, warrior, target)

        context
        |> Map.put(:warrior, warrior)
        |> Map.put(:target_hp0, context.other_city.hp)
        |> then(&{:ok, &1})
      end

      when_ "I order the Warrior to attack the rival city", context do
        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the attacker sees a combat report and the city loses HP", context do
        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
        assert dealt > 0

        [rival_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert rival_city.hp < context.target_hp0
        {:ok, context}
      end
    end
  end
end
