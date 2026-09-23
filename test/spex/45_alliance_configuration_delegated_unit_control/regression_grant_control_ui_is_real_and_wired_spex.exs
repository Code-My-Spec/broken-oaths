defmodule BrokenOathsSpex.Story947.GrantControlUiRegressionSpex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Regression guard for issue 8b66ded8 — QA found that no rendered
  template ever fired `"set_delegated_control"`; the only way to
  invoke it was `render_hook`, a raw LiveView test call that bypasses
  rendering entirely, so an owner had no real path to ever grant
  control. Proven here via the real, rendered `[data-test='grant-
  control-ID']` form/`[data-test='set-delegated-control']` button in
  `GameLive.AlliancePanel` — `render_click`/`render_submit` on the
  actual DOM elements, not a hook — and via the grant actually
  persisting (`Game.alliances/2` reflects it back), not just the
  event round-tripping without effect.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOaths.Game

  spex "the owner's real grant-control button actually persists a delegate's control level",
    fail_on_error_logs: false do
    scenario "clicking the rendered form, not render_hook, sets a real ControlGrant" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "we are accepted allies and I have not yet granted any control", context do
        %{play_live_a: owner_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        assert [%{my_grant: %{level: :none}}] = Game.alliances(context.world, context.user)

        {:ok, Map.put(context, :owner_live, owner_live)}
      end

      when_ "I open the real alliance panel and submit the real Set Control form for Full/Always-on",
            context do
        context.owner_live
        |> element("[data-test='alliance-button']")
        |> render_click()

        assert has_element?(
                 context.owner_live,
                 "[data-test='grant-control-#{context.other_user.id}']"
               ),
               "the real grant-control form never rendered for an accepted ally"

        context.owner_live
        |> element("[data-test='grant-control-#{context.other_user.id}']")
        |> render_submit(%{
          "delegate_user_id" => to_string(context.other_user.id),
          "level" => "full",
          "mode" => "always_on"
        })

        {:ok, context}
      end

      then_ "the grant is really persisted — Game.alliances/2 reflects Full/Always-on", context do
        assert [%{my_grant: %{level: :full, mode: :always_on}}] =
                 Game.alliances(context.world, context.user)

        {:ok, context}
      end

      then_ "the panel re-renders with Full/Always-on now pre-selected", context do
        html = render(context.owner_live)

        assert html =~ ~s(<option value="full" selected)
        assert html =~ ~s(<option value="always_on" selected)

        {:ok, context}
      end
    end
  end
end
