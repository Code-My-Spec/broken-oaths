defmodule BrokenOathsSpex.Story917.Criterion7745Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7745 — "A vassal who seizes the moment declares
  independence through the normal story-915 path — cities rise on the
  fallen lord's Honor and tribute record, and a strain-sized temporary
  rebellion army spawns. The death is only the opening; the
  liberation mechanics are unchanged."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).

  ## Scope boundary against story 915

  This spec deliberately does NOT assert the exact city-rise
  threshold formula (Honor + tribute rate) or the exact army-size
  formula (from Oath Strain) — both are story 915's own component to
  own, the same way `BrokenOathsSpex.Story913.Criterion7725Spex`'s
  own moduledoc scopes those out of ITS component
  (`BrokenOaths.Game.OathStrain`). What this spec DOES own: proving
  the SAME single `declare_independence` action produces those two
  effects even when triggered from the seize-the-moment prompt
  (i.e. against an already-dead lord) — "the liberation mechanics are
  unchanged" is, by construction, satisfied by driving the identical
  event this batch's sibling specs already establish rather than by
  a bespoke "leaderless-only" code path. The gherkin's third clause
  ("the outcome matches what a story-915 declaration would have
  produced against that same lord") restates this same fact in
  different words and isn't asserted as a SEPARATE comparison against
  a live-lord control run — see the moduledoc note in
  `criterion_7746`'s own file for why a full differential test was
  judged out of scope for this batch.

  ## "High Oath Strain" and "low Honor" — real, already-shipped levers

  - Oath Strain: the SAME 7x refused-call-to-arms spike
    `criterion_7725`'s own moduledoc documents (`+15` each, clamped at
    100 — `BrokenOaths.Game.Tribute.spike_oath_strain/1`).
  - Honor: the lord's OWN Honor (not the vassal's) is docked by
    executing a captured garrison — `resolve_garrison_fate`,
    `"execute"`, already shipped and real
    (`BrokenOaths.Game.WorldServer.apply_garrison_fate_honor/3` ->
    `Siege.apply_execute_honor_penalty/1`), the same mechanism
    `BrokenOathsSpex.Story906.Criterion7662Spex` already exercises.
    This spec grinds the vassal's OWN city down (undefended, same
    "avoid real counter-fire" ordering `criterion_7662` documents),
    lets them raise a last-stand garrison, then executes it —
    combining the Honor hit and the vassal's own subjugation into one
    conquest rather than needing a second, throwaway rival city.

  ## Not-yet-built surface

  `declare_independence` doesn't exist anywhere in `lib/` yet (see
  `criterion_7725`'s own moduledoc) — driven through `attempt_event/3`.
  "Cities rise" / "temporary rebellion army spawns" have no dedicated
  DOM surface yet either; this spec reads the already-established
  `city-status` badge (`:free`/`:broken`/`:occupied`,
  `BrokenOaths.Game.Siege.status/1`) for the first, and a raw unit-count
  delta (`Fixtures.player_units/2`, sanctioned board-state read) for
  the second — the narrowest true stand-ins available without
  fabricating a formula this story doesn't own.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "seizing the moment liberates through the normal path", fail_on_error_logs: false do
    scenario "a vassal with high strain against a dishonored fallen lord rises and rallies a temporary army" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "a vassal whose fallen lord had low Honor", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        broken_city =
          grind_city(context.play_live, context.world, my_lord, context.other_user, context.other_city)

        render_hook(context.other_play_live, "queue_production", %{
          "city_id" => to_string(context.other_city.id),
          "item" => "warrior"
        })

        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [garrison] =
          for u <- Fixtures.player_units(context.world, context.other_user), u.type == :warrior, do: u

        _garrison =
          if garrison.tile_id == context.other_city.tile_id do
            garrison
          else
            march_to(context.other_play_live, context.world, context.other_user, garrison, context.other_city.tile_id)
          end

        my_lord = march_to(context.play_live, context.world, context.user, my_lord, context.other_city.tile_id)

        attempt_event(context.play_live, "resolve_garrison_fate", %{
          "city_id" => to_string(context.other_city.id),
          "choice" => "execute"
        })

        {:ok,
         context
         |> Map.put(:my_lord, my_lord)
         |> Map.put(:broken_city, broken_city)}
      end

      given_ "the same vassal's Oath Strain is high", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        for _ <- 1..7 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        units_before = Fixtures.player_units(context.world, context.other_user)

        {:ok, Map.put(context, :units_before, units_before)}
      end

      given_ "the lord has just fallen", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.my_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.my_lord.tile_id))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)
        Fixtures.set_unit_hp(context.world, context.my_lord.id, 1)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, context.my_lord.id)

        {:ok, context}
      end

      when_ "the vassal chooses Declare Independence from the seize-the-moment prompt", context do
        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "their occupied cities rise according to the fallen lord's Honor and tribute record",
            context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        render_hook(fresh_vassal_live, "select_city", %{"city_id" => to_string(context.other_city.id)})

        refute has_element?(fresh_vassal_live, "[data-test='city-status']", "occupied"),
               "the city should no longer read occupied once it rises to a low-Honor lord"

        refute has_element?(fresh_vassal_live, "[data-test='vassal-status']"),
               "declaring independence should sever the Vassalage — no vassal-status badge should remain"

        {:ok, context}
      end

      then_ "a temporary rebellion army sized by their Oath Strain spawns to fight the war", context do
        units_after = Fixtures.player_units(context.world, context.other_user)

        assert length(units_after) > length(context.units_before),
               "declaring independence with high Oath Strain against a low-Honor lord should rally a temporary rebellion army — unit count should have grown"

        {:ok, context}
      end
    end
  end
end
