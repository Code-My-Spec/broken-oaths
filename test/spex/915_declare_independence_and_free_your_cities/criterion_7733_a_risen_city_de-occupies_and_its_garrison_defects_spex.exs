defmodule BrokenOathsSpex.Story915.Criterion7733Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7733 — "A city that rises has its occupation removed, its
  garrison defects to the returning owner, and the owner controls it
  again" (story 915's own gherkin). This is the per-city AFTERMATH of a
  rise, distinct from `criterion_7732`'s own preview and
  `criterion_7734`'s own multi-city/army-size subject.

  ## Judgment call: reaching "Mira's low Honor" for real

  Same substitution as `criterion_7732`'s own moduledoc: Honor has no
  numeric UI surface anywhere in this codebase, so this spec drives the
  one real, already-shipped dishonorable act
  (`BrokenOathsSpex.SharedGivens.lord_executes_a_throwaway_garrison/1`)
  against a THROWAWAY third player, never Wes.

  ## Judgment call: what "the lord's garrison stationed there" is

  Occupation in this codebase is a simple flag
  (`BrokenOaths.Game.Siege`'s own `occupied_by_player_id`) set once at
  capture — it does NOT require the capturing unit to keep standing on
  the tile afterward (nothing un-occupies a city if the besieger later
  walks away). "The lord's garrison stationed there" is therefore
  operationalized here as whichever of the lord's own units is
  literally still standing on that city's own tile at the moment
  independence is declared — in this single-city scenario, that is
  Mira's own capturing Lord unit itself, deliberately left in place
  (marched back onto Wes's captured city as this given's own final
  step, after being marched away to execute the throwaway garrison
  elsewhere) rather than moved on to garrison duty by a second unit —
  the simplest real setup that gives this criterion an actual "lord's
  unit standing on the risen city" to observe defecting.

  ## Observing "defects" through the sanctioned board-state read

  `Fixtures.player_units/2` is already the established, sanctioned
  read for board-state assertions (`BrokenOathsSpex.Story906.
  Criterion7662Spex`'s own "the executed garrison is gone" check, among
  others) — this spec reads it for BOTH Mira and Wes to prove the same
  unit id moved from one player's own roster to the other's, at the
  same tile. This is a read through the same bridge every other 906-913
  spec already uses, not a new schema read.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a risen city de-occupies and its garrison defects", fail_on_error_logs: false do
    scenario "the uprising resolves: the city reads free again, and the lord's own stationed unit is now the rebel's" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes is captured and becomes Mira's vassal, her army still standing on his city",
             context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "Mira has since executed a captured garrison elsewhere, denting her Honor, taxes Wes heavily, and her army returns to garrison his city",
             context do
        context = lord_executes_a_throwaway_garrison(context)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "80"
        })

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        my_lord =
          march_to(context.play_live, context.world, context.user, my_lord, context.other_city.tile_id)

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "the uprising resolves", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        attempt_event(context.other_play_live, "confirm_declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "that city's occupied status is removed and Wes controls it fully again", context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        render_hook(fresh_vassal_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        refute has_element?(fresh_vassal_live, "[data-test='city-status']"),
               "a fully-owned, unoccupied city renders no city-status badge at all"

        assert has_element?(fresh_vassal_live, "[data-test='city-size']"),
               "the risen city should still render fine as Wes's own"

        {:ok, context}
      end

      then_ "the lord's garrison stationed there defects to Wes", context do
        still_mira_owned =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.my_lord.id,
              do: u

        assert still_mira_owned == [],
               "Mira's own occupying unit should no longer be hers once the city it stood on rose"

        defected =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.my_lord.id,
              do: u

        assert [%{tile_id: tile_id}] = defected,
               "the defecting unit should now belong to Wes"

        assert tile_id == context.other_city.tile_id

        {:ok, context}
      end
    end
  end
end
