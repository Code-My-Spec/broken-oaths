defmodule BrokenOathsSpex.Story947.Criterion2701Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2701 — no steward relationship, however trusted, ever
  grants war/attack authority: `WorldServer`'s own `:steward_attack`
  handler always refuses with `:not_allowed`, unconditionally,
  regardless of eligibility — "never to launch aggression" is enforced
  structurally, the same absence-of-a-real-path discipline
  `steward_disband_unit`/`steward_cancel_production_item` share (see
  `BrokenOaths.Feudal.Stewardship`'s own moduledoc).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Full-control ally cannot start a war the owner could not start",
    fail_on_error_logs: false do
    scenario "an accepted, eligible ally's attack order is always refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted, eligible ally and a nearby hostile barbarian exists",
             context do
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

        [target_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(my_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, target_tile)

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:barbarian, barbarian)
        |> then(&{:ok, &1})
      end

      when_ "the ally tries to use my unit to attack the barbarian", context do
        attempt_event(context.ally_live, "steward_attack", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => to_string(context.my_lord.id),
          "target_camp_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the barbarian was never struck", context do
        [barbarian_now] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        assert barbarian_now.hp == context.barbarian.hp
        {:ok, context}
      end
    end
  end
end
