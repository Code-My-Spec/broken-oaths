defmodule BrokenOathsSpex.Story39.Criterion3642Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3642 — Fortify is rejected when `:defend` is not in the
  unit's actions catalog, and the stance is left unchanged.

  The Galley (story 921) is the only player-commandable type whose
  `BrokenOaths.Units.Actions.available/1` omits `:defend` — see that
  module's own moduledoc, "Vocabulary": V1 naval scope deliberately
  gives it none of a land unit's Fortify stance. Placed via
  `Fixtures.spawn_unit/4` (the sanctioned direct-placement bridge for a
  real, additional player-owned unit) on the player's own city tile, so
  no ocean-tile search is needed — `BrokenOaths.Units.Unit.fortify/3`'s
  own `:defend not in Actions.available(unit)` gate is a pure type
  check with no terrain dependency, so where the Galley sits is
  irrelevant to what this criterion tests.

  Confirmed first, as an anchor, that the real UnitPanel never even
  offers the Fortify button for this unit (`unit_panel.ex`'s own
  `:if={:defend in @actions and @fortified_turns == 0}` gate) — the
  rejection this criterion asserts is the same rule the UI already
  hides behind, not a second, independent check.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fortify is rejected when :defend is not in the unit's actions" do
    scenario "the player attempts to fortify a Galley" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player controls a Galley, which has no Fortify affordance", context do
        {:ok, player} = Fixtures.join_world(context.world, context.user)
        galley = Fixtures.spawn_unit(context.world, player.id, :galley, context.city.tile_id)

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(galley.id)})

        refute has_element?(context.play_live, "[data-test='fortify']")
        refute has_element?(context.play_live, "[data-test='unit-fortified']")

        {:ok, Map.put(context, :galley, galley)}
      end

      when_ "the player attempts to fortify it anyway", context do
        render_hook(context.play_live, "fortify", %{"unit_id" => to_string(context.galley.id)})
        {:ok, context}
      end

      then_ "the command is rejected with the real combat-error message", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='combat-error']",
                 "That unit can't fortify."
               )

        {:ok, context}
      end

      then_ "the unit's stance is unchanged — still not fortified", context do
        refute has_element?(context.play_live, "[data-test='unit-fortified']")

        [galley] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.galley.id,
              do: u

        assert Map.get(galley, :fortified_turns, 0) == 0
        {:ok, context}
      end
    end
  end
end
