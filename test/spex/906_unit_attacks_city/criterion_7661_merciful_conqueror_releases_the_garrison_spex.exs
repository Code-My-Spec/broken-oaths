defmodule BrokenOathsSpex.Story906.Criterion7661Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7661 — capturing a GARRISONED city presents the conqueror a
  choice for the fallen defenders: "the conqueror chooses — execute the
  defenders or let them flee — and the choice carries a small Honor
  consequence (mercy is the honorable option...)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-4 final
  foundation mechanics"). This criterion is the merciful branch:
  releasing the garrison lets it survive.

  See `criterion_7657`'s own moduledoc for the shared `city-status`
  badge/`grind_city/6` judgment calls this criterion builds on.

  ## This criterion's own new judgment calls

  1. **A "fallen" garrison stops blocking entry, but isn't dead yet.**
     Today, `Turn.attempt_step/2`'s `blocked?/5` refuses ANY step onto
     a tile with living occupants (the entering-own-garrison exception
     only applies to the MOVER'S OWN city) — so a besieger literally
     cannot walk onto a still-garrisoned tile at all right now, broken
     city or not. `BrokenOaths.Combat.Siege`'s own job is to lift that
     refusal once the CITY itself (not the garrisoned unit's own HP,
     which `Game.CityDefense.resolve_attack/4` never touches) has
     broken — the garrison is defeated/surrendered along with the
     walls, "fallen" and no longer defending, but its ultimate fate
     (survive vs. destroyed) stays open until the conqueror decides.
     This spec's own RED signal for that lifted refusal is the
     besieger's unit failing to actually reach the city's own tile.
  2. **The fate choice is a new event.** No UI/event exists yet. This
     spec's judgment call: `"resolve_garrison_fate"` with
     `%{"city_id" => ..., "choice" => "release" | "execute"}`, sent by
     the conqueror once they've walked onto the broken city's tile —
     driven through `attempt_event/3` since no `handle_event/3` clause
     exists for it yet (mirrors every other not-yet-implemented event
     this codebase's own specs already guard the same way, e.g.
     `criterion_7533`'s `attempt_attack/3`).
  3. **Honor has no observable surface in this batch.** Only Levy and
     GoldLog schemas exist yet; no Honor ledger/UI exists anywhere in
     the app for ANY story, so this spec deliberately does not assert
     a specific Honor delta for "release" — only the OBSERVABLE
     survival outcome the criterion's own plain-language title
     promises. Honor's exact numbers are explicitly a later "balancing
     pass" per the design doc, not this criterion's own concern.
  4. **Setup ordering avoids an unrelated combat outcome.**
     `Game.CityDefense.resolve_attack/4` already lands REAL counter
     damage on the besieger from a live garrisoned defender
     (`criterion_7656`'s own subject) — a Warrior's garrison-boosted
     strength (15) actually EXCEEDS a lone Lord's (12), so grinding a
     GARRISONED city down over `grind_city/6`'s many rounds would kill
     the besieger's own Lord from counter-fire alone, an outcome about
     unit-vs-unit attrition this criterion isn't testing at all. This
     spec therefore grinds the city down WHILE undefended first (same
     zero-counter siege `criterion_7659` already covers), and only
     THEN has the defender march a freshly-produced Warrior onto their
     own already-broken city as a last-stand garrison — giving this
     criterion a live "fallen garrison" to decide the fate of without
     smuggling in an unrelated attrition mechanic.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a merciful conqueror releases the garrison", fail_on_error_logs: false do
    scenario "releasing a captured garrison lets it survive" do
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

      when_ "I choose to release the fallen garrison", context do
        attempt_event(context.play_live, "resolve_garrison_fate", %{
          "city_id" => to_string(context.other_city.id),
          "choice" => "release"
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

      then_ "the released garrison survives", context do
        [survivor] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.garrison.id,
              do: u

        assert survivor.hp > 0
        {:ok, context}
      end
    end
  end
end
