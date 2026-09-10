defmodule BrokenOathsSpex.Story947.Criterion2704Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2704 — there is no separate "revoke control" action;
  breaking the alliance itself (`GameLive.AlliancePanel`'s real
  `"break_alliance"` event, `BrokenOaths.Diplomacy.break_alliance/3`)
  is what ends steward eligibility — `BrokenOaths.Feudal.Stewardship.
  steward_role/4` immediately resolves `:none` once the `Alliance` row
  is gone, so the ex-ally's very next steward attempt is refused.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a revoked ally's next order is refused", fail_on_error_logs: false do
    scenario "the owner breaks the alliance and the ex-ally's next steward attempt is refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally who can currently steward while offline", context do
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
        banked0 = Fixtures.bank_status(context.world, context.user).gold
        assert banked0 > 0

        attempt_event(ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        assert Fixtures.bank_status(context.world, context.user).gold == 0,
               "setup's own steward sweep never actually worked while allied"

        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the owner comes back online to break the alliance, then goes offline again", context do
        {:ok, owner_live, _html} = live(context.conn, "/play/#{context.world.id}")

        owner_live
        |> element("[data-test='alliance-button']")
        |> render_click()

        owner_live
        |> element("[data-test='break-alliance']")
        |> render_click()

        go_offline(owner_live)

        Fixtures.advance_turn(context.world)
        banked1 = Fixtures.bank_status(context.world, context.user).gold
        assert banked1 > 0

        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, Map.put(context, :banked1, banked1)}
      end

      then_ "the ex-ally's next order is refused — the newly banked gold was never swept", context do
        assert Fixtures.bank_status(context.world, context.user).gold == context.banked1
        {:ok, context}
      end

      then_ "the ex-ally is shown they aren't eligible any more", context do
        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        assert has_element?(context.ally_live, "[data-test='steward-error']", "eligible")
        {:ok, context}
      end
    end
  end
end
