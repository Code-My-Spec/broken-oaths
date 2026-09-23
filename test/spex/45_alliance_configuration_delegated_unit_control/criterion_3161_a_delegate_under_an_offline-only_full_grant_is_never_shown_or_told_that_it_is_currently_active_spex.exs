defmodule BrokenOathsSpex.Story947.Criterion3161Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 3161 — a delegate acting under an offline-only Full grant
  is never shown or told that it is currently active: no banner,
  indicator, or notification of any kind (PM decision, 2026-09-09;
  consistent with the existing no-order-feed/no-undo trust model this
  story's own DECISIONS section already establishes). Proven here by
  performing a genuinely successful steward action — proof the grant
  IS active — and asserting the ally's own view carries no `steward-
  active`-shaped indicator anywhere, the natural counterpart to the
  `steward-error` indicator criterion 3150 already proves exists for
  the refused case.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a delegate under an offline-only Full grant is never shown or told that it is currently active",
    fail_on_error_logs: false do
    scenario "a successful steward action leaves no active-grant indicator in the ally's own view" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally and real banked gold offline", context do
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

        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the ally genuinely stewards my offline bank", context do
        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the grant was genuinely active, yet the ally is shown no indicator that it is", context do
        assert Fixtures.bank_status(context.world, context.user).gold == 0

        refute has_element?(context.ally_live, "[data-test='steward-active']")
        {:ok, context}
      end
    end
  end
end
