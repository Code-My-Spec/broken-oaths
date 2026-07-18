defmodule BrokenOathsSpex.Case do
  @moduledoc """
  Base case for spex (BDD spec) tests.

  Wires up Phoenix.ConnTest for HTTP assertions, Phoenix.LiveViewTest
  for driving LiveViews, the SexySpex DSL (spex/scenario/given_/when_/then_),
  and the DB sandbox.
  """
  use ExUnit.CaseTemplate

  import ExUnit.Assertions, only: [flunk: 1]

  using do
    quote do
      @endpoint BrokenOathsWeb.Endpoint

      use BrokenOathsWeb, :verified_routes
      use SexySpex

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import BrokenOathsSpex.Case
    end
  end

  setup tags do
    BrokenOathsTest.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Waits up to `timeout` ms for an `event` push from `view`, returning
  `{:ok, payload}` if one arrives or `:none` if the mailbox stays
  quiet. Unlike `Phoenix.LiveViewTest.assert_push_event/3,4`, a quiet
  mailbox is not a test failure here: `"game:camps"`/`"game:improvements"`
  are content-diffed against their last-pushed value (QA issue
  dbcbd478) — a turn boundary or action that doesn't change the camp/
  improvement set legitimately produces no push at all, unlike
  `"game:units"`/`"game:cities"`/`"game:window"`, which still push
  unconditionally on every board refresh.
  """
  def maybe_push_event(view, event, timeout \\ 500) do
    %{proxy: {ref, _topic, _}} = view

    receive do
      {^ref, {:push_event, ^event, payload}} -> {:ok, payload}
    after
      timeout -> :none
    end
  end

  @doc """
  Non-blocking flush of every `event` push currently queued in
  `view`'s mailbox. `Phoenix.LiveViewTest.assert_push_event/3,4`
  always matches the OLDEST queued message for its event — so a stale
  push left over from setup (a natural camp spawn during a wait loop,
  another player's own attack, an unrelated `refresh_board/1` call)
  would otherwise be read by a LATER assertion ahead of the fresh push
  the scenario's own action actually produced (QA issue dbcbd478).
  Call this right before the action whose OWN push you need, to
  guarantee the next `assert_push_event` for that event reads
  something produced strictly after this call.
  """
  def drain_events(view, event) do
    %{proxy: {ref, _topic, _}} = view
    do_drain_events(ref, event)
  end

  defp do_drain_events(ref, event) do
    receive do
      {^ref, {:push_event, ^event, _payload}} -> do_drain_events(ref, event)
    after
      0 -> :ok
    end
  end

  @doc """
  Turn-by-turn state tracker for `"game:camps"`: returns the freshest
  `camps` list pushed to `view` within `timeout` ms, or `fallback`
  (the caller's last-known snapshot) if this particular turn/action
  produced no push at all — the correct behavior now that `"game:camps"`
  is content-diffed (QA issue dbcbd478): a quiet turn means the camp
  set genuinely didn't change, so the last-known snapshot is still
  accurate. Used by loops that must survive some iterations pushing
  nothing (a natural-spawn cadence, "wait until X" loops) without
  either hanging on `assert_push_event` or losing track of state.
  """
  def latest_camps(view, fallback) do
    case maybe_push_event(view, "game:camps", 500) do
      {:ok, %{camps: camps}} -> camps
      :none -> fallback
    end
  end

  @doc """
  Reads the DEFINITIVE, final "game:camps" push produced by the
  action a `when_`/`then_` step just performed, coalescing away any
  near-simultaneous duplicate that occasionally arrives immediately
  after the first one for the SAME action (an artifact of the async
  broadcast -> LiveView -> test-process relay under load — a stale,
  pre-mutation snapshot followed within milliseconds by the fresh,
  post-mutation one). `assert_push_event/3,4` always matches the
  OLDEST queued message, so reading only the first push risks the
  stale intermediate value; this blocks up to `timeout` ms for the
  first push, then keeps consuming any FURTHER ones that arrive within
  a short 100ms settle window, returning only the LAST (freshest)
  `camps` list seen. Raises via `flunk/1` if no push arrives at all
  within `timeout` — the caller's action was expected to change the
  camp set.
  """
  def settle_camps(view, timeout \\ 500) do
    case maybe_push_event(view, "game:camps", timeout) do
      {:ok, %{camps: camps}} -> settle_camps_more(view, camps)
      :none -> flunk("expected a \"game:camps\" push within #{timeout}ms, none arrived")
    end
  end

  defp settle_camps_more(view, camps) do
    case maybe_push_event(view, "game:camps", 100) do
      {:ok, %{camps: newer}} -> settle_camps_more(view, newer)
      :none -> camps
    end
  end
end
