defmodule BrokenOathsSpex.Story906.Criterion7653Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7653 — a unit that is NOT standing adjacent to a rival
  city cannot order it attacked: the order is refused and the city
  takes no damage.

  Already-implemented behavior (`Game.CityDefense.validate_attack/3`'s
  `city.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}`
  clause, wired into `GameLive.Play`'s `"attack"`/`target_city_id`
  handler as `combat_error_message(:not_adjacent)` — see
  `BrokenOathsSpex.Story906.Criterion7652Spex`'s own moduledoc for why
  city assault predates this story). No march is needed to prove
  "non-adjacent": `BrokenOaths.Game.Spawner`'s own doc guarantees each
  joining player's region is claimed independently and spawn tiles are
  chosen well inside it, so `context.user`'s own Lord — left exactly
  where it spawned, never moved — is not adjacent to a city
  `context.other_user` founds in THEIR own, separately-claimed region.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a non-adjacent unit cannot attack the city" do
    scenario "attacking a rival city from far away is refused and does no damage" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my Lord stands nowhere near a rival player's city", context do
        context = join_and_found_rival_city(context)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        refute my_lord.tile_id in Fixtures.adjacent_tiles(context.world, context.other_city.tile_id)

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:target_hp0, context.other_city.hp)
        |> then(&{:ok, &1})
      end

      when_ "I order my Lord to attack the rival city anyway", context do
        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.my_lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the attack is refused as out of range and the city takes no damage", context do
        assert has_element?(context.play_live, "[data-test='combat-error']", "out of range")

        [rival_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert rival_city.hp == context.target_hp0
        {:ok, context}
      end
    end
  end
end
