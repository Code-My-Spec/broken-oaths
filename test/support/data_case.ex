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
    # `mix test` gets this for free from `test/test_helper.exs`, but
    # `mix spex` (the `sexy_spex` dep's own Mix task) never requires
    # that file — it boots ExUnit itself and calls straight into
    # `ExUnit.run/0`. Without it, `BrokenOaths.Repo`'s sandbox pool
    # sits in `Ecto.Adapters.SQL.Sandbox`'s OWN default, `:auto`, mode
    # forever. That was invisible as long as every spex test used
    # `shared: true` below (private `async: true` specs are new) —
    # `start_owner!/2`'s `shared` branch force-sets `{:shared, self()}`
    # explicitly regardless of the mode coming in, masking the gap.
    # Its `else` (private/`allow`-based) branch has no such override:
    # `allow/3` only does anything useful once the pool is actually in
    # `:manual` mode, so a private-mode spex test silently got each
    # process (test, LiveView, `WorldServer`) its OWN independent
    # auto-checkout instead of sharing the test's one transaction —
    # every cross-process read came back `nil`, no crash, no hint why.
    # Idempotent and already a no-op under `mix test` (already
    # `:manual` by the time this runs), so safe to call unconditionally.
    Ecto.Adapters.SQL.Sandbox.mode(BrokenOaths.Repo, :manual)

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(BrokenOaths.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
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
