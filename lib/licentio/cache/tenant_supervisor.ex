defmodule Licentio.Cache.TenantSupervisor do
  @moduledoc """
  Supervises one TenantServer per active tenant.
  Starts all active tenants on boot, and allows starting
  new tenants dynamically at runtime.
  """

  use DynamicSupervisor

  alias Licentio.Cache.TenantServer
  alias Licentio.Tenants

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a TenantServer for a tenant if not already running."
  def ensure_started(tenant_id) do
    case DynamicSupervisor.start_child(__MODULE__, {TenantServer, tenant_id}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
