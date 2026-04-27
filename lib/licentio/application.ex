defmodule Licentio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Licentio.Cache.Store.init_tables()

    children = [
      LicentioWeb.Telemetry,
      Licentio.Repo,
      {DNSCluster, query: Application.get_env(:licentio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Licentio.PubSub},
      {Registry, keys: :unique, name: Licentio.TenantRegistry},
      Licentio.Cache.TenantSupervisor,
      LicentioWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Licentio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LicentioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
