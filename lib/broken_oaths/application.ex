defmodule BrokenOaths.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BrokenOathsWeb.Telemetry,
      BrokenOaths.Repo,
      {DNSCluster, query: Application.get_env(:broken_oaths, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BrokenOaths.PubSub},
      # Start a worker by calling: BrokenOaths.Worker.start_link(arg)
      # {BrokenOaths.Worker, arg},
      # Start to serve requests, typically the last entry
      BrokenOathsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BrokenOaths.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BrokenOathsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
