defmodule BrokenOathsSpex.Story947.Criterion3151Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 3151 — an always-on Full grant
  (`BrokenOaths.Feudal.Stewardship.set_delegated_control/5` with
  `mode: :always_on`) is presence-independent by definition: the
  delegate may act EVEN WHILE the owner is online, unlike every other
  grant (default/no-grant, offline-only Full, Defensive-only), which
  all still require the owner to be offline.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an always-on Full grant lets the delegate act even while the owner is online",
    fail_on_error_logs: false do
    scenario "the ally queues production in my city while I am still connected" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I have a city, an accepted ally, and an always-on Full grant for that ally",
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
        render_hook(owner_live, "set_allow_steward_production", %{"allowed" => "true"})

        render_hook(owner_live, "set_delegated_control", %{
          "delegate_user_id" => to_string(context.other_user.id),
          "level" => "full",
          "mode" => "always_on"
        })

        [my_city] = Fixtures.player_cities(context.world, context.user)

        # Deliberately NOT calling `go_offline/1` here — the whole point
        # of this criterion is that the owner stays connected and the
        # always-on grant works anyway.
        context
        |> Map.put(:owner_live, owner_live)
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_city, my_city)
        |> then(&{:ok, &1})
      end

      when_ "the ally queues production while I am still online", context do
        assert Phoenix.LiveViewTest.render(context.owner_live)

        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => to_string(context.my_city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the steward's production order landed despite me being online the whole time",
            context do
        refute has_element?(context.ally_live, "[data-test='steward-error']")

        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.my_city.id,
              do: c

        assert Enum.any?(city_now.queue, &(&1.type == :warrior))
        {:ok, context}
      end
    end
  end
end
