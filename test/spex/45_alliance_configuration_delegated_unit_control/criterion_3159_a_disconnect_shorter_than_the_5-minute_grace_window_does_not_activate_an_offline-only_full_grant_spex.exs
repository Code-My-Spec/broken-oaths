defmodule BrokenOathsSpex.Story947.Criterion3159Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 3159 — an offline-only Full grant activates only after the
  owner has been continuously disconnected for 5 minutes (PM decision,
  2026-09-09); a brief disconnect does not flip control. Proven here
  with a REAL city and the production-stewardship flag already granted
  — the only remaining variable is elapsed offline time — so a passing
  order at the instant of disconnect can only mean the grace window
  is not yet being enforced.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a disconnect shorter than the 5-minute grace window does not activate an offline-only Full grant",
    fail_on_error_logs: false do
    scenario "an ally's steward attempt fails the instant after the owner disconnects" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally, real banked production rights, and has just disconnected",
             context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(owner_live, "found_city", %{"unit_id" => to_string(my_settler.id)})
        [my_city] = Fixtures.player_cities(context.world, context.user)

        render_hook(owner_live, "set_allow_steward_production", %{"allowed" => "true"})
        go_offline(owner_live)

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:city_id, my_city.id)
        |> then(&{:ok, &1})
      end

      when_ "the ally immediately tries to steward my production", context do
        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => to_string(context.city_id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the brief disconnect has not activated the offline-only Full grant, and the order is refused",
            context do
        assert has_element?(context.ally_live, "[data-test='steward-error']")
        {:ok, context}
      end
    end
  end
end
