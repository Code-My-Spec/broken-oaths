defmodule BrokenOathsSpex.Story947.Criterion2715Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2715 — the converse of criterion 2714: without the owner's
  own empire-wide `allow_steward_production` grant (default `false`,
  playtest issue 340c1ad4), an otherwise-eligible steward's production
  order is refused — `:steward_production_disabled`, checked before
  `city_id` is ever resolved, so it covers every city equally.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "without steward production permission a steward cannot set production in any city",
    fail_on_error_logs: false do
    scenario "an eligible ally's production order is refused with no empire-wide grant" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I have a city and an accepted ally, but have not granted steward production",
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

        go_offline(owner_live)

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_city, my_city)
        |> then(&{:ok, &1})
      end

      when_ "the ally tries to queue production in my city", context do
        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => to_string(context.my_city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the production change is refused, my city's queue stays empty", context do
        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.my_city.id,
              do: c

        assert city_now.queue == []
        {:ok, context}
      end

      then_ "the ally is told I haven't allowed steward production", context do
        assert has_element?(context.ally_live, "[data-test='steward-error']", "production")
        {:ok, context}
      end
    end
  end
end
