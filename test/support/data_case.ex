defmodule BrokenOathsTest.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use BrokenOathsTest.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias BrokenOaths.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import BrokenOathsTest.DataCase
    end
  end

  setup tags do
    BrokenOathsTest.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    ensure_manual_mode_once()

    pid = Sandbox.start_owner!(BrokenOaths.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  # `mix test` gets `Sandbox.mode(Repo, :manual)` for free from
  # `test/test_helper.exs`, but `mix spex` (the `sexy_spex` dep's own Mix
  # task) never requires that file — it boots ExUnit itself and calls
  # straight into `ExUnit.run/0`. Without setting it somewhere, the pool
  # sits in Sandbox's own `:auto` default forever.
  #
  # This USED to call `Sandbox.mode/2` unconditionally on every test's
  # setup, on the theory that it's already `:manual` under `mix test` so
  # the call is a harmless no-op. That's only true in isolation —
  # `Sandbox.mode/2` sets the pool's mode GLOBALLY, and `async: false`
  # tests rely on `:shared` mode staying in effect for their ENTIRE test
  # (their own `start_owner!(shared: true)` call below sets it). An
  # `async: true` test running concurrently anywhere in the suite that
  # also called this unconditionally would flip the pool back to
  # `:manual` mid-flight — breaking any process spawned by the
  # `async: false` test (a `WorldServer`, a LiveView) that relies on
  # `:shared` mode rather than an explicit `allow/3`, exactly the
  # DBConnection.OwnershipError `world_server_test.exs` hit. Setting this
  # once per BEAM boot, guarded by `:persistent_term`, keeps the
  # `mix spex` fix (the pool needs to be `:manual` at least once before
  # anything checks a connection out) without touching the mode again
  # once a real test run is underway.
  defp ensure_manual_mode_once do
    unless :persistent_term.get({__MODULE__, :manual_mode_set}, false) do
      Sandbox.mode(BrokenOaths.Repo, :manual)
      :persistent_term.put({__MODULE__, :manual_mode_set}, true)
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
