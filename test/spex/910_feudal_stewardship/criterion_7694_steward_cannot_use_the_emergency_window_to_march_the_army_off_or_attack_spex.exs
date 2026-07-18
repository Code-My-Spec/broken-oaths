defmodule BrokenOathsSpex.Story910.Criterion7694Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7694 — the bound `criterion_7693`'s own emergency window
  keeps: "defensive orders only... never to launch aggression or march
  the army off"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). Even mid-attack, a steward's `"steward_defend"`
  is not a blank check — a destination far from the danger (marching
  the army off) and an outright attack order are both refused.

  See `criterion_7693`'s own moduledoc for the "under attack" judgment
  call (a real barbarian strike, via `Fixtures.spawn_barbarian/2` +
  `Fixtures.resolve_barbarian_attack/3`) and the `"steward_defend"`
  event this reuses. This criterion's own new judgment call:
  `"steward_attack"`, `%{"owner_user_id" => ..., "unit_id" => ...,
  "target_camp_id" => ...}` — the aggression half, mirroring the
  ordinary `"attack"` hook's own `target_camp_id` param shape. Both
  driven through `attempt_event/3` since neither `handle_event/3`
  clause exists yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the steward cannot use the emergency window to march the army off or attack",
       fail_on_error_logs: false do
    scenario "even mid-attack, a steward cannot march the owner's Lord far away or order an attack" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline and under attack, with a distant tile and a barbarian camp both in reach",
             context do
        %{lord_play_live: lord_play_live} =
          subjugate(context.world, context.conn, context.user, context.other_conn, context.other_user)

        {:ok, vassal_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        go_offline(vassal_play_live)

        [vassal_lord | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(vassal_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, vassal_lord.id)

        [vassal_lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == vassal_lord.id,
              do: u

        assert vassal_lord_now.hp > 0,
               "setup's own barbarian strike killed the Lord outright — nothing left to steward"

        [far_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(barbarian_target)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [vassal_lord_now.tile_id, barbarian_target]))

        [nearby_camp | _] = Fixtures.list_camps(context.world)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_lord, vassal_lord_now)
        |> Map.put(:far_tile, far_tile)
        |> Map.put(:nearby_camp, nearby_camp)
        |> then(&{:ok, &1})
      end

      when_ "I, the steward, try to march their Lord far away and order it to attack a camp",
            context do
        attempt_event(context.lord_play_live, "steward_defend", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.vassal_lord.id),
          "to_tile" => context.far_tile
        })

        attempt_event(context.lord_play_live, "steward_attack", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.vassal_lord.id),
          "target_camp_id" => to_string(context.nearby_camp.id)
        })

        {:ok, context}
      end

      then_ "the Lord never marched off and never struck the camp", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.vassal_lord.id,
              do: u

        refute lord_now.tile_id == context.far_tile

        [camp_now] =
          for c <- Fixtures.list_camps(context.world), c.id == context.nearby_camp.id, do: c

        assert camp_now.hp == context.nearby_camp.hp
        {:ok, context}
      end
    end
  end
end
