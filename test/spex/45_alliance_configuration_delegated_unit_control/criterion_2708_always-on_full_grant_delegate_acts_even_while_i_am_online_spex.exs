defmodule BrokenOathsSpex.Story947.Criterion2708Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2708 — there is no "always-on" tier that lets a delegate
  act while the owner is online (criterion 2707 proves the owner-online
  gate is unconditional for everyone) — what an accepted alliance
  actually gives is a DURABLE relationship, not a one-time or
  single-session token: the same ally is eligible again every time the
  owner goes back offline, not just the first time. Proven by cycling
  offline -> steward succeeds -> online -> steward refused -> offline
  again -> steward succeeds again.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an always-on Full grant lets the delegate act even while the owner is online",
    fail_on_error_logs: false do
    scenario "the ally's steward eligibility returns every time the owner goes back offline" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally and real banked gold while offline", context do
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

        go_offline(owner_live)

        Fixtures.advance_turn(context.world)
        assert Fixtures.bank_status(context.world, context.user).gold > 0

        attempt_event(ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        assert Fixtures.bank_status(context.world, context.user).gold == 0,
               "setup's own first sweep never actually worked"

        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the owner comes online (steward refused), then goes offline again (steward works again)",
            context do
        {:ok, owner_live, _html} = live(context.conn, "/play/#{context.world.id}")

        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        assert has_element?(context.ally_live, "[data-test='steward-error']", "online")

        go_offline(owner_live)

        Fixtures.advance_turn(context.world)
        banked1 = Fixtures.bank_status(context.world, context.user).gold
        assert banked1 > 0
        treasury1 = Fixtures.gold(context.world, context.user)

        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context |> Map.put(:banked1, banked1) |> Map.put(:treasury1, treasury1)}
      end

      then_ "the same, unchanged alliance let the ally steward me again once I was offline again",
            context do
        assert Fixtures.gold(context.world, context.user) ==
                 context.treasury1 + context.banked1

        {:ok, context}
      end
    end
  end
end
