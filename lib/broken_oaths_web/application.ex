defmodule BrokenOathsWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BrokenOathsWeb.Telemetry,
        BrokenOaths.Repo,
        # Cloak vault for encrypted OAuth token columns — without it
        # every Encrypted.Binary write raises Ecto.ChangeError.
        BrokenOaths.Vault,
        {DNSCluster, query: Application.get_env(:broken_oaths, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BrokenOaths.PubSub},
        # One WorldServer per active game world, lazily started and
        # addressed by world id (see BrokenOaths.Game.WorldServer).
        {Registry, keys: :unique, name: BrokenOaths.GameRegistry},
        {DynamicSupervisor, name: BrokenOaths.GameSupervisor, strategy: :one_for_one},
        # Per-(world, player) online tracking (see BrokenOaths.Players.Presence):
        # a `:duplicate` registry so a player connected in several tabs still
        # registers once per LiveView pid, each entry auto-removed by the
        # Registry's own monitor the instant that connection's process dies —
        # no explicit "disconnect" bookkeeping needed.
        {Registry, keys: :duplicate, name: BrokenOaths.PresenceRegistry},
        # Owns the :oauth_state_store ETS table the OAuth connect flow
        # writes to — without it every /integrations/oauth/* request
        # crashes on a missing table.
        BrokenOaths.Integrations.OAuthStateStore,
        # Per-user CodeMySpec support-widget connections (chat + report
        # a problem), one Slipstream client per logged-in user.
        {Registry, keys: :unique, name: BrokenOaths.CodeMySpec.WidgetRegistry},
        {DynamicSupervisor, strategy: :one_for_one, name: BrokenOaths.CodeMySpec.WidgetSupervisor},
        # Start to serve requests, typically the last entry
        BrokenOathsWeb.Endpoint
      ] ++ globe_warmup()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BrokenOaths.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Pre-build the default globe mesh so the first world mount doesn't pay
  # the ~250ms build. Disabled in test (tests use small frequencies).
  defp globe_warmup do
    if Application.get_env(:broken_oaths, :globe_warmup, true) do
      [
        Supervisor.child_spec(
          {Task,
           fn ->
             BrokenOaths.Worlds.Globe.get(54)
             BrokenOaths.Worlds.Facets.get(54)
             BrokenOaths.Worlds.Texture.warm(54)
           end},
          id: :globe_warmup,
          restart: :temporary
        )
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BrokenOathsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
