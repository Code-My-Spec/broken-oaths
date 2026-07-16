defmodule BrokenOathsSpex.Story896.Criterion7574Spex do
  @moduledoc """
  Story 896 — Lord Leads the Fight
  Criterion 7574 — the lord is visually distinct from every other unit
  type by its crown, both on the board and in the unit panel.

  Two observable surfaces, per the board doctrine (canvas paint itself
  is never asserted — see criterion 7424's moduledoc, story 875):

    * Board sprite — the client already keys each unit's sprite off
      its `type` field (`assets/js/globe_render.js`'s
      `lord: "/images/game/units/lord.png"` entry, distinct from every
      other unit type's sprite path). The pushed `"game:units"`
      payload carrying `type: :lord` for the lord's own entry is the
      server-side fact that drives that distinct sprite selection —
      this spec asserts that fact through the push, the literal
      surface the board doctrine allows for "the board sprite carries
      the crown identity."
    * Unit panel identity — the panel already labels the lord "Lord"
      (criterion 7424, story 875), but that is a plain type label, not
      a crown identity, and pre-dates this story. This spec's judgment
      call (the same kind of call criterion 7540, story 891, made for
      the "game:combat" event shape): a `data-test="unit-crown"`
      marker in the unit panel, present only when the selected unit is
      the lord. The future implementer is free to rename it, but some
      crown-specific marker distinct from the pre-existing type label
      is what "the unit panel carries the crown identity" requires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "you always know the king" do
    scenario "the lord's board sprite and unit panel both carry the crown identity" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my lord stands on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        assert_push_event(play_live, "game:units", %{units: initial_units})
        lord_marker = Enum.find(initial_units, &(&1.type == :lord))

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:lord, lord)
         |> Map.put(:lord_marker, lord_marker)}
      end

      when_ "I select it", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.lord.id)})
        {:ok, context}
      end

      then_ "its board sprite and unit panel both carry the crown identity", context do
        assert context.lord_marker != nil
        assert context.lord_marker.type == :lord

        assert has_element?(context.play_live, "[data-test='unit-type']", "Lord")
        assert has_element?(context.play_live, "[data-test='unit-crown']")

        {:ok, context}
      end
    end
  end
end
