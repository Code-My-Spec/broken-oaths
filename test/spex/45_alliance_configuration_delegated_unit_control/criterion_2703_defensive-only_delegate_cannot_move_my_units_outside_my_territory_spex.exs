defmodule BrokenOathsSpex.Story947.Criterion2703Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2703 — even mid-emergency, `"steward_defend"` is not a
  blank check: `BrokenOaths.Feudal.Stewardship.defend_target_allowed?/3`
  refuses any destination beyond one hex from the unit's own current
  tile — a far-off target (well outside the owner's own immediate
  reach, let alone their territory) never moves the unit. Overreaching
  the destination while genuinely under attack is provable sabotage
  (logged, dinged on the steward's own Honor), not a silent no-op —
  same construction as story 910's own criterion 7694 for a
  lord/vassal pair, reused here for an accepted ally.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Defensive-only delegate cannot move units outside the owner's territory",
    fail_on_error_logs: false do
    scenario "an accepted ally cannot march the offline owner's attacked Lord far away" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my offline Lord is under attack, with a distant tile in reach", context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(owner_live)

        [my_lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(my_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} = Fixtures.resolve_barbarian_attack(context.world, barbarian.id, my_lord.id)

        [my_lord_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == my_lord.id,
            do: u

        assert my_lord_now.hp > 0, "setup's own barbarian strike killed the Lord outright"

        [far_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(barbarian_target)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [my_lord_now.tile_id, barbarian_target]))

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_lord, my_lord_now)
        |> Map.put(:far_tile, far_tile)
        |> then(&{:ok, &1})
      end

      when_ "the ally tries to move my unit far outside its own immediate reach", context do
        attempt_event(context.ally_live, "steward_defend", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => to_string(context.my_lord.id),
          "to_tile" => context.far_tile
        })

        {:ok, context}
      end

      then_ "the out-of-reach move never happened", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.my_lord.id,
            do: u

        refute lord_now.tile_id == context.far_tile
        {:ok, context}
      end
    end
  end
end
