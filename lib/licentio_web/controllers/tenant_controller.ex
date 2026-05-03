defmodule LicentioWeb.TenantController do
  use LicentioWeb, :controller

  alias Licentio.Tenants
  alias LicentioWeb.Controllers.Helpers

  def create(conn, params) do
    Helpers.respond(conn, Tenants.create_tenant(params), &serialize/1)
  end

  def show(conn, %{"id" => id}) do
    case Tenants.get_tenant(id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "Tenant not found"})
      tenant -> json(conn, serialize(tenant))
    end
  end

  defp serialize(tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      code: tenant.code,
      is_active: tenant.is_active,
      metadata: tenant.metadata,
      inserted_at: tenant.inserted_at
    }
  end
end
