defmodule BrokenOathsSpex.Story947.Criterion3160Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 3160 — when the owner reconnects while a delegate's order
  is mid-execution, the delegate's authority is not cut off mid-order:
  the order finishes, and only then does control revert to the owner
  (PM decision, 2026-09-09). Proven here with a queued production
  order — the same `steward_queue_production` surface criterion 3141/
  3150 already exercise — issued while the owner is offline, with the
  owner reconnecting before that item completes.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the owner reconnecting mid-order lets the delegate's in-flight order finish",
    fail_on_error_logs: false do
    scenario "a production order the ally queued while I was offline still completes after I reconnect" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner is offline, and the ally has queued production for my city", context do
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

        attempt_event(ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => to_string(my_city.id),
          "item" => "warrior"
        })

        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the owner reconnects before that item finishes building", context do
        {:ok, owner_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :owner_live, owner_live)}
      end

      then_ "the ally's in-flight production order still completes, rather than being cancelled by the reconnect",
            context do
        completed? =
          Enum.reduce_while(1..60, false, fn _, _ ->
            Fixtures.advance_turn(context.world)

            if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :warrior)) do
              {:halt, true}
            else
              {:cont, false}
            end
          end)

        assert completed?,
               "the delegate's in-flight production order never completed after the owner reconnected"

        {:ok, context}
      end
    end
  end
end
