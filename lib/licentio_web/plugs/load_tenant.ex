defmodule LicentioWeb.Plugs.LoadTenant do
  @moduledoc """
  Reads tenant_id from URL params and assigns the tenant to the conn.
  Also ensures the TenantServer is running for this tenant.

  Skipped for routes that don't have a tenant_id param (e.g. POST /tenants).
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Licentio.Tenants
  alias Licentio.Cache.TenantSupervisor

  def init(opts), do: opts

  def call(%{params: %{"tenant_id" => tenant_id}} = conn, _opts) do
    case Tenants.get_tenant(tenant_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tenant not found"})
        |> halt()

      tenant ->
        TenantSupervisor.ensure_started(tenant.id)
        assign(conn, :tenant, tenant)
    end
  end

  def call(conn, _opts), do: conn
end
