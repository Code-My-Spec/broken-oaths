defmodule BrokenOathsSpex.Story910.Criterion7693Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7693 — the exception `criterion_7692`'s own baseline opens
  for: "if the offline player is UNDER ATTACK, a steward may command
  their units to DEFEND — defensive orders only, active only while
  under attack"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). This story's own text names an ALLY specifically
  as one of the three eligible steward relationships (alongside lord
  and fellow vassal); this criterion exercises that one — see
  `BrokenOathsSpex.Story910.Criterion7688Spex`'s own moduledoc for the
  real, already-shipped alliance propose/accept flow this reuses.

  ## "Under attack" — this criterion's own new judgment call

  No "under attack" flag exists anywhere in this codebase yet. This
  spec's judgment call: a real barbarian landing a real hit on the
  offline owner's own unit, THIS turn, IS "under attack" — the most
  literal, observable interpretation available, using the SAME
  documented narrow exception (`Fixtures.spawn_barbarian/2` +
  `Fixtures.resolve_barbarian_attack/3`) story 891/896's own combat
  specs already rely on for "a barbarian's attack, with no story-893
  AI or session of its own to drive it for real." The owner's own LORD
  (base strength 12, 150 max HP) is the struck unit, not a civilian —
  a Settler's own 0 combat strength risks a one-hit kill from the SAME
  barbarian, which would collapse this setup entirely (the "still
  standing, moved to safety" story this criterion tells requires the
  attacked unit to survive the hit).

  `"steward_defend"`, `%{"owner_user_id" => ..., "unit_id" => ...,
  "to_tile" => ...}` — deliberately a SEPARATE event from
  `criterion_7692`'s own `"steward_queue_move"`, not a parameter on it:
  the two need different eligibility rules (never vs. only-while-
  attacked), and a single shared event would need an extra flag this
  spec has no reason to invent. Driven through `attempt_event/3` since
  no `handle_event/3` clause exists for it yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an ally issues a defensive order while the offline owner is under attack",
       fail_on_error_logs: false do
    scenario "an ally's defensive move order for an offline, attacked owner's unit actually lands" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my offline ally's Lord was just struck by a barbarian, and survived", context do
        %{play_live_a: ally_play_live, play_live_b: owner_play_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(owner_play_live)

        [owner_lord | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(owner_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, owner_lord.id)

        [owner_lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == owner_lord.id,
              do: u

        assert owner_lord_now.hp < owner_lord.hp,
               "setup's own barbarian strike never actually landed"

        assert owner_lord_now.hp > 0,
               "setup's own barbarian strike killed the Lord outright — nothing left to defend"

        safe_target =
          adjacent_land_tile(context.world, owner_lord_now.tile_id, [barbarian_target])

        context
        |> Map.put(:ally_play_live, ally_play_live)
        |> Map.put(:owner_lord, owner_lord_now)
        |> Map.put(:safe_target, safe_target)
        |> then(&{:ok, &1})
      end

      when_ "my ally issues a defensive order for my Lord", context do
        attempt_event(context.ally_play_live, "steward_defend", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.owner_lord.id),
          "to_tile" => context.safe_target
        })

        {:ok, context}
      end

      then_ "the defensive order actually moved my Lord to safety", context do
        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [lord_now] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == context.owner_lord.id,
                do: u

          if lord_now.tile_id == context.safe_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.owner_lord.id,
              do: u

        assert lord_now.tile_id == context.safe_target
        {:ok, context}
      end
    end
  end
end
