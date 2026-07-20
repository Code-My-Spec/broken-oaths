defmodule BrokenOathsSpex.Story906.Criterion7654Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7654 — a civilian unit (a Settler) standing adjacent to a
  rival player's city cannot besiege it: the order is refused, the
  city takes no damage, and the civilian's own movement isn't spent on
  a phantom "attack".

  Genuinely new: `Game.CityDefense.validate_attack/3` today checks
  movement, adjacency, and "not my own city" — nothing about the
  attacker's TYPE. A Settler (`Game.Combat.base_strength(:settler) ==
  0`) can already walk right up and "attack" today; it does zero
  effective damage (0 strength) but is neither refused nor left with
  its movement untouched (`WorldServer.resolve_city_attack/3`
  unconditionally zeroes `attacker.movement` on ANY resolved attack,
  civilian or not) — this criterion is `BrokenOaths.Combat.Siege`'s own
  acceptance test that a civilian besieger is refused outright, not
  merely ineffective. `data-test="combat-error"` is the same alert
  `criterion_7653` already reads; a fresh `combat_error_message/1`
  clause for whatever refusal atom Siege introduces (e.g.
  `:not_military`) is this criterion's own implementation debt.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a civilian unit cannot besiege a city" do
    scenario "a Settler adjacent to a rival city is refused, not just ineffective" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my unfounded Settler stands adjacent to a rival player's city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target =
          adjacent_land_tile(context.world, context.other_city.tile_id, [
            my_lord.tile_id,
            my_settler.tile_id
          ])

        settler = march_to(context.play_live, context.world, context.user, my_settler, target)

        context
        |> Map.put(:settler, settler)
        |> Map.put(:settler_movement0, settler.movement)
        |> Map.put(:target_hp0, context.other_city.hp)
        |> then(&{:ok, &1})
      end

      when_ "I order my Settler to besiege the rival city", context do
        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.settler.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the order is refused, the city is untouched, and the Settler kept its movement",
            context do
        assert has_element?(context.play_live, "[data-test='combat-error']")

        [rival_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert rival_city.hp == context.target_hp0

        [settler] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.settler.id,
              do: u

        assert settler.movement == context.settler_movement0
        {:ok, context}
      end
    end
  end
end
