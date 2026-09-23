defmodule BrokenOathsSpex.Story39.Criterion3641Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3641 — Fortify succeeds when `:defend` is in the unit's
  actions catalog, driven from the real UnitPanel affordance rather
  than a bare hook call — the criterion's own wording ("taps Fortify
  on the UnitPanel") is literally a button click, so this one clicks
  the real `[data-test='fortify']` button instead of `render_hook`ing
  the event directly the way the other criteria in this story do.

  A fresh Warrior carries `:defend` in `BrokenOaths.Units.Actions.
  available/1` (every player-commandable combat/civilian type does
  except the Galley — see criterion 3642's moduledoc), so it is a
  legal, unremarkable target for the affordance this criterion checks.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fortify succeeds when :defend is in the unit's actions" do
    scenario "the player taps Fortify on the UnitPanel for a selected warrior" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "my warrior is selected in the UnitPanel, not yet fortified", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})

        refute has_element?(context.play_live, "[data-test='unit-fortified']")
        assert has_element?(context.play_live, "[data-test='fortify']")

        {:ok, Map.put(context, :warrior, warrior)}
      end

      when_ "the player taps the Fortify button", context do
        context.play_live
        |> element("[data-test='fortify']")
        |> render_click()

        {:ok, context}
      end

      then_ "Game.fortify succeeds — no combat error, and the panel shows fortified", context do
        refute has_element?(context.play_live, "[data-test='combat-error']")
        assert has_element?(context.play_live, "[data-test='unit-fortified']")
        refute has_element?(context.play_live, "[data-test='fortify']")
        {:ok, context}
      end

      then_ "the unit's own stance is fortified", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.fortified_turns > 0
        {:ok, context}
      end
    end
  end
end
