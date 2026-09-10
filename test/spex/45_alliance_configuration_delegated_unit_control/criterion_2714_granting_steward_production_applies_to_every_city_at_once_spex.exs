defmodule BrokenOathsSpex.Story947.Criterion2714Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2714 — `"set_allow_steward_production"` (playtest issue
  340c1ad4) is an EMPIRE-WIDE flag on the owner's own `Player` row,
  never scoped by `city_id`
  (`BrokenOaths.Feudal.Stewardship.queue_production/5`'s own
  `ensure_production_allowed/1` gate reads this ONE flag regardless of
  which city a steward targets) — turning it on once covers every city
  the owner has, present or future, not a per-city switch.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "granting steward production applies to every city at once", fail_on_error_logs: false do
    scenario "an eligible offline owner's empire-wide grant lets an ally queue production" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I have a city, an accepted ally, and have granted steward production empire-wide",
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

        [my_city] = Fixtures.player_cities(context.world, context.user)

        go_offline(owner_live)

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_city, my_city)
        |> then(&{:ok, &1})
      end

      when_ "the ally queues production in my city", context do
        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => to_string(context.my_city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the steward's production order actually landed in my city's queue", context do
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
