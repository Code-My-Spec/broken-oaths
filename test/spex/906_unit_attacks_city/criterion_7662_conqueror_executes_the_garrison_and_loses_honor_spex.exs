defmodule BrokenOathsSpex.Story906.Criterion7662Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7662 — the harsh branch of `criterion_7661`'s own choice:
  the conqueror puts a captured garrison to the sword instead of
  releasing it — "putting them to the sword costs Honor"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-4 final
  foundation mechanics"). This is `criterion_7661`'s own sibling —
  same setup, opposite `"choice"`, opposite observable outcome for the
  garrison.

  See `criterion_7657`'s own moduledoc for the shared `city-status`
  badge/`grind_city/6` judgment calls, and `criterion_7661`'s own
  moduledoc for: the `"resolve_garrison_fate"` event judgment call, why
  Honor itself has no observable surface in this batch (so this spec,
  like its sibling, asserts only the observable execute outcome — the
  garrison is gone — not a specific Honor number), and why the setup
  grinds the city down WHILE undefended before adding a last-stand
  garrison (avoids the besieger dying to real counter-fire from a live
  garrisoned defender, an unrelated attrition outcome).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a conqueror executes the garrison and loses Honor", fail_on_error_logs: false do
    scenario "executing a captured garrison removes it from the board" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a broken rival city gets a last-stand garrison, and I've walked in", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        broken_city =
          grind_city(
            context.play_live,
            context.world,
            my_lord,
            context.other_user,
            context.other_city
          )

        render_hook(context.other_play_live, "queue_production", %{
          "city_id" => to_string(context.other_city.id),
          "item" => "warrior"
        })

        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [garrison] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        garrison =
          if garrison.tile_id == context.other_city.tile_id do
            garrison
          else
            march_to(
              context.other_play_live,
              context.world,
              context.other_user,
              garrison,
              context.other_city.tile_id
            )
          end

        assert garrison.tile_id == context.other_city.tile_id

        my_lord =
          march_to(
            context.play_live,
            context.world,
            context.user,
            my_lord,
            context.other_city.tile_id
          )

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:garrison, garrison)
        |> Map.put(:broken_city, broken_city)
        |> then(&{:ok, &1})
      end

      when_ "I choose to execute the fallen garrison", context do
        attempt_event(context.play_live, "resolve_garrison_fate", %{
          "city_id" => to_string(context.other_city.id),
          "choice" => "execute"
        })

        {:ok, context}
      end

      then_ "my unit actually holds the city's own tile and the city reads occupied", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        {:ok, context}
      end

      then_ "the executed garrison is gone", context do
        survivors =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.garrison.id,
              do: u

        assert survivors == []
        {:ok, context}
      end
    end
  end
end
